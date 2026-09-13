// prf: 64 x 64-bit physical register file, 4 read ports + 2 write ports, p0 reads as zero.
module prf (
    input  logic        clk,

    input  logic [6:0]  raddr0,
    input  logic [6:0]  raddr1,
    input  logic [6:0]  raddr2,
    input  logic [6:0]  raddr3,
    output logic [63:0] rdata0,
    output logic [63:0] rdata1,
    output logic [63:0] rdata2,
    output logic [63:0] rdata3,

    input  logic        wen0,
    input  logic [6:0]  waddr0,
    input  logic [63:0] wdata0,
    input  logic        wen1,
    input  logic [6:0]  waddr1,
    input  logic [63:0] wdata1
);

  logic [63:0] regs[64];

  assign rdata0 = (raddr0 == 7'd0) ? 64'd0 : regs[raddr0[5:0]];
  assign rdata1 = (raddr1 == 7'd0) ? 64'd0 : regs[raddr1[5:0]];
  assign rdata2 = (raddr2 == 7'd0) ? 64'd0 : regs[raddr2[5:0]];
  assign rdata3 = (raddr3 == 7'd0) ? 64'd0 : regs[raddr3[5:0]];

  always_ff @(posedge clk) begin
    if (wen0 && (waddr0 != 7'd0)) regs[waddr0[5:0]] <= wdata0;
    if (wen1 && (waddr1 != 7'd0)) regs[waddr1[5:0]] <= wdata1;
  end

endmodule
