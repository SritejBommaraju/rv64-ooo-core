// Golden byte-map memory + a behavioral in-order memory-side responder for l1d.
#pragma once
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <unordered_map>

// Sparse byte-addressable memory. Used both as the "golden" CPU-visible
// memory (updated the instant a store is accepted) and as the cache's
// backing store (updated only when the cache writes a line back).
struct ByteMem {
  std::unordered_map<uint64_t, uint8_t> bytes;

  uint8_t get(uint64_t addr) const {
    auto it = bytes.find(addr);
    return it == bytes.end() ? 0 : it->second;
  }
  void set(uint64_t addr, uint8_t v) { bytes[addr] = v; }

  uint64_t read(uint64_t addr, int size_log2) const {
    uint64_t v = 0;
    int n = 1 << size_log2;
    for (int i = n - 1; i >= 0; i--) v = (v << 8) | get(addr + i);
    return v;
  }
  void write(uint64_t addr, int size_log2, uint64_t v) {
    int n = 1 << size_log2;
    for (int i = 0; i < n; i++) { set(addr + i, (uint8_t)(v & 0xFF)); v >>= 8; }
  }

  std::array<uint8_t, 64> read_line(uint64_t line_addr) const {
    std::array<uint8_t, 64> line{};
    for (int i = 0; i < 64; i++) line[i] = get(line_addr + i);
    return line;
  }
  void write_line(uint64_t line_addr, const std::array<uint8_t, 64> &line) {
    for (int i = 0; i < 64; i++) set(line_addr + i, line[i]);
  }

  // seed both instances identically so the initial memory image matches
  void seed_random(uint64_t base, uint64_t nbytes, uint32_t rng_seed) {
    srand(rng_seed);
    for (uint64_t a = base; a < base + nbytes; a++) set(a, (uint8_t)(rand() & 0xFF));
  }

  void diff_report(const ByteMem &o, int max_lines) const {
    int n = 0;
    for (auto &kv : bytes) {
      if (kv.second != o.get(kv.first)) {
        fprintf(stderr, "DIFF addr=%llx mine=%02x other=%02x\n", (unsigned long long)kv.first, kv.second, o.get(kv.first));
        if (++n >= max_lines) return;
      }
    }
  }
  // semantic equality: a byte absent from the map is defined as 0, so a
  // written-back line's untouched (still-zero) bytes don't count as a diff
  // just because they materialized a map entry that the other side lacks.
  bool equals(const ByteMem &o) const {
    for (auto &kv : bytes) if (kv.second != o.get(kv.first)) return false;
    for (auto &kv : o.bytes) if (kv.second != get(kv.first)) return false;
    return true;
  }
};

// Little-endian conversion between a 512-bit Verilator wide signal (16
// uint32_t words) and a 64-byte array.
inline std::array<uint8_t, 64> wide_to_bytes(const uint32_t *w) {
  std::array<uint8_t, 64> b{};
  for (int i = 0; i < 16; i++)
    for (int j = 0; j < 4; j++) b[i * 4 + j] = (uint8_t)((w[i] >> (8 * j)) & 0xFF);
  return b;
}
inline void bytes_to_wide(const std::array<uint8_t, 64> &b, uint32_t *w) {
  for (int i = 0; i < 16; i++) {
    uint32_t v = 0;
    for (int j = 0; j < 4; j++) v |= (uint32_t)b[i * 4 + j] << (8 * j);
    w[i] = v;
  }
}

// Behavioral memory-side responder for l1d's single-outstanding mem port.
// mem_req_ready is tied high by the testbench (the DUT never issues a second
// request before the first resolves), so this model only ever tracks one
// in-flight read at a time; writes commit to `backing` immediately on accept
// (no response, matching the l1d contract) and reads are answered after a
// random 1..20 cycle latency, in request order.
struct MemResponder {
  ByteMem &backing;
  bool pending = false;
  int countdown = 0;
  std::array<uint8_t, 64> pending_line{};
  uint64_t writebacks_seen = 0;
  int min_latency = 1; // tests can raise this to force a wide fill window

  explicit MemResponder(ByteMem &b) : backing(b) {}

  // call once per cycle with the DUT's *current* combinational mem_req outputs;
  // returns true if a response should be asserted THIS cycle, filling resp_bytes.
  bool step(bool req_valid, uint64_t req_addr, bool req_we, const uint32_t *req_wdata,
            std::array<uint8_t, 64> &resp_bytes) {
    if (pending) {
      countdown--;
      if (countdown == 0) {
        pending = false;
        resp_bytes = pending_line;
        return true;
      }
    }
    if (req_valid && !pending) {
      if (req_we) {
        backing.write_line(req_addr, wide_to_bytes(req_wdata));
        writebacks_seen++;
      } else {
        pending = true;
        countdown = min_latency + (rand() % (21 - min_latency));
        pending_line = backing.read_line(req_addr);
      }
    }
    return false;
  }
};
