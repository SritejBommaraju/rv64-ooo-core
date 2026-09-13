#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>
#include "Vrob.h"
#include "verilated.h"
#include "rob_model.h"

static constexpr int DEPTH = 32;
static constexpr int WIDTH = 2;
using Model = RobModel<DEPTH, WIDTH>;

static Vrob* dut;
static vluint64_t g_time = 0;

static void tick() {
    dut->clk = 0;
    dut->eval();
    g_time++;
    dut->clk = 1;
    dut->eval();
    g_time++;
}

static void applyRstOnly(bool rst) {
    dut->rst = rst;
    for (int i = 0; i < WIDTH; i++) {
        dut->alloc_valid[i] = 0;
        dut->wb_valid[i] = 0;
    }
}

static void driveAlloc(int slot, const Model::AllocReq& a) {
    dut->alloc_valid[slot] = a.valid;
    dut->alloc_pc[slot] = a.pc;
    dut->alloc_rd_arch[slot] = a.rd_arch;
    dut->alloc_prd[slot] = a.prd;
    dut->alloc_prev_prd[slot] = a.prev_prd;
    dut->alloc_is_branch[slot] = a.is_branch;
    dut->alloc_is_store[slot] = a.is_store;
}

static void driveWb(int slot, const Model::WbReq& w) {
    dut->wb_valid[slot] = w.valid;
    dut->wb_rob_idx[slot] = w.rob_idx;
    dut->wb_exception[slot] = w.exception;
    dut->wb_mispredict[slot] = w.mispredict;
    dut->wb_redirect_pc[slot] = w.redirect_pc;
}

