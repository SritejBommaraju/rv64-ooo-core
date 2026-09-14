// Integration testbench: frontend + branch_tbl + rob + rename + lsq, wired together in
// software (each is a separately-verilated top module; wires are forwarded by this TB
// exactly as real RTL glue would carry them) and driven by the ISS as the execute stage.
//
// Single-issue, in-order dispatch/commit: one instruction fetched, renamed, allocated
// into ROB slot0 and (if a branch) recorded into branch_tbl per cycle; writeback is
// scheduled one cycle later. Simplification: the LSQ receives real squash pulses on
// every mispredict flush but is never dispatched into (no loads/stores in the test
// programs), so its bookkeeping check (lq_count/sq_count == 0) is necessarily trivial -
// see the task report for why.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <queue>
#include <string>
#include <vector>

#include "verilated.h"
#include "Vfrontend.h"
#include "Vbranch_tbl.h"
#include "Vrob.h"
#include "Vrename.h"
#include "Vlsq.h"
#include "../../model/iss.h"
#ifdef TB_DEBUG
#include "Vrename___024root.h"
#endif

static constexpr int ROB_DEPTH = 32;

template <typename T>
static void tick(T* dut) {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
}

struct WbEvent {
    uint32_t rob_idx;
    bool mispredict;
    uint64_t redirect_pc;
    bool is_branch;
    bool taken;
    uint64_t target;
};

