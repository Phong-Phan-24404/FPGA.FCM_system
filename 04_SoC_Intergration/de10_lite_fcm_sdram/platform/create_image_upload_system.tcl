package require -exact qsys 15.0

create_system image_upload_system
set_project_property DEVICE_FAMILY "MAX 10"
set_project_property DEVICE "10M50DAF484C7G"

add_instance clk_0 clock_source
set_instance_parameter_value clk_0 clockFrequency {50000000}
set_instance_parameter_value clk_0 clockFrequencyKnown {true}
set_instance_parameter_value clk_0 resetSynchronousEdges {NONE}

add_instance jtag_master altera_jtag_avalon_master
set_instance_parameter_value jtag_master USE_PLI {0}
# The standard bridge is sufficient for one-time image loading and avoids the
# much larger experimental high-throughput transaction FIFO.
set_instance_parameter_value jtag_master FAST_VER {0}
set_instance_parameter_value jtag_master FIFO_DEPTHS {2}

add_instance image_upload image_upload_avalon_slave

add_connection clk_0.clk jtag_master.clk clock
add_connection clk_0.clk image_upload.clock clock
add_connection clk_0.clk_reset jtag_master.clk_reset reset
add_connection clk_0.clk_reset image_upload.reset reset
add_connection jtag_master.master image_upload.s0 avalon
set_connection_parameter_value jtag_master.master/image_upload.s0 baseAddress {0x00000000}

add_interface clk clock sink
set_interface_property clk EXPORT_OF clk_0.clk_in
add_interface reset reset sink
set_interface_property reset EXPORT_OF clk_0.clk_in_reset
add_interface image_control conduit end
set_interface_property image_control EXPORT_OF image_upload.control

save_system image_upload_system.qsys
