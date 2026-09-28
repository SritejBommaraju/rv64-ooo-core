// Machine-mode CSR file for ooo_core (Zicsr, no traps yet).
// Read is combinational from `addr`; the write lands on the clock edge the
// CSR instruction issues. ooo_core only dispatches a CSR op into an empty ROB,
// so every CSR access happens in program order with nothing older in flight.
// Unimplemented addresses read as zero and ignore writes.
module csr #(
    parameter logic [63:0] MISA = 64'h8000_0000_0000_0100  // RV64, I
) (
    input  logic        clk,
    input  logic        rst,

    input  logic [11:0] addr,
    output logic [63:0] rdata,

    input  logic        wen,
    input  logic [63:0] wdata,

    input  logic        retire   // one pulse per committed instruction (minstret)
);
    localparam logic [11:0] MSTATUS  = 12'h300, MISA_A   = 12'h301, MIE     = 12'h304,
                            MTVEC    = 12'h305, MSCRATCH = 12'h340, MEPC    = 12'h341,
                            MCAUSE   = 12'h342, MTVAL    = 12'h343, MIP     = 12'h344,
                            MCYCLE   = 12'hB00, MINSTRET = 12'hB02,
                            MVENDOR  = 12'hF11, MARCHID  = 12'hF12, MIMPID  = 12'hF13,
                            MHARTID  = 12'hF14;

    // mstatus: only MIE (3), MPIE (7) are writable; MPP (12:11) reads 3 (M-only core)
    localparam logic [63:0] MSTATUS_WMASK = 64'h0000_0000_0000_0088;
    localparam logic [63:0] MSTATUS_FIXED = 64'h0000_0000_0000_1800;
    // mie/mip: MSIE (3), MTIE (7), MEIE (11)
    localparam logic [63:0] MIE_WMASK     = 64'h0000_0000_0000_0888;

    logic [63:0] mstatus_q, mie_q, mtvec_q, mscratch_q, mepc_q, mcause_q, mtval_q;
    logic [63:0] mcycle_q, minstret_q;

    always_comb begin
        unique case (addr)
            MSTATUS:  rdata = mstatus_q | MSTATUS_FIXED;
            MISA_A:   rdata = MISA;
            MIE:      rdata = mie_q;
            MTVEC:    rdata = mtvec_q;
            MSCRATCH: rdata = mscratch_q;
            MEPC:     rdata = mepc_q;
            MCAUSE:   rdata = mcause_q;
            MTVAL:    rdata = mtval_q;
            MCYCLE:   rdata = mcycle_q;
            MINSTRET: rdata = minstret_q;
            default:  rdata = 64'd0;  // mip, mvendorid, marchid, mimpid, mhartid, unimplemented
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus_q  <= 64'd0;
            mie_q      <= 64'd0;
            mtvec_q    <= 64'd0;
            mscratch_q <= 64'd0;
            mepc_q     <= 64'd0;
            mcause_q   <= 64'd0;
            mtval_q    <= 64'd0;
            mcycle_q   <= 64'd0;
            minstret_q <= 64'd0;
        end else begin
            mcycle_q <= mcycle_q + 64'd1;
            if (retire) minstret_q <= minstret_q + 64'd1;
            if (wen) begin
                unique case (addr)
                    MSTATUS:  mstatus_q  <= wdata & MSTATUS_WMASK;
                    MIE:      mie_q      <= wdata & MIE_WMASK;
                    MTVEC:    mtvec_q    <= {wdata[63:2], 1'b0, wdata[0]};  // direct/vectored
                    MSCRATCH: mscratch_q <= wdata;
                    MEPC:     mepc_q     <= {wdata[63:2], 2'b00};           // no C: IALIGN=32
                    MCAUSE:   mcause_q   <= wdata;
                    MTVAL:    mtval_q    <= wdata;
                    MCYCLE:   mcycle_q   <= wdata;
                    MINSTRET: minstret_q <= wdata;
                    default: ;
                endcase
            end
        end
    end

    // verilator lint_off UNUSED
    wire unused = |{MVENDOR, MARCHID, MIMPID, MHARTID, MIP};
    // verilator lint_on UNUSED
endmodule
