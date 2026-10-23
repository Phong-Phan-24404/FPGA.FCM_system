// File: tb_image_stream_reader.sv
// Description: Checks pixels read from the image stream memory.

// Author: Phan Chau Phong

`timescale 1ns/1ps

// Module: tb_image_stream_reader
// Description: Checks pixels read from the image stream memory.
module tb_image_stream_reader;
    localparam int ADDR_WIDTH = 16;
    localparam int WIDTH = 23;
    localparam int HEIGHT = 3;
    localparam int STRIDE = 32;
    localparam int WORDS_PER_LINE = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic start = 1'b0;
    logic [ADDR_WIDTH-1:0] frame_base_addr = 16'h0100;
    logic [15:0] image_width = WIDTH;
    logic [15:0] image_height = HEIGHT;
    logic [ADDR_WIDTH-1:0] line_stride_bytes = STRIDE;
    logic mem_read;
    logic [ADDR_WIDTH-1:0] mem_address;
    logic mem_acknowledge = 1'b0;
    logic [127:0] mem_read_data = '0;
    logic [7:0] pixel_data;
    logic pixel_valid;
    logic pixel_ready = 1'b0;
    logic pixel_sof;
    logic pixel_eol;
    logic pixel_eof;
    logic busy;
    logic done;
    logic error;

    logic [7:0] memory [0:511];
    logic pending = 1'b0;
    logic [ADDR_WIDTH-1:0] pending_address;
    integer stall_count = 0;
    integer expected_x = 0;
    integer expected_y = 0;
    integer received_pixels = 0;
    integer request_count = 0;
    integer ready_cycle = 0;

    image_stream_reader #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MAX_WORDS_PER_LINE(4)
    ) dut (.*);

    always #5 clk = ~clk;

    // Function: expected_pixel
    // Description: Calculates the expected image pixel value.
    function automatic [7:0] expected_pixel(input integer x, input integer y);
        expected_pixel = (y * 8'h40) + x;
    endfunction

    // Function: read_word
    // Description: Reads one word from the test memory.
    function automatic [127:0] read_word(input integer address);
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                read_word[i*8 +: 8] = memory[address+i];
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (mem_acknowledge) begin

            mem_acknowledge <= 1'b0;
        end else if (pending) begin
            if (stall_count == 0) begin
                mem_read_data <= read_word(pending_address);
                mem_acknowledge <= 1'b1;
                pending <= 1'b0;
            end else begin
                stall_count <= stall_count - 1;
            end
        end else if (mem_read) begin
            pending_address <= mem_address;
            stall_count <= request_count % 3;
            request_count <= request_count + 1;
            pending <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        ready_cycle <= ready_cycle + 1;
        pixel_ready <= (ready_cycle % 4) != 2;
        if (pixel_valid && pixel_ready) begin
            if (pixel_data !== expected_pixel(expected_x, expected_y)) begin
                $fatal(1, "pixel mismatch at (%0d,%0d): got %02h", expected_x,
                       expected_y, pixel_data);
            end
            if (pixel_sof !== ((expected_x == 0) && (expected_y == 0))) begin
                $fatal(1, "incorrect SOF marker");
            end
            if (pixel_eol !== (expected_x == WIDTH-1)) begin
                $fatal(1, "incorrect EOL marker");
            end
            if (pixel_eof !== ((expected_x == WIDTH-1) && (expected_y == HEIGHT-1))) begin
                $fatal(1, "incorrect EOF marker");
            end

            received_pixels <= received_pixels + 1;
            if (expected_x == WIDTH-1) begin
                expected_x <= 0;
                expected_y <= expected_y + 1;
            end else begin
                expected_x <= expected_x + 1;
            end
        end
    end

    initial begin : stimulus
        integer x;
        integer y;
        integer i;
        for (i = 0; i < 512; i = i + 1) begin
            memory[i] = 8'hA5;
        end
        for (y = 0; y < HEIGHT; y = y + 1) begin
            for (x = 0; x < WIDTH; x = x + 1) begin
                memory[frame_base_addr + y*STRIDE + x] = expected_pixel(x, y);
            end
        end

        repeat (3) @(posedge clk);
        reset_n <= 1'b1;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait (done);
        @(posedge clk);
        if (error) $fatal(1, "unexpected reader error");
        if (received_pixels != WIDTH*HEIGHT) begin
            $fatal(1, "expected %0d pixels, received %0d", WIDTH*HEIGHT, received_pixels);
        end
        if (request_count != HEIGHT*WORDS_PER_LINE) begin
            $fatal(1, "expected %0d reads, observed %0d", HEIGHT*WORDS_PER_LINE, request_count);
        end
        $display("PASS: image stream reader transferred %0d pixels", received_pixels);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "simulation timeout");
    end
endmodule