// applies one cycle to both DUT and model, drives inputs already set on dut before call, checks outputs after edge
static bool checkCycle(Model& model, const std::vector<Model::AllocReq>& allocs,
                        const std::vector<Model::WbReq>& wbs, bool rst, long cycle, int seed,
                        std::vector<int>* alloc_idx_out, int* commits_seen,
                        bool* flush_this_cycle_out = nullptr) {
    // capture combinational outputs before the clock edge (alloc_ready, alloc_rob_idx, commit_*, flush_*)
    dut->eval();

    bool exp_flush_valid, exp_flush_full;
    uint64_t exp_flush_pc;
    int exp_flush_branch_idx;
    std::vector<Model::CommitOut> exp_commit;

    bool exp_alloc_ready = model.allocReady();
    std::vector<int> exp_alloc_idx(WIDTH);
    for (int i = 0; i < WIDTH; i++) exp_alloc_idx[i] = model.allocIdx(i);

    model.step(allocs, wbs, rst, exp_commit, exp_flush_valid, exp_flush_full, exp_flush_pc,
               exp_flush_branch_idx);

    if (!rst) {
        if ((bool)dut->alloc_ready != exp_alloc_ready) {
            printf("MISMATCH seed=%d cycle=%ld field=alloc_ready dut=%d exp=%d\n", seed, cycle,
                   dut->alloc_ready, exp_alloc_ready);
            return false;
        }
        for (int i = 0; i < WIDTH; i++) {
            if ((int)dut->alloc_rob_idx[i] != exp_alloc_idx[i]) {
                printf("MISMATCH seed=%d cycle=%ld field=alloc_rob_idx[%d] dut=%d exp=%d\n", seed, cycle, i,
                       dut->alloc_rob_idx[i], exp_alloc_idx[i]);
                return false;
            }
        }
        for (int i = 0; i < WIDTH; i++) {
            bool cv = dut->commit_valid[i];
            if (cv != exp_commit[i].valid) {
                printf("MISMATCH seed=%d cycle=%ld field=commit_valid[%d] dut=%d exp=%d\n", seed, cycle, i,
                       cv, exp_commit[i].valid);
                return false;
            }
            if (cv) {
                if (dut->commit_pc[i] != exp_commit[i].pc ||
                    (int)dut->commit_rd_arch[i] != exp_commit[i].rd_arch ||
                    (int)dut->commit_prd[i] != exp_commit[i].prd ||
                    (int)dut->commit_prev_prd[i] != exp_commit[i].prev_prd ||
                    (bool)dut->commit_is_store[i] != exp_commit[i].is_store) {
                    printf("MISMATCH seed=%d cycle=%ld field=commit_fields[%d]\n", seed, cycle, i);
                    return false;
                }
                (*commits_seen)++;
            }
        }
        if ((bool)dut->flush_valid != exp_flush_valid || (bool)dut->flush_full != exp_flush_full) {
            printf("MISMATCH seed=%d cycle=%ld field=flush_valid/full dut=%d/%d exp=%d/%d\n", seed, cycle,
                   dut->flush_valid, dut->flush_full, exp_flush_valid, exp_flush_full);
            return false;
        }
        if (exp_flush_valid && dut->flush_pc != exp_flush_pc) {
            printf("MISMATCH seed=%d cycle=%ld field=flush_pc dut=%lx exp=%lx\n", seed, cycle,
                   (unsigned long)dut->flush_pc, (unsigned long)exp_flush_pc);
            return false;
        }
        if (exp_flush_valid && !exp_flush_full &&
            (int)dut->flush_branch_rob_idx != exp_flush_branch_idx) {
            printf("MISMATCH seed=%d cycle=%ld field=flush_branch_rob_idx dut=%d exp=%d\n", seed, cycle,
                   dut->flush_branch_rob_idx, exp_flush_branch_idx);
            return false;
        }
    }

    tick();
    dut->eval();

    if ((int)dut->rob_head != model.head() || (int)dut->rob_tail != model.tail() ||
        (int)dut->rob_count != model.count()) {
        printf("MISMATCH seed=%d cycle=%ld field=status dut(h=%d,t=%d,c=%d) exp(h=%d,t=%d,c=%d)\n", seed,
               cycle, dut->rob_head, dut->rob_tail, dut->rob_count, model.head(), model.tail(),
               model.count());
        return false;
    }
    if ((bool)dut->rob_empty != model.empty() || (bool)dut->rob_full != model.full()) {
        printf("MISMATCH seed=%d cycle=%ld field=empty/full dut=%d/%d exp=%d/%d\n", seed, cycle,
               dut->rob_empty, dut->rob_full, model.empty(), model.full());
        return false;
    }

    if (alloc_idx_out) *alloc_idx_out = exp_alloc_idx;
    if (flush_this_cycle_out) *flush_this_cycle_out = exp_flush_valid;
    return true;
}

static Model::AllocReq mkAlloc(bool v, uint64_t pc, uint8_t rd, uint8_t prd, uint8_t prev, bool br, bool st) {
    return {v, pc, rd, prd, prev, br, st};
}
static Model::WbReq mkWb(bool v, int idx, bool exc, bool mis, uint64_t rpc) {
    return {v, idx, exc, mis, rpc};
}

static void doReset(Model& model) {
    applyRstOnly(true);
    std::vector<Model::CommitOut> co;
    bool fv, ff;
    uint64_t fpc;
    int fbi;
    model.step({}, {}, true, co, fv, ff, fpc, fbi);
    tick();
    dut->rst = 0;
    dut->eval();
}

// ------------- directed tests -------------

