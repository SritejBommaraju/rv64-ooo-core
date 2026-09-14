// Top level: wires ooo_core to ooo_mem. Debug ports pass straight through for the TB.
module ooo_top (
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
    output logic         dbg_wb_alu_valid
);
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;
    logic [63:0] dmem_rd_addr, dmem_rd_data;
    logic        dmem_wr_valid;
    logic [63:0] dmem_wr_addr, dmem_wr_data;
    logic [1:0]  dmem_wr_size;

    ooo_core u_core (
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
        .dbg_wb_alu_valid(dbg_wb_alu_valid)
    );

    ooo_mem u_mem (
        .clk(clk),
        .iaddr(imem_addr), .irdata(imem_rdata),
        .dmem_rd_addr(dmem_rd_addr), .dmem_rd_data(dmem_rd_data),
        .dmem_wr_valid(dmem_wr_valid), .dmem_wr_addr(dmem_wr_addr),
        .dmem_wr_size(dmem_wr_size), .dmem_wr_data(dmem_wr_data)
    );

    // testbench pokes memory contents directly via hierarchical access (u_mem.bytes)
endmodule
