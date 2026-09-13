// Cycle-exact testbench for the rename unit: independent C++ reference model
// checked bit-for-bit against the RTL every cycle, directed + randomized.
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <random>
#include <set>
#include <vector>
#include "Vrename.h"
#include "verilated.h"
#include "rename_model.h"

static Vrename *dut;
static RenameModel model;
static vluint64_t tick = 0;

static void apply(const RenameInputs &in) {
  dut->valid0 = in.valid0;
  dut->rs1_0 = in.rs1_0;
  dut->rs2_0 = in.rs2_0;
  dut->rd0 = in.rd0;
  dut->is_branch0 = in.is_branch0;
  dut->ckpt_take0 = in.ckpt_take0;
  dut->valid1 = in.valid1;
  dut->rs1_1 = in.rs1_1;
  dut->rs2_1 = in.rs2_1;
  dut->rd1 = in.rd1;
  dut->is_branch1 = in.is_branch1;
  dut->ckpt_take1 = in.ckpt_take1;
  dut->restore_valid = in.restore_valid;
  dut->restore_ckpt_id = in.restore_ckpt_id;
  dut->commit_valid0 = in.commit_valid0;
  dut->commit_prev_prd0 = in.commit_prev_prd0;
  dut->commit_ckpt_release0 = in.commit_ckpt_release0;
  dut->commit_valid1 = in.commit_valid1;
  dut->commit_prev_prd1 = in.commit_prev_prd1;
  dut->commit_ckpt_release1 = in.commit_ckpt_release1;
}

// drive one cycle through both DUT and model, compare outputs, return model outputs.
// All rename outputs are pure combinational functions of the current registers and
// this cycle's inputs, so they must be read before the clock edge commits updates.
static RenameOutputs step_and_check(const RenameInputs &in, const char *ctx) {
  apply(in);
  dut->clk = 0;
  dut->eval(); // settle combinational outputs for this cycle
  RenameOutputs mo = model.step(in);

  bool ok = true;
  auto chk = [&](const char *name, int rtl_v, int mdl_v) {
    if (rtl_v != mdl_v) {
      printf("MISMATCH @tick %llu (%s): %s rtl=%d model=%d\n", (unsigned long long)tick, ctx, name, rtl_v, mdl_v);
      ok = false;
    }
  };
  chk("prs1_0", dut->prs1_0, mo.prs1_0);
  chk("prs2_0", dut->prs2_0, mo.prs2_0);
  chk("prd0", dut->prd0, mo.prd0);
  chk("prev_prd0", dut->prev_prd0, mo.prev_prd0);
  chk("ckpt_id0", dut->ckpt_id0, mo.ckpt_id0);
  chk("rename_ready0", dut->rename_ready0, mo.rename_ready0);
  chk("prs1_1", dut->prs1_1, mo.prs1_1);
  chk("prs2_1", dut->prs2_1, mo.prs2_1);
  chk("prd1", dut->prd1, mo.prd1);
  chk("prev_prd1", dut->prev_prd1, mo.prev_prd1);
  chk("ckpt_id1", dut->ckpt_id1, mo.ckpt_id1);
  chk("rename_ready1", dut->rename_ready1, mo.rename_ready1);
  chk("free_count", dut->free_count, mo.free_count);
  chk("ckpt_free_count", dut->ckpt_free_count, mo.ckpt_free_count);

  if (!ok) {
    printf("FAIL at %s\n", ctx);
    exit(1);
  }

  dut->clk = 1;
  dut->eval(); // commit the rising edge
  tick++;
  return mo;
}

