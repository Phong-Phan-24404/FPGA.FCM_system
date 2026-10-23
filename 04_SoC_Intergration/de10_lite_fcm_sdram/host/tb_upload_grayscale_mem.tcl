# Syntax and protocol smoke test for upload_grayscale_mem.tcl.
# Run with: quartus_sh -t host/tb_upload_grayscale_mem.tcl
#
# The mock accepts the 50,625 JTAG writes and reports a committed image.
# SDRAM streaming is started only by the DE10-Lite KEY1 FCM control.

set argc 0
set argv {}
set data_write_count 0
set controls {}
set active_control 0

proc get_service_paths {service} {
    if {$service ne "master"} { error "unexpected service '$service'" }
    return [list mock_master]
}

proc open_service {service master} {
    if {$service ne "master" || $master ne "mock_master"} {
        error "unexpected master service"
    }
}

proc close_service {service master} {}

proc master_write_32 {master address data} {
    global data_write_count controls active_control
    if {$master ne "mock_master"} { error "unexpected master" }
    switch -- $address {
        0 { incr data_write_count }
        4 {
            lappend controls $data
            set active_control $data
        }
        default { error "unexpected write address $address" }
    }
}

proc master_read_32 {master address count} {
    global active_control
    if {$master ne "mock_master" || $address != 8 || $count != 1} {
        error "unexpected status read"
    }
    if {$active_control == 1} { return [list 0x001] }
    error "status read without an upload command"
}

source [file join [file dirname [file normalize [info script]]] upload_grayscale_mem.tcl]

if {$data_write_count != 50625} {
    error "expected 50625 data writes, got $data_write_count"
}
if {[llength $controls] != 1 || [lindex $controls 0] != 1} {
    error "expected only the upload control, got $controls"
}
puts "PASS: upload_grayscale_mem.tcl protocol mock"
