set SOURCE_DIR ../vhdl

vlib wave
vlib qspi

vcom -2008 -work wave $SOURCE_DIR/wave_array_pkg.vhd 
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/flash_fifo_sim_netlist.vhdl
vcom -2008 -work qspi $SOURCE_DIR/qspi/qspi_interface.vhd 
vcom -2008 -work wave $SOURCE_DIR/tb_qspi.vhd 