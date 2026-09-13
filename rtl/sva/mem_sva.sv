// Assertions bound into mem, checking that stores land at the right byte offsets.
module mem_sva (
    input  logic        clk,
    input  logic [63:0] dwdata,
    input  logic        dwen,
    input  logic [2:0]  dfunct3,
    input  logic [15:0] da,
    input  logic [7:0] bytes [0:65535]
);
    // byte store (SB)
    assert property (@(posedge clk) (dwen && dfunct3 == 3'h0) |=> bytes[$past(da)] == $past(dwdata[7:0]))
        else $fatal(1, "sb_writes_byte");

    // doubleword store (SD), little-endian
    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : g_sd
            assert property (@(posedge clk)
                (dwen && dfunct3 == 3'h3) |=> bytes[$past(da) + i] == $past(dwdata[8*i +: 8]))
                else $fatal(1, "sd_writes_bytes_le");
        end
    endgenerate

    // no store means no change at the last-touched address; da itself moves every
    // cycle (it's just the current dmem addr), so latch it only when a write occurs
    logic [15:0] last_waddr;
    logic        has_written;
    always_ff @(posedge clk) begin
        if (dwen) begin
            last_waddr  <= da;
            has_written <= 1'b1;
        end
    end

    assert property (@(posedge clk) disable iff (!has_written)
        !dwen |=> $stable(bytes[last_waddr]))
        else $fatal(1, "no_write_no_change");
endmodule
