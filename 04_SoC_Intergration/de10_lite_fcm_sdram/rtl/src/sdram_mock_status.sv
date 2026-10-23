// File: sdram_mock_status.sv
// Description: Shows test status on the FPGA seven-segment displays.
// Author: Phan Chau Phong

// Module: sdram_mock_status
// Description: Tracks mock SDRAM test progress and displays pass or fail results.

module sdram_mock_status (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       upload_start_i,
    input  logic       stream_start_i,
    input  logic       upload_error_i,
    input  logic       stream_done_i,
    input  logic       stream_error_i,
    input  logic       stream_parity_i,
    output logic [7:0] hex0_o,
    output logic [7:0] hex1_o,
    output logic [7:0] hex2_o,
    output logic [7:0] hex3_o,
    output logic [7:0] hex4_o,
    output logic [7:0] hex5_o,
    output logic       pass_o,
    output logic       fail_o
);
    typedef enum logic [1:0] {IDLE, RUNNING, PASS, FAIL} state_t;
    state_t state_q;

    // Function: seven_seg
    // Description: Returns the display pattern for the test status digits.
    function automatic logic [7:0] seven_seg(input logic [3:0] digit);

        case (digit)
            4'd3:   seven_seg = 8'b1_0110000;
            4'd5:   seven_seg = 8'b1_0010010;
            4'd8:   seven_seg = 8'b1_0000000;
            4'd9:   seven_seg = 8'b1_0010000;
            default: seven_seg = 8'hff;
        endcase
    endfunction

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_q <= IDLE;
        end else if (upload_start_i) begin
            state_q <= IDLE;
        end else begin
            case (state_q)
                IDLE: begin
                    if (upload_error_i)
                        state_q <= FAIL;
                    else if (stream_start_i)
                        state_q <= RUNNING;
                end
                RUNNING: begin
                    if (upload_error_i || stream_error_i)
                        state_q <= FAIL;
                    else if (stream_done_i)
                        state_q <= stream_parity_i ? FAIL : PASS;
                end
                PASS, FAIL: state_q <= state_q;
                default:    state_q <= FAIL;
            endcase
        end
    end

    always_comb begin
        hex0_o = 8'hff;
        hex1_o = 8'hff;
        hex2_o = 8'hff;
        hex3_o = 8'hff;
        hex4_o = 8'hff;
        hex5_o = 8'hff;
        pass_o = 1'b0;
        fail_o = 1'b0;
        case (state_q)
            PASS: begin
                hex5_o = seven_seg(4'd3);
                hex4_o = seven_seg(4'd3);
                hex3_o = seven_seg(4'd3);
                hex2_o = seven_seg(4'd9);
                hex1_o = seven_seg(4'd9);
                hex0_o = seven_seg(4'd9);
                pass_o = 1'b1;
            end
            FAIL: begin
                hex5_o = seven_seg(4'd8);
                hex4_o = seven_seg(4'd8);
                hex3_o = seven_seg(4'd8);
                hex2_o = seven_seg(4'd5);
                hex1_o = seven_seg(4'd5);
                hex0_o = seven_seg(4'd5);
                fail_o = 1'b1;
            end
            default: begin end
        endcase
    end
endmodule
