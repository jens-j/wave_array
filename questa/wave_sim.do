quit -sim
vsim -novopt -t ps tb_wave_array

add wave -divider top:
add wave tb_wave_array/wave_array/*
add wave -divider i2s:
add wave tb_wave_array/wave_array/i2s_interface/*
add wave -divider i2s_clk_enable:
add wave tb_wave_array/wave_array/i2s_interface/clk_enable/*
add wave -divider midi:
add wave tb_wave_array/wave_array/midi_slave/*
add wave -divider osc_controller:
add wave tb_wave_array/wave_array/synth_subsys/osc_controller/*
add wave -divider oscillator:
add wave tb_wave_array/wave_array/synth_subsys/oscillator/*
add wave -divider address_generator:
add wave tb_wave_array/wave_array/synth_subsys/oscillator/table_addr_gen/*
add wave -divider table_interpolator:
add wave tb_wave_array/wave_array/synth_subsys/oscillator/table_interpolator/*
add wave -divider halfband:
add wave tb_wave_array/wave_array/synth_subsys/oscillator/halfband/*
add wave -divider mixer:
add wave tb_wave_array/wave_array/synth_subsys/mixer/*

run 100 ms
