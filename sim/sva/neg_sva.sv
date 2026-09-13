// Deliberately false property proving the assertion machinery is live: test1 reaches pc==8.
module neg_sva (
    input logic clk, rst,
    input logic [63:0] pc
);
    assert property (@(posedge clk) disable iff (rst) pc != 64'd8)
        else $fatal(1, "neg_test_pc_reached_8");
endmodule

bind core neg_sva u_neg_sva (.*);
