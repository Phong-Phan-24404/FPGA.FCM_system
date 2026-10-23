// File: tb_fcm_board_ui.sv
// Description: Checks the board UI input and output signals.

// Author: Phan Chau Phong

`timescale 1ns/1ps

// Module: tb_fcm_board_ui
// Description: Checks the board UI input and output signals.
module tb_fcm_board_ui;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic key1_n = 1'b1;
    logic [9:0] sw = '0;
    logic image_loaded = 1'b0;
    logic fcm_busy = 1'b0;
    logic fcm_done = 1'b0;
    logic error = 1'b0;
    logic [2:0] active_k = 3'd3;
    logic [7:0] centroids [0:6];
    logic [2:0] selected_k;
    logic fcm_start;
    logic [9:0] ledr;
    logic [7:0] hex0, hex1, hex2, hex3, hex4, hex5;
    integer starts = 0;
    integer i;

    fcm_board_ui #(.DEBOUNCE_CYCLES(2)) dut (
        .clk_i(clk), .rst_n_i(rst_n), .key1_n_i(key1_n), .sw_i(sw),
        .image_loaded_i(image_loaded), .fcm_busy_i(fcm_busy),
        .fcm_done_i(fcm_done), .error_i(error), .contract_error_i(1'b0),
        .active_num_clusters_i(active_k), .centroids_i(centroids),
        .selected_num_clusters_o(selected_k), .fcm_start_o(fcm_start),
        .ledr_o(ledr), .hex0_o(hex0), .hex1_o(hex1), .hex2_o(hex2),
        .hex3_o(hex3), .hex4_o(hex4), .hex5_o(hex5)
    );

    always #5 clk = ~clk;
    always @(posedge clk) if (fcm_start) starts <= starts + 1;

    initial begin
        for (i = 0; i < 7; i = i + 1)
            centroids[i] = 8'h00;
        centroids[1] = 8'h8e;

        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        image_loaded <= 1'b1;
        sw[2:0] <= 3'd3;
        repeat (4) @(posedge clk);
        if (selected_k != 3'd3 || !ledr[0] || !ledr[1])
            $fatal(1, "ready/K selection display state is incorrect");

        key1_n <= 1'b0;
        repeat (5) @(posedge clk);
        key1_n <= 1'b1;
        repeat (5) @(posedge clk);
        if (starts != 1)
            $fatal(1, "expected one debounced FCM start, got %0d", starts);

        fcm_busy <= 1'b1;
        @(posedge clk);
        if (!ledr[2] || ledr[3])
            $fatal(1, "running LED state is incorrect");

        fcm_busy <= 1'b0;
        fcm_done <= 1'b1;
        sw[5:3] <= 3'd1;
        repeat (3) @(posedge clk);
        if (!ledr[3] || hex5 != 8'b1_1000110 ||
            hex4 != 8'b1_1111001 || hex1 != 8'b1_0000000 ||
            hex0 != 8'b1_0000110)
            $fatal(1, "centroid C1=8E display state is incorrect");

        sw[5:3] <= 3'd5;
        repeat (3) @(posedge clk);
        if (hex2 != 8'b1_0100001 || hex1 != 8'b1_0100001 || hex0 != 8'b1_0100001)
            $fatal(1, "out-of-range centroid must display dashes");
        $display("PASS: DE10-Lite FCM UI behavior");
        $finish;
    end
endmodule
