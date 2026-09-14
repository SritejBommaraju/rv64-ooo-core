#include "iss.h"
#include <cstdio>
#include <cstring>

static int64_t sext(uint64_t v, int bits) {
    uint64_t m = 1ULL << (bits - 1);
    return (int64_t)((v ^ m) - m);
}

Iss::Iss() { mem.assign(64 * 1024, 0); }

void Iss::load(const std::vector<uint8_t>& image) {
    std::memset(mem.data(), 0, mem.size());
    size_t n = image.size() < mem.size() ? image.size() : mem.size();
    std::memcpy(mem.data(), image.data(), n);
}

uint8_t Iss::load8(uint64_t a) const { return mem[a & 0xffff]; }
uint16_t Iss::load16(uint64_t a) const {
    return (uint16_t)load8(a) | ((uint16_t)load8(a + 1) << 8);
}
uint32_t Iss::load32(uint64_t a) const {
    return (uint32_t)load16(a) | ((uint32_t)load16(a + 2) << 16);
}
uint64_t Iss::load64(uint64_t a) const {
    return (uint64_t)load32(a) | ((uint64_t)load32(a + 4) << 32);
}
void Iss::store8(uint64_t a, uint8_t v) { mem[a & 0xffff] = v; }
void Iss::store16(uint64_t a, uint16_t v) { store8(a, v & 0xff); store8(a + 1, v >> 8); }
void Iss::store32(uint64_t a, uint32_t v) { store16(a, v & 0xffff); store16(a + 2, v >> 16); }
void Iss::store64(uint64_t a, uint64_t v) { store32(a, (uint32_t)v); store32(a + 4, (uint32_t)(v >> 32)); }
uint32_t Iss::fetch(uint64_t a) const { return load32(a); }

