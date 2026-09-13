#include <cstdio>
#include <cstdlib>
#include <list>
#include <random>
#include <vector>
#include "Vlsq.h"
#include "verilated.h"
#include "lsq_model.h"

static constexpr int LQD = 8, SQD = 8, ROBW = 5;
using Model = LsqModel<LQD, SQD, ROBW>;

struct Op {
    bool is_load;
    int rob_idx;
    int slot;
    bool addr_set = false;
    long addr_cycle = -1;
    bool resolved = false;
};

static Vlsq* dut;
static Model* model;
static std::vector<uint8_t> mem;
static std::list<Op> prog;
static Op* lq_owner[LQD];
static Op* sq_owner[SQD];
static int next_rob_idx = 0;
static long g_cycle = 0;
static long g_forwards = 0, g_stalls = 0;
struct CommitLogEntry { uint64_t addr; int size; uint64_t data; };
static std::vector<CommitLogEntry> g_commit_log;
static vluint64_t g_time = 0;

static void tick() {
    dut->clk = 0; dut->eval(); g_time++;
    dut->clk = 1; dut->eval(); g_time++;
}

static void resetAll() {
    dut->rst = 1;
    for (int i = 0; i < 2; i++) { dut->disp_valid[i] = 0; dut->disp_is_load[i] = 0; dut->disp_rob_idx[i] = 0; }
    dut->st_addr_valid = 0; dut->ld_addr_valid = 0;
    dut->commit_store_valid = 0; dut->commit_load_valid = 0;
    dut->squash_valid = 0; dut->squash_all = 0;
    dut->rob_head = 0;
    tick();
    dut->rst = 0;
    dut->eval();
    delete model;
    model = new Model();
    mem.assign(8192, 0);
    prog.clear();
    for (int i = 0; i < LQD; i++) lq_owner[i] = nullptr;
    for (int i = 0; i < SQD; i++) sq_owner[i] = nullptr;
    next_rob_idx = 0;
    g_cycle = 0;
    g_commit_log.clear();
}

// replays the recorded commit log into a fresh buffer independently of the live `mem` array
static bool checkFinalMemoryImage(int seed) {
    std::vector<uint8_t> replay(mem.size(), 0);
    for (auto& e : g_commit_log)
        for (int b = 0; b < (1 << e.size); b++) replay[e.addr + b] = (uint8_t)(e.data >> (8 * b));
    if (replay != mem) {
        printf("RANDOM FAIL seed=%d: final memory image mismatch vs replayed commit log\n", seed);
        return false;
    }
    return true;
}

static uint32_t curRobHead() {
    return prog.empty() ? (uint32_t)next_rob_idx : (uint32_t)prog.front().rob_idx;
}

struct CycleInputs {
    bool disp_valid[2] = {false, false};
    bool disp_is_load[2] = {false, false};
    bool st_addr_valid = false; int st_slot = 0; uint64_t st_addr = 0; int st_size = 0; uint64_t st_data = 0;
    bool ld_addr_valid = false; int ld_slot = 0; uint64_t ld_addr = 0; int ld_size = 0; bool ld_signed = false;
    bool commit_store = false, commit_load = false;
    bool squash_valid = false; int squash_rob_idx = 0; bool squash_all = false;
};

struct CycleOutputs {
    bool disp_accept[2] = {false, false};
    int disp_slot[2] = {0, 0};
    bool resp_valid = false;
    int resp_slot = 0;
    uint64_t resp_data = 0;
};

