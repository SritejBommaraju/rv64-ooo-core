// Header-only golden model for the LSQ, mirroring rtl/lsq/lsq.sv semantics.
// Keeps a program-order trace (circular LQ/SQ windows keyed by rob_idx) plus the TB's own byte
// memory, and answers "what should this load return" independently of DUT scheduling: the
// architecturally correct value is the latest older non-squashed store that fully covers the
// load's bytes, else the memory image.
#pragma once
#include <cstdint>
#include <vector>

template <int LQ_DEPTH, int SQ_DEPTH, int ROB_IDX_W>
class LsqModel {
public:
    struct LqEntry {
        int rob_idx = 0;
        bool addr_v = false;
        uint64_t addr = 0;
        int size = 0;
        bool sgn = false;
    };
    struct SqEntry {
        int rob_idx = 0;
        bool addr_v = false;
        uint64_t addr = 0;
        int size = 0;
        uint64_t data = 0;
    };
    struct DispReq {
        bool valid = false;
        bool is_load = false;
        int rob_idx = 0;
    };
    struct StoreCommitInfo {
        bool valid = false;
        uint64_t addr = 0;
        int size = 0;
        uint64_t data = 0;
    };

    LsqModel() : lq_(LQ_DEPTH), sq_(SQ_DEPTH) {}

    static int bytesOf(int size) { return 1 << size; }

    static uint64_t extend(uint64_t raw, int size, bool sgn) {
        switch (size) {
            case 0: return sgn ? (uint64_t)(int64_t)(int8_t)raw  : (raw & 0xffULL);
            case 1: return sgn ? (uint64_t)(int64_t)(int16_t)raw : (raw & 0xffffULL);
            case 2: return sgn ? (uint64_t)(int64_t)(int32_t)raw : (raw & 0xffffffffULL);
            default: return raw;
        }
    }

    static uint32_t age(int idx, int head) {
        return (uint32_t)(idx - head) & ((1u << ROB_IDX_W) - 1);
    }

    int lqCount() const { return lq_cnt_; }
    int sqCount() const { return sq_cnt_; }

    // ---- dispatch: pure peek (matches disp_ready/disp_lq_idx/disp_sq_idx combinational outputs) ----
    // squash_this_cycle: dispatch is held off entirely on a squash cycle (matches RTL - a same-cycle
    // squash changes the tail out from under the pre-squash disp_lq_idx/disp_sq_idx computation).
    void peekDispatch(const DispReq req[2], bool ready_out[2], int idx_out[2], bool squash_this_cycle = false) const {
        int lq_free = LQ_DEPTH - lq_cnt_;
        int sq_free = SQ_DEPTH - sq_cnt_;
        bool p0_ready = !squash_this_cycle && (req[0].is_load ? (lq_free > 0) : (sq_free > 0));
        bool p0_lq = req[0].valid && p0_ready && req[0].is_load;
        bool p0_sq = req[0].valid && p0_ready && !req[0].is_load;
        int lq_free1 = lq_free - (p0_lq ? 1 : 0);
        int sq_free1 = sq_free - (p0_sq ? 1 : 0);
        bool p1_ready = !squash_this_cycle && (req[1].is_load ? (lq_free1 > 0) : (sq_free1 > 0));
        ready_out[0] = p0_ready;
        ready_out[1] = p1_ready;
        idx_out[0] = req[0].is_load ? lq_tail_ : sq_tail_;
        idx_out[1] = req[1].is_load ? (p0_lq ? (lq_tail_ + 1) % LQ_DEPTH : lq_tail_)
                                     : (p0_sq ? (sq_tail_ + 1) % SQ_DEPTH : sq_tail_);
    }

    // ---- store commit peek: what dmem_wr_* should be this cycle, before popping ----
    StoreCommitInfo peekStoreCommit(bool commit_store_valid) const {
        StoreCommitInfo r;
        r.valid = commit_store_valid && sq_cnt_ != 0;
        if (sq_cnt_ != 0) {
            const SqEntry& e = sq_[sq_head_];
            r.addr = e.addr;
            r.size = e.size;
            r.data = e.data;
        }
        return r;
    }

    int lqRobIdx(int i) const { return lq_[i].rob_idx; }
    int sqRobIdx(int i) const { return sq_[i].rob_idx; }

