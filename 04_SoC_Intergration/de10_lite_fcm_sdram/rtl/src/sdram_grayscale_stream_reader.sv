// File: sdram_grayscale_stream_reader.sv
// Description: Reads grayscale image data from SDRAM for the pixel stream.
// Author: Phan Chau Phong

// Module: sdram_grayscale_stream_reader
// Description: Fetches stored pixel words and streams their grayscale values.

module sdram_grayscale_stream_reader #(
    parameter int FRAME_WIDTH  = 450,
    parameter int FRAME_HEIGHT = 450,
    parameter int BURST_WORDS  = 256,
    parameter logic [24:0] BASE_WORD_ADDR = 25'd0
) (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        start_i,
    input  logic        image_committed_i,

    output logic [15:0] read_data_o,
    output logic        read_pop_o,
    output logic [24:0] read_start_word_addr_o,
    output logic [24:0] read_max_word_addr_o,
    output logic [8:0]  read_burst_words_o,
    output logic        read_load_o,
    output logic        read_enable_o,
    input  logic [15:0] read_data_i,
    input  logic        read_empty_i,

    output logic [7:0]  pixel_data_o,
    output logic        pixel_valid_o,
    input  logic        pixel_ready_i,
    output logic        pixel_sof_o,
    output logic        pixel_eol_o,
    output logic        pixel_eof_o,
    output logic        busy_o,
    output logic        done_o,
    output logic        error_o
);
    localparam int FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int IMAGE_WORDS  = (FRAME_PIXELS + 1) / 2;
    localparam int PADDED_WORDS = ((IMAGE_WORDS + BURST_WORDS - 1) / BURST_WORDS) * BURST_WORDS;

    typedef enum logic [1:0] {IDLE, LOAD, STREAM, DONE} state_t;
    state_t state_q;
    logic [15:0] word_q;
    logic        word_valid_q;
    logic        pop_pending_q;
    logic        high_byte_q;
    logic [24:0] pixel_index_q;
    logic [15:0] column_q;

    assign read_start_word_addr_o = BASE_WORD_ADDR;
    assign read_max_word_addr_o   = BASE_WORD_ADDR + PADDED_WORDS;
    assign read_burst_words_o     = BURST_WORDS[8:0];
    assign read_load_o            = (state_q == LOAD);
    assign read_enable_o          = (state_q == STREAM);
    assign busy_o                 = (state_q == LOAD) || (state_q == STREAM);
    assign done_o                 = (state_q == DONE);

    assign read_pop_o    = (state_q == STREAM) && !word_valid_q && !pop_pending_q && !read_empty_i;
    assign read_data_o   = read_data_i;
    assign pixel_valid_o = (state_q == STREAM) && word_valid_q;
    assign pixel_data_o  = high_byte_q ? word_q[15:8] : word_q[7:0];
    assign pixel_sof_o   = pixel_valid_o && (pixel_index_q == 0);
    assign pixel_eol_o   = pixel_valid_o && (column_q == FRAME_WIDTH - 1);
    assign pixel_eof_o   = pixel_valid_o && (pixel_index_q == FRAME_PIXELS - 1);

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_q         <= IDLE;
            word_q          <= '0;
            word_valid_q    <= 1'b0;
            pop_pending_q   <= 1'b0;
            high_byte_q     <= 1'b0;
            pixel_index_q   <= '0;
            column_q        <= '0;
            error_o         <= 1'b0;
        end else begin
            case (state_q)
                IDLE, DONE: begin
                    if (start_i) begin
                        if (image_committed_i) begin
                            state_q       <= LOAD;
                            word_valid_q  <= 1'b0;
                            pop_pending_q <= 1'b0;
                            high_byte_q   <= 1'b0;
                            pixel_index_q <= '0;
                            column_q      <= '0;
                            error_o       <= 1'b0;
                        end else begin
                            error_o <= 1'b1;
                        end
                    end
                end

                LOAD: state_q <= STREAM;

                STREAM: begin
                    if (read_pop_o) begin
                        pop_pending_q <= 1'b1;
                    end else if (pop_pending_q) begin

                        word_q        <= read_data_i;
                        word_valid_q  <= 1'b1;
                        pop_pending_q <= 1'b0;
                    end

                    if (pixel_valid_o && pixel_ready_i) begin
                        if (!high_byte_q) begin
                            high_byte_q <= 1'b1;
                        end else begin
                            high_byte_q  <= 1'b0;
                            word_valid_q <= 1'b0;
                        end

                        if (column_q == FRAME_WIDTH - 1)
                            column_q <= '0;
                        else
                            column_q <= column_q + 1'b1;

                        if (pixel_index_q == FRAME_PIXELS - 1)
                            state_q <= DONE;
                        else
                            pixel_index_q <= pixel_index_q + 1'b1;
                    end
                end

                default: begin
                    state_q <= IDLE;
                    error_o <= 1'b1;
                end
            endcase
        end
    end
endmodule
