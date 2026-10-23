// File: fcm_core_engine.sv
// Description: Runs the FCM iterations and calculates the cluster centers.
// Author: Phan Chau Phong
// Module: fcm_core_engine
// Description: Updates centers using histogram bins and fixed-point membership values.
// Each iteration keeps a copy of the starting centers, processes the active
// histogram bins, and uses weighted sums to calculate the next centers.
// Clusters with no weight are reseeded using the least represented gray bin.
// Convergence uses the largest center change after reseeding.

module fcm_core_engine import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic [NUMC_W-1:0]     num_clusters,
    input  center_t               init_centers_q [0:MAX_C-1],

    output logic [GRAY_W-1:0]     hist_rd_addr,
    input  logic [COUNT_W-1:0]    hist_rd_data,

    output center_t               centers_q [0:MAX_C-1],
    output logic                  converged,
    output logic [ITER_W-1:0]     iter_converged,
    output logic                  busy,
    output logic                  done,
    output logic                  contract_error
);

    localparam int IDX_W = $clog2(MAX_C);

    typedef enum logic [4:0] {
        E_IDLE,
        E_ITER_START,
        E_BIN_ADDR,
        E_BIN_FETCH,
        E_MEMBER_START,
        E_MEMBER_WAIT,
        E_ACCUM_START,
        E_BIN_NEXT,
        E_DRAIN,
        E_CENTER_START,
        E_CENTER_WAIT,
        E_CENTER_NEXT,
        E_RS_SETUP,
        E_RS_ADDR,
        E_RS_FETCH,
        E_RS_DIST,
        E_RS_SQUARE,
        E_RS_MIN,
        E_RS_SCORE_MUL,
        E_RS_SCORE,
        E_RS_NEXT_BIN,
        E_RS_COMMIT,
        E_DELTA_CALC,
        E_DELTA,
        E_CHECK,
        E_DONE
    } state_t;

    state_t state;

    logic [NUMC_W-1:0] k_active;
    logic [ITER_W-1:0] iteration;
    logic [GRAY_W-1:0] bin_index;
    logic              bin_last;
    logic [IDX_W-1:0]  cidx;

    center_t           center_reg   [0:MAX_C-1];
    center_t           previous_reg [0:MAX_C-1];
    member_t           member_bus   [0:MAX_C-1];
    logic [MAX_C-1:0]  dead_mask;
    center_t           max_delta;

    logic [COUNT_W-1:0] bin_count;

    // Process membership values for the next bin while the current bin is
    // being accumulated. Both operations use the same centers for the iteration.
    // A one-entry buffer stores the membership values and their gray/count data
    // so they remain valid when the next membership calculation starts.
    logic [GRAY_W-1:0]  mem_gray;
    logic [COUNT_W-1:0] mem_count;
    member_t            res_member [0:MAX_C-1];
    logic [GRAY_W-1:0]  res_gray;
    logic [COUNT_W-1:0] res_count;
    logic               res_valid;

    // Calculate membership values for each histogram bin.
    logic member_start, member_done, member_error;

    fcm_member #(.MAX_C(MAX_C)) u_member (
        .clk(clk), .rst_n(rst_n),
        .start(member_start),
        .num_clusters(k_active),
        .gray(mem_gray),
        .centers_q(previous_reg),
        .membership_q(member_bus),
        .busy(), .done(member_done),
        .contract_error(member_error)
    );

    // Run one accumulator for each cluster in parallel.
    logic accum_clear, accum_start;
    logic [ACC_DEN_W-1:0] accum_den [0:MAX_C-1];
    logic [ACC_NUM_W-1:0] accum_num [0:MAX_C-1];
    logic [MAX_C-1:0]     accum_done;
    logic [MAX_C-1:0]     accum_busy;
    logic [MAX_C-1:0]     accum_overflow;

    // Check busy for every accumulator before moving on.
    // The done signal only lasts one cycle, so it cannot be used to wait for idle.
    logic accum_quiet;
    assign accum_quiet = (accum_busy == '0) && !accum_start;

    generate
        genvar lane;
        for (lane = 0; lane < MAX_C; lane = lane + 1) begin : gen_accum
            // Inactive lanes receive zero membership but finish with the other lanes.
            fcm_accum_update u_accum (
                .clk(clk), .rst_n(rst_n),
                .clear(accum_clear),
                .start(accum_start),
                .bin_count(res_count),
                .gray(res_gray),
                .membership_q(res_member[lane]),
                .accum_den(accum_den[lane]),
                .accum_num(accum_num[lane]),
                .busy(accum_busy[lane]), .done(accum_done[lane]),
                .overflow(accum_overflow[lane])
            );
        end
    endgenerate

    // Update each center using (numerator << F) / denominator.
    logic                    center_start, center_done, center_dz, center_ovf;
    logic [CENTER_NUM_W-1:0] center_num;
    logic [ACC_DEN_W-1:0]    center_den;
    center_t                 center_quot;

    fcm_divider #(.NUM_W(CENTER_NUM_W), .DEN_W(ACC_DEN_W), .QUOT_W(CENTER_W))
    center_divider (
        .clk(clk), .rst_n(rst_n), .start(center_start),
        .numerator(center_num), .denominator(center_den),
        .quotient(center_quot), .remainder(),
        .busy(), .done(center_done),
        .div_by_zero(center_dz), .overflow(center_ovf)
    );

    // Keep the values needed to reseed clusters with no weight.
    logic [GRAY_BINS-1:0]        gray_used;
    logic [RESEED_SCORE_W-1:0]   rs_best_score,   rs_global_score;
    logic [GRAY_W-1:0]           rs_best_gray,    rs_global_gray;
    logic                        rs_best_valid,   rs_global_valid;
    logic [DSQ_W-1:0]            rs_min_square;
    logic [IDX_W-1:0]            rs_k;
    logic [IDX_W-1:0]            rs_dead;

    // Calculate the squared distance to the selected starting center.
    center_t          rs_gray_q, rs_distance, rs_dist_q;
    logic [DSQ_W-1:0] rs_square, rs_square_q;

    assign rs_gray_q = center_t'(bin_index) << CENTER_FRAC;

    // Select a center and calculate the absolute distance first.
    // Square the distance in a separate step to keep the logic path short.
    always_comb begin
        if (rs_gray_q >= previous_reg[rs_k]) rs_distance = rs_gray_q - previous_reg[rs_k];
        else                                 rs_distance = previous_reg[rs_k] - rs_gray_q;
    end

    assign rs_square = DSQ_W'(rs_dist_q) * DSQ_W'(rs_dist_q);

    // Calculate reseed scores as count * minimum squared distance.
    // Register the wide product before comparing candidate scores.
    logic [RESEED_SCORE_W-1:0] rs_score;
    logic [RESEED_SCORE_W-1:0] rs_score_q;
    assign rs_score = RESEED_SCORE_W'(bin_count) * RESEED_SCORE_W'(rs_min_square);

    // Calculate the absolute change between each center and its starting value.
    // The maximum-change comparison is done in another step.
    center_t delta_abs, delta_abs_q;
    always_comb begin
        if (center_reg[cidx] >= previous_reg[cidx])
            delta_abs = center_reg[cidx] - previous_reg[cidx];
        else
            delta_abs = previous_reg[cidx] - center_reg[cidx];
    end

    assign busy = (state != E_IDLE);
    assign done = (state == E_DONE);
    assign hist_rd_addr = bin_index;

    generate
        genvar o;
        for (o = 0; o < MAX_C; o = o + 1) begin : gen_center_out
            assign centers_q[o] = center_reg[o];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= E_IDLE;
            k_active        <= NUMC_W'(MIN_CLUSTERS);
            iteration       <= '0;
            bin_index       <= '0;
            bin_last        <= 1'b0;
            cidx            <= '0;
            bin_count       <= '0;
            mem_gray        <= '0;
            mem_count       <= '0;
            res_gray        <= '0;
            res_count       <= '0;
            res_valid       <= 1'b0;
            for (int i = 0; i < MAX_C; i++) res_member[i] <= '0;
            dead_mask       <= '0;
            max_delta       <= '0;
            delta_abs_q     <= '0;
            converged       <= 1'b0;
            iter_converged  <= '0;
            contract_error  <= 1'b0;
            member_start    <= 1'b0;
            accum_clear     <= 1'b0;
            accum_start     <= 1'b0;
            center_start    <= 1'b0;
            center_num      <= '0;
            center_den      <= '0;
            gray_used       <= '0;
            rs_best_score   <= '0;
            rs_best_gray    <= '0;
            rs_best_valid   <= 1'b0;
            rs_global_score <= '0;
            rs_global_gray  <= '0;
            rs_global_valid <= 1'b0;
            rs_min_square   <= '0;
            rs_dist_q       <= '0;
            rs_score_q      <= '0;
            rs_square_q     <= '0;
            rs_k            <= '0;
            rs_dead         <= '0;
            for (int i = 0; i < MAX_C; i++) begin
                center_reg[i]   <= '0;
                previous_reg[i] <= '0;
            end
        end else begin
            member_start <= 1'b0;
            accum_clear  <= 1'b0;
            accum_start  <= 1'b0;
            center_start <= 1'b0;

            if (|accum_overflow) contract_error <= 1'b1;
            if (member_error)    contract_error <= 1'b1;

            case (state)
                E_IDLE: begin
                    if (start) begin
                        k_active       <= num_clusters;
                        iteration      <= ITER_W'(1);
                        converged      <= 1'b0;
                        iter_converged <= '0;
                        contract_error <= 1'b0;
                        for (int i = 0; i < MAX_C; i++) center_reg[i] <= init_centers_q[i];
                        state <= E_ITER_START;
                    end
                end

                // Keep the starting centers fixed throughout this iteration.
                E_ITER_START: begin
                    for (int i = 0; i < MAX_C; i++) previous_reg[i] <= center_reg[i];
                    accum_clear <= 1'b1;
                    bin_index   <= '0;
                    bin_last    <= 1'b0;
                    dead_mask   <= '0;
                    max_delta   <= '0;
                    res_valid   <= 1'b0;
                    state       <= E_BIN_ADDR;
                end

                // Read the histogram count one cycle after setting the address.
                E_BIN_ADDR: state <= E_BIN_FETCH;

                E_BIN_FETCH: begin
                    bin_count <= hist_rd_data;
                    bin_last  <= (bin_index == GRAY_W'(GRAY_BINS - 1));
                    if (hist_rd_data == '0) state <= E_BIN_NEXT;
                    else begin
                        // Save the gray value and count while membership processing runs.
                        mem_gray  <= bin_index;
                        mem_count <= hist_rd_data;
                        state     <= E_MEMBER_START;
                    end
                end

                E_MEMBER_START: begin
                    member_start <= 1'b1;
                    state        <= E_MEMBER_WAIT;
                end

                // Buffer the finished membership values with their matching bin data.
                // The accumulator can use this data while the next bin is processed.
                E_MEMBER_WAIT: begin
                    if (member_done) begin
                        for (int i = 0; i < MAX_C; i++) res_member[i] <= member_bus[i];
                        res_gray  <= mem_gray;
                        res_count <= mem_count;
                        res_valid <= 1'b1;
                        state     <= E_ACCUM_START;
                    end
                end

                // Start accumulation and continue processing the next bin.
                // Only start when all accumulator lanes are idle.
                E_ACCUM_START: begin
                    if (accum_quiet) begin
                        accum_start <= 1'b1;
                        res_valid   <= 1'b0;
                        state       <= E_BIN_NEXT;
                    end
                end

                E_BIN_NEXT: begin
                    if (bin_last) state <= E_DRAIN;
                    else begin
                        bin_index <= bin_index + GRAY_W'(1);
                        state     <= E_BIN_ADDR;
                    end
                end

                // Wait for all buffered contributions before updating any center.
                E_DRAIN: begin
                    if (accum_quiet && !res_valid) begin
                        cidx  <= '0;
                        state <= E_CENTER_START;
                    end
                end

                // Update centers using the weighted average.
                E_CENTER_START: begin
                    if (NUMC_W'(cidx) >= k_active) begin
                        // Leave inactive cluster centers unchanged.
                        state <= E_CENTER_NEXT;
                    end else if (accum_den[cidx] == '0) begin
                        // Keep the center for now and mark this cluster for reseeding.
                        dead_mask[cidx] <= 1'b1;
                        state           <= E_CENTER_NEXT;
                    end else begin
                        center_num   <= CENTER_NUM_W'(accum_num[cidx]) << CENTER_FRAC;
                        center_den   <= accum_den[cidx];
                        center_start <= 1'b1;
                        state        <= E_CENTER_WAIT;
                    end
                end

                E_CENTER_WAIT: begin
                    if (center_done) begin
                        center_reg[cidx] <= center_quot;
                        if (center_dz || center_ovf) contract_error <= 1'b1;
                        // Check that the center stays within the allowed grayscale range.
                        if (center_quot > CENTER_MAX_Q) contract_error <= 1'b1;
                        state <= E_CENTER_NEXT;
                    end
                end

                E_CENTER_NEXT: begin
                    if (cidx == IDX_W'(MAX_C - 1)) begin
                        cidx <= '0;
                        if (|dead_mask) state <= E_RS_SETUP;
                        else            state <= E_DELTA_CALC;
                    end else begin
                        cidx  <= cidx + IDX_W'(1);
                        state <= E_CENTER_START;
                    end
                end

                // Reseed clusters that received no weight.
                // Scan histogram bins to find the strongest unused candidate.
                E_RS_SETUP: begin
                    gray_used       <= '0;
                    rs_dead         <= '0;
                    rs_best_valid   <= 1'b0;
                    rs_best_score   <= '0;
                    rs_global_valid <= 1'b0;
                    rs_global_score <= '0;
                    bin_index       <= '0;
                    bin_last        <= 1'b0;
                    state           <= E_RS_ADDR;
                end

                E_RS_ADDR: state <= E_RS_FETCH;

                E_RS_FETCH: begin
                    bin_count     <= hist_rd_data;
                    bin_last      <= (bin_index == GRAY_W'(GRAY_BINS - 1));
                    rs_k          <= '0;
                    rs_min_square <= {DSQ_W{1'b1}};
                    if (hist_rd_data == '0) state <= E_RS_NEXT_BIN;
                    else                    state <= E_RS_DIST;
                end

                // Select a center, square the distance, and compare the result in
                // separate steps.
                E_RS_DIST: begin
                    rs_dist_q <= rs_distance;
                    state     <= E_RS_SQUARE;
                end

                E_RS_SQUARE: begin
                    rs_square_q <= rs_square;
                    state       <= E_RS_MIN;
                end

                E_RS_MIN: begin
                    if (rs_square_q < rs_min_square) rs_min_square <= rs_square_q;
                    if (rs_k == IDX_W'(k_active - NUMC_W'(1))) state <= E_RS_SCORE_MUL;
                    else begin
                        rs_k <= rs_k + IDX_W'(1);
                        state <= E_RS_DIST;
                    end
                end

                // Choose the highest reseed score. Ties go to the smaller gray value
                // because bins are checked in ascending order.
                E_RS_SCORE_MUL: begin
                    rs_score_q <= rs_score;
                    state      <= E_RS_SCORE;
                end

                E_RS_SCORE: begin
                    if (!rs_global_valid || (rs_score_q > rs_global_score)) begin
                        rs_global_valid <= 1'b1;
                        rs_global_score <= rs_score_q;
                        rs_global_gray  <= bin_index;
                    end
                    if (!gray_used[bin_index] &&
                        (!rs_best_valid || (rs_score_q > rs_best_score))) begin
                        rs_best_valid <= 1'b1;
                        rs_best_score <= rs_score_q;
                        rs_best_gray  <= bin_index;
                    end
                    state <= E_RS_NEXT_BIN;
                end

                E_RS_NEXT_BIN: begin
                    if (bin_last) state <= E_RS_COMMIT;
                    else begin
                        bin_index <= bin_index + GRAY_W'(1);
                        state     <= E_RS_ADDR;
                    end
                end

                E_RS_COMMIT: begin
                    if (dead_mask[rs_dead]) begin
                        // If all unused candidates are taken, choose the best overall bin.
                        automatic logic [GRAY_W-1:0] pick =
                            rs_best_valid ? rs_best_gray : rs_global_gray;
                        center_reg[rs_dead] <= center_t'(pick) << CENTER_FRAC;
                        gray_used[pick]     <= 1'b1;
                    end

                    if (rs_dead == IDX_W'(MAX_C - 1)) begin
                        cidx  <= '0;
                        state <= E_DELTA_CALC;
                    end else begin
                        rs_dead       <= rs_dead + IDX_W'(1);
                        // Scan again for the next cluster using the updated used-bin flags.
                        rs_best_valid <= 1'b0;
                        rs_best_score <= '0;
                        bin_index     <= '0;
                        bin_last      <= 1'b0;
                        state         <= E_RS_ADDR;
                    end
                end

                // Calculate the largest center change after reseeding.
                E_DELTA_CALC: begin
                    delta_abs_q <= delta_abs;
                    state       <= E_DELTA;
                end

                E_DELTA: begin
                    if ((NUMC_W'(cidx) < k_active) && (delta_abs_q > max_delta))
                        max_delta <= delta_abs_q;
                    if (cidx == IDX_W'(MAX_C - 1)) state <= E_CHECK;
                    else begin
                        cidx  <= cidx + IDX_W'(1);
                        state <= E_DELTA_CALC;
                    end
                end

                E_CHECK: begin
                    if (max_delta <= EPSILON_Q) begin
                        converged      <= 1'b1;
                        iter_converged <= iteration;
                        state          <= E_DONE;
                    end else if (iteration == ITER_W'(MAX_ITER)) begin
                        converged      <= 1'b0;
                        iter_converged <= iteration;
                        state          <= E_DONE;
                    end else begin
                        iteration <= iteration + ITER_W'(1);
                        state     <= E_ITER_START;
                    end
                end

                E_DONE: state <= E_IDLE;

                default: state <= E_IDLE;
            endcase
        end
    end

endmodule
