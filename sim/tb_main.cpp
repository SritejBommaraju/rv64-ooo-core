#include <cstdio>
#include <cstdlib>
#include <fstream>
#include "Vtop.h"
#include "Vtop___024root.h"
#include "Vtop_top.h"
#include "Vtop_core.h"
#include "Vtop_mem.h"
#include "Vtop_regfile.h"
#include "verilated.h"

// Loads a flat binary program into memory then runs until x31 == 1 (test-pass convention) or cycle limit.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtop* top = new Vtop;

    if (argc < 2) {
        printf("usage: sim <program.bin>\n");
        return 1;
    }

    std::ifstream f(argv[1], std::ios::binary);
    if (!f) {
        printf("failed to open %s\n", argv[1]);
        return 1;
    }
    std::vector<uint8_t> prog((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    for (size_t i = 0; i < prog.size(); i++)
        top->rootp->top->u_mem->bytes[i] = prog[i];

    top->rst = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->rst = 0;

    const int MAX_CYCLES = 10000;
    int cycle = 0;
    for (; cycle < MAX_CYCLES; cycle++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        uint64_t x31 = top->rootp->top->u_core->u_regfile->regs[31];
        if (x31 == 1) {
            printf("PASS at cycle %d\n", cycle);
            delete top;
            return 0;
        }
    }

    printf("FAIL: timed out after %d cycles\n", MAX_CYCLES);
    delete top;
    return 1;
}
