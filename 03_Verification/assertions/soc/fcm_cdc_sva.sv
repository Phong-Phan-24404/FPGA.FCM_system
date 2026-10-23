// File: fcm_cdc_sva.sv
// Description: Clock-domain-crossing assertions for fcm_de10lite_integration.

// The two clocks come from the same PLL reference and run at 50 MHz.
// The SDC keeps their paths timed instead of treating them as asynchronous.
// The synchronizer and FIFO give extra protection at the boundary.
// Simulation assertions check the crossing protocol, not metastability.
// A separate CDC tool would still be needed to check the synchronizer structure.

// Module: fcm_cdc_sva
// Description: Checks protocol rules at the clock-domain boundaries.
module fcm_cdc_sva (
    input logic       clk_50_i,
    input logic       clk_fcm_i,
    input logic       rst_n_i,

    // Check the FIFO write side on clk_50.
    input logic       pixel_valid_i,
    input logic [7:0] pixel_data_i,
    input logic       pixel_eof_i,
    input logic       pixel_ready_o,
    input logic       fifo_full,

    // Check the FIFO read side on clk_fcm.
    input logic       fifo_rdreq,
    input logic       fifo_empty,

    // Check stream_request passing from clk_fcm to clk_50 through three flops.
    input logic       stream_request_fcm,
    input logic       stream_request_meta_50,
    input logic       stream_request_sync_50
);

  // Check the FIFO input in the clk_50 domain.

  // Keep pixel data stable while the FIFO cannot accept it.
  // Timing checks alone cannot detect a dropped pixel.
  a_hold_data_when_backpressured: assert property (
      @(posedge clk_50_i) disable iff (!rst_n_i)
      (pixel_valid_i && !pixel_ready_o) |=> $stable({pixel_eof_i, pixel_data_i})
  ) else $error("cdc: nguon doi pixel trong khi dcfifo dang day");

  // Never write when fifo_full is high.
  // The RTL currently gates writes with !fifo_full.
  a_no_fifo_overflow: assert property (
      @(posedge clk_50_i) disable iff (!rst_n_i)
      fifo_full |-> !pixel_ready_o
  ) else $error("cdc: dcfifo day ma van bao ready");

  // Check FIFO reads in the clk_fcm domain.

  a_no_fifo_underflow: assert property (
      @(posedge clk_fcm_i) disable iff (!rst_n_i)
      fifo_rdreq |-> !fifo_empty
  ) else $error("cdc: doc dcfifo khi dang rong");

  // Check the control signal crossing between the two clocks.

  // stream_request_fcm is a level signal, not a one-cycle pulse.
  // Keep it high long enough for clk_50 to sample the synchronized value.
  a_stream_request_wide_enough: assert property (
      @(posedge clk_50_i) disable iff (!rst_n_i)
      $rose(stream_request_meta_50) |=> stream_request_meta_50
  ) else $error("cdc: stream_request qua ngan, phia clk_50 chi thay mot nhip");

  // The synchronized signal must follow the previous meta stage.
  a_sync_follows_meta: assert property (
      @(posedge clk_50_i) disable iff (!rst_n_i)
      ##1 stream_request_sync_50 == $past(stream_request_meta_50)
  ) else $error("cdc: tang dong bo thu hai khong bam theo tang thu nhat");

endmodule


// Keep bind inside a separate module.
// The testbench instantiates fcm_cdc_sva_bind to turn on these checks.

// Module: fcm_cdc_sva_bind
// Description: Binds the CDC assertions onto the integration layer.
module fcm_cdc_sva_bind;

  bind fcm_de10lite_integration fcm_cdc_sva u_sva (
      .clk_50_i(clk_50_i), .clk_fcm_i(clk_fcm_i), .rst_n_i(rst_n_i),
      .pixel_valid_i(pixel_valid_i), .pixel_data_i(pixel_data_i),
      .pixel_eof_i(pixel_eof_i), .pixel_ready_o(pixel_ready_o),
      .fifo_full(fifo_full),
      .fifo_rdreq(fifo_rdreq), .fifo_empty(fifo_empty),
      .stream_request_fcm(stream_request_fcm),
      .stream_request_meta_50(stream_request_meta_50),
      .stream_request_sync_50(stream_request_sync_50)
  );

endmodule
