// File: tb_fcm_core_profile.sv
// Description: Checks a core case and measures cycles in each stage.

// Run one core case, check the result against reference data, and report the cycle breakdown when
// profiling is enabled.

`timescale 1ns/1ps

// Module: tb_fcm_core_profile
// Description: Checks a core case and measures cycles in each stage.
module tb_fcm_core_profile;

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

  // Assertions and the profiler both bind into the same DUT.
  fcm_sva_bind_member u_sva_bind_member ();
  fcm_sva_bind_core   u_sva_bind_core   ();
  fcm_profile_bind    u_profile_bind    ();

  string vector_dir = FCM_DEFAULT_VECTOR_DIR;
  int    case_k     = 7;

  int unsigned        hist_mem [GRAY_BINS];
  center_t            init_mem [0:MAX_C-1];
  center_t            gold_centers [0:MAX_C-1];
  int unsigned        gold_iterations;
  bit                 gold_converged;
  int                 errors = 0;

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
    if (n != k) return 1'b0;
    for (int i = 0; i < MAX_C; i++)
      init_mem[i] = (i < k) ? center_t'(q[i]) : '0;

    n = fcm_read_mem({dir, "/golden_centers.mem"}, q);
    if (n != k) return 1'b0;
    for (int i = 0; i < MAX_C; i++)
      gold_centers[i] = (i < k) ? center_t'(q[i]) : '0;

    n = fcm_read_mem({dir, "/golden_iteration_count_u8.mem"}, q);
    if (n != 1) return 1'b0;
    gold_iterations = int'(q[0]);

    n = fcm_read_mem({dir, "/golden_converged_u1.mem"}, q);
    if (n != 1) return 1'b0;
    gold_converged = q[0][0];
    return 1'b1;
  endfunction

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

  initial begin
    string dir;
    int    k;
    int unsigned cycles;

    vector_dir = fcm_vector_dir();
    if ($value$plusargs("FCM_CASE_K=%d", k)) case_k = k;

    rst_n           = 1'b0;
    start           = 1'b0;
    num_clusters    = '0;
    hist_wr_en      = 1'b0;
    hist_wr_addr    = '0;
    hist_wr_data    = '0;
    labels_lut_addr = '0;
    for (int i = 0; i < MAX_C; i++) init_centers_q[i] = '0;

    dir = fcm_case_dir(vector_dir, case_k);
    if (!load_case(dir, case_k)) begin
      $display("[FATAL] khong doc duoc case: %s", dir);
      $fatal(1, "tb_fcm_core_profile: thieu vector");
    end
    $display("tb_fcm_core_profile: case %s K=%0d", dir, case_k);

    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    load_histogram();

    @(negedge clk);
    num_clusters <= NUMC_W'(case_k);
    for (int i = 0; i < MAX_C; i++) init_centers_q[i] <= init_mem[i];
    @(negedge clk);
    start <= 1'b1;
    @(negedge clk);
    start <= 1'b0;

    cycles = 0;
    while (done !== 1'b1) begin
      @(posedge clk);
      cycles++;
      if (cycles > 40_000_000) $fatal(1, "tb_fcm_core_profile: timeout");
    end

    // Check the output data before using the timing measurements.
    if (iter_converged !== ITER_W'(gold_iterations)) begin
      errors++;
      $display("[FAIL] iterations DUT=%0d reference=%0d",
               iter_converged, gold_iterations);
    end
    if (converged !== gold_converged) begin
      errors++;
      $display("[FAIL] converged DUT=%0b reference=%0b", converged, gold_converged);
    end
    if (contract_error !== 1'b0) begin
      errors++;
      $display("[FAIL] contract_error bat");
    end
    for (int i = 0; i < case_k; i++)
      if (centers_q[i] !== gold_centers[i]) begin
        errors++;
        $display("[FAIL] center[%0d] DUT=%0d reference=%0d",
                 i, centers_q[i], gold_centers[i]);
      end

    $display("tb_fcm_core_profile: start->done = %0d cycles", cycles);
    if (errors == 0)
      $display("PASS tb_fcm_core_profile: K=%0d matches reference", case_k);
    else
      $fatal(1, "FAIL tb_fcm_core_profile: %0d loi", errors);
    $finish;
  end

  initial begin
    #2000ms;
    $fatal(1, "tb_fcm_core_profile qua thoi gian");
  end

endmodule
