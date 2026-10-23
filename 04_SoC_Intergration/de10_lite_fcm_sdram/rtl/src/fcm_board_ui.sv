// File: fcm_board_ui.sv
// Description: Handles the FPGA board buttons, switches, LEDs, and seven-segment displays.
// Author: Phan Chau Phong

// Module: fcm_board_ui
// Description: Starts clustering from the debounced button and displays FCM status and centers.

module fcm_board_ui #(
    parameter int DEBOUNCE_CYCLES = 500_000
) (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       key1_n_i,
    input  logic [9:0] sw_i,
    input  logic       image_loaded_i,
    input  logic       fcm_busy_i,
    input  logic       fcm_done_i,
    input  logic       error_i,
    // A contract error lights LEDR[5] but still allows another run.
    // The regular error signal blocks the start button.
    input  logic       contract_error_i,
    input  logic [2:0] active_num_clusters_i,
    input  logic [7:0] centroids_i [0:6],
    output logic [2:0] selected_num_clusters_o,
    output logic       fcm_start_o,
    output logic [9:0] ledr_o,
    output logic [7:0] hex0_o,
    output logic [7:0] hex1_o,
    output logic [7:0] hex2_o,
    output logic [7:0] hex3_o,
    output logic [7:0] hex4_o,
    output logic [7:0] hex5_o
);
    localparam int DB_W = $clog2(DEBOUNCE_CYCLES + 1);
    logic key_meta_q, key_sync_q, key_pressed_q, key_pressed_prev_q;
    logic [DB_W-1:0] key_stable_count_q;
    logic [9:0] sw_meta_q, sw_sync_q;
    logic [2:0] k_selected;
    logic [2:0] centroid_index;
    logic       k_valid;
    logic [7:0] selected_centroid;
    logic       centroid_valid;

    // Function: seg_digit
    // Description: Returns the seven-segment pattern for a hexadecimal digit.
    function automatic logic [7:0] seg_digit(input logic [3:0] digit);
        case (digit)
            4'd0: seg_digit = 8'b1_1000000;
            4'd1: seg_digit = 8'b1_1111001;
            4'd2: seg_digit = 8'b1_0100100;
            4'd3: seg_digit = 8'b1_0110000;
            4'd4: seg_digit = 8'b1_0011001;
            4'd5: seg_digit = 8'b1_0010010;
            4'd6: seg_digit = 8'b1_0000010;
            4'd7: seg_digit = 8'b1_1111000;
            4'd8: seg_digit = 8'b1_0000000;
            4'd9: seg_digit = 8'b1_0010000;
            4'hA: seg_digit = 8'b1_0001000;
            4'hB: seg_digit = 8'b1_0000011;
            4'hC: seg_digit = 8'b1_1000110;
            4'hD: seg_digit = 8'b1_0100001;
            4'hE: seg_digit = 8'b1_0000110;
            default: seg_digit = 8'b1_0001110;
        endcase
    endfunction

    // Function: seg_char
    // Description: Returns the seven-segment pattern for a display character.
    function automatic logic [7:0] seg_char(input logic [7:0] c);
        case (c)
            "K": seg_char = 8'b1_0001001;
            "L": seg_char = 8'b1_1000111;
            "O": seg_char = 8'b1_1000000;
            "A": seg_char = 8'b1_0001000;
            "d": seg_char = 8'b1_0100001;
            "r": seg_char = 8'b1_0101111;
            "U": seg_char = 8'b1_1000001;
            "n": seg_char = 8'b1_0101011;
            "E": seg_char = 8'b1_0000110;
            default: seg_char = 8'hff;
        endcase
    endfunction

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            key_meta_q          <= 1'b1;
            key_sync_q          <= 1'b1;
            key_pressed_q       <= 1'b0;
            key_pressed_prev_q  <= 1'b0;
            key_stable_count_q  <= '0;
            sw_meta_q           <= '0;
            sw_sync_q           <= '0;
            fcm_start_o         <= 1'b0;
        end else begin
            key_meta_q <= key1_n_i;
            key_sync_q <= key_meta_q;
            sw_meta_q  <= sw_i;
            sw_sync_q  <= sw_meta_q;
            fcm_start_o <= 1'b0;

            if ((~key_sync_q) == key_pressed_q) begin
                key_stable_count_q <= '0;
            end else if (key_stable_count_q == DEBOUNCE_CYCLES-1) begin
                key_pressed_q      <= ~key_sync_q;
                key_stable_count_q <= '0;
            end else begin
                key_stable_count_q <= key_stable_count_q + 1'b1;
            end

            key_pressed_prev_q <= key_pressed_q;
            if (key_pressed_q && !key_pressed_prev_q && image_loaded_i &&
                !fcm_busy_i && !error_i && k_valid)
                fcm_start_o <= 1'b1;
        end
    end

    always_comb begin

        k_selected       = sw_sync_q[2:0];
        k_valid          = (k_selected >= 3'd2) && (k_selected <= 3'd7);
        centroid_index   = sw_sync_q[5:3];
        selected_centroid = 8'd0;
        centroid_valid   = (centroid_index < active_num_clusters_i);
        if (centroid_index < 3'd7)
            selected_centroid = centroids_i[centroid_index];
        selected_num_clusters_o = k_valid ? k_selected : 3'd2;

        ledr_o      = '0;
        ledr_o[0]   = image_loaded_i;
        ledr_o[1]   = image_loaded_i && !fcm_busy_i && !fcm_done_i && k_valid;
        ledr_o[2]   = fcm_busy_i;
        ledr_o[3]   = fcm_done_i;
        ledr_o[4]   = error_i;
        ledr_o[5]   = contract_error_i;

        hex0_o = 8'hff;
        hex1_o = 8'hff;
        hex2_o = 8'hff;
        hex3_o = 8'hff;
        hex4_o = 8'hff;
        hex5_o = 8'hff;
        if (error_i) begin
            hex5_o = seg_char("E");
            hex4_o = seg_char("r");
            hex3_o = seg_char("r");
        end else if (!image_loaded_i) begin
            hex5_o = seg_char("L");
            hex4_o = seg_char("O");
            hex3_o = seg_char("A");
            hex2_o = seg_char("d");
        end else if (fcm_busy_i) begin
            hex5_o = seg_char("r");
            hex4_o = seg_char("U");
            hex3_o = seg_char("n");
        end else if (fcm_done_i) begin

            hex5_o = seg_digit(4'hC);
            hex4_o = seg_digit({1'b0, centroid_index});
            if (centroid_valid) begin
                hex1_o = seg_digit(selected_centroid[7:4]);
                hex0_o = seg_digit(selected_centroid[3:0]);
            end else begin
                hex2_o = seg_digit(4'hD);
                hex1_o = seg_digit(4'hD);
                hex0_o = seg_digit(4'hD);
            end
        end else begin
            hex5_o = seg_char("K");
            hex0_o = k_valid ? seg_digit({1'b0, k_selected}) : seg_digit(4'hE);
        end
    end
endmodule
