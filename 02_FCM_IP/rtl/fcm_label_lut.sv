// File: fcm_label_lut.sv
// Description: Builds the label lookup table for grayscale values.
// Author: Phan Chau Phong
// Module: fcm_label_lut
// Description: Assigns each gray value to its nearest cluster center.
// The table has 256 entries, one for each grayscale level.
// When distances are equal, the cluster with the smaller index wins.

module fcm_label_lut import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic [NUMC_W-1:0]     num_clusters,
    input  center_t               centers_q [0:MAX_C-1],

    output logic                  wr_en,
    output logic [GRAY_W-1:0]     wr_addr,
    output logic [LABEL_W-1:0]    wr_data,

    output logic                  busy,
    output logic                  done
);

    localparam int IDX_W = $clog2(MAX_C);

    typedef enum logic [2:0] {L_IDLE, L_DIST, L_SCAN, L_WRITE, L_DONE} state_t;
    state_t state;

    logic [NUMC_W-1:0] k_active;
    logic [GRAY_W-1:0] gray;
    logic [IDX_W-1:0]  cidx;
    center_t           best_distance;
    logic [LABEL_W-1:0] best_label;

    center_t gray_q, distance_comb, dist_q;
    assign gray_q = center_t'(gray) << CENTER_FRAC;

    // Select the center and calculate its absolute distance first.
    // Compare the distance with the current best value in the next state.
    // Keeping these steps separate makes the combinational path shorter.
    always_comb begin
        if (gray_q >= centers_q[cidx]) distance_comb = gray_q - centers_q[cidx];
        else                           distance_comb = centers_q[cidx] - gray_q;
    end

    assign busy = (state != L_IDLE);
    assign done = (state == L_DONE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= L_IDLE;
            k_active      <= NUMC_W'(MIN_CLUSTERS);
            gray          <= '0;
            cidx          <= '0;
            best_distance <= '0;
            best_label    <= '0;
            dist_q        <= '0;
            wr_en         <= 1'b0;
            wr_addr       <= '0;
            wr_data       <= '0;
        end else begin
            wr_en <= 1'b0;

            case (state)
                L_IDLE: begin
                    if (start) begin
                        k_active      <= num_clusters;
                        gray          <= '0;
                        cidx          <= '0;
                        best_distance <= {CENTER_W{1'b1}};
                        best_label    <= '0;
                        state         <= L_DIST;
                    end
                end

                L_DIST: begin
                    dist_q <= distance_comb;
                    state  <= L_SCAN;
                end

                L_SCAN: begin
                    if (dist_q < best_distance) begin
                        best_distance <= dist_q;
                        best_label    <= LABEL_W'(cidx);
                    end
                    if (cidx == IDX_W'(k_active - NUMC_W'(1))) begin
                        cidx  <= '0;
                        state <= L_WRITE;
                    end else begin
                        cidx  <= cidx + IDX_W'(1);
                        state <= L_DIST;
                    end
                end

                L_WRITE: begin
                    wr_en   <= 1'b1;
                    wr_addr <= gray;
                    // The last comparison has already updated best_label, so this state
                    // writes the selected label without another comparison.
                    wr_data <= best_label;

                    if (gray == GRAY_W'(GRAY_BINS - 1)) begin
                        state <= L_DONE;
                    end else begin
                        gray          <= gray + GRAY_W'(1);
                        best_distance <= {CENTER_W{1'b1}};
                        best_label    <= '0;
                        state         <= L_DIST;
                    end
                end

                L_DONE: state <= L_IDLE;

                default: state <= L_IDLE;
            endcase
        end
    end

endmodule
