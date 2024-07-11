quit -sim
vsim -L unisims_ver -L unisim -L secureip -voptargs="+acc" -t ps xil_defaultlib.glbl wave.tb_wave_array(arch_with_sdram)

add wave -divider tb:
add wave tb_wave_array/*
add wave -divider top:
add wave tb_wave_array/wave_array/*
add wave -divider clk_subsys:
add wave tb_wave_array/wave_array/clk_subsys/*
add wave -divider reset_subsys:
add wave tb_wave_array/wave_array/reset_subsys/*
add wave -divider i2s:
add wave tb_wave_array/wave_array/i2s_interface/*
add wave -divider midi:
add wave tb_wave_array/wave_array/midi_slave/*
add wave -divider synth_subsys:
add wave tb_wave_array/wave_array/synth_subsys/*
add wave -divider osc_controller:
add wave tb_wave_array/wave_array/synth_subsys/osc_controller/*
add wave -divider oscillator:
add wave tb_wave_array/wave_array/synth_subsys/osc_subsys/osc_gen(0)/osc_n/*
add wave -divider address_generator:
add wave tb_wave_array/wave_array/synth_subsys/osc_subsys/osc_gen(0)/osc_n/table_addr_gen/*
add wave -divider table_interpolator:
add wave tb_wave_array/wave_array/synth_subsys/osc_subsys/osc_gen(0)/osc_n/table_interpolator/*
add wave -divider halfband:
add wave tb_wave_array/wave_array/synth_subsys/osc_subsys/osc_gen(0)/osc_n/halfband/*
add wave -divider mixer:
add wave tb_wave_array/wave_array/synth_subsys/voice_mixer_subsys/*
add wave -divider envelope:
add wave tb_wave_array/wave_array/synth_subsys/envelope/*
add wave -divider lfo:
add wave tb_wave_array/wave_array/synth_subsys/lfo/*
add wave -divider mod_matrix:
add wave tb_wave_array/wave_array/synth_subsys/mod_matrix/*
add wave -divider frame_dma:
add wave tb_wave_array/wave_array/synth_subsys/frame_dma/*
add wave -divider uart_subsys:
add wave tb_wave_array/wave_array/uart_subsys/*
add wave -divider packet_engine:
add wave tb_wave_array/wave_array/uart_subsys/packet_engine/*
add wave -divider regfile:
add wave tb_wave_array/wave_array/reg_file/*
add wave -divider sdram_arbiter:
add wave tb_wave_array/wave_array/arbiter/*
add wave -divider flash_interface:
add wave tb_wave_array/wave_array/qspi_if/*
add wave -divider flash_dma:
add wave tb_wave_array/wave_array/flash_dma/*
#add wave -divider sdram:
#add wave tb_wave_array/sdram/*
add wave -divider uart_tester:
add wave tb_wave_array/uart_tester/*
add wave -divider uart_reader:
add wave tb_wave_array/uart_tester/reader/*

run 10 ms
