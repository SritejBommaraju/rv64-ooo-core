// Cycle-exact testbench for bp_bimodal_btb: independent C++ reference model
// checked bit-for-bit against the RTL every cycle, driven by a synthetic trace.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "Vbp_bimodal_btb.h"
#include "verilated.h"

#ifndef PHT_ENTRIES
#define PHT_ENTRIES 1024
#endif
#ifndef BTB_ENTRIES
#define BTB_ENTRIES 64
#endif
#ifndef TAG_BITS
#define TAG_BITS 20
#endif

static unsigned clog2(unsigned n) {
  unsigned r = 0;
  while ((1u << r) < n) r++;
  return r;
}

// Reference model: same widths, index/tag slicing, reset value and update policy as the RTL.
struct RefModel {
  unsigned pht_idx_w, btb_idx_w;
  std::vector<uint8_t> pht;
  std::vector<uint8_t> btb_valid;
  std::vector<uint64_t> btb_tag;
  std::vector<uint64_t> btb_target;

  RefModel() {
    pht_idx_w = clog2(PHT_ENTRIES);
    btb_idx_w = clog2(BTB_ENTRIES);
    pht.assign(PHT_ENTRIES, 1); // 2'b01 weakly not-taken
    btb_valid.assign(BTB_ENTRIES, 0);
    btb_tag.assign(BTB_ENTRIES, 0);
    btb_target.assign(BTB_ENTRIES, 0);
  }

  uint64_t pht_idx(uint64_t pc) const { return (pc >> 2) & ((1ull << pht_idx_w) - 1); }
  uint64_t btb_idx(uint64_t pc) const { return (pc >> 2) & ((1ull << btb_idx_w) - 1); }
  uint64_t tag(uint64_t pc) const {
    return (pc >> (btb_idx_w + 2)) & ((1ull << TAG_BITS) - 1);
  }

  void predict(uint64_t pc, bool &hit, bool &taken, uint64_t &target) const {
    uint64_t bidx = btb_idx(pc);
    hit = btb_valid[bidx] && (btb_tag[bidx] == tag(pc));
    taken = hit && (pht[pht_idx(pc)] & 0x2);
    target = btb_target[bidx];
  }

  void update(uint64_t pc, bool taken, uint64_t target) {
    uint64_t pidx = pht_idx(pc);
    if (taken) {
      if (pht[pidx] != 3) pht[pidx]++;
    } else {
      if (pht[pidx] != 0) pht[pidx]--;
    }
    if (taken) {
      uint64_t bidx = btb_idx(pc);
      btb_valid[bidx] = 1;
      btb_tag[bidx] = tag(pc);
      btb_target[bidx] = target;
    }
  }
};

struct Event {
  uint64_t pc;
  bool taken;
  uint64_t target;
  bool is_loop_stream;
};

static uint32_t lfsr_next(uint32_t &state) {
  // 32-bit Fibonacci LFSR, maximal-length taps (32,22,2,1)
  uint32_t bit = ((state >> 0) ^ (state >> 10) ^ (state >> 30) ^ (state >> 31)) & 1u;
  state = (state >> 1) | (bit << 31);
  return state;
}