static bool directedTests() {
    Model model;
    int commits = 0;

    // Test 1: fill to full, check alloc_ready deasserts
    doReset(model);
    for (int i = 0; i < WIDTH; i++) driveAlloc(i, mkAlloc(false, 0, 0, 0, 0, false, false));
    for (int i = 0; i < WIDTH; i++) driveWb(i, mkWb(false, 0, false, false, 0));

    long cyc = 0;
    for (int n = 0; n < DEPTH / WIDTH; n++) {
        std::vector<Model::AllocReq> allocs = {mkAlloc(true, 0x1000 + n, 1, 2, 0, false, false),
                                                mkAlloc(true, 0x1004 + n, 3, 4, 0, false, false)};
        for (int i = 0; i < WIDTH; i++) driveAlloc(i, allocs[i]);
        if (!checkCycle(model, allocs, {}, false, cyc++, 1, nullptr, &commits)) return false;
    }
    dut->eval();
    if (dut->alloc_ready) {
        printf("DIRECTED FAIL: alloc_ready should be low when full\n");
        return false;
    }
    if (!model.full() || !dut->rob_full) {
        printf("DIRECTED FAIL: rob should be full\n");
        return false;
    }

    // Test 2: commit drains in order - writeback everything in order, then commit
    for (int i = 0; i < WIDTH; i++) driveAlloc(i, mkAlloc(false, 0, 0, 0, 0, false, false));
    for (int n = 0; n < DEPTH; n++) {
        std::vector<Model::WbReq> wbs;
        for (int i = 0; i < WIDTH; i++) driveWb(i, mkWb(false, 0, false, false, 0));
        if (n % WIDTH == 0) {
            std::vector<Model::WbReq> w2 = {mkWb(true, n, false, false, 0), mkWb(true, n + 1, false, false, 0)};
            driveWb(0, w2[0]);
            driveWb(1, w2[1]);
            wbs = w2;
        }
        if (!checkCycle(model, {}, wbs, false, cyc++, 1, nullptr, &commits)) return false;
    }
    for (int i = 0; i < WIDTH; i++) driveWb(i, mkWb(false, 0, false, false, 0));
    if (!model.empty() || !dut->rob_empty) {
        printf("DIRECTED FAIL: rob should be empty after full drain\n");
        return false;
    }

    // Test 3: writeback out-of-order then commit stays in order
    doReset(model);
    {
        std::vector<Model::AllocReq> allocs = {mkAlloc(true, 0x2000, 1, 2, 0, false, false),
                                                mkAlloc(true, 0x2004, 3, 4, 0, false, false)};
        for (int i = 0; i < WIDTH; i++) driveAlloc(i, allocs[i]);
        if (!checkCycle(model, allocs, {}, false, cyc++, 1, nullptr, &commits)) return false;
    }
    for (int i = 0; i < WIDTH; i++) driveAlloc(i, mkAlloc(false, 0, 0, 0, 0, false, false));
    // writeback idx 1 first (out of order), idx0 should not commit yet
    {
        std::vector<Model::WbReq> wbs = {mkWb(false, 0, false, false, 0), mkWb(true, 1, false, false, 0)};
        for (int i = 0; i < WIDTH; i++) driveWb(i, wbs[i]);
        if (!checkCycle(model, {}, wbs, false, cyc++, 1, nullptr, &commits)) return false;
    }
    if (dut->commit_valid[0] || dut->commit_valid[1]) {
        printf("DIRECTED FAIL: commit should not fire until head is done\n");
        return false;
    }
    {
        std::vector<Model::WbReq> wbs = {mkWb(true, 0, false, false, 0), mkWb(false, 0, false, false, 0)};
        for (int i = 0; i < WIDTH; i++) driveWb(i, wbs[i]);
        if (!checkCycle(model, {}, wbs, false, cyc++, 1, nullptr, &commits)) return false;
    }

    // Test 4: mispredict squash of younger entries
    doReset(model);
    {
        std::vector<Model::AllocReq> a = {mkAlloc(true, 0x3000, 1, 2, 0, true, false),
                                           mkAlloc(true, 0x3004, 3, 4, 0, false, false)};
        for (int i = 0; i < WIDTH; i++) driveAlloc(i, a[i]);
        std::vector<int> idxs;
        if (!checkCycle(model, a, {}, false, cyc++, 1, &idxs, &commits)) return false;
    }
    {
        std::vector<Model::AllocReq> a = {mkAlloc(true, 0x3008, 5, 6, 0, false, false),
                                           mkAlloc(true, 0x300c, 7, 8, 0, false, false)};
        for (int i = 0; i < WIDTH; i++) driveAlloc(i, a[i]);
        std::vector<int> idxs;
        if (!checkCycle(model, a, {}, false, cyc++, 1, &idxs, &commits)) return false;
    }
    for (int i = 0; i < WIDTH; i++) driveAlloc(i, mkAlloc(false, 0, 0, 0, 0, false, false));
    {
        // mark all 4 done; idx0 is mispredict, redirect to 0x9000
        std::vector<Model::WbReq> wbs = {mkWb(true, 0, false, true, 0x9000), mkWb(true, 1, false, false, 0)};
        for (int i = 0; i < WIDTH; i++) driveWb(i, wbs[i]);
        if (!checkCycle(model, {}, wbs, false, cyc++, 1, nullptr, &commits)) return false;
    }
    {
        std::vector<Model::WbReq> wbs = {mkWb(true, 2, false, false, 0), mkWb(true, 3, false, false, 0)};
        for (int i = 0; i < WIDTH; i++) driveWb(i, wbs[i]);
        if (!checkCycle(model, {}, wbs, false, cyc++, 1, nullptr, &commits)) return false;
    }
    // next cycle idx0 commits with mispredict -> flush_branch, squashing idx1..3
    for (int i = 0; i < WIDTH; i++) driveWb(i, mkWb(false, 0, false, false, 0));
    if (!checkCycle(model, {}, {}, false, cyc++, 1, nullptr, &commits)) return false;
    if (!model.empty() || !dut->rob_empty) {
        printf("DIRECTED FAIL: rob should be empty after mispredict squash\n");
        return false;
    }

    // Test 5: exception full flush
    doReset(model);
    {
        std::vector<Model::AllocReq> a = {mkAlloc(true, 0x4000, 1, 2, 0, false, false),
                                           mkAlloc(true, 0x4004, 3, 4, 0, false, false)};
        for (int i = 0; i < WIDTH; i++) driveAlloc(i, a[i]);
        if (!checkCycle(model, a, {}, false, cyc++, 1, nullptr, &commits)) return false;
    }
    for (int i = 0; i < WIDTH; i++) driveAlloc(i, mkAlloc(false, 0, 0, 0, 0, false, false));
    {
        std::vector<Model::WbReq> wbs = {mkWb(true, 0, true, false, 0xdead), mkWb(true, 1, false, false, 0)};
        for (int i = 0; i < WIDTH; i++) driveWb(i, wbs[i]);
        if (!checkCycle(model, {}, wbs, false, cyc++, 1, nullptr, &commits)) return false;
    }
    for (int i = 0; i < WIDTH; i++) driveWb(i, mkWb(false, 0, false, false, 0));
    // next cycle idx0 commits with exception -> full flush
    if (!checkCycle(model, {}, {}, false, cyc++, 1, nullptr, &commits)) return false;
    if (!model.empty() || !dut->rob_empty) {
        printf("DIRECTED FAIL: rob should be empty after exception full flush\n");
        return false;
    }

    // Test 6: wraparound across DEPTH - alloc/commit repeatedly to wrap head/tail past DEPTH
    doReset(model);
    for (int i = 0; i < WIDTH; i++) driveAlloc(i, mkAlloc(false, 0, 0, 0, 0, false, false));
    for (int round = 0; round < (DEPTH * 2) / WIDTH; round++) {
        std::vector<Model::AllocReq> a = {mkAlloc(true, 0x5000 + round, 1, 2, 0, false, false),
                                           mkAlloc(true, 0x5000 + round, 3, 4, 0, false, false)};
        for (int i = 0; i < WIDTH; i++) driveAlloc(i, a[i]);
        std::vector<int> idxs;
        if (!checkCycle(model, a, {}, false, cyc++, 1, &idxs, &commits)) return false;
        std::vector<Model::WbReq> wbs = {mkWb(true, idxs[0], false, false, 0), mkWb(true, idxs[1], false, false, 0)};
        for (int i = 0; i < WIDTH; i++) driveAlloc(i, mkAlloc(false, 0, 0, 0, 0, false, false));
        for (int i = 0; i < WIDTH; i++) driveWb(i, wbs[i]);
        if (!checkCycle(model, {}, wbs, false, cyc++, 1, nullptr, &commits)) return false;
        for (int i = 0; i < WIDTH; i++) driveWb(i, mkWb(false, 0, false, false, 0));
        if (!checkCycle(model, {}, {}, false, cyc++, 1, nullptr, &commits)) return false;
    }
    if (model.head() == 0 && model.tail() == 0) {
        // wrapped an integer number of times back to 0 - fine, just make sure no mismatch occurred
    }

    printf("DIRECTED PASS\n");
    return true;
}

