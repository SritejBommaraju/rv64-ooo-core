// Iterative multi-cycle M-extension unit. Multiply is combinational behind an output register
// (1-cycle latency); divide/remainder use a 1-bit-per-cycle restoring divider (64 or 32 iterations).
module muldiv (
    input  logic        clk, rst,
    input  logic [63:0] a, b,
    input  logic [2:0]  op,       // = funct3: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
    input  logic        is_word,  // W-variant: 32-bit inputs/op, sign-extend result
    input  logic        start,    // 1-cycle pulse: latch a/b/op/is_word and begin
    output logic        busy,
    output logic        done,     // 1-cycle pulse, y valid on this cycle
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

    logic [63:0] mul_full;
    assign mul_full = a * b; // low 64 bits of the product; low 32 bits are correct for MULW too

    logic [63:0] mul_result;
    always_comb begin
        if (is_word)
            unique case (op)
                3'h0: mul_result = {{32{mul_full[31]}}, mul_full[31:0]}; // MULW
                default: mul_result = 64'd0;
            endcase
        else
            unique case (op)
                3'h0: mul_result = mul_full;               // MUL
                3'h1: mul_result = mulh_ss[127:64];         // MULH
                3'h2: mul_result = mulh_su[127:64];         // MULHSU
                3'h3: mul_result = mulh_uu[127:64];         // MULHU
                default: mul_result = 64'd0;
            endcase
    end

    logic is_div;
    assign is_div = op[2]; // funct3[2] set for DIV/DIVU/REM/REMU (3-7)

    // ---- iterative restoring divider ----
    // Operates on unsigned magnitudes zero-extended into 64 bits; sign correction and corner cases
    // applied at latch/finish time. Always runs 64 iterations (even for W forms, whose magnitudes fit
    // in the low 32 bits with zero above) since a 64-bit-wide restoring divide of a zero-extended W
    // operand naturally reduces to the correct 32-bit result -- simpler than threading a second,
    // narrower shift-register width through the same datapath.
    logic [6:0]  iter;      // iterations remaining
    logic [63:0] rem_r, quo_r, divisor_r;
    logic        neg_quo, neg_rem;   // apply negation on finish for signed ops
    logic        op_is_rem;          // REM/REMU vs DIV/DIVU
    logic        op_is_word_r;
    logic        div_by_zero, sign_ovf;
    logic [63:0] a_lat; // latched dividend, needed for the div-by-zero/overflow special-case results

    typedef enum logic [1:0] {IDLE, RUN, FINISH} state_t;
    state_t state;

    assign busy = (state != IDLE);

    // {rem_r, quo_r} shifted left by 1: new remainder candidate is {rem_r[62:0], quo_r[63]}
    logic [63:0] cand_rem, trial_sub;
    logic        ge;
    assign cand_rem  = {rem_r[62:0], quo_r[63]};
    assign trial_sub = cand_rem - divisor_r;
    assign ge        = cand_rem >= divisor_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done  <= 1'b0;
            y     <= 64'd0;
        end else begin
            done <= 1'b0;
            unique case (state)
                IDLE: begin
                    if (start) begin
                        a_lat <= a; op_is_word_r <= is_word;
                        op_is_rem <= op[1]; // REM/REMU have funct3[1] set (6,7) vs DIV/DIVU (4,5)
                        iter  <= 7'd64;
                        if (!is_div) begin
                            // multiply: single-cycle combinational result behind this register
                            y    <= mul_result;
                            done <= 1'b1;
                        end else begin
                            logic is_signed_op;
                            logic [63:0] amag, bmag;
                            is_signed_op = ~op[0]; // DIV/REM (4,6) signed; DIVU/REMU (5,7) unsigned
                            div_by_zero = is_word ? (b[31:0] == 32'd0) : (b == 64'd0);
                            sign_ovf = is_signed_op && (is_word ?
                                (as32 == 32'h8000_0000 && bs32 == 32'hFFFF_FFFF) :
                                (a == 64'h8000_0000_0000_0000 && b == 64'hFFFF_FFFF_FFFF_FFFF));
                            if (is_word) begin
                                amag = is_signed_op && as32[31] ? {32'd0, 32'd0 - a[31:0]} : {32'd0, a[31:0]};
                                bmag = is_signed_op && bs32[31] ? {32'd0, 32'd0 - b[31:0]} : {32'd0, b[31:0]};
                                neg_quo = is_signed_op && (as32[31] ^ bs32[31]) && !div_by_zero;
                                neg_rem = is_signed_op && as32[31] && !div_by_zero;
                            end else begin
                                amag = is_signed_op && as64[63] ? -a : a;
                                bmag = is_signed_op && bs64[63] ? -b : b;
                                neg_quo = is_signed_op && (a[63] ^ b[63]) && !div_by_zero;
                                neg_rem = is_signed_op && a[63] && !div_by_zero;
                            end
                            quo_r <= amag;
                            rem_r <= 64'd0;
                            divisor_r <= bmag;
                            if (div_by_zero || sign_ovf)
                                state <= FINISH;
                            else
                                state <= RUN;
                        end
                    end
                end
                RUN: begin
                    rem_r <= ge ? trial_sub : cand_rem;
                    quo_r <= {quo_r[62:0], ge};
                    iter  <= iter - 7'd1;
                    if (iter == 7'd1) state <= FINISH;
                end
                FINISH: begin
                    logic [63:0] quo_f, rem_f, result;
                    if (div_by_zero) begin
                        quo_f = op_is_word_r ? 64'hFFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
                        rem_f = a_lat;
                    end else if (sign_ovf) begin
                        quo_f = a_lat;
                        rem_f = 64'd0;
                    end else begin
                        quo_f = neg_quo ? -quo_r : quo_r;
                        rem_f = neg_rem ? -rem_r : rem_r;
                    end
                    result = op_is_rem ? rem_f : quo_f;
                    y <= op_is_word_r ? {{32{result[31]}}, result[31:0]} : result;
                    done  <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
