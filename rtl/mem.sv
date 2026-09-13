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
    logic [7:0] bytes [0:DEPTH_BYTES-1];

    assign irdata = {bytes[iaddr+3], bytes[iaddr+2], bytes[iaddr+1], bytes[iaddr]};

    assign drdata = {bytes[daddr+7], bytes[daddr+6], bytes[daddr+5], bytes[daddr+4],
                      bytes[daddr+3], bytes[daddr+2], bytes[daddr+1], bytes[daddr]};

    always_ff @(posedge clk) begin
        if (dwen) begin
            unique case (dfunct3)
                3'h0: bytes[daddr] <= dwdata[7:0];                                   // SB
                3'h1: {bytes[daddr+1], bytes[daddr]} <= dwdata[15:0];                // SH
                3'h2: {bytes[daddr+3], bytes[daddr+2], bytes[daddr+1], bytes[daddr]} <= dwdata[31:0]; // SW
                3'h3: {bytes[daddr+7], bytes[daddr+6], bytes[daddr+5], bytes[daddr+4],
                       bytes[daddr+3], bytes[daddr+2], bytes[daddr+1], bytes[daddr]} <= dwdata; // SD
                default: ;
            endcase
        end
    end
endmodule