// drives one cycle end-to-end: dut inputs -> eval (+dmem settle) -> checks vs model -> apply mutations -> tick
static bool cycle(const CycleInputs& in, int seed, CycleOutputs* out = nullptr) {
    uint32_t rob_head = curRobHead();

    for (int i = 0; i < 2; i++) {
        dut->disp_valid[i] = in.disp_valid[i];
        dut->disp_is_load[i] = in.disp_is_load[i];
        dut->disp_rob_idx[i] = (next_rob_idx + i) & 31;
    }
    dut->rob_head = rob_head;
    dut->st_addr_valid = in.st_addr_valid;
    dut->st_sq_idx = in.st_slot; dut->st_addr = in.st_addr; dut->st_size = in.st_size; dut->st_data = in.st_data;
    dut->ld_addr_valid = in.ld_addr_valid;
    dut->ld_lq_idx = in.ld_slot; dut->ld_addr = in.ld_addr; dut->ld_size = in.ld_size; dut->ld_signed = in.ld_signed;
    dut->commit_store_valid = in.commit_store;
    dut->commit_load_valid = in.commit_load;
    dut->squash_valid = in.squash_valid;
    dut->squash_rob_idx = in.squash_rob_idx;
    dut->squash_all = in.squash_all;

    dut->eval();
    if (dut->dmem_rd_valid) {
        int nb = 1 << dut->dmem_rd_size;
        uint64_t addr = dut->dmem_rd_addr, v = 0;
        for (int b = 0; b < nb; b++) v |= (uint64_t)mem[addr + b] << (8 * b);
        dut->dmem_rd_data = v;
    } else {
        dut->dmem_rd_data = 0;
    }
    dut->eval();

    // ---- checks ----
    Model::DispReq reqs[2];
    for (int i = 0; i < 2; i++) reqs[i] = {in.disp_valid[i], in.disp_is_load[i], (int)dut->disp_rob_idx[i]};
    bool ready_exp[2]; int idx_exp[2];
    model->peekDispatch(reqs, ready_exp, idx_exp, in.squash_valid || in.squash_all);
    for (int i = 0; i < 2; i++) {
        if ((bool)dut->disp_ready[i] != ready_exp[i]) {
            printf("MISMATCH seed=%d cycle=%ld field=disp_ready[%d] dut=%d exp=%d\n", seed, g_cycle, i,
                   dut->disp_ready[i], ready_exp[i]);
            return false;
        }
        if (reqs[i].valid && ready_exp[i]) {
            int got = reqs[i].is_load ? dut->disp_lq_idx[i] : dut->disp_sq_idx[i];
            if (got != idx_exp[i]) {
                printf("MISMATCH seed=%d cycle=%ld field=disp_idx[%d] dut=%d exp=%d\n", seed, g_cycle, i, got,
                       idx_exp[i]);
                return false;
            }
        }
    }

    if ((int)dut->lq_count != model->lqCount() || (int)dut->sq_count != model->sqCount()) {
        printf("MISMATCH seed=%d cycle=%ld field=count dut=(%d,%d) exp=(%d,%d)\n", seed, g_cycle, dut->lq_count,
               dut->sq_count, model->lqCount(), model->sqCount());
        return false;
    }

    auto sc = model->peekStoreCommit(in.commit_store);
    if ((bool)dut->dmem_wr_valid != sc.valid) {
        printf("MISMATCH seed=%d cycle=%ld field=dmem_wr_valid dut=%d exp=%d\n", seed, g_cycle, dut->dmem_wr_valid,
               sc.valid);
        return false;
    }
    if (sc.valid && (dut->dmem_wr_addr != sc.addr || dut->dmem_wr_size != sc.size || dut->dmem_wr_data != sc.data)) {
        printf("MISMATCH seed=%d cycle=%ld field=dmem_wr_fields dut=(%lx,%d,%lx) exp=(%lx,%d,%lx)\n", seed, g_cycle,
               (unsigned long)dut->dmem_wr_addr, dut->dmem_wr_size, (unsigned long)dut->dmem_wr_data,
               (unsigned long)sc.addr, sc.size, (unsigned long)sc.data);
        return false;
    }

    bool resp_valid = dut->ld_resp_valid;
    if (resp_valid) {
        int slot = dut->ld_resp_lq_idx;
        Op* op = lq_owner[slot];
        if (!op) {
            printf("MISMATCH seed=%d cycle=%ld field=ld_resp orphan slot=%d\n", seed, g_cycle, slot);
            return false;
        }
        if ((uint32_t)dut->ld_resp_rob_idx != (uint32_t)op->rob_idx) {
            printf("MISMATCH seed=%d cycle=%ld field=ld_resp_rob_idx dut=%d exp=%d\n", seed, g_cycle,
                   dut->ld_resp_rob_idx, op->rob_idx);
            return false;
        }
        bool used_fwd = false;
        uint64_t exp = model->expectedLoadValue(slot, rob_head, mem.data(), &used_fwd);
        if (dut->ld_resp_data != exp) {
            printf("MISMATCH seed=%d cycle=%ld field=ld_resp_data slot=%d dut=%lx exp=%lx\n", seed, g_cycle, slot,
                   (unsigned long)dut->ld_resp_data, (unsigned long)exp);
            return false;
        }
        op->resolved = true;
        if (used_fwd) g_forwards++;
        if (op->addr_cycle >= 0 && g_cycle > op->addr_cycle) g_stalls++;
        if (out) { out->resp_valid = true; out->resp_slot = slot; out->resp_data = exp; }
    }

    // ---- apply mutations ----
    bool dut_ready[2] = {(bool)dut->disp_ready[0], (bool)dut->disp_ready[1]};
    int dut_idx[2];
    for (int i = 0; i < 2; i++) dut_idx[i] = reqs[i].is_load ? dut->disp_lq_idx[i] : dut->disp_sq_idx[i];
    model->applyDispatch(reqs, dut_ready, dut_idx);
    int accepted = 0;
    for (int i = 0; i < 2; i++) {
        if (reqs[i].valid && dut_ready[i]) {
            prog.push_back(Op{reqs[i].is_load, reqs[i].rob_idx, dut_idx[i]});
            Op* p = &prog.back();
            if (reqs[i].is_load) lq_owner[dut_idx[i]] = p; else sq_owner[dut_idx[i]] = p;
            accepted++;
            if (out) { out->disp_accept[i] = true; out->disp_slot[i] = dut_idx[i]; }
        }
    }
    next_rob_idx = (next_rob_idx + accepted) & 31;

    if (in.st_addr_valid) {
        model->applyStoreAddr(in.st_slot, in.st_addr, in.st_size, in.st_data);
        Op* p = sq_owner[in.st_slot];
        if (p) p->addr_set = true;
    }
    if (in.ld_addr_valid) {
        model->applyLoadAddr(in.ld_slot, in.ld_addr, in.ld_size, in.ld_signed);
        Op* p = lq_owner[in.ld_slot];
        if (p) { p->addr_set = true; p->addr_cycle = g_cycle; }
    }

    if (sc.valid) {
        for (int b = 0; b < (1 << sc.size); b++) mem[sc.addr + b] = (uint8_t)(sc.data >> (8 * b));
        g_commit_log.push_back({sc.addr, sc.size, sc.data});
    }
    model->applyCommit(in.commit_store, in.commit_load);
    if (in.commit_store) {
        if (prog.empty() || prog.front().is_load) { printf("TB BUG: commit_store with no store at head\n"); return false; }
        sq_owner[prog.front().slot] = nullptr;
        prog.pop_front();
    }
    if (in.commit_load) {
        if (prog.empty() || !prog.front().is_load) { printf("TB BUG: commit_load with no load at head\n"); return false; }
        lq_owner[prog.front().slot] = nullptr;
        prog.pop_front();
    }

    if (in.squash_all) {
        model->applySquash(false, 0, true, rob_head);
        prog.clear();
        for (int i = 0; i < LQD; i++) lq_owner[i] = nullptr;
        for (int i = 0; i < SQD; i++) sq_owner[i] = nullptr;
    } else if (in.squash_valid) {
        model->applySquash(true, in.squash_rob_idx, false, rob_head);
        uint32_t b = Model::age(in.squash_rob_idx, rob_head);
        while (!prog.empty()) {
            Op& back = prog.back();
            if (Model::age(back.rob_idx, rob_head) > b) {
                if (back.is_load) lq_owner[back.slot] = nullptr; else sq_owner[back.slot] = nullptr;
                prog.pop_back();
            } else break;
        }
    }

    tick();
    g_cycle++;
    return true;
}

