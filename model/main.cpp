#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include "iss.h"

// Writes the shared 33-line register dump format: x0..x31 then pc, each as "name 0x<16 hex digits>\n".
static void write_dump(const Iss& iss, const std::string& path) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) { fprintf(stderr, "failed to open dump file %s\n", path.c_str()); return; }
    for (int i = 0; i < 32; i++)
        fprintf(f, "x%d 0x%016llx\n", i, (unsigned long long)iss.x[i]);
    fprintf(f, "pc 0x%016llx\n", (unsigned long long)iss.pc);
    fclose(f);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("usage: iss <program.bin> [--max-steps N] [--dump-regs <path>] [--trace]\n");
        return 1;
    }

    std::string prog_path = argv[1];
    int max_steps = 10000;
    std::string dump_path;
    bool trace = false;

    for (int i = 2; i < argc; i++) {
        if (std::strcmp(argv[i], "--max-steps") == 0 && i + 1 < argc) {
            max_steps = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "--dump-regs") == 0 && i + 1 < argc) {
            dump_path = argv[++i];
        } else if (std::strcmp(argv[i], "--trace") == 0) {
            trace = true;
        }
    }

    std::ifstream f(prog_path, std::ios::binary);
    if (!f) {
        printf("failed to open %s\n", prog_path.c_str());
        return 1;
    }
    std::vector<uint8_t> prog((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());

    Iss iss;
    iss.load(prog);

    int step = 0;
    int result = 1;
    for (; step < max_steps; step++) {
        bool ok = iss.step();
        if (trace) {
            printf("step %d pc=0x%016llx insn=0x%08x", step, (unsigned long long)iss.pc, iss.last_insn);
            if (iss.last_rd > 0) printf(" x%d=0x%016llx", iss.last_rd, (unsigned long long)iss.last_rd_val);
            printf("\n");
        }
        if (!ok) {
            switch (iss.exit_reason) {
            case Iss::Exit::ECALL: printf("ECALL halt at step %d\n", step); result = 2; break;
            case Iss::Exit::EBREAK: printf("EBREAK halt at step %d\n", step); result = 3; break;
            case Iss::Exit::ILLEGAL: printf("ILLEGAL instruction 0x%08x at pc 0x%016llx, step %d\n",
                                             iss.last_insn, (unsigned long long)iss.pc, step); result = 4; break;
            default: result = 4; break;
            }
            if (!dump_path.empty()) write_dump(iss, dump_path);
            return result;
        }
        if (iss.x[31] == 1) {
            printf("PASS at step %d\n", step);
            if (!dump_path.empty()) write_dump(iss, dump_path);
            return 0;
        }
    }

    printf("FAIL: timed out\n");
    if (!dump_path.empty()) write_dump(iss, dump_path);
    return 1;
}
