// File: fcm_core.sv
// Description: Connects the histogram memory, FCM engine, and label lookup table.
// Author: Phan Chau Phong
// Module: fcm_core
// Description: Runs the FCM algorithm using histogram data provided by the host.
// The host writes 256 histogram bins and provides the starting centers.
// The engine updates the centers, then builds a label table for gray values.
// The done signal indicates that the results are ready to read.

module fcm_core import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic [NUMC_W-1:0]     num_clusters,

    // Write the histogram values from the host.
    input  logic [GRAY_W-1:0]     hist_wr_addr,
    input  logic [COUNT_W-1:0]    hist_wr_data,
    input  logic                  hist_wr_en,

    // Starting centers in Q8.F format.
    // The host uses (i + 1) * 255 / (k + 1), rounded down, then shifts by F.
    input  center_t               init_centers_q [0:MAX_C-1],

    // Read the label table after the calculation finishes.
    input  logic [GRAY_W-1:0]     labels_lut_addr,
    output logic [LABEL_W-1:0]    labels_lut_data,

    output center_t               centers_q [0:MAX_C-1],
    output logic                  converged,
    output logic [ITER_W-1:0]     iter_converged,
    output logic                  busy,
    output logic                  done,
    output logic                  contract_error
);

    typedef enum logic [1:0] {C_IDLE, C_ENGINE, C_LUT, C_DONE} state_t;
    state_t state;

    logic [NUMC_W-1:0] k_active;

    // Histogram memory uses a one-cycle synchronous read.
    // The engine sets the address first and reads the value on the next cycle.
    logic [COUNT_W-1:0] histogram [0:GRAY_BINS-1];
    logic [GRAY_W-1:0]  hist_rd_addr;
    logic [COUNT_W-1:0] hist_rd_data;

    always_ff @(posedge clk) begin
        if (hist_wr_en && (state == C_IDLE) && !start)
            histogram[hist_wr_addr] <= hist_wr_data;
        hist_rd_data <= histogram[hist_rd_addr];
    end

    // Store and read the final label table.
    logic [LABEL_W-1:0] label_mem [0:GRAY_BINS-1];
    logic               lut_wr_en;
    logic [GRAY_W-1:0]  lut_wr_addr;
    logic [LABEL_W-1:0] lut_wr_data;

    always_ff @(posedge clk) begin
        if (lut_wr_en) label_mem[lut_wr_addr] <= lut_wr_data;
        labels_lut_data <= label_mem[labels_lut_addr];
    end

    // Connect the iterative FCM engine.
    logic engine_start, engine_done, engine_error;

    fcm_core_engine #(.MAX_C(MAX_C)) u_engine (
        .clk(clk), .rst_n(rst_n),
        .start(engine_start),
        .num_clusters(k_active),
        .init_centers_q(init_centers_q),
        .hist_rd_addr(hist_rd_addr),
        .hist_rd_data(hist_rd_data),
        .centers_q(centers_q),
        .converged(converged),
        .iter_converged(iter_converged),
        .busy(), .done(engine_done),
        .contract_error(engine_error)
    );

    logic lut_start, lut_done;

    fcm_label_lut #(.MAX_C(MAX_C)) u_lut (
        .clk(clk), .rst_n(rst_n),
        .start(lut_start),
        .num_clusters(k_active),
        .centers_q(centers_q),
        .wr_en(lut_wr_en),
        .wr_addr(lut_wr_addr),
        .wr_data(lut_wr_data),
        .busy(), .done(lut_done)
    );

    assign busy = (state != C_IDLE);
    assign done = (state == C_DONE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= C_IDLE;
            k_active       <= NUMC_W'(MIN_CLUSTERS);
            engine_start   <= 1'b0;
            lut_start      <= 1'b0;
            contract_error <= 1'b0;
        end else begin
            engine_start <= 1'b0;
            lut_start    <= 1'b0;

            if (engine_error) contract_error <= 1'b1;
            // Reject histogram writes while busy or together with start.
            if ((hist_wr_en && ((state != C_IDLE) || start)) ||
                (start && (state != C_IDLE)))
                contract_error <= 1'b1;

            case (state)
                C_IDLE: begin
                    if (start) begin
                        // Report a write conflict instead of accepting the histogram update.
                        if (hist_wr_en) begin
                            contract_error <= 1'b1;
                        end else
                        // Report an invalid cluster count instead of changing it silently.
                        if ((num_clusters < NUMC_W'(MIN_CLUSTERS)) ||
                            (num_clusters > NUMC_W'(MAX_C))) begin
                            contract_error <= 1'b1;
                        end else begin
                            k_active       <= num_clusters;
                            contract_error <= 1'b0;
                            engine_start   <= 1'b1;
                            state          <= C_ENGINE;
                        end
                    end
                end

                C_ENGINE: begin
                    if (engine_done) begin
                        lut_start <= 1'b1;
                        state     <= C_LUT;
                    end
                end

                C_LUT: if (lut_done) state <= C_DONE;

                C_DONE: state <= C_IDLE;

                default: state <= C_IDLE;
            endcase
        end
    end

endmodule
