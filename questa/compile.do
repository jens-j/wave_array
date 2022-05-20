set SOURCE_DIR ../vhdl
set SIM_LIB_DIR ../vivado/wave_array/wave_array.cache/compile_simlib/questa

vcom -2008 -work wave $SOURCE_DIR/wave_array_pkg.vhd
vcom -2008 -work wave $SOURCE_DIR/midi_pkg.vhd
vcom -2008 -work wave $SOURCE_DIR/blockram.vhd
vcom -2008 -work wave $SOURCE_DIR/osc_coeff_memory.vhd
vcom -2008 -work wave $SOURCE_DIR/osc_wave_memory.vhd
vcom -2008 -work wave $SOURCE_DIR/table_address_generator.vhd
vcom -2008 -work wave $SOURCE_DIR/table_interpolator.vhd
vcom -2008 -work wave $SOURCE_DIR/halfband_filter.vhd
vcom -2008 -work wave $SOURCE_DIR/oscillator.vhd
vcom -2008 -work wave $SOURCE_DIR/tb_oscillator.vhd