// ------------- random test -------------

static bool randomTest(int seed, long n_cycles, int* commits_out) {
    Model model;
    doReset(model);
    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> pctDist(0, 99);
    std::uniform_int_distribution<int> prdDist(0, 127);
    std::uniform_int_distribution<int> rdDist(0, 31);
    std::uniform_int_distribution<uint64_t> pcDist(0, ~0ULL);

    std::vector<int> outstanding; // rob indices allocated but not yet written back
    int commits = 0;

    for (long c = 0; c < n_cycles; c++) {
        bool ready_now = model.allocReady();
        std::vector<Model::AllocReq> allocs(WIDTH);
        int n_want = pctDist(rng) % 3; // 0,1,2 roughly uniform via mod3 bias acceptable for stress
        for (int i = 0; i < WIDTH; i++) {
            bool v = ready_now && (i < n_want);
            allocs[i] = mkAlloc(v, pcDist(rng), rdDist(rng), prdDist(rng), prdDist(rng),
                                 pctDist(rng) < 10, pctDist(rng) < 20);
            driveAlloc(i, allocs[i]);
        }

        // pick up to WIDTH random outstanding entries to write back this cycle
        std::vector<Model::WbReq> wbs(WIDTH);
        std::vector<int> chosen;
        for (int i = 0; i < WIDTH && !outstanding.empty(); i++) {
            if (pctDist(rng) < 70) {
                std::uniform_int_distribution<size_t> pick(0, outstanding.size() - 1);
                size_t k = pick(rng);
                int idx = outstanding[k];
                bool already = false;
                for (int c2 : chosen)
                    if (c2 == idx) already = true;
                if (already) continue;
                chosen.push_back(idx);
                outstanding.erase(outstanding.begin() + k);
                bool exc = pctDist(rng) < 2;
                bool mis = !exc && (pctDist(rng) < 5);
                wbs[i] = mkWb(true, idx, exc, mis, pcDist(rng));
            } else {
                wbs[i] = mkWb(false, 0, false, false, 0);
            }
        }
        for (int i = 0; i < WIDTH; i++) driveWb(i, wbs[i]);

        std::vector<int> alloc_idx;
        bool flush_this_cycle = false;
        if (!checkCycle(model, allocs, wbs, false, c, seed, &alloc_idx, &commits, &flush_this_cycle))
            return false;

        // a flush cycle bypasses allocation entirely (see rob.sv), so nothing new actually landed in the ROB
        if (ready_now && !flush_this_cycle) {
            for (int i = 0; i < WIDTH; i++)
                if (allocs[i].valid) outstanding.push_back(alloc_idx[i]);
        }
        // any outstanding entries that got squashed by a flush must be dropped so we don't wb stale indices;
        // simplest correct approach: after a flush, clear outstanding and let allocations repopulate it,
        // since we can't easily tell which indices survived without re-deriving rob state.
        if (flush_this_cycle) outstanding.clear();
    }
    *commits_out = commits;
    return true;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vrob;

    if (!directedTests()) {
        printf("DIRECTED FAIL\n");
        return 1;
    }

    delete dut;

    int total_commits = 0;
    for (int seed = 1; seed <= 10; seed++) {
        dut = new Vrob;
        int commits = 0;
        if (!randomTest(seed, 100000, &commits)) {
            printf("RANDOM FAIL seed=%d\n", seed);
            return 1;
        }
        total_commits += commits;
        delete dut;
    }

    printf("RANDOM PASS seeds=10 cycles=100000 commits=%d\n", total_commits);
    return 0;
}
