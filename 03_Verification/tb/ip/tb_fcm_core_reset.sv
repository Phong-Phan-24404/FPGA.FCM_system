// File: tb_fcm_core_reset.sv
// Description: Tests reset during processing and back-to-back runs.

// Test reset and back-to-back core runs. Reset should clear the active operation, and the next full
// run should match the saved reference values.
`timescale 1ns/1ps

// Module: tb_fcm_core_reset
// Description: Tests reset during processing and back-to-back runs.
module tb_fcm_core_reset;

  import fcm_pkg::*;
  import fcm_vector_pkg::*;

  localparam int CLK_HALF = 5;
  localparam int MAX_C    = MAX_CLUSTERS;

  logic clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  logic                rst_n;
  logic                start;
  logic [NUMC_W-1:0]   num_clusters;
  logic [GRAY_W-1:0]   hist_wr_addr;
  logic [COUNT_W-1:0]  hist_wr_data;
  logic                hist_wr_en;
  center_t             init_centers_q [0:MAX_C-1];
  logic [GRAY_W-1:0]   labels_lut_addr;
  logic [LABEL_W-1:0]  labels_lut_data;
  center_t             centers_q [0:MAX_C-1];
  logic                converged;
  logic [ITER_W-1:0]   iter_converged;
  logic                busy;
  logic                done;
  logic                contract_error;

  fcm_core #(.MAX_C(MAX_C)) dut (.*);

  // Load the reference values for the selected test case.
  string vector_dir = FCM_DEFAULT_VECTOR_DIR;
  int    case_k     = 7;

  int unsigned hist_mem [GRAY_BINS];
  center_t     init_mem [0:MAX_C-1];
  center_t     gold_centers [0:MAX_C-1];
  logic [LABEL_W-1:0] gold_lut [GRAY_BINS];
  int unsigned gold_iterations;
  bit          gold_converged;

  int errors = 0;
  int checks = 0;

  // Function: fail
  // Description: Records a test failure with a message.
  function automatic void fail(string msg);
    errors++;
    $display("[FAIL] %s", msg);
  endfunction

  // Function: load_case
  // Description: Loads the vector files for a selected test case.
  function automatic bit load_case(string dir, int k);
    longint unsigned q [$];
    int n;

    n = fcm_read_mem({dir, "/hist_counts_u18.mem"}, q);
    if (n != GRAY_BINS) begin
      $display("[FAIL] hist_counts_u18.mem: %0d word, can %0d", n, GRAY_BINS);
      return 1'b0;
    end
    for (int g = 0; g < GRAY_BINS; g++) hist_mem[g] = int'(q[g]);

    n = fcm_read_mem({dir, "/initial_centers.mem"}, q);
    if (n != k) begin
      $display("[FAIL] initial_centers.mem: %0d word, can %0d", n, k);
      return 1'b0;
    end
    for (int i = 0; i < MAX_C; i++)
      init_mem[i] = (i < k) ? center_t'(q[i]) : '0;

    n = fcm_read_mem({dir, "/golden_centers.mem"}, q);
    if (n != k) return 1'b0;
    for (int i = 0; i < MAX_C; i++)
      gold_centers[i] = (i < k) ? center_t'(q[i]) : '0;

    n = fcm_read_mem({dir, "/golden_lut_u3.mem"}, q);
    if (n != GRAY_BINS) return 1'b0;
    for (int g = 0; g < GRAY_BINS; g++) gold_lut[g] = q[g][LABEL_W-1:0];

    n = fcm_read_mem({dir, "/golden_iteration_count_u8.mem"}, q);
    if (n != 1) return 1'b0;
    gold_iterations = int'(q[0]);

    n = fcm_read_mem({dir, "/golden_converged_u1.mem"}, q);
    if (n != 1) return 1'b0;
    gold_converged = q[0][0];

    return 1'b1;
  endfunction

  // Task: apply_reset
  // Description: Holds reset for the requested number of cycles.
  task automatic apply_reset(int cycles);
    @(negedge clk);
    rst_n = 1'b0;
    repeat (cycles) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask

  // Write all histogram bins so each run starts with the expected RAM contents.
  // Task: load_histogram
  // Description: Writes all histogram bins into the DUT.
  task automatic load_histogram();
    for (int g = 0; g < GRAY_BINS; g++) begin
      @(negedge clk);
      hist_wr_addr <= g[GRAY_W-1:0];
      hist_wr_data <= hist_mem[g][COUNT_W-1:0];
      hist_wr_en   <= 1'b1;
    end
    @(negedge clk);
    hist_wr_en <= 1'b0;
  endtask

  // Task: pulse_start
  // Description: Sends a start pulse to the DUT.
  task automatic pulse_start();
    @(negedge clk);
    num_clusters <= NUMC_W'(case_k);
    for (int i = 0; i < MAX_C; i++) init_centers_q[i] <= init_mem[i];
    @(negedge clk);
    start <= 1'b1;
    @(negedge clk);
    start <= 1'b0;
  endtask

  // Task: read_lut
  // Description: Reads the label LUT values after processing.
  task automatic read_lut(output logic [LABEL_W-1:0] got [GRAY_BINS]);
    // The label LUT uses synchronous RAM with one cycle of read latency.
    // Apply an address at negedge, then sample its data at the next negedge.
    // Sample before changing the address to avoid an off-by-one error.
    @(negedge clk);
    labels_lut_addr <= '0;
    @(negedge clk);
    for (int g = 0; g < GRAY_BINS; g++) begin
      got[g] = labels_lut_data;
      labels_lut_addr <= GRAY_W'((g + 1) % GRAY_BINS);
      @(negedge clk);
    end
  endtask

  // Run the loaded case to completion and compare everything against golden.
  // Task: run_and_check
  // Description: Runs the DUT and checks its results against the reference.
  task automatic run_and_check(string tag);
    logic [LABEL_W-1:0] got_lut [GRAY_BINS];
    int lut_errors = 0;
    int guard = 0;

    load_histogram();
    pulse_start();

    while (done !== 1'b1) begin
      @(posedge clk);
      guard++;
      if (guard > 40_000_000) begin
        fail($sformatf("%s: khong thay done (timeout)", tag));
        return;
      end
    end

    checks++;
    if (iter_converged !== ITER_W'(gold_iterations))
      fail($sformatf("%s: iterations DUT=%0d reference=%0d",
                     tag, iter_converged, gold_iterations));
    if (converged !== gold_converged)
      fail($sformatf("%s: converged DUT=%0b reference=%0b",
                     tag, converged, gold_converged));
    if (contract_error !== 1'b0)
      fail($sformatf("%s: contract_error bat", tag));
    for (int i = 0; i < case_k; i++)
      if (centers_q[i] !== gold_centers[i])
        fail($sformatf("%s: center[%0d] DUT=%0d reference=%0d",
                       tag, i, centers_q[i], gold_centers[i]));

    read_lut(got_lut);
    for (int g = 0; g < GRAY_BINS; g++)
      if (got_lut[g] !== gold_lut[g]) lut_errors++;
    if (lut_errors > 0)
      fail($sformatf("%s: %0d/%0d muc LUT sai", tag, lut_errors, GRAY_BINS));
  endtask

  // Start a run, abort it with reset after `abort_cycles`, then prove the DUT
  // Came back clean by running the same case to a bit-exact finish.
  // Task: abort_then_rerun
  // Description: Resets an active run and checks the following full run.
  task automatic abort_then_rerun(int abort_cycles);
    int observed_done = 0;

    load_histogram();
    pulse_start();

    repeat (abort_cycles) begin
      @(posedge clk);
      if (done === 1'b1) observed_done++;
    end

    if (observed_done != 0)
      fail($sformatf("abort@%0d: case ket thuc truoc khi reset, diem abort vo nghia",
                     abort_cycles));
    if (busy !== 1'b1)
      fail($sformatf("abort@%0d: DUT khong con busy truoc reset", abort_cycles));

    apply_reset(3);

    if (busy !== 1'b0)
      fail($sformatf("abort@%0d: busy van bat sau reset", abort_cycles));
    if (done !== 1'b0)
      fail($sformatf("abort@%0d: done van bat sau reset", abort_cycles));
    if (contract_error !== 1'b0)
      fail($sformatf("abort@%0d: contract_error van bat sau reset", abort_cycles));

    run_and_check($sformatf("rerun sau abort@%0d", abort_cycles));
  endtask

  // Task: scenario
  // Description: Runs the reset and back-to-back test cases.
  task automatic scenario(int k, bit with_aborts);
    string dir;
    dir = fcm_case_dir(vector_dir, k);
    case_k = k;
    if (!load_case(dir, k)) begin
      $display("[FATAL] khong doc duoc case: %s", dir);
      $fatal(1, "tb_fcm_core_reset: thieu vector");
    end
    $display("tb_fcm_core_reset: case %s K=%0d aborts=%0b", dir, k, with_aborts);

    // Start with a normal run to check the reference results.
    run_and_check($sformatf("K=%0d baseline", k));

    // Run again without an idle gap to catch state left from the last frame.
    run_and_check($sformatf("K=%0d back-to-back #2", k));

    if (!with_aborts) return;

    run_and_check($sformatf("K=%0d back-to-back #3", k));

    // Apply reset at different points in the bin scan and iteration loop.
    abort_then_rerun(50);
    abort_then_rerun(500);
    abort_then_rerun(5_000);
    abort_then_rerun(100_000);

    // Finish with another normal run to check that reset left the DUT usable.
    run_and_check($sformatf("K=%0d final clean run", k));
  endtask

  initial begin
    int k;

    vector_dir = fcm_vector_dir();

    rst_n           = 1'b0;
    start           = 1'b0;
    num_clusters    = '0;
    hist_wr_en      = 1'b0;
    hist_wr_addr    = '0;
    hist_wr_data    = '0;
    labels_lut_addr = '0;
    for (int i = 0; i < MAX_C; i++) init_centers_q[i] = '0;

    apply_reset(5);

    // Use K=2 for the long abort scenario to reduce simulation cycles.
    // Also check K=7 with normal and back-to-back runs.
    // +FCM_CASE_K selects a cluster count for the full abort scenario.
    if ($value$plusargs("FCM_CASE_K=%d", k)) begin
      scenario(k, 1'b1);
    end else begin
      scenario(2, 1'b1);
      scenario(7, 1'b0);
    end

    if (errors == 0)
      $display("PASS tb_fcm_core_reset: %0d full-case checks, 4 abort points", checks);
    else
      $fatal(1, "FAIL tb_fcm_core_reset: %0d loi", errors);
    $finish;
  end

  initial begin
    #2000ms;
    $fatal(1, "tb_fcm_core_reset qua thoi gian");
  end

endmodule
