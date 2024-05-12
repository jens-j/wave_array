set SOURCE_DIR ../vhdl

vlib wave
vlib qspi

vcom -2008 -work qspi $SOURCE_DIR/qspi/qspi_pkg.vhd 
vcom -2008 -work qspi $SOURCE_DIR/qspi/qspi_interface.vhd 
vcom -2008 -work wave $SOURCE_DIR/tb_qspi.vhd 