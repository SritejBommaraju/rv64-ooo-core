module decode (
    input  logic [31:0] instr,
    output logic [4:0]  rs1, rs2, rd,
    output logic [63:0] imm,
    output logic [3:0]  alu_op,
    output logic        alu_src_imm,
    output logic        reg_write,
    output logic        is_load, is_store, is_branch, is_jal, is_jalr,
    output logic        is_lui, is_auipc,
    output logic [2:0]  funct3,
    output logic        is_word,   // W-variant: operate on low 32 bits, sign-extend result
    output logic        is_muldiv, // M-extension op
    output logic [2:0]  muldiv_op  // = funct3 for the muldiv unit
);
    logic [6:0] opcode = instr[6:0];
    logic       funct7_5 = instr[30]; // only bit that distinguishes ADD/SUB, SRL/SRA
    logic       funct7_0 = instr[25]; // set for all M-extension (funct7=0000001) encodings

    assign rd     = instr[11:7];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct3 = instr[14:12];

    // sign-extended immediate, shape picked by opcode
    logic [63:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    assign imm_i = {{52{instr[31]}}, instr[31:20]};
    assign imm_s = {{52{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {{32{instr[31]}}, instr[31:12], 12'b0};
    assign imm_j = {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    always_comb begin
        is_load = 1'b0; is_store = 1'b0; is_branch = 1'b0; is_jal = 1'b0; is_jalr = 1'b0;
        is_lui = 1'b0; is_auipc = 1'b0; reg_write = 1'b0; alu_src_imm = 1'b0;
        alu_op = 4'h0; imm = 64'd0;
        is_word = 1'b0; is_muldiv = 1'b0; muldiv_op = 3'h0;

        unique case (opcode)
            7'b0110111: begin is_lui = 1; reg_write = 1; imm = imm_u; end
            7'b0010111: begin is_auipc = 1; reg_write = 1; alu_src_imm = 1; imm = imm_u; end
            7'b1101111: begin is_jal = 1; reg_write = 1; imm = imm_j; end
            7'b1100111: begin is_jalr = 1; reg_write = 1; alu_src_imm = 1; imm = imm_i; end
            7'b1100011: begin is_branch = 1; imm = imm_b; end
            7'b0000011: begin is_load = 1; reg_write = 1; alu_src_imm = 1; imm = imm_i; end
            7'b0100011: begin is_store = 1; alu_src_imm = 1; imm = imm_s; end
            7'b0010011: begin // OP-IMM
                reg_write = 1; alu_src_imm = 1; imm = imm_i;
                unique case (funct3)
                    3'h0: alu_op = 4'h0; // ADDI
                    3'h2: alu_op = 4'h3; // SLTI
                    3'h3: alu_op = 4'h4; // SLTIU
                    3'h4: alu_op = 4'h5; // XORI
                    3'h6: alu_op = 4'h8; // ORI
                    3'h7: alu_op = 4'h9; // ANDI
                    3'h1: alu_op = 4'h2; // SLLI
                    3'h5: alu_op = funct7_5 ? 4'h7 : 4'h6; // SRAI/SRLI
                    default: alu_op = 4'h0;
                endcase
            end
            7'b0110011: begin // OP
                reg_write = 1;
                if (funct7_0) begin // M extension: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
                    is_muldiv = 1; muldiv_op = funct3;
                end else begin
                    unique case (funct3)
                        3'h0: alu_op = funct7_5 ? 4'h1 : 4'h0; // SUB/ADD
                        3'h1: alu_op = 4'h2; // SLL
                        3'h2: alu_op = 4'h3; // SLT
                        3'h3: alu_op = 4'h4; // SLTU
                        3'h4: alu_op = 4'h5; // XOR
                        3'h5: alu_op = funct7_5 ? 4'h7 : 4'h6; // SRA/SRL
                        3'h6: alu_op = 4'h8; // OR
                        3'h7: alu_op = 4'h9; // AND
                        default: alu_op = 4'h0;
                    endcase
                end
            end
            7'b0011011: begin // OP-IMM-32 (W-variants): ADDIW/SLLIW/SRLIW/SRAIW
                reg_write = 1; alu_src_imm = 1; imm = imm_i; is_word = 1;
                unique case (funct3)
                    3'h0: alu_op = 4'h0; // ADDIW
                    3'h1: alu_op = 4'h2; // SLLIW (shamt = instr[24:20])
                    3'h5: alu_op = funct7_5 ? 4'h7 : 4'h6; // SRAIW/SRLIW
                    default: alu_op = 4'h0;
                endcase
            end
            7'b0111011: begin // OP-32 (W-variants): ADDW/SUBW/SLLW/SRLW/SRAW, MULW/DIVW/DIVUW/REMW/REMUW
                reg_write = 1; is_word = 1;
                if (funct7_0) begin
                    is_muldiv = 1; muldiv_op = funct3;
                end else begin
                    unique case (funct3)
                        3'h0: alu_op = funct7_5 ? 4'h1 : 4'h0; // SUBW/ADDW
                        3'h1: alu_op = 4'h2; // SLLW
                        3'h5: alu_op = funct7_5 ? 4'h7 : 4'h6; // SRAW/SRLW
                        default: alu_op = 4'h0;
                    endcase
                end
            end
            default: ; // unimplemented (SYSTEM, etc) treated as NOP
        endcase
    end
endmodule