// ------------- directed tests -------------

static bool idleCycle(int seed) { return cycle(CycleInputs{}, seed); }

// dispatch a single op on port0, retrying idle cycles until accepted (queue must have room)
static bool dispatchOne(bool is_load, int* slot_out, int seed) {
    for (int tries = 0; tries < 20; tries++) {
        CycleInputs in;
        in.disp_valid[0] = true;
        in.disp_is_load[0] = is_load;
        CycleOutputs out;
        if (!cycle(in, seed, &out)) return false;
        if (out.disp_accept[0]) { *slot_out = out.disp_slot[0]; return true; }
    }
    printf("DIRECTED FAIL: dispatch never accepted\n");
    return false;
}

static bool sendStoreAddr(int slot, uint64_t addr, int size, uint64_t data, int seed) {
    CycleInputs in;
    in.st_addr_valid = true; in.st_slot = slot; in.st_addr = addr; in.st_size = size; in.st_data = data;
    return cycle(in, seed);
}
// sends the load address pulse, then one idle cycle to let it register - resolution (if any) is
// combinational off the *registered* address, so it can only appear starting the cycle after this pulse.
static bool sendLoadAddr(int slot, uint64_t addr, int size, bool sgn, int seed, CycleOutputs* out = nullptr) {
    CycleInputs in;
    in.ld_addr_valid = true; in.ld_slot = slot; in.ld_addr = addr; in.ld_size = size; in.ld_signed = sgn;
    if (!cycle(in, seed)) return false;
    return cycle(CycleInputs{}, seed, out);
}
static bool commitStore(int seed, CycleOutputs* out = nullptr) {
    CycleInputs in; in.commit_store = true; return cycle(in, seed, out);
}
static bool commitLoad(int seed) {
    CycleInputs in; in.commit_load = true; return cycle(in, seed);
}

