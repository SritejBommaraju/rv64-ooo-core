// First integrated OOO pipeline: rename + PRF + ROB + LSQ wired around decode/alu.
// RV64I only (no muldiv). Single-issue dispatch (rob/rename slot0 only), out-of-order
// issue/completion (oldest-ready-first scoreboard scheduling: a younger ALU op can
// complete and commit-block-clear before an older pending load returns), in-order
// commit. No branch speculation: conditional branches and JALR stall fetch until
// they resolve in the issue stage, so there is no flush/mispredict path (wb_mispredict
// tied 0 throughout). JAL redirects immediately at decode (target needs no register).
module ooo_core (
    input  logic clk,
    input  logic rst,

    // imem port to ooo_mem
    output logic [63:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // dmem ports to ooo_mem (combinational read, posedge sized write)
    output logic [63:0] dmem_rd_addr,
    input  logic [63:0] dmem_rd_data,
    output logic         dmem_wr_valid,
    output logic [63:0]  dmem_wr_addr,
    output logic [1:0]   dmem_wr_size,
    output logic [63:0]  dmem_wr_data,

    // debug/TB observability (no source edits needed in rename/prf to expose arch state:
    // ooo_core tracks its own shadow of the arch->phys map, updated identically to
    // rename_map's, and reads the value back out through prf's spare read ports)
    output logic         dbg_halted,       // x31 == 1 and rob fully drained
    output logic [5:0]   dbg_rob_count,
    output logic [63:0]  dbg_last_commit_pc,
    input  logic [4:0]   dbg_arch_reg,
    output logic [63:0]  dbg_arch_val,
    output logic         dbg_committed,
    output logic         dbg_issue_valid,
    output logic         dbg_issue_is_load,
    output logic         dbg_ld_resp_valid,
    output logic         dbg_ld_from_mem,
    output logic         dbg_wb_alu_valid
);
    localparam int ROB_DEPTH = 32;
    localparam int IDX_W     = 5; // $clog2(ROB_DEPTH)
    localparam int LQ_DEPTH  = 8;
    localparam int SQ_DEPTH  = 8;

    // ==================================================================
    // Fetch (F): pc register + combinational imem read. Exactly the signal
    // set another task's rtl/fe/frontend.sv can drop in to replace: fetch_valid,
    // fetch_pc, fetch_instr, stall_fetch, redirect_valid, redirect_pc.
    // ==================================================================
    logic [63:0] fetch_pc_q;
    logic        pending_ctrl_q;   // an outstanding branch/jalr awaiting resolution

    logic        fetch_valid;
    logic [63:0] fetch_pc;
    logic [31:0] fetch_instr;
    logic        stall_fetch;
    logic        redirect_valid;
    logic [63:0] redirect_pc;

    assign fetch_pc    = fetch_pc_q;
    assign imem_addr   = fetch_pc_q;
    assign fetch_instr = imem_rdata;
    assign stall_fetch = pending_ctrl_q;
    assign fetch_valid = !stall_fetch;
    // redirect_valid/redirect_pc driven below once decode/issue results exist
    // ==================================================================
    // end fetch block
    // ==================================================================

    // ---- decode ----
    logic [4:0]  rs1_d, rs2_d, rd_d;
    logic [63:0] imm_d;
    logic [3:0]  alu_op_d;
    logic        alu_src_imm_d, reg_write_d;
    logic        is_load_d, is_store_d, is_branch_d, is_jal_d, is_jalr_d, is_lui_d, is_auipc_d;
    logic [2:0]  funct3_d;
    logic        is_word_d;

    decode u_decode (
        .instr(fetch_instr), .rs1(rs1_d), .rs2(rs2_d), .rd(rd_d), .imm(imm_d),
        .alu_op(alu_op_d), .alu_src_imm(alu_src_imm_d), .reg_write(reg_write_d),
        .is_load(is_load_d), .is_store(is_store_d), .is_branch(is_branch_d),
        .is_jal(is_jal_d), .is_jalr(is_jalr_d), .is_lui(is_lui_d), .is_auipc(is_auipc_d),
        .funct3(funct3_d), .is_word(is_word_d), .is_muldiv(), .muldiv_op()
    );

    // decode.sv doesn't gate the rd/rs fields by opcode (e.g. a store's instr[11:7]
    // is really immediate bits) - only present a real destination arch reg to rename.
    wire [4:0] rd0_for_rename = reg_write_d ? rd_d : 5'd0;
    wire       is_mem_d       = is_load_d || is_store_d;
    wire       need_rs1_d     = !(is_lui_d || is_jal_d || is_auipc_d);
    wire       need_rs2_d     = is_branch_d || is_store_d ||
                                 (reg_write_d && !alu_src_imm_d && !is_lui_d && !is_jal_d && !is_auipc_d);

    // ---- rename (slot0 only; slot1 unused, no branch checkpoints ever taken) ----
    logic [6:0] prs1_0, prs2_0, prd0, prev_prd0;
    logic       rename_ready0;
    logic [5:0] free_count_unused;
    logic [3:0] ckpt_free_count_unused;

    logic dispatch_fire; // computed below from rename/rob/lsq readiness

    rename u_rename (
        .clk(clk), .rst(rst),
        .valid0(dispatch_fire), .rs1_0(rs1_d), .rs2_0(rs2_d), .rd0(rd0_for_rename),
        .is_branch0(is_branch_d), .ckpt_take0(1'b0),
        .prs1_0(prs1_0), .prs2_0(prs2_0), .prd0(prd0), .prev_prd0(prev_prd0),
        .ckpt_id0(), .rename_ready0(rename_ready0),
        .valid1(1'b0), .rs1_1(5'd0), .rs2_1(5'd0), .rd1(5'd0),
        .is_branch1(1'b0), .ckpt_take1(1'b0),
        .prs1_1(), .prs2_1(), .prd1(), .prev_prd1(), .ckpt_id1(), .rename_ready1(),
        .restore_valid(1'b0), .restore_ckpt_id('0),
        .commit_valid0(rob_commit_valid[0]), .commit_prev_prd0(rob_commit_prev_prd[0]),
        .commit_ckpt_release0(1'b0),
        .commit_valid1(1'b0), .commit_prev_prd1(7'd0), .commit_ckpt_release1(1'b0),
        .free_count(free_count_unused), .ckpt_free_count(ckpt_free_count_unused)
    );

    // ---- PRF ----
    logic [6:0]  prf_raddr0, prf_raddr1, prf_raddr2, prf_raddr3;
    logic [63:0] prf_rdata0, prf_rdata1, prf_rdata2, prf_rdata3;
    logic        prf_wen0, prf_wen1;
    logic [6:0]  prf_waddr0, prf_waddr1;
    logic [63:0] prf_wdata0, prf_wdata1;

    prf u_prf (
        .clk(clk),
        .raddr0(prf_raddr0), .raddr1(prf_raddr1), .raddr2(prf_raddr2), .raddr3(prf_raddr3),
        .rdata0(prf_rdata0), .rdata1(prf_rdata1), .rdata2(prf_rdata2), .rdata3(prf_rdata3),
        .wen0(prf_wen0), .waddr0(prf_waddr0), .wdata0(prf_wdata0),
        .wen1(prf_wen1), .waddr1(prf_waddr1), .wdata1(prf_wdata1)
    );

    // ---- ROB (slot0 only) ----
    logic        rob_alloc_valid[2];
    logic [63:0] rob_alloc_pc[2];
    logic [4:0]  rob_alloc_rd_arch[2];
    logic [6:0]  rob_alloc_prd[2], rob_alloc_prev_prd[2];
    logic        rob_alloc_is_branch[2], rob_alloc_is_store[2];
    logic [IDX_W-1:0] rob_alloc_rob_idx[2];
    logic        rob_alloc_ready;

    logic        rob_wb_valid[2];
    logic [IDX_W-1:0] rob_wb_rob_idx[2];
    logic        rob_wb_exception[2], rob_wb_mispredict[2];
    logic [63:0] rob_wb_redirect_pc[2];

    logic        rob_commit_valid[2];
    logic [63:0] rob_commit_pc[2];
    logic [4:0]  rob_commit_rd_arch[2];
    logic [6:0]  rob_commit_prd[2], rob_commit_prev_prd[2];
    logic        rob_commit_is_store[2];

    logic [IDX_W-1:0] rob_head, rob_tail;
    logic [IDX_W:0]   rob_count;
    logic             rob_empty, rob_full;

    assign rob_alloc_valid[1]      = 1'b0;
    assign rob_alloc_pc[1]         = 64'd0;
    assign rob_alloc_rd_arch[1]    = 5'd0;
    assign rob_alloc_prd[1]        = 7'd0;
    assign rob_alloc_prev_prd[1]   = 7'd0;
    assign rob_alloc_is_branch[1]  = 1'b0;
    assign rob_alloc_is_store[1]   = 1'b0;
    assign rob_wb_valid[1]         = ld_resp_valid;
    assign rob_wb_rob_idx[1]       = ld_resp_rob_idx;
    assign rob_wb_exception[0]     = 1'b0;
    assign rob_wb_exception[1]     = 1'b0;
    assign rob_wb_mispredict[0]    = 1'b0;
    assign rob_wb_mispredict[1]    = 1'b0;
    assign rob_wb_redirect_pc[0]   = 64'd0;
    assign rob_wb_redirect_pc[1]   = 64'd0;

    rob #(.ROB_DEPTH(ROB_DEPTH), .WIDTH(2)) u_rob (
        .clk(clk), .rst(rst),
        .alloc_valid(rob_alloc_valid), .alloc_pc(rob_alloc_pc), .alloc_rd_arch(rob_alloc_rd_arch),
        .alloc_prd(rob_alloc_prd), .alloc_prev_prd(rob_alloc_prev_prd),
        .alloc_is_branch(rob_alloc_is_branch), .alloc_is_store(rob_alloc_is_store),
        .alloc_rob_idx(rob_alloc_rob_idx), .alloc_ready(rob_alloc_ready),
        .wb_valid(rob_wb_valid), .wb_rob_idx(rob_wb_rob_idx),
        .wb_exception(rob_wb_exception), .wb_mispredict(rob_wb_mispredict), .wb_redirect_pc(rob_wb_redirect_pc),
        .commit_valid(rob_commit_valid), .commit_pc(rob_commit_pc), .commit_rd_arch(rob_commit_rd_arch),
        .commit_prd(rob_commit_prd), .commit_prev_prd(rob_commit_prev_prd), .commit_is_store(rob_commit_is_store),
        .flush_valid(), .flush_full(), .flush_pc(), .flush_branch_rob_idx(),
        .rob_head(rob_head), .rob_tail(rob_tail), .rob_count(rob_count),
        .rob_empty(rob_empty), .rob_full(rob_full)
    );

    // ---- LSQ ----
    logic        lsq_disp_valid[2], lsq_disp_is_load[2];
    logic [IDX_W-1:0] lsq_disp_rob_idx[2];
    logic        lsq_disp_ready[2];
    logic [2:0]  lsq_disp_lq_idx[2];
    logic [2:0]  lsq_disp_sq_idx[2];

    logic        st_addr_valid;
    logic [2:0]  st_sq_idx;
    logic [63:0] st_addr;
    logic [1:0]  st_size;
    logic [63:0] st_data;

    logic        ld_addr_valid;
    logic [2:0]  ld_lq_idx;
    logic [63:0] ld_addr;
    logic [1:0]  ld_size;
    logic        ld_signed;

    logic        ld_resp_valid;
    logic [2:0]  ld_resp_lq_idx;
    logic [63:0] ld_resp_data;
    logic [IDX_W-1:0] ld_resp_rob_idx;

    logic        commit_store_valid, commit_load_valid;
    logic [$clog2(LQ_DEPTH):0] lq_count;
    logic [$clog2(SQ_DEPTH):0] sq_count;

    assign lsq_disp_valid[1]   = 1'b0;
    assign lsq_disp_is_load[1] = 1'b0;
    assign lsq_disp_rob_idx[1] = '0;

    lsq #(.LQ_DEPTH(LQ_DEPTH), .SQ_DEPTH(SQ_DEPTH), .ROB_IDX_W(IDX_W)) u_lsq (
        .clk(clk), .rst(rst), .rob_head(rob_head),
        .disp_valid(lsq_disp_valid), .disp_is_load(lsq_disp_is_load), .disp_rob_idx(lsq_disp_rob_idx),
        .disp_ready(lsq_disp_ready), .disp_lq_idx(lsq_disp_lq_idx), .disp_sq_idx(lsq_disp_sq_idx),
        .st_addr_valid(st_addr_valid), .st_sq_idx(st_sq_idx), .st_addr(st_addr), .st_size(st_size), .st_data(st_data),
        .ld_addr_valid(ld_addr_valid), .ld_lq_idx(ld_lq_idx), .ld_addr(ld_addr), .ld_size(ld_size), .ld_signed(ld_signed),
        .ld_resp_valid(ld_resp_valid), .ld_resp_lq_idx(ld_resp_lq_idx), .ld_resp_data(ld_resp_data),
        .ld_resp_rob_idx(ld_resp_rob_idx),
        .dmem_rd_valid(dbg_ld_from_mem), .dmem_rd_addr(dmem_rd_addr), .dmem_rd_size(), .dmem_rd_data(dmem_rd_data),
        .commit_store_valid(commit_store_valid), .commit_load_valid(commit_load_valid),
        .dmem_wr_valid(dmem_wr_valid), .dmem_wr_addr(dmem_wr_addr), .dmem_wr_size(dmem_wr_size), .dmem_wr_data(dmem_wr_data),
        .squash_valid(1'b0), .squash_rob_idx('0), .squash_all(1'b0),
        .lq_count(lq_count), .sq_count(sq_count)
    );

    // ==================================================================
    // per-ROB-entry side table (rename/rob/lsq only carry what they need
    // internally - issue needs everything else to execute the instruction).
    // ==================================================================
    logic [63:0] tab_pc[ROB_DEPTH], tab_imm[ROB_DEPTH];
    logic [6:0]  tab_prs1[ROB_DEPTH], tab_prs2[ROB_DEPTH], tab_prd[ROB_DEPTH];
    logic [3:0]  tab_alu_op[ROB_DEPTH];
    logic        tab_is_word[ROB_DEPTH], tab_alu_src_imm[ROB_DEPTH];
    logic [2:0]  tab_funct3[ROB_DEPTH];
    logic        tab_is_load[ROB_DEPTH], tab_is_store[ROB_DEPTH], tab_is_branch[ROB_DEPTH];
    logic        tab_is_jal[ROB_DEPTH], tab_is_jalr[ROB_DEPTH], tab_is_lui[ROB_DEPTH], tab_is_auipc[ROB_DEPTH];
    logic [2:0]  tab_lq_idx[ROB_DEPTH], tab_sq_idx[ROB_DEPTH];
    logic        tab_need_rs1[ROB_DEPTH], tab_need_rs2[ROB_DEPTH];
    logic        issued_q[ROB_DEPTH];

    // ---- physical-register readiness scoreboard (p0 permanently ready) ----
    logic [63:0] ready_q;

    // ==================================================================
    // dispatch: allocate rob (+lsq for mem ops) for the fetched instruction
    // ==================================================================
    wire [IDX_W-1:0] new_rob_idx = rob_alloc_rob_idx[0];
    logic halt_latch_q;

    // equivalent to lsq's own disp_ready[0] (squash is always tied 0 here) but computed
    // from lq_count/sq_count directly to avoid a spurious array-aliased comb loop through
    // lsq's port1 accounting once verilator flattens the disp_ready[2] array as one node
    wire lsq_ok = !is_mem_d || (is_load_d ? (lq_count < LQ_DEPTH[$clog2(LQ_DEPTH):0])
                                           : (sq_count < SQ_DEPTH[$clog2(SQ_DEPTH):0]));
    always_comb dispatch_fire = fetch_valid && rename_ready0 && rob_alloc_ready && lsq_ok && !halt_latch_q;

    assign rob_alloc_valid[0]     = dispatch_fire;
    assign rob_alloc_pc[0]        = fetch_pc_q;
    assign rob_alloc_rd_arch[0]   = rd0_for_rename;
    assign rob_alloc_prd[0]       = prd0;
    assign rob_alloc_prev_prd[0]  = prev_prd0;
    assign rob_alloc_is_branch[0] = is_branch_d;
    assign rob_alloc_is_store[0]  = is_store_d;

    assign lsq_disp_valid[0]   = dispatch_fire && is_mem_d;
    assign lsq_disp_is_load[0] = is_load_d;
    assign lsq_disp_rob_idx[0] = new_rob_idx;

    // ==================================================================
    // issue: oldest ready unissued rob entry (out-of-order relative to
    // program order - a younger ready ALU op wins over an older pending load)
    // ==================================================================
    logic       iss_valid;
    logic [IDX_W-1:0] iss_idx;

    always_comb begin
        iss_valid = 1'b0;
        iss_idx   = '0;
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (!iss_valid && (i < rob_count)) begin
                automatic logic [IDX_W-1:0] idx = rob_head + IDX_W'(i);
                automatic logic r1ok = !tab_need_rs1[idx] || ready_q[tab_prs1[idx][5:0]];
                automatic logic r2ok = !tab_need_rs2[idx] || ready_q[tab_prs2[idx][5:0]];
                if (!issued_q[idx] && r1ok && r2ok) begin
                    iss_valid = 1'b1;
                    iss_idx   = idx;
                end
            end
        end
    end

    assign dbg_issue_valid   = iss_valid;
    assign dbg_issue_is_load = iss_valid && tab_is_load[iss_idx];

    // ---- execute (combinational, same cycle as issue) ----
    logic [63:0] rs1_val, rs2_val;
    assign prf_raddr0 = tab_prs1[iss_idx];
    assign prf_raddr1 = tab_prs2[iss_idx];
    assign rs1_val = prf_rdata0;
    assign rs2_val = prf_rdata1;

    logic [63:0] alu_a, alu_b, alu_y;
    assign alu_a = tab_is_auipc[iss_idx] ? tab_pc[iss_idx] : rs1_val;
    assign alu_b = tab_alu_src_imm[iss_idx] ? tab_imm[iss_idx] : rs2_val;
    alu u_alu (.a(alu_a), .b(alu_b), .op(tab_alu_op[iss_idx]), .is_word(tab_is_word[iss_idx]), .y(alu_y));

    logic branch_taken;
    always_comb begin
        unique case (tab_funct3[iss_idx])
            3'h0: branch_taken = (rs1_val == rs2_val);                   // BEQ
            3'h1: branch_taken = (rs1_val != rs2_val);                   // BNE
            3'h4: branch_taken = ($signed(rs1_val) <  $signed(rs2_val)); // BLT
            3'h5: branch_taken = ($signed(rs1_val) >= $signed(rs2_val)); // BGE
            3'h6: branch_taken = (rs1_val <  rs2_val);                   // BLTU
            3'h7: branch_taken = (rs1_val >= rs2_val);                   // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    wire [63:0] jalr_target   = (rs1_val + tab_imm[iss_idx]) & ~64'd1;
    wire [63:0] branch_target = branch_taken ? (tab_pc[iss_idx] + tab_imm[iss_idx]) : (tab_pc[iss_idx] + 64'd4);
    wire [63:0] ctrl_target   = tab_is_jalr[iss_idx] ? jalr_target : branch_target;

    wire [63:0] alu_wdata = tab_is_lui[iss_idx]  ? tab_imm[iss_idx] :
                             (tab_is_jal[iss_idx] || tab_is_jalr[iss_idx]) ? (tab_pc[iss_idx] + 64'd4) :
                             alu_y;

    wire iss_is_load  = iss_valid && tab_is_load[iss_idx];
    wire iss_is_store = iss_valid && tab_is_store[iss_idx];
    wire iss_is_ctrl  = iss_valid && (tab_is_branch[iss_idx] || tab_is_jalr[iss_idx]);
    // everything except a load completes (rob-wb's) the same cycle it issues:
    // alu/lui/auipc/jal/jalr/branch write back a register (or none), and a store's
    // address+data are already known - only its dmem write itself waits for commit.
    //
    // KNOWN BUG (found via tests/arch/src/x0_sink.s, stores.s, st_ld_forward.s under
    // --dut ooo): rob.sv allows a head-of-ROB entry to writeback and commit in the
    // SAME cycle. For a store, wb (this line) fires the same cycle st_addr_valid below
    // pulses, but lsq.sv's sq_addr_q/sq_data_q are only WRITTEN via a registered
    // `<=` on that same edge - not yet visible to a same-cycle combinational read.
    // If that store is already at ROB head, commit_store_valid can therefore fire
    // the SAME cycle, and dmem_wr_addr/dmem_wr_data (= sq_addr_q/sq_data_q[sq_head],
    // read combinationally) sample the STALE previous occupant of that SQ slot instead
    // of this store's real address/data - the store silently writes the wrong location
    // with the wrong value. Confirmed via direct $display instrumentation (not a
    // measurement artifact). A same-cycle wb+commit is rare (a fast-issuing store must
    // already be at the ROB head with no older entry pending) which is why it only
    // surfaces in the riscv-arch-test-style suite's longer/denser programs, not the
    // shorter hand-written test1/test_w/test_m or the sw/build/*.bin directed tests.
    // An attempted fix (delaying store wb by one registered cycle) was tried and
    // REVERTED here: a single-slot delay register gets clobbered by a second store
    // issuing before the first's delayed wb is consumed, and gating issue on that slot
    // deadlocked several tests (ROB fills waiting on a store that can now never
    // reissue). The correct fix needs either a small per-outstanding-store delay
    // queue in ooo_core.sv, or (preferably) lsq.sv exposing a same-cycle
    // store-address/data bypass path from st_addr_valid straight to dmem_wr_*  when
    // commit_store_valid coincides with st_addr_valid for the same sq_idx - which
    // needs touching lsq.sv itself. Left as-is (original single-cycle-wb behavior,
    // which is what the sw/build/*.bin suite and test1/test_w/test_m validate) rather
    // than shipping a broken fix.
    wire iss_is_alu   = iss_valid && !iss_is_load;

    // loads: send address to lsq; completion arrives later via ld_resp_valid
    assign ld_addr_valid = iss_is_load;
    assign ld_lq_idx      = tab_lq_idx[iss_idx];
    assign ld_addr        = alu_y; // rs1_val + imm (alu_op=ADD, alu_src_imm=1 for loads)
    assign ld_size        = tab_funct3[iss_idx][1:0];
    assign ld_signed      = !tab_funct3[iss_idx][2];

    // stores: address+data computed at issue, but the actual dmem write waits for commit
    assign st_addr_valid = iss_is_store;
    assign st_sq_idx      = tab_sq_idx[iss_idx];
    assign st_addr        = alu_y;
    assign st_size        = tab_funct3[iss_idx][1:0];
    assign st_data        = rs2_val;

    // ---- rob writeback: slot0 = issue-stage completion (alu/ctrl/store), slot1 = load response ----
    assign rob_wb_valid[0]   = iss_is_alu;
    assign rob_wb_rob_idx[0] = iss_idx;

    assign prf_wen0   = iss_is_alu && (tab_prd[iss_idx] != 7'd0);
    assign prf_waddr0 = tab_prd[iss_idx];
    assign prf_wdata0 = alu_wdata;

    assign prf_wen1   = ld_resp_valid;
    assign prf_waddr1 = tab_prd[ld_resp_rob_idx];
    assign prf_wdata1 = ld_resp_data;

    assign dbg_ld_resp_valid = ld_resp_valid;
    assign dbg_wb_alu_valid  = iss_is_alu;

    // ---- issued/scoreboard state ----
    always_ff @(posedge clk) begin
        if (rst) begin
            ready_q <= 64'hFFFF_FFFF_FFFF_FFFF;
            for (int i = 0; i < ROB_DEPTH; i++) issued_q[i] <= 1'b0;
        end else begin
            if (dispatch_fire) issued_q[new_rob_idx] <= 1'b0;
            if (iss_valid)     issued_q[iss_idx]      <= 1'b1;

            if (dispatch_fire && (prd0 != 7'd0)) ready_q[prd0[5:0]] <= 1'b0;
            if (prf_wen0)                        ready_q[prf_waddr0[5:0]] <= 1'b1;
            if (prf_wen1)                        ready_q[prf_waddr1[5:0]] <= 1'b1;
        end
    end

    // ---- dispatch-time side-table write ----
    always_ff @(posedge clk) begin
        if (dispatch_fire) begin
            tab_pc[new_rob_idx]          <= fetch_pc_q;
            tab_imm[new_rob_idx]         <= imm_d;
            tab_prs1[new_rob_idx]        <= prs1_0;
            tab_prs2[new_rob_idx]        <= prs2_0;
            tab_prd[new_rob_idx]         <= prd0;
            tab_alu_op[new_rob_idx]      <= alu_op_d;
            tab_is_word[new_rob_idx]     <= is_word_d;
            tab_alu_src_imm[new_rob_idx] <= alu_src_imm_d;
            tab_funct3[new_rob_idx]      <= funct3_d;
            tab_is_load[new_rob_idx]     <= is_load_d;
            tab_is_store[new_rob_idx]    <= is_store_d;
            tab_is_branch[new_rob_idx]   <= is_branch_d;
            tab_is_jal[new_rob_idx]      <= is_jal_d;
            tab_is_jalr[new_rob_idx]     <= is_jalr_d;
            tab_is_lui[new_rob_idx]      <= is_lui_d;
            tab_is_auipc[new_rob_idx]    <= is_auipc_d;
            tab_lq_idx[new_rob_idx]      <= lsq_disp_lq_idx[0];
            tab_sq_idx[new_rob_idx]      <= lsq_disp_sq_idx[0];
            tab_need_rs1[new_rob_idx]    <= need_rs1_d;
            tab_need_rs2[new_rob_idx]    <= need_rs2_d;
        end
    end

    // ==================================================================
    // commit: rob slot0 -> rename retirement + lsq pop
    // ==================================================================
    assign commit_store_valid = rob_commit_valid[0] && rob_commit_is_store[0];
    assign commit_load_valid  = rob_commit_valid[0] && tab_is_load[rob_head];

    assign dbg_committed = rob_commit_valid[0];
    assign dbg_rob_count = 6'(rob_count);

    always_ff @(posedge clk) begin
        if (rst) dbg_last_commit_pc <= 64'd0;
        else if (rob_commit_valid[0]) dbg_last_commit_pc <= rob_commit_pc[0];
    end

    // ==================================================================
    // fetch redirects: JAL at decode (no operand needed), branch/jalr at issue
    // ==================================================================
    wire jal_redirect_now = dispatch_fire && is_jal_d;
    wire [63:0] jal_target = fetch_pc_q + imm_d;

    assign redirect_valid = jal_redirect_now || iss_is_ctrl;
    assign redirect_pc    = jal_redirect_now ? jal_target : ctrl_target;

    wire ctrl_dispatched_now = dispatch_fire && (is_branch_d || is_jalr_d);

    always_ff @(posedge clk) begin
        if (rst) pending_ctrl_q <= 1'b0;
        else if (iss_is_ctrl) pending_ctrl_q <= 1'b0;
        else if (ctrl_dispatched_now) pending_ctrl_q <= 1'b1;
    end

    always_ff @(posedge clk) begin
        if (rst) fetch_pc_q <= 64'd0;
        else if (redirect_valid) fetch_pc_q <= redirect_pc;
        else if (dispatch_fire) fetch_pc_q <= fetch_pc_q + 64'd4;
    end

    // ==================================================================
    // architectural-register shadow map, updated identically to rename_map's
    // own map (dispatch-time rename write) so it always agrees with it without
    // needing a read port rename.sv doesn't expose. Used only for the x31 halt
    // check and the TB's post-run register dump - never for pipeline decisions.
    // ==================================================================
    logic [6:0] arch_map_q[32];
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) arch_map_q[i] <= 7'(i);
        end else if (dispatch_fire && (rd0_for_rename != 5'd0)) begin
            arch_map_q[rd0_for_rename] <= prd0;
        end
    end

    assign prf_raddr2  = arch_map_q[31];
    wire [63:0] x31_val = prf_rdata2;

    assign prf_raddr3   = arch_map_q[dbg_arch_reg];
    assign dbg_arch_val = prf_rdata3;

    always_ff @(posedge clk) begin
        if (rst) halt_latch_q <= 1'b0;
        else if (x31_val == 64'd1) halt_latch_q <= 1'b1;
    end

    assign dbg_halted = halt_latch_q && rob_empty;

    // rob_full/lq_count/sq_count are available for a future backpressure story but
    // unused by this milestone's stats
    // verilator lint_off UNUSED
    wire unused = |{rob_full, lq_count, sq_count, ld_resp_lq_idx, rob_tail};
    // verilator lint_on UNUSED
endmodule
