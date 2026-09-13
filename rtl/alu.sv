module alu (
    input  logic [63:0] a, b,
    input  logic [3:0]  op,
    output logic [63:0] y
);
    // op encodes funct3/funct7 bit5 packed by decoder
    always_comb begin
        unique case (op)
            4'h0: y = a + b;                                   // ADD
            4'h1: y = a - b;                                   // SUB
            4'h2: y = a << b[5:0];                              // SLL
            4'h3: y = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0; // SLT
            4'h4: y = (a < b) ? 64'd1 : 64'd0;                  // SLTU
            4'h5: y = a ^ b;                                    // XOR
            4'h6: y = a >> b[5:0];                              // SRL
            4'h7: y = $signed(a) >>> b[5:0];                    // SRA
            4'h8: y = a | b;                                    // OR
            4'h9: y = a & b;                                    // AND
            default: y = 64'd0;
        endcase
    end
endmodule
