# File: fcm_ip.sdc
# Description: Sets the clock and interface timing constraints for the FCM IP.
# The core uses an external 50 MHz clock with a 20 ns period.
# Input and output delays are set to zero for standalone timing analysis.
# The reset is asynchronous and excluded from register timing paths.
# Board-level timing and clock-domain constraints are defined separately.

create_clock -name fcm_compute -period 20.000 [get_ports {clk}]

derive_clock_uncertainty

# Ignore timing paths from the asynchronous reset to registers.
set_false_path -from [get_ports {rst_n}] -to [all_registers]

# Use zero interface delays to focus on internal register timing.
set_input_delay  -clock fcm_compute 0 [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay -clock fcm_compute 0 [all_outputs]
