// File: fcm_power_on_reset.sv
// Description: Provides the power-on reset signal for board startup.
// Author: Phan Chau Phong

// Module: fcm_power_on_reset
// Description: Holds reset during startup and releases it after the configured delay.

module fcm_power_on_reset #(
    parameter int RESET_CYCLES = 50_000
) (
    input  logic clk_i,
    output logic reset_n_o = 1'b0
);
    localparam int COUNT_W = $clog2(RESET_CYCLES + 1);
    logic [COUNT_W-1:0] count_q = '0;

    always_ff @(posedge clk_i) begin
        if (!reset_n_o) begin
            if (count_q == RESET_CYCLES - 1)
                reset_n_o <= 1'b1;
            else
                count_q <= count_q + 1'b1;
        end
    end
endmodule
