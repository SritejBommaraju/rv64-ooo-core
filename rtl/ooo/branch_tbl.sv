// branch_tbl: ROB_DEPTH-entry side table the ROB itself doesn't keep. Written at dispatch
// with {is_branch, ckpt_id, predicted npc}; written at writeback with {actual taken, target}.
// Read with the ROB's flush_branch_rob_idx to drive rename restore + LSQ squash + frontend
// redirect on a mispredict flush; read with commit_pc/rob_head at commit to drive BTB
// training (bp_upd, committed branches only) and rename checkpoint release.
module branch_tbl #(
    parameter int ROB_DEPTH = 32,
    parameter int N_CKPT    = 8,
    parameter int WIDTH     = 2
) (
    input logic clk,
    input logic rst,

    // dispatch write, WIDTH slots. disp_is_branch gates BTB training at commit (real
    // conditional branches only); disp_took_ckpt gates checkpoint release at commit
    // (anything rename granted a checkpoint to - branches, jal, jalr) - the two differ
    // because a checkpoint is needed for any control-flow redirect point, not just
    // instructions the direction predictor trains on.
    input logic                          disp_valid    [WIDTH],
    input logic [$clog2(ROB_DEPTH)-1:0]  disp_rob_idx  [WIDTH],
    input logic                          disp_is_branch[WIDTH],
    input logic                          disp_took_ckpt[WIDTH],
    input logic [$clog2(N_CKPT)-1:0]     disp_ckpt_id  [WIDTH],
    input logic [63:0]                   disp_pred_npc [WIDTH],

    // writeback write, WIDTH slots
    input logic                          wb_valid   [WIDTH],
    input logic [$clog2(ROB_DEPTH)-1:0]  wb_rob_idx [WIDTH],
    input logic                          wb_taken   [WIDTH],
    input logic [63:0]                   wb_target  [WIDTH],

    // flush read, from the ROB
    input  logic                          rob_flush_valid,
    input  logic                          rob_flush_full,
    input  logic [$clog2(ROB_DEPTH)-1:0]  rob_flush_branch_rob_idx,
    input  logic [63:0]                   rob_flush_pc,

    output logic                         restore_valid,   // -> rename
    output logic [$clog2(N_CKPT)-1:0]    restore_ckpt_id, // -> rename
    output logic                         squash_valid,    // -> lsq
    output logic [$clog2(ROB_DEPTH)-1:0] squash_rob_idx,  // -> lsq
    output logic                         redirect_valid,  // -> frontend
    output logic [63:0]                  redirect_pc,     // -> frontend

    // commit read, WIDTH slots, from the ROB
    input logic                          commit_valid [WIDTH],
    input logic [63:0]                   commit_pc    [WIDTH],
    input logic [$clog2(ROB_DEPTH)-1:0]  rob_head,

    output logic         bp_upd_valid [WIDTH], // -> frontend's predictor
    output logic [63:0]  bp_upd_pc    [WIDTH],
    output logic         bp_upd_taken [WIDTH],
    output logic [63:0]  bp_upd_target[WIDTH],
    output logic          commit_ckpt_release0, // -> rename
    output logic          commit_ckpt_release1, // -> rename

    output logic [31:0] cnt_branches_committed,
    output logic [31:0] cnt_mispredicts,
    output logic [31:0] cnt_ckpt_alloc,
    output logic [31:0] cnt_ckpt_release
);
    localparam int IDX_W  = $clog2(ROB_DEPTH);
    localparam int CKPT_W = $clog2(N_CKPT);

    logic                is_branch_q[ROB_DEPTH];
    logic                took_ckpt_q[ROB_DEPTH];
    logic [CKPT_W-1:0]   ckpt_id_q  [ROB_DEPTH];
    logic [63:0]         pred_npc_q [ROB_DEPTH];
    logic                taken_q    [ROB_DEPTH];
    logic [63:0]         target_q   [ROB_DEPTH];

    // -------------------- flush read (mispredict recovery) --------------------
    wire [IDX_W-1:0] flush_idx = rob_flush_branch_rob_idx;

    assign restore_valid   = rob_flush_valid && !rob_flush_full;
    assign restore_ckpt_id = ckpt_id_q[flush_idx];
    assign squash_valid    = restore_valid;
    assign squash_rob_idx  = flush_idx;
    assign redirect_valid  = restore_valid;
    assign redirect_pc     = rob_flush_pc;

    // -------------------- commit read (BTB training + ckpt release) --------------------
    logic [IDX_W-1:0] commit_idx[WIDTH];
    genvar gi;
    generate
        for (gi = 0; gi < WIDTH; gi++) begin : g_commit_idx
            assign commit_idx[gi] = rob_head + IDX_W'(gi);

            assign bp_upd_valid[gi]  = commit_valid[gi] && is_branch_q[commit_idx[gi]];
            assign bp_upd_pc[gi]     = commit_pc[gi];
            assign bp_upd_taken[gi]  = taken_q[commit_idx[gi]];
            assign bp_upd_target[gi] = target_q[commit_idx[gi]];
        end
    endgenerate

    // a mispredicting branch's own checkpoint is reclaimed by the restore's head
    // rollback itself (see rename.sv), and it commits the very same cycle the
    // restore fires, so its commit must not release the checkpoint a second time
    assign commit_ckpt_release0 = commit_valid[0] && took_ckpt_q[commit_idx[0]] &&
                                   !(restore_valid && commit_idx[0] == flush_idx);
    assign commit_ckpt_release1 = commit_valid[1] && took_ckpt_q[commit_idx[1]] &&
                                   !(restore_valid && commit_idx[1] == flush_idx);

    // -------------------- sequential storage + counters --------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < ROB_DEPTH; i++) begin
                is_branch_q[i] <= 1'b0;
                took_ckpt_q[i] <= 1'b0;
            end
            cnt_branches_committed <= '0;
            cnt_mispredicts        <= '0;
            cnt_ckpt_alloc         <= '0;
            cnt_ckpt_release       <= '0;
        end else begin
            for (int i = 0; i < WIDTH; i++) begin
                if (disp_valid[i]) begin
                    is_branch_q[disp_rob_idx[i]] <= disp_is_branch[i];
                    took_ckpt_q[disp_rob_idx[i]] <= disp_took_ckpt[i];
                    ckpt_id_q[disp_rob_idx[i]]   <= disp_ckpt_id[i];
                    pred_npc_q[disp_rob_idx[i]]  <= disp_pred_npc[i];
                end
                if (wb_valid[i]) begin
                    taken_q[wb_rob_idx[i]]  <= wb_taken[i];
                    target_q[wb_rob_idx[i]] <= wb_target[i];
                end
            end

            if (restore_valid) cnt_mispredicts <= cnt_mispredicts + 32'd1;

            for (int i = 0; i < WIDTH; i++) begin
                if (commit_valid[i] && is_branch_q[commit_idx[i]])
                    cnt_branches_committed <= cnt_branches_committed + 32'd1;
                if (disp_valid[i] && disp_took_ckpt[i])
                    cnt_ckpt_alloc <= cnt_ckpt_alloc + 32'd1;
            end
            cnt_ckpt_release <= cnt_ckpt_release + {31'd0, commit_ckpt_release0} + {31'd0, commit_ckpt_release1};
        end
    end

    // pred_npc_q is recorded for a future predicted-vs-actual comparison lane; not read
    // by any output port today (the TB/executor computes the comparison itself)
    // verilator lint_off UNUSEDSIGNAL
    wire [63:0] unused_pred_npc = pred_npc_q[0];
    // verilator lint_on UNUSEDSIGNAL

endmodule
