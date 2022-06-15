quit -sim
vsim -novopt -t ps tb_wave_array

add wave -divider top:
add wave tb_wave_array/wave_array/*
add wave -divider i2s:
add wave tb_wave_array/wave_array/i2s_interface/*
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
add wave -divider sample_uart:
add wave tb_wave_array/wave_array/synth_subsys/sample_uart/*

run 10 ms
