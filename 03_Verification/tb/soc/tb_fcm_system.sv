// File: tb_fcm_system.sv
// Description: Checks the full Avalon upload, SDRAM, FCM and board UI path.
// The test starts at the Avalon slave instead of the vendor JTAG bridge.
// The SDRAM client model adds FIFO backpressure but does not model DRAM pins.
// Run tb_fcm_system and use +FCM_CASE_K to select K from 2 to 7.

`timescale 1ns/1ps

module tb_fcm_system;

    import fcm_pkg::*;
    import fcm_vector_pkg::*;
    localparam int WIDTH = 450;
    localparam int HEIGHT = 450;
    localparam int PIXELS = WIDTH * HEIGHT;
    localparam int WORDS = PIXELS / 2;
    localparam int BURST = 256;
    localparam int PADDED_WORDS = 101376;

    logic clk_50 = 1'b0;
    reg clk_fcm_reg = 1'b0;
    int unsigned fcm_clk_half;
    wire clk_fcm = clk_fcm_reg;
    logic rst_n = 1'b0;
    logic key1_n = 1'b1;
    // Read the cluster count from +FCM_CASE_K, defaulting to 7.
    // The board UI reads the binary K value from sw[2:0].
    int unsigned case_k;
    logic [9:0] sw = '0;

    // Hold KEY longer than the board UI debounce limit of 500000 clk_fcm cycles.
    // Otherwise the FCM start signal may never be asserted.
    localparam int KEY_HOLD_CYCLES = 500_010;

    logic [2:0] avs_address = '0;
    logic avs_read = 1'b0;
    logic avs_write = 1'b0;
    logic [31:0] avs_writedata = '0;
    logic [3:0] avs_byteenable = 4'hf;
    logic [31:0] avs_readdata;
    logic avs_waitrequest;

    logic upload_start;
    logic [7:0] upload_pixel;
    logic upload_valid;
    logic upload_ready;
    logic image_loaded;
    logic upload_busy;
    logic upload_error;
    logic host_stream_start;

    logic [7:0] pixel_data;
    logic pixel_valid;
    logic pixel_ready;
    logic pixel_sof;
    logic pixel_eol;
    logic pixel_eof;
    logic stream_busy;
    logic stream_done;
    logic stream_error;
    logic fcm_stream_start;
    logic fcm_busy;
    logic fcm_done;
    logic fcm_error;
    logic [3:0] fcm_stage;
    logic [9:0] ledr;
    logic [7:0] hex0, hex1, hex2, hex3, hex4, hex5;

    logic [15:0] write_data;
    logic write_valid;
    logic [24:0] write_start_word_addr;
    logic [24:0] write_max_word_addr;
    logic [8:0] write_burst_words;
    logic write_load;
    logic write_enable;
    logic write_full;
    logic [15:0] write_used_words;
    logic read_pop;
    logic [24:0] read_start_word_addr;
    logic [24:0] read_max_word_addr;
    logic [8:0] read_burst_words;
    logic read_load;
    logic read_enable;
    logic [15:0] read_data;
    logic read_empty;
    logic [15:0] read_used_words;

    logic [7:0] reference_pixels [0:PIXELS-1];
    logic [15:0] sdram_words [0:PADDED_WORDS-1];
    logic [17:0] golden_histogram [0:255];
    logic signed [31:0] golden_centers_q [0:MAX_CLUSTERS-1];

    logic [15:0] write_fifo [0:63];
    logic [15:0] read_fifo [0:63];
    integer write_wr_ptr, write_rd_ptr, write_fifo_count, write_sdram_addr;
    integer read_wr_ptr, read_rd_ptr, read_fifo_count, read_sdram_addr;
    integer cycle_count;
    integer words_committed;
    integer pixels_seen;
    integer fcm_pixels_seen;
    time fcm_busy_start_ns;
    time fcm_done_ns;

    wire write_push = write_valid && !write_full;
    wire write_drain = write_enable && (write_fifo_count != 0) && ((cycle_count % 3) != 1);
    wire read_fill = read_enable && (read_sdram_addr < read_max_word_addr) &&
                     (read_fifo_count < 48) && ((cycle_count % 5) != 2);
    wire read_take = read_pop && !read_empty;

    assign write_full = (write_fifo_count >= 48) || ((cycle_count % 97) == 13);
    assign write_used_words = write_fifo_count;
    assign read_empty = (read_fifo_count == 0);
    assign read_used_words = read_fifo_count;

    always #10 clk_50 = ~clk_50;
    // Use a 50 MHz FCM clock by default, matching the board PLL setting.
    // +FCM_CLK_HALF=20 also tests the older 25 MHz setting and a 2:1 clock ratio.
    initial begin
      if (!$value$plusargs("FCM_CLK_HALF=%d", fcm_clk_half)) fcm_clk_half = 10;
      forever #(fcm_clk_half) clk_fcm_reg = ~clk_fcm_reg;
    end

    image_upload_avalon_slave jtag_avalon_endpoint (
        .clk(clk_50), .reset_n(rst_n), .avs_address, .avs_read, .avs_write,
        .avs_writedata, .avs_byteenable, .avs_readdata, .avs_waitrequest,
        .upload_start_o(upload_start), .upload_pixel_o(upload_pixel),
        .upload_valid_o(upload_valid), .upload_ready_i(upload_ready),
        .image_loaded_i(image_loaded), .upload_busy_i(upload_busy),
        .upload_error_i(upload_error), .stream_start_o(host_stream_start),
        .stream_busy_i(stream_busy), .stream_done_i(stream_done),
        .stream_error_i(stream_error), .stream_parity_i(1'b0)
    );

    sdram_image_path image_path (
        .clk_i(clk_50), .rst_n_i(rst_n), .stream_rst_n_i(rst_n),
        .upload_start_i(upload_start), .upload_pixel_i(upload_pixel),
        .upload_valid_i(upload_valid), .upload_ready_o(upload_ready),
        .image_loaded_o(image_loaded), .upload_busy_o(upload_busy), .upload_error_o(upload_error),
        .stream_start_i(fcm_stream_start), .pixel_data_o(pixel_data),
        .pixel_valid_o(pixel_valid), .pixel_ready_i(pixel_ready), .pixel_sof_o(pixel_sof),
        .pixel_eol_o(pixel_eol), .pixel_eof_o(pixel_eof), .stream_busy_o(stream_busy),
        .stream_done_o(stream_done), .stream_error_o(stream_error), .write_data_o(write_data),
        .write_valid_o(write_valid), .write_start_word_addr_o(write_start_word_addr),
        .write_max_word_addr_o(write_max_word_addr), .write_burst_words_o(write_burst_words),
        .write_load_o(write_load), .write_enable_o(write_enable), .write_full_i(write_full),
        .write_used_words_i(write_used_words), .read_pop_o(read_pop),
        .read_start_word_addr_o(read_start_word_addr), .read_max_word_addr_o(read_max_word_addr),
        .read_burst_words_o(read_burst_words), .read_load_o(read_load), .read_enable_o(read_enable),
        .read_data_i(read_data), .read_empty_i(read_empty)
    );

    fcm_de10lite_integration fcm_integration (
        .clk_50_i(clk_50), .clk_fcm_i(clk_fcm), .rst_n_i(rst_n), .key1_n_i(key1_n), .sw_i(sw),
        .image_loaded_i(image_loaded), .upload_error_i(upload_error), .stream_error_i(stream_error),
        .stream_start_o(fcm_stream_start), .pixel_data_i(pixel_data), .pixel_valid_i(pixel_valid),
        .pixel_ready_o(pixel_ready), .pixel_eof_i(pixel_eof), .fcm_busy_o(fcm_busy),
        .fcm_done_o(fcm_done), .fcm_error_o(fcm_error), .fcm_stage_o(fcm_stage), .ledr_o(ledr),
        .hex0_o(hex0), .hex1_o(hex1), .hex2_o(hex2), .hex3_o(hex3), .hex4_o(hex4), .hex5_o(hex5)
    );

    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            write_wr_ptr <= 0; write_rd_ptr <= 0; write_fifo_count <= 0;
            write_sdram_addr <= 0; words_committed <= 0; cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (write_load) begin
                if ((write_start_word_addr != 0) || (write_max_word_addr != PADDED_WORDS) ||
                    (write_burst_words != BURST))
                    $fatal(1, "invalid SDRAM write burst configuration");
                write_sdram_addr <= write_start_word_addr;
            end
            if (write_push) begin
                write_fifo[write_wr_ptr] <= write_data;
                write_wr_ptr <= (write_wr_ptr + 1) % 64;
            end
            if (write_drain) begin
                if (write_sdram_addr >= PADDED_WORDS)
                    $fatal(1, "write model exceeded SDRAM allocation");
                sdram_words[write_sdram_addr] <= write_fifo[write_rd_ptr];
                write_rd_ptr <= (write_rd_ptr + 1) % 64;
                write_sdram_addr <= write_sdram_addr + 1;
                words_committed <= words_committed + 1;
            end
            case ({write_push, write_drain})
                2'b10: write_fifo_count <= write_fifo_count + 1;
                2'b01: write_fifo_count <= write_fifo_count - 1;
                default: write_fifo_count <= write_fifo_count;
            endcase
        end
    end

    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            read_wr_ptr <= 0; read_rd_ptr <= 0; read_fifo_count <= 0;
            read_sdram_addr <= 0; read_data <= '0;
        end else begin
            if (read_load) begin
                if ((read_start_word_addr != 0) || (read_max_word_addr != PADDED_WORDS) ||
                    (read_burst_words != BURST))
                    $fatal(1, "invalid SDRAM read burst configuration");
                read_wr_ptr <= 0; read_rd_ptr <= 0; read_fifo_count <= 0;
                read_sdram_addr <= read_start_word_addr;
            end else begin
                if (read_fill) begin
                    read_fifo[read_wr_ptr] <= sdram_words[read_sdram_addr];
                    read_wr_ptr <= (read_wr_ptr + 1) % 64;
                    read_sdram_addr <= read_sdram_addr + 1;
                end
                if (read_take) begin
                    read_data <= read_fifo[read_rd_ptr];
                    read_rd_ptr <= (read_rd_ptr + 1) % 64;
                end
                case ({read_fill, read_take})
                    2'b10: read_fifo_count <= read_fifo_count + 1;
                    2'b01: read_fifo_count <= read_fifo_count - 1;
                    default: read_fifo_count <= read_fifo_count;
                endcase
            end
        end
    end

    always @(posedge clk_50) begin
        if (rst_n && pixel_valid && pixel_ready) begin
            if (pixel_data !== reference_pixels[pixels_seen])
                $fatal(1, "stream pixel %0d: expected %02h, got %02h", pixels_seen,
                       reference_pixels[pixels_seen], pixel_data);
            if (pixel_sof !== (pixels_seen == 0) ||
                pixel_eol !== ((pixels_seen % WIDTH) == WIDTH-1) ||
                pixel_eof !== (pixels_seen == PIXELS-1))
                $fatal(1, "stream marker mismatch at pixel %0d", pixels_seen);
            pixels_seen <= pixels_seen + 1;
        end
    end

    always @(posedge clk_fcm) begin
        if (rst_n && fcm_integration.fifo_rdreq) begin
            if (fcm_integration.fifo_q[7:0] !== reference_pixels[fcm_pixels_seen] ||
                fcm_integration.fifo_q[8] !== (fcm_pixels_seen == PIXELS-1))
                $fatal(1, "FCM FIFO mismatch at pixel %0d", fcm_pixels_seen);
            fcm_pixels_seen <= fcm_pixels_seen + 1;
        end
    end

    task automatic avalon_write(input logic [2:0] address, input logic [31:0] data,
                                input logic [3:0] byteenable);
        begin
            @(negedge clk_50);
            avs_address <= address;
            avs_writedata <= data;
            avs_byteenable <= byteenable;
            avs_write <= 1'b1;
            do @(posedge clk_50); while (avs_waitrequest);
            @(negedge clk_50);
            avs_write <= 1'b0;
            avs_address <= '0;
            avs_writedata <= '0;
            avs_byteenable <= 4'hf;
        end
    endtask

    function automatic [7:0] golden_center_u8(input logic signed [31:0] center_q);
        logic signed [32:0] rounded;
        logic signed [16:0] integer_center;
        begin
            rounded = center_q + 33'sd2048;      // add half an LSB before rounding
            integer_center = rounded >>> 12;     // convert unsigned Q8.12 to integer
            if (integer_center < 0)
                golden_center_u8 = 8'd0;
            else if (integer_center > 255)
                golden_center_u8 = 8'd255;
            else
                golden_center_u8 = integer_center[7:0];
        end
    endfunction

    string case_dir;

    // Instantiate the Avalon assertion bind module so the checks are active.
    fcm_avalon_sva_bind u_bind_avalon ();
    fcm_cdc_sva_bind    u_bind_cdc ();

    initial begin : test
        integer i;
        // Use pixels from the same vector case as the expected histogram.
        // The old fixture image does not match that histogram.
        case_k = 7;
        void'($value$plusargs("FCM_CASE_K=%d", case_k));
        if (case_k < MIN_CLUSTERS || case_k > MAX_CLUSTERS)
            $fatal(1, "FCM_CASE_K=%0d ngoai dai %0d..%0d", case_k, MIN_CLUSTERS, MAX_CLUSTERS);
        sw[2:0] = case_k[2:0];

        case_dir = fcm_case_dir(fcm_vector_dir(), case_k);
        $display("tb_fcm_system: case %s K=%0d", case_dir, case_k);
        $readmemh({case_dir, "/pixels_u8.mem"},       reference_pixels);
        $readmemh({case_dir, "/hist_counts_u18.mem"}, golden_histogram);
        $readmemh({case_dir, "/golden_centers.mem"},  golden_centers_q);
        pixels_seen = 0;
        fcm_pixels_seen = 0;
        for (i = 0; i < PADDED_WORDS; i = i + 1)
            sdram_words[i] = 16'hxxxx;

        repeat (5) @(posedge clk_50);
        rst_n <= 1'b1;

        avalon_write(3'd1, 32'h0000_0001, 4'hf);

        avalon_write(3'd0, 32'hdead_beef, 4'b0001);
        @(negedge clk_50); avs_address <= 3'd2; avs_read <= 1'b1;
        #1;
        if (!avs_readdata[8]) $fatal(1, "invalid byteenable did not set protocol error");
        @(negedge clk_50); avs_read <= 1'b0;
        avalon_write(3'd1, 32'h0000_0004, 4'hf);

        for (i = 0; i < PIXELS; i = i + 4)
            avalon_write(3'd0, {reference_pixels[i+3], reference_pixels[i+2],
                                reference_pixels[i+1], reference_pixels[i]}, 4'hf);

        wait (image_loaded);
        if (upload_error || (words_committed != PADDED_WORDS))
            $fatal(1, "upload did not commit exactly %0d SDRAM words", PADDED_WORDS);
        for (i = 0; i < WORDS; i = i + 1)
            if (sdram_words[i] !== {reference_pixels[2*i+1], reference_pixels[2*i]})
                $fatal(1, "SDRAM word %0d packing mismatch", i);
        for (i = WORDS; i < PADDED_WORDS; i = i + 1)
            if (sdram_words[i] !== 16'h0000)
                $fatal(1, "SDRAM padding word %0d is not zero", i);

        fork
            begin
                @(posedge fcm_busy);
                fcm_busy_start_ns = $time;
            end
        join_none
        key1_n <= 1'b0;
        repeat (KEY_HOLD_CYCLES) @(posedge clk_fcm);
        key1_n <= 1'b1;
        wait (fcm_done);
        fcm_done_ns = $time;
        @(posedge clk_fcm);

        if (upload_error || stream_error || fcm_error || (pixels_seen != PIXELS) ||
            (fcm_pixels_seen != PIXELS))
            $fatal(1, "system completion has an error or lost stream data");
        for (i = 0; i < 256; i = i + 1)
            if (fcm_integration.fcm_pipeline.histogram[i] !== golden_histogram[i])
                $fatal(1, "FCM histogram bin %0d mismatch", i);
        for (i = 0; i < int'(case_k); i = i + 1)
            if (fcm_integration.final_centroids[i] !== golden_center_u8(golden_centers_q[i]))
                $fatal(1, "FCM centroid %0d mismatch: expected %02h got %02h", i,
                       golden_center_u8(golden_centers_q[i]), fcm_integration.final_centroids[i]);
        if (!ledr[3] || ledr[4])
            $fatal(1, "board UI did not report a clean completed run");
        // Check ledr[5] for contract_error_o even when the output centers match.
        if (ledr[5])
            $fatal(1, "fcm_stream_pipeline bat contract_error");
        if (fcm_busy_start_ns == 0)
            $fatal(1, "FCM busy transition was not observed");
        $display("METRIC: fcm_busy_to_done_ns=%0d", fcm_done_ns - fcm_busy_start_ns);
        $display("PASS tb_fcm_system: K=%0d, %0d pixel, upload+SDRAM+FCM+UI khop reference", case_k, PIXELS);
        $finish;
    end

    initial begin

        #2_000_000_000;
        $display("timeout state: loaded=%0b upload_busy=%0b upload_error=%0b stream_busy=%0b stream_done=%0b stream_error=%0b fcm_busy=%0b fcm_done=%0b fcm_error=%0b stage=%0d pixels_seen=%0d words=%0d", image_loaded, upload_busy, upload_error, stream_busy, stream_done, stream_error, fcm_busy, fcm_done, fcm_error, fcm_stage, pixels_seen, words_committed);
        $fatal(1, "tb_fcm_system timeout");
    end
endmodule
