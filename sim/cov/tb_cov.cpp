#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include "Vtop.h"
#include "Vtop___024root.h"
#include "Vtop_top.h"
#include "Vtop_core.h"
#include "Vtop_mem.h"
#include "Vtop_regfile.h"
#include "verilated.h"
#include "verilated_cov.h"

// Loads a flat binary program into memory then runs until x31 == 1 (test-pass convention) or cycle limit.
// Copy of ../tb_main.cpp with coverage.dat written before returning.
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

    std::string dump_path;
    if (argc >= 4 && std::strcmp(argv[2], "--dump-regs") == 0) dump_path = argv[3];

    auto write_dump = [&]() {
        if (dump_path.empty()) return;
        FILE* df = fopen(dump_path.c_str(), "wb");
        if (!df) { fprintf(stderr, "failed to open dump file %s\n", dump_path.c_str()); return; }
        for (int i = 0; i < 32; i++)
            fprintf(df, "x%d 0x%016llx\n", i, (unsigned long long)top->rootp->top->u_core->u_regfile->regs[i]);
        fprintf(df, "pc 0x%016llx\n", (unsigned long long)top->rootp->top->u_core->__PVT__pc);
        fclose(df);
    };

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
            write_dump();
            Verilated::threadContextp()->coveragep()->write("coverage.dat");
            delete top;
            return 0;
        }
    }

    printf("FAIL: timed out after %d cycles\n", MAX_CYCLES);
    write_dump();
    Verilated::threadContextp()->coveragep()->write("coverage.dat");
    delete top;
    return 1;
}
