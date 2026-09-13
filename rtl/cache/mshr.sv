// mshr: N_MSHR miss-status holding registers for l1d. Each entry tracks one
// outstanding line miss: the original CPU request plus (if the victim way
// was dirty) the writeback that must precede the fill. The memory-side port
// is single-outstanding (one request in flight at a time, response order ==
// request order) so no tagging is needed to match mem_resp back to an entry.
// No secondary-miss merging: a request whose line matches an entry already
// in flight is rejected by chk_pending and must be retried by the caller.
module mshr #(
    parameter int N_MSHR = 4,
    parameter int AW     = 64,
    parameter int WAYW   = 1
) (
    input  logic clk,
    input  logic rst_n,

    // allocate a new miss
    input  logic            alloc_valid,
    output logic            alloc_ready,
    input  logic [AW-1:0]   alloc_addr,        // full CPU address (with offset)
    input  logic [3:0]      alloc_reqtag,
    input  logic            alloc_we,
    input  logic [1:0]      alloc_size,
    input  logic [63:0]     alloc_wdata,
    input  logic [WAYW-1:0] alloc_way,
    input  logic            alloc_victim_dirty,
    input  logic [AW-1:0]   alloc_victim_addr, // line-aligned
    input  logic [511:0]    alloc_victim_data,

    // is any in-flight entry (its new line or its evicted victim line)
    // aliased to this line address? used to stall secondary misses.
    input  logic [AW-1:0] chk_addr,
    output logic           chk_pending,

    // is way0/way1 of chk_addr's set already reserved by an in-flight entry?
    // (the array slot is invalidated at alloc time, so a second miss to a
    // different line in the same set must not "see" that way as free)
    output logic way0_busy,
    output logic way1_busy,

    output logic [$clog2(N_MSHR+1)-1:0] busy_cnt,

    // memory-side port (single outstanding transaction, in-order)
    output logic          mem_req_valid,
    input  logic          mem_req_ready,
    output logic [AW-1:0] mem_req_addr,
    output logic          mem_req_we,
    output logic [511:0]  mem_req_wdata,
    input  logic          mem_resp_valid,
    input  logic [511:0]  mem_resp_rdata,
    output logic          wb_fire, // pulses when a writeback req is accepted

    // fill/writeback complete: commit the line + response into the cache
    output logic            commit_valid,
    input  logic            commit_ready,
    output logic [AW-1:0]   commit_addr,
    output logic [3:0]      commit_reqtag,
    output logic            commit_we,
    output logic [1:0]      commit_size,
    output logic [63:0]     commit_wdata,
    output logic [WAYW-1:0] commit_way,
    output logic [511:0]    commit_data
);

  localparam int IW = $clog2(N_MSHR);
  localparam logic [2:0] ST_IDLE = 3'd0, ST_WB = 3'd1, ST_FILL_REQ = 3'd2,
                          ST_FILL_WAIT = 3'd3, ST_DONE = 3'd4;

  logic [2:0]      st        [N_MSHR];
  logic [AW-1:0]   addr_r    [N_MSHR];
  logic [3:0]      tag_r     [N_MSHR];
  logic            we_r      [N_MSHR];
  logic [1:0]      size_r    [N_MSHR];
  logic [63:0]     wdata_r   [N_MSHR];
  logic [WAYW-1:0] way_r     [N_MSHR];
  logic            vdirty_r  [N_MSHR];
  logic [AW-1:0]   vaddr_r   [N_MSHR];
  logic [511:0]    vdata_r   [N_MSHR];
  logic [511:0]    filldata_r[N_MSHR];

  // free-slot / pending-commit / send-arbiter priority encoders (fixed lowest-index priority)
  logic [IW-1:0] free_idx, done_idx, send_idx;
  logic          free_any, done_any, send_any;

  always_comb begin
    free_any = 1'b0; free_idx = '0;
    done_any = 1'b0; done_idx = '0;
    send_any = 1'b0; send_idx = '0;
    for (int i = N_MSHR - 1; i >= 0; i--) begin
      if (st[i] == ST_IDLE) begin free_any = 1'b1; free_idx = i[IW-1:0]; end
      if (st[i] == ST_DONE) begin done_any = 1'b1; done_idx = i[IW-1:0]; end
      if (st[i] == ST_WB || st[i] == ST_FILL_REQ) begin send_any = 1'b1; send_idx = i[IW-1:0]; end
    end
  end

  assign alloc_ready = free_any;

  always_comb begin
    chk_pending = 1'b0;
    for (int i = 0; i < N_MSHR; i++) begin
      if (st[i] != ST_IDLE) begin
        if (addr_r[i][AW-1:6] == chk_addr[AW-1:6]) chk_pending = 1'b1;
        if (vdirty_r[i] && vaddr_r[i][AW-1:6] == chk_addr[AW-1:6]) chk_pending = 1'b1;
      end
    end
  end

  always_comb begin
    way0_busy = 1'b0;
    way1_busy = 1'b0;
    for (int i = 0; i < N_MSHR; i++) begin
      if (st[i] != ST_IDLE && addr_r[i][11:6] == chk_addr[11:6]) begin
        if (way_r[i] == '0) way0_busy = 1'b1;
        else way1_busy = 1'b1;
      end
    end
  end

  always_comb begin
    busy_cnt = '0;
    for (int i = 0; i < N_MSHR; i++) if (st[i] != ST_IDLE) busy_cnt = busy_cnt + 1'b1;
  end

  logic          mem_busy;
  logic [IW-1:0] busy_idx;

  assign mem_req_valid = send_any && !mem_busy;
  assign mem_req_we    = (st[send_idx] == ST_WB);
  assign mem_req_addr  = mem_req_we ? vaddr_r[send_idx] : {addr_r[send_idx][AW-1:6], 6'b0};
  assign mem_req_wdata = vdata_r[send_idx];
  assign wb_fire        = mem_req_valid && mem_req_ready && mem_req_we;

  assign commit_valid  = done_any;
  assign commit_addr   = addr_r[done_idx];
  assign commit_reqtag = tag_r[done_idx];
  assign commit_we     = we_r[done_idx];
  assign commit_size   = size_r[done_idx];
  assign commit_wdata  = wdata_r[done_idx];
  assign commit_way    = way_r[done_idx];
  assign commit_data   = filldata_r[done_idx];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < N_MSHR; i++) st[i] <= ST_IDLE;
      mem_busy <= 1'b0;
    end else begin
      if (alloc_valid && alloc_ready) begin
        addr_r[free_idx]   <= alloc_addr;
        tag_r[free_idx]    <= alloc_reqtag;
        we_r[free_idx]     <= alloc_we;
        size_r[free_idx]   <= alloc_size;
        wdata_r[free_idx]  <= alloc_wdata;
        way_r[free_idx]    <= alloc_way;
        vdirty_r[free_idx] <= alloc_victim_dirty;
        vaddr_r[free_idx]  <= alloc_victim_addr;
        vdata_r[free_idx]  <= alloc_victim_data;
        st[free_idx]       <= alloc_victim_dirty ? ST_WB : ST_FILL_REQ;
      end

      if (mem_req_valid && mem_req_ready) begin
        if (st[send_idx] == ST_WB) begin
          st[send_idx] <= ST_FILL_REQ;
        end else begin
          st[send_idx] <= ST_FILL_WAIT;
          mem_busy     <= 1'b1;
          busy_idx     <= send_idx;
        end
      end

      if (mem_resp_valid) begin
        filldata_r[busy_idx] <= mem_resp_rdata;
        st[busy_idx]         <= ST_DONE;
        mem_busy             <= 1'b0;
      end

      if (commit_valid && commit_ready) st[done_idx] <= ST_IDLE;
    end
  end

endmodule
