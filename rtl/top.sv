module top (
    input logic clk,
    input logic rst
);
    logic [63:0] imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
    logic [31:0] imem_rdata;
    logic        dmem_wen;
    logic [2:0]  dmem_funct3;

    core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wen(dmem_wen),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata)
    );

    mem u_mem (
        .clk(clk), .iaddr(imem_addr), .irdata(imem_rdata),
        .daddr(dmem_addr), .dwdata(dmem_wdata), .dwen(dmem_wen),
        .dfunct3(dmem_funct3), .drdata(dmem_rdata)
    );

    // testbench pokes memory contents directly via hierarchical access
endmodule
