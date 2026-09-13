// rename: 2-wide rename stage wiring rename_map + free_list + a small in-order
// checkpoint-id allocator (N_CKPT slots) for branch/mispredict recovery.
// Intra-group hazards: slot1 forwards slot0's freshly allocated prd for
// rs1/rs2 matches on slot0.rd, and when slot0.rd == slot1.rd the map ends up
// pointing at slot1's prd while slot0's prd becomes slot1's prev_prd.
module rename #(
    parameter int N_CKPT = 8
) (
    input  logic clk,
    input  logic rst,

    input  logic       valid0,
    input  logic [4:0] rs1_0,
    input  logic [4:0] rs2_0,
    input  logic [4:0] rd0,
    input  logic       is_branch0,
    input  logic       ckpt_take0,
    output logic [6:0] prs1_0,
    output logic [6:0] prs2_0,
    output logic [6:0] prd0,
    output logic [6:0] prev_prd0,
    output logic [$clog2(N_CKPT)-1:0] ckpt_id0,
    output logic       rename_ready0,

    input  logic       valid1,
    input  logic [4:0] rs1_1,
    input  logic [4:0] rs2_1,
    input  logic [4:0] rd1,
    input  logic       is_branch1,
    input  logic       ckpt_take1,
    output logic [6:0] prs1_1,
    output logic [6:0] prs2_1,
    output logic [6:0] prd1,
    output logic [6:0] prev_prd1,
    output logic [$clog2(N_CKPT)-1:0] ckpt_id1,
    output logic       rename_ready1,

    input  logic                       restore_valid,
    input  logic [$clog2(N_CKPT)-1:0]  restore_ckpt_id,

    input  logic       commit_valid0,
    input  logic [6:0] commit_prev_prd0,
    input  logic       commit_ckpt_release0,
    input  logic       commit_valid1,
    input  logic [6:0] commit_prev_prd1,
    input  logic       commit_ckpt_release1,

    output logic [5:0] free_count,
    output logic [3:0] ckpt_free_count
);

  localparam int CKPT_W = $clog2(N_CKPT);

  // ---- checkpoint-id allocator: head + outstanding count, no explicit tail needed ----
  logic [CKPT_W-1:0] ckpt_head;
  logic [CKPT_W:0]   ckpt_count;

  assign ckpt_free_count = 4'(N_CKPT) - 4'(ckpt_count);

  wire needs_prd0 = valid0 && (rd0 != 5'd0);
  wire needs_prd1 = valid1 && (rd1 != 5'd0);

  wire want_ckpt0 = valid0 && is_branch0 && ckpt_take0;
  wire want_ckpt1 = valid1 && is_branch1 && ckpt_take1;
  wire [1:0] needed_ckpts = (want_ckpt0 ? 2'd1 : 2'd0) + (want_ckpt1 ? 2'd1 : 2'd0);

  wire preg_ok  = free_count >= 6'd2;
  wire ckpt_ok  = ckpt_free_count >= {2'd0, needed_ckpts};
  wire bundle_ready = preg_ok && ckpt_ok;

  assign rename_ready0 = bundle_ready;
  assign rename_ready1 = bundle_ready;

  wire alloc_en0 = needs_prd0 && bundle_ready;
  wire alloc_en1 = needs_prd1 && bundle_ready;
  wire grant_ckpt0 = want_ckpt0 && bundle_ready && !restore_valid;
  wire grant_ckpt1 = want_ckpt1 && bundle_ready && !restore_valid;

  wire [CKPT_W:0] release_count = {3'd0, (commit_valid0 && commit_ckpt_release0)} +
                                   {3'd0, (commit_valid1 && commit_ckpt_release1)};
  wire [CKPT_W:0] count_after_release = ckpt_count - release_count;
  wire [CKPT_W:0] count_after0 = count_after_release + (grant_ckpt0 ? {{CKPT_W{1'b0}},1'b1} : '0);
  wire [CKPT_W:0] count_after1 = count_after0 + (grant_ckpt1 ? {{CKPT_W{1'b0}},1'b1} : '0);
  wire [CKPT_W-1:0] head_after0 = ckpt_head + (grant_ckpt0 ? {{CKPT_W-1{1'b0}},1'b1} : '0);
  wire [CKPT_W-1:0] head_after1 = head_after0 + (grant_ckpt1 ? {{CKPT_W-1{1'b0}},1'b1} : '0);

  assign ckpt_id0 = ckpt_head;
  assign ckpt_id1 = head_after0;

  // checkpoints granted since restore_ckpt_id's own grant, now being undone (id
  // itself is the pointer value at grant time, so no separate saved-head is needed)
  wire [CKPT_W-1:0] undone_ckpts = ckpt_head - restore_ckpt_id;

  always_ff @(posedge clk) begin
    if (rst) begin
      ckpt_head  <= '0;
      ckpt_count <= '0;
    end else begin
      if (restore_valid) begin
        ckpt_head  <= restore_ckpt_id;
        // ckpt_count tracks *outstanding* ids, so undone (discarded) ones subtract
        ckpt_count <= count_after_release - {1'b0, undone_ckpts};
      end else begin
        ckpt_head  <= head_after1;
        ckpt_count <= count_after1;
      end
    end
  end

  // ---- free list ----
  logic [6:0] alloc0, alloc1;

  free_list #(.NUM_PREGS(64), .ARCH_REGS(32), .N_CKPT(N_CKPT)) u_free_list (
      .clk(clk), .rst(rst),
      .alloc_en0(alloc_en0), .alloc_en1(alloc_en1),
      .alloc_preg0(alloc0), .alloc_preg1(alloc1),
      .free_en0(commit_valid0 && (commit_prev_prd0 != 7'd0)), .free_preg0(commit_prev_prd0),
      .free_en1(commit_valid1 && (commit_prev_prd1 != 7'd0)), .free_preg1(commit_prev_prd1),
      .free_count(free_count),
      .ckpt_save0(grant_ckpt0), .ckpt_save_id0(ckpt_id0),
      .ckpt_save1(grant_ckpt1), .ckpt_save_id1(ckpt_id1),
      .restore_valid(restore_valid), .restore_id(restore_ckpt_id)
  );

  // ---- rename map ----
  logic [6:0] raw_prs1_0, raw_prs2_0, raw_prs1_1, raw_prs2_1, raw_old0, raw_old1;

  rename_map #(.N_CKPT(N_CKPT)) u_rename_map (
      .clk(clk), .rst(rst),
      .rs1_0(rs1_0), .rs2_0(rs2_0), .rs1_1(rs1_1), .rs2_1(rs2_1),
      .rd0(rd0), .rd1(rd1),
      .prs1_0(raw_prs1_0), .prs2_0(raw_prs2_0), .prs1_1(raw_prs1_1), .prs2_1(raw_prs2_1),
      .old_prd0(raw_old0), .old_prd1(raw_old1),
      .w_en0(alloc_en0), .w_arch0(rd0), .w_prd0(alloc0),
      .w_en1(alloc_en1), .w_arch1(rd1), .w_prd1(alloc1),
      .ckpt_save0(grant_ckpt0), .ckpt_save_id0(ckpt_id0),
      .ckpt_save1(grant_ckpt1), .ckpt_save_id1(ckpt_id1),
      .restore_valid(restore_valid), .restore_id(restore_ckpt_id)
  );

  // ---- intra-group forwarding ----
  wire same_rd_hazard = needs_prd0 && valid1 && (rd1 == rd0);

  assign prs1_0 = raw_prs1_0;
  assign prs2_0 = raw_prs2_0;
  assign prs1_1 = (needs_prd0 && (rs1_1 == rd0)) ? alloc0 : raw_prs1_1;
  assign prs2_1 = (needs_prd0 && (rs2_1 == rd0)) ? alloc0 : raw_prs2_1;

  assign prd0 = needs_prd0 ? alloc0 : 7'd0;
  assign prd1 = needs_prd1 ? alloc1 : 7'd0;

  assign prev_prd0 = raw_old0;
  assign prev_prd1 = same_rd_hazard ? alloc0 : raw_old1;

endmodule
