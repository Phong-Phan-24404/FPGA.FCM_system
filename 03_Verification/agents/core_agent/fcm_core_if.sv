// File: fcm_core_if.sv
// Description: Defines the signals used by the core UVM agent.

// This interface connects the UVM agent to the DUT through config_db.

// Interface: fcm_core_if
// Description: Connects the testbench interface signals to the DUT.
interface fcm_core_if import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic clk
);
  logic              rst_n;
  logic              start;
  logic [NUMC_W-1:0] num_clusters;

  logic [GRAY_W-1:0] hist_wr_addr;
  logic [COUNT_W-1:0] hist_wr_data;
  logic              hist_wr_en;

  center_t           init_centers_q [0:MAX_C-1];

  logic [GRAY_W-1:0]  labels_lut_addr;
  logic [LABEL_W-1:0] labels_lut_data;

  center_t           centers_q [0:MAX_C-1];
  logic              converged;
  logic [ITER_W-1:0] iter_converged;
  logic              busy;
  logic              done;
  logic              contract_error;
endinterface
