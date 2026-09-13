// Golden C++ model of the rename unit: same semantics as free_list.sv +
// rename_map.sv + rename.sv (map vector, free-list deque, checkpoint vectors).
#pragma once
#include <array>
#include <cstdint>
#include <deque>
#include <vector>

static constexpr int NUM_PREGS = 64;
static constexpr int ARCH_REGS = 32;
static constexpr int N_CKPT    = 8;
static constexpr int DEPTH     = NUM_PREGS - ARCH_REGS; // 32

struct RenameInputs {
  bool valid0 = false, valid1 = false;
  int rs1_0 = 0, rs2_0 = 0, rd0 = 0;
  int rs1_1 = 0, rs2_1 = 0, rd1 = 0;
  bool is_branch0 = false, is_branch1 = false;
  bool ckpt_take0 = false, ckpt_take1 = false;

  bool restore_valid = false;
  int restore_ckpt_id = 0;

  bool commit_valid0 = false, commit_valid1 = false;
  int commit_prev_prd0 = 0, commit_prev_prd1 = 0;
  bool commit_ckpt_release0 = false, commit_ckpt_release1 = false;
};

struct RenameOutputs {
  int prs1_0 = 0, prs2_0 = 0, prd0 = 0, prev_prd0 = 0;
  int ckpt_id0 = 0;
  bool rename_ready0 = false;
  int prs1_1 = 0, prs2_1 = 0, prd1 = 0, prev_prd1 = 0;
  int ckpt_id1 = 0;
  bool rename_ready1 = false;
  int free_count = 0;
  int ckpt_free_count = 0;
};

class RenameModel {
 public:
  RenameModel() { reset(); }

  void reset() {
    map_.assign(32, 0);
    for (int i = 0; i < 32; i++) map_[i] = i;
    for (auto &m : ckpt_map_) m.assign(32, 0);

    fl_.assign(DEPTH, 0);
    for (int i = 0; i < DEPTH; i++) fl_[i] = ARCH_REGS + i;
    head_ = 0;
    tail_ = 0;
    count_ = DEPTH;
    ckpt_fl_head_.assign(N_CKPT, 0);

    ckpt_head_ = 0;
    ckpt_count_ = 0;
  }

