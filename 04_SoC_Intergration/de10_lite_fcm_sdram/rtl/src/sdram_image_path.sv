// File: sdram_image_path.sv
// Description: Connects image upload, SDRAM storage, and pixel streaming.
// Author: Phan Chau Phong

// Module: sdram_image_path
// Description: Links the SDRAM writer and reader to the image processing path.

module sdram_image_path #(
    parameter int FRAME_WIDTH  = 450,
    parameter int FRAME_HEIGHT = 450,
    parameter int BURST_WORDS  = 256,
    parameter logic [24:0] BASE_WORD_ADDR = 25'd0
) (
    input  logic        clk_i,
    input  logic        rst_n_i,

    input  logic        stream_rst_n_i,

    input  logic        upload_start_i,
    input  logic [7:0]  upload_pixel_i,
    input  logic        upload_valid_i,
    output logic        upload_ready_o,
    output logic        image_loaded_o,
    output logic        upload_busy_o,
    output logic        upload_error_o,

    input  logic        stream_start_i,
    output logic [7:0]  pixel_data_o,
    output logic        pixel_valid_o,
    input  logic        pixel_ready_i,
    output logic        pixel_sof_o,
    output logic        pixel_eol_o,
    output logic        pixel_eof_o,
    output logic        stream_busy_o,
    output logic        stream_done_o,
    output logic        stream_error_o,

    output logic [15:0] write_data_o,
    output logic        write_valid_o,
    output logic [24:0] write_start_word_addr_o,
    output logic [24:0] write_max_word_addr_o,
    output logic [8:0]  write_burst_words_o,
    output logic        write_load_o,
    output logic        write_enable_o,
    input  logic        write_full_i,
    input  logic [15:0] write_used_words_i,

    output logic        read_pop_o,
    output logic [24:0] read_start_word_addr_o,
    output logic [24:0] read_max_word_addr_o,
    output logic [8:0]  read_burst_words_o,
    output logic        read_load_o,
    output logic        read_enable_o,
    input  logic [15:0] read_data_i,
    input  logic        read_empty_i
);
    sdram_image_store #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .BURST_WORDS(BURST_WORDS), .BASE_WORD_ADDR(BASE_WORD_ADDR)
    ) store (
        .clk_i, .rst_n_i, .upload_start_i, .upload_pixel_i, .upload_valid_i,
        .upload_ready_o, .write_data_o, .write_valid_o, .write_start_word_addr_o,
        .write_max_word_addr_o, .write_burst_words_o, .write_load_o, .write_enable_o,
        .write_full_i, .write_used_words_i, .busy_o(upload_busy_o),
        .image_committed_o(image_loaded_o), .error_o(upload_error_o)
    );

    sdram_grayscale_stream_reader #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .BURST_WORDS(BURST_WORDS), .BASE_WORD_ADDR(BASE_WORD_ADDR)
    ) reader (
        .clk_i, .rst_n_i(stream_rst_n_i), .start_i(stream_start_i), .image_committed_i(image_loaded_o),
        .read_data_o(), .read_pop_o, .read_start_word_addr_o, .read_max_word_addr_o,
        .read_burst_words_o, .read_load_o, .read_enable_o, .read_data_i, .read_empty_i,
        .pixel_data_o, .pixel_valid_o, .pixel_ready_i, .pixel_sof_o, .pixel_eol_o,
        .pixel_eof_o, .busy_o(stream_busy_o), .done_o(stream_done_o), .error_o(stream_error_o)
    );
endmodule
