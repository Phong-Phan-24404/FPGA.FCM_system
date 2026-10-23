// File: image_stream_reader.sv
// Description: Reads stored image pixels and sends them to the processing pipeline.
// Author: Phan Chau Phong

// Module: image_stream_reader
// Description: Controls pixel streaming and the ready/valid handshake.

module image_stream_reader #(
    parameter int ADDR_WIDTH         = 26,
    parameter int MAX_WORDS_PER_LINE = 128
) (
    input  logic                  clk,
    input  logic                  reset_n,

    input  logic                  start,
    input  logic [ADDR_WIDTH-1:0] frame_base_addr,
    input  logic [15:0]           image_width,
    input  logic [15:0]           image_height,
    input  logic [ADDR_WIDTH-1:0] line_stride_bytes,

    output logic                  mem_read,
    output logic [ADDR_WIDTH-1:0] mem_address,
    input  logic                  mem_acknowledge,
    input  logic [127:0]          mem_read_data,

    output logic [7:0]            pixel_data,
    output logic                  pixel_valid,
    input  logic                  pixel_ready,
    output logic                  pixel_sof,
    output logic                  pixel_eol,
    output logic                  pixel_eof,

    output logic                  busy,
    output logic                  done,
    output logic                  error
);

    localparam int WORD_INDEX_WIDTH = $clog2(MAX_WORDS_PER_LINE);

    logic [127:0] line_buffer0 [0:MAX_WORDS_PER_LINE-1];
    logic [127:0] line_buffer1 [0:MAX_WORDS_PER_LINE-1];
    logic [1:0]   buffer_full;

    logic                  fetch_active;
    logic                  fetch_buffer;
    logic [WORD_INDEX_WIDTH-1:0] fetch_word;
    logic [ADDR_WIDTH-1:0]       fetch_base;
    logic [15:0]                 next_fetch_row;
    logic [ADDR_WIDTH-1:0]       next_fetch_base;

    logic                  output_active;
    logic                  output_buffer;
    logic [15:0]           output_row;
    logic [15:0]           output_pixel;

    logic [15:0]           width_reg;
    logic [15:0]           height_reg;
    logic [15:0]           words_per_line;
    logic [ADDR_WIDTH-1:0] stride_reg;
    logic [127:0]          output_word;

    assign mem_read = fetch_active;
    assign mem_address = fetch_base + (fetch_word << 4);

    assign pixel_valid = output_active;
    assign pixel_sof = output_active && (output_row == 0) && (output_pixel == 0);
    assign pixel_eol = output_active && (output_pixel == width_reg - 1'b1);
    assign pixel_eof = pixel_eol && (output_row == height_reg - 1'b1);

    always_comb begin
        if (output_buffer) begin
            output_word = line_buffer1[output_pixel[15:4]];
        end else begin
            output_word = line_buffer0[output_pixel[15:4]];
        end
        pixel_data = output_word[(output_pixel[3:0] * 8) +: 8];
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            buffer_full     <= '0;
            fetch_active    <= 1'b0;
            fetch_buffer    <= 1'b0;
            fetch_word      <= '0;
            fetch_base      <= '0;
            next_fetch_row  <= '0;
            next_fetch_base <= '0;
            output_active   <= 1'b0;
            output_buffer   <= 1'b0;
            output_row      <= '0;
            output_pixel    <= '0;
            width_reg       <= '0;
            height_reg      <= '0;
            words_per_line  <= '0;
            stride_reg      <= '0;
            busy            <= 1'b0;
            done            <= 1'b0;
            error           <= 1'b0;
        end else begin
            if (start) begin
                if (busy) begin
                    error <= 1'b1;
                end else if ((image_width == 0) || (image_height == 0) ||
                             (((image_width + 15) >> 4) > MAX_WORDS_PER_LINE)) begin
                    error <= 1'b1;
                end else begin
                    buffer_full     <= '0;
                    fetch_active    <= 1'b1;
                    fetch_buffer    <= 1'b0;
                    fetch_word      <= '0;
                    fetch_base      <= frame_base_addr;
                    next_fetch_row  <= 16'd1;
                    next_fetch_base <= frame_base_addr + line_stride_bytes;
                    output_active   <= 1'b0;
                    output_buffer   <= 1'b0;
                    output_row      <= '0;
                    output_pixel    <= '0;
                    width_reg       <= image_width;
                    height_reg      <= image_height;
                    words_per_line  <= (image_width + 15) >> 4;
                    stride_reg      <= line_stride_bytes;
                    busy            <= 1'b1;
                    done            <= 1'b0;
                    error           <= 1'b0;
                end
            end else if (busy) begin

                if (fetch_active && mem_acknowledge) begin
                    if (fetch_buffer) begin
                        line_buffer1[fetch_word] <= mem_read_data;
                    end else begin
                        line_buffer0[fetch_word] <= mem_read_data;
                    end

                    if (fetch_word == words_per_line - 1'b1) begin
                        buffer_full[fetch_buffer] <= 1'b1;
                        fetch_active <= 1'b0;
                    end else begin
                        fetch_word <= fetch_word + 1'b1;
                    end
                end

                if (!output_active) begin
                    if (buffer_full[0]) begin
                        output_active <= 1'b1;
                        output_buffer <= 1'b0;
                        output_pixel  <= '0;
                    end else if (buffer_full[1]) begin
                        output_active <= 1'b1;
                        output_buffer <= 1'b1;
                        output_pixel  <= '0;
                    end
                end else if (pixel_ready) begin
                    if (output_pixel == width_reg - 1'b1) begin
                        buffer_full[output_buffer] <= 1'b0;
                        output_pixel <= '0;
                        output_active <= 1'b0;
                        if (output_row == height_reg - 1'b1) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            output_row <= output_row + 1'b1;
                        end
                    end else begin
                        output_pixel <= output_pixel + 1'b1;
                    end
                end

                if (!fetch_active && (next_fetch_row < height_reg)) begin
                    if (!buffer_full[0] && (!output_active || output_buffer)) begin
                        fetch_active    <= 1'b1;
                        fetch_buffer    <= 1'b0;
                        fetch_word      <= '0;
                        fetch_base      <= next_fetch_base;
                        next_fetch_base <= next_fetch_base + stride_reg;
                        next_fetch_row  <= next_fetch_row + 1'b1;
                    end else if (!buffer_full[1] && (!output_active || !output_buffer)) begin
                        fetch_active    <= 1'b1;
                        fetch_buffer    <= 1'b1;
                        fetch_word      <= '0;
                        fetch_base      <= next_fetch_base;
                        next_fetch_base <= next_fetch_base + stride_reg;
                        next_fetch_row  <= next_fetch_row + 1'b1;
                    end
                end
            end
        end
    end

endmodule
