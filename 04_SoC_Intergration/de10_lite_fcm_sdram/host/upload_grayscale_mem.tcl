# Run with Quartus System Console after programming the FPGA:
#   C:/altera_lite/25.1std/quartus/sopc_builder/bin/system-console.exe --script upload_grayscale_mem.tcl
# Optional first argument: a different 450x450 8-bit hexadecimal .mem file.

set mem_file ""
foreach candidate [list \
    [file normalize [file join [file dirname [info script]] .. mem input_grayscale.mem]] \
    [file normalize [file join [pwd] mem input_grayscale.mem]] \
    [file normalize [file join [pwd] .. mem input_grayscale.mem]]] {
    if {[file exists $candidate]} {
        set mem_file $candidate
        break
    }
}
if {$argc >= 1} {
    set mem_file [file normalize [lindex $argv 0]]
}

if {![file exists $mem_file]} {
    error "Image file not found: $mem_file"
}
puts "Using input image: $mem_file"

set master_paths [get_service_paths master]
if {[llength $master_paths] == 0} {
    error "No JTAG Avalon Master found. Program the SOF and check the USB-Blaster connection."
}
set master [lindex $master_paths 0]
open_service master $master

set fh [open $mem_file r]
set pixels {}
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} { continue }
    if {![regexp {^[0-9A-Fa-f]{2}$} $line]} {
        close $fh
        error "Invalid grayscale byte '$line' in $mem_file"
    }
    scan $line %x pixel
    lappend pixels $pixel
}
close $fh

if {[llength $pixels] != 202500} {
    error "Expected exactly 202500 grayscale bytes (450x450), found [llength $pixels]"
}

# Avalon byte addresses: 0 = DATA, 4 = CONTROL, 8 = STATUS.
master_write_32 $master 4 0x00000001
set words [expr {[llength $pixels] / 4}]
for {set i 0} {$i < $words} {incr i} {
    set p0 [lindex $pixels [expr {4*$i + 0}]]
    set p1 [lindex $pixels [expr {4*$i + 1}]]
    set p2 [lindex $pixels [expr {4*$i + 2}]]
    set p3 [lindex $pixels [expr {4*$i + 3}]]
    set word [expr {$p0 | ($p1 << 8) | ($p2 << 16) | ($p3 << 24)}]
    master_write_32 $master 0 $word
    if {(($i + 1) % 4096) == 0} {
        puts "Uploaded [expr {$i + 1}] / $words Avalon words"
    }
}

set timeout_ms 30000
set elapsed_ms 0
while {1} {
    set status [lindex [master_read_32 $master 8 1] 0]
    if {$status & 0x10} { error "SDRAM image upload reported an error (status=0x[format %08X $status])" }
    if {$status & 0x1} { break }
    if {$elapsed_ms >= $timeout_ms} { error "Timed out waiting for SDRAM commit (status=0x[format %08X $status])" }
    after 10
    incr elapsed_ms 10
}

puts "PASS: uploaded 450x450 grayscale image to SDRAM (status=0x[format %08X $status]). Select K then press KEY1 to run FCM."
close_service master $master
