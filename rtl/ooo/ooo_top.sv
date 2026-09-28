// Top level: wires ooo_core to ooo_mem. Debug ports pass straight through for the TB.
module ooo_top #(
    parameter logic [63:0] RESET_PC  = 64'd0,
    parameter int          MEM_BYTES = 65536
) (
    input logic clk,
    input logic rst,

    output logic         dbg_halted,
    output logic [5:0]   dbg_rob_count,
    output logic [63:0]  dbg_last_commit_pc,
    input  logic [4:0]   dbg_arch_reg,
    output logic [63:0]  dbg_arch_val,
    output logic         dbg_committed,
    output logic         dbg_issue_valid,
    output logic         dbg_issue_is_load,
    output logic         dbg_ld_resp_valid,
    output logic         dbg_ld_from_mem,
    output logic         dbg_wb_alu_valid,

    output logic         rvfi_valid,
    output logic [63:0]  rvfi_order,
    output logic [31:0]  rvfi_insn,
    output logic         rvfi_trap,
    output logic         rvfi_halt,
    output logic         rvfi_intr,
    output logic [1:0]   rvfi_mode,
    output logic [1:0]   rvfi_ixl,
    output logic [4:0]   rvfi_rs1_addr,
    output logic [4:0]   rvfi_rs2_addr,
    output logic [63:0]  rvfi_rs1_rdata,
    output logic [63:0]  rvfi_rs2_rdata,
    output logic [4:0]   rvfi_rd_addr,
    output logic [63:0]  rvfi_rd_wdata,
    output logic [63:0]  rvfi_pc_rdata,
    output logic [63:0]  rvfi_pc_wdata,
    output logic [63:0]  rvfi_mem_addr,
    output logic [7:0]   rvfi_mem_rmask,
    output logic [7:0]   rvfi_mem_wmask,
    output logic [63:0]  rvfi_mem_rdata,
    output logic [63:0]  rvfi_mem_wdata
);
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;
    logic [63:0] dmem_rd_addr, dmem_rd_data;
    logic        dmem_wr_valid;
    logic [63:0] dmem_wr_addr, dmem_wr_data;
    logic [1:0]  dmem_wr_size;

    ooo_core #(.RESET_PC(RESET_PC)) u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_rd_addr(dmem_rd_addr), .dmem_rd_data(dmem_rd_data),
        .dmem_wr_valid(dmem_wr_valid), .dmem_wr_addr(dmem_wr_addr),
        .dmem_wr_size(dmem_wr_size), .dmem_wr_data(dmem_wr_data),
        .dbg_halted(dbg_halted), .dbg_rob_count(dbg_rob_count),
        .dbg_last_commit_pc(dbg_last_commit_pc),
        .dbg_arch_reg(dbg_arch_reg), .dbg_arch_val(dbg_arch_val),
        .dbg_committed(dbg_committed),
        .dbg_issue_valid(dbg_issue_valid), .dbg_issue_is_load(dbg_issue_is_load),
        .dbg_ld_resp_valid(dbg_ld_resp_valid), .dbg_ld_from_mem(dbg_ld_from_mem),
        .dbg_wb_alu_valid(dbg_wb_alu_valid),
        .rvfi_valid(rvfi_valid), .rvfi_order(rvfi_order), .rvfi_insn(rvfi_insn),
        .rvfi_trap(rvfi_trap), .rvfi_halt(rvfi_halt), .rvfi_intr(rvfi_intr),
        .rvfi_mode(rvfi_mode), .rvfi_ixl(rvfi_ixl),
        .rvfi_rs1_addr(rvfi_rs1_addr), .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata), .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr), .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata), .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_mem_addr(rvfi_mem_addr), .rvfi_mem_rmask(rvfi_mem_rmask), .rvfi_mem_wmask(rvfi_mem_wmask),
        .rvfi_mem_rdata(rvfi_mem_rdata), .rvfi_mem_wdata(rvfi_mem_wdata)
    );

    ooo_mem #(.DEPTH_BYTES(MEM_BYTES)) u_mem (
        .clk(clk),
        .iaddr(imem_addr), .irdata(imem_rdata),
        .dmem_rd_addr(dmem_rd_addr), .dmem_rd_data(dmem_rd_data),
        .dmem_wr_valid(dmem_wr_valid), .dmem_wr_addr(dmem_wr_addr),
        .dmem_wr_size(dmem_wr_size), .dmem_wr_data(dmem_wr_data)
    );

    // testbench pokes memory contents directly via hierarchical access (u_mem.bytes)
endmodule
