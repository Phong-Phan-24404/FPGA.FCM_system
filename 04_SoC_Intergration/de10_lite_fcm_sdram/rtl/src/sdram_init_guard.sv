// File: sdram_init_guard.sv
// Description: Keeps SDRAM clients in reset while the memory clock starts up.
// Author: Phan Chau Phong

// Module: sdram_init_guard
// Description: Waits for the PLL lock and a startup delay before enabling clients.

module sdram_init_guard #(
    parameter int GUARD_CYCLES = 13000
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic pll_locked_i,
    output logic client_rst_n_o,
    output logic ready_o
);
    localparam int COUNT_W = $clog2(GUARD_CYCLES + 1);
    logic [COUNT_W-1:0] count_q;

    assign client_rst_n_o = rst_n_i && ready_o;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            count_q <= '0;
            ready_o <= 1'b0;
        end else if (!pll_locked_i) begin
            count_q <= '0;
            ready_o <= 1'b0;
        end else if (!ready_o) begin
            if (count_q == GUARD_CYCLES - 1)
                ready_o <= 1'b1;
            else
                count_q <= count_q + 1'b1;
        end
    end
endmodule
