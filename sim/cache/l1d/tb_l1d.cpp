// Testbench for l1d: golden byte-map comparison + directed and random tests.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "Vl1d.h"
#include "verilated.h"
#include "cache_model.h"

static void tick(Vl1d *dut) {
  dut->clk = 1; dut->eval();
  dut->clk = 0; dut->eval();
}

static uint64_t mk_addr(uint64_t tag, uint64_t idx, uint64_t off) {
  return (tag << 12) | (idx << 6) | off;
}

struct PendingReq { bool is_read; uint64_t expected; };

// Drives one DUT + one golden/backing memory pair through the whole test.
struct Sim {
  Vl1d *dut;
  ByteMem golden, backing;
  MemResponder resp;
  bool tag_busy[16] = {};
  PendingReq slot[16] = {};
  std::vector<int> resp_log; // tags in arrival order
  bool mismatch = false;

  explicit Sim(uint32_t seed) : resp(backing) {
    dut = new Vl1d;
    golden.seed_random(0, 1ull << 20, seed);
    backing.seed_random(0, 1ull << 20, seed); // identical initial image
    dut->rst_n = 0; dut->clk = 0; dut->req_valid = 0; dut->flush_all = 0;
    dut->mem_req_ready = 1; dut->mem_resp_valid = 0;
    for (int i = 0; i < 4; i++) tick(dut);
    dut->rst_n = 1;
  }
  ~Sim() { delete dut; }

  int find_free_tag() {
    for (int t = 0; t < 16; t++) if (!tag_busy[t]) return t;
    return -1;
  }

  // one clock cycle; if tag>=0 and req_valid, presents that request. returns accepted.
  bool cycle(bool req_valid, uint64_t addr, bool we, int size_log2, uint64_t wdata, int tag, bool flush_all = false) {
    dut->req_valid = req_valid;
    dut->req_addr = addr;
    dut->req_we = we;
    dut->req_size = size_log2;
    dut->req_wdata = wdata;
    dut->req_tag = tag;
    dut->flush_all = flush_all;
    dut->eval();
    bool accepted = req_valid && dut->req_ready;
    if (accepted) {
      if (!we) {
        slot[tag] = {true, golden.read(addr, size_log2)};
      } else {
        golden.write(addr, size_log2, wdata);
        slot[tag] = {false, 0};
      }
      tag_busy[tag] = true;
    }

    uint32_t reqw[16];
    for (int i = 0; i < 16; i++) reqw[i] = dut->mem_req_wdata[i];
    std::array<uint8_t, 64> respbytes;
    bool resp_now = resp.step(dut->mem_req_valid, dut->mem_req_addr, dut->mem_req_we, reqw, respbytes);
    dut->mem_resp_valid = resp_now;
    if (resp_now) {
      uint32_t w[16];
      bytes_to_wide(respbytes, w);
      for (int i = 0; i < 16; i++) dut->mem_resp_rdata[i] = w[i];
    }
    dut->mem_req_ready = 1;

    tick(dut);

    if (dut->resp_valid) {
      int rt = dut->resp_tag;
      if (!tag_busy[rt]) {
        fprintf(stderr, "ERROR: unexpected resp on idle tag %d\n", rt);
        mismatch = true;
      } else {
        PendingReq &p = slot[rt];
        if (p.is_read && dut->resp_rdata != p.expected) {
          fprintf(stderr, "MISMATCH tag=%d got=%llx exp=%llx\n", rt,
                  (unsigned long long)dut->resp_rdata, (unsigned long long)p.expected);
          mismatch = true;
        }
        tag_busy[rt] = false;
        resp_log.push_back(rt);
      }
    }
    return accepted;
  }

  // issue a request, retrying (bubbling on non-accept) until accepted; returns the tag used.
  int issue(uint64_t addr, bool we, int size_log2, uint64_t wdata) {
    int t = find_free_tag();
    while (t < 0) { cycle(false, 0, 0, 0, 0, 0); t = find_free_tag(); }
    while (!cycle(true, addr, we, size_log2, wdata, t)) { /* held until accepted */ }
    return t;
  }

  // drain all outstanding responses.
  void drain() {
    while (true) {
      bool any = false;
      for (int t = 0; t < 16; t++) if (tag_busy[t]) any = true;
      if (!any) break;
      cycle(false, 0, 0, 0, 0, 0);
    }
  }

  void flush_and_check(bool &ok) {
    drain();
    dut->req_valid = 0;
    while (true) {
      cycle(false, 0, 0, 0, 0, 0, true);
      if (dut->flush_done) break;
    }
    ok = backing.equals(golden);
  }
};

