// l1d: standalone non-blocking L1 data cache. 8KB, 2-way set-associative,
// 64B lines, write-back + write-allocate, 1-bit pseudo-LRU per set,
// N_MSHR outstanding misses. Hit latency is 1 cycle; responses (hits and
// fills) are queued into resp_fifo and popped one per cycle, so they can
// come back out of program order relative to request acceptance.
//
// No secondary-miss merging: a request whose line already has an MSHR
// entry in flight (its target line, or the line being evicted to make
// room for it) deasserts req_ready until that entry retires.
//
// Memory-side contract (for a future AXI4 adapter to bridge):
//   - mem_req_valid/ready is a single-outstanding request/accept handshake:
//     the cache issues at most one request at a time and waits for the
//     matching mem_resp before issuing the next (writes get no response,
//     but the port still holds off further requests until any outstanding
//     read's response arrives, keeping the two channels trivially in order).
//   - mem_req_addr is line-aligned (bits [5:0] == 0). mem_req_we=1 is a
//     512-bit line writeback with data on mem_req_wdata; mem_req_we=0 is a
//     512-bit line fill request.
//   - mem_resp_valid/mem_resp_rdata deliver exactly one 512-bit line for
//     each fill request (we=0), in request order; writes produce no resp.
module l1d #(
    parameter int N_MSHR = 4
) (
    input  logic clk,
    input  logic rst_n,

    // CPU-side port
    input  logic        req_valid,
    output logic        req_ready,
    input  logic [63:0] req_addr,
    input  logic        req_we,
    input  logic [1:0]  req_size, // 0=B,1=H,2=W,3=D
    input  logic [63:0] req_wdata,
    input  logic [3:0]  req_tag,

    output logic        resp_valid,
    output logic [3:0]  resp_tag,
    output logic [63:0] resp_rdata,

    // memory-side port, see header comment
    output logic         mem_req_valid,
    input  logic          mem_req_ready,
    output logic [63:0]   mem_req_addr,
    output logic          mem_req_we,
    output logic [511:0]  mem_req_wdata,
    input  logic          mem_resp_valid,
    input  logic [511:0]  mem_resp_rdata,

    // forced writeback-all (test/debug hook): hold flush_all high while idle;
    // flush_done pulses for one cycle once every dirty line has been written back.
    input  logic flush_all,
    output logic flush_done,

    output logic [31:0] cnt_hits,
    output logic [31:0] cnt_misses,
    output logic [31:0] cnt_hit_under_miss,
    output logic [31:0] cnt_miss_under_miss,
    output logic [31:0] cnt_writebacks
);

  localparam int SETS = 64;
  localparam int WAYS = 2;
  localparam int IDXW = 6;
  localparam int OFFW = 6;
  localparam int TAGW = 64 - IDXW - OFFW;
  localparam int FIFO_DEPTH = 32;

  logic [TAGW-1:0] tag_arr  [SETS][WAYS];
  logic            valid_arr[SETS][WAYS];
  logic            dirty_arr[SETS][WAYS];
  logic [511:0]    data_arr [SETS][WAYS];
  logic            plru     [SETS]; // MRU way of the set

  wire [IDXW-1:0] r_idx = req_addr[11:6];
  wire [OFFW-1:0] r_off = req_addr[5:0];
  wire [TAGW-1:0] r_tag = req_addr[63:12];

  wire hit0 = valid_arr[r_idx][0] && tag_arr[r_idx][0] == r_tag;
  wire hit1 = valid_arr[r_idx][1] && tag_arr[r_idx][1] == r_tag;
  wire hit     = hit0 || hit1;
  wire hit_way = hit1;

  wire empty0 = !valid_arr[r_idx][0];
  wire empty1 = !valid_arr[r_idx][1];

  // a way already reserved by an in-flight MSHR entry for this set must not be
  // picked again by a second miss to a different line in the same set.
  logic way0_busy, way1_busy;
  wire way0_ok = !way0_busy;
  wire way1_ok = !way1_busy;
  logic no_way_avail, alloc_way;
  always_comb begin
    no_way_avail = 1'b0;
    alloc_way = 1'b0;
    if (!way0_ok && !way1_ok) no_way_avail = 1'b1;
    else if (way0_ok && empty0) alloc_way = 1'b0;
    else if (way1_ok && empty1) alloc_way = 1'b1;
    else if (way0_ok && way1_ok) alloc_way = ~plru[r_idx];
    else if (way0_ok) alloc_way = 1'b0;
    else alloc_way = 1'b1;
  end

  wire chosen_empty = alloc_way ? empty1 : empty0;
  wire victim_dirty = !chosen_empty && dirty_arr[r_idx][alloc_way];
  wire [63:0] victim_addr = {tag_arr[r_idx][alloc_way], r_idx, 6'b0};
  wire [511:0] victim_data = data_arr[r_idx][alloc_way];

  // byte-lane helpers: variable base, constant width part-selects
  function automatic [63:0] extract(logic [511:0] line, logic [5:0] off, logic [1:0] size);
    case (size)
      2'd0: extract = {56'b0, line[off*8 +: 8]};
      2'd1: extract = {48'b0, line[off*8 +: 16]};
      2'd2: extract = {32'b0, line[off*8 +: 32]};
      default: extract = line[off*8 +: 64];
    endcase
  endfunction

  function automatic [511:0] merge(logic [511:0] line, logic [5:0] off, logic [1:0] size, logic [63:0] wdata);
    merge = line;
    case (size)
      2'd0: merge[off*8 +: 8]  = wdata[7:0];
      2'd1: merge[off*8 +: 16] = wdata[15:0];
      2'd2: merge[off*8 +: 32] = wdata[31:0];
      default: merge[off*8 +: 64] = wdata;
    endcase
  endfunction

  // ---- MSHR ----
  logic alloc_valid, alloc_ready;
  logic chk_pending;
  logic [$clog2(N_MSHR+1)-1:0] busy_cnt;
  logic mshr_mem_req_valid, mshr_mem_req_we, mshr_wb_fire;
  logic [63:0] mshr_mem_req_addr;
  logic [511:0] mshr_mem_req_wdata;
  logic commit_valid, commit_ready;
  logic [63:0] commit_addr;
  logic [3:0] commit_reqtag;
  logic commit_we;
  logic [1:0] commit_size;
  logic [63:0] commit_wdata;
  logic commit_way;
  logic [511:0] commit_data;

  mshr #(.N_MSHR(N_MSHR), .AW(64), .WAYW(1)) u_mshr (
      .clk(clk), .rst_n(rst_n),
      .alloc_valid(alloc_valid), .alloc_ready(alloc_ready),
      .alloc_addr(req_addr), .alloc_reqtag(req_tag), .alloc_we(req_we),
      .alloc_size(req_size), .alloc_wdata(req_wdata), .alloc_way(alloc_way),
      .alloc_victim_dirty(victim_dirty), .alloc_victim_addr(victim_addr), .alloc_victim_data(victim_data),
      .chk_addr(req_addr), .chk_pending(chk_pending),
      .way0_busy(way0_busy), .way1_busy(way1_busy),
      .busy_cnt(busy_cnt),
      .mem_req_valid(mshr_mem_req_valid), .mem_req_ready(mem_req_ready && !flush_active),
      .mem_req_addr(mshr_mem_req_addr), .mem_req_we(mshr_mem_req_we), .mem_req_wdata(mshr_mem_req_wdata),
      .mem_resp_valid(mem_resp_valid && !flush_active), .mem_resp_rdata(mem_resp_rdata),
      .wb_fire(mshr_wb_fire),
      .commit_valid(commit_valid), .commit_ready(commit_ready),
      .commit_addr(commit_addr), .commit_reqtag(commit_reqtag), .commit_we(commit_we),
      .commit_size(commit_size), .commit_wdata(commit_wdata), .commit_way(commit_way), .commit_data(commit_data)
  );

  // ---- response FIFO ----
  logic [3:0]  fifo_tag [FIFO_DEPTH];
  logic [63:0] fifo_data[FIFO_DEPTH];
  logic [$clog2(FIFO_DEPTH)-1:0] fifo_head, fifo_tail;
  logic [$clog2(FIFO_DEPTH):0]   fifo_cnt;

  wire fifo_room2 = fifo_cnt <= (FIFO_DEPTH - 2); // room for a hit-push and a commit-push this cycle

  wire hit_accept  = req_valid && hit && req_ready;
  wire miss_accept = req_valid && !hit && req_ready;

  assign req_ready = req_valid && hit  ? fifo_room2 :
                      req_valid && !hit ? (alloc_ready && !chk_pending && !no_way_avail && fifo_room2) :
                      1'b1;

  assign alloc_valid  = miss_accept;
  assign commit_ready = fifo_room2 && !flush_active;

  wire [63:0] hit_rdata = req_we ? req_wdata : extract(data_arr[r_idx][hit_way], r_off, req_size);
  wire [63:0] commit_rdata = commit_we ? commit_wdata : extract(commit_data, commit_addr[5:0], commit_size);
  wire [IDXW-1:0] c_idx = commit_addr[11:6];

  logic [3:0]  resp_tag_r;
  logic [63:0] resp_data_r;
  assign resp_tag   = resp_tag_r;
  assign resp_rdata = resp_data_r;

  wire commit_fire = commit_valid && commit_ready;
  wire [1:0] num_push = hit_accept + commit_fire; // 0, 1 or 2
  wire       do_pop   = fifo_cnt > 0;

  integer fp_i, fp_j;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fifo_head <= '0; fifo_tail <= '0; fifo_cnt <= '0;
      resp_valid <= 1'b0;
    end else begin
      if (hit_accept) begin
        fifo_tag[fifo_tail]  <= req_tag;
        fifo_data[fifo_tail] <= hit_rdata;
      end
      if (commit_fire) begin
        fifo_tag[hit_accept ? fifo_tail + 1'b1 : fifo_tail]  <= commit_reqtag;
        fifo_data[hit_accept ? fifo_tail + 1'b1 : fifo_tail] <= commit_rdata;
      end
      fifo_tail <= fifo_tail + num_push;
      fifo_cnt  <= fifo_cnt + num_push - do_pop;

      if (do_pop) begin
        resp_valid  <= 1'b1;
        resp_tag_r  <= fifo_tag[fifo_head];
        resp_data_r <= fifo_data[fifo_head];
        fifo_head   <= fifo_head + 1'b1;
      end else begin
        resp_valid <= 1'b0;
      end
    end
  end

  // ---- flush-all FSM (drives the mem port directly; only run while the MSHR is idle) ----
  logic flush_active;
  logic [IDXW:0] fl_idx;
  logic          fl_way;
  logic          fl_busy;

  assign flush_active = fl_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fl_busy <= 1'b0; fl_idx <= '0; fl_way <= 1'b0; flush_done <= 1'b0;
    end else begin
      flush_done <= 1'b0;
      if (!fl_busy) begin
        if (flush_all && busy_cnt == 0) begin fl_busy <= 1'b1; fl_idx <= '0; fl_way <= 1'b0; end
      end else begin
        if (fl_idx == SETS[IDXW:0]) begin
          fl_busy <= 1'b0;
          flush_done <= 1'b1;
        end else if (valid_arr[fl_idx[IDXW-1:0]][fl_way] && dirty_arr[fl_idx[IDXW-1:0]][fl_way]) begin
          if (mem_req_ready) begin
            dirty_arr[fl_idx[IDXW-1:0]][fl_way] <= 1'b0;
            cnt_writebacks <= cnt_writebacks + 1'b1;
            if (fl_way == 1'b1) begin fl_way <= 1'b0; fl_idx <= fl_idx + 1'b1; end
            else fl_way <= 1'b1;
          end
        end else begin
          if (fl_way == 1'b1) begin fl_way <= 1'b0; fl_idx <= fl_idx + 1'b1; end
          else fl_way <= 1'b1;
        end
      end
    end
  end

  assign mem_req_valid = flush_active ? (fl_idx != SETS[IDXW:0] && valid_arr[fl_idx[IDXW-1:0]][fl_way] && dirty_arr[fl_idx[IDXW-1:0]][fl_way])
                                       : mshr_mem_req_valid;
  assign mem_req_addr  = flush_active ? {tag_arr[fl_idx[IDXW-1:0]][fl_way], fl_idx[IDXW-1:0], 6'b0} : mshr_mem_req_addr;
  assign mem_req_we    = flush_active ? 1'b1 : mshr_mem_req_we;
  assign mem_req_wdata = flush_active ? data_arr[fl_idx[IDXW-1:0]][fl_way] : mshr_mem_req_wdata;

  // ---- cache array updates + counters ----
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (fp_i = 0; fp_i < SETS; fp_i++) begin
        plru[fp_i] <= 1'b0;
        for (fp_j = 0; fp_j < WAYS; fp_j++) begin
          valid_arr[fp_i][fp_j] <= 1'b0;
          dirty_arr[fp_i][fp_j] <= 1'b0;
        end
      end
      cnt_hits <= '0; cnt_misses <= '0; cnt_hit_under_miss <= '0;
      cnt_miss_under_miss <= '0; cnt_writebacks <= '0;
    end else begin
      if (hit_accept) begin
        plru[r_idx] <= hit_way;
        if (req_we) begin
          data_arr[r_idx][hit_way]  <= merge(data_arr[r_idx][hit_way], r_off, req_size, req_wdata);
          dirty_arr[r_idx][hit_way] <= 1'b1;
        end
        cnt_hits <= cnt_hits + 1'b1;
        if (busy_cnt != 0) cnt_hit_under_miss <= cnt_hit_under_miss + 1'b1;
      end

      if (miss_accept) begin
        valid_arr[r_idx][alloc_way] <= 1'b0; // slot reserved for the pending fill
        cnt_misses <= cnt_misses + 1'b1;
        if (busy_cnt != 0) cnt_miss_under_miss <= cnt_miss_under_miss + 1'b1;
      end

      if (mshr_wb_fire) cnt_writebacks <= cnt_writebacks + 1'b1;

      if (commit_valid && commit_ready) begin
        tag_arr[c_idx][commit_way]   <= commit_addr[63:12];
        valid_arr[c_idx][commit_way] <= 1'b1;
        plru[c_idx] <= commit_way;
        if (commit_we) begin
          data_arr[c_idx][commit_way]  <= merge(commit_data, commit_addr[5:0], commit_size, commit_wdata);
          dirty_arr[c_idx][commit_way] <= 1'b1;
        end else begin
          data_arr[c_idx][commit_way]  <= commit_data;
          dirty_arr[c_idx][commit_way] <= 1'b0;
        end
      end
    end
  end

endmodule