static void check_invariants(const char *ctx, const std::set<int> &inflight = {}) {
  // no preg appears twice in free list; no preg both free and mapped;
  // free + mapped(distinct) + in-flight(distinct) == 64, all pairwise disjoint.
  std::vector<int> fl = model.free_list_contents();
  std::set<int> fl_set(fl.begin(), fl.end());
  if (fl_set.size() != fl.size()) {
    printf("INVARIANT FAIL @%s: duplicate preg in free list\n", ctx);
    exit(1);
  }
  std::set<int> mapped(model.map().begin(), model.map().end());
  for (int p : fl) {
    if (mapped.count(p)) {
      printf("INVARIANT FAIL @%s: preg %d both free and mapped\n", ctx, p);
      printf("map:");
      for (int v : model.map()) printf(" %d", v);
      printf("\nfree:");
      for (int v : fl) printf(" %d", v);
      printf("\n");
      exit(1);
    }
  }
  for (int p : inflight) {
    if (fl_set.count(p)) {
      printf("INVARIANT FAIL @%s: preg %d both free and in-flight\n", ctx, p);
      exit(1);
    }
    if (mapped.count(p)) {
      printf("INVARIANT FAIL @%s: preg %d both mapped and in-flight\n", ctx, p);
      exit(1);
    }
  }
  size_t total = fl.size() + mapped.size() + inflight.size();
  if (total != 64) {
    printf("INVARIANT FAIL @%s: free(%zu)+mapped(%zu)+inflight(%zu) = %zu != 64\n", ctx, fl.size(),
           mapped.size(), inflight.size(), total);
    printf("map:");
    for (int v : model.map()) printf(" %d", v);
    printf("\nfree:");
    for (int v : fl) printf(" %d", v);
    printf("\ninflight:");
    for (int v : inflight) printf(" %d", v);
    printf("\n");
    exit(1);
  }
}

static std::set<int> g_inflight;

static void reset_dut() {
  dut->rst = 1;
  apply(RenameInputs{});
  for (int i = 0; i < 3; i++) {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
    tick++;
  }
  dut->rst = 0;
  model.reset();
  g_inflight.clear();
}

// drives one cycle, checks RTL-vs-model, maintains g_inflight (displaced-but-uncommitted
// prds), and checks the free/mapped/in-flight partition invariant.
static RenameOutputs do_cycle(const RenameInputs &in, const char *ctx) {
  RenameOutputs o = step_and_check(in, ctx);
  bool ready = o.rename_ready0; // bundle-atomic
  if (ready) {
    if (in.valid0 && in.rd0 != 0) g_inflight.insert(o.prev_prd0);
    if (in.valid1 && in.rd1 != 0) g_inflight.insert(o.prev_prd1);
  }
  if (in.commit_valid0 && in.commit_prev_prd0 != 0) g_inflight.erase(in.commit_prev_prd0);
  if (in.commit_valid1 && in.commit_prev_prd1 != 0) g_inflight.erase(in.commit_prev_prd1);
  check_invariants(ctx, g_inflight);
  return o;
}