static uint64_t extendExp(uint64_t raw, int size, bool sgn) { return Model::extend(raw, size, sgn); }

// forwarding matrix: every (store size, load size, offset) combo that fully covers
static bool testForwardingMatrix(int seed) {
    uint64_t base = 0x1000;
    for (int ss = 0; ss < 4; ss++) {
        int sbytes = 1 << ss;
        for (int ls = 0; ls <= ss; ls++) { // load must be <= store size to be fully coverable
            int lbytes = 1 << ls;
            for (int off = 0; off + lbytes <= sbytes; off += (lbytes > 1 ? lbytes : (sbytes > 1 ? sbytes - 1 : 1))) {
                int store_slot, load_slot;
                if (!dispatchOne(false, &store_slot, seed)) return false;
                if (!dispatchOne(true, &load_slot, seed)) return false;
                uint64_t data = 0x8877665544332211ULL;
                if (!sendStoreAddr(store_slot, base, ss, data, seed)) return false;
                CycleOutputs out;
                bool sgn = (off % 2) == 0;
                if (!sendLoadAddr(load_slot, base + off, ls, sgn, seed, &out)) return false;
                if (!out.resp_valid) {
                    printf("DIRECTED FAIL: forwarding matrix ss=%d ls=%d off=%d did not resolve immediately\n", ss,
                           ls, off);
                    return false;
                }
                uint64_t raw = (data >> (off * 8));
                uint64_t exp = extendExp(raw, ls, sgn);
                if (out.resp_data != exp) {
                    printf("DIRECTED FAIL: forwarding matrix ss=%d ls=%d off=%d got=%lx exp=%lx\n", ss, ls, off,
                           (unsigned long)out.resp_data, (unsigned long)exp);
                    return false;
                }
                if (!commitStore(seed)) return false;
                if (!commitLoad(seed)) return false;
                base += 64;
                if (off + lbytes >= sbytes) break;
            }
        }
    }
    return true;
}

