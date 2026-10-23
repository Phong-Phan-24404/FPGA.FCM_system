// File: fcm_divider.sv
// Description: Provides an unsigned integer divider for the FCM datapath.
// Author: Phan Chau Phong
// Module: fcm_divider
// Description: Calculates a quotient and remainder with restoring division.
// It supports different operand widths and radix-2 or radix-4 steps.
// The divider skips leading quotient zeros using the highest set bits.
// The quotient is rounded down, matching integer division.
// A zero denominator sets div_by_zero and returns an all-ones quotient.
// The overflow flag indicates a quotient that does not fit QUOT_W.

module fcm_divider #(
    parameter int NUM_W  = 32,   // numerator width
    parameter int DEN_W  = 32,   // denominator width
    parameter int QUOT_W = 32,   // quotient width
    // RADIX=2 produces one quotient bit per cycle.
    // RADIX=4 produces two bits by comparing against 1x, 2x, and 3x the divisor.
    // Both modes use the same unsigned integer division rule.
    parameter int RADIX  = 2
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [NUM_W-1:0]   numerator,
    input  logic [DEN_W-1:0]   denominator,
    output logic [QUOT_W-1:0]  quotient,
    output logic [DEN_W-1:0]   remainder,
    output logic               busy,
    output logic               done,
    output logic               div_by_zero,
    // Set overflow if the full quotient does not fit the output width.
    output logic               overflow
);

    localparam int STEP_W = $clog2(NUM_W + 1);
    // Keep enough bits for the numerator index and the skipped-bit count.
    localparam int PTR_W  = (NUM_W > 1) ? $clog2(NUM_W) : 1;
    localparam int SKIP_W = $clog2(NUM_W + 1) + 1;
    // Select a valid bit range for checking truncated quotient bits.
    // If QUOT_W is large enough, the overflow condition is disabled.
    localparam int OVF_LOW = (NUM_W > QUOT_W) ? QUOT_W : (NUM_W - 1);
    // Allow an extra remainder bit for radix-2 and two bits for radix-4.
    // The shifted remainder can be up to 2x or 4x the denominator.
    localparam int REM_W  = (RADIX == 4) ? (DEN_W + 2) : (DEN_W + 1);

    typedef enum logic [2:0] {D_IDLE, D_LZC, D_ALIGN, D_RUN, D_DONE} state_t;
    state_t state;

    logic [NUM_W-1:0]  num_reg;
    logic [NUM_W-1:0]  quot_acc;
    logic [REM_W-1:0]  rem_acc;
    logic [DEN_W-1:0]  den_reg;
    logic [STEP_W-1:0] step;
    logic [PTR_W-1:0]  ptr;
    logic              zero_den;
    logic              skip_all;
    // If the quotient has an odd number of bits, start with one radix-2
    // step before using pairs of bits for radix-4.
    logic              odd_first;
    logic [REM_W-1:0]  den3_reg;

    // Find the highest set bit of each operand.
    logic [SKIP_W-1:0] p_skip;

    always_comb begin
        automatic int unsigned msb_num = 0;
        automatic int unsigned msb_den = 0;
        automatic bit          num_zero = 1'b1;
        // Keep the highest set-bit index found in the loop.
        for (int i = 0; i < NUM_W; i++)
            if (num_reg[i]) begin
                msb_num  = i;
                num_zero = 1'b0;
            end
        for (int i = 0; i < DEN_W; i++)
            if (den_reg[i]) msb_den = i;

        if (num_zero)
            p_skip = SKIP_W'(NUM_W);
        else if (((NUM_W - 1 - msb_num) + msb_den) >= NUM_W)
            p_skip = SKIP_W'(NUM_W);
        else
            p_skip = SKIP_W'((NUM_W - 1 - msb_num) + msb_den);
    end

    // Calculate one restoring-division step.
    logic [REM_W-1:0] rem_shifted;
    logic [REM_W-1:0] rem_minus;
    logic             rem_fits;

    always_comb begin
        rem_shifted = {rem_acc[REM_W-2:0], num_reg[ptr]};
        rem_minus   = rem_shifted - REM_W'(den_reg);
        rem_fits    = (rem_shifted >= REM_W'(den_reg));
    end

    // Calculate two quotient bits in one radix-4 step.
    // Compare the shifted remainder with 3x, 2x, and 1x the denominator.
    // The chosen digit is 0, 1, 2, or 3.
    logic [REM_W-1:0] rem4_shifted;
    logic [REM_W-1:0] rem4_next;
    logic [1:0]       q4_digit;
    logic             num_bit_lo;

    always_comb begin
        // Guard the lower bit index so simulation cannot read outside the vector.
        num_bit_lo   = (ptr >= PTR_W'(1)) ? num_reg[ptr - PTR_W'(1)] : 1'b0;
        rem4_shifted = {rem_acc[REM_W-3:0], num_reg[ptr], num_bit_lo};

        if (rem4_shifted >= den3_reg) begin
            q4_digit  = 2'd3;
            rem4_next = rem4_shifted - den3_reg;
        end else if (rem4_shifted >= (REM_W'(den_reg) << 1)) begin
            q4_digit  = 2'd2;
            rem4_next = rem4_shifted - (REM_W'(den_reg) << 1);
        end else if (rem4_shifted >= REM_W'(den_reg)) begin
            q4_digit  = 2'd1;
            rem4_next = rem4_shifted - REM_W'(den_reg);
        end else begin
            q4_digit  = 2'd0;
            rem4_next = rem4_shifted;
        end
    end

    assign busy = (state != D_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= D_IDLE;
            num_reg     <= '0;
            quot_acc    <= '0;
            rem_acc     <= '0;
            den_reg     <= '0;
            step        <= '0;
            ptr         <= '0;
            zero_den    <= 1'b0;
            skip_all    <= 1'b0;
            odd_first   <= 1'b0;
            den3_reg    <= '0;
            quotient    <= '0;
            remainder   <= '0;
            done        <= 1'b0;
            div_by_zero <= 1'b0;
            overflow    <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                D_IDLE: begin
                    if (start) begin
                        num_reg  <= numerator;
                        den_reg  <= denominator;
                        quot_acc <= '0;
                        rem_acc  <= '0;
                        zero_den <= (denominator == '0);
                        skip_all <= 1'b0;
                        // Save three times the denominator for radix-4 comparisons.
                        den3_reg <= REM_W'(denominator) + (REM_W'(denominator) << 1);
                        state    <= D_LZC;
                    end
                end

                // Find how many quotient bits need to be calculated.
                D_LZC: begin
                    if (zero_den) begin
                        state <= D_DONE;
                    end else begin
                        automatic int steps2 = NUM_W - int'(p_skip);
                        skip_all <= (p_skip >= SKIP_W'(NUM_W));
                        ptr      <= (p_skip >= SKIP_W'(NUM_W))
                                    ? PTR_W'(0)
                                    : PTR_W'(NUM_W - 1 - int'(p_skip));
                        if (RADIX == 4) begin
                            // Process the first bit separately if the number of bits is odd.
                            // The remaining radix-4 steps read two input bits at a time.
                            odd_first <= steps2[0];
                            step      <= STEP_W'((steps2 + 1) >> 1);
                        end else begin
                            odd_first <= 1'b0;
                            step      <= STEP_W'(steps2);
                        end
                        state <= D_ALIGN;
                    end
                end

                // Load the remainder from the skipped leading numerator bits.
                D_ALIGN: begin
                    if (skip_all) begin
                        // If the numerator is smaller than the denominator, the quotient is
                        // zero and the remainder is the numerator.
                        rem_acc <= REM_W'(num_reg);
                        state   <= D_DONE;
                    end else begin
                        rem_acc <= REM_W'(num_reg >> (int'(ptr) + 1));
                        state   <= D_RUN;
                    end
                end

                D_RUN: begin
                    // RADIX is a constant, so synthesis only keeps the selected path.
                    if ((RADIX == 4) && !odd_first) begin
                        quot_acc <= {quot_acc[NUM_W-3:0], q4_digit};
                        rem_acc  <= rem4_next;
                        if (ptr >= PTR_W'(2)) ptr <= ptr - PTR_W'(2);
                        else                  ptr <= PTR_W'(0);
                    end else begin
                        quot_acc  <= {quot_acc[NUM_W-2:0], rem_fits};
                        rem_acc   <= rem_fits ? rem_minus : rem_shifted;
                        if (ptr != PTR_W'(0)) ptr <= ptr - PTR_W'(1);
                        odd_first <= 1'b0;
                    end
                    step <= step - STEP_W'(1);
                    if (step == STEP_W'(1)) state <= D_DONE;
                end

                D_DONE: begin
                    if (zero_den) begin
                        quotient    <= {QUOT_W{1'b1}};
                        remainder   <= '0;
                        div_by_zero <= 1'b1;
                        overflow    <= 1'b0;
                    end else begin
                        quotient    <= QUOT_W'(quot_acc);
                        remainder   <= DEN_W'(rem_acc);
                        div_by_zero <= 1'b0;
                        // Check whether any quotient bits outside QUOT_W are nonzero.
                        // The skipped leading quotient bits are always zero.
                        overflow    <= (NUM_W > QUOT_W) && (|quot_acc[NUM_W-1:OVF_LOW]);
                    end
                    done  <= 1'b1;
                    state <= D_IDLE;
                end

                default: state <= D_IDLE;
            endcase
        end
    end

endmodule
