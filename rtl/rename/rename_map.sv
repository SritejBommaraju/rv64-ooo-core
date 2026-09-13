// rename_map: 32-entry architectural -> physical register map.
// 4 read ports (rs1/rs2 for 2 slots) + 2 read ports for the destinations' old
// mapping (needed to produce prev_prd), 2 write ports, x0 fixed to p0 forever.
// N_CKPT full-map snapshots, saved/restored by id for mispredict recovery.
module rename_map #(
    parameter int N_CKPT = 8
) (
    input  logic clk,
    input  logic rst,

    input  logic [4:0] rs1_0,
    input  logic [4:0] rs2_0,
    input  logic [4:0] rs1_1,
    input  logic [4:0] rs2_1,
    input  logic [4:0] rd0,
    input  logic [4:0] rd1,
    output logic [6:0] prs1_0,
    output logic [6:0] prs2_0,
    output logic [6:0] prs1_1,
    output logic [6:0] prs2_1,
    output logic [6:0] old_prd0,
    output logic [6:0] old_prd1,

    input  logic       w_en0,
    input  logic [4:0] w_arch0,
    input  logic [6:0] w_prd0,
    input  logic       w_en1,
    input  logic [4:0] w_arch1,
    input  logic [6:0] w_prd1,

    // slot0/slot1 checkpoint snapshots (slot1 sees slot0's own write already applied)
    input  logic                        ckpt_save0,
    input  logic [$clog2(N_CKPT) - 1:0] ckpt_save_id0,
    input  logic                        ckpt_save1,
    input  logic [$clog2(N_CKPT) - 1:0] ckpt_save_id1,

    input  logic                        restore_valid,
    input  logic [$clog2(N_CKPT) - 1:0] restore_id
);

  logic [6:0] map_[32];
  logic [6:0] ckpt_mem[N_CKPT][32];

  assign prs1_0   = map_[rs1_0];
  assign prs2_0   = map_[rs2_0];
  assign prs1_1   = map_[rs1_1];
  assign prs2_1   = map_[rs2_1];
  assign old_prd0 = map_[rd0];
  assign old_prd1 = map_[rd1];

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < 32; i++) map_[i] <= 7'(i);
    end else if (restore_valid) begin
      for (int i = 0; i < 32; i++) map_[i] <= ckpt_mem[restore_id][i];
    end else begin
      logic [6:0] nxt0[32];
      logic [6:0] nxt1[32];
      for (int i = 0; i < 32; i++) nxt0[i] = map_[i];
      if (w_en0 && (w_arch0 != 5'd0)) nxt0[w_arch0] = w_prd0;
      for (int i = 0; i < 32; i++) nxt1[i] = nxt0[i];
      if (w_en1 && (w_arch1 != 5'd0)) nxt1[w_arch1] = w_prd1;

      for (int i = 0; i < 32; i++) map_[i] <= nxt1[i];
      if (ckpt_save0) for (int i = 0; i < 32; i++) ckpt_mem[ckpt_save_id0][i] <= nxt0[i];
      if (ckpt_save1) for (int i = 0; i < 32; i++) ckpt_mem[ckpt_save_id1][i] <= nxt1[i];
    end
  end

endmodule
