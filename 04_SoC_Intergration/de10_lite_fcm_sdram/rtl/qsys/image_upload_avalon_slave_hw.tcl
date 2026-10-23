package require -exact qsys 15.0

set_module_property NAME image_upload_avalon_slave
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "SDRAM Image Upload Slave"
set_module_property GROUP "Project/SDRAM Image"
set_module_property DESCRIPTION "JTAG Avalon control and pixel ingress for the SDRAM grayscale frame path"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL image_upload_avalon_slave
add_fileset_file ../src/image_upload_avalon_slave.sv SYSTEM_VERILOG PATH ../src/image_upload_avalon_slave.sv TOP_LEVEL_FILE

add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL image_upload_avalon_slave
add_fileset_file ../src/image_upload_avalon_slave.sv SYSTEM_VERILOG PATH ../src/image_upload_avalon_slave.sv TOP_LEVEL_FILE

add_interface clock clock end
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

add_interface s0 avalon end
set_interface_property s0 addressUnits WORDS
set_interface_property s0 associatedClock clock
set_interface_property s0 associatedReset reset
set_interface_property s0 bitsPerSymbol 8
set_interface_property s0 burstOnBurstBoundariesOnly false
set_interface_property s0 burstcountUnits WORDS
set_interface_property s0 linewrapBursts false
set_interface_property s0 maximumPendingReadTransactions 0
set_interface_property s0 readLatency 0
set_interface_property s0 readWaitTime 0
set_interface_property s0 setupTime 0
set_interface_property s0 timingUnits Cycles
set_interface_property s0 writeWaitTime 0
add_interface_port s0 avs_address address Input 3
add_interface_port s0 avs_read read Input 1
add_interface_port s0 avs_write write Input 1
add_interface_port s0 avs_writedata writedata Input 32
add_interface_port s0 avs_byteenable byteenable Input 4
add_interface_port s0 avs_readdata readdata Output 32
add_interface_port s0 avs_waitrequest waitrequest Output 1

add_interface control conduit end
add_interface_port control upload_start_o upload_start Output 1
add_interface_port control upload_pixel_o upload_pixel Output 8
add_interface_port control upload_valid_o upload_valid Output 1
add_interface_port control upload_ready_i upload_ready Input 1
add_interface_port control image_loaded_i image_loaded Input 1
add_interface_port control upload_busy_i upload_busy Input 1
add_interface_port control upload_error_i upload_error Input 1
add_interface_port control stream_start_o stream_start Output 1
add_interface_port control stream_busy_i stream_busy Input 1
add_interface_port control stream_done_i stream_done Input 1
add_interface_port control stream_error_i stream_error Input 1
add_interface_port control stream_parity_i stream_parity Input 1
