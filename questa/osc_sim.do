quit -sim
vsim -novopt -t ps tb_oscillator

add wave -divider table_address_generator:
add wave tb_oscillator/dut/table_addr_gen/*
add wave -divider table_interpolator:
add wave tb_oscillator/dut/table_interpolator/*
add wave -divider halfband_filter:
add wave tb_oscillator/dut/halfband/*
add wave -divider sample_uart:
add wave tb_oscillator/dut/synth_subsys/sample_uart/*

run 100 us
