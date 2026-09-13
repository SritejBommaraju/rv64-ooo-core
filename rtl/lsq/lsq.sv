// Standalone load/store queue: store-to-load forwarding, in-order store commit, squash.
// verilator lint_off WIDTHEXPAND
// verilator lint_off WIDTHTRUNC
module lsq #(
    parameter int LQ_DEPTH  = 8,
    parameter int SQ_DEPTH  = 8,
    parameter int ROB_IDX_W = 5
) (
    input logic clk,
    input logic rst,
    input logic [ROB_IDX_W-1:0] rob_head, // for age comparisons; ages wrap relative to this

    // dispatch, 2 ports, port0 older than port1 within a cycle
    input  logic                        disp_valid  [2],
    input  logic                        disp_is_load[2],
    input  logic [ROB_IDX_W-1:0]        disp_rob_idx[2],
    output logic                        disp_ready  [2],
    output logic [$clog2(LQ_DEPTH)-1:0] disp_lq_idx [2],
    output logic [$clog2(SQ_DEPTH)-1:0] disp_sq_idx [2],

    // store address/data arrival, one port, out of order by sq_idx
    input logic                        st_addr_valid,
    input logic [$clog2(SQ_DEPTH)-1:0] st_sq_idx,
    input logic [63:0]                 st_addr,
    input logic [1:0]                  st_size, // 0=B,1=H,2=W,3=D
    input logic [63:0]                 st_data,

    // load address arrival, one port, out of order by lq_idx
    input logic                        ld_addr_valid,
    input logic [$clog2(LQ_DEPTH)-1:0] ld_lq_idx,
    input logic [63:0]                 ld_addr,
    input logic [1:0]                  ld_size,
    input logic                        ld_signed,

    // load resolution: forwarded or read from dmem, at most one per cycle, retried automatically while pending
    output logic                        ld_resp_valid,
    output logic [$clog2(LQ_DEPTH)-1:0] ld_resp_lq_idx,
    output logic [63:0]                 ld_resp_data,
    output logic [ROB_IDX_W-1:0]        ld_resp_rob_idx,

    // dmem read port, combinational (TB/mem.sv return data same cycle)
    output logic        dmem_rd_valid,
    output logic [63:0] dmem_rd_addr,
    output logic [1:0]  dmem_rd_size,
    input  logic [63:0] dmem_rd_data,

    // commit, in order from ROB, one store / one load per cycle
    input  logic         commit_store_valid,
    input  logic         commit_load_valid,
    output logic         dmem_wr_valid,
    output logic [63:0]  dmem_wr_addr,
    output logic [1:0]   dmem_wr_size,
    output logic [63:0]  dmem_wr_data,

    // squash: drop entries strictly younger than squash_rob_idx; squash_all drops everything
    input logic                  squash_valid,
    input logic [ROB_IDX_W-1:0]  squash_rob_idx,
    input logic                  squash_all,

    output logic [$clog2(LQ_DEPTH):0] lq_count,
    output logic [$clog2(SQ_DEPTH):0] sq_count
);
    localparam int LQW = $clog2(LQ_DEPTH);
    localparam int SQW = $clog2(SQ_DEPTH);

    // age relative to rob_head; smaller = older. wraps naturally via mod-2^W subtraction.
    function automatic logic [ROB_IDX_W-1:0] age_f(input logic [ROB_IDX_W-1:0] idx);
        return idx - rob_head;
    endfunction

    function automatic logic [63:0] extend_f(input logic [63:0] raw, input logic [1:0] sz, input logic sgn);
        case (sz)
            2'd0: extend_f = sgn ? {{56{raw[7]}},  raw[7:0]}  : {56'd0, raw[7:0]};
            2'd1: extend_f = sgn ? {{48{raw[15]}}, raw[15:0]} : {48'd0, raw[15:0]};
            2'd2: extend_f = sgn ? {{32{raw[31]}}, raw[31:0]} : {32'd0, raw[31:0]};
            default: extend_f = raw;
        endcase
    endfunction

    function automatic logic [3:0] nbytes_f(input logic [1:0] sz);
        return 4'd1 << sz;
    endfunction

    // -------------------- storage --------------------
    logic [ROB_IDX_W-1:0] lq_rob      [LQ_DEPTH];
    logic                 lq_addr_v   [LQ_DEPTH];
    logic [63:0]          lq_addr_q   [LQ_DEPTH];
    logic [1:0]           lq_size_q   [LQ_DEPTH];
    logic                 lq_signed_q [LQ_DEPTH];
    logic                 lq_resolved [LQ_DEPTH];
    logic [LQW-1:0] lq_head, lq_tail;
    logic [LQW:0]   lq_cnt;

    logic [ROB_IDX_W-1:0] sq_rob      [SQ_DEPTH];
    logic                 sq_addr_v   [SQ_DEPTH];
    logic [63:0]          sq_addr_q   [SQ_DEPTH];
    logic [1:0]           sq_size_q   [SQ_DEPTH];
    logic [63:0]          sq_data_q   [SQ_DEPTH];
    logic [SQW-1:0] sq_head, sq_tail;
    logic [SQW:0]   sq_cnt;

    assign lq_count = lq_cnt;
    assign sq_count = sq_cnt;

    // -------------------- dispatch --------------------
    logic [LQW:0] lq_free;
    logic [SQW:0] sq_free;
    assign lq_free = LQ_DEPTH[LQW:0] - lq_cnt;
    assign sq_free = SQ_DEPTH[SQW:0] - sq_cnt;

    logic p0_takes_lq, p0_takes_sq;
    assign p0_takes_lq = disp_valid[0] && ready0_i && disp_is_load[0];
    assign p0_takes_sq = disp_valid[0] && ready0_i && !disp_is_load[0];

    logic [LQW:0] lq_free_after0;
    logic [SQW:0] sq_free_after0;
    assign lq_free_after0 = lq_free - (p0_takes_lq ? 1'b1 : 1'b0);
    assign sq_free_after0 = sq_free - (p0_takes_sq ? 1'b1 : 1'b0);

    // scalar temporaries so verilator doesn't (falsely) see a self-loop through the disp_ready[] array
    logic ready0_i, ready1_i;
    // dispatch is held off entirely on a squash cycle: a same-cycle squash changes the tail out from
    // under disp_lq_idx/disp_sq_idx (which are driven off the pre-squash registered tail), so front-end
    // dispatch and squash never overlap - matches a real core stalling decode during a flush cycle.
    logic squash_this_cycle;
    assign squash_this_cycle = squash_valid || squash_all;
    assign ready0_i = !squash_this_cycle && (disp_is_load[0] ? (lq_free        != 0) : (sq_free        != 0));
    assign ready1_i = !squash_this_cycle && (disp_is_load[1] ? (lq_free_after0 != 0) : (sq_free_after0 != 0));
    assign disp_ready[0] = ready0_i;
    assign disp_ready[1] = ready1_i;

    assign disp_lq_idx[0] = lq_tail;
    assign disp_sq_idx[0] = sq_tail;
    assign disp_lq_idx[1] = p0_takes_lq ? ((lq_tail + 1'b1) & (LQ_DEPTH-1)) : lq_tail;
    assign disp_sq_idx[1] = p0_takes_sq ? ((sq_tail + 1'b1) & (SQ_DEPTH-1)) : sq_tail;

    logic [LQW:0] n_lq_alloc;
    logic [SQW:0] n_sq_alloc;
    always_comb begin
        n_lq_alloc = '0;
        n_sq_alloc = '0;
        for (int i = 0; i < 2; i++) begin
            if (disp_valid[i] && disp_ready[i]) begin
                if (disp_is_load[i]) n_lq_alloc++;
                else n_sq_alloc++;
            end
        end
    end

    // -------------------- squash survivor counts --------------------
    logic [LQW:0] lq_keep_cnt;
    logic [SQW:0] sq_keep_cnt;
    always_comb begin
        lq_keep_cnt = '0;
        for (int i = 0; i < LQ_DEPTH; i++) begin
            automatic logic [LQW-1:0] li = (lq_head + i[LQW-1:0]) & (LQ_DEPTH-1);
            if (i < lq_cnt && age_f(lq_rob[li]) <= age_f(squash_rob_idx)) lq_keep_cnt++;
        end
        sq_keep_cnt = '0;
        for (int i = 0; i < SQ_DEPTH; i++) begin
            automatic logic [SQW-1:0] si = (sq_head + i[SQW-1:0]) & (SQ_DEPTH-1);
            if (i < sq_cnt && age_f(sq_rob[si]) <= age_f(squash_rob_idx)) sq_keep_cnt++;
        end
    end

    // -------------------- load resolution search --------------------
    logic                  found_ld;
    logic [LQW-1:0]        found_li;
    logic                  found_is_dmem;
    logic [63:0]           found_fwd_data;

    always_comb begin
        found_ld       = 1'b0;
        found_li       = '0;
        found_is_dmem  = 1'b0;
        found_fwd_data = '0;
        for (int i = 0; i < LQ_DEPTH; i++) begin
            automatic logic [LQW-1:0] li = (lq_head + i[LQW-1:0]) & (LQ_DEPTH-1);
            automatic logic        blocked_unknown = 1'b0;
            automatic logic        any_overlap     = 1'b0;
            automatic logic        yv_full         = 1'b0;
            automatic logic [ROB_IDX_W-1:0] yv_age = '0;
            automatic logic [63:0] yv_data          = '0;
            automatic logic [63:0] l_lo = lq_addr_q[li];
            automatic logic [63:0] l_hi = lq_addr_q[li] + {60'd0, nbytes_f(lq_size_q[li])};
            automatic logic ld_pending = !found_ld && i < lq_cnt && lq_addr_v[li] && !lq_resolved[li];
            for (int j = 0; j < SQ_DEPTH; j++) begin
                automatic logic [SQW-1:0] sj = (sq_head + j[SQW-1:0]) & (SQ_DEPTH-1);
                automatic logic [63:0] s_lo = sq_addr_q[sj];
                automatic logic [63:0] s_hi = sq_addr_q[sj] + {60'd0, nbytes_f(sq_size_q[sj])};
                automatic logic [2:0]  off  = l_lo[2:0] - s_lo[2:0];
                automatic logic [63:0] shifted = sq_data_q[sj] >> ({58'd0, off} * 8);
                if (ld_pending && j < sq_cnt && age_f(sq_rob[sj]) < age_f(lq_rob[li])) begin
                    if (!sq_addr_v[sj]) begin
                        blocked_unknown = 1'b1;
                    end else if (!(l_hi <= s_lo || s_hi <= l_lo)) begin // overlaps
                        if (!any_overlap || age_f(sq_rob[sj]) > yv_age) begin
                            any_overlap = 1'b1;
                            yv_age      = age_f(sq_rob[sj]);
                            yv_full     = (s_lo <= l_lo) && (s_hi >= l_hi);
                            if (yv_full) yv_data = extend_f(shifted, lq_size_q[li], lq_signed_q[li]);
                        end
                    end
                end
            end

            if (ld_pending) begin
                if (!blocked_unknown) begin
                    if (any_overlap && yv_full) begin
                        found_ld       = 1'b1;
                        found_li       = li;
                        found_is_dmem  = 1'b0;
                        found_fwd_data = yv_data;
                    end else if (!any_overlap) begin
                        found_ld      = 1'b1;
                        found_li      = li;
                        found_is_dmem = 1'b1;
                    end
                    // any_overlap && !yv_full: partial overlap, stall - leave found_ld low, try next load
                end
            end
        end
    end

    assign dmem_rd_valid = found_ld && found_is_dmem;
    assign dmem_rd_addr  = found_ld ? lq_addr_q[found_li] : 64'd0;
    assign dmem_rd_size  = found_ld ? lq_size_q[found_li] : 2'd0;

    assign ld_resp_valid   = found_ld;
    assign ld_resp_lq_idx  = found_li;
    assign ld_resp_rob_idx = found_ld ? lq_rob[found_li] : '0;
    assign ld_resp_data    = found_is_dmem ? extend_f(dmem_rd_data, lq_size_q[found_li], lq_signed_q[found_li])
                                            : found_fwd_data;

    // -------------------- commit --------------------
    assign dmem_wr_valid = commit_store_valid && (sq_cnt != 0);
    assign dmem_wr_addr  = sq_addr_q[sq_head];
    assign dmem_wr_size  = sq_size_q[sq_head];
    assign dmem_wr_data  = sq_data_q[sq_head];

    // -------------------- sequential state update --------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            lq_head <= '0; lq_tail <= '0; lq_cnt <= '0;
            sq_head <= '0; sq_tail <= '0; sq_cnt <= '0;
            for (int i = 0; i < LQ_DEPTH; i++) begin lq_addr_v[i] <= 1'b0; lq_resolved[i] <= 1'b0; end
            for (int i = 0; i < SQ_DEPTH; i++) sq_addr_v[i] <= 1'b0;
        end else if (squash_all) begin
            lq_head <= '0; lq_tail <= '0; lq_cnt <= '0;
            sq_head <= '0; sq_tail <= '0; sq_cnt <= '0;
        end else begin
            automatic logic [LQW:0] lq_base_cnt;
            automatic logic [SQW:0] sq_base_cnt;
            automatic logic [LQW:0] lq_after_commit;
            automatic logic [SQW:0] sq_after_commit;
            automatic logic [LQW-1:0] lq_head_n;
            automatic logic [SQW-1:0] sq_head_n;
            automatic logic [LQW:0] lq_final_cnt;
            automatic logic [SQW:0] sq_final_cnt;

            lq_base_cnt = squash_valid ? lq_keep_cnt : lq_cnt;
            sq_base_cnt = squash_valid ? sq_keep_cnt : sq_cnt;

            lq_after_commit = lq_base_cnt - ((commit_load_valid  && lq_base_cnt != 0) ? 1'b1 : 1'b0);
            sq_after_commit = sq_base_cnt - ((commit_store_valid && sq_base_cnt != 0) ? 1'b1 : 1'b0);
            lq_head_n = (commit_load_valid  && lq_base_cnt != 0) ? ((lq_head + 1'b1) & (LQ_DEPTH-1)) : lq_head;
            sq_head_n = (commit_store_valid && sq_base_cnt != 0) ? ((sq_head + 1'b1) & (SQ_DEPTH-1)) : sq_head;

            lq_final_cnt = lq_after_commit + n_lq_alloc;
            sq_final_cnt = sq_after_commit + n_sq_alloc;

            lq_head <= lq_head_n;
            sq_head <= sq_head_n;
            lq_tail <= (lq_head_n + lq_final_cnt[LQW-1:0]) & (LQ_DEPTH-1);
            sq_tail <= (sq_head_n + sq_final_cnt[SQW-1:0]) & (SQ_DEPTH-1);
            lq_cnt  <= lq_final_cnt;
            sq_cnt  <= sq_final_cnt;

            // new dispatches
            for (int i = 0; i < 2; i++) begin
                if (disp_valid[i] && disp_ready[i]) begin
                    if (disp_is_load[i]) begin
                        automatic logic [LQW-1:0] idx = disp_lq_idx[i];
                        lq_rob[idx]      <= disp_rob_idx[i];
                        lq_addr_v[idx]   <= 1'b0;
                        lq_resolved[idx] <= 1'b0;
                    end else begin
                        automatic logic [SQW-1:0] idx = disp_sq_idx[i];
                        sq_rob[idx]    <= disp_rob_idx[i];
                        sq_addr_v[idx] <= 1'b0;
                    end
                end
            end
        end

        // address/data arrival, independent of squash/commit/dispatch bookkeeping above
        if (st_addr_valid) begin
            sq_addr_v[st_sq_idx] <= 1'b1;
            sq_addr_q[st_sq_idx] <= st_addr;
            sq_size_q[st_sq_idx] <= st_size;
            sq_data_q[st_sq_idx] <= st_data;
        end
        if (ld_addr_valid) begin
            lq_addr_v[ld_lq_idx]   <= 1'b1;
            lq_addr_q[ld_lq_idx]   <= ld_addr;
            lq_size_q[ld_lq_idx]   <= ld_size;
            lq_signed_q[ld_lq_idx] <= ld_signed;
            lq_resolved[ld_lq_idx] <= 1'b0;
        end
        if (ld_resp_valid && !rst && !squash_all) lq_resolved[found_li] <= 1'b1;
    end
endmodule
