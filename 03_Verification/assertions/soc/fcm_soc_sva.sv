// File: fcm_soc_sva.sv
// Description: Contains protocol and output assertions for the SoC stream pipeline.

// Bind these assertions to the SoC stream pipeline to check its input and output protocol.

// Module: fcm_stream_pipeline_sva
// Description: Checks the handshake and output signals.
module fcm_stream_pipeline_sva import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic              clk_i,
    input logic              rst_n_i,
    input logic              start_i,
    input logic [NUMC_W-1:0] num_clusters_i,
    input logic              busy_o,
    input logic              done_o,
    input logic              error_o,
    input logic              contract_error_o,
    input logic              pixel_valid_i,
    input logic              pixel_ready_o,
    input logic              stream_start_o,
    input logic [7:0]        centroids_o [0:MAX_C-1],
    input logic [NUMC_W-1:0] active_num_clusters_o
);

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_n_i);

  // A new start cannot interrupt an active image stream.
  a_no_start_while_busy: assert property (
      start_i |-> !busy_o
  ) else $error("fcm_stream_pipeline: start trong khi busy");

  // pixel_ready must only be high while the pipeline can receive pixels.
  a_ready_only_when_streaming: assert property (
      pixel_ready_o |-> stream_start_o
  ) else $error("fcm_stream_pipeline: pixel_ready ngoai cua so streaming");

  // A frame cannot finish with both DONE and error.
  a_done_xor_error: assert property (
      !(done_o && error_o)
  ) else $error("fcm_stream_pipeline: done va error cung len");

  // The requested cluster count must be in the supported range.
  a_k_in_range: assert property (
      start_i |-> (num_clusters_i >= NUMC_W'(MIN_CLUSTERS)) &&
                  (num_clusters_i <= NUMC_W'(MAX_CLUSTERS))
  ) else $error("fcm_stream_pipeline: K=%0d ngoai dai 2..7", num_clusters_i);

  // Check that the requested cluster count is latched on the cycle after START.
  a_numc_latched: assert property (
      (start_i && !busy_o) |=> (active_num_clusters_o == $past(num_clusters_i))
  ) else $error("fcm_stream_pipeline: active_num_clusters=%0d, K yeu cau=%0d",
                active_num_clusters_o, $past(num_clusters_i));

  // The contract error flag must stay low during a valid run.
  a_no_contract_error: assert property (
      !contract_error_o
  ) else $error("fcm_stream_pipeline: contract_error_o");

endmodule


// Keep bind statements inside this helper module so the simulator elaborates the assertions.
// Module: fcm_soc_sva_bind
// Description: Binds the checks to their DUT modules.
module fcm_soc_sva_bind;

  bind fcm_stream_pipeline fcm_stream_pipeline_sva u_sva (
      .clk_i(clk_i), .rst_n_i(rst_n_i), .start_i(start_i),
      .num_clusters_i(num_clusters_i),
      .busy_o(busy_o), .done_o(done_o), .error_o(error_o),
      .contract_error_o(contract_error_o),
      .pixel_valid_i(pixel_valid_i), .pixel_ready_o(pixel_ready_o),
      .stream_start_o(stream_start_o),
      .centroids_o(centroids_o),
      .active_num_clusters_o(active_num_clusters_o)
  );

endmodule
