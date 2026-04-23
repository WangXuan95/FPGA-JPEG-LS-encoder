# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com

set SYNTH_DIR [file normalize [file dirname [info script]]]
set OUT_DIR [file normalize $SYNTH_DIR/vivado_out_orig]
file mkdir $OUT_DIR

create_project -in_memory -part xc7a100tcsg324-1
set_property DEFAULT_LIB work [current_project]
read_verilog  [file normalize $SYNTH_DIR/jls_encoder_orig.v]
read_xdc      [file normalize $SYNTH_DIR/jls_encoder.xdc]

synth_design -top jls_encoder -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt -directive PerformanceOptimized
write_checkpoint -force "$OUT_DIR/post_synth.dcp"

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force "$OUT_DIR/post_route.dcp"

report_utilization  -hierarchical -file "$OUT_DIR/utilization_route.rpt"
report_timing_summary -max_paths 20 -report_unconstrained -warn_on_violation -file "$OUT_DIR/timing_route.rpt"
report_timing -from [all_registers -output_pins] -to [all_registers -input_pins] -max_paths 5 -sort_by slack -file "$OUT_DIR/timing_worst_paths.rpt"
