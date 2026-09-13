// free_list: circular FIFO of free physical register tags.
// NUM_PREGS-ARCH_REGS entries (p32..p63 free at reset, p0..p31 permanently mapped 1:1).
// 2 alloc (dequeue) ports, 2 free (enqueue) ports at commit, per-branch checkpoint
// of the head pointer + count so a mispredict can roll back all allocations since.
module free_list #(
    parameter int NUM_PREGS = 64,
    parameter int ARCH_REGS = 32,
    parameter int N_CKPT    = 8
) (
    input  logic clk,
    input  logic rst,

    input  logic       alloc_en0,
    input  logic       alloc_en1,
    output logic [6:0] alloc_preg0,
    output logic [6:0] alloc_preg1,

    input  logic       free_en0,
    input  logic [6:0] free_preg0,
    input  logic       free_en1,
    input  logic [6:0] free_preg1,

    output logic [$clog2(NUM_PREGS - ARCH_REGS + 1) - 1:0] free_count,

    // slot0/slot1 checkpoint snapshots (slot1 sees slot0's own alloc already applied)
    input  logic                        ckpt_save0,
    input  logic [$clog2(N_CKPT) - 1:0] ckpt_save_id0,
    input  logic                        ckpt_save1,
    input  logic [$clog2(N_CKPT) - 1:0] ckpt_save_id1,

    input  logic                        restore_valid,
    input  logic [$clog2(N_CKPT) - 1:0] restore_id
);

  localparam int DEPTH  = NUM_PREGS - ARCH_REGS; // must be a power of two
  localparam int PTR_W  = $clog2(DEPTH);
  localparam int CNT_W  = $clog2(DEPTH + 1);

  logic [6:0]        fl[DEPTH];
  logic [PTR_W-1:0]  head, tail;
  logic [CNT_W-1:0]  count;

  // only the head pointer is snapshotted per checkpoint; count on restore is
  // recovered as (current count) + (allocations undone), since tail keeps
  // advancing with real commits regardless of any speculation being flushed.
  logic [PTR_W-1:0] ckpt_head[N_CKPT];

  wire do_a0 = alloc_en0 && !restore_valid && (count >= CNT_W'(1));
  wire do_a1 = alloc_en1 && !restore_valid && (count >= (do_a0 ? CNT_W'(2) : CNT_W'(1)));
  wire do_f0 = free_en0;
  wire do_f1 = free_en1;

  wire [PTR_W-1:0] idx0 = head;
  wire [PTR_W-1:0] idx1 = head + (do_a0 ? PTR_W'(1) : PTR_W'(0));
  assign alloc_preg0 = fl[idx0];
  assign alloc_preg1 = fl[idx1];

  wire [PTR_W-1:0] fidx0 = tail;
  wire [PTR_W-1:0] fidx1 = tail + (do_f0 ? PTR_W'(1) : PTR_W'(0));

  // state after slot0's own alloc only, and after both slots (used for checkpoint snapshots)
  wire [PTR_W-1:0] head_after0 = head + (do_a0 ? PTR_W'(1) : PTR_W'(0));
  wire [CNT_W-1:0] count_after_frees = count + (do_f0 ? CNT_W'(1) : CNT_W'(0)) + (do_f1 ? CNT_W'(1) : CNT_W'(0));
  wire [CNT_W-1:0] count_after0 = count_after_frees - (do_a0 ? CNT_W'(1) : CNT_W'(0));
  wire [PTR_W-1:0] head_after1 = head_after0 + (do_a1 ? PTR_W'(1) : PTR_W'(0));
  wire [CNT_W-1:0] count_after1 = count_after0 - (do_a1 ? CNT_W'(1) : CNT_W'(0));

  // number of allocations issued since restore_id's checkpoint, now being undone
  wire [PTR_W-1:0] undone_allocs = head - ckpt_head[restore_id];

  assign free_count = count;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < DEPTH; i++) fl[i] <= 7'(ARCH_REGS + i);
      head  <= '0;
      tail  <= '0;
      count <= CNT_W'(DEPTH);
    end else begin
      if (do_f0) fl[fidx0] <= free_preg0;
      if (do_f1) fl[fidx1] <= free_preg1;

      tail <= tail + (do_f0 ? PTR_W'(1) : PTR_W'(0)) + (do_f1 ? PTR_W'(1) : PTR_W'(0));

      if (restore_valid) begin
        head  <= ckpt_head[restore_id];
        count <= count_after_frees + CNT_W'(undone_allocs);
      end else begin
        head  <= head_after1;
        count <= count_after1;
      end

      if (ckpt_save0) ckpt_head[ckpt_save_id0] <= head_after0;
      if (ckpt_save1) ckpt_head[ckpt_save_id1] <= head_after1;
    end
  end

endmodule
