module regfile (
    input  logic        clk,
    input  logic [4:0]  rs1, rs2, rd,
    input  logic [63:0] wdata,
    input  logic        wen,
    output logic [63:0] rdata1, rdata2
);
    logic [63:0] regs [0:31];

    assign rdata1 = (rs1 == 5'd0) ? 64'd0 : regs[rs1];
    assign rdata2 = (rs2 == 5'd0) ? 64'd0 : regs[rs2];

    always_ff @(posedge clk) begin
        if (wen && rd != 5'd0) regs[rd] <= wdata;
    end
endmodule