// partial overlap: load must stall until the overlapping older store commits, then drains via dmem
static bool testPartialOverlapStall(int seed) {
    uint64_t base = 0x8000;
    int store_slot, load_slot;
    if (!dispatchOne(false, &store_slot, seed)) return false;
    if (!dispatchOne(true, &load_slot, seed)) return false;
    // store W at base, load D at base-4: overlaps upper 4 bytes of the load only (partial)
    if (!sendStoreAddr(store_slot, base, 2 /*W*/, 0xaabbccddULL, seed)) return false;
    CycleOutputs out;
    if (!sendLoadAddr(load_slot, base - 4, 3 /*D*/, false, seed, &out)) return false;
    if (out.resp_valid) { printf("DIRECTED FAIL: partial overlap resolved immediately (should stall)\n"); return false; }
    for (int i = 0; i < 5; i++) {
        if (!idleCycle(seed)) return false;
        // resp shouldn't fire while blocked
    }
    if (!commitStore(seed, &out)) return false; // pops the blocking store, unblocking the load next cycle
    bool resolved = false;
    for (int i = 0; i < 5 && !resolved; i++) {
        CycleOutputs o2;
        if (!cycle(CycleInputs{}, seed, &o2)) return false;
        if (o2.resp_valid) resolved = true;
    }
    if (!resolved) { printf("DIRECTED FAIL: partial overlap load never drained after store commit\n"); return false; }
    if (!commitLoad(seed)) return false;
    return true;
}

// older store with unknown address forces the load to wait regardless of overlap
static bool testUnknownAddrStall(int seed) {
    uint64_t base = 0x9000;
    int store_slot, load_slot;
    if (!dispatchOne(false, &store_slot, seed)) return false;
    if (!dispatchOne(true, &load_slot, seed)) return false;
    CycleOutputs out;
    if (!sendLoadAddr(load_slot, base, 2, false, seed, &out)) return false;
    if (out.resp_valid) { printf("DIRECTED FAIL: load resolved despite older unknown-address store\n"); return false; }
    for (int i = 0; i < 4; i++) if (!idleCycle(seed)) return false;
    if (!sendStoreAddr(store_slot, base + 100, 2, 0x11223344ULL, seed)) return false; // non-overlapping, far away
    CycleInputs in;
    CycleOutputs o2;
    if (!cycle(in, seed, &o2)) return false;
    if (!o2.resp_valid) { printf("DIRECTED FAIL: load did not resolve after store address arrived\n"); return false; }
    if (!commitStore(seed)) return false;
    if (!commitLoad(seed)) return false;
    return true;
}

// out-of-order address arrival: two older stores, younger of the two (fully covering) wins
static bool testOutOfOrderAddrArrival(int seed) {
    uint64_t base = 0xa000;
    int s1, s2, ld;
    if (!dispatchOne(false, &s1, seed)) return false;
    if (!dispatchOne(false, &s2, seed)) return false;
    if (!dispatchOne(true, &ld, seed)) return false;
    // send S2 (younger store) address first
    if (!sendStoreAddr(s2, base, 2, 0xdeadbeefULL, seed)) return false;
    CycleOutputs out;
    if (!sendLoadAddr(ld, base, 2, false, seed, &out)) return false;
    if (out.resp_valid) { printf("DIRECTED FAIL: load resolved before S1 address known\n"); return false; }
    // now send S1 (older store), also fully covering, different data - S2 must still win
    if (!sendStoreAddr(s1, base, 2, 0x11112222ULL, seed)) return false;
    CycleInputs in;
    CycleOutputs o2;
    if (!cycle(in, seed, &o2)) return false;
    if (!o2.resp_valid) { printf("DIRECTED FAIL: load never resolved after both stores addressed\n"); return false; }
    if (o2.resp_data != 0xdeadbeefULL) {
        printf("DIRECTED FAIL: out-of-order fwd picked wrong store, got=%lx\n", (unsigned long)o2.resp_data);
        return false;
    }
    if (!commitStore(seed)) return false;
    if (!commitStore(seed)) return false;
    if (!commitLoad(seed)) return false;
    return true;
}