// ---------------- directed tests ----------------
static void directed() {
  reset_dut();

  // x0 handling: rd=0 must not allocate, prd=0, prev_prd=0, no free-list movement
  {
    RenameInputs in;
    in.valid0 = true;
    in.rs1_0 = 1;
    in.rs2_0 = 2;
    in.rd0 = 0;
    RenameOutputs o = do_cycle(in, "x0-noalloc");
    if (o.prd0 != 0 || o.prev_prd0 != 0) {
      printf("x0 handling failed\n");
      exit(1);
    }
  }

  // intra-group RAW hazard: slot1 rs1 == slot0 rd
  {
    RenameInputs in;
    in.valid0 = true;
    in.rd0 = 5;
    in.rs1_0 = 1;
    in.rs2_0 = 2;
    in.valid1 = true;
    in.rd1 = 6;
    in.rs1_1 = 5;
    in.rs2_1 = 3;
    RenameOutputs o = do_cycle(in, "hazard-rs1");
    if (o.prs1_1 != o.prd0) {
      printf("intra-group rs1 forwarding failed\n");
      exit(1);
    }
  }
  {
    RenameInputs in;
    in.valid0 = true;
    in.rd0 = 7;
    in.rs1_0 = 1;
    in.rs2_0 = 2;
    in.valid1 = true;
    in.rd1 = 8;
    in.rs1_1 = 3;
    in.rs2_1 = 7;
    RenameOutputs o = do_cycle(in, "hazard-rs2");
    if (o.prs2_1 != o.prd0) {
      printf("intra-group rs2 forwarding failed\n");
      exit(1);
    }
  }

  // same-rd hazard: map ends at slot1's prd, slot0's prd becomes slot1's prev_prd
  {
    RenameInputs in;
    in.valid0 = true;
    in.rd0 = 9;
    in.rs1_0 = 1;
    in.rs2_0 = 2;
    in.valid1 = true;
    in.rd1 = 9;
    in.rs1_1 = 3;
    in.rs2_1 = 4;
    RenameOutputs o = do_cycle(in, "same-rd");
    if (o.prd0 == o.prd1) {
      printf("same-rd: expected distinct prds\n");
      exit(1);
    }
    if (o.prev_prd1 != o.prd0) {
      printf("same-rd: prev_prd1 should be slot0's prd, got %d want %d\n", o.prev_prd1, o.prd0);
      exit(1);
    }
    if (model.map()[9] != o.prd1) {
      printf("same-rd: map should end at slot1's prd\n");
      exit(1);
    }
  }

  // full free-list backpressure: drain free list with single-dest renames until <2 free
  {
    reset_dut();
    int reg = 1;
    while (true) {
      RenameInputs in;
      in.valid0 = true;
      in.rd0 = (reg % 31) + 1;
      reg++;
      RenameOutputs o = do_cycle(in, "drain");
      if (!o.rename_ready0) {
        if (o.free_count >= 2) {
          printf("backpressure asserted too early, free=%d\n", o.free_count);
          exit(1);
        }
        break;
      }
    }
  }

  // checkpoint exhaustion backpressure: take N_CKPT branches, N_CKPT+1th must stall
  {
    reset_dut();
    for (int i = 0; i < N_CKPT; i++) {
      RenameInputs in;
      in.valid0 = true;
      in.is_branch0 = true;
      in.ckpt_take0 = true;
      in.rd0 = 0;
      RenameOutputs o = do_cycle(in, "ckpt-fill");
      if (!o.rename_ready0) {
        printf("checkpoint fill stalled too early at i=%d\n", i);
        exit(1);
      }
    }
    RenameInputs in;
    in.valid0 = true;
    in.is_branch0 = true;
    in.ckpt_take0 = true;
    RenameOutputs o = do_cycle(in, "ckpt-exhausted");
    if (o.rename_ready0) {
      printf("checkpoint exhaustion should have stalled\n");
      exit(1);
    }
  }

  // take-branch / mispredict / restore then verify map equals model (implicit, since
  // checked every cycle) -- also confirm RTL map contents directly via a probe write path:
  // we assert via prs reads after restore instead of peeking internal arrays.
  {
    reset_dut();
    RenameInputs in;
    in.valid0 = true;
    in.rd0 = 10;
    in.rs1_0 = 1;
    in.rs2_0 = 2;
    in.is_branch0 = true;
    in.ckpt_take0 = true;
    RenameOutputs o = step_and_check(in, "branch-ckpt");
    int saved_id = o.ckpt_id0;
    int saved_p10 = model.map()[10];

    // speculative instruction past the branch, wrongly renames x10 again
    RenameInputs spec;
    spec.valid0 = true;
    spec.rd0 = 10;
    spec.rs1_0 = 1;
    spec.rs2_0 = 2;
    step_and_check(spec, "post-branch-spec");
    if (model.map()[10] == saved_p10) {
      printf("speculative rename should have changed map[10]\n");
      exit(1);
    }

    // mispredict: restore
    RenameInputs restore;
    restore.restore_valid = true;
    restore.restore_ckpt_id = saved_id;
    step_and_check(restore, "restore");
    if (model.map()[10] != saved_p10) {
      printf("restore did not roll back map[10]\n");
      exit(1);
    }

    // subsequent rename should see the restored mapping as a source operand
    RenameInputs after;
    after.valid0 = true;
    after.rd0 = 11;
    after.rs1_0 = 10;
    after.rs2_0 = 2;
    RenameOutputs oa = step_and_check(after, "post-restore");
    if (oa.prs1_0 != saved_p10) {
      printf("post-restore read of x10 wrong: got %d want %d\n", oa.prs1_0, saved_p10);
      exit(1);
    }
  }

  // free-list wraparound: alloc + commit-free repeatedly past DEPTH boundary
  {
    reset_dut();
    std::deque<int> inflight;
    for (int i = 0; i < 200; i++) {
      RenameInputs in;
      in.valid0 = true;
      in.rd0 = (i % 31) + 1;
      RenameOutputs o = do_cycle(in, "wrap-alloc");
      inflight.push_back(o.prev_prd0);
      if (inflight.size() >= 4) {
        RenameInputs c;
        c.commit_valid0 = true;
        c.commit_prev_prd0 = inflight.front();
        inflight.pop_front();
        do_cycle(c, "wrap-commit");
      }
    }
  }

  printf("DIRECTED PASS\n");
}

