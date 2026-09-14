#include <cstdio>
#include <cstdint>
#include <cstring>
#include "Vmuldiv.h"
#include "verilated.h"
#include "../../model/iss.h"

// R-type encoder matching model/test_iss.cpp: funct7=0x01 (M-extension), opcode 0x33 (64-bit) / 0x3B (W).
static uint32_t enc_r(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode) {
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}

static const uint64_t CODE_ADDR = 0x100;

// Runs op(a,b) through the golden ISS and returns the result in x3 (rd=3, rs1=1, rs2=2).
static uint64_t golden(uint64_t a, uint64_t b, uint32_t funct3, bool is_word) {
    Iss iss;
    iss.x[1] = a; iss.x[2] = b;
    uint32_t opcode = is_word ? 0x3B : 0x33;
    uint32_t insn = enc_r(0x01, 2, 1, funct3, 3, opcode);
    iss.pc = CODE_ADDR;
    std::memcpy(iss.mem.data() + CODE_ADDR, &insn, 4);
    iss.step();
    return iss.x[3];
}

// LFSR for reproducible pseudo-random test vectors.
static uint64_t lfsr_state = 0x123456789ABCDEFULL;
static uint64_t next_rand() {
    lfsr_state ^= lfsr_state << 13;
    lfsr_state ^= lfsr_state >> 7;
    lfsr_state ^= lfsr_state << 17;
    return lfsr_state;
}

static Vmuldiv* dut;
static int mismatches = 0;
static uint64_t cycle_count = 0;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
    cycle_count++;
}

// Drives one (a,b,op,is_word) case: pulses start, waits for done, checks y against the golden model.
static void run_case(uint64_t a, uint64_t b, uint32_t funct3, bool is_word) {
    uint64_t expect = golden(a, b, funct3, is_word);

    dut->a = a; dut->b = b; dut->op = funct3; dut->is_word = is_word;
    dut->start = 1;
    tick();
    dut->start = 0;

    int guard = 200;
    while (!dut->done && guard-- > 0) tick();

    if (!dut->done) {
        printf("FAIL: timeout waiting for done (a=%llx b=%llx op=%u w=%d)\n",
               (unsigned long long)a, (unsigned long long)b, funct3, is_word);
        mismatches++;
        return;
    }
    if (dut->y != expect) {
        printf("MISMATCH: a=%llx b=%llx op=%u w=%d got=%llx want=%llx\n",
               (unsigned long long)a, (unsigned long long)b, funct3, is_word,
               (unsigned long long)dut->y, (unsigned long long)expect);
        mismatches++;
    }
    tick(); // let done deassert before the next case
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vmuldiv;

    dut->rst = 1; dut->start = 0; dut->a = 0; dut->b = 0; dut->op = 0; dut->is_word = 0;
    tick();
    dut->rst = 0;

    // start-not-accepted / done-quiescent-without-start check
    tick();
    if (dut->busy) { printf("FAIL: busy asserted with no start ever issued\n"); mismatches++; }
    if (dut->done) { printf("FAIL: done asserted with no start ever issued\n"); mismatches++; }

    const uint32_t ops[] = {0,1,2,3,4,5,6,7}; // MUL,MULH,MULHSU,MULHU,DIV,DIVU,REM,REMU

    // explicit corner cases
    struct Corner { uint64_t a, b; };
    Corner corners[] = {
        {0, 0}, {42, 0}, {0, 1}, {1, 0}, {(uint64_t)-1, 1}, {1, (uint64_t)-1},
        {0x8000000000000000ULL, 0xFFFFFFFFFFFFFFFFULL},          // INT64_MIN / -1
        {0xFFFFFFFF80000000ULL, 0xFFFFFFFFFFFFFFFFULL},           // INT32_MIN / -1 (W form uses low 32 bits)
        {0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL},
        {0xFFFFFFFFFFFFFFFFULL, 0x0000000000000001ULL},
        {0x7FFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL},
    };
    for (auto& c : corners)
        for (uint32_t op : ops)
            for (int w = 0; w < 2; w++)
                run_case(c.a, c.b, op, w);

    // a start issued while busy must not be accepted: kick off a slow DIV, then try to restart mid-flight
    // with a different operand and confirm the original (a,b) result still comes out.
    {
        uint64_t a = 0x123456789ABCDEF0ULL, b = 7;
        uint64_t expect = golden(a, b, 4, false);
        dut->a = a; dut->b = b; dut->op = 4; dut->is_word = 0; dut->start = 1;
        tick();
        dut->start = 0;
        tick(); // now busy
        if (!dut->busy) { printf("FAIL: expected busy after start\n"); mismatches++; }
        dut->a = 999; dut->b = 3; dut->op = 5; dut->start = 1; // attempted interrupt, should be ignored
        tick();
        dut->start = 0;
        int guard = 200;
        while (!dut->done && guard-- > 0) tick();
        if (dut->y != expect) {
            printf("MISMATCH: start-while-busy corrupted result: got=%llx want=%llx\n",
                   (unsigned long long)dut->y, (unsigned long long)expect);
            mismatches++;
        }
        tick();
    }

    // 100,000 random cases
    for (int i = 0; i < 100000; i++) {
        uint64_t a = next_rand();
        uint64_t b = next_rand();
        uint32_t op = ops[next_rand() % 8];
        bool is_word = next_rand() & 1;
        run_case(a, b, op, is_word);
    }

    if (mismatches == 0)
        printf("PASS: 0 mismatches over %llu cycles\n", (unsigned long long)cycle_count);
    else
        printf("FAIL: %d mismatches\n", mismatches);

    delete dut;
    return mismatches == 0 ? 0 : 1;
}
