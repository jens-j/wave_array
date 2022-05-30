set SOURCE_DIR ../vhdl
set SIM_LIB_DIR ../vivado/wave_array/wave_array.cache/compile_simlib/questa

vlib wave
vlib ip

vmap unisim $SIM_LIB_DIR/unisim
vmap fifo_generator_v13_2_5 $SIM_LIB_DIR/fifo_generator_v13_2_5


vcom -2008 -work work $SOURCE_DIR/ip/clk_generator_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/xadc_gen.vhd
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/i2s_fifo.vhd
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/uart_tx_fifo_gen.vhd
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/midi_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/adc_mul_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/halfband_macc_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/osc_interpolation_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/osc_macc_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/osc_wave_memory_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/ip/osc_coeff_memory_gen_sim_netlist.vhdl