static bool directed_tests() {
  Sim s(0xC0FFEE);
  bool fail = false;

  // cold miss read
  uint64_t a0 = mk_addr(1, 0, 0);
  int t = s.issue(a0, false, 3, 0);
  s.drain();
  if (s.mismatch) { fprintf(stderr, "FAIL cold miss\n"); fail = true; }

  // write hit (same line, now resident)
  s.issue(a0, true, 2, 0xDEADBEEF);
  s.drain();
  if (s.mismatch) { fprintf(stderr, "FAIL write hit\n"); fail = true; }
  int rt = s.issue(a0, false, 2, 0);
  s.drain();
  if (s.mismatch) { fprintf(stderr, "FAIL read-back after write hit\n"); fail = true; }
  (void)rt; (void)t;

  // dirty eviction then re-read: fill way0 & way1 of set 0 with two lines, write both dirty,
  // then bring in a third line to the same set (evicts one), then re-read the evicted address.
  uint64_t la = mk_addr(2, 0, 0), lb = mk_addr(3, 0, 0), lc = mk_addr(4, 0, 0);
  s.issue(la, true, 3, 0x1111111111111111ull); s.drain();
  s.issue(lb, true, 3, 0x2222222222222222ull); s.drain();
  s.issue(lc, false, 3, 0); s.drain(); // evicts la or lb (whichever is not-MRU)
  s.issue(la, false, 3, 0); s.drain(); // must reflect the write even if it was evicted+refetched
  s.issue(lb, false, 3, 0); s.drain();
  if (s.mismatch) { fprintf(stderr, "FAIL dirty eviction/re-read\n"); fail = true; }

  // 2-way conflict thrash: repeatedly bring in 5 distinct lines mapping to set 7
  for (int r = 0; r < 20; r++) {
    for (int k = 0; k < 5; k++) {
      uint64_t a = mk_addr(10 + k, 7, (k % 8) * 8);
      bool we = (k % 2) == 0;
      s.issue(a, we, 3, 0xA000000000000000ull + r * 16 + k);
      s.drain();
    }
  }
  if (s.mismatch) { fprintf(stderr, "FAIL conflict thrash\n"); fail = true; }

  // hit-under-miss: warm up 10 addresses in other sets, then issue one cold miss and,
  // before draining it, issue the 10 hits and confirm they all arrive before the miss resp.
  uint64_t hot_addrs[10];
  for (int i = 0; i < 10; i++) { hot_addrs[i] = mk_addr(20 + i, 40 + i, 0); s.issue(hot_addrs[i], false, 3, 0); }
  s.drain();
  size_t log_before = s.resp_log.size();
  uint64_t miss_addr = mk_addr(99, 50, 0);
  s.resp.min_latency = 15; // force the fill to take long enough to serve all 10 hits first
  int miss_tag = s.issue(miss_addr, false, 3, 0);
  int hit_tags[10];
  for (int i = 0; i < 10; i++) hit_tags[i] = s.issue(hot_addrs[i], false, 3, 0);
  s.drain();
  s.resp.min_latency = 1;
  int miss_pos = -1, worst_hit_pos = -1;
  for (size_t i = log_before; i < s.resp_log.size(); i++) {
    if (s.resp_log[i] == miss_tag) miss_pos = (int)i;
    for (int h : hit_tags) if (s.resp_log[i] == h && (int)i > worst_hit_pos) worst_hit_pos = (int)i;
  }
  if (miss_pos < 0 || worst_hit_pos < 0 || worst_hit_pos > miss_pos) {
    fprintf(stderr, "FAIL hit-under-miss ordering (miss_pos=%d worst_hit_pos=%d)\n", miss_pos, worst_hit_pos);
    fail = true;
  }
  if (s.mismatch) { fprintf(stderr, "FAIL hit-under-miss data\n"); fail = true; }

  // 4 misses outstanding then a 5th stalls
  {
    uint64_t m[5];
    for (int i = 0; i < 5; i++) m[i] = mk_addr(60 + i, 55 + i, 0); // distinct sets, no conflicts
    int mt[4];
    for (int i = 0; i < 4; i++) mt[i] = s.issue(m[i], false, 3, 0);
    // 5th must stall: req_ready deasserted while presented
    s.dut->req_valid = 1; s.dut->req_addr = m[4]; s.dut->req_we = 0; s.dut->req_size = 3;
    s.dut->req_tag = 0; s.dut->eval();
    if (s.dut->req_ready) { fprintf(stderr, "FAIL: 5th miss did not stall on full MSHRs\n"); fail = true; }
    s.dut->req_valid = 0; s.dut->eval();
    s.drain();
    for (int i = 0; i < 4; i++) (void)mt[i];
    s.issue(m[4], false, 3, 0);
    s.drain();
  }
  if (s.mismatch) { fprintf(stderr, "FAIL miss-under-miss data\n"); fail = true; }

  // same-line pending miss stalls
  {
    uint64_t base = mk_addr(70, 30, 0);
    int tag = s.find_free_tag();
    while (!s.cycle(true, base, false, 3, 0, tag)) {} // accept the primary miss
    // now try the same line (different offset) immediately: must stall
    s.dut->req_valid = 1; s.dut->req_addr = base + 8; s.dut->req_we = 0; s.dut->req_size = 3; s.dut->req_tag = 0;
    s.dut->eval();
    if (s.dut->req_ready) { fprintf(stderr, "FAIL: same-line pending miss did not stall\n"); fail = true; }
    s.dut->req_valid = 0; s.dut->eval();
    s.drain();
  }
  if (s.mismatch) { fprintf(stderr, "FAIL same-line-pending data\n"); fail = true; }

  // all sizes with sub-line offsets
  {
    uint64_t base = mk_addr(80, 20, 0);
    s.issue(base, false, 3, 0); s.drain(); // bring line in
    int sizes[4] = {0, 1, 2, 3};
    int maxoff[4] = {63, 62, 60, 56};
    for (int sz = 0; sz < 4; sz++) {
      for (int off = 0; off <= maxoff[sz]; off += 7) {
        uint64_t a = base + off;
        s.issue(a, true, sizes[sz], 0x0102030405060708ull + off);
        s.drain();
        s.issue(a, false, sizes[sz], 0);
        s.drain();
      }
    }
  }
  if (s.mismatch) { fprintf(stderr, "FAIL sub-line offsets/sizes\n"); fail = true; }

  bool flush_ok;
  s.flush_and_check(flush_ok);
  if (!flush_ok) { fprintf(stderr, "FAIL directed flush memory mismatch\n"); fail = true; }

  if (!fail) printf("DIRECTED PASS\n");
  return !fail;
}

