#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>
#include "Vtop.h"
#include "Vtop___024root.h"
#include "Vtop_top.h"
#include "Vtop_core.h"
#include "Vtop_mem.h"
#include "Vtop_regfile.h"
#include "verilated.h"

// Arch-test style TB: runs a program to halt (x31==1) or timeout, then dumps a byte range of
// u_mem.bytes as one 32-bit little-endian word per line in lowercase hex (RISCOF signature format).
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    if (argc < 2) {
        printf("usage: tb_arch <prog.bin> --sig-begin <hex> --sig-end <hex> --sig-out <path>\n");
        return 1;
    }

    std::string prog_path = argv[1];
    uint64_t sig_begin = 0, sig_end = 0;
    std::string sig_out;
    for (int i = 2; i < argc; i++) {
        if (std::strcmp(argv[i], "--sig-begin") == 0 && i + 1 < argc) sig_begin = std::strtoull(argv[++i], nullptr, 16);
        else if (std::strcmp(argv[i], "--sig-end") == 0 && i + 1 < argc) sig_end = std::strtoull(argv[++i], nullptr, 16);
        else if (std::strcmp(argv[i], "--sig-out") == 0 && i + 1 < argc) sig_out = argv[++i];
    }
    if (sig_out.empty() || sig_end <= sig_begin) {
        printf("error: --sig-begin/--sig-end/--sig-out required\n");
        return 1;
    }

    std::ifstream f(prog_path, std::ios::binary);
    if (!f) {
        printf("failed to open %s\n", prog_path.c_str());
        return 1;
    }
    std::vector<uint8_t> prog((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());

    Vtop* top = new Vtop;
    for (size_t i = 0; i < prog.size(); i++)
        top->rootp->top->u_mem->bytes[i] = prog[i];

    top->rst = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->rst = 0;

    const int MAX_CYCLES = 200000;
    bool passed = false;
    for (int cycle = 0; cycle < MAX_CYCLES; cycle++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        if (top->rootp->top->u_core->u_regfile->regs[31] == 1) {
            passed = true;
            break;
        }
    }
    printf(passed ? "PASS\n" : "FAIL: timed out after %d cycles\n", MAX_CYCLES);

    FILE* sf = fopen(sig_out.c_str(), "wb");
    if (!sf) {
        fprintf(stderr, "failed to open signature output %s\n", sig_out.c_str());
        delete top;
        return 1;
    }
    for (uint64_t addr = sig_begin; addr < sig_end; addr += 4) {
        auto& bytes = top->rootp->top->u_mem->bytes;
        uint32_t word = (uint32_t)bytes[addr] | ((uint32_t)bytes[addr + 1] << 8) |
                         ((uint32_t)bytes[addr + 2] << 16) | ((uint32_t)bytes[addr + 3] << 24);
        fprintf(sf, "%08x\n", word);
    }
    fclose(sf);

    delete top;
    return passed ? 0 : 1;
}