  RenameOutputs step(const RenameInputs &in) {
    RenameOutputs out;

    bool needs_prd0 = in.valid0 && (in.rd0 != 0);
    bool needs_prd1 = in.valid1 && (in.rd1 != 0);
    bool want_ckpt0 = in.valid0 && in.is_branch0 && in.ckpt_take0;
    bool want_ckpt1 = in.valid1 && in.is_branch1 && in.ckpt_take1;
    int needed_ckpts = (want_ckpt0 ? 1 : 0) + (want_ckpt1 ? 1 : 0);

    bool preg_ok = count_ >= 2;
    int ckpt_free_now = N_CKPT - ckpt_count_;
    bool ckpt_ok = ckpt_free_now >= needed_ckpts;
    bool bundle_ready = preg_ok && ckpt_ok;

    out.rename_ready0 = bundle_ready;
    out.rename_ready1 = bundle_ready;
    out.free_count = count_;
    out.ckpt_free_count = ckpt_free_now;

    bool alloc_en0 = needs_prd0 && bundle_ready;
    bool alloc_en1 = needs_prd1 && bundle_ready;
    bool grant_ckpt0 = want_ckpt0 && bundle_ready && !in.restore_valid;
    bool grant_ckpt1 = want_ckpt1 && bundle_ready && !in.restore_valid;

    // ---- free list alloc (mirrors free_list.sv) ----
    bool do_a0 = alloc_en0 && !in.restore_valid && (count_ >= 1);
    bool do_a1 = alloc_en1 && !in.restore_valid && (count_ >= (do_a0 ? 2 : 1));
    int idx0 = head_;
    int idx1 = (head_ + (do_a0 ? 1 : 0)) % DEPTH;
    int alloc0 = fl_[idx0];
    int alloc1 = fl_[idx1];

    bool do_f0 = in.commit_valid0 && (in.commit_prev_prd0 != 0);
    bool do_f1 = in.commit_valid1 && (in.commit_prev_prd1 != 0);
    int fidx0 = tail_;
    int fidx1 = (tail_ + (do_f0 ? 1 : 0)) % DEPTH;

    int head_after0 = (head_ + (do_a0 ? 1 : 0)) % DEPTH;
    int count_after_frees = count_ + (do_f0 ? 1 : 0) + (do_f1 ? 1 : 0);
    int count_after0 = count_after_frees - (do_a0 ? 1 : 0);
    int head_after1 = (head_after0 + (do_a1 ? 1 : 0)) % DEPTH;
    int count_after1 = count_after0 - (do_a1 ? 1 : 0);

    // ---- rename map (mirrors rename_map.sv) ----
    int raw_prs1_0 = map_[in.rs1_0], raw_prs2_0 = map_[in.rs2_0];
    int raw_prs1_1 = map_[in.rs1_1], raw_prs2_1 = map_[in.rs2_1];
    int raw_old0 = map_[in.rd0], raw_old1 = map_[in.rd1];

    std::vector<int> nxt0 = map_;
    if (alloc_en0 && in.rd0 != 0) nxt0[in.rd0] = alloc0;
    std::vector<int> nxt1 = nxt0;
    if (alloc_en1 && in.rd1 != 0) nxt1[in.rd1] = alloc1;

    // ---- checkpoint-id allocator (mirrors rename.sv) ----
    int release_count = (in.commit_valid0 && in.commit_ckpt_release0 ? 1 : 0) +
                         (in.commit_valid1 && in.commit_ckpt_release1 ? 1 : 0);
    int count_after_release = ckpt_count_ - release_count;
    int ckpt_count_after0 = count_after_release + (grant_ckpt0 ? 1 : 0);
    int ckpt_count_after1 = ckpt_count_after0 + (grant_ckpt1 ? 1 : 0);
    int ckpt_head_after0 = (ckpt_head_ + (grant_ckpt0 ? 1 : 0)) % N_CKPT;
    int ckpt_head_after1 = (ckpt_head_after0 + (grant_ckpt1 ? 1 : 0)) % N_CKPT;

    out.ckpt_id0 = ckpt_head_;
    out.ckpt_id1 = ckpt_head_after0;

    // ---- outputs ----
    out.prs1_0 = raw_prs1_0;
    out.prs2_0 = raw_prs2_0;
    out.prs1_1 = (needs_prd0 && in.rs1_1 == in.rd0) ? alloc0 : raw_prs1_1;
    out.prs2_1 = (needs_prd0 && in.rs2_1 == in.rd0) ? alloc0 : raw_prs2_1;
    out.prd0 = needs_prd0 ? alloc0 : 0;
    out.prd1 = needs_prd1 ? alloc1 : 0;
    out.prev_prd0 = raw_old0;
    bool same_rd_hazard = needs_prd0 && in.valid1 && (in.rd1 == in.rd0);
    out.prev_prd1 = same_rd_hazard ? alloc0 : raw_old1;

    // ---- commit state updates (sequential) ----
    if (do_f0) fl_[fidx0] = in.commit_prev_prd0;
    if (do_f1) fl_[fidx1] = in.commit_prev_prd1;
    tail_ = (tail_ + (do_f0 ? 1 : 0) + (do_f1 ? 1 : 0)) % DEPTH;

    if (in.restore_valid) {
      int undone_allocs = ((head_ - ckpt_fl_head_[in.restore_ckpt_id]) % DEPTH + DEPTH) % DEPTH;
      head_ = ckpt_fl_head_[in.restore_ckpt_id];
      count_ = count_after_frees + undone_allocs;
    } else {
      head_ = head_after1;
      count_ = count_after1;
    }
    if (grant_ckpt0) ckpt_fl_head_[out.ckpt_id0] = head_after0;
    if (grant_ckpt1) ckpt_fl_head_[out.ckpt_id1] = head_after1;

    if (in.restore_valid) {
      map_ = ckpt_map_[in.restore_ckpt_id];
    } else {
      map_ = nxt1;
      if (grant_ckpt0) ckpt_map_[out.ckpt_id0] = nxt0;
      if (grant_ckpt1) ckpt_map_[out.ckpt_id1] = nxt1;
    }

    if (in.restore_valid) {
      int undone_ckpts = ((ckpt_head_ - in.restore_ckpt_id) % N_CKPT + N_CKPT) % N_CKPT;
      ckpt_head_ = in.restore_ckpt_id;
      // ckpt_count_ tracks *outstanding* ids, so undone (discarded) ones subtract
      ckpt_count_ = count_after_release - undone_ckpts;
    } else {
      ckpt_head_ = ckpt_head_after1;
      ckpt_count_ = ckpt_count_after1;
    }

    return out;
  }

  // invariant checks
  const std::vector<int> &map() const { return map_; }
  std::vector<int> free_list_contents() const {
    std::vector<int> v;
    for (int i = 0; i < count_; i++) v.push_back(fl_[(head_ + i) % DEPTH]);
    return v;
  }
  int free_count() const { return count_; }

 private:
  std::vector<int> map_;
  std::array<std::vector<int>, N_CKPT> ckpt_map_;

  std::vector<int> fl_;
  int head_, tail_, count_;
  std::vector<int> ckpt_fl_head_;

  int ckpt_head_, ckpt_count_;
};
