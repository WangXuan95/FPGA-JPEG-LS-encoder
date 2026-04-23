# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com

# Constraints for jls_encoder on Arty A7-100T (xc7a100tcsg324-1)
# Timing-closure target: 66.67 MHz (15 ns period)
# The 100 MHz on-board oscillator is NOT used here — this is an IP core
# that gets clocked by whatever system clock the user connects.  We set
# a 15 ns (66.67 MHz) virtual clock as the primary target.
# To test at a more aggressive goal, change the period below.

create_clock -name clk -period 16.000 [get_ports clk]

# Input setup/hold: assume inputs are registered in the upstream fabric
# one clock before they arrive, so use a reasonable IOB model.
set_input_delay  -clock clk -max 2.0 [get_ports {rstn i_sof i_e i_x[*] i_w[*] i_h[*]}]
set_input_delay  -clock clk -min 0.5 [get_ports {rstn i_sof i_e i_x[*] i_w[*] i_h[*]}]

# Output delay: downstream logic is also fabric-registered
set_output_delay -clock clk -max 2.0 [get_ports {o_e o_last o_data[*]}]
set_output_delay -clock clk -min 0.5 [get_ports {o_e o_last o_data[*]}]
