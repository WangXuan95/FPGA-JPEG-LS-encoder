del sim.out dump.vcd
iverilog  -g2005-sv  -o sim.out  tb_jls_encoder.sv  ../RTL/jls_encoder.sv
vvp -n sim.out
del sim.out
pause