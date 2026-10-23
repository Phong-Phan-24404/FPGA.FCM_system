// File: tb_fcm_accum_update.sv
// Description: Tests accumulator contributions with fixed and random values.

// Test the accumulator lane with directed and seeded arithmetic inputs.
`timescale 1ns/1ps
// Module: tb_fcm_accum_update
// Description: Tests accumulator contributions with fixed and random values.
module tb_fcm_accum_update;
  import fcm_pkg::*;
  logic clk = 1'b0;
  always #2.5 clk = ~clk;
  logic rst_n, clear, start;
  logic [COUNT_W-1:0] bin_count;
  logic [GRAY_W-1:0] gray;
  member_t membership_q;
  logic [ACC_DEN_W-1:0] accum_den;
  logic [ACC_NUM_W-1:0] accum_num;
  logic busy, done, overflow;
  longint unsigned expected_den, expected_num;
  int unsigned seed;

  fcm_accum_update dut (.*);

  // Task: step
  // Description: Sends one accumulator test input.
  task automatic step(input int unsigned h, input int unsigned g, input int unsigned u);
    longint unsigned weighted;
    int timeout;
    @(negedge clk);
    bin_count = COUNT_W'(h);
    gray = GRAY_W'(g);
    membership_q = MEMBER_W'(u);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    weighted = (64'(h) * 64'(u) * 64'(u)) >> MEMBER_FRAC;
    expected_den += weighted;
    expected_num += weighted * g;
    timeout = 0;
    while (done !== 1'b1 && timeout < 12) begin
      @(negedge clk);
      timeout++;
    end
    if (!done || accum_den !== ACC_DEN_W'(expected_den) ||
        accum_num !== ACC_NUM_W'(expected_num) || overflow)
      $fatal(1,"ACCUM FAIL h=%0d g=%0d u=%0d observed=(%0d,%0d) exp=(%0d,%0d)",
             h,g,u,accum_den,accum_num,expected_den,expected_num);
    @(negedge clk);
    if (done !== 1'b0) $fatal(1,"done not a pulse");
  endtask

  initial begin
    rst_n=0;clear=0;start=0;bin_count=0;gray=0;membership_q=0;
    expected_den=0;expected_num=0;seed=32'h1fcb2026;
    repeat (4) @(negedge clk);
    rst_n=1;
    step(202500, 255, 65536);
    @(negedge clk);clear=1;
    @(negedge clk);clear=0;
    expected_den=0;expected_num=0;
    step(202500, 255, 255); // check for early truncation
    @(negedge clk);clear=1;
    @(negedge clk);clear=0;
    expected_den=0;expected_num=0;
    step(10,0,65536);
    step(1,100,1);
    step(3,200,60000);
    for (int i=0;i<120;i++) begin
      // Keep valid frame total bound: each h <= 1000; observed running
      // Accumulators remain within valid output widths.
      seed = (seed * 32'd1664525) + 32'd1013904223;
      step((seed >> 11)%1000, (seed >> 3)%256, (seed >> 16)%65537);
    end
    $display("PASS tb_fcm_accum_update: 125 deterministic/seeded operations");
    $finish;
  end
endmodule
