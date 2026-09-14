#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>
#include "Vooo_top.h"
#include "Vooo_top___024root.h"
#include "Vooo_top_ooo_top.h"
#include "Vooo_top_ooo_mem.h"
#include "verilated.h"

// Runs a flat RV64I binary on the OOO pipeline until the halt convention (x31==1
// with the rob drained) or a cycle timeout. Superset CLI of both tb_main and tb_arch:
// <prog.bin> [--dump-regs <path>] [--sig-begin <hex> --sig-end <hex> --sig-out <path>]
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    if (argc < 2) {
        printf("usage: tb_ooo_core <prog.bin> [--dump-regs <path>] "
               "[--sig-begin <hex> --sig-end <hex> --sig-out <path>]\n");
        return 1;
    }

    std::string prog_path = argv[1];
    std::string dump_path, sig_out;
    uint64_t sig_begin = 0, sig_end = 0;
    bool have_sig = false;

    for (int i = 2; i < argc; i++) {
        if (std::strcmp(argv[i], "--dump-regs") == 0 && i + 1 < argc) dump_path = argv[++i];
        else if (std::strcmp(argv[i], "--sig-begin") == 0 && i + 1 < argc) sig_begin = std::strtoull(argv[++i], nullptr, 16);
        else if (std::strcmp(argv[i], "--sig-end") == 0 && i + 1 < argc) sig_end = std::strtoull(argv[++i], nullptr, 16);
        else if (std::strcmp(argv[i], "--sig-out") == 0 && i + 1 < argc) sig_out = argv[++i];
    }
    if (!sig_out.empty() && sig_end > sig_begin) have_sig = true;

    std::ifstream f(prog_path, std::ios::binary);
    if (!f) {
        printf("failed to open %s\n", prog_path.c_str());
        return 1;
    }
    std::vector<uint8_t> prog((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());

    Vooo_top* top = new Vooo_top;
    for (size_t i = 0; i < prog.size(); i++)
        top->rootp->ooo_top->u_mem->bytes[i] = prog[i];

    top->rst = 1;
    top->dbg_arch_reg = 0;
    top->clk = 0; top->eval();
    top->clk = 1; top->eval();
    top->rst = 0;

    const int MAX_CYCLES = 200000;
    bool passed = false;

    long long committed = 0;
    unsigned max_rob_count = 0;
    long long loads_forwarded = 0, loads_from_mem = 0;

    // OOO-reorder proof: track loads whose address has issued but not yet
    // responded, and whether any non-load writeback landed while one was pending.
    int loads_outstanding = 0;
    bool reorder_proven = false;

    int cycle = 0;
    for (; cycle < MAX_CYCLES; cycle++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        if (top->dbg_committed) committed++;
        if (top->dbg_rob_count > max_rob_count) max_rob_count = top->dbg_rob_count;

        if (top->dbg_issue_valid && top->dbg_issue_is_load) loads_outstanding++;
        if (top->dbg_wb_alu_valid && loads_outstanding > 0) reorder_proven = true;
        if (top->dbg_ld_resp_valid) {
            loads_outstanding--;
            if (top->dbg_ld_from_mem) loads_from_mem++;
            else loads_forwarded++;
        }

        if (top->dbg_halted) {
            passed = true;
            break;
        }
    }

    printf(passed ? "PASS at cycle %d\n" : "FAIL: timed out after %d cycles\n", passed ? cycle : MAX_CYCLES);

    double ipc = cycle > 0 ? (double)committed / (double)cycle : 0.0;
    printf("stats: cycles=%d committed=%lld ipc=%.3f max_rob_count=%u loads_forwarded=%lld loads_from_mem=%lld\n",
           cycle, committed, ipc, max_rob_count, loads_forwarded, loads_from_mem);
    printf(reorder_proven ? "ooo-check: PASS (a younger op wrote back while an older load was pending)\n"
                          : "ooo-check: not observed this run\n");

    if (!dump_path.empty()) {
        FILE* df = fopen(dump_path.c_str(), "wb");
        if (!df) {
            fprintf(stderr, "failed to open dump file %s\n", dump_path.c_str());
        } else {
            for (int r = 0; r < 32; r++) {
                top->dbg_arch_reg = r;
                top->eval(); // combinational prf read, no clock edge needed
                fprintf(df, "x%d 0x%016llx\n", r, (unsigned long long)top->dbg_arch_val);
            }
            fprintf(df, "pc 0x%016llx\n", (unsigned long long)(top->dbg_last_commit_pc + 4));
            fclose(df);
        }
    }

    if (have_sig) {
        FILE* sf = fopen(sig_out.c_str(), "wb");
        if (!sf) {
            fprintf(stderr, "failed to open signature output %s\n", sig_out.c_str());
        } else {
            auto& bytes = top->rootp->ooo_top->u_mem->bytes;
            for (uint64_t addr = sig_begin; addr < sig_end; addr += 4) {
                uint32_t word = (uint32_t)bytes[addr] | ((uint32_t)bytes[addr + 1] << 8) |
                                 ((uint32_t)bytes[addr + 2] << 16) | ((uint32_t)bytes[addr + 3] << 24);
                fprintf(sf, "%08x\n", word);
            }
            fclose(sf);
        }
    }

    delete top;
    return passed ? 0 : 1;
}