// squash drops younger in-flight entries; a stalled load that gets squashed must never respond
static bool testSquash(int seed) {
    uint64_t base = 0xb000;
    int s1, ld1, s2, ld2;
    if (!dispatchOne(false, &s1, seed)) return false;   // kept (older than squash point)
    if (!sendStoreAddr(s1, base, 2, 0x1ULL, seed)) return false;
    if (!commitStore(seed)) return false; // retire s1 so it's out of the way entirely
    if (!dispatchOne(false, &s2, seed)) return false;   // younger store, address left unknown -> would block ld2
    if (!dispatchOne(true, &ld1, seed)) return false;   // will be squashed
    if (!dispatchOne(true, &ld2, seed)) return false;   // will be squashed, blocked on s2's unknown address
    CycleOutputs out;
    if (!sendLoadAddr(ld2, base, 2, false, seed, &out)) return false;
    if (out.resp_valid) { printf("DIRECTED FAIL: ld2 resolved despite s2 unknown address\n"); return false; }

    // squash everything younger than s2 (drops ld1, ld2, but s2 itself, being the boundary, is kept)
    CycleInputs in;
    in.squash_valid = true; in.squash_rob_idx = -1; // filled below
    // find s2's rob_idx via list scan
    int s2_rob = -1;
    for (auto& op : prog) if (op.slot == s2 && !op.is_load) s2_rob = op.rob_idx;
    in.squash_rob_idx = s2_rob;
    if (!cycle(in, seed)) return false;

    // now send s2's address as something that would have resolved ld2 - must produce no response since ld2 is gone
    if (!sendStoreAddr(s2, base, 2, 0x99ULL, seed)) return false;
    for (int i = 0; i < 3; i++) {
        CycleInputs in2;
        CycleOutputs o2;
        if (!cycle(in2, seed, &o2)) return false;
        if (o2.resp_valid && o2.resp_slot == ld2) {
            printf("DIRECTED FAIL: squashed load ld2 still produced a response\n");
            return false;
        }
    }
    if (model->lqCount() != 0 || model->sqCount() != 1) {
        printf("DIRECTED FAIL: squash left unexpected counts lq=%d sq=%d\n", model->lqCount(), model->sqCount());
        return false;
    }
    if (!commitStore(seed)) return false;
    return true;
}

// wraparound: dispatch/commit past LQ_DEPTH/SQ_DEPTH so head/tail wrap the physical buffer
static bool testWraparound(int seed) {
    uint64_t base = 0xc000;
    for (int n = 0; n < LQD * 3; n++) {
        int st, ld;
        if (!dispatchOne(false, &st, seed)) return false;
        if (!dispatchOne(true, &ld, seed)) return false;
        uint64_t addr = base + (n % 4) * 8;
        uint64_t data = 0x100 + n;
        if (!sendStoreAddr(st, addr, 3, data, seed)) return false;
        CycleOutputs out;
        if (!sendLoadAddr(ld, addr, 3, false, seed, &out)) return false;
        if (!out.resp_valid || out.resp_data != data) {
            printf("DIRECTED FAIL: wraparound iter %d forward mismatch\n", n);
            return false;
        }
        if (!commitStore(seed)) return false;
        if (!commitLoad(seed)) return false;
    }
    return true;
}

