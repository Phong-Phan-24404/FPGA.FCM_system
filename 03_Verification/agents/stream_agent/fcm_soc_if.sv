// File: fcm_soc_if.sv
// Description: Defines the signals used by the soc UVM agent.

// This interface connects the SoC image stream and results to the UVM agent.

// Interface: fcm_soc_if
// Description: Connects the testbench interface signals to the DUT.
interface fcm_soc_if import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic clk
);
  logic              rst_n;
  logic              start;
  logic [NUMC_W-1:0] num_clusters;

  // pixel_ready shows when the DUT can accept a pixel.
  logic              stream_start;
  logic [7:0]        pixel_data;
  logic              pixel_valid;
  logic              pixel_ready;
  logic              pixel_eof;

  logic [7:0]        centroids [0:MAX_C-1];
  logic [NUMC_W-1:0] active_num_clusters;
  logic              busy;
  logic              done;
  logic              error;
  logic              contract_error;
  logic [3:0]        stage;
endinterface
