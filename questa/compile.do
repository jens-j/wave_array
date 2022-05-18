set SOURCE_DIR ../vhdl
set SIM_LIB_DIR ../vivado/wave_array/wave_array.cache/compile_simlib/questa

#vlib wave
#vlib ip
#vmap unisim $SIM_LIB_DIR/unisim

#vcom -2008 -work ip $SOURCE_DIR/ip/adc_mul_gen_sim_netlist.vhdl
#vcom -2008 -work ip $SOURCE_DIR/ip/halfband_macc_gen_sim_netlist.vhdl
#vcom -2008 -work ip $SOURCE_DIR/ip/osc_interpolation_gen_sim_netlist.vhdl
#vcom -2008 -work ip $SOURCE_DIR/ip/osc_macc_gen_sim_netlist.vhdl
#vcom -2008 -work ip $SOURCE_DIR/ip/osc_wave_memory_gen_sim_netlist.vhdl
#vcom -2008 -work ip $SOURCE_DIR/ip/osc_coeff_memory_gen_sim_netlist.vhdl

vcom -2008 -work wave $SOURCE_DIR/wave_array_pkg.vhd
vcom -2008 -work wave $SOURCE_DIR/midi_pkg.vhd
vcom -2008 -work wave $SOURCE_DIR/table_address_generator.vhd
vcom -2008 -work wave $SOURCE_DIR/table_interpolator.vhd
vcom -2008 -work wave $SOURCE_DIR/halfband_filter.vhd
vcom -2008 -work wave $SOURCE_DIR/oscillator.vhd
vcom -2008 -work wave $SOURCE_DIR/tb_oscillator.vhd
