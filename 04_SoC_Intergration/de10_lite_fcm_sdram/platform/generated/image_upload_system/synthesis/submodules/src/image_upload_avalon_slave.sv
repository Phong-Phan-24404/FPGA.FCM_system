// JTAG-Avalon-visible control and data ingress for sdram_image_path.
//
// Word address 0: write four grayscale bytes in little-endian byte order.
// Word address 1: control, bit 0 = begin a new upload, bit 1 = start stream.
// Word address 2: status, bit 0 loaded, 1 upload busy, 2 stream busy,
//                 3 stream done, 4 upload error, 5 stream error,
//                 6 input byte pending, 7 upload ready, 8 protocol error,
//                 9 streamed-image rolling parity.
module image_upload_avalon_slave (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [2:0]  avs_address,
    input  logic        avs_read,
    input  logic        avs_write,
    input  logic [31:0] avs_writedata,
    input  logic [3:0]  avs_byteenable,
    output logic [31:0] avs_readdata,
    output logic        avs_waitrequest,

    output logic        upload_start_o,
    output logic [7:0]  upload_pixel_o,
    output logic        upload_valid_o,
    input  logic        upload_ready_i,
    input  logic        image_loaded_i,
    input  logic        upload_busy_i,
    input  logic        upload_error_i,

    output logic        stream_start_o,
    input  logic        stream_busy_i,
    input  logic        stream_done_i,
    input  logic        stream_error_i,
    input  logic        stream_parity_i
);
    localparam logic [2:0] DATA_ADDR    = 3'd0;
    localparam logic [2:0] CONTROL_ADDR = 3'd1;
    localparam logic [2:0] STATUS_ADDR  = 3'd2;

    logic [31:0] pending_bytes_q;
    logic [2:0]  pending_count_q;
    logic        protocol_error_q;

    assign upload_valid_o = (pending_count_q != 0);
    assign upload_pixel_o = pending_bytes_q[7:0];

    // DATA writes are accepted only when the previous word has fully crossed
    // into the image store.  This keeps the bridge lossless without a BRAM.
    always_comb begin
        avs_waitrequest = (pending_count_q != 0);
        if ((avs_address == DATA_ADDR) && avs_write && !upload_ready_i)
            avs_waitrequest = 1'b1;

        avs_readdata = 32'h0000_0000;
        if (avs_read && (avs_address == STATUS_ADDR)) begin
            avs_readdata[0] = image_loaded_i;
            avs_readdata[1] = upload_busy_i;
            avs_readdata[2] = stream_busy_i;
            avs_readdata[3] = stream_done_i;
            avs_readdata[4] = upload_error_i;
            avs_readdata[5] = stream_error_i;
            avs_readdata[6] = (pending_count_q != 0);
            avs_readdata[7] = upload_ready_i;
            avs_readdata[8] = protocol_error_q;
            avs_readdata[9] = stream_parity_i;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pending_bytes_q <= '0;
            pending_count_q <= '0;
            protocol_error_q <= 1'b0;
            upload_start_o <= 1'b0;
            stream_start_o <= 1'b0;
        end else begin
            upload_start_o <= 1'b0;
            stream_start_o <= 1'b0;

            if (upload_valid_o && upload_ready_i) begin
                pending_bytes_q <= {8'h00, pending_bytes_q[31:8]};
                pending_count_q <= pending_count_q - 1'b1;
            end

            if (avs_write && !avs_waitrequest) begin
                case (avs_address)
                    DATA_ADDR: begin
                        if (avs_byteenable == 4'hf) begin
                            pending_bytes_q <= avs_writedata;
                            pending_count_q <= 3'd4;
                        end else begin
                            protocol_error_q <= 1'b1;
                        end
                    end
                    CONTROL_ADDR: begin
                        upload_start_o <= avs_writedata[0];
                        stream_start_o <= avs_writedata[1];
                        if (avs_writedata[2])
                            protocol_error_q <= 1'b0;
                    end
                    default: protocol_error_q <= 1'b1;
                endcase
            end
        end
    end
endmodule
