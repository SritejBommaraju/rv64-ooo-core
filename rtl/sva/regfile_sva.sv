// Assertions bound into regfile. Uses only regfile's ports plus the public regs array.
module regfile_sva (
    input  logic        clk,
    input  logic [4:0]  rs1, rs2, rd,
    input  logic [63:0] wdata,
    input  logic        wen,
    input  logic [63:0] regs [0:31],
    input  logic [63:0] rdata1, rdata2
);
    // x0 reads as zero
    assert property (@(posedge clk) rs1 == 5'd0 |-> rdata1 == 64'd0)
        else $fatal(1, "rdata1_zero_on_x0");
    assert property (@(posedge clk) rs2 == 5'd0 |-> rdata2 == 64'd0)
        else $fatal(1, "rdata2_zero_on_x0");

    // x0 storage never changes
    assert property (@(posedge clk) regs[0] == 64'd0)
        else $fatal(1, "regs0_always_zero");

    // a write to a non-x0 dest lands next cycle
    assert property (@(posedge clk) (wen && rd != 5'd0) |=> regs[$past(rd)] == $past(wdata))
        else $fatal(1, "write_takes_effect");

    // with no write, no entry moves
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin : g_stable
            assert property (@(posedge clk) !wen |=> $stable(regs[i]))
                else $fatal(1, "regs_stable_when_not_wen");
        end
    endgenerate

    // read ports mirror the array for non-x0 sources
    assert property (@(posedge clk) rs1 != 5'd0 |-> rdata1 == regs[rs1])
        else $fatal(1, "rdata1_matches_regs");
    assert property (@(posedge clk) rs2 != 5'd0 |-> rdata2 == regs[rs2])
        else $fatal(1, "rdata2_matches_regs");
endmodule
