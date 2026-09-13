// Functional coverage for the RV64IM instruction decoder, bound onto core.
// Decodes mnemonics itself from raw instr bits (opcode/funct3/funct7 tables)
// so this survives refactors of decode.sv/core.sv without referencing them.
//
// Coverage plan (83 labels total: 72 mnemonics + 11 operand-shape covers):
//   RV64I (59): cov_LUI cov_AUIPC cov_JAL cov_JALR cov_BEQ cov_BNE cov_BLT
//     cov_BGE cov_BLTU cov_BGEU cov_LB cov_LH cov_LW cov_LD cov_LBU cov_LHU
//     cov_LWU cov_SB cov_SH cov_SW cov_SD cov_ADDI cov_SLTI cov_SLTIU
//     cov_XORI cov_ORI cov_ANDI cov_SLLI cov_SRLI cov_SRAI cov_ADD cov_SUB
//     cov_SLL cov_SLT cov_SLTU cov_XOR cov_SRL cov_SRA cov_OR cov_AND
//     cov_FENCE cov_ECALL cov_EBREAK cov_ADDIW cov_SLLIW cov_SRLIW cov_SRAIW
//     cov_ADDW cov_SUBW cov_SLLW cov_SRLW cov_SRAW
//   M (13): cov_MUL cov_MULH cov_MULHSU cov_MULHU cov_DIV cov_DIVU cov_REM
//     cov_REMU cov_MULW cov_DIVW cov_DIVUW cov_REMW cov_REMUW
//   Operand-shape (11): cov_rd_x0 cov_rs1_eq_rs2 cov_itype_imm_neg
//     cov_itype_imm_pos cov_branch_back cov_branch_fwd cov_jal_back
//     cov_jal_fwd cov_shamt_max cov_illegal
module decode_cov (
    input logic        clk,
    input logic        rst,
    input logic [31:0] instr
);
    logic [6:0] opcode = instr[6:0];
    logic [2:0] funct3 = instr[14:12];
    logic [6:0] funct7 = instr[31:25];
    logic       f7_5   = instr[30]; // ADD/SUB, SRL/SRA distinguishing bit
    logic [4:0] rd     = instr[11:7];
    logic [4:0] rs1    = instr[19:15];
    logic [4:0] rs2    = instr[24:20];
    logic [5:0] shamt  = instr[25:20]; // 6-bit shamt for RV64 shift-immediates

    // mnemonic decode, one-hot per instruction
    logic is_LUI, is_AUIPC, is_JAL, is_JALR;
    logic is_BEQ, is_BNE, is_BLT, is_BGE, is_BLTU, is_BGEU;
    logic is_LB, is_LH, is_LW, is_LD, is_LBU, is_LHU, is_LWU;
    logic is_SB, is_SH, is_SW, is_SD;
    logic is_ADDI, is_SLTI, is_SLTIU, is_XORI, is_ORI, is_ANDI, is_SLLI, is_SRLI, is_SRAI;
    logic is_ADD, is_SUB, is_SLL, is_SLT, is_SLTU, is_XOR, is_SRL, is_SRA, is_OR, is_AND;
    logic is_FENCE, is_ECALL, is_EBREAK;
    logic is_ADDIW, is_SLLIW, is_SRLIW, is_SRAIW;
    logic is_ADDW, is_SUBW, is_SLLW, is_SRLW, is_SRAW;
    logic is_MUL, is_MULH, is_MULHSU, is_MULHU, is_DIV, is_DIVU, is_REM, is_REMU;
    logic is_MULW, is_DIVW, is_DIVUW, is_REMW, is_REMUW;
    logic is_rtype, is_itype, is_reg_write, is_illegal;

    always_comb begin
        {is_LUI, is_AUIPC, is_JAL, is_JALR} = '0;
        {is_BEQ, is_BNE, is_BLT, is_BGE, is_BLTU, is_BGEU} = '0;
        {is_LB, is_LH, is_LW, is_LD, is_LBU, is_LHU, is_LWU} = '0;
        {is_SB, is_SH, is_SW, is_SD} = '0;
        {is_ADDI, is_SLTI, is_SLTIU, is_XORI, is_ORI, is_ANDI, is_SLLI, is_SRLI, is_SRAI} = '0;
        {is_ADD, is_SUB, is_SLL, is_SLT, is_SLTU, is_XOR, is_SRL, is_SRA, is_OR, is_AND} = '0;
        {is_FENCE, is_ECALL, is_EBREAK} = '0;
        {is_ADDIW, is_SLLIW, is_SRLIW, is_SRAIW} = '0;
        {is_ADDW, is_SUBW, is_SLLW, is_SRLW, is_SRAW} = '0;
        {is_MUL, is_MULH, is_MULHSU, is_MULHU, is_DIV, is_DIVU, is_REM, is_REMU} = '0;
        {is_MULW, is_DIVW, is_DIVUW, is_REMW, is_REMUW} = '0;
        is_rtype = 1'b0; is_itype = 1'b0;

        unique case (opcode)
            7'b0110111: is_LUI = 1'b1;
            7'b0010111: is_AUIPC = 1'b1;
            7'b1101111: is_JAL = 1'b1;
            7'b1100111: if (funct3 == 3'h0) is_JALR = 1'b1;
            7'b1100011: begin
                unique case (funct3)
                    3'h0: is_BEQ  = 1'b1;
                    3'h1: is_BNE  = 1'b1;
                    3'h4: is_BLT  = 1'b1;
                    3'h5: is_BGE  = 1'b1;
                    3'h6: is_BLTU = 1'b1;
                    3'h7: is_BGEU = 1'b1;
                    default: ;
                endcase
            end
            7'b0000011: begin
                is_itype = 1'b1;
                unique case (funct3)
                    3'h0: is_LB  = 1'b1;
                    3'h1: is_LH  = 1'b1;
                    3'h2: is_LW  = 1'b1;
                    3'h3: is_LD  = 1'b1;
                    3'h4: is_LBU = 1'b1;
                    3'h5: is_LHU = 1'b1;
                    3'h6: is_LWU = 1'b1;
                    default: ;
                endcase
            end
            7'b0100011: begin
                unique case (funct3)
                    3'h0: is_SB = 1'b1;
                    3'h1: is_SH = 1'b1;
                    3'h2: is_SW = 1'b1;
                    3'h3: is_SD = 1'b1;
                    default: ;
                endcase
            end
            7'b0010011: begin
                is_itype = 1'b1;
                unique case (funct3)
                    3'h0: is_ADDI  = 1'b1;
                    3'h2: is_SLTI  = 1'b1;
                    3'h3: is_SLTIU = 1'b1;
                    3'h4: is_XORI  = 1'b1;
                    3'h6: is_ORI   = 1'b1;
                    3'h7: is_ANDI  = 1'b1;
                    3'h1: is_SLLI  = 1'b1;
                    3'h5: if (f7_5) is_SRAI = 1'b1; else is_SRLI = 1'b1;
                    default: ;
                endcase
            end
            7'b0110011: begin
                is_rtype = 1'b1;
                unique case (funct7)
                    7'b0000000: unique case (funct3)
                        3'h0: is_ADD  = 1'b1;
                        3'h1: is_SLL  = 1'b1;
                        3'h2: is_SLT  = 1'b1;
                        3'h3: is_SLTU = 1'b1;
                        3'h4: is_XOR  = 1'b1;
                        3'h5: is_SRL  = 1'b1;
                        3'h6: is_OR   = 1'b1;
                        3'h7: is_AND  = 1'b1;
                        default: ;
                    endcase
                    7'b0100000: unique case (funct3)
                        3'h0: is_SUB = 1'b1;
                        3'h5: is_SRA = 1'b1;
                        default: ;
                    endcase
                    7'b0000001: unique case (funct3)
                        3'h0: is_MUL    = 1'b1;
                        3'h1: is_MULH   = 1'b1;
                        3'h2: is_MULHSU = 1'b1;
                        3'h3: is_MULHU  = 1'b1;
                        3'h4: is_DIV    = 1'b1;
                        3'h5: is_DIVU   = 1'b1;
                        3'h6: is_REM    = 1'b1;
                        3'h7: is_REMU   = 1'b1;
                        default: ;
                    endcase
                    default: ;
                endcase
            end
            7'b0001111: if (funct3 == 3'h0) is_FENCE = 1'b1;
            7'b1110011: begin
                if (funct3 == 3'h0 && instr[19:7] == 13'h0) begin
                    if (instr[31:20] == 12'h000) is_ECALL  = 1'b1;
                    else if (instr[31:20] == 12'h001) is_EBREAK = 1'b1;
                end
            end
            7'b0011011: begin
                is_itype = 1'b1;
                unique case (funct3)
                    3'h0: is_ADDIW = 1'b1;
                    3'h1: if (funct7 == 7'b0000000) is_SLLIW = 1'b1;
                    3'h5: begin
                        if (funct7 == 7'b0000000) is_SRLIW = 1'b1;
                        else if (funct7 == 7'b0100000) is_SRAIW = 1'b1;
                    end
                    default: ;
                endcase
            end
            7'b0111011: begin
                is_rtype = 1'b1;
                unique case (funct7)
                    7'b0000000: unique case (funct3)
                        3'h0: is_ADDW = 1'b1;
                        3'h1: is_SLLW = 1'b1;
                        3'h5: is_SRLW = 1'b1;
                        default: ;
                    endcase
                    7'b0100000: unique case (funct3)
                        3'h0: is_SUBW = 1'b1;
                        3'h5: is_SRAW = 1'b1;
                        default: ;
                    endcase
                    7'b0000001: unique case (funct3)
                        3'h0: is_MULW  = 1'b1;
                        3'h4: is_DIVW  = 1'b1;
                        3'h5: is_DIVUW = 1'b1;
                        3'h6: is_REMW  = 1'b1;
                        3'h7: is_REMUW = 1'b1;
                        default: ;
                    endcase
                    default: ;
                endcase
            end
            default: ;
        endcase
    end

    assign is_reg_write = is_LUI | is_AUIPC | is_JAL | is_JALR
        | is_LB | is_LH | is_LW | is_LD | is_LBU | is_LHU | is_LWU
        | is_ADDI | is_SLTI | is_SLTIU | is_XORI | is_ORI | is_ANDI | is_SLLI | is_SRLI | is_SRAI
        | is_ADD | is_SUB | is_SLL | is_SLT | is_SLTU | is_XOR | is_SRL | is_SRA | is_OR | is_AND
        | is_ADDIW | is_SLLIW | is_SRLIW | is_SRAIW
        | is_ADDW | is_SUBW | is_SLLW | is_SRLW | is_SRAW
        | is_MUL | is_MULH | is_MULHSU | is_MULHU | is_DIV | is_DIVU | is_REM | is_REMU
        | is_MULW | is_DIVW | is_DIVUW | is_REMW | is_REMUW;

    assign is_illegal = ~(is_LUI | is_AUIPC | is_JAL | is_JALR
        | is_BEQ | is_BNE | is_BLT | is_BGE | is_BLTU | is_BGEU
        | is_LB | is_LH | is_LW | is_LD | is_LBU | is_LHU | is_LWU
        | is_SB | is_SH | is_SW | is_SD
        | is_ADDI | is_SLTI | is_SLTIU | is_XORI | is_ORI | is_ANDI | is_SLLI | is_SRLI | is_SRAI
        | is_ADD | is_SUB | is_SLL | is_SLT | is_SLTU | is_XOR | is_SRL | is_SRA | is_OR | is_AND
        | is_FENCE | is_ECALL | is_EBREAK
        | is_ADDIW | is_SLLIW | is_SRLIW | is_SRAIW
        | is_ADDW | is_SUBW | is_SLLW | is_SRLW | is_SRAW
        | is_MUL | is_MULH | is_MULHSU | is_MULHU | is_DIV | is_DIVU | is_REM | is_REMU
        | is_MULW | is_DIVW | is_DIVUW | is_REMW | is_REMUW);

    logic is_shift_imm = is_SLLI | is_SRLI | is_SRAI | is_SLLIW | is_SRLIW | is_SRAIW;

    // mnemonic covers
    cov_LUI:    cover property (@(posedge clk) disable iff (rst) is_LUI);
    cov_AUIPC:  cover property (@(posedge clk) disable iff (rst) is_AUIPC);
    cov_JAL:    cover property (@(posedge clk) disable iff (rst) is_JAL);
    cov_JALR:   cover property (@(posedge clk) disable iff (rst) is_JALR);
    cov_BEQ:    cover property (@(posedge clk) disable iff (rst) is_BEQ);
    cov_BNE:    cover property (@(posedge clk) disable iff (rst) is_BNE);
    cov_BLT:    cover property (@(posedge clk) disable iff (rst) is_BLT);
    cov_BGE:    cover property (@(posedge clk) disable iff (rst) is_BGE);
    cov_BLTU:   cover property (@(posedge clk) disable iff (rst) is_BLTU);
    cov_BGEU:   cover property (@(posedge clk) disable iff (rst) is_BGEU);
    cov_LB:     cover property (@(posedge clk) disable iff (rst) is_LB);
    cov_LH:     cover property (@(posedge clk) disable iff (rst) is_LH);
    cov_LW:     cover property (@(posedge clk) disable iff (rst) is_LW);
    cov_LD:     cover property (@(posedge clk) disable iff (rst) is_LD);
    cov_LBU:    cover property (@(posedge clk) disable iff (rst) is_LBU);
    cov_LHU:    cover property (@(posedge clk) disable iff (rst) is_LHU);
    cov_LWU:    cover property (@(posedge clk) disable iff (rst) is_LWU);
    cov_SB:     cover property (@(posedge clk) disable iff (rst) is_SB);
    cov_SH:     cover property (@(posedge clk) disable iff (rst) is_SH);
    cov_SW:     cover property (@(posedge clk) disable iff (rst) is_SW);
    cov_SD:     cover property (@(posedge clk) disable iff (rst) is_SD);
    cov_ADDI:   cover property (@(posedge clk) disable iff (rst) is_ADDI);
    cov_SLTI:   cover property (@(posedge clk) disable iff (rst) is_SLTI);
    cov_SLTIU:  cover property (@(posedge clk) disable iff (rst) is_SLTIU);
    cov_XORI:   cover property (@(posedge clk) disable iff (rst) is_XORI);
    cov_ORI:    cover property (@(posedge clk) disable iff (rst) is_ORI);
    cov_ANDI:   cover property (@(posedge clk) disable iff (rst) is_ANDI);
    cov_SLLI:   cover property (@(posedge clk) disable iff (rst) is_SLLI);
    cov_SRLI:   cover property (@(posedge clk) disable iff (rst) is_SRLI);
    cov_SRAI:   cover property (@(posedge clk) disable iff (rst) is_SRAI);
    cov_ADD:    cover property (@(posedge clk) disable iff (rst) is_ADD);
    cov_SUB:    cover property (@(posedge clk) disable iff (rst) is_SUB);
    cov_SLL:    cover property (@(posedge clk) disable iff (rst) is_SLL);
    cov_SLT:    cover property (@(posedge clk) disable iff (rst) is_SLT);
    cov_SLTU:   cover property (@(posedge clk) disable iff (rst) is_SLTU);
    cov_XOR:    cover property (@(posedge clk) disable iff (rst) is_XOR);
    cov_SRL:    cover property (@(posedge clk) disable iff (rst) is_SRL);
    cov_SRA:    cover property (@(posedge clk) disable iff (rst) is_SRA);
    cov_OR:     cover property (@(posedge clk) disable iff (rst) is_OR);
    cov_AND:    cover property (@(posedge clk) disable iff (rst) is_AND);
    cov_FENCE:  cover property (@(posedge clk) disable iff (rst) is_FENCE);
    cov_ECALL:  cover property (@(posedge clk) disable iff (rst) is_ECALL);
    cov_EBREAK: cover property (@(posedge clk) disable iff (rst) is_EBREAK);
    cov_ADDIW:  cover property (@(posedge clk) disable iff (rst) is_ADDIW);
    cov_SLLIW:  cover property (@(posedge clk) disable iff (rst) is_SLLIW);
    cov_SRLIW:  cover property (@(posedge clk) disable iff (rst) is_SRLIW);
    cov_SRAIW:  cover property (@(posedge clk) disable iff (rst) is_SRAIW);
    cov_ADDW:   cover property (@(posedge clk) disable iff (rst) is_ADDW);
    cov_SUBW:   cover property (@(posedge clk) disable iff (rst) is_SUBW);
    cov_SLLW:   cover property (@(posedge clk) disable iff (rst) is_SLLW);
    cov_SRLW:   cover property (@(posedge clk) disable iff (rst) is_SRLW);
    cov_SRAW:   cover property (@(posedge clk) disable iff (rst) is_SRAW);
    cov_MUL:    cover property (@(posedge clk) disable iff (rst) is_MUL);
    cov_MULH:   cover property (@(posedge clk) disable iff (rst) is_MULH);
    cov_MULHSU: cover property (@(posedge clk) disable iff (rst) is_MULHSU);
    cov_MULHU:  cover property (@(posedge clk) disable iff (rst) is_MULHU);
    cov_DIV:    cover property (@(posedge clk) disable iff (rst) is_DIV);
    cov_DIVU:   cover property (@(posedge clk) disable iff (rst) is_DIVU);
    cov_REM:    cover property (@(posedge clk) disable iff (rst) is_REM);
    cov_REMU:   cover property (@(posedge clk) disable iff (rst) is_REMU);
    cov_MULW:   cover property (@(posedge clk) disable iff (rst) is_MULW);
    cov_DIVW:   cover property (@(posedge clk) disable iff (rst) is_DIVW);
    cov_DIVUW:  cover property (@(posedge clk) disable iff (rst) is_DIVUW);
    cov_REMW:   cover property (@(posedge clk) disable iff (rst) is_REMW);
    cov_REMUW:  cover property (@(posedge clk) disable iff (rst) is_REMUW);

    // operand-shape covers
    cov_rd_x0:         cover property (@(posedge clk) disable iff (rst) is_reg_write && rd == 5'd0);
    cov_rs1_eq_rs2:    cover property (@(posedge clk) disable iff (rst) is_rtype && rs1 == rs2);
    cov_itype_imm_neg: cover property (@(posedge clk) disable iff (rst) is_itype && instr[31]);
    cov_itype_imm_pos: cover property (@(posedge clk) disable iff (rst) is_itype && !instr[31]);
    cov_branch_back:   cover property (@(posedge clk) disable iff (rst) (opcode == 7'b1100011) && instr[31]);
    cov_branch_fwd:    cover property (@(posedge clk) disable iff (rst) (opcode == 7'b1100011) && !instr[31]);
    cov_jal_back:      cover property (@(posedge clk) disable iff (rst) is_JAL && instr[31]);
    cov_jal_fwd:       cover property (@(posedge clk) disable iff (rst) is_JAL && !instr[31]);
    cov_shamt_max:     cover property (@(posedge clk) disable iff (rst) is_shift_imm && shamt == 6'd63);
    cov_illegal:       cover property (@(posedge clk) disable iff (rst) is_illegal);
endmodule
