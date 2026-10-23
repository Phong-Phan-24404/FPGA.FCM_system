// File: tb_fcm_core_uvm.sv
// Description: Connects the core DUT to its UVM testbench.

// Run the full core UVM testbench with reference histogram vectors.

`timescale 1ns/1ps

// Module: tb_fcm_core_uvm
// Description: Connects the core DUT to its UVM testbench.
module tb_fcm_core_uvm;

  import uvm_pkg::*;
  import fcm_pkg::*;
  import fcm_core_uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int CLK_HALF = 5;

  logic clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  fcm_core_if #(.MAX_C(MAX_CLUSTERS)) vif (.clk(clk));

  fcm_core #(.MAX_C(MAX_CLUSTERS)) dut (
      .clk             (clk),
      .rst_n           (vif.rst_n),
      .start           (vif.start),
      .num_clusters    (vif.num_clusters),
      .hist_wr_addr    (vif.hist_wr_addr),
      .hist_wr_data    (vif.hist_wr_data),
      .hist_wr_en      (vif.hist_wr_en),
      .init_centers_q  (vif.init_centers_q),
      .labels_lut_addr (vif.labels_lut_addr),
      .labels_lut_data (vif.labels_lut_data),
      .centers_q       (vif.centers_q),
      .converged       (vif.converged),
      .iter_converged  (vif.iter_converged),
      .busy            (vif.busy),
      .done            (vif.done),
      .contract_error  (vif.contract_error)
  );

  // Enable both the member and core assertion bind groups.
  fcm_sva_bind_member u_sva_bind_member ();
  fcm_sva_bind_core   u_sva_bind_core   ();

  initial begin
    vif.rst_n = 1'b0;
    repeat (5) @(posedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    // Give the interface to the top-level UVM test, which configures the agent.
    uvm_config_db #(virtual fcm_core_if)::set(null, "uvm_test_top", "vif", vif);
    run_test();
  end

  // Use a watchdog so a stalled core simulation ends with an error.
  initial begin
    #2000ms;
    `uvm_fatal("TIMEOUT", "tb_fcm_core_uvm qua thoi gian")
  end

endmodule
