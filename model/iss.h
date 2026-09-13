#pragma once
#include <cstdint>
#include <vector>

// RV64IM instruction-set simulator (golden model). Flat 64 KiB little-endian memory at address 0.
class Iss {
public:
    uint64_t x[32] = {0};
    uint64_t pc = 0;
    std::vector<uint8_t> mem;

    enum class Exit { NONE, ECALL, EBREAK, ILLEGAL };
    Exit exit_reason = Exit::NONE;
    uint32_t last_insn = 0;
    int last_rd = -1;      // rd written by the most recent step, -1 if none
    uint64_t last_rd_val = 0;

    Iss();
    void load(const std::vector<uint8_t>& image);
    bool step();          // executes one instruction; returns false on halt (ecall/ebreak/illegal)

private:
    uint8_t  load8(uint64_t addr) const;
    uint16_t load16(uint64_t addr) const;
    uint32_t load32(uint64_t addr) const;
    uint64_t load64(uint64_t addr) const;
    void store8(uint64_t addr, uint8_t v);
    void store16(uint64_t addr, uint16_t v);
    void store32(uint64_t addr, uint32_t v);
    void store64(uint64_t addr, uint64_t v);
    uint32_t fetch(uint64_t addr) const;
};
