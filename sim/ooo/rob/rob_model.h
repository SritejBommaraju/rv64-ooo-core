// Header-only golden model for the ROB, mirroring rtl/ooo/rob.sv semantics.
#pragma once
#include <cstdint>
#include <deque>
#include <vector>

template <int DEPTH, int WIDTH>
class RobModel {
public:
    struct Entry {
        bool valid = false;
        bool done = false;
        bool exception = false;
        bool mispredict = false;
        uint64_t pc = 0;
        uint64_t redirect_pc = 0;
        uint8_t rd_arch = 0;
        uint8_t prd = 0;
        uint8_t prev_prd = 0;
        bool is_store = false;
    };

    struct AllocReq {
        bool valid;
        uint64_t pc;
        uint8_t rd_arch, prd, prev_prd;
        bool is_branch, is_store;
    };
    struct WbReq {
        bool valid;
        int rob_idx;
        bool exception, mispredict;
        uint64_t redirect_pc;
    };
    struct CommitOut {
        bool valid;
        uint64_t pc;
        uint8_t rd_arch, prd, prev_prd;
        bool is_store;
    };

    RobModel() : buf_(DEPTH), head_(0), tail_(0), count_(0) {}

    int head() const { return head_; }
    int tail() const { return tail_; }
    int count() const { return count_; }
    bool empty() const { return count_ == 0; }
    bool full() const { return count_ == DEPTH; }

    // returns alloc_ready for this cycle (computed on entry state, before this cycle's mutation)
    bool allocReady() const { return (DEPTH - count_) >= WIDTH; }

    int idxAt(int offset) const { return (head_ + offset) % DEPTH; }

    // one clock edge: applies alloc/wb/commit/flush exactly like the RTL, returns commit outputs and flush info
    void step(const std::vector<AllocReq>& allocs, const std::vector<WbReq>& wbs, bool rst,
              std::vector<CommitOut>& commit_out, bool& flush_valid, bool& flush_full,
              uint64_t& flush_pc, int& flush_branch_idx) {
        commit_out.assign(WIDTH, CommitOut{false, 0, 0, 0, 0, false});
        flush_valid = false;
        flush_full = false;
        flush_pc = 0;
        flush_branch_idx = 0;

        if (rst) {
            buf_.assign(DEPTH, Entry{});
            head_ = tail_ = count_ = 0;
            return;
        }

        bool alloc_ready = allocReady();

        // determine commit eligibility (combinational, based on pre-edge state)
        std::vector<int> head_idx(WIDTH);
        std::vector<bool> can_commit(WIDTH, false);
        for (int i = 0; i < WIDTH; i++) head_idx[i] = idxAt(i);
        can_commit[0] = buf_[head_idx[0]].valid && buf_[head_idx[0]].done;
        for (int i = 1; i < WIDTH; i++) {
            can_commit[i] = can_commit[i - 1] && !buf_[head_idx[i - 1]].exception &&
                            !buf_[head_idx[i - 1]].mispredict && buf_[head_idx[i]].valid &&
                            buf_[head_idx[i]].done;
        }

        int n_commit = 0;
        for (int i = 0; i < WIDTH; i++) {
            if (can_commit[i]) {
                const Entry& e = buf_[head_idx[i]];
                commit_out[i] = {true, e.pc, e.rd_arch, e.prd, e.prev_prd, e.is_store};
                n_commit++;
            }
        }

        // flush detection
        bool flush_full_c = false, flush_branch_c = false;
        int flush_idx_c = 0;
        uint64_t flush_pc_c = 0;
        for (int i = 0; i < WIDTH; i++) {
            if (can_commit[i] && buf_[head_idx[i]].exception && !flush_full_c && !flush_branch_c) {
                flush_full_c = true;
                flush_pc_c = buf_[head_idx[i]].redirect_pc;
            } else if (can_commit[i] && buf_[head_idx[i]].mispredict && !flush_full_c && !flush_branch_c) {
                flush_branch_c = true;
                flush_idx_c = head_idx[i];
                flush_pc_c = buf_[head_idx[i]].redirect_pc;
            }
        }

        flush_valid = flush_full_c || flush_branch_c;
        flush_full = flush_full_c;
        flush_pc = flush_pc_c;
        flush_branch_idx = flush_idx_c;

        int n_alloc = 0;
        if (alloc_ready) {
            for (auto& a : allocs)
                if (a.valid) n_alloc++;
        }

        if (flush_full_c) {
            buf_.assign(DEPTH, Entry{});
            head_ = tail_ = count_ = 0;
            return;
        }

        // retire committed entries
        for (int i = 0; i < WIDTH; i++) {
            if (can_commit[i]) buf_[head_idx[i]].valid = false;
        }
        head_ = (head_ + n_commit) % DEPTH;

        if (flush_branch_c) {
            int n_squash = count_ - n_commit;
            for (int k = 0; k < n_squash; k++) {
                int idx = (flush_idx_c + 1 + k) % DEPTH;
                buf_[idx].valid = false;
            }
            tail_ = (flush_idx_c + 1) % DEPTH;
            count_ = 0;
        } else {
            if (alloc_ready) {
                int slot = 0;
                for (auto& a : allocs) {
                    if (a.valid) {
                        // tail_ has not been mutated yet this step, so it still names the next free slot
                        int idx = (tail_ + slot) % DEPTH;
                        Entry e;
                        e.valid = true;
                        e.done = false;
                        e.exception = false;
                        e.mispredict = false;
                        e.pc = a.pc;
                        e.rd_arch = a.rd_arch;
                        e.prd = a.prd;
                        e.prev_prd = a.prev_prd;
                        e.is_store = a.is_store;
                        buf_[idx] = e;
                        slot++;
                    }
                }
            }
            tail_ = (tail_ + n_alloc) % DEPTH;
            count_ = count_ - n_commit + n_alloc;
        }

        for (auto& w : wbs) {
            if (w.valid) {
                buf_[w.rob_idx].done = true;
                buf_[w.rob_idx].exception = w.exception;
                buf_[w.rob_idx].mispredict = w.mispredict;
                buf_[w.rob_idx].redirect_pc = w.redirect_pc;
            }
        }
    }

    // allocation index this cycle for slot i, matching RTL's alloc_rob_idx (based on pre-edge state)
    int allocIdx(int slot) const { return idxAt(count_ + slot); }

private:
    std::vector<Entry> buf_;
    int head_, tail_, count_;
};
