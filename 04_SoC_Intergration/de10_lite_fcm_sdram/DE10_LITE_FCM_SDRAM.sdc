#**************************************************************
# This .sdc file is created by Terasic Tool.
# Users are recommended to modify this file to match users logic.
#**************************************************************

#**************************************************************
# Create Clock
#**************************************************************
create_clock -period "10.0 MHz" [get_ports ADC_CLK_10]
create_clock -period "50.0 MHz" [get_ports MAX10_CLK1_50]
create_clock -period "50.0 MHz" [get_ports MAX10_CLK2_50]

#**************************************************************
# Create Generated Clock
#**************************************************************
# SDRAM clock is the -3 ns phase-shifted output of the retained Terasic PLL.
# The name mirrors the reference SDRAM_RTL_Test constraints; the hierarchy is
# updated for the project-local controller wrapper.
create_generated_clock \
    -source [get_pins {sdram_controller|u_sdram_control|sdram_pll0_inst|altpll_component|auto_generated|pll1|clk[1]}] \
    -name clk_dram_ext [get_ports {DRAM_CLK}]
# derive_pll_clocks also creates the FCM compute clock from fcm_pll. That PLL
# produced 25 MHz until 2026-10-20 and now produces 50 MHz (VGA_Audio_PLL.v,
# clk0_divide_by = 1), so the FCM core is constrained at 20 ns here without any
# clock declaration of its own. Do not add a hand-written create_clock for it:
# the PLL parameters are the single source of truth, and a stale literal here
# would silently constrain the core at the wrong period.
#
# The FCM domain and MAX10_CLK1_50 are both 50 MHz and share a reference, so
# TimeQuest analyses the crossings between them as related clocks. They pass
# (FCM domain +2.322 ns setup, 0 failing paths), and the crossings themselves
# go through a dcfifo and a three-flop synchronizer in
# fcm_de10lite_integration.sv. They are deliberately NOT cut with
# set_clock_groups -asynchronous: cutting them would also stop checking any
# future unsynchronised signal added between the two domains.
derive_pll_clocks



#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************
derive_clock_uncertainty

# KEY[0] is an asynchronous board reset. The JTAG pins are clocked by the
# hard JTAG block, and the LEDs are board-status indicators rather than a
# synchronous external interface.
set_false_path -from [get_ports {KEY[0]}]
set_false_path -from [get_ports {KEY[1] SW[*]}]
set_false_path -from [get_ports {altera_reserved_tdi altera_reserved_tms}]
set_false_path -to   [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] altera_reserved_tdo}]



#**************************************************************
# Set Input Delay
#**************************************************************
# DE10-Lite SDRAM timing values retained from Terasic's SDRAM_RTL_Test.
# They include board-trace skew and the external SDRAM device limits.
set_input_delay -max -clock clk_dram_ext 5.9 [get_ports {DRAM_DQ[*]}]
set_input_delay -min -clock clk_dram_ext 3.0 [get_ports {DRAM_DQ[*]}]

# The negative-phase external clock is sampled against the internal 0-degree
# controller clock. The SDRAM RTL reference requires this two-cycle setup path.
set_multicycle_path -from [get_clocks {clk_dram_ext}] \
                    -to [get_clocks {sdram_controller|u_sdram_control|sdram_pll0_inst|altpll_component|auto_generated|pll1|clk[0]}] \
                    -setup 2



#**************************************************************
# Set Output Delay
#**************************************************************
set_output_delay -max -clock clk_dram_ext 1.6 [get_ports {DRAM_DQ[*] DRAM_LDQM DRAM_UDQM}]
set_output_delay -min -clock clk_dram_ext -0.9 [get_ports {DRAM_DQ[*] DRAM_LDQM DRAM_UDQM}]
set_output_delay -max -clock clk_dram_ext 1.6 [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_CKE DRAM_CS_N}]
set_output_delay -min -clock clk_dram_ext -0.9 [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_CKE DRAM_CS_N}]



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************



#**************************************************************
# Set Load
#**************************************************************



