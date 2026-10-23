// File: fcm_member.sv
// Description: Calculates FCM membership values using unsigned fixed-point math.
// Author: Phan Chau Phong
// Module: fcm_member
// Description: Converts distances to membership weights for each active cluster.
// It squares the distance from each center, calculates normalized ratios,
// and scales the ratios so all membership values add up to 2^M.
// An exact center match shares the weight across matching clusters.
// Ties and leftover bits are handled in a fixed cluster order.

module fcm_member import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic [NUMC_W-1:0]     num_clusters,
    input  logic [GRAY_W-1:0]     gray,
    input  center_t               centers_q [0:MAX_C-1],
    output member_t               membership_q [0:MAX_C-1],
    output logic                  busy,
    output logic                  done,
    // Set this flag if a fixed-point calculation breaks the expected range.
    output logic                  contract_error
);

    localparam int IDX_W = $clog2(MAX_C);

    // The state machine needs five bits for all of its states.
    typedef enum logic [4:0] {
        S_IDLE,
        S_DIST,
        S_SQUARE,
        S_SQUARE_COMMIT,
        S_SQUARE_REDUCE,
        S_SPLIT_DIV,
        S_SPLIT_WAIT,
        S_SPLIT_ASSIGN,
        S_RATIO_DIV,
        S_RATIO_WAIT,
        S_RATIO_REDUCE,
        S_RATIO_REDUCE2,
        S_RECIP_DIV,
        S_RECIP_WAIT,
        S_SCALE,
        S_SCALE_SHIFT,
        S_SCALE_SUM,
        S_RESIDUAL,
        S_DONE
    } state_t;

    state_t state;

    logic [NUMC_W-1:0] k_active;
    logic [GRAY_W-1:0] gray_reg;
    center_t           center_reg [0:MAX_C-1];
    logic [IDX_W-1:0]  idx;

    logic [DSQ_W-1:0]  square [0:MAX_C-1];
    center_t           dist_q [0:MAX_C-1];
    logic [DSQ_W-1:0]  min_square;
    logic [NUMC_W-1:0] zero_count;
    // Remember which clusters match the gray value exactly.
    logic [MAX_C-1:0]  zero_mask_q;

    logic [RATIO_W-1:0]     ratio [0:MAX_C-1];
    logic [RATIO_SUM_W-1:0] ratio_sum;
    logic [RECIP_W-1:0]     recip;

    member_t                member [0:MAX_C-1];
    logic [RATIO_SUM_W-1:0] member_sum;
    logic [IDX_W-1:0]       best_idx;
    logic [RATIO_W-1:0]     best_ratio;

    // Calculate the distance and squared distance for each cluster.
    center_t          gray_q;
    center_t          distance_comb [0:MAX_C-1];
    logic [DSQ_W-1:0] square_comb   [0:MAX_C-1];

    assign gray_q = center_t'(gray_reg) << CENTER_FRAC;

    // Calculate distances for all cluster lanes in parallel.
    // Register each distance before squaring it to shorten the logic path.
    always_comb begin
        for (int i = 0; i < MAX_C; i++) begin
            if (gray_q >= center_reg[i]) distance_comb[i] = gray_q - center_reg[i];
            else                         distance_comb[i] = center_reg[i] - gray_q;
            square_comb[i] = DSQ_W'(dist_q[i]) * DSQ_W'(dist_q[i]);
        end
    end

    // Find the smallest squared distance with a comparison tree.
    // A tree keeps the number of comparison levels small.
    localparam int TREE_N = 1 << $clog2(MAX_C);
    localparam int TREE_L = $clog2(MAX_C);
    localparam int L1_N   = TREE_N / 2;

    // Inactive cluster lanes use the maximum value, so they cannot win
    // the minimum-distance comparison.
    // Function: sq_masked
    // Description: Returns a squared distance or the mask for an inactive lane.
    function automatic logic [DSQ_W-1:0] sq_masked(input int i);
        if ((i < MAX_C) && (NUMC_W'(i) < k_active)) return square[(i < MAX_C) ? i : 0];
        else                                        return {DSQ_W{1'b1}};
    endfunction

    logic [DSQ_W-1:0]  min_l1_comb [0:L1_N-1];
    logic [DSQ_W-1:0]  min_l1      [0:L1_N-1];
    logic [DSQ_W-1:0]  min_rest [0:TREE_L-1][0:L1_N-1];
    logic [DSQ_W-1:0]  min_square_comb;
    logic [NUMC_W-1:0] zero_count_comb;

    // Use an addition tree to sum memberships across active lanes.
    logic [RATIO_SUM_W-1:0] sum_tree [0:TREE_L][0:TREE_N-1];
    logic [RATIO_SUM_W-1:0] member_sum_comb;

    always_comb begin
        for (int i = 0; i < TREE_N; i++)
            sum_tree[0][i] = ((i < MAX_C) && (NUMC_W'(i) < k_active))
                             ? RATIO_SUM_W'(member[(i < MAX_C) ? i : 0])
                             : '0;
        for (int l = 1; l <= TREE_L; l++)
            for (int i = 0; i < (TREE_N >> l); i++)
                sum_tree[l][i] = sum_tree[l-1][2*i] + sum_tree[l-1][2*i+1];
        member_sum_comb = sum_tree[TREE_L][0];
    end

    // Split the minimum-distance tree across registered stages.
    always_comb begin
        automatic logic [DSQ_W-1:0] a, b;
        for (int i = 0; i < L1_N; i++) begin
            a = sq_masked(2*i);
            b = sq_masked(2*i + 1);
            min_l1_comb[i] = (a < b) ? a : b;
        end

        for (int i = 0; i < L1_N; i++) min_rest[0][i] = min_l1[i];
        for (int l = 1; l < TREE_L; l++)
            for (int i = 0; i < (L1_N >> l); i++)
                min_rest[l][i] = (min_rest[l-1][2*i] < min_rest[l-1][2*i+1])
                                 ? min_rest[l-1][2*i] : min_rest[l-1][2*i+1];
        min_square_comb = min_rest[TREE_L-1][0];

        // Inactive lanes cannot be counted as exact center matches.
        zero_count_comb = '0;
        for (int i = 0; i < TREE_N; i++)
            if (sq_masked(i) == '0) zero_count_comb = zero_count_comb + NUMC_W'(1);
    end

    // Run one ratio divider for each active cluster.
    // Each lane calculates (minimum squared distance << M) / squared distance.
    // Inactive lanes never start, so they cannot trigger divide-by-zero.
    // Save each result as it finishes because divider times can differ.
    logic                   ratio_start;
    logic [RATIO_NUM_W-1:0] ratio_num;
    logic [MAX_C-1:0]       ratio_done_bus, ratio_dz_bus, ratio_ovf_bus;
    logic [RATIO_W-1:0]     ratio_quot_bus [0:MAX_C-1];
    logic [MAX_C-1:0]       lane_active;
    logic [MAX_C-1:0]       ratio_got, ratio_got_next;

    generate
        genvar rlane;
        for (rlane = 0; rlane < MAX_C; rlane = rlane + 1) begin : gen_ratio
            assign lane_active[rlane] = (NUMC_W'(rlane) < k_active);

            fcm_divider #(.NUM_W(RATIO_NUM_W), .DEN_W(DSQ_W), .QUOT_W(RATIO_W))
            ratio_divider (
                .clk(clk), .rst_n(rst_n),
                .start(ratio_start & lane_active[rlane]),
                .numerator(ratio_num), .denominator(square[rlane]),
                .quotient(ratio_quot_bus[rlane]), .remainder(),
                .busy(), .done(ratio_done_bus[rlane]),
                .div_by_zero(ratio_dz_bus[rlane]), .overflow(ratio_ovf_bus[rlane])
            );
        end
    endgenerate

    // Inactive divider lanes count as finished.
    always_comb begin
        ratio_got_next = ratio_got | (ratio_done_bus & lane_active);
    end

    logic                  recip_start, recip_done, recip_dz, recip_ovf;
    logic [RECIP_W-1:0]    recip_quot;

    // Use radix-2 division for the normalization reciprocal.
    localparam int RECIP_RADIX = 2;

    fcm_divider #(.NUM_W(NORM_NUM_W), .DEN_W(RATIO_SUM_W), .QUOT_W(RECIP_W),
                  .RADIX(RECIP_RADIX))
    recip_divider (
        .clk(clk), .rst_n(rst_n), .start(recip_start),
        .numerator(NORM_NUM_W'(1) << (MEMBER_FRAC + NORM_GUARD)),
        .denominator(ratio_sum),
        .quotient(recip_quot), .remainder(),
        .busy(), .done(recip_done),
        .div_by_zero(recip_dz), .overflow(recip_ovf)
    );

    logic                  split_start, split_done, split_dz;
    logic [MEMBER_W-1:0]   split_quot;
    logic [NUMC_W-1:0]     split_rem;

    fcm_divider #(.NUM_W(MEMBER_W), .DEN_W(NUMC_W), .QUOT_W(MEMBER_W))
    split_divider (
        .clk(clk), .rst_n(rst_n), .start(split_start),
        .numerator(MEMBER_W'(ONE_Q)), .denominator(zero_count),
        .quotient(split_quot), .remainder(split_rem),
        .busy(), .done(split_done),
        .div_by_zero(split_dz), .overflow()
    );

    // Find the sum of ratios and the index with the largest ratio.
    // For equal ratios, keep the smaller cluster index.
    // Register pairwise results before combining the remaining values.
    logic [RATIO_W-1:0]     r_l1_val  [0:L1_N-1];
    logic [IDX_W-1:0]       r_l1_idx  [0:L1_N-1];
    logic [RATIO_SUM_W-1:0] r_l1_sum  [0:L1_N-1];
    logic [RATIO_W-1:0]     r_l1_val_q [0:L1_N-1];
    logic [IDX_W-1:0]       r_l1_idx_q [0:L1_N-1];
    logic [RATIO_SUM_W-1:0] r_l1_sum_q [0:L1_N-1];

    logic [RATIO_W-1:0]     best_val_comb;
    logic [IDX_W-1:0]       best_idx_comb;
    logic [RATIO_SUM_W-1:0] sum_comb;

    // Inactive lanes have a zero ratio and do not affect the sum or max.
    always_comb begin
        automatic logic [RATIO_W-1:0] a_val, b_val;
        automatic logic [IDX_W-1:0]   a_idx, b_idx;

        // Compare adjacent pairs of cluster lanes.
        for (int i = 0; i < L1_N; i++) begin
            // Use a safe index for the unused lane at the end of the tree.
            a_val = ((2*i)   < MAX_C && NUMC_W'(2*i)   < k_active)
                    ? ratio[((2*i)   < MAX_C) ? (2*i)   : 0] : '0;
            b_val = ((2*i+1) < MAX_C && NUMC_W'(2*i+1) < k_active)
                    ? ratio[((2*i+1) < MAX_C) ? (2*i+1) : 0] : '0;
            a_idx = IDX_W'(2*i);
            b_idx = IDX_W'(2*i+1);
            // Keep the smaller index when ratio values are equal.
            if (b_val > a_val) begin
                r_l1_val[i] = b_val;
                r_l1_idx[i] = b_idx;
            end else begin
                r_l1_val[i] = a_val;
                r_l1_idx[i] = a_idx;
            end
            r_l1_sum[i] = RATIO_SUM_W'(a_val) + RATIO_SUM_W'(b_val);
        end

        // Combine the pairwise results saved in registers.
        best_val_comb = r_l1_val_q[0];
        best_idx_comb = r_l1_idx_q[0];
        sum_comb      = '0;
        for (int i = 0; i < L1_N; i++) begin
            if (i != 0 && (r_l1_val_q[i] > best_val_comb)) begin
                best_val_comb = r_l1_val_q[i];
                best_idx_comb = r_l1_idx_q[i];
            end
            sum_comb = sum_comb + r_l1_sum_q[i];
        end
    end

    // Scale every active ratio with u_k = (r_k * t) >> G.
    // Each cluster has its own multiplier.
    logic [NORM_PROD_W-1:0] scale_product [0:MAX_C-1];
    // Register the products before shifting and storing memberships.
    // This separates the multiplication from the next logic step.
    logic [NORM_PROD_W-1:0] prod_q [0:MAX_C-1];
    generate
        genvar slane;
        for (slane = 0; slane < MAX_C; slane = slane + 1) begin : gen_scale
            assign scale_product[slane] =
                NORM_PROD_W'(ratio[slane]) * NORM_PROD_W'(recip);
        end
    endgenerate

    assign busy = (state != S_IDLE);
    assign done = (state == S_DONE);

    generate
        genvar g;
        for (g = 0; g < MAX_C; g = g + 1) begin : gen_member_out
            assign membership_q[g] = member[g];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            idx            <= '0;
            k_active       <= NUMC_W'(MIN_CLUSTERS);
            gray_reg       <= '0;
            min_square     <= '0;
            zero_mask_q    <= '0;
            for (int i = 0; i < MAX_C; i++) dist_q[i] <= '0;
            for (int i = 0; i < MAX_C; i++) prod_q[i] <= '0;
            for (int i = 0; i < L1_N; i++)   min_l1[i] <= {DSQ_W{1'b1}};
            for (int i = 0; i < L1_N; i++) begin
                r_l1_val_q[i] <= '0;
                r_l1_idx_q[i] <= '0;
                r_l1_sum_q[i] <= '0;
            end
            zero_count     <= '0;
            ratio_sum      <= '0;
            recip          <= '0;
            member_sum     <= '0;
            best_idx       <= '0;
            best_ratio     <= '0;
            ratio_start    <= 1'b0;
            ratio_got      <= '0;
            recip_start    <= 1'b0;
            split_start    <= 1'b0;
            ratio_num      <= '0;
            contract_error <= 1'b0;
            for (int i = 0; i < MAX_C; i++) begin
                center_reg[i] <= '0;
                square[i]     <= '0;
                ratio[i]      <= '0;
                member[i]     <= '0;
            end
        end else begin
            ratio_start <= 1'b0;
            recip_start <= 1'b0;
            split_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        k_active       <= num_clusters;
                        gray_reg       <= gray;
                        idx            <= '0;
                        min_square     <= {DSQ_W{1'b1}};
                        zero_count     <= '0;
                        ratio_sum      <= '0;
                        member_sum     <= '0;
                        best_idx       <= '0;
                        best_ratio     <= '0;
                        contract_error <= 1'b0;
                        for (int i = 0; i < MAX_C; i++) begin
                            center_reg[i] <= centers_q[i];
                            dist_q[i]     <= '0;
                            square[i]     <= '0;
                            ratio[i]      <= '0;
                            member[i]     <= '0;
                        end
                        state <= S_DIST;
                    end
                end

                // Calculate distance, square, register, and reduce across all clusters.
                S_DIST: begin
                    for (int i = 0; i < MAX_C; i++) dist_q[i] <= distance_comb[i];
                    state <= S_SQUARE;
                end

                S_SQUARE: begin
                    // Keep squared distances at zero for inactive cluster lanes.
                    for (int i = 0; i < MAX_C; i++)
                        square[i] <= (NUMC_W'(i) < k_active) ? square_comb[i] : '0;
                    state <= S_SQUARE_COMMIT;
                end

                // Save the first comparison-tree stage and count exact matches.
                S_SQUARE_COMMIT: begin
                    for (int i = 0; i < L1_N; i++) min_l1[i] <= min_l1_comb[i];
                    zero_count <= zero_count_comb;
                    state      <= S_SQUARE_REDUCE;
                end

                // Finish finding the minimum distance before starting ratio division.
                S_SQUARE_REDUCE: begin
                    min_square <= min_square_comb;
                    idx        <= '0;
                    if (zero_count != '0) state <= S_SPLIT_DIV;
                    else                  state <= S_RATIO_DIV;
                end

                // Share membership equally when centers match the gray value.
                S_SPLIT_DIV: begin
                    split_start <= 1'b1;
                    state       <= S_SPLIT_WAIT;
                end

                // Save the exact-match mask, then distribute the remaining units.
                // Lower cluster indices receive any leftover units first.
                S_SPLIT_WAIT: begin
                    if (split_done) begin
                        for (int i = 0; i < MAX_C; i++)
                            zero_mask_q[i] <= (NUMC_W'(i) < k_active) &&
                                              (square[i] == '0);
                        if (split_dz) contract_error <= 1'b1;
                        state <= S_SPLIT_ASSIGN;
                    end
                end

                S_SPLIT_ASSIGN: begin
                    automatic logic [NUMC_W-1:0] seen = '0;
                    for (int i = 0; i < MAX_C; i++) begin
                        if (zero_mask_q[i]) begin
                            member[i] <= (seen < split_rem)
                                         ? member_t'(split_quot + MEMBER_W'(1))
                                         : member_t'(split_quot);
                            seen = seen + NUMC_W'(1);
                        end else begin
                            member[i] <= '0;
                        end
                    end
                    state <= S_DONE;
                end

                // Calculate each ratio from its squared distance.
                // Start all active divider lanes together.
                S_RATIO_DIV: begin
                    ratio_num   <= RATIO_NUM_W'(min_square) << MEMBER_FRAC;
                    ratio_start <= 1'b1;
                    ratio_got   <= '0;
                    idx         <= '0;
                    state       <= S_RATIO_WAIT;
                end

                S_RATIO_WAIT: begin
                    ratio_got <= ratio_got_next;
                    for (int i = 0; i < MAX_C; i++) begin
                        if (lane_active[i] && ratio_done_bus[i] && !ratio_got[i]) begin
                            ratio[i] <= ratio_quot_bus[i];
                            if (ratio_dz_bus[i] || ratio_ovf_bus[i])
                                contract_error <= 1'b1;
                        end
                    end
                    // Wait for every active divider lane to finish.
                    if ((ratio_got_next | ~lane_active) == {MAX_C{1'b1}}) begin
                        idx   <= '0;
                        state <= S_RATIO_REDUCE;
                    end
                end

                // Save the first stage of the ratio sum and maximum-ratio selection.
                // Ties must keep the smaller cluster index.
                S_RATIO_REDUCE: begin
                    for (int i = 0; i < L1_N; i++) begin
                        r_l1_val_q[i] <= r_l1_val[i];
                        r_l1_idx_q[i] <= r_l1_idx[i];
                        r_l1_sum_q[i] <= r_l1_sum[i];
                    end
                    state <= S_RATIO_REDUCE2;
                end

                // Combine the remaining values and store the complete ratio sum.
                S_RATIO_REDUCE2: begin
                    ratio_sum  <= sum_comb;
                    best_ratio <= best_val_comb;
                    best_idx   <= best_idx_comb;
                    idx        <= '0;
                    state      <= S_RECIP_DIV;
                end

                // Calculate the normalization factor from the ratio sum.
                S_RECIP_DIV: begin
                    recip_start <= 1'b1;
                    state       <= S_RECIP_WAIT;
                end

                S_RECIP_WAIT: begin
                    if (recip_done) begin
                        recip <= recip_quot;
                        if (recip_dz || recip_ovf) contract_error <= 1'b1;
                        // Check that the ratio sum is within the expected fixed-point range.
                        if ((ratio_sum < RATIO_SUM_W'(ONE_Q)) ||
                            (ratio_sum > (RATIO_SUM_W'(k_active) << MEMBER_FRAC)))
                            contract_error <= 1'b1;
                        idx   <= '0;
                        state <= S_SCALE;
                    end
                end

                // Scale all cluster ratios in parallel.
                // Sum the memberships in another cycle.
                S_SCALE: begin
                    for (int i = 0; i < MAX_C; i++) prod_q[i] <= scale_product[i];
                    state <= S_SCALE_SHIFT;
                end

                S_SCALE_SHIFT: begin
                    for (int i = 0; i < MAX_C; i++)
                        member[i] <= (NUMC_W'(i) < k_active)
                                     ? member_t'(prod_q[i] >> NORM_GUARD)
                                     : '0;
                    state <= S_SCALE_SUM;
                end

                // Use integer addition to combine the membership values.
                S_SCALE_SUM: begin
                    member_sum <= member_sum_comb;
                    state      <= S_RESIDUAL;
                end

                // Give any missing units to the cluster with the largest ratio,
                // so the membership sum is exactly 2^M.
                S_RESIDUAL: begin
                    if (member_sum > RATIO_SUM_W'(ONE_Q)) begin
                        contract_error <= 1'b1;
                    end else begin
                        member[best_idx] <= member[best_idx] +
                            member_t'(RATIO_SUM_W'(ONE_Q) - member_sum);
                    end
                    state <= S_DONE;
                end

                S_DONE: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
