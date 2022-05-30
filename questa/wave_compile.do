set SOURCE_DIR ../vhdl
set SIM_LIB_DIR ../vivado/wave_array/wave_array.cache/compile_simlib/questa

vcom -2008 -work wave $SOURCE_DIR/wave_array_pkg.vhd
vcom -2008 -work wave $SOURCE_DIR/midi_pkg.vhd
vcom -2008 -work wave $SOURCE_DIR/clk_subsystem.vhd
vcom -2008 -work wave $SOURCE_DIR/input_subsystem.vhd
vcom -2008 -work wave $SOURCE_DIR/seven_segment.vhd
vcom -2008 -work wave $SOURCE_DIR/uart_rx.vhd
vcom -2008 -work wave $SOURCE_DIR/uart_tx.vhd
vcom -2008 -work wave $SOURCE_DIR/uart_transmitter.vhd
vcom -2008 -work wave $SOURCE_DIR/sample_uart.vhd
vcom -2008 -work wave $SOURCE_DIR/midi_reader.vhd
vcom -2008 -work wave $SOURCE_DIR/midi_receiver.vhd
vcom -2008 -work wave $SOURCE_DIR/midi_slave.vhd
vcom -2008 -work wave $SOURCE_DIR/midi_tester.vhd
vcom -2008 -work wave $SOURCE_DIR/i2s_serializer.vhd
vcom -2008 -work wave $SOURCE_DIR/i2s_interface.vhd
vcom -2008 -work wave $SOURCE_DIR/osc_coeff_memory.vhd
vcom -2008 -work wave $SOURCE_DIR/osc_wave_memory.vhd
vcom -2008 -work wave $SOURCE_DIR/table_address_generator.vhd
vcom -2008 -work wave $SOURCE_DIR/table_interpolator.vhd
vcom -2008 -work wave $SOURCE_DIR/halfband_filter.vhd
vcom -2008 -work wave $SOURCE_DIR/oscillator.vhd
vcom -2008 -work wave $SOURCE_DIR/tb_oscillator.vhd
vcom -2008 -work wave $SOURCE_DIR/osc_controller.vhd
vcom -2008 -work wave $SOURCE_DIR/mixer.vhd
vcom -2008 -work wave $SOURCE_DIR/synth_subsystem.vhd
vcom -2008 -work wave $SOURCE_DIR/wave_array.vhd
vcom -2008 -work wave $SOURCE_DIR/tb_wave_array.vhd