static bool directedTests(int seed) {
    resetAll();
    if (!testForwardingMatrix(seed)) return false;
    resetAll();
    if (!testPartialOverlapStall(seed)) return false;
    resetAll();
    if (!testUnknownAddrStall(seed)) return false;
    resetAll();
    if (!testOutOfOrderAddrArrival(seed)) return false;
    resetAll();
    if (!testSquash(seed)) return false;
    resetAll();
    if (!testWraparound(seed)) return false;
    printf("DIRECTED PASS\n");
    return true;
}

// ------------- random test -------------

static bool randomTest(int seed, long n_ops) {
    resetAll();
    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> pct(0, 99);
    std::uniform_int_distribution<int> winOff(0, 55); // keeps addr+8 within the 64B window
    std::uniform_int_distribution<int> sizeDist(0, 3);
    std::uniform_int_distribution<uint64_t> dataDist(0, ~0ULL);
    const uint64_t WIN_BASE = 0x100;

    long attempts = 0;
    long safety = n_ops * 20 + 10000;
    for (long c = 0; c < safety; c++) {
        bool draining = attempts >= n_ops;
        CycleInputs in;

        if (!draining) {
            bool want0 = pct(rng) < 70;
            bool want1 = want0 && pct(rng) < 50;
            if (want0) { in.disp_valid[0] = true; in.disp_is_load[0] = pct(rng) < 50; attempts++; }
            if (want1) { in.disp_valid[1] = true; in.disp_is_load[1] = pct(rng) < 50; attempts++; }
        }

        // pick a store awaiting address
        if (pct(rng) < 60) {
            std::vector<int> cands;
            for (int i = 0; i < SQD; i++) if (sq_owner[i] && !sq_owner[i]->addr_set) cands.push_back(i);
            if (!cands.empty()) {
                int slot = cands[rng() % cands.size()];
                in.st_addr_valid = true; in.st_slot = slot;
                in.st_addr = WIN_BASE + winOff(rng);
                in.st_size = sizeDist(rng);
                in.st_data = dataDist(rng);
            }
        }
        // pick a load awaiting address
        if (pct(rng) < 60) {
            std::vector<int> cands;
            for (int i = 0; i < LQD; i++) if (lq_owner[i] && !lq_owner[i]->addr_set) cands.push_back(i);
            if (!cands.empty()) {
                int slot = cands[rng() % cands.size()];
                in.ld_addr_valid = true; in.ld_slot = slot;
                in.ld_addr = WIN_BASE + winOff(rng);
                in.ld_size = sizeDist(rng);
                in.ld_signed = pct(rng) < 50;
            }
        }
        // commit front of program order if it's ready to retire
        if (!prog.empty() && pct(rng) < 50) {
            Op& f = prog.front();
            if (f.is_load) { if (f.resolved) in.commit_load = true; }
            else { if (f.addr_set) in.commit_store = true; }
        }
        // occasional squash
        if (!prog.empty() && pct(rng) < 5) {
            int n = (int)prog.size();
            int k = rng() % n;
            auto it = prog.begin();
            std::advance(it, k);
            in.squash_valid = true;
            in.squash_rob_idx = it->rob_idx;
        } else if (!prog.empty() && pct(rng) < 1) {
            in.squash_all = true;
        }

        if (!cycle(in, seed)) return false;

        if (draining && prog.empty()) break;
    }
    if (!prog.empty()) {
        printf("RANDOM FAIL seed=%d: did not drain, %zu ops left\n", seed, prog.size());
        return false;
    }
    return checkFinalMemoryImage(seed);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vlsq;
    model = new Model();

    if (!directedTests(1)) {
        printf("DIRECTED FAIL\n");
        return 1;
    }

    const long OPS = 20000;
    for (int seed = 1; seed <= 10; seed++) {
        if (!randomTest(seed, OPS)) {
            printf("RANDOM FAIL seed=%d\n", seed);
            return 1;
        }
    }

    printf("RANDOM PASS seeds=10 ops=%ld forwards=%ld stalls=%ld\n", OPS, g_forwards, g_stalls);

    delete dut;
    delete model;
    return 0;
}
