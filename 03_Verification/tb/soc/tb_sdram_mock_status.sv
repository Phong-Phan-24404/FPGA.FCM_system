// File: tb_sdram_mock_status.sv
// Description: Checks the SDRAM mock status and control signals.

// Author: Phan Chau Phong

`timescale 1ns/1ps

// Module: tb_sdram_mock_status
// Description: Checks the SDRAM mock status and control signals.
module tb_sdram_mock_status;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic upload_start = 1'b0;
    logic stream_start = 1'b0;
    logic upload_error = 1'b0;
    logic stream_done = 1'b0;
    logic stream_error = 1'b0;
    logic stream_parity = 1'b0;
    logic [7:0] hex0, hex1, hex2, hex3, hex4, hex5;
    logic pass, fail;

    always #5 clk = ~clk;

    sdram_mock_status dut (
        .clk_i(clk), .rst_n_i(rst_n), .upload_start_i(upload_start),
        .stream_start_i(stream_start), .upload_error_i(upload_error),
        .stream_done_i(stream_done), .stream_error_i(stream_error),
        .stream_parity_i(stream_parity), .hex0_o(hex0), .hex1_o(hex1),
        .hex2_o(hex2), .hex3_o(hex3), .hex4_o(hex4), .hex5_o(hex5),
        .pass_o(pass), .fail_o(fail)
    );

    // Task: pulse_upload_start;
    // Description: Runs the pulse upload start; step of verification.
    task automatic pulse_upload_start;
        begin
            @(negedge clk);
            upload_start = 1'b1;
            @(negedge clk);
            upload_start = 1'b0;
        end
    endtask

    // Task: pulse_stream_start;
    // Description: Runs the pulse stream start; step of verification.
    task automatic pulse_stream_start;
        begin
            @(negedge clk);
            stream_start = 1'b1;
            @(negedge clk);
            stream_start = 1'b0;
        end
    endtask

    // Task: pulse_stream_done;
    // Description: Runs the pulse stream done; step of verification.
    task automatic pulse_stream_done;
        begin
            @(negedge clk);
            stream_done = 1'b1;
            @(negedge clk);
            stream_done = 1'b0;
        end
    endtask

    // Task: expect_pass;
    // Description: Runs the expect pass; step of verification.
    task automatic expect_pass;
        begin
            if (!pass || fail || hex5 != 8'b1_0110000 || hex4 != 8'b1_0110000 ||
                hex3 != 8'b1_0110000 || hex2 != 8'b1_0010000 ||
                hex1 != 8'b1_0010000 || hex0 != 8'b1_0010000)
                $fatal(1, "expected 333999 pass display");
        end
    endtask

    // Task: expect_fail;
    // Description: Runs the expect fail; step of verification.
    task automatic expect_fail;
        begin
            if (pass || !fail || hex5 != 8'b1_0000000 || hex4 != 8'b1_0000000 ||
                hex3 != 8'b1_0000000 || hex2 != 8'b1_0010010 ||
                hex1 != 8'b1_0010010 || hex0 != 8'b1_0010010)
                $fatal(1, "expected 888555 fail display");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        pulse_upload_start();
        pulse_stream_start();
        pulse_stream_done();
        @(posedge clk);
        expect_pass();

        pulse_upload_start();
        pulse_stream_start();
        stream_parity = 1'b1;
        pulse_stream_done();
        @(posedge clk);
        expect_fail();

        $display("PASS: tb_sdram_mock_status");
        $finish;
    end
endmodule
