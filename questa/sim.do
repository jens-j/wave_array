quit -sim
vsim -novopt -t ps tb_oscillator

add wave -divider table_address_generator:
add wave tb_oscillator/dut/table_addr_gen/*
add wave -divider table_interpolator:
add wave tb_oscillator/dut/table_interpolator/*
add wave -divider halfband_filter:
add wave tb_oscillator/dut/halfband/*

run 100 us