    // ---- expected value for a load currently resolving (DUT asserted ld_resp_valid for lq_idx) ----
    uint64_t expectedLoadValue(int lq_idx, int rob_head, const uint8_t* mem, bool* used_forward = nullptr) const {
        const LqEntry& L = lq_[lq_idx];
        uint64_t l_lo = L.addr, l_hi = L.addr + bytesOf(L.size);
        bool any_overlap = false, yv_full = false;
        uint32_t yv_age = 0;
        uint64_t yv_data = 0;
        for (int i = 0; i < sq_cnt_; i++) {
            int sj = (sq_head_ + i) % SQ_DEPTH;
            const SqEntry& S = sq_[sj];
            if (age(S.rob_idx, rob_head) < age(L.rob_idx, rob_head)) {
                uint64_t s_lo = S.addr, s_hi = S.addr + bytesOf(S.size);
                if (!(l_hi <= s_lo || s_hi <= l_lo)) { // overlaps
                    uint32_t a = age(S.rob_idx, rob_head);
                    if (!any_overlap || a > yv_age) {
                        any_overlap = true;
                        yv_age = a;
                        yv_full = (s_lo <= l_lo) && (s_hi >= l_hi);
                        if (yv_full) {
                            int off = (int)(l_lo - s_lo);
                            uint64_t shifted = S.data >> (off * 8);
                            yv_data = extend(shifted, L.size, L.sgn);
                        }
                    }
                }
            }
        }
        if (any_overlap && yv_full) {
            if (used_forward) *used_forward = true;
            return yv_data;
        }
        if (used_forward) *used_forward = false;
        uint64_t raw = 0;
        for (int b = 0; b < bytesOf(L.size); b++) raw |= ((uint64_t)mem[l_lo + b]) << (8 * b);
        return extend(raw, L.size, L.sgn);
    }

    // ---- apply: mutate state for this cycle exactly like the RTL's always_ff (call after checks) ----
    void applyDispatch(const DispReq req[2], const bool ready[2], const int idx[2]) {
        for (int i = 0; i < 2; i++) {
            if (req[i].valid && ready[i]) {
                if (req[i].is_load) {
                    lq_[idx[i]] = LqEntry{req[i].rob_idx, false, 0, 0, false};
                    lq_tail_ = (lq_tail_ + 1) % LQ_DEPTH;
                    lq_cnt_++;
                } else {
                    sq_[idx[i]] = SqEntry{req[i].rob_idx, false, 0, 0, 0};
                    sq_tail_ = (sq_tail_ + 1) % SQ_DEPTH;
                    sq_cnt_++;
                }
            }
        }
    }

    void applyStoreAddr(int sq_idx, uint64_t addr, int size, uint64_t data) {
        sq_[sq_idx].addr_v = true;
        sq_[sq_idx].addr = addr;
        sq_[sq_idx].size = size;
        sq_[sq_idx].data = data;
    }
    void applyLoadAddr(int lq_idx, uint64_t addr, int size, bool sgn) {
        lq_[lq_idx].addr_v = true;
        lq_[lq_idx].addr = addr;
        lq_[lq_idx].size = size;
        lq_[lq_idx].sgn = sgn;
    }

    void applyCommit(bool commit_store_valid, bool commit_load_valid) {
        if (commit_store_valid && sq_cnt_ != 0) {
            sq_head_ = (sq_head_ + 1) % SQ_DEPTH;
            sq_cnt_--;
        }
        if (commit_load_valid && lq_cnt_ != 0) {
            lq_head_ = (lq_head_ + 1) % LQ_DEPTH;
            lq_cnt_--;
        }
    }

    void applySquash(bool squash_valid, int squash_rob_idx, bool squash_all, int rob_head) {
        if (squash_all) {
            lq_head_ = lq_tail_ = lq_cnt_ = 0;
            sq_head_ = sq_tail_ = sq_cnt_ = 0;
            return;
        }
        if (!squash_valid) return;
        int keep = 0;
        for (int i = 0; i < lq_cnt_; i++) {
            int li = (lq_head_ + i) % LQ_DEPTH;
            if (age(lq_[li].rob_idx, rob_head) <= age(squash_rob_idx, rob_head)) keep++;
        }
        lq_cnt_ = keep;
        lq_tail_ = (lq_head_ + keep) % LQ_DEPTH;

        keep = 0;
        for (int i = 0; i < sq_cnt_; i++) {
            int si = (sq_head_ + i) % SQ_DEPTH;
            if (age(sq_[si].rob_idx, rob_head) <= age(squash_rob_idx, rob_head)) keep++;
        }
        sq_cnt_ = keep;
        sq_tail_ = (sq_head_ + keep) % SQ_DEPTH;
    }

private:
    std::vector<LqEntry> lq_;
    std::vector<SqEntry> sq_;
    int lq_head_ = 0, lq_tail_ = 0, lq_cnt_ = 0;
    int sq_head_ = 0, sq_tail_ = 0, sq_cnt_ = 0;
};