static void run_random_seed(uint32_t seed, uint64_t n_ops,
                             uint64_t &hits, uint64_t &misses, uint64_t &hum, uint64_t &mum,
                             uint64_t &wbs, bool &ok) {
  srand(seed);
  Sim s(seed * 7919u + 13);
  const uint64_t HOT_SETS = 4;
  const uint64_t HOT_TAGS = 8;

  for (uint64_t i = 0; i < n_ops; i++) {
    bool hot = (rand() % 100) < 70;
    uint64_t idx, tag;
    if (hot) { idx = rand() % HOT_SETS; tag = 100 + (rand() % HOT_TAGS); }
    else { idx = HOT_SETS + (rand() % (64 - HOT_SETS)); tag = 200 + (rand() % 64); }
    int size_log2 = rand() % 4;
    int n = 1 << size_log2;
    int off = rand() % (65 - n);
    off -= off % n; // keep it naturally aligned
    uint64_t addr = mk_addr(tag, idx, off);
    bool we = (rand() % 2) == 0;
    uint64_t wdata = ((uint64_t)rand() << 32) ^ (uint64_t)rand();

    int t = s.find_free_tag();
    while (t < 0) { s.cycle(false, 0, 0, 0, 0, 0); t = s.find_free_tag(); }
    while (!s.cycle(true, addr, we, size_log2, wdata, t)) {}
  }
  s.drain();

  bool flush_ok;
  s.flush_and_check(flush_ok);
  if (!flush_ok) s.golden.diff_report(s.backing, 5);
  ok = !s.mismatch && flush_ok;

  hits = s.dut->cnt_hits;
  misses = s.dut->cnt_misses;
  hum = s.dut->cnt_hit_under_miss;
  mum = s.dut->cnt_miss_under_miss;
  wbs = s.dut->cnt_writebacks;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  bool dpass = directed_tests();

  uint64_t tot_hits = 0, tot_misses = 0, tot_hum = 0, tot_mum = 0, tot_wb = 0;
  bool all_ok = true;
  const uint64_t N_OPS = 100000;
  for (uint32_t seed = 1; seed <= 10; seed++) {
    uint64_t h, m, hum, mum, wb;
    bool ok;
    run_random_seed(seed, N_OPS, h, m, hum, mum, wb, ok);
    tot_hits += h; tot_misses += m; tot_hum += hum; tot_mum += mum; tot_wb += wb;
    if (!ok) { fprintf(stderr, "FAIL seed=%u\n", seed); all_ok = false; }
  }

  if (all_ok)
    printf("RANDOM PASS seeds=10 ops=%llu hits=%llu misses=%llu hit_under_miss=%llu miss_under_miss=%llu writebacks=%llu\n",
           (unsigned long long)N_OPS, (unsigned long long)tot_hits, (unsigned long long)tot_misses,
           (unsigned long long)tot_hum, (unsigned long long)tot_mum, (unsigned long long)tot_wb);
  else
    printf("RANDOM FAIL\n");

  bool pass = dpass && all_ok && tot_hum > 0 && tot_mum > 0;
  printf("%s\n", pass ? "OVERALL PASS" : "OVERALL FAIL");
  return pass ? 0 : 1;
}
