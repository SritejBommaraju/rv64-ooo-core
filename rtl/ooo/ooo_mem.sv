// Byte-addressable memory backing both imem and the LSQ's dmem ports for ooo_core.
// dmem read is combinational (matches lsq.sv's same-cycle dmem_rd contract); write is
// posedge, sized 0=B,1=H,2=W,3=D (same size encoding lsq uses for both ld/st).
module ooo_mem #(parameter DEPTH_BYTES = 65536) (
    input  logic        clk,

    input  logic [63:0] iaddr,
    output logic [31:0] irdata,

    input  logic [63:0] dmem_rd_addr,
    output logic [63:0] dmem_rd_data,

    input  logic         dmem_wr_valid,
    input  logic [63:0]  dmem_wr_addr,
    input  logic [1:0]   dmem_wr_size,
    input  logic [63:0]  dmem_wr_data
);
    // addresses alias modulo DEPTH_BYTES (must be a power of two), so a program linked
    // at e.g. 0x8000_0000 runs unmodified from byte 0 of this array.
    localparam int AW = $clog2(DEPTH_BYTES);

    logic [7:0] bytes [0:DEPTH_BYTES-1] /* verilator public */;
    logic [AW-1:0] ia, da;
    assign ia = iaddr[AW-1:0];
    assign da = dmem_rd_addr[AW-1:0];

    assign irdata = {bytes[ia+3], bytes[ia+2], bytes[ia+1], bytes[ia]};

    // always read 8 bytes; lsq's extend_f only looks at the low size-bits of this, so
    // no need to size the read itself.
    assign dmem_rd_data = {bytes[da+7], bytes[da+6], bytes[da+5], bytes[da+4],
                            bytes[da+3], bytes[da+2], bytes[da+1], bytes[da]};

    logic [AW-1:0] wa;
    assign wa = dmem_wr_addr[AW-1:0];

    always_ff @(posedge clk) begin
        if (dmem_wr_valid) begin
            unique case (dmem_wr_size)
                2'h0: bytes[wa] <= dmem_wr_data[7:0];                                     // B
                2'h1: {bytes[wa+1], bytes[wa]} <= dmem_wr_data[15:0];                      // H
                2'h2: {bytes[wa+3], bytes[wa+2], bytes[wa+1], bytes[wa]} <= dmem_wr_data[31:0]; // W
                2'h3: {bytes[wa+7], bytes[wa+6], bytes[wa+5], bytes[wa+4],
                       bytes[wa+3], bytes[wa+2], bytes[wa+1], bytes[wa]} <= dmem_wr_data;  // D
            endcase
        end
    end
endmodule
