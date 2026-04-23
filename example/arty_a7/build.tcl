# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com

# Vivado batch build for the Arty A7-100T JPEG-LS encoder demo.
# Usage: vivado -mode batch -source build.tcl
#
# Environment:
#   FCAPZ_ROOT — path to fpgacapZero repo (defaults to <repo>/fcapz)

set example_dir [file normalize [file dirname [info script]]]
set jls_root    [file normalize $example_dir/../..]

set default_fcapz_root [file normalize $jls_root/fcapz]
set fcapz_root [expr {[info exists ::env(FCAPZ_ROOT)] ? $::env(FCAPZ_ROOT) : $default_fcapz_root}]
if {![file isdirectory $fcapz_root]} {
    puts "ERROR: fpgacapZero not found at $fcapz_root"
    puts "Set FCAPZ_ROOT or initialize the fcapz submodule"
    exit 1
}

set project_name arty_jls_demo
set project_dir  $example_dir/vivado_out
file mkdir $project_dir

if {[llength [current_project -quiet]] > 0} {
    close_project
}

create_project $project_name $project_dir -part xc7a100tcsg324-1 -force

# ── Source RTL ─────────────────────────────────────────────────
add_files [list \
    $jls_root/RTL/jls_encoder.v \
    $example_dir/rtl/sync_fifo.v \
    $example_dir/rtl/axi_jls_ctrl.v \
    $example_dir/rtl/arty_jls_top.v \
    $fcapz_root/rtl/fcapz_version.vh \
    $fcapz_root/rtl/fcapz_async_fifo.v \
    $fcapz_root/rtl/jtag_reg_iface.v \
    $fcapz_root/rtl/jtag_burst_read.v \
    $fcapz_root/rtl/jtag_tap/jtag_tap_xilinx7.v \
    $fcapz_root/rtl/fcapz_ejtagaxi.v \
    $fcapz_root/rtl/fcapz_ejtagaxi_xilinx7.v \
]

set_property file_type "Verilog Header" [get_files $fcapz_root/rtl/fcapz_version.vh]
set_property is_global_include true     [get_files $fcapz_root/rtl/fcapz_version.vh]

add_files -fileset constrs_1 $example_dir/constraints/arty_jls.xdc

set_property top arty_jls_top [current_fileset]

# ── Synth + impl + bitstream ───────────────────────────────────
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# ── Timing summary ─────────────────────────────────────────────
open_run impl_1
report_timing_summary -file $example_dir/vivado_out/timing_summary.rpt
report_utilization    -file $example_dir/vivado_out/utilization.rpt

file copy -force \
    $project_dir/${project_name}.runs/impl_1/arty_jls_top.bit \
    $example_dir/arty_jls_top.bit

puts "\n=== Build complete: example/arty_a7/arty_jls_top.bit ==="
