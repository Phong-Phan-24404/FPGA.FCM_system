// File: terasic_sdram_controller.sv
// Description: Connects the SDRAM controller to the board memory pins.
// Author: Phan Chau Phong

// Module: terasic_sdram_controller
// Description: Wraps the Terasic SDRAM controller and exposes the read/write interface.

module terasic_sdram_controller (
    input  logic        ref_clk_50,
    input  logic        reset_n,
    input  logic        client_clk,

    input  logic [15:0] write_data,
    input  logic        write_valid,
    input  logic [24:0] write_start_word_addr,
    input  logic [24:0] write_max_word_addr,
    input  logic [8:0]  write_burst_words,
    input  logic        write_load,
    input  logic        write_enable,
    output logic        write_full,
    output logic [15:0] write_used_words,

    output logic [15:0] read_data,
    input  logic        read_ready,
    input  logic [24:0] read_start_word_addr,
    input  logic [24:0] read_max_word_addr,
    input  logic [8:0]  read_burst_words,
    input  logic        read_load,
    input  logic        read_enable,
    output logic        read_empty,
    output logic [15:0] read_used_words,

    output logic        controller_clk_100,
    output logic        controller_locked,
    output logic [12:0] dram_addr,
    output logic [1:0]  dram_ba,
    output logic        dram_cas_n,
    output logic        dram_cke,
    output logic        dram_clk,
    output logic        dram_cs_n,
    inout  wire  [15:0] dram_dq,
    output logic        dram_ldqm,
    output logic        dram_ras_n,
    output logic        dram_udqm,
    output logic        dram_we_n
);

    logic [1:0] dram_cs_n_internal;
    logic [1:0] dram_dqm;

    assign dram_cs_n = dram_cs_n_internal[0];
    assign dram_ldqm = dram_dqm[0];
    assign dram_udqm = dram_dqm[1];

    Sdram_Control u_sdram_control (
        .REF_CLK     (ref_clk_50),
        .RESET_N     (reset_n),
        .CLK         (controller_clk_100),
        .WR_DATA     (write_data),
        .WR          (write_valid),
        .WR_ADDR     (write_start_word_addr),
        .WR_MAX_ADDR (write_max_word_addr),
        .WR_LENGTH   (write_burst_words),
        .WR_LOAD     (write_load),
        .WR_ENABLE   (write_enable),
        .WR_CLK      (client_clk),
        .WR_FULL     (write_full),
        .WR_USE      (write_used_words),
        .RD_DATA     (read_data),
        .RD          (read_ready),
        .RD_ADDR     (read_start_word_addr),
        .RD_MAX_ADDR (read_max_word_addr),
        .RD_LENGTH   (read_burst_words),
        .RD_LOAD     (read_load),
        .RD_ENABLE   (read_enable),
        .RD_CLK      (client_clk),
        .RD_EMPTY    (read_empty),
        .RD_USE      (read_used_words),
        .SA          (dram_addr),
        .BA          (dram_ba),
        .CS_N        (dram_cs_n_internal),
        .CKE         (dram_cke),
        .RAS_N       (dram_ras_n),
        .CAS_N       (dram_cas_n),
        .WE_N        (dram_we_n),
        .DQ          (dram_dq),
        .DQM         (dram_dqm),
        .SDR_CLK     (dram_clk),
        .PLL_LOCKED  (controller_locked)
    );

endmodule
