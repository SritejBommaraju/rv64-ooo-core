// Assertions bound into core, checking PC generation and mem-request legality.
module core_sva (
    input logic        clk, rst,
    input logic [63:0] pc, pc_next, imem_addr, dmem_addr,
    input logic        dmem_wen,
    input logic        is_store, is_load, is_jal, is_jalr, is_branch,
    input logic [63:0] imm
);
    assert property (@(posedge clk) imem_addr == pc)
        else $fatal(1, "imem_addr_follows_pc");

    assert property (@(posedge clk) pc[1:0] == 2'b00)
        else $fatal(1, "pc_aligned_no_c_ext");

    assert property (@(posedge clk) $past(rst) |-> pc == 64'd0)
        else $fatal(1, "pc_zero_after_reset");

    assert property (@(posedge clk) disable iff (rst)
        !(is_jal || is_jalr || is_branch) |-> pc_next == pc + 64'd4)
        else $fatal(1, "pc_next_sequential");

    assert property (@(posedge clk) disable iff (rst)
        is_jal |-> pc_next == pc + imm)
        else $fatal(1, "pc_next_jal");

    assert property (@(posedge clk) disable iff (rst)
        is_jalr |-> pc_next[0] == 1'b0)
        else $fatal(1, "pc_next_jalr_aligned");

    assert property (@(posedge clk) disable iff (rst)
        dmem_wen |-> is_store)
        else $fatal(1, "dmem_wen_implies_store");

    assert property (@(posedge clk) disable iff (rst)
        !(is_load && is_store))
        else $fatal(1, "load_store_mutex");

    assert property (@(posedge clk) disable iff (rst)
        !$isunknown(pc))
        else $fatal(1, "pc_never_unknown");

    assert property (@(posedge clk) disable iff (rst)
        (is_load || is_store) |-> !$isunknown(dmem_addr))
        else $fatal(1, "dmem_addr_known_on_access");
endmodule
