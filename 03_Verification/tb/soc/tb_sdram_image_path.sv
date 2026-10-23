// File: tb_sdram_image_path.sv
// Description: Checks image writes and reads through the SDRAM path.

// Author: Phan Chau Phong

`timescale 1ns/1ps

// Module: tb_sdram_image_path
// Description: Checks image writes and reads through the SDRAM path.
module tb_sdram_image_path;
    localparam int WIDTH  = 450;
    localparam int HEIGHT = 450;
    localparam int PIXELS = WIDTH * HEIGHT;
    localparam int WORDS  = PIXELS / 2;
    localparam int BURST  = 256;
    localparam int PADDED_WORDS = ((WORDS + BURST - 1) / BURST) * BURST;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic stream_rst_n = 1'b0;
    logic upload_start = 1'b0;
    logic [7:0] upload_pixel = '0;
    logic upload_valid = 1'b0;
    logic upload_ready;
    logic image_loaded;
    logic upload_busy;
    logic upload_error;
    logic stream_start = 1'b0;
    logic [7:0] pixel_data;
    logic pixel_valid;
    logic pixel_ready = 1'b0;
    logic pixel_sof;
    logic pixel_eol;
    logic pixel_eof;
    logic stream_busy;
    logic stream_done;
    logic stream_error;

    logic [15:0] write_data;
    logic write_valid;
    logic [24:0] write_start_word_addr;
    logic [24:0] write_max_word_addr;
    logic [8:0] write_burst_words;
    logic write_load;
    logic write_enable;
    logic write_full = 1'b0;
    logic [15:0] write_used_words = '0;
    logic read_pop;
    logic [24:0] read_start_word_addr;
    logic [24:0] read_max_word_addr;
    logic [8:0] read_burst_words;
    logic read_load;
    logic read_enable;
    logic [15:0] read_data = '0;
    logic read_empty;

    logic [7:0] ref_mem [0:PIXELS-1];
    logic [15:0] sdram_words [0:PADDED_WORDS-1];
    integer words_written = 0;
    integer words_read = 0;
    integer pixels_seen = 0;
    integer cycle_count = 0;

    sdram_image_path dut (
        .clk_i(clk), .rst_n_i(rst_n), .stream_rst_n_i(stream_rst_n),
        .upload_start_i(upload_start), .upload_pixel_i(upload_pixel),
        .upload_valid_i(upload_valid), .upload_ready_o(upload_ready),
        .image_loaded_o(image_loaded), .upload_busy_o(upload_busy), .upload_error_o(upload_error),
        .stream_start_i(stream_start), .pixel_data_o(pixel_data), .pixel_valid_o(pixel_valid),
        .pixel_ready_i(pixel_ready), .pixel_sof_o(pixel_sof), .pixel_eol_o(pixel_eol),
        .pixel_eof_o(pixel_eof), .stream_busy_o(stream_busy), .stream_done_o(stream_done),
        .stream_error_o(stream_error), .write_data_o(write_data), .write_valid_o(write_valid),
        .write_start_word_addr_o(write_start_word_addr), .write_max_word_addr_o(write_max_word_addr),
        .write_burst_words_o(write_burst_words), .write_load_o(write_load), .write_enable_o(write_enable),
        .write_full_i(write_full), .write_used_words_i(write_used_words), .read_pop_o(read_pop),
        .read_start_word_addr_o(read_start_word_addr), .read_max_word_addr_o(read_max_word_addr),
        .read_burst_words_o(read_burst_words), .read_load_o(read_load), .read_enable_o(read_enable),
        .read_data_i(read_data), .read_empty_i(read_empty)
    );

    always #5 clk = ~clk;
    assign read_empty = (words_read >= PADDED_WORDS);

    always_ff @(posedge clk) begin
        if (write_valid) begin
            if (words_written >= PADDED_WORDS)
                $fatal(1, "writer exceeded padded SDRAM allocation");
            sdram_words[words_written] <= write_data;
            words_written <= words_written + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (read_pop) begin
            if (read_empty)
                $fatal(1, "reader popped an empty FIFO");
            read_data <= sdram_words[words_read];
            words_read <= words_read + 1;
        end
    end

    always_ff @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        pixel_ready <= (cycle_count % 7) != 3;
        if (pixel_valid && pixel_ready) begin
            if (pixel_data !== ref_mem[pixels_seen])
                $fatal(1, "pixel %0d mismatch: expected %02h got %02h",
                       pixels_seen, ref_mem[pixels_seen], pixel_data);
            if (pixel_sof !== (pixels_seen == 0))
                $fatal(1, "incorrect SOF at pixel %0d", pixels_seen);
            if (pixel_eol !== ((pixels_seen % WIDTH) == WIDTH - 1))
                $fatal(1, "incorrect EOL at pixel %0d", pixels_seen);
            if (pixel_eof !== (pixels_seen == PIXELS - 1))
                $fatal(1, "incorrect EOF at pixel %0d", pixels_seen);
            pixels_seen <= pixels_seen + 1;
        end
    end

    initial begin : stimulus
        integer i;
        // Read the source image from the reference vector directory.
        // Do not use the old fixture image, which has a different histogram.
        $readmemh("../../03_Verification/vectors/precision/demo_k07/pixels_u8.mem", ref_mem);
        for (i = 0; i < PADDED_WORDS; i = i + 1)
            sdram_words[i] = 16'hxxxx;

        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        stream_rst_n <= 1'b1;

        @(negedge clk);
        stream_start <= 1'b1;
        @(negedge clk);
        stream_start <= 1'b0;
        @(posedge clk);
        if (!stream_error || stream_busy || stream_done)
            $fatal(1, "uncommitted image start was not rejected");

        @(negedge clk);
        upload_start <= 1'b1;
        @(negedge clk);
        upload_start <= 1'b0;

        for (i = 0; i < PIXELS; i = i + 1) begin
            upload_pixel <= ref_mem[i];
            upload_valid <= 1'b1;
            do @(posedge clk); while (!upload_ready);
        end
        @(negedge clk);
        upload_valid <= 1'b0;

        wait (image_loaded);
        if (upload_error)
            $fatal(1, "unexpected upload error");
        if (words_written != PADDED_WORDS)
            $fatal(1, "expected %0d SDRAM words, wrote %0d", PADDED_WORDS, words_written);
        for (i = 0; i < WORDS; i = i + 1) begin
            if (sdram_words[i] !== {ref_mem[2*i+1], ref_mem[2*i]})
                $fatal(1, "SDRAM word %0d packing mismatch", i);
        end
        for (i = WORDS; i < PADDED_WORDS; i = i + 1) begin
            if (sdram_words[i] !== 16'h0000)
                $fatal(1, "SDRAM padding word %0d is not zero", i);
        end
        if ((write_start_word_addr != 0) || (write_max_word_addr != PADDED_WORDS) ||
            (write_burst_words != BURST))
            $fatal(1, "incorrect write range configuration");

        @(negedge clk);
        stream_start <= 1'b1;
        @(negedge clk);
        stream_start <= 1'b0;
        wait (stream_done);
        @(posedge clk);
        if (stream_error)
            $fatal(1, "unexpected stream error");
        if (pixels_seen != PIXELS)
            $fatal(1, "expected %0d grayscale bytes, saw %0d", PIXELS, pixels_seen);
        if ((read_start_word_addr != 0) || (read_max_word_addr != PADDED_WORDS) ||
            (read_burst_words != BURST))
            $fatal(1, "incorrect read range configuration");
        $display("PASS: 450x450 .mem image transferred through SDRAM image path (%0d words)", words_written);
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "simulation timeout");
    end
endmodule
