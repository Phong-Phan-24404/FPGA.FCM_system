// File: tb_fcm_stream_pipeline_uvm.sv
// Description: Connects the stream pipeline to its UVM testbench.

// Run image-based SoC UVM tests from the full pixel stream.

`timescale 1ns/1ps

// Module: tb_fcm_stream_pipeline_uvm
// Description: Connects the stream pipeline to its UVM testbench.
module tb_fcm_stream_pipeline_uvm;

  import uvm_pkg::*;
  import fcm_pkg::*;
  import fcm_soc_uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int CLK_HALF = 5;

  logic clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  fcm_soc_if #(.MAX_C(MAX_CLUSTERS)) vif (.clk(clk));

  fcm_stream_pipeline dut (
      .clk_i                 (clk),
      .rst_n_i               (vif.rst_n),
      .start_i               (vif.start),
      .num_clusters_i        (vif.num_clusters),
      .stream_start_o        (vif.stream_start),
      .pixel_data_i          (vif.pixel_data),
      .pixel_valid_i         (vif.pixel_valid),
      .pixel_ready_o         (vif.pixel_ready),
      .pixel_eof_i           (vif.pixel_eof),
      .centroids_o           (vif.centroids),
      .active_num_clusters_o (vif.active_num_clusters),
      .busy_o                (vif.busy),
      .done_o                (vif.done),
      .error_o               (vif.error),
      .contract_error_o      (vif.contract_error),
      .stage_o               (vif.stage)
  );

  // Enable both SoC and IP assertions for the blocks inside the pipeline.
  fcm_soc_sva_bind    u_bind_soc ();
  fcm_sva_bind_member u_bind_member ();
  fcm_sva_bind_core   u_bind_core ();

  initial begin
    vif.rst_n = 1'b0;
    repeat (5) @(posedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    // Give the interface to the UVM test so it can configure the stream agent.
    uvm_config_db #(virtual fcm_soc_if)::set(null, "uvm_test_top", "vif", vif);
    run_test();
  end

  // Allow enough time for image streaming and FCM processing.
  initial begin
    #4000ms;
    `uvm_fatal("TIMEOUT", "tb_fcm_stream_pipeline_uvm qua thoi gian")
  end

endmodule