static std::vector<Event> build_trace() {
  std::vector<Event> ev;

  // (a) nested-loop pattern: 500 outer iterations, inner backward branch taken 9/10,
  // plus 3 always-taken forward branches at fixed pcs.
  // low 2 bits of (pc>>2) are chosen distinct (0,1,2,3) so these four pcs never
  // alias in PHT/BTB even for the smallest run-small sizes (PHT=16, BTB=4).
  const uint64_t inner_pc = 0x1000;
  const uint64_t inner_target = 0x0F00; // backward
  const uint64_t fwd_pc[3] = {0x1004, 0x1008, 0x100C};
  const uint64_t fwd_target[3] = {0x2100, 0x2110, 0x2120};
  uint32_t loop_lfsr = 0xACE1u;
  for (int outer = 0; outer < 500; outer++) {
    for (int inner = 0; inner < 10; inner++) {
      bool taken = (lfsr_next(loop_lfsr) % 10) != 0; // 9/10 taken, deterministic-ish
      ev.push_back({inner_pc, taken, taken ? inner_target : 0, true});
    }
    for (int f = 0; f < 3; f++) {
      ev.push_back({fwd_pc[f], true, fwd_target[f], true});
    }
  }

  // (b) 32-bit LFSR-driven random stream of branch pcs (aliasing across PHT/BTB), random outcomes.
  uint32_t lfsr = 0xDEADBEEFu;
  size_t rand_count = 200000 - ev.size();
  for (size_t i = 0; i < rand_count; i++) {
    uint32_t r1 = lfsr_next(lfsr);
    uint32_t r2 = lfsr_next(lfsr);
    uint64_t pc = ((uint64_t)(r1 & 0x3FFF) << 2); // small range to force aliasing
    bool taken = (r2 & 1u) != 0;
    uint64_t target = ((uint64_t)r2 << 2) & 0xFFFFF; // arbitrary target
    ev.push_back({pc, taken, taken ? target : 0, false});
  }
  return ev;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Vbp_bimodal_btb *dut = new Vbp_bimodal_btb;
  RefModel ref;

  dut->rst = 1;
  dut->clk = 0;
  dut->upd_valid = 0;
  dut->pred_pc = 0;
  for (int i = 0; i < 4; i++) {
    dut->clk = !dut->clk;
    dut->eval();
  }
  dut->rst = 0;

  std::vector<Event> trace = build_trace();

  uint64_t loop_total = 0, loop_dir_correct = 0, loop_mismatch = 0;
  uint64_t loop_btb_hits = 0, loop_btb_checked = 0;
  uint64_t rand_total = 0, rand_dir_correct = 0, rand_mismatch = 0;
  uint64_t event_idx = 0;

  for (const Event &e : trace) {
    // combinational prediction check
    dut->pred_pc = e.pc;
    dut->eval();

    bool ref_hit, ref_taken;
    uint64_t ref_target;
    ref.predict(e.pc, ref_hit, ref_taken, ref_target);

    bool mismatch = false;
    if ((bool)dut->pred_hit != ref_hit) mismatch = true;
    if ((bool)dut->pred_taken != ref_taken) mismatch = true;
    if (ref_hit && dut->pred_target != ref_target) mismatch = true;
    // spec: pred_taken must be 0 when pred_hit is 0
    if (!dut->pred_hit && dut->pred_taken) mismatch = true;

    if (mismatch) {
      if (e.is_loop_stream) loop_mismatch++;
      else rand_mismatch++;
      fprintf(stderr, "MISMATCH @evt %llu pc=%llx dut(hit=%d,taken=%d,target=%llx) ref(hit=%d,taken=%d,target=%llx)\n",
              (unsigned long long)event_idx, (unsigned long long)e.pc,
              dut->pred_hit, dut->pred_taken, (unsigned long long)dut->pred_target,
              ref_hit, ref_taken, (unsigned long long)ref_target);
    }

    if (e.is_loop_stream) {
      loop_total++;
      if (dut->pred_hit == ref_hit && dut->pred_taken == e.taken) loop_dir_correct++;
      if (event_idx >= 100) {
        loop_btb_checked++;
        if (dut->pred_hit) loop_btb_hits++;
      }
    } else {
      rand_total++;
      if (dut->pred_taken == e.taken) rand_dir_correct++;
    }

    // apply update on posedge
    dut->upd_valid = 1;
    dut->upd_pc = e.pc;
    dut->upd_taken = e.taken;
    dut->upd_target = e.target;
    dut->clk = 1;
    dut->eval();
    dut->clk = 0;
    dut->eval();
    dut->upd_valid = 0;

    ref.update(e.pc, e.taken, e.target);
    event_idx++;
  }

  uint64_t total_mismatch = loop_mismatch + rand_mismatch;
  double loop_dir_acc = 100.0 * (double)loop_dir_correct / (double)loop_total;
  double rand_dir_acc = 100.0 * (double)rand_dir_correct / (double)rand_total;
  double loop_btb_rate = 100.0 * (double)loop_btb_hits / (double)loop_btb_checked;

  printf("=== bp_bimodal_btb testbench summary ===\n");
  printf("total events: %llu (loop=%llu, random=%llu)\n",
         (unsigned long long)(loop_total + rand_total), (unsigned long long)loop_total,
         (unsigned long long)rand_total);
  printf("mismatches: %llu\n", (unsigned long long)total_mismatch);
  printf("loop-stream direction accuracy: %.3f%%\n", loop_dir_acc);
  printf("loop-stream BTB hit rate (post warm-up): %.3f%%\n", loop_btb_rate);
  printf("random-stream direction accuracy: %.3f%%\n", rand_dir_acc);

  bool pass = (total_mismatch == 0) && (loop_dir_acc >= 85.0) && (loop_btb_rate >= 99.0);
  printf("%s\n", pass ? "PASS" : "FAIL");

  delete dut;
  return pass ? 0 : 1;
}
