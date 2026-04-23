# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com

# ---------------------------------------------------------------------------
# run_synth.tcl  —  Vivado batch synthesis + implementation for jls_encoder
# Target board : Arty A7-100T  (xc7a100tcsg324-1)
# Usage        : vivado -mode batch -source run_synth.tcl
#                (run from the SYNTH directory, or adjust paths below)
# Outputs written to ./vivado_out/
# ---------------------------------------------------------------------------

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set RTL_FILE   [file normalize "$SCRIPT_DIR/../RTL/jls_encoder.v"]
set XDC_FILE   [file normalize "$SCRIPT_DIR/jls_encoder.xdc"]
set OUT_DIR    "$SCRIPT_DIR/vivado_out"

file mkdir $OUT_DIR

# ---------------------------------------------------------------------------
# 1. Create in-memory project
# ---------------------------------------------------------------------------
create_project -in_memory -part xc7a100tcsg324-1

set_property PART xc7a100tcsg324-1 [current_project]
set_property DEFAULT_LIB work       [current_project]

read_verilog $RTL_FILE
read_xdc     $XDC_FILE

# ---------------------------------------------------------------------------
# 2. Synthesis
# ---------------------------------------------------------------------------
puts ""
puts "================================================================"
puts "  SYNTHESIS"
puts "================================================================"
synth_design \
    -top  jls_encoder \
    -part xc7a100tcsg324-1 \
    -flatten_hierarchy rebuilt \
    -directive PerformanceOptimized

write_checkpoint -force "$OUT_DIR/post_synth.dcp"
report_utilization  -file "$OUT_DIR/utilization_synth.rpt"
report_timing_summary -file "$OUT_DIR/timing_synth.rpt" -max_paths 10

# ---------------------------------------------------------------------------
# 3. Implementation: opt → place → route
# ---------------------------------------------------------------------------
puts ""
puts "================================================================"
puts "  OPT + PLACE + ROUTE"
puts "================================================================"
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force "$OUT_DIR/post_route.dcp"

# ---------------------------------------------------------------------------
# 4. Final reports  (the ones that matter for timing closure)
# ---------------------------------------------------------------------------
puts ""
puts "================================================================"
puts "  REPORTS"
puts "================================================================"

report_utilization  -hierarchical \
                    -file "$OUT_DIR/utilization_route.rpt"

report_timing_summary \
    -max_paths 20 \
    -report_unconstrained \
    -warn_on_violation \
    -file "$OUT_DIR/timing_route.rpt"

report_timing_summary \
    -max_paths 5 \
    -file "$OUT_DIR/timing_worst_paths.rpt"

report_clock_utilization -file "$OUT_DIR/clock_util.rpt"
report_power             -file "$OUT_DIR/power.rpt"

# ---------------------------------------------------------------------------
# 5. Print summary to console
# ---------------------------------------------------------------------------
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
# TNS isn't a timing_path property; parse it out of the design timing summary.
set tsum [report_timing_summary -no_header -no_detailed_paths -return_string -quiet]
if {[regexp {TNS\s*\(ns\)[^\n]*\n[^\n]*\n\s*([-\d.]+)\s+([-\d.]+)} $tsum _ _wns _tns]} {
    set tns $_tns
} else { set tns 0.000 }

puts ""
puts "================================================================"
puts "  RESULT SUMMARY"
puts "================================================================"
puts "  Device     : xc7a100tcsg324-1 (Arty A7-100T)"
puts "  Clock target: 16.000 ns  (62.50 MHz)"
puts ""
puts "  Worst Negative Slack (WNS) : $wns ns"
puts "  Total Negative Slack (TNS) : $tns ns"

if {$wns >= 0} {
    set fmax_ns [expr {16.000 - $wns}]
    set fmax_mhz [expr {1000.0 / $fmax_ns}]
    puts "  => TIMING MET"
    puts "  => Estimated Fmax : [format %.1f $fmax_mhz] MHz  (margin [format %.3f $wns] ns)"
} else {
    set fmax_ns [expr {16.000 - $wns}]
    set fmax_mhz [expr {1000.0 / $fmax_ns}]
    puts "  => TIMING NOT MET  (need to increase clock period or optimize)"
    puts "  => Achievable Fmax : [format %.1f $fmax_mhz] MHz  (at WNS [format %.3f $wns] ns)"
}
puts "================================================================"
puts ""
puts "Full reports in: $OUT_DIR"
