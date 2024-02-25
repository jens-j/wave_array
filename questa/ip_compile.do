set SOURCE_DIR ../vhdl

set SIM_LIB_DIR ../vivado/wave_array/wave_array.cache/compile_simlib/questa

vmap unisim $SIM_LIB_DIR/unisim

vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/sys_clk_generator_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/i2s_clk_generator_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/i2s_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/uart_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/sdram_uart_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/uart_sdram_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/midi_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/adc_mul_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/halfband_macc_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/osc_interpolation_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/osc_macc_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/osc_wave_memory_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/envelope_cordic_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/envelope_mult_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/cordic_lfo_sine_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/wave_uart_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/svf_macc_gen_sim_netlist.vhdl


#vlog -work cellram $SOURCE_DIR/ip/cellram.v
