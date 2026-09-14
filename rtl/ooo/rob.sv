// Standalone 2-wide circular reorder buffer.
module rob #(
    parameter int ROB_DEPTH = 32,
    parameter int WIDTH     = 2
) (
    input  logic clk,
    input  logic rst,

    // allocate (dispatch) port, WIDTH slots
    input  logic        alloc_valid   [WIDTH],
    input  logic [63:0] alloc_pc      [WIDTH],
    input  logic [4:0]  alloc_rd_arch [WIDTH],
    input  logic [6:0]  alloc_prd     [WIDTH],
    input  logic [6:0]  alloc_prev_prd[WIDTH],
    input  logic        alloc_is_branch[WIDTH],
    input  logic        alloc_is_store [WIDTH],
    output logic [$clog2(ROB_DEPTH)-1:0] alloc_rob_idx[WIDTH],
    output logic         alloc_ready,

    // writeback port, WIDTH slots
    input  logic        wb_valid     [WIDTH],
    input  logic [$clog2(ROB_DEPTH)-1:0] wb_rob_idx[WIDTH],
    input  logic        wb_exception [WIDTH],
    input  logic        wb_mispredict[WIDTH],
    input  logic [63:0] wb_redirect_pc[WIDTH],

    // commit port, WIDTH slots, in-order from head. commit_accept[i] must be asserted by the
    // caller for slot i to actually retire this cycle - lets a caller that can only consume
    // fewer than WIDTH commits/cycle (e.g. a single-issue core using this ROB at WIDTH=2 purely
    // for its 2-port writeback capability) force single-commit without losing state: without this
    // gate, done_q/v_q alone would let two ready head entries retire together even though only
    // commit port 0 is ever drained downstream, silently skipping port 1's LSQ pop/rename retire.
    input  logic         commit_accept  [WIDTH],
    output logic        commit_valid   [WIDTH],
    output logic [63:0] commit_pc      [WIDTH],
    output logic [4:0]  commit_rd_arch [WIDTH],
    output logic [6:0]  commit_prd     [WIDTH],
    output logic [6:0]  commit_prev_prd[WIDTH],
    output logic        commit_is_store[WIDTH],

    // flush
    output logic         flush_valid,
    output logic         flush_full,
    output logic [63:0]  flush_pc,
    output logic [$clog2(ROB_DEPTH)-1:0] flush_branch_rob_idx,

    // status
    output logic [$clog2(ROB_DEPTH)-1:0] rob_head,
    output logic [$clog2(ROB_DEPTH)-1:0] rob_tail,
    output logic [$clog2(ROB_DEPTH):0]   rob_count,
    output logic         rob_empty,
    output logic         rob_full
);
    localparam int IDX_W = $clog2(ROB_DEPTH);

    logic                v_q     [ROB_DEPTH];
    logic                done_q  [ROB_DEPTH];
    logic                exc_q   [ROB_DEPTH];
    logic                mis_q   [ROB_DEPTH];
    logic [63:0]         pc_q    [ROB_DEPTH];
    logic [63:0]         redir_q [ROB_DEPTH];
    logic [4:0]           rd_arch_q [ROB_DEPTH];
    logic [6:0]           prd_q     [ROB_DEPTH];
    logic [6:0]           prev_prd_q[ROB_DEPTH];
    logic                is_store_q[ROB_DEPTH];

    logic [IDX_W-1:0] head_q, tail_q;
    logic [IDX_W:0]   count_q;

    assign rob_head  = head_q;
    assign rob_tail  = tail_q;
    assign rob_count = count_q;
    assign rob_empty = (count_q == '0);
    assign rob_full  = (count_q == ROB_DEPTH[IDX_W:0]);

    // number of free slots available this cycle, before this cycle's commit is applied to count
    logic [IDX_W:0] free_slots;
    assign free_slots = ROB_DEPTH[IDX_W:0] - count_q;
    assign alloc_ready = (free_slots >= WIDTH[IDX_W:0]);

    genvar gi;
    generate
        for (gi = 0; gi < WIDTH; gi++) begin : g_alloc_idx
            assign alloc_rob_idx[gi] = head_q + count_q[IDX_W-1:0] + IDX_W'(gi);
        end
    endgenerate

    // commit eligibility: slot0 must be valid+done, slot1 only commits if slot0 committed and slot1 valid+done,
    // and neither slot commits an exception/mispredict entry as a "normal" commit continuing past it -
    // exception/mispredict at slot0 still commits itself (it retires) but blocks slot1 and triggers flush
    logic [IDX_W-1:0] head_idx[WIDTH];
    logic             can_commit[WIDTH];

    always_comb begin
        for (int i = 0; i < WIDTH; i++) begin
            head_idx[i] = head_q + IDX_W'(i);
        end
        can_commit[0] = v_q[head_idx[0]] && done_q[head_idx[0]] && commit_accept[0];
        for (int i = 1; i < WIDTH; i++) begin
            can_commit[i] = can_commit[i-1] && !exc_q[head_idx[i-1]] && !mis_q[head_idx[i-1]] &&
                            v_q[head_idx[i]] && done_q[head_idx[i]] && commit_accept[i];
        end
    end

    always_comb begin
        for (int i = 0; i < WIDTH; i++) begin
            commit_valid[i]    = can_commit[i];
            commit_pc[i]       = pc_q[head_idx[i]];
            commit_rd_arch[i]  = rd_arch_q[head_idx[i]];
            commit_prd[i]      = prd_q[head_idx[i]];
            commit_prev_prd[i] = prev_prd_q[head_idx[i]];
            commit_is_store[i] = is_store_q[head_idx[i]];
        end
    end

    // flush detection: exception committing at head -> full flush; mispredict committing -> squash younger
    logic flush_full_c, flush_branch_c;
    logic [IDX_W-1:0] flush_idx_c;
    logic [63:0] flush_pc_c;
    always_comb begin
        flush_full_c   = 1'b0;
        flush_branch_c = 1'b0;
        flush_idx_c    = '0;
        flush_pc_c     = '0;
        for (int i = 0; i < WIDTH; i++) begin
            if (can_commit[i] && exc_q[head_idx[i]] && !flush_full_c && !flush_branch_c) begin
                flush_full_c = 1'b1;
                flush_pc_c   = redir_q[head_idx[i]];
            end else if (can_commit[i] && mis_q[head_idx[i]] && !flush_full_c && !flush_branch_c) begin
                flush_branch_c = 1'b1;
                flush_idx_c    = head_idx[i];
                flush_pc_c     = redir_q[head_idx[i]];
            end
        end
    end

    assign flush_valid           = flush_full_c | flush_branch_c;
    assign flush_full            = flush_full_c;
    assign flush_pc              = flush_pc_c;
    assign flush_branch_rob_idx  = flush_idx_c;

    logic [IDX_W:0] n_commit;
    always_comb begin
        n_commit = '0;
        for (int i = 0; i < WIDTH; i++) if (can_commit[i]) n_commit++;
    end

    logic [IDX_W:0] n_alloc;
    always_comb begin
        n_alloc = '0;
        if (alloc_ready) for (int i = 0; i < WIDTH; i++) if (alloc_valid[i]) n_alloc++;
    end

    // number of entries squashed by a mispredict flush: everything younger than flush_idx_c that is currently valid
    logic [IDX_W:0] n_squash;
    always_comb begin
        n_squash = '0;
        if (flush_branch_c) n_squash = count_q - n_commit;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head_q  <= '0;
            tail_q  <= '0;
            count_q <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                v_q[i]    <= 1'b0;
                done_q[i] <= 1'b0;
                exc_q[i]  <= 1'b0;
                mis_q[i]  <= 1'b0;
            end
        end else if (flush_full_c) begin
            head_q  <= '0;
            tail_q  <= '0;
            count_q <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) v_q[i] <= 1'b0;
        end else begin
            // retire committed entries
            for (int i = 0; i < WIDTH; i++) begin
                if (can_commit[i]) v_q[head_idx[i]] <= 1'b0;
            end
            head_q <= head_q + n_commit[IDX_W-1:0];

            if (flush_branch_c) begin
                tail_q  <= flush_idx_c + IDX_W'(1);
                count_q <= '0;
                for (int i = 0; i < ROB_DEPTH; i++) begin
                    // invalidate everything strictly younger than the mispredicting entry
                    automatic logic [IDX_W-1:0] gap = IDX_W'(i) - flush_idx_c;
                    if (v_q[i] && (IDX_W'(i) != flush_idx_c) && {1'b0, gap} <= n_squash) v_q[i] <= 1'b0;
                end
            end else begin
                // allocate new entries
                if (alloc_ready) begin
                    for (int i = 0; i < WIDTH; i++) begin
                        if (alloc_valid[i]) begin
                            automatic logic [IDX_W-1:0] idx = alloc_rob_idx[i];
                            v_q[idx]         <= 1'b1;
                            done_q[idx]      <= 1'b0;
                            exc_q[idx]       <= 1'b0;
                            mis_q[idx]       <= 1'b0;
                            pc_q[idx]        <= alloc_pc[i];
                            rd_arch_q[idx]   <= alloc_rd_arch[i];
                            prd_q[idx]       <= alloc_prd[i];
                            prev_prd_q[idx]  <= alloc_prev_prd[i];
                            is_store_q[idx]  <= alloc_is_store[i];
                        end
                    end
                end
                tail_q  <= tail_q + n_alloc[IDX_W-1:0];
                count_q <= count_q - n_commit + n_alloc;
            end

            // writeback marks entries done, independent of alloc/commit this cycle
            for (int i = 0; i < WIDTH; i++) begin
                if (wb_valid[i]) begin
                    done_q[wb_rob_idx[i]]  <= 1'b1;
                    exc_q[wb_rob_idx[i]]   <= wb_exception[i];
                    mis_q[wb_rob_idx[i]]   <= wb_mispredict[i];
                    redir_q[wb_rob_idx[i]] <= wb_redirect_pc[i];
                end
            end
        end
    end

    // is_branch is not consumed by any output port; kept as an input for interface completeness
    // verilator lint_off UNUSED
    logic unused_is_branch;
    assign unused_is_branch = |{alloc_is_branch[0], alloc_is_branch[1]};
    // verilator lint_on UNUSED

endmodule