// runs one program end-to-end through the wired-together DUTs; returns true on pass
static bool runProgram(const std::string& name, const std::string& bin_path, double min_accuracy) {
    std::ifstream f(bin_path, std::ios::binary);
    if (!f) {
        printf("[%s] failed to open %s\n", name.c_str(), bin_path.c_str());
        return false;
    }
    std::vector<uint8_t> image((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());

    Vfrontend* fe = new Vfrontend;
    Vbranch_tbl* bt = new Vbranch_tbl;
    Vrob* rob = new Vrob;
    Vrename* rn = new Vrename;
    Vlsq* lsq = new Vlsq;

    Iss iss;
    iss.load(image);

    auto imem_read32 = [&](uint64_t addr) -> uint32_t {
        uint64_t a = addr & 0xffff;
        uint32_t w = 0;
        for (int i = 0; i < 4; i++) w |= (uint32_t)image[(a + i) < image.size() ? (a + i) : 0] << (8 * i);
        return w;
    };

    // reset all five DUTs
    fe->rst = 1; bt->rst = 1; rob->rst = 1; rn->rst = 1; lsq->rst = 1;
    fe->stall_fetch = 0; fe->redirect_valid = 0; fe->bp_upd_valid = 0;
    for (int i = 0; i < 2; i++) {
        rob->alloc_valid[i] = 0; rob->wb_valid[i] = 0;
        bt->disp_valid[i] = 0; bt->wb_valid[i] = 0; bt->commit_valid[i] = 0;
        rn->restore_valid = 0;
    }
    lsq->disp_valid[0] = 0; lsq->disp_valid[1] = 0; lsq->squash_valid = 0; lsq->squash_all = 0;
    lsq->commit_store_valid = 0; lsq->commit_load_valid = 0; lsq->st_addr_valid = 0; lsq->ld_addr_valid = 0;
    lsq->rob_head = 0;
    rn->valid0 = 0; rn->valid1 = 0; rn->restore_ckpt_id = 0;
    rn->commit_valid0 = 0; rn->commit_valid1 = 0; rn->commit_ckpt_release0 = 0; rn->commit_ckpt_release1 = 0;
    rn->commit_prev_prd0 = 0; rn->commit_prev_prd1 = 0;
    tick(fe); tick(bt); tick(rob); tick(rn); tick(lsq);
    fe->rst = 0; bt->rst = 0; rob->rst = 0; rn->rst = 0; lsq->rst = 0;
    rob->eval(); rn->eval();

    fe->eval();
    rn->eval();
    const uint32_t init_free_count = rn->free_count;
    const uint32_t init_ckpt_free_count = rn->ckpt_free_count;

    std::map<int, std::vector<WbEvent>> pending_wb; // scheduled 1 cycle after dispatch
    bool wrong_path = false;
    bool halted = false;

    struct Meta { uint64_t pc; bool is_branch; bool correct; };
    std::queue<Meta> expected;
    bool is_wrong_path_at_dispatch[ROB_DEPTH] = {false};

    uint64_t committed = 0, committed_branches = 0, correct_branches = 0;
    const long MAX_CYCLES = 3'000'000;
    long cycle = 0;
    bool fail = false;
    uint64_t recorded_actual_next[ROB_DEPTH] = {0};

    for (; cycle < MAX_CYCLES; cycle++) {
        // ---- 1. read rob's purely-registered-state combinational outputs ----
        rob->eval();
        bool rob_alloc_ready = rob->alloc_ready;
        uint32_t alloc_idx0 = rob->alloc_rob_idx[0];
        bool commit_valid0 = rob->commit_valid[0];
        uint64_t commit_pc0 = rob->commit_pc[0];
        uint32_t commit_prev_prd0 = rob->commit_prev_prd[0];
        bool flush_valid = rob->flush_valid, flush_full = rob->flush_full;
        uint64_t flush_pc = rob->flush_pc;
        uint32_t flush_branch_idx = rob->flush_branch_rob_idx;
        uint32_t rob_head = rob->rob_head;
        bool rob_empty = rob->rob_empty;

        if (halted && rob_empty) break;

        // ---- 2. branch_tbl reads rob's flush/commit ports ----
        bt->rob_flush_valid = flush_valid;
        bt->rob_flush_full = flush_full;
        bt->rob_flush_branch_rob_idx = flush_branch_idx;
        bt->rob_flush_pc = flush_pc;
        bt->commit_valid[0] = commit_valid0; bt->commit_valid[1] = 0;
        bt->commit_pc[0] = commit_pc0;
        bt->rob_head = rob_head;
        bt->eval();
        bool restore_valid = bt->restore_valid;
        uint32_t restore_ckpt_id = bt->restore_ckpt_id;
        bool squash_valid = bt->squash_valid;
        uint32_t squash_rob_idx = bt->squash_rob_idx;
        bool redirect_valid = bt->redirect_valid;
        uint64_t redirect_pc = bt->redirect_pc;
        bool bp_upd_valid0 = bt->bp_upd_valid[0];
        uint64_t bp_upd_pc0 = bt->bp_upd_pc[0];
        bool bp_upd_taken0 = bt->bp_upd_taken[0];
        uint64_t bp_upd_target0 = bt->bp_upd_target[0];
        bool ckpt_rel0 = bt->commit_ckpt_release0;

        // ---- 3. frontend consumes redirect/bp-update, produces this cycle's fetch ----
        fe->redirect_valid = redirect_valid; fe->redirect_pc = redirect_pc;
        fe->bp_upd_valid = bp_upd_valid0; fe->bp_upd_pc = bp_upd_pc0;
        fe->bp_upd_taken = bp_upd_taken0; fe->bp_upd_target = bp_upd_target0;
        fe->stall_fetch = 0;
        fe->eval();
        uint64_t fetch_pc = fe->imem_addr;
        fe->imem_rdata = imem_read32(fetch_pc);
        fe->eval();
        uint32_t fetch_instr = fe->fetch_instr;
        uint64_t pred_npc = fe->fetch_pred_npc;

        uint32_t opcode = fetch_instr & 0x7f;
        uint32_t rd = (fetch_instr >> 7) & 0x1f;
        uint32_t rs1 = (fetch_instr >> 15) & 0x1f;
        uint32_t rs2 = (fetch_instr >> 20) & 0x1f;
        bool is_branch_arch = (opcode == 0x63);
        bool is_jalr = (opcode == 0x67);
        bool is_jal = (opcode == 0x6f);
        bool needs_ckpt = is_branch_arch || is_jalr || is_jal;

        // ---- 4. rename: gate admission on rob readiness before consuming resources ----
        bool valid0_to_rename = !halted && rob_alloc_ready;
        rn->valid0 = valid0_to_rename; rn->rs1_0 = rs1; rn->rs2_0 = rs2; rn->rd0 = rd;
        rn->is_branch0 = needs_ckpt; rn->ckpt_take0 = needs_ckpt;
        rn->valid1 = 0; rn->rs1_1 = 0; rn->rs2_1 = 0; rn->rd1 = 0; rn->is_branch1 = 0; rn->ckpt_take1 = 0;
        rn->restore_valid = restore_valid; rn->restore_ckpt_id = restore_ckpt_id;
        rn->commit_valid0 = commit_valid0; rn->commit_prev_prd0 = commit_prev_prd0;
        rn->commit_ckpt_release0 = ckpt_rel0;
        rn->commit_valid1 = 0; rn->commit_prev_prd1 = 0; rn->commit_ckpt_release1 = 0;
        rn->eval();
        bool rename_ready0 = rn->rename_ready0;
        bool dispatch_ok = valid0_to_rename && rename_ready0;
        uint32_t prd0 = rn->prd0, prev_prd0 = rn->prev_prd0, ckpt_id0 = rn->ckpt_id0;

        // ---- 5. rob alloc + scheduled writeback ----
        rob->alloc_valid[0] = dispatch_ok; rob->alloc_pc[0] = fetch_pc; rob->alloc_rd_arch[0] = rd;
        rob->alloc_prd[0] = prd0; rob->alloc_prev_prd[0] = prev_prd0;
        rob->alloc_is_branch[0] = needs_ckpt; rob->alloc_is_store[0] = 0;
        rob->alloc_valid[1] = 0; rob->alloc_pc[1] = 0; rob->alloc_rd_arch[1] = 0;
        rob->alloc_prd[1] = 0; rob->alloc_prev_prd[1] = 0; rob->alloc_is_branch[1] = 0; rob->alloc_is_store[1] = 0;

        rob->wb_valid[0] = 0; rob->wb_valid[1] = 0;
        bt->wb_valid[0] = 0; bt->wb_valid[1] = 0;
        auto it = pending_wb.find((int)cycle);
        if (it != pending_wb.end()) {
            for (size_t s = 0; s < it->second.size() && s < 2; s++) {
                const WbEvent& e = it->second[s];
                rob->wb_valid[s] = 1; rob->wb_rob_idx[s] = e.rob_idx; rob->wb_exception[s] = 0;
                rob->wb_mispredict[s] = e.mispredict; rob->wb_redirect_pc[s] = e.redirect_pc;
                bt->wb_valid[s] = 1; bt->wb_rob_idx[s] = e.rob_idx; bt->wb_taken[s] = e.taken; bt->wb_target[s] = e.target;
            }
        }

        // ---- 6. branch_tbl dispatch write ----
        bt->disp_valid[0] = dispatch_ok; bt->disp_rob_idx[0] = alloc_idx0;
        bt->disp_is_branch[0] = is_branch_arch; bt->disp_took_ckpt[0] = needs_ckpt;
        bt->disp_ckpt_id[0] = ckpt_id0; bt->disp_pred_npc[0] = pred_npc;
        bt->disp_valid[1] = 0; bt->disp_took_ckpt[1] = 0;

        // ---- 7. lsq: real squash wiring, never dispatched into (see file header) ----
        lsq->squash_valid = squash_valid; lsq->squash_rob_idx = squash_rob_idx; lsq->squash_all = 0;
        lsq->rob_head = rob_head;
        lsq->disp_valid[0] = 0; lsq->disp_valid[1] = 0;
        lsq->commit_store_valid = 0; lsq->commit_load_valid = 0;
        lsq->st_addr_valid = 0; lsq->ld_addr_valid = 0;
        lsq->eval();
        if (lsq->lq_count != 0 || lsq->sq_count != 0) {
            printf("[%s] FAIL: lsq count nonzero at cycle %ld (lq=%d sq=%d)\n", name.c_str(), cycle,
                   lsq->lq_count, lsq->sq_count);
            fail = true; break;
        }

        // ---- 8. finalize frontend stall for this edge ----
        fe->stall_fetch = !dispatch_ok;
        fe->eval();

        // sanity: redirect_pc must equal the recorded actual next-pc for the flushing entry
        if (redirect_valid && recorded_actual_next[flush_branch_idx] != redirect_pc) {
            printf("[%s] FAIL: redirect_pc %llx != recorded actual next %llx (idx=%u) @cycle %ld\n",
                   name.c_str(), (unsigned long long)redirect_pc,
                   (unsigned long long)recorded_actual_next[flush_branch_idx], flush_branch_idx, cycle);
            fail = true; break;
        }

        // ---- 9. execute (ISS) + software bookkeeping for the accepted instruction ----
        if (dispatch_ok) {
            if (!wrong_path) {
                if (iss.pc != fetch_pc) {
                    printf("[%s] FAIL: correct-path fetch_pc %llx != iss.pc %llx @cycle %ld\n", name.c_str(),
                           (unsigned long long)fetch_pc, (unsigned long long)iss.pc, cycle);
                    fail = true; break;
                }
                uint64_t pc_before = iss.pc;
                iss.step();
                uint64_t actual_next = iss.pc;
                bool mispred = (pred_npc != actual_next);
                bool taken = (actual_next != pc_before + 4);
                recorded_actual_next[alloc_idx0] = actual_next;
                pending_wb[(int)cycle + 1].push_back({alloc_idx0, mispred, actual_next, is_branch_arch, taken, actual_next});
                expected.push({pc_before, is_branch_arch, !mispred || !is_branch_arch});
                is_wrong_path_at_dispatch[alloc_idx0] = false;
                if (mispred) wrong_path = true;
                if (iss.x[31] == 1) halted = true;
            } else {
                pending_wb[(int)cycle + 1].push_back({alloc_idx0, false, 0, is_branch_arch, false, 0});
                is_wrong_path_at_dispatch[alloc_idx0] = true;
            }
        }

        // ---- 10. check committed pc against the ISS trace ----
        if (commit_valid0) {
            if (is_wrong_path_at_dispatch[rob_head]) {
                printf("[%s] FAIL: wrong-path entry committed @cycle %ld (rob_idx=%u pc=%llx)\n", name.c_str(),
                       cycle, rob_head, (unsigned long long)commit_pc0);
                fail = true; break;
            }
            if (expected.empty()) {
                printf("[%s] FAIL: commit with no expected pc queued @cycle %ld\n", name.c_str(), cycle);
                fail = true; break;
            }
            Meta m = expected.front(); expected.pop();
            if (m.pc != commit_pc0) {
                printf("[%s] FAIL: commit pc mismatch @cycle %ld dut=%llx exp=%llx\n", name.c_str(), cycle,
                       (unsigned long long)commit_pc0, (unsigned long long)m.pc);
                fail = true; break;
            }
            committed++;
            if (m.is_branch) {
                committed_branches++;
                if (m.correct) correct_branches++;
            }
        }

#ifdef TB_DEBUG
        if (cycle < 400) {
            printf("cyc=%ld fpc=%llx instr=%08x disp=%d idx=%u needs_ckpt=%d ckpt_id=%u rr0=%d rob_ready=%d "
                   "commit_v=%d commit_pc=%llx ckpt_rel=%d ckpt_free=%u free=%u restore=%d flush=%d/%d wp=%d "
                   "alloc_cnt=%u rel_cnt=%u\n",
                   cycle, (unsigned long long)fetch_pc, fetch_instr, dispatch_ok, alloc_idx0, needs_ckpt, ckpt_id0,
                   rename_ready0, rob_alloc_ready, commit_valid0, (unsigned long long)commit_pc0, ckpt_rel0,
                   rn->ckpt_free_count, rn->free_count, restore_valid, flush_valid, flush_full, wrong_path,
                   bt->cnt_ckpt_alloc, bt->cnt_ckpt_release);
            printf("   internal: ckpt_head=%d ckpt_count=%d\n", rn->rootp->rename__DOT__ckpt_head,
                   rn->rootp->rename__DOT__ckpt_count);
        }
#endif
        // ---- 11. wrong_path clears the cycle the redirect (rob flush) actually fires ----
        if (redirect_valid) wrong_path = false;

        // ---- 12. advance the clock on all five DUTs ----
        tick(fe); tick(bt); tick(rob); tick(rn); tick(lsq);
    }

    if (!fail && cycle >= MAX_CYCLES) {
        printf("[%s] FAIL: timed out after %ld cycles\n", name.c_str(), cycle);
        fail = true;
    }

    rn->eval();
    uint32_t final_free = rn->free_count, final_ckpt_free = rn->ckpt_free_count;
    uint32_t leaked_pregs = (final_free < init_free_count) ? (init_free_count - final_free) : 0;
    uint32_t leaked_ckpts = (final_ckpt_free < init_ckpt_free_count) ? (init_ckpt_free_count - final_ckpt_free) : 0;

    double accuracy = committed_branches ? (100.0 * (double)correct_branches / (double)committed_branches) : 100.0;
    uint32_t mispredicts = bt->cnt_mispredicts;

    printf("[%s] cycles=%ld committed=%llu committed_branches=%llu accuracy=%.2f%% "
           "mispredicts=%u leaked_pregs=%u leaked_ckpts=%u lq=%d sq=%d\n",
           name.c_str(), cycle, (unsigned long long)committed, (unsigned long long)committed_branches, accuracy,
           mispredicts, leaked_pregs, leaked_ckpts, lsq->lq_count, lsq->sq_count);

    if (!fail) {
        if (leaked_pregs != 0) { printf("[%s] FAIL: leaked pregs=%u\n", name.c_str(), leaked_pregs); fail = true; }
        if (leaked_ckpts != 0) { printf("[%s] FAIL: leaked ckpts=%u\n", name.c_str(), leaked_ckpts); fail = true; }
        if (lsq->lq_count != 0 || lsq->sq_count != 0) { printf("[%s] FAIL: lsq nonempty at halt\n", name.c_str()); fail = true; }
        if (mispredicts == 0) { printf("[%s] FAIL: recovery never exercised (mispredicts=0)\n", name.c_str()); fail = true; }
        if (accuracy < min_accuracy) {
            printf("[%s] FAIL: accuracy %.2f%% below required %.2f%%\n", name.c_str(), accuracy, min_accuracy);
            fail = true;
        }
    }

    delete fe; delete bt; delete rob; delete rn; delete lsq;
    return !fail;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    bool ok = true;
    ok &= runProgram("branch.s", "../../sw/build/branch.bin", 0.0);
    ok &= runProgram("branches.s", "../../sw/build/branches_arch.bin", 0.0);
    ok &= runProgram("bp_loops.s", "../../sw/build/bp_loops.bin", 85.0);

    printf(ok ? "PASS\n" : "FAIL\n");
    return ok ? 0 : 1;
}
