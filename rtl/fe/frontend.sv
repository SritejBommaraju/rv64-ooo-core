// frontend: PC register + bp_bimodal_btb, the fetch-stage seam for ooo_core.sv.
// Next pc = redirect ? redirect_pc : pred_taken ? pred_target : pc+4. redirect has
// top priority and overrides even a stall, since a misprediction must not be starved.
module frontend (
    input  logic clk,
    input  logic rst,

    input  logic         stall_fetch,

    output logic [63:0]  imem_addr,
    input  logic [31:0]  imem_rdata,

    output logic         fetch_valid,
    output logic [63:0]  fetch_pc,
    output logic [31:0]  fetch_instr,
    output logic         fetch_pred_taken,
    output logic [63:0]  fetch_pred_npc,

    input  logic         redirect_valid,
    input  logic [63:0]  redirect_pc,

    input  logic         bp_upd_valid,
    input  logic [63:0]  bp_upd_pc,
    input  logic         bp_upd_taken,
    input  logic [63:0]  bp_upd_target
);

    logic [63:0] pc_q;
    logic        pred_taken, pred_hit;
    logic [63:0] pred_target;

    bp_bimodal_btb u_bp (
        .clk(clk), .rst(rst),
        .pred_pc(pc_q), .pred_taken(pred_taken), .pred_target(pred_target), .pred_hit(pred_hit),
        .upd_valid(bp_upd_valid), .upd_pc(bp_upd_pc), .upd_taken(bp_upd_taken), .upd_target(bp_upd_target)
    );

    assign imem_addr = pc_q;

    assign fetch_valid       = !rst && !stall_fetch;
    assign fetch_pc          = pc_q;
    assign fetch_instr       = imem_rdata;
    assign fetch_pred_taken  = pred_taken;
    assign fetch_pred_npc    = pred_taken ? pred_target : (pc_q + 64'd4);

    wire [63:0] seq_next = pred_taken ? pred_target : (pc_q + 64'd4);

    always_ff @(posedge clk) begin
        if (rst) pc_q <= 64'd0;
        else if (redirect_valid) pc_q <= redirect_pc;
        else if (!stall_fetch) pc_q <= seq_next;
    end

    // pred_hit not consumed outside the predictor itself; kept for interface completeness
    // verilator lint_off UNUSEDSIGNAL
    wire unused_pred_hit = pred_hit;
    // verilator lint_on UNUSEDSIGNAL

endmodule
