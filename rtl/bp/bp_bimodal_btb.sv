// bp_bimodal_btb: standalone 2-bit bimodal direction predictor + direct-mapped BTB.
//
// Fetch-stage contract (for the future 2-wide fetch unit):
//   - Prediction is combinational: drive pred_pc with the next-PC candidate in F1
//     and consume pred_taken/pred_target/pred_hit in the same cycle.
//   - Update happens at commit (or branch resolution): assert upd_valid for one
//     cycle with the resolved pc/taken/target; the update is registered on the
//     next posedge and is visible to predictions from that cycle onward.
module bp_bimodal_btb #(
    parameter int PHT_ENTRIES = 1024,
    parameter int BTB_ENTRIES = 64,
    parameter int TAG_BITS    = 20
) (
    input  logic        clk,
    input  logic        rst,

    // prediction port (combinational read)
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [63:0] pred_pc,
    output logic        pred_taken,
    output logic [63:0] pred_target,
    output logic        pred_hit,

    // update port (registered)
    input  logic        upd_valid,
    input  logic [63:0] upd_pc,
    input  logic        upd_taken,
    input  logic [63:0] upd_target
    /* verilator lint_on UNUSEDSIGNAL */
);

  localparam int PHT_IDX_W = $clog2(PHT_ENTRIES);
  localparam int BTB_IDX_W = $clog2(BTB_ENTRIES);

  logic [1:0] pht [PHT_ENTRIES];
  logic                btb_valid [BTB_ENTRIES];
  logic [TAG_BITS-1:0] btb_tag   [BTB_ENTRIES];
  logic [63:0]         btb_target[BTB_ENTRIES];

  wire [PHT_IDX_W-1:0] pred_pht_idx = pred_pc[PHT_IDX_W+1:2];
  wire [BTB_IDX_W-1:0] pred_btb_idx = pred_pc[BTB_IDX_W+1:2];
  wire [TAG_BITS-1:0]  pred_tag     = pred_pc[BTB_IDX_W+2+:TAG_BITS];

  assign pred_hit    = btb_valid[pred_btb_idx] && (btb_tag[pred_btb_idx] == pred_tag);
  assign pred_taken  = pred_hit && pht[pred_pht_idx][1];
  assign pred_target = btb_target[pred_btb_idx];

  wire [PHT_IDX_W-1:0] upd_pht_idx = upd_pc[PHT_IDX_W+1:2];
  wire [BTB_IDX_W-1:0] upd_btb_idx = upd_pc[BTB_IDX_W+1:2];
  wire [TAG_BITS-1:0]  upd_tag     = upd_pc[BTB_IDX_W+2+:TAG_BITS];

  integer i;
  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < PHT_ENTRIES; i = i + 1) pht[i] <= 2'b01;
      for (i = 0; i < BTB_ENTRIES; i = i + 1) btb_valid[i] <= 1'b0;
    end else if (upd_valid) begin
      // 2-bit saturating counter update
      if (upd_taken) begin
        if (pht[upd_pht_idx] != 2'b11) pht[upd_pht_idx] <= pht[upd_pht_idx] + 2'b01;
      end else begin
        if (pht[upd_pht_idx] != 2'b00) pht[upd_pht_idx] <= pht[upd_pht_idx] - 2'b01;
      end

      if (upd_taken) begin
        btb_valid[upd_btb_idx]  <= 1'b1;
        btb_tag[upd_btb_idx]    <= upd_tag;
        btb_target[upd_btb_idx] <= upd_target;
      end
    end
  end

endmodule
