// Unified byte-addressable memory backing both imem and dmem ports for sim.
module mem #(parameter DEPTH_BYTES = 65536) (
    input  logic        clk,
    input  logic [63:0] iaddr,
    output logic [31:0] irdata,
    input  logic [63:0] daddr,
    input  logic [63:0] dwdata,
    input  logic        dwen,
    input  logic [2:0]  dfunct3,
    output logic [63:0] drdata
);
    logic [7:0] bytes [0:DEPTH_BYTES-1] /* verilator public */;
    logic [15:0] ia, da; // truncated indices, DEPTH_BYTES fits in 16 bits
    assign ia = iaddr[15:0];
    assign da = daddr[15:0];

    assign irdata = {bytes[ia+3], bytes[ia+2], bytes[ia+1], bytes[ia]};

    assign drdata = {bytes[da+7], bytes[da+6], bytes[da+5], bytes[da+4],
                      bytes[da+3], bytes[da+2], bytes[da+1], bytes[da]};

    always_ff @(posedge clk) begin
        if (dwen) begin
            unique case (dfunct3)
                3'h0: bytes[da] <= dwdata[7:0];                                   // SB
                3'h1: {bytes[da+1], bytes[da]} <= dwdata[15:0];                   // SH
                3'h2: {bytes[da+3], bytes[da+2], bytes[da+1], bytes[da]} <= dwdata[31:0]; // SW
                3'h3: {bytes[da+7], bytes[da+6], bytes[da+5], bytes[da+4],
                       bytes[da+3], bytes[da+2], bytes[da+1], bytes[da]} <= dwdata; // SD
                default: ;
            endcase
        end
    end
endmodule
