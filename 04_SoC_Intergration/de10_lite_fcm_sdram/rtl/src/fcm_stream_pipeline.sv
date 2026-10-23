// File: fcm_stream_pipeline.sv
// Description: Builds the image histogram and sends it to the FCM clustering core.
// Author: Phan Chau Phong

// Module: fcm_stream_pipeline
// Description: Collects pixels, sets the initial cluster centers, and manages the core run.
// Uses the FCM precision profile with unsigned Q8.12 cluster centers.
// The stream pipeline handles the histogram and starting centers while the core
// handles the clustering calculations.

module fcm_stream_pipeline import fcm_pkg::*; (
    input  logic                       clk_i,
    input  logic                       rst_n_i,
    input  logic                       start_i,
    input  logic [NUMC_W-1:0]          num_clusters_i,

    output logic                       stream_start_o,
    input  logic [7:0]                 pixel_data_i,
    input  logic                       pixel_valid_i,
    output logic                       pixel_ready_o,
    input  logic                       pixel_eof_i,

    output logic [7:0]                 centroids_o [0:MAX_CLUSTERS-1],
    output logic [NUMC_W-1:0]          active_num_clusters_o,
    output logic                       busy_o,
    output logic                       done_o,
    output logic                       error_o,
    // Shows core contract errors such as invalid cluster counts or divider errors.
    // A contract error means the clustering result may not be reliable.
    output logic                       contract_error_o,
    output logic [3:0]                 stage_o
);
    // Use enough address bits to count the pixels in one image.
    localparam int PX_ADDR = $clog2(IMG_PIXELS);

    typedef enum logic [3:0] {
        P_IDLE         = 4'd0,
        P_CLEAR_HIST   = 4'd1,
        P_STREAM_START = 4'd2,
        P_STREAM       = 4'd3,
        P_LOAD_HIST    = 4'd4,
        P_INIT_START   = 4'd5,
        P_INIT_WAIT    = 4'd6,
        P_INIT_NEXT    = 4'd7,
        P_CORE_START   = 4'd8,
        P_CORE_WAIT    = 4'd9,
        P_DONE         = 4'd10,
        P_ERROR        = 4'd11
    } state_t;

    state_t state_q;
    logic [COUNT_W-1:0] histogram [0:GRAY_BINS-1];
    logic [7:0] clear_index_q;
    logic [7:0] load_index_q;
    logic [PX_ADDR-1:0] pixel_count_q;
    logic [NUMC_W-1:0] active_numc_q;

    logic                       core_start_q;
    logic                       core_done;
    logic                       core_contract_error;
    logic [7:0]                 core_hist_addr;
    logic [COUNT_W-1:0]         core_hist_data;
    logic                       core_hist_we;
    logic [7:0]                 core_lut_addr;
    logic [LABEL_W-1:0]         core_lut_data;
    center_t                    init_centers_q [0:MAX_CLUSTERS-1];
    center_t                    centers_q [0:MAX_CLUSTERS-1];
    logic                       converged_unused;
    logic [ITER_W-1:0]          iter_unused;

    logic [LABEL_W-1:0] init_center_index_q;
    logic               init_div_start_q;
    logic [11:0]        init_div_num;
    logic [4:0]         init_div_den;
    logic [11:0]        init_div_quot;
    logic [4:0]         init_div_rem_unused;
    logic               init_div_done;
    logic               init_div_zero;
    logic               init_div_ovf;
    integer i;

    // Spread the starting centers across the grayscale range.
    // Center i is floor((i + 1) * 255 / (k + 1)), using integer division.
    always_comb begin
        init_div_num = 12'(init_center_index_q + 1'b1) * 12'd255;
        init_div_den = 5'(active_numc_q) + 1'b1;
    end

    fcm_divider #(.NUM_W(12), .DEN_W(5), .QUOT_W(12)) initial_center_divider (
        .clk(clk_i), .rst_n(rst_n_i), .start(init_div_start_q),
        .numerator(init_div_num), .denominator(init_div_den),
        .quotient(init_div_quot), .remainder(init_div_rem_unused),
        .busy(), .done(init_div_done),
        .div_by_zero(init_div_zero), .overflow(init_div_ovf)
    );

    assign core_hist_we   = (state_q == P_LOAD_HIST);
    assign core_hist_addr = load_index_q;
    assign core_hist_data = histogram[load_index_q];

    assign core_lut_addr  = pixel_data_i;

    fcm_core core (
        .clk(clk_i), .rst_n(rst_n_i), .start(core_start_q),
        .num_clusters(active_numc_q),
        .hist_wr_addr(core_hist_addr), .hist_wr_data(core_hist_data),
        .hist_wr_en(core_hist_we), .init_centers_q(init_centers_q),
        .labels_lut_addr(core_lut_addr), .labels_lut_data(core_lut_data),
        .centers_q(centers_q), .converged(converged_unused),
        .iter_converged(iter_unused), .busy(), .done(core_done),
        .contract_error(core_contract_error)
    );

    // Convert unsigned fixed-point centers to 8-bit grayscale values.
    // Round to the nearest integer and limit any value above 255.
    always_comb begin : centroid_conversion
        logic [CENTER_W:0] rounded_center;
        logic [CENTER_W-CENTER_FRAC:0] integer_center;
        for (i = 0; i < MAX_CLUSTERS; i = i + 1) begin
            rounded_center = (CENTER_W+1)'(centers_q[i]) +
                             (CENTER_W+1)'(1 << (CENTER_FRAC-1));
            integer_center = (CENTER_W-CENTER_FRAC+1)'(rounded_center >> CENTER_FRAC);
            if (integer_center > 255)
                centroids_o[i] = 8'd255;
            else
                centroids_o[i] = integer_center[7:0];
        end
    end

    assign stream_start_o          = (state_q == P_STREAM_START) || (state_q == P_STREAM);
    assign pixel_ready_o           = (state_q == P_STREAM_START) || (state_q == P_STREAM);
    assign active_num_clusters_o   = active_numc_q;
    assign busy_o                   = (state_q != P_IDLE) && (state_q != P_DONE) &&
                                      (state_q != P_ERROR);
    assign done_o                   = (state_q == P_DONE);
    assign stage_o                  = state_q;

    always_ff @(posedge clk_i) begin
        if (state_q == P_CLEAR_HIST)
            histogram[clear_index_q] <= '0;
        else if ((state_q == P_STREAM) && pixel_valid_i && pixel_ready_o)
            histogram[pixel_data_i] <= histogram[pixel_data_i] + 1'b1;
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        integer k;
        if (!rst_n_i) begin
            state_q             <= P_IDLE;
            clear_index_q       <= '0;
            load_index_q        <= '0;
            pixel_count_q       <= '0;
            active_numc_q       <= NUMC_W'(3);
            init_center_index_q <= '0;
            init_div_start_q    <= 1'b0;
            core_start_q        <= 1'b0;
            error_o              <= 1'b0;
            contract_error_o     <= 1'b0;
            for (k = 0; k < MAX_CLUSTERS; k = k + 1)
                init_centers_q[k] <= '0;
        end else begin
            init_div_start_q <= 1'b0;
            core_start_q     <= 1'b0;

            // Keep core and divider contract errors visible after processing.
            if (core_contract_error || (init_div_done && (init_div_zero || init_div_ovf)))
                contract_error_o <= 1'b1;

            case (state_q)
                P_IDLE, P_DONE: begin
                    error_o <= 1'b0;
                    if (start_i) begin
                        if (num_clusters_i < NUMC_W'(MIN_CLUSTERS))
                            active_numc_q <= NUMC_W'(MIN_CLUSTERS);
                        else if (num_clusters_i > NUMC_W'(MAX_CLUSTERS))
                            active_numc_q <= NUMC_W'(MAX_CLUSTERS);
                        else
                            active_numc_q <= num_clusters_i;
                        clear_index_q    <= '0;
                        pixel_count_q    <= '0;
                        contract_error_o <= 1'b0;
                        for (k = 0; k < MAX_CLUSTERS; k = k + 1)
                            init_centers_q[k] <= '0;
                        state_q <= P_CLEAR_HIST;
                    end
                end

                P_CLEAR_HIST: begin
                    if (clear_index_q == 8'hff)
                        state_q <= P_STREAM_START;
                    else
                        clear_index_q <= clear_index_q + 1'b1;
                end

                P_STREAM_START: state_q <= P_STREAM;

                P_STREAM: begin
                    if (pixel_valid_i && pixel_ready_o) begin
                        if (pixel_eof_i) begin

                            if (pixel_count_q == PX_ADDR'(IMG_PIXELS-1)) begin
                                load_index_q <= '0;
                                state_q      <= P_LOAD_HIST;
                            end else begin
                                error_o <= 1'b1;
                                state_q <= P_ERROR;
                            end
                        end else if (pixel_count_q == PX_ADDR'(IMG_PIXELS-1)) begin

                            error_o <= 1'b1;
                            state_q <= P_ERROR;
                        end else begin
                            pixel_count_q <= pixel_count_q + 1'b1;
                        end
                    end
                end

                P_LOAD_HIST: begin
                    if (load_index_q == 8'hff) begin
                        init_center_index_q <= '0;
                        state_q             <= P_INIT_START;
                    end else begin
                        load_index_q <= load_index_q + 1'b1;
                    end
                end

                P_INIT_START: begin
                    init_div_start_q <= 1'b1;
                    state_q          <= P_INIT_WAIT;
                end

                P_INIT_WAIT: begin
                    if (init_div_done) begin
                        init_centers_q[init_center_index_q] <=
                            CENTER_W'(init_div_quot) << CENTER_FRAC;
                        state_q <= P_INIT_NEXT;
                    end
                end

                P_INIT_NEXT: begin
                    if (init_center_index_q == LABEL_W'(active_numc_q - 1'b1))
                        state_q <= P_CORE_START;
                    else begin
                        init_center_index_q <= init_center_index_q + 1'b1;
                        state_q <= P_INIT_START;
                    end
                end

                P_CORE_START: begin
                    core_start_q <= 1'b1;
                    state_q      <= P_CORE_WAIT;
                end

                P_CORE_WAIT: begin
                    if (core_done)
                        state_q <= P_DONE;
                end

                P_ERROR: begin

                    if (start_i) begin
                        clear_index_q <= '0;
                        pixel_count_q <= '0;
                        error_o       <= 1'b0;
                        state_q       <= P_CLEAR_HIST;
                    end
                end

                default: begin
                    error_o <= 1'b1;
                    state_q <= P_ERROR;
                end
            endcase
        end
    end
endmodule
