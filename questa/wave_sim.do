quit -sim
vsim -voptargs="+acc" -t ps tb_wave_array

add wave -divider top:
add wave tb_wave_array/wave_array/*
add wave -divider clk_subsys:
add wave tb_wave_array/wave_array/clk_subsys/*
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
add wave -divider uart_subsys:
add wave tb_wave_array/wave_array/uart_subsys/*
add wave -divider packet_engine:
add wave tb_wave_array/wave_array/uart_subsys/packet_engine/*
add wave -divider regfile:
add wave tb_wave_array/wave_array/reg_file/*
add wave -divider sdram_arbiter:
add wave tb_wave_array/wave_array/arbiter/*
add wave -divider sdram_controller:
add wave tb_wave_array/wave_array/arbiter/sdram_controller/*
add wave -divider sdram:
add wave tb_wave_array/sdram/*
add wave -divider uart_tester:
add wave tb_wave_array/uart_tester/*
add wave -divider uart_reader:
add wave tb_wave_array/uart_tester/reader/*

run 10 ms
