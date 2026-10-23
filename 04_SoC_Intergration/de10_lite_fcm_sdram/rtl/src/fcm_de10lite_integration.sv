// File: fcm_de10lite_integration.sv
// Description: Connects the image stream and FCM controls to the DE10-Lite board.
// Author: Phan Chau Phong

// Module: fcm_de10lite_integration
// Description: Connects the pixel clock bridge, FCM pipeline, and board display controls.

module fcm_de10lite_integration (
    input  logic        clk_50_i,
    input  logic        clk_fcm_i,
    input  logic        rst_n_i,
    input  logic        key1_n_i,
    input  logic [9:0]  sw_i,
    input  logic        image_loaded_i,
    input  logic        upload_error_i,
    input  logic        stream_error_i,
    output logic        stream_start_o,
    input  logic [7:0]  pixel_data_i,
    input  logic        pixel_valid_i,
    output logic        pixel_ready_o,
    input  logic        pixel_eof_i,
    output logic        fcm_busy_o,
    output logic        fcm_done_o,
    output logic        fcm_error_o,
    output logic [3:0]  fcm_stage_o,
    output logic [9:0]  ledr_o,
    output logic [7:0]  hex0_o,
    output logic [7:0]  hex1_o,
    output logic [7:0]  hex2_o,
    output logic [7:0]  hex3_o,
    output logic [7:0]  hex4_o,
    output logic [7:0]  hex5_o
);
    logic [2:0] selected_num_clusters;
    logic [2:0] active_num_clusters;
    logic [7:0] final_centroids [0:6];
    logic       fcm_start;
    logic       stream_request_fcm;
    logic       stream_request_meta_50;
    logic       stream_request_sync_50;
    logic       stream_request_sync_d_50;
    logic [8:0] fifo_q;
    logic       fifo_full;
    logic       fifo_empty;
    logic       fifo_rdreq;
    logic       pixel_ready_fcm;
    logic       fcm_contract_error;

    dcfifo #(
        .intended_device_family("MAX 10"),
        .lpm_numwords(512), .lpm_showahead("ON"), .lpm_type("dcfifo"),
        .lpm_width(9), .lpm_widthu(9), .overflow_checking("ON"),
        .underflow_checking("ON"), .rdsync_delaypipe(4), .wrsync_delaypipe(4),
        .use_eab("ON")
    ) pixel_clock_bridge (
        .aclr(~rst_n_i),
        .data({pixel_eof_i, pixel_data_i}),
        .wrclk(clk_50_i),
        .wrreq(pixel_valid_i && !fifo_full),
        .wrfull(fifo_full),
        .rdclk(clk_fcm_i),
        .rdreq(fifo_rdreq),
        .q(fifo_q),
        .rdempty(fifo_empty)
    );

    assign pixel_ready_o = !fifo_full;
    assign fifo_rdreq    = !fifo_empty && pixel_ready_fcm;

    always_ff @(posedge clk_50_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            stream_request_meta_50   <= 1'b0;
            stream_request_sync_50   <= 1'b0;
            stream_request_sync_d_50 <= 1'b0;
        end else begin
            stream_request_meta_50   <= stream_request_fcm;
            stream_request_sync_50   <= stream_request_meta_50;
            stream_request_sync_d_50 <= stream_request_sync_50;
        end
    end
    assign stream_start_o = stream_request_sync_50 & ~stream_request_sync_d_50;

`ifdef ALTERA_RESERVED_QIS
    fcm_stream_pipeline fcm_pipeline (
        .clk_i(clk_fcm_i), .rst_n_i, .start_i(fcm_start),
        .num_clusters_i(selected_num_clusters),
        .stream_start_o(stream_request_fcm), .pixel_data_i(fifo_q[7:0]),
        .pixel_valid_i(!fifo_empty), .pixel_ready_o(pixel_ready_fcm),
        .pixel_eof_i(fifo_q[8]), .centroids_o(final_centroids),
        .active_num_clusters_o(active_num_clusters), .busy_o(fcm_busy_o),
        .done_o(fcm_done_o), .error_o(fcm_error_o),
        .contract_error_o(fcm_contract_error), .stage_o(fcm_stage_o)
    );
`else

    fcm_stream_pipeline fcm_pipeline (
        .clk_i(clk_fcm_i), .rst_n_i, .start_i(fcm_start),
        .num_clusters_i(selected_num_clusters), .stream_start_o(stream_request_fcm),
        .pixel_data_i(fifo_q[7:0]), .pixel_valid_i(!fifo_empty),
        .pixel_ready_o(pixel_ready_fcm), .pixel_eof_i(fifo_q[8]), .centroids_o(),
        .active_num_clusters_o(active_num_clusters), .busy_o(fcm_busy_o),
        .done_o(fcm_done_o), .error_o(fcm_error_o),
        .contract_error_o(fcm_contract_error), .stage_o(fcm_stage_o)
    );

    generate
        genvar centroid_sim_index;
        for (centroid_sim_index = 0; centroid_sim_index < 7;
             centroid_sim_index = centroid_sim_index + 1) begin : gen_centroids_sim
            assign final_centroids[centroid_sim_index] =
                fcm_pipeline.centroids_o[centroid_sim_index];
        end
    endgenerate
`endif

    // Use 500,000 FCM clock cycles for button debouncing.
    // This gives a 10 ms debounce time when clk_fcm_i runs at 50 MHz.
    fcm_board_ui #(.DEBOUNCE_CYCLES(500_000)) board_ui (
        .clk_i(clk_fcm_i), .rst_n_i, .key1_n_i, .sw_i, .image_loaded_i,
        .fcm_busy_i(fcm_busy_o), .fcm_done_i(fcm_done_o),
        .error_i(upload_error_i | stream_error_i | fcm_error_o),
        .contract_error_i(fcm_contract_error),
        .active_num_clusters_i(active_num_clusters),
        .centroids_i(final_centroids),
        .selected_num_clusters_o(selected_num_clusters), .fcm_start_o(fcm_start),
        .ledr_o, .hex0_o, .hex1_o, .hex2_o, .hex3_o, .hex4_o, .hex5_o
    );
endmodule
