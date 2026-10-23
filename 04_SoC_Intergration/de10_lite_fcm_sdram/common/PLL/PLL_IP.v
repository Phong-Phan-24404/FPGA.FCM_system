// Compatibility wrapper around the DE10-Lite MAX 10 PLL reference IP.
// CLOCK_50 (50 MHz) -> outclk_0 (50 MHz), via clk0_divide_by = 1 in
// VGA_Audio_PLL.v. It was 25 MHz (divide_by = 2) while the FCM core was the
// old Q16.16 design; the V4 core closes well above 50 MHz standalone, so the
// divide was pure lost throughput.
//
// The PLL is kept rather than wiring MAX10_CLK1_50 straight through: it is
// what provides `locked` for the FCM reset, and it keeps the FCM clock a
// separate TimeQuest clock, so the clock-domain crossing into the 50 MHz
// image path stays explicit instead of silently becoming same-clock.
module PLL_IP (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire locked
);

    VGA_Audio_PLL pll_max10 (
        .areset (rst),
        .inclk0 (refclk),
        .c0     (outclk_0),
        .c1     (),
        .c2     (),
        .locked (locked)
    );

endmodule
