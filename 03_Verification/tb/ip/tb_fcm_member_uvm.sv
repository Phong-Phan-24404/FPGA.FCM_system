// File: tb_fcm_member_uvm.sv
// Description: Connects the membership DUT to its UVM testbench.

// Run the UVM membership testbench with reference trace vectors.

`timescale 1ns/1ps

// Module: tb_fcm_member_uvm
// Description: Connects the membership DUT to its UVM testbench.
module tb_fcm_member_uvm;

  import uvm_pkg::*;
  import fcm_pkg::*;
  import fcm_member_uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int CLK_HALF = 5;

  logic clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  fcm_member_if #(.MAX_C(MAX_CLUSTERS)) vif (.clk(clk));

  fcm_member #(.MAX_C(MAX_CLUSTERS)) dut (
      .clk            (clk),
      .rst_n          (vif.rst_n),
      .start          (vif.start),
      .num_clusters   (vif.num_clusters),
      .gray           (vif.gray),
      .centers_q      (vif.centers_q),
      .membership_q   (vif.membership_q),
      .busy           (vif.busy),
      .done           (vif.done),
      .contract_error (vif.contract_error)
  );

  // Instantiate the assertion bind module so protocol checks are active.
  fcm_sva_bind_member u_sva_bind ();

  initial begin
    vif.rst_n = 1'b0;
    repeat (5) @(posedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    // Give the interface to the UVM test, which passes it to the correct agent.
    uvm_config_db #(virtual fcm_member_if)::set(null, "uvm_test_top", "vif", vif);
    run_test();
  end

  // Limit simulation time so a stalled transaction fails clearly.
  initial begin
    #200ms;
    `uvm_fatal("TIMEOUT", "tb_fcm_member_uvm quá thời gian")
  end

endmodule
