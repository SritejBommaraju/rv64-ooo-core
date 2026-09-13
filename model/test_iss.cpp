#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "iss.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static uint32_t enc_r(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode) {
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}
static uint32_t enc_i(int32_t imm, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode) {
    return ((uint32_t)(imm & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}
static uint32_t enc_s(int32_t imm, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t opcode) {
    uint32_t u = (uint32_t)imm;
    return ((u & 0xfe0) << 20) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((u & 0x1f) << 7) | opcode;
}
static uint32_t enc_b(int32_t imm, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t opcode) {
    uint32_t u = (uint32_t)imm;
    return (((u >> 12) & 1) << 31) | (((u >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | (((u >> 1) & 0xf) << 8) | (((u >> 11) & 1) << 7) | opcode;
}
[[maybe_unused]] static uint32_t enc_u(int32_t imm, uint32_t rd, uint32_t opcode) {
    return ((uint32_t)imm & 0xfffff000) | (rd << 7) | opcode;
}
[[maybe_unused]] static uint32_t enc_j(int32_t imm, uint32_t rd, uint32_t opcode) {
    uint32_t u = (uint32_t)imm;
    return (((u >> 20) & 1) << 31) | (((u >> 1) & 0x3ff) << 21) | (((u >> 11) & 1) << 20) |
           (((u >> 12) & 0xff) << 12) | (rd << 7) | opcode;
}

// Places a single instruction word at a fixed code address (away from data at address 0) and runs one step.
static const uint64_t CODE_ADDR = 0x100;
static void run1(Iss& iss, uint32_t insn) {
    iss.pc = CODE_ADDR;
    std::memcpy(iss.mem.data() + CODE_ADDR, &insn, 4);
    iss.step();
}

int main() {
    // MULH(-1,-1) = 0
    { Iss iss; iss.x[1] = (uint64_t)-1; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_r(0x01, 2, 1, 1, 3, 0x33));
      CHECK(iss.x[3] == 0, "MULH(-1,-1)"); }

    // MULHU(-1,-1) = 0xFFFFFFFFFFFFFFFE
    { Iss iss; iss.x[1] = (uint64_t)-1; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_r(0x01, 2, 1, 3, 3, 0x33));
      CHECK(iss.x[3] == 0xFFFFFFFFFFFFFFFEULL, "MULHU(-1,-1)"); }

    // MULHSU(-1,1) = -1
    { Iss iss; iss.x[1] = (uint64_t)-1; iss.x[2] = 1;
      run1(iss, enc_r(0x01, 2, 1, 2, 3, 0x33));
      CHECK(iss.x[3] == (uint64_t)-1, "MULHSU(-1,1)"); }

    // DIV(x,0) = -1
    { Iss iss; iss.x[1] = 42; iss.x[2] = 0;
      run1(iss, enc_r(0x01, 2, 1, 4, 3, 0x33));
      CHECK(iss.x[3] == (uint64_t)-1, "DIV(x,0)"); }

    // REM(x,0) = x
    { Iss iss; iss.x[1] = 42; iss.x[2] = 0;
      run1(iss, enc_r(0x01, 2, 1, 6, 3, 0x33));
      CHECK(iss.x[3] == 42, "REM(x,0)"); }

    // DIV(INT64_MIN,-1) = INT64_MIN
    { Iss iss; iss.x[1] = (uint64_t)INT64_MIN; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_r(0x01, 2, 1, 4, 3, 0x33));
      CHECK(iss.x[3] == (uint64_t)INT64_MIN, "DIV(INT64_MIN,-1)"); }

    // REM(INT64_MIN,-1) = 0
    { Iss iss; iss.x[1] = (uint64_t)INT64_MIN; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_r(0x01, 2, 1, 6, 3, 0x33));
      CHECK(iss.x[3] == 0, "REM(INT64_MIN,-1)"); }

    // DIVW(INT32_MIN,-1) sign-extended = INT32_MIN as 64-bit
    { Iss iss; iss.x[1] = (uint64_t)(int64_t)INT32_MIN; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_r(0x01, 2, 1, 4, 3, 0x3B));
      CHECK(iss.x[3] == (uint64_t)(int64_t)INT32_MIN, "DIVW(INT32_MIN,-1)"); }

    // SRAIW of a negative 32-bit value
    { Iss iss; iss.x[1] = (uint64_t)(int64_t)(int32_t)0x80000000;
      run1(iss, enc_i(0x400 | 4, 1, 5, 3, 0x1B)); // SRAIW rs1,4
      CHECK(iss.x[3] == (uint64_t)(int64_t)(int32_t)0xF8000000, "SRAIW negative"); }

    // SRLIW of a negative 32-bit value (logical, zero-extends within 32 bits then sign-extends result)
    { Iss iss; iss.x[1] = (uint64_t)(int64_t)(int32_t)0x80000000;
      run1(iss, enc_i(4, 1, 5, 3, 0x1B)); // SRLIW rs1,4
      CHECK(iss.x[3] == 0x08000000ULL, "SRLIW negative"); }

    // ADDIW overflow wrap
    { Iss iss; iss.x[1] = (uint64_t)(int64_t)0x7FFFFFFF;
      run1(iss, enc_i(1, 1, 0, 3, 0x1B)); // ADDIW rs1,1
      CHECK(iss.x[3] == (uint64_t)(int64_t)(int32_t)0x80000000, "ADDIW overflow"); }

    // SLT on 0x8000000000000000 (as signed, this is negative and less than 0)
    { Iss iss; iss.x[1] = 0x8000000000000000ULL; iss.x[2] = 0;
      run1(iss, enc_r(0, 2, 1, 2, 3, 0x33));
      CHECK(iss.x[3] == 1, "SLT 0x8000... < 0"); }

    // SLTU on 0x8000000000000000 (unsigned, this is huge, not less than 0)
    { Iss iss; iss.x[1] = 0x8000000000000000ULL; iss.x[2] = 0;
      run1(iss, enc_r(0, 2, 1, 3, 3, 0x33));
      CHECK(iss.x[3] == 0, "SLTU 0x8000... < 0"); }

    // LB/LBU/LH/LHU/LW/LWU extension
    { Iss iss;
      iss.mem[0] = 0x80; // LB -> sign extend negative, LBU -> zero extend
      iss.x[1] = 0;
      run1(iss, enc_i(0, 1, 0, 3, 0x03)); // LB
      CHECK(iss.x[3] == (uint64_t)(int64_t)-128, "LB sign extend");
      run1(iss, enc_i(0, 1, 4, 3, 0x03)); // LBU
      CHECK(iss.x[3] == 0x80, "LBU zero extend"); }
    { Iss iss;
      iss.mem[0] = 0x00; iss.mem[1] = 0x80; // 0x8000
      iss.x[1] = 0;
      run1(iss, enc_i(0, 1, 1, 3, 0x03)); // LH
      CHECK(iss.x[3] == (uint64_t)(int64_t)(int16_t)0x8000, "LH sign extend");
      run1(iss, enc_i(0, 1, 5, 3, 0x03)); // LHU
      CHECK(iss.x[3] == 0x8000, "LHU zero extend"); }
    { Iss iss;
      iss.mem[0] = 0; iss.mem[1] = 0; iss.mem[2] = 0; iss.mem[3] = 0x80; // 0x80000000
      iss.x[1] = 0;
      run1(iss, enc_i(0, 1, 2, 3, 0x03)); // LW
      CHECK(iss.x[3] == (uint64_t)(int64_t)(int32_t)0x80000000, "LW sign extend");
      run1(iss, enc_i(0, 1, 6, 3, 0x03)); // LWU
      CHECK(iss.x[3] == 0x80000000ULL, "LWU zero extend"); }

    // SD/LD round trip
    { Iss iss; iss.x[1] = 0; iss.x[2] = 0x1122334455667788ULL;
      run1(iss, enc_s(0, 2, 1, 3, 0x23)); // SD x2, 0(x1)
      run1(iss, enc_i(0, 1, 3, 4, 0x03)); // LD x4, 0(x1)
      CHECK(iss.x[4] == 0x1122334455667788ULL, "SD/LD round trip"); }

    // JALR clears bit 0
    { Iss iss; iss.x[1] = 0x11; // odd target
      run1(iss, enc_i(0, 1, 0, 3, 0x67)); // JALR x3, 0(x1)
      CHECK(iss.pc == 0x10, "JALR clears bit 0");
      CHECK(iss.x[3] == CODE_ADDR + 4, "JALR link value"); }

    // All six branch conditions taken/not-taken
    { Iss iss; iss.x[1] = 5; iss.x[2] = 5;
      run1(iss, enc_b(8, 2, 1, 0, 0x63)); // BEQ taken
      CHECK(iss.pc == CODE_ADDR + 8, "BEQ taken"); }
    { Iss iss; iss.x[1] = 5; iss.x[2] = 6;
      run1(iss, enc_b(8, 2, 1, 0, 0x63)); // BEQ not taken
      CHECK(iss.pc == CODE_ADDR + 4, "BEQ not taken"); }
    { Iss iss; iss.x[1] = 5; iss.x[2] = 6;
      run1(iss, enc_b(8, 2, 1, 1, 0x63)); // BNE taken
      CHECK(iss.pc == CODE_ADDR + 8, "BNE taken"); }
    { Iss iss; iss.x[1] = 5; iss.x[2] = 5;
      run1(iss, enc_b(8, 2, 1, 1, 0x63)); // BNE not taken
      CHECK(iss.pc == CODE_ADDR + 4, "BNE not taken"); }
    { Iss iss; iss.x[1] = (uint64_t)-1; iss.x[2] = 1;
      run1(iss, enc_b(8, 2, 1, 4, 0x63)); // BLT taken (-1 < 1)
      CHECK(iss.pc == CODE_ADDR + 8, "BLT taken"); }
    { Iss iss; iss.x[1] = 1; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_b(8, 2, 1, 4, 0x63)); // BLT not taken
      CHECK(iss.pc == CODE_ADDR + 4, "BLT not taken"); }
    { Iss iss; iss.x[1] = 1; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_b(8, 2, 1, 5, 0x63)); // BGE taken (1 >= -1)
      CHECK(iss.pc == CODE_ADDR + 8, "BGE taken"); }
    { Iss iss; iss.x[1] = (uint64_t)-1; iss.x[2] = 1;
      run1(iss, enc_b(8, 2, 1, 5, 0x63)); // BGE not taken
      CHECK(iss.pc == CODE_ADDR + 4, "BGE not taken"); }
    { Iss iss; iss.x[1] = 1; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_b(8, 2, 1, 6, 0x63)); // BLTU taken (1 < huge)
      CHECK(iss.pc == CODE_ADDR + 8, "BLTU taken"); }
    { Iss iss; iss.x[1] = (uint64_t)-1; iss.x[2] = 1;
      run1(iss, enc_b(8, 2, 1, 6, 0x63)); // BLTU not taken
      CHECK(iss.pc == CODE_ADDR + 4, "BLTU not taken"); }
    { Iss iss; iss.x[1] = (uint64_t)-1; iss.x[2] = 1;
      run1(iss, enc_b(8, 2, 1, 7, 0x63)); // BGEU taken (huge >= 1)
      CHECK(iss.pc == CODE_ADDR + 8, "BGEU taken"); }
    { Iss iss; iss.x[1] = 1; iss.x[2] = (uint64_t)-1;
      run1(iss, enc_b(8, 2, 1, 7, 0x63)); // BGEU not taken
      CHECK(iss.pc == CODE_ADDR + 4, "BGEU not taken"); }

    if (failures == 0) printf("All tests passed.\n");
    else printf("%d test(s) failed.\n", failures);
    return failures == 0 ? 0 : 1;
}
