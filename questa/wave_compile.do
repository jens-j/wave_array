set SOURCE_DIR ../vhdl
set SIM_LIB_DIR ../vivado/wave_array/wave_array.cache/compile_simlib/questa

vcom -2008 -work wave $SOURCE_DIR/wave_array_pkg.vhd

vcom -2008 -work i2s $SOURCE_DIR/i2s/i2s_serializer.vhd
vcom -2008 -work i2s $SOURCE_DIR/i2s/i2s_interface.vhd

vcom -2008 -work uart $SOURCE_DIR/uart/uart_pkg.vhd
vcom -2008 -work uart $SOURCE_DIR/uart/uart_rx.vhd
vcom -2008 -work uart $SOURCE_DIR/uart/uart_tx.vhd
vcom -2008 -work uart $SOURCE_DIR/uart/uart_transmitter.vhd
vcom -2008 -work uart $SOURCE_DIR/uart/uart_reader.vhd
vcom -2008 -work uart $SOURCE_DIR/uart/uart_packet_engine.vhd
vcom -2008 -work uart $SOURCE_DIR/uart/uart_subsystem.vhd
vcom -2008 -work uart $SOURCE_DIR/uart/uart_tester.vhd

vcom -2008 -work midi $SOURCE_DIR/midi/midi_pkg.vhd
vcom -2008 -work midi $SOURCE_DIR/midi/midi_reader.vhd
vcom -2008 -work midi $SOURCE_DIR/midi/midi_receiver.vhd
vcom -2008 -work midi $SOURCE_DIR/midi/midi_slave.vhd
vcom -2008 -work midi $SOURCE_DIR/midi/midi_tester.vhd

vcom -2008 -work sdram $SOURCE_DIR/sdram/ddr_arbiter.vhd

vcom -2008 -work qspi $SOURCE_DIR/qspi/qspi_interface.vhd

vcom -2008 -work osc $SOURCE_DIR/oscillator/lfsr32.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/noise_source.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/osc_controller.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/osc_coeff_memory.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/osc_wave_memory.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/table_address_generator.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/halfband_filter.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/table_interpolator.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/oscillator.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/table_mixer.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/unison_mixer.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/unison_step.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/unison_spread.vhd
vcom -2008 -work osc $SOURCE_DIR/oscillator/oscillator_subsystem.vhd

# SDRAM simulation model
vlog +define+den4096Mb -sv -work ddr3 $SOURCE_DIR/ddr3/ddr3.v

vcom -2008 -work wave $SOURCE_DIR/cdc_ff.vhd
vcom -2008 -work wave $SOURCE_DIR/rom.vhd
vcom -2008 -work wave $SOURCE_DIR/lin2log.vhd
vcom -2008 -work wave $SOURCE_DIR/lin2exp.vhd
vcom -2008 -work wave $SOURCE_DIR/clk_subsystem.vhd
vcom -2008 -work wave $SOURCE_DIR/reset_subsystem.vhd
vcom -2008 -work wave $SOURCE_DIR/frame_dma.vhd
vcom -2008 -work wave $SOURCE_DIR/lfo.vhd
vcom -2008 -work wave $SOURCE_DIR/envelope.vhd
vcom -2008 -work wave $SOURCE_DIR/state_variable_filter.vhd
vcom -2008 -work wave $SOURCE_DIR/pitch_modulator.vhd
vcom -2008 -work wave $SOURCE_DIR/mod_matrix.vhd
vcom -2008 -work wave $SOURCE_DIR/hk_offload.vhd
vcom -2008 -work wave $SOURCE_DIR/voice_mixer.vhd
vcom -2008 -work wave $SOURCE_DIR/voice_mixer_subsystem.vhd
vcom -2008 -work wave $SOURCE_DIR/wave_offload.vhd
vcom -2008 -work wave $SOURCE_DIR/synth_subsystem.vhd

vcom -2008 -work wave $SOURCE_DIR/flash_dma.vhd
vcom -2008 -work wave $SOURCE_DIR/register_file.vhd
vcom -2008 -work wave $SOURCE_DIR/wave_array.vhd
vcom -2008 -work wave $SOURCE_DIR/tb_wave_array.vhd
#vcom -2008 -work wave $SOURCE_DIR/tb_wave_array_no_sdram.vhd