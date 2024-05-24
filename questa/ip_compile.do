set SOURCE_DIR ../vhdl
set SIM_LIB_DIR ../vivado/wave_array/wave_array.cache/compile_simlib/questa

vmap unisim $SIM_LIB_DIR/unisim
vmap secureip $SIM_LIB_DIR/secureip
vmap unisims_ver $SIM_LIB_DIR/unisims_ver

vlib xil_defaultlib

vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_arb_mux.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_arb_row_col.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_arb_select.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_bank_cntrl.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_bank_common.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_bank_compare.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_bank_mach.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_bank_queue.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_bank_state.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_clk_ibuf.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_col_mach.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_byte_group_io.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_byte_lane.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_calib_top.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_if_post_fifo.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_mc_phy.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_mc_phy_wrapper.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_of_pre_fifo.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_4lanes.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ck_addr_cmd_delay.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_dqs_found_cal.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_dqs_found_cal_hr.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_init.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ocd_cntlr.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ocd_data.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ocd_edge.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ocd_lim.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ocd_mux.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ocd_po_cntlr.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_ocd_samp.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_oclkdelay_cal.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_prbs_rdlvl.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_rdlvl.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_tempmon.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_wrcal.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_wrlvl.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_wrlvl_off_delay.v
vcom -2008 -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_phy_top.vhd
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_prbs_gen.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ddr_skip_calib_tap.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ecc_buf.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ecc_dec_fix.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ecc_gen.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ecc_merge_enc.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_fi_xor.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_infrastructure.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_iodelay_ctrl.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_mc.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_mem_intfc.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_memc_ui_top_std.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_poc_cc.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_poc_edge_store.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_poc_meta.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_poc_pd.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_poc_tap_base.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_poc_top.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_rank_cntrl.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_rank_common.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_rank_mach.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_round_robin_arb.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_tempmon.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ui_cmd.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ui_rd_data.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ui_top.v
vlog -work xil_defaultlib $SOURCE_DIR/mig/mig_7series_v4_2_ui_wr_data.v

vcom -2008 -work xil_defaultlib $SOURCE_DIR/mig/mig_gen_mig_sim.vhd
vcom -2008 -work xil_defaultlib $SOURCE_DIR/mig/mig_gen.vhd
vlog -work xil_defaultlib $SOURCE_DIR/mig/glbl.v

#vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/mig_gen_sim_netlist.vhdl


vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/sys_clk_generator_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/i2s_clk_generator_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/i2s_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/uart_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/uart_tx_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/sdram_uart_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/uart_sdram_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/midi_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/adc_mul_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/halfband_macc_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/halfband_ram_even_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/halfband_ram_odd_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/osc_interpolation_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/osc_macc_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/osc_wave_memory_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/envelope_cordic_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/envelope_mult_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/cordic_lfo_sine_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/wave_uart_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/wave_mem_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/wave_offload_fifo_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/svf_macc_gen_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/arbiter_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/flash_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/flash_to_sdram_dma_fifo_sim_netlist.vhdl
vcom -2008 -work xil_defaultlib $SOURCE_DIR/xilinx/sdram_to_flash_dma_fifo_sim_netlist.vhdl



