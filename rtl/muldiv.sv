// Combinational M-extension unit (single-cycle for this seed core).
// An iterative multi-cycle divider is future work once the pipeline exists.
module muldiv (
    input  logic [63:0] a, b,
    input  logic [2:0]  op,       // = funct3: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
    input  logic        is_word,  // W-variant: 32-bit inputs/op, sign-extend result
    output logic [63:0] y
);
    logic signed [63:0] as64, bs64;
    assign as64 = $signed(a);
    assign bs64 = $signed(b);

    logic signed [31:0] as32, bs32;
    assign as32 = a[31:0];
    assign bs32 = b[31:0];

    // 128-bit products for MULH/MULHSU/MULHU (64-bit only; no W form exists for these)
    logic signed [127:0] sa128, sb128;
    logic        [127:0] ua128, ub128;
    assign sa128 = {{64{a[63]}}, a};
    assign sb128 = {{64{b[63]}}, b};
    assign ua128 = {64'd0, a};
    assign ub128 = {64'd0, b};

    logic [127:0] mulh_ss, mulh_su, mulh_uu;
    assign mulh_ss = sa128 * sb128;
    assign mulh_su = sa128 * $signed(ub128); // ub128's top bit is always 0, so this cast is value-preserving
    assign mulh_uu = ua128 * ub128;

    // 64-bit divide/remainder with divide-by-zero and signed-overflow corner cases
    logic [63:0] div_u64, rem_u64, div_s64, rem_s64;
    always_comb begin
        if (b == 64'd0) begin
            div_u64 = 64'hFFFF_FFFF_FFFF_FFFF; rem_u64 = a;
        end else begin
            div_u64 = a / b; rem_u64 = a % b;
        end
        if (b == 64'd0) begin
            div_s64 = 64'hFFFF_FFFF_FFFF_FFFF; rem_s64 = a;
        end else if (a == 64'h8000_0000_0000_0000 && b == 64'hFFFF_FFFF_FFFF_FFFF) begin
            div_s64 = a; rem_s64 = 64'd0;
        end else begin
            div_s64 = as64 / bs64; rem_s64 = as64 % bs64;
        end
    end

    // 32-bit (W) divide/remainder with the same corner cases
    logic [31:0] div_u32, rem_u32, div_s32, rem_s32;
    always_comb begin
        if (b[31:0] == 32'd0) begin
            div_u32 = 32'hFFFF_FFFF; rem_u32 = a[31:0];
        end else begin
            div_u32 = a[31:0] / b[31:0]; rem_u32 = a[31:0] % b[31:0];
        end
        if (b[31:0] == 32'd0) begin
            div_s32 = 32'hFFFF_FFFF; rem_s32 = a[31:0];
        end else if (as32 == 32'h8000_0000 && bs32 == 32'hFFFF_FFFF) begin
            div_s32 = as32; rem_s32 = 32'd0;
        end else begin
            div_s32 = as32 / bs32; rem_s32 = as32 % bs32;
        end
    end

    logic [63:0] mul_full;
    assign mul_full = a * b; // low 64 bits of the product; low 32 bits are correct for MULW too

    always_comb begin
        if (is_word) begin
            unique case (op)
                3'h0: y = {{32{mul_full[31]}}, mul_full[31:0]};   // MULW
                3'h4: y = {{32{div_s32[31]}},  div_s32};           // DIVW
                3'h5: y = {{32{div_u32[31]}},  div_u32};           // DIVUW
                3'h6: y = {{32{rem_s32[31]}},  rem_s32};           // REMW
                3'h7: y = {{32{rem_u32[31]}},  rem_u32};           // REMUW
                default: y = 64'd0;
            endcase
        end else begin
            unique case (op)
                3'h0: y = mul_full;                  // MUL
                3'h1: y = mulh_ss[127:64];            // MULH
                3'h2: y = mulh_su[127:64];            // MULHSU
                3'h3: y = mulh_uu[127:64];            // MULHU
                3'h4: y = div_s64;                    // DIV
                3'h5: y = div_u64;                    // DIVU
                3'h6: y = rem_s64;                    // REM
                3'h7: y = rem_u64;                    // REMU
            endcase
        end
    end
endmodule
