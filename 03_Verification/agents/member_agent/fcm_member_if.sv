// File: fcm_member_if.sv
// Description: Defines the signals used by the member UVM agent.

// This interface connects the UVM agent to the DUT through config_db.

// Interface: fcm_member_if
// Description: Connects the testbench interface signals to the DUT.
interface fcm_member_if import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic clk
);
  logic              rst_n;
  logic              start;
  logic [NUMC_W-1:0] num_clusters;
  logic [GRAY_W-1:0] gray;
  center_t           centers_q [0:MAX_C-1];
  member_t           membership_q [0:MAX_C-1];
  logic              busy;
  logic              done;
  logic              contract_error;
endinterface