bool Iss::step() {
    x[0] = 0;
    uint32_t insn = fetch(pc);
    last_insn = insn;
    last_rd = -1;

    uint32_t opcode = insn & 0x7f;
    uint32_t rd = (insn >> 7) & 0x1f;
    uint32_t funct3 = (insn >> 12) & 0x7;
    uint32_t rs1 = (insn >> 15) & 0x1f;
    uint32_t rs2 = (insn >> 20) & 0x1f;
    uint32_t funct7 = (insn >> 25) & 0x7f;
    uint32_t shamt = (insn >> 20) & 0x3f;   // 6-bit shift amount (RV64)
    uint32_t shamtw = (insn >> 20) & 0x1f;  // 5-bit shift amount for *W ops

    int64_t i_imm = sext(insn >> 20, 12);
    int64_t s_imm = sext(((insn >> 25) << 5) | ((insn >> 7) & 0x1f), 12);
    int64_t b_imm = sext((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) |
                         (((insn >> 25) & 0x3f) << 5) | (((insn >> 8) & 0xf) << 1), 13);
    int64_t u_imm = (int64_t)(int32_t)(insn & 0xfffff000);
    int64_t j_imm = sext((((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xff) << 12) |
                         (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3ff) << 1), 21);

    uint64_t next_pc = pc + 4;
    auto wb = [&](uint64_t v) { if (rd != 0) x[rd] = v; last_rd = (int)rd; last_rd_val = (rd == 0) ? 0 : v; };

    switch (opcode) {
    case 0x37: // LUI
        wb((uint64_t)u_imm);
        break;
    case 0x17: // AUIPC
        wb(pc + (uint64_t)u_imm);
        break;
    case 0x6F: // JAL
        wb(pc + 4);
        next_pc = pc + (uint64_t)j_imm;
        break;
    case 0x67: // JALR
        if (funct3 != 0) { exit_reason = Exit::ILLEGAL; return false; }
        { uint64_t target = (x[rs1] + (uint64_t)i_imm) & ~1ULL;
          wb(pc + 4);
          next_pc = target; }
        break;
    case 0x63: { // branches
        bool taken = false;
        int64_t a = (int64_t)x[rs1], b = (int64_t)x[rs2];
        switch (funct3) {
        case 0: taken = (a == b); break;                       // BEQ
        case 1: taken = (a != b); break;                       // BNE
        case 4: taken = (a < b); break;                        // BLT
        case 5: taken = (a >= b); break;                       // BGE
        case 6: taken = (x[rs1] < x[rs2]); break;               // BLTU
        case 7: taken = (x[rs1] >= x[rs2]); break;              // BGEU
        default: exit_reason = Exit::ILLEGAL; return false;
        }
        if (taken) next_pc = pc + (uint64_t)b_imm;
        break;
    }
    case 0x03: { // loads
        uint64_t addr = x[rs1] + (uint64_t)i_imm;
        switch (funct3) {
        case 0: wb((uint64_t)sext(load8(addr), 8)); break;   // LB
        case 1: wb((uint64_t)sext(load16(addr), 16)); break; // LH
        case 2: wb((uint64_t)sext(load32(addr), 32)); break; // LW
        case 4: wb((uint64_t)load8(addr)); break;            // LBU
        case 5: wb((uint64_t)load16(addr)); break;           // LHU
        case 6: wb((uint64_t)load32(addr)); break;           // LWU
        case 3: wb(load64(addr)); break;                     // LD
        default: exit_reason = Exit::ILLEGAL; return false;
        }
        break;
    }
    case 0x23: { // stores
        uint64_t addr = x[rs1] + (uint64_t)s_imm;
        switch (funct3) {
        case 0: store8(addr, (uint8_t)x[rs2]); break;   // SB
        case 1: store16(addr, (uint16_t)x[rs2]); break; // SH
        case 2: store32(addr, (uint32_t)x[rs2]); break; // SW
        case 3: store64(addr, x[rs2]); break;           // SD
        default: exit_reason = Exit::ILLEGAL; return false;
        }
        break;
    }
    case 0x13: { // imm arith
        int64_t a = (int64_t)x[rs1];
        switch (funct3) {
        case 0: wb((uint64_t)(a + i_imm)); break;                          // ADDI
        case 2: wb(a < i_imm ? 1 : 0); break;                              // SLTI
        case 3: wb(x[rs1] < (uint64_t)i_imm ? 1 : 0); break;               // SLTIU
        case 4: wb((uint64_t)(a ^ i_imm)); break;                          // XORI
        case 6: wb((uint64_t)(a | i_imm)); break;                          // ORI
        case 7: wb((uint64_t)(a & i_imm)); break;                          // ANDI
        case 1:
            // RV64 shamt is 6 bits (insn[25:20]); only insn[31:26] is the real funct6.
            if ((funct7 & 0xFE) != 0x00) { exit_reason = Exit::ILLEGAL; return false; }
            wb(x[rs1] << shamt);                                          // SLLI
            break;
        case 5:
            if ((funct7 & 0xFE) == 0x00) wb(x[rs1] >> shamt);             // SRLI
            else if ((funct7 & 0xFE) == 0x20) wb((uint64_t)(a >> shamt)); // SRAI
            else { exit_reason = Exit::ILLEGAL; return false; }
            break;
        }
        break;
    }
    case 0x33: { // reg-reg (RV64I + M)
        int64_t a = (int64_t)x[rs1], b = (int64_t)x[rs2];
        if (funct7 == 0x01) { // M extension
            switch (funct3) {
            case 0: wb((uint64_t)(a * b)); break;                          // MUL
            case 1: { __int128 p = (__int128)a * (__int128)b; wb((uint64_t)(p >> 64)); break; } // MULH
            case 2: { __int128 p = (__int128)a * (unsigned __int128)x[rs2]; wb((uint64_t)(p >> 64)); break; } // MULHSU
            case 3: { unsigned __int128 p = (unsigned __int128)x[rs1] * (unsigned __int128)x[rs2]; wb((uint64_t)(p >> 64)); break; } // MULHU
            case 4: // DIV
                if (b == 0) wb((uint64_t)-1);
                else if (a == INT64_MIN && b == -1) wb((uint64_t)INT64_MIN);
                else wb((uint64_t)(a / b));
                break;
            case 5: // DIVU
                if (x[rs2] == 0) wb((uint64_t)-1);
                else wb(x[rs1] / x[rs2]);
                break;
            case 6: // REM
                if (b == 0) wb((uint64_t)a);
                else if (a == INT64_MIN && b == -1) wb(0);
                else wb((uint64_t)(a % b));
                break;
            case 7: // REMU
                if (x[rs2] == 0) wb(x[rs1]);
                else wb(x[rs1] % x[rs2]);
                break;
            }
            break;
        }
        switch (funct3) {
        case 0:
            if (funct7 == 0x00) wb((uint64_t)(a + b));       // ADD
            else if (funct7 == 0x20) wb((uint64_t)(a - b));  // SUB
            else { exit_reason = Exit::ILLEGAL; return false; }
            break;
        case 1:
            if (funct7 != 0) { exit_reason = Exit::ILLEGAL; return false; }
            wb(x[rs1] << (x[rs2] & 0x3f));                   // SLL
            break;
        case 2: wb(a < b ? 1 : 0); break;                    // SLT
        case 3: wb(x[rs1] < x[rs2] ? 1 : 0); break;          // SLTU
        case 4:
            if (funct7 != 0) { exit_reason = Exit::ILLEGAL; return false; }
            wb((uint64_t)(a ^ b));                           // XOR
            break;
        case 5:
            if (funct7 == 0x00) wb(x[rs1] >> (x[rs2] & 0x3f));       // SRL
            else if (funct7 == 0x20) wb((uint64_t)(a >> (x[rs2] & 0x3f))); // SRA
            else { exit_reason = Exit::ILLEGAL; return false; }
            break;
        case 6:
            if (funct7 != 0) { exit_reason = Exit::ILLEGAL; return false; }
            wb((uint64_t)(a | b));                           // OR
            break;
        case 7:
            if (funct7 != 0) { exit_reason = Exit::ILLEGAL; return false; }
            wb((uint64_t)(a & b));                           // AND
            break;
        }
        break;
    }
    case 0x0F: // FENCE / FENCE.I - treated as NOP
        break;
    case 0x73: // ECALL / EBREAK
        if (i_imm == 0) { exit_reason = Exit::ECALL; return false; }
        else if (i_imm == 1) { exit_reason = Exit::EBREAK; return false; }
        else { exit_reason = Exit::ILLEGAL; return false; }
    case 0x1B: { // *IW imm arith
        int32_t a = (int32_t)x[rs1];
        switch (funct3) {
        case 0: wb((uint64_t)(int64_t)(int32_t)(a + (int32_t)i_imm)); break; // ADDIW
        case 1:
            if (funct7 != 0) { exit_reason = Exit::ILLEGAL; return false; }
            wb((uint64_t)(int64_t)(int32_t)(a << shamtw));               // SLLIW
            break;
        case 5:
            if (funct7 == 0x00) wb((uint64_t)(int64_t)(int32_t)((uint32_t)a >> shamtw)); // SRLIW
            else if (funct7 == 0x20) wb((uint64_t)(int64_t)(a >> shamtw));               // SRAIW
            else { exit_reason = Exit::ILLEGAL; return false; }
            break;
        default: exit_reason = Exit::ILLEGAL; return false;
        }
        break;
    }
    case 0x3B: { // *W reg-reg (RV64I + M)
        int32_t a = (int32_t)x[rs1], b = (int32_t)x[rs2];
        if (funct7 == 0x01) { // M extension W-variants
            switch (funct3) {
            case 0: wb((uint64_t)(int64_t)(int32_t)(a * b)); break;       // MULW
            case 4: // DIVW
                if (b == 0) wb((uint64_t)-1);
                else if (a == INT32_MIN && b == -1) wb((uint64_t)(int64_t)a);
                else wb((uint64_t)(int64_t)(int32_t)(a / b));
                break;
            case 5: // DIVUW
                if (b == 0) wb((uint64_t)(int64_t)(int32_t)-1);
                else wb((uint64_t)(int64_t)(int32_t)((uint32_t)a / (uint32_t)b));
                break;
            case 6: // REMW
                if (b == 0) wb((uint64_t)(int64_t)a);
                else if (a == INT32_MIN && b == -1) wb(0);
                else wb((uint64_t)(int64_t)(int32_t)(a % b));
                break;
            case 7: // REMUW
                if (b == 0) wb((uint64_t)(int64_t)a);
                else wb((uint64_t)(int64_t)(int32_t)((uint32_t)a % (uint32_t)b));
                break;
            default: exit_reason = Exit::ILLEGAL; return false;
            }
            break;
        }
        switch (funct3) {
        case 0:
            if (funct7 == 0x00) wb((uint64_t)(int64_t)(int32_t)(a + b)); // ADDW
            else if (funct7 == 0x20) wb((uint64_t)(int64_t)(int32_t)(a - b)); // SUBW
            else { exit_reason = Exit::ILLEGAL; return false; }
            break;
        case 1:
            if (funct7 != 0) { exit_reason = Exit::ILLEGAL; return false; }
            wb((uint64_t)(int64_t)(int32_t)(a << (b & 0x1f)));           // SLLW
            break;
        case 5:
            if (funct7 == 0x00) wb((uint64_t)(int64_t)(int32_t)((uint32_t)a >> (b & 0x1f))); // SRLW
            else if (funct7 == 0x20) wb((uint64_t)(int64_t)(int32_t)(a >> (b & 0x1f)));      // SRAW
            else { exit_reason = Exit::ILLEGAL; return false; }
            break;
        default: exit_reason = Exit::ILLEGAL; return false;
        }
        break;
    }
    default:
        exit_reason = Exit::ILLEGAL;
        return false;
    }

    x[0] = 0;
    pc = next_pc;
    return true;
}