// ---------------- randomized test ----------------
struct InFlightInstr {
  bool has_dest;
  int prev_prd;
  bool has_ckpt;
  int ckpt_id;
  long seq;
  bool unresolved; // true while has_ckpt and the branch hasn't been restored/released yet
};

static void randomized(int seeds, long cycles_per_seed, long &total_renames, long &total_restores) {
  total_renames = 0;
  total_restores = 0;
  for (int seed = 1; seed <= seeds; seed++) {
    reset_dut();
    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> dist100(0, 99);
    std::uniform_int_distribution<int> reg_dist(0, 31);
    std::uniform_int_distribution<int> nslot_dist(0, 2);

    std::deque<InFlightInstr> rob; // in-order not-yet-committed renamed instrs
    std::set<int> inflight_set; // prev_prd of every rob entry with has_dest
    long seq_counter = 0;
    // branches awaiting resolution, in program order, identified by rob seq (an
    // unresolved branch blocks commit of anything at-or-after it, so it is always
    // reachable in rob when we go to resolve it -- possibly not at the front).
    struct PendingBranch {
      int ckpt_id;
      long seq;
    };
    std::deque<PendingBranch> pending_branches;

    for (long c = 0; c < cycles_per_seed; c++) {
      RenameInputs in;

      // random misprediction resolution in program order, before committing further.
      // A restore cycle drives no new rename (the fetched bundle is being redirected).
      // the checkpointed free-list/ckpt-id state is only reconstructible via a
      // pointer-delta from the live circular buffers, which stays exact only while
      // fewer than DEPTH real allocations/frees have churned through since the
      // checkpoint was taken (matching how a real core bounds branch resolution
      // latency by ROB depth) -- so force-resolve a pending branch before it goes stale.
      bool must_resolve = !pending_branches.empty() && (seq_counter - pending_branches.front().seq) >= (DEPTH / 3);
      bool did_restore = false;
      if (!pending_branches.empty() && (must_resolve || dist100(rng) < 8)) {
        PendingBranch pb = pending_branches.front();
        pending_branches.pop_front();
        bool mispredict = dist100(rng) < 50;
        if (mispredict) {
          in.restore_valid = true;
          in.restore_ckpt_id = pb.ckpt_id;
          // discard rob entries strictly younger than this branch (it survives, now resolved)
          while (!rob.empty() && rob.back().seq > pb.seq) {
            if (rob.back().has_dest) inflight_set.erase(rob.back().prev_prd);
            rob.pop_back();
          }
          // the restore's own head rollback already reclaims this branch's checkpoint
          // id (and every younger one), so its later commit must not release it again
          if (!rob.empty() && rob.back().seq == pb.seq) {
            rob.back().unresolved = false;
            rob.back().has_ckpt = false;
          }
          // discard younger pending branches too (all still in the deque are younger)
          pending_branches.clear();
          did_restore = true;
          total_restores++;
        } else {
          // correct prediction: mark resolved so it (and anything after it) may commit;
          // checkpoint itself is released via commit_ckpt_release when it retires.
          for (auto &ii : rob) {
            if (ii.seq == pb.seq) {
              ii.unresolved = false;
              break;
            }
          }
        }
      }

      bool want0 = false, want1 = false;
      int rd0 = 0, rd1 = 0;
      bool br0 = false, br1 = false;
      if (!did_restore) {
        int nslots = nslot_dist(rng);
        want0 = nslots >= 1;
        want1 = nslots >= 2;
        if (want0) {
          in.valid0 = true;
          in.rs1_0 = reg_dist(rng);
          in.rs2_0 = reg_dist(rng);
          rd0 = (dist100(rng) < 10) ? 0 : reg_dist(rng);
          in.rd0 = rd0;
          br0 = dist100(rng) < 15;
          in.is_branch0 = br0;
          in.ckpt_take0 = br0;
        }
        if (want1) {
          in.valid1 = true;
          in.rs1_1 = reg_dist(rng);
          in.rs2_1 = reg_dist(rng);
          rd1 = (dist100(rng) < 10) ? 0 : reg_dist(rng);
          in.rd1 = rd1;
          br1 = dist100(rng) < 15;
          in.is_branch1 = br1;
          in.ckpt_take1 = br1;
        }
      }

      // random commit (only if not restoring this cycle); blocked at an unresolved
      // branch since a branch cannot retire before it is known correct or mispredicted.
      if (!did_restore) {
        int commit_rate = dist100(rng);
        bool commit0 = !rob.empty() && !rob.front().unresolved && commit_rate < 60;
        if (commit0) {
          InFlightInstr ii = rob.front();
          rob.pop_front();
          if (ii.has_dest) inflight_set.erase(ii.prev_prd);
          in.commit_valid0 = true;
          in.commit_prev_prd0 = ii.has_dest ? ii.prev_prd : 0;
          in.commit_ckpt_release0 = ii.has_ckpt;
        }
        bool commit1 = commit0 && !rob.empty() && !rob.front().unresolved && dist100(rng) < 60;
        if (commit1) {
          InFlightInstr ii = rob.front();
          rob.pop_front();
          if (ii.has_dest) inflight_set.erase(ii.prev_prd);
          in.commit_valid1 = true;
          in.commit_prev_prd1 = ii.has_dest ? ii.prev_prd : 0;
          in.commit_ckpt_release1 = ii.has_ckpt;
        }
      }

      RenameOutputs o = step_and_check(in, "random");
      if (!did_restore) {
        bool rename_happened = o.rename_ready0; // bundle-atomic
        if (rename_happened) {
          if (want0) {
            total_renames++;
            InFlightInstr ii;
            ii.has_dest = (rd0 != 0);
            ii.prev_prd = o.prev_prd0;
            ii.has_ckpt = br0 && want0;
            ii.ckpt_id = o.ckpt_id0;
            ii.seq = seq_counter++;
            ii.unresolved = ii.has_ckpt;
            rob.push_back(ii);
            if (ii.has_dest) inflight_set.insert(ii.prev_prd);
            if (br0) pending_branches.push_back({o.ckpt_id0, ii.seq});
          }
          if (want1) {
            total_renames++;
            InFlightInstr ii;
            ii.has_dest = (rd1 != 0);
            ii.prev_prd = o.prev_prd1;
            ii.has_ckpt = br1 && want1;
            ii.ckpt_id = o.ckpt_id1;
            ii.seq = seq_counter++;
            ii.unresolved = ii.has_ckpt;
            rob.push_back(ii);
            if (ii.has_dest) inflight_set.insert(ii.prev_prd);
            if (br1) pending_branches.push_back({o.ckpt_id1, ii.seq});
          }
        }
      }

      char ctxbuf[64];
      snprintf(ctxbuf, sizeof(ctxbuf), "random seed=%d c=%ld", seed, c);
      check_invariants(ctxbuf, inflight_set);
    }
  }
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  dut = new Vrename;

  directed();

  long total_renames = 0, total_restores = 0;
  randomized(10, 50000, total_renames, total_restores);
  printf("RANDOM PASS seeds=10 cycles=50000 renames=%ld restores=%ld\n", total_renames, total_restores);

  if (total_restores <= 100) {
    printf("insufficient restores exercised: %ld\n", total_restores);
    return 1;
  }

  dut->final();
  delete dut;
  return 0;
}
