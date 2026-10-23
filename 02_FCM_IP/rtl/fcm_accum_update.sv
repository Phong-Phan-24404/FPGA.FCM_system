// File: fcm_accum_update.sv
// Description: Adds weighted histogram values for one FCM cluster.
// Author: Phan Chau Phong
// Module: fcm_accum_update
// Description: Calculates each weighted contribution and updates the accumulators.
// The calculation runs in registered steps:
// - Square the membership value.
// - Multiply the square by the bin count.
// - Shift the denominator weight and multiply it by the gray value.
// - Add both values to the running totals and signal done.
// The full product is kept before shifting to preserve fixed-point accuracy.
// Clear cancels the current operation, and start is only used when idle.
module fcm_accum_update import fcm_pkg::*; (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   clear,
    input  logic                   start,
    input  logic [COUNT_W-1:0]     bin_count,
    input  logic [GRAY_W-1:0]      gray,
    input  member_t                membership_q,
    output logic [ACC_DEN_W-1:0]   accum_den,
    output logic [ACC_NUM_W-1:0]   accum_num,
    output logic                   busy,
    output logic                   done,
    output logic                   overflow
);
    localparam int SQ_W = MEMBER_W * 2;
    typedef enum logic [2:0] {
        A_IDLE, A_PRODUCT, A_WEIGHT, A_ACCUM
    } state_t;
    state_t state;

    logic [SQ_W-1:0]            square_q;
    logic [COUNT_W-1:0]        count_q;
    logic [GRAY_W-1:0]         gray_q;
    logic [CSQ_PROD_W-1:0]     count_square_q;
    logic [ACC_DEN_W-1:0]      den_add_q;
    logic [ACC_NUM_W-1:0]      num_add_q;
    logic [ACC_DEN_W:0]        den_next;
    logic [ACC_NUM_W:0]        num_next;

    // Add the pending denominator and numerator values to the totals.
    assign den_next = {1'b0, accum_den} + {1'b0, den_add_q};
    assign num_next = {1'b0, accum_num} + {1'b0, num_add_q};
    assign busy = (state != A_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= A_IDLE;
            accum_den      <= '0;
            accum_num      <= '0;
            square_q       <= '0;
            count_q        <= '0;
            gray_q         <= '0;
            count_square_q <= '0;
            den_add_q      <= '0;
            num_add_q      <= '0;
            done           <= 1'b0;
            overflow       <= 1'b0;
        end else if (clear) begin
            state          <= A_IDLE;
            accum_den      <= '0;
            accum_num      <= '0;
            square_q       <= '0;
            count_q        <= '0;
            gray_q         <= '0;
            count_square_q <= '0;
            den_add_q      <= '0;
            num_add_q      <= '0;
            done           <= 1'b0;
            overflow       <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                A_IDLE: begin
                    if (start) begin
                        square_q <= SQ_W'(membership_q) * SQ_W'(membership_q);
                        count_q  <= bin_count;
                        gray_q   <= gray;
                        state    <= A_PRODUCT;
                    end
                end
                A_PRODUCT: begin
                    count_square_q <= CSQ_PROD_W'(count_q) *
                                      CSQ_PROD_W'(square_q);
                    state          <= A_WEIGHT;
                end
                A_WEIGHT: begin
                    den_add_q <= ACC_DEN_W'(count_square_q >> MEMBER_FRAC);
                    num_add_q <= ACC_NUM_W'(count_square_q >> MEMBER_FRAC) *
                                 ACC_NUM_W'(gray_q);
                    state     <= A_ACCUM;
                end
                A_ACCUM: begin
                    accum_den <= den_next[ACC_DEN_W-1:0];
                    accum_num <= num_next[ACC_NUM_W-1:0];
                    if (den_next[ACC_DEN_W] || num_next[ACC_NUM_W])
                        overflow <= 1'b1;
                    done  <= 1'b1;
                    state <= A_IDLE;
                end
                default: state <= A_IDLE;
            endcase
        end
    end
endmodule
