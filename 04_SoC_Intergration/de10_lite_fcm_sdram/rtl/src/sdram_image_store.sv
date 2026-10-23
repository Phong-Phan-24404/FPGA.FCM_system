// File: sdram_image_store.sv
// Description: Writes uploaded image pixels into SDRAM.
// Author: Phan Chau Phong

// Module: sdram_image_store
// Description: Packs grayscale pixels into SDRAM words and manages frame loading.

module sdram_image_store #(
    parameter int FRAME_WIDTH       = 450,
    parameter int FRAME_HEIGHT      = 450,
    parameter int BURST_WORDS       = 256,
    parameter int DRAIN_GUARD_CYCLES = 1024,
    parameter logic [24:0] BASE_WORD_ADDR = 25'd0
) (
    input  logic        clk_i,
    input  logic        rst_n_i,

    input  logic        upload_start_i,
    input  logic [7:0]  upload_pixel_i,
    input  logic        upload_valid_i,
    output logic        upload_ready_o,

    output logic [15:0] write_data_o,
    output logic        write_valid_o,
    output logic [24:0] write_start_word_addr_o,
    output logic [24:0] write_max_word_addr_o,
    output logic [8:0]  write_burst_words_o,
    output logic        write_load_o,
    output logic        write_enable_o,
    input  logic        write_full_i,
    input  logic [15:0] write_used_words_i,

    output logic        busy_o,
    output logic        image_committed_o,
    output logic        error_o
);
    localparam int FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int IMAGE_WORDS  = (FRAME_PIXELS + 1) / 2;
    localparam int PADDED_WORDS = ((IMAGE_WORDS + BURST_WORDS - 1) / BURST_WORDS) * BURST_WORDS;
    localparam int DRAIN_COUNT_W = $clog2(DRAIN_GUARD_CYCLES + 1);

    typedef enum logic [2:0] {IDLE, LOAD, UPLOAD, PAD, DRAIN, DONE} state_t;
    state_t state_q;
    logic [7:0] low_pixel_q;
    logic       low_pixel_valid_q;
    logic [24:0] pixel_count_q;
    logic [24:0] word_count_q;
    logic [DRAIN_COUNT_W-1:0] drain_count_q;

    initial begin
        if ((FRAME_PIXELS & 1) != 0)
            $error("sdram_image_store requires an even pixel count");
        if ((BURST_WORDS < 1) || (BURST_WORDS > 512))
            $error("sdram_image_store BURST_WORDS must be in 1..512");
    end

    assign write_start_word_addr_o = BASE_WORD_ADDR;
    assign write_max_word_addr_o   = BASE_WORD_ADDR + PADDED_WORDS;
    assign write_burst_words_o     = BURST_WORDS[8:0];
    assign write_load_o            = (state_q == LOAD);
    assign write_enable_o          = (state_q == UPLOAD) || (state_q == PAD) || (state_q == DRAIN);
    assign busy_o                  = (state_q != IDLE) && (state_q != DONE);
    assign image_committed_o       = (state_q == DONE);

    assign upload_ready_o = (state_q == UPLOAD) &&
                            (!low_pixel_valid_q || !write_full_i);
    assign write_valid_o  = (state_q == UPLOAD) ?
                            (upload_valid_i && upload_ready_o && low_pixel_valid_q) :
                            ((state_q == PAD) && !write_full_i);
    assign write_data_o   = (state_q == UPLOAD) ? {upload_pixel_i, low_pixel_q} : 16'h0000;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_q           <= IDLE;
            low_pixel_q       <= '0;
            low_pixel_valid_q <= 1'b0;
            pixel_count_q     <= '0;
            word_count_q      <= '0;
            drain_count_q     <= '0;
            error_o           <= 1'b0;
        end else begin
            case (state_q)
                IDLE, DONE: begin
                    if (upload_start_i) begin
                        state_q           <= LOAD;
                        low_pixel_valid_q <= 1'b0;
                        pixel_count_q     <= '0;
                        word_count_q      <= '0;
                        drain_count_q     <= '0;
                        error_o           <= 1'b0;
                    end
                end

                LOAD: state_q <= UPLOAD;

                UPLOAD: begin
                    if (upload_valid_i && upload_ready_o) begin
                        if (!low_pixel_valid_q) begin
                            low_pixel_q       <= upload_pixel_i;
                            low_pixel_valid_q <= 1'b1;
                        end else begin
                            low_pixel_valid_q <= 1'b0;
                            word_count_q      <= word_count_q + 1'b1;
                        end

                        if (pixel_count_q == FRAME_PIXELS - 1) begin
                            if (!low_pixel_valid_q)
                                error_o <= 1'b1;
                            state_q <= PAD;
                        end
                        pixel_count_q <= pixel_count_q + 1'b1;
                    end
                end

                PAD: begin
                    if (write_valid_o) begin
                        if (word_count_q == PADDED_WORDS - 1) begin
                            word_count_q  <= word_count_q + 1'b1;
                            drain_count_q <= '0;
                            state_q       <= DRAIN;
                        end else begin
                            word_count_q <= word_count_q + 1'b1;
                        end
                    end
                end

                DRAIN: begin
                    if (write_used_words_i == 0) begin
                        if (drain_count_q == DRAIN_GUARD_CYCLES - 1)
                            state_q <= DONE;
                        else
                            drain_count_q <= drain_count_q + 1'b1;
                    end else begin
                        drain_count_q <= '0;
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
