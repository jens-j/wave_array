### This file is a general .xdc for the Nexys Video Rev. A
### To use it in a project:
### - uncomment the lines corresponding to used pins
### - rename the used ports (in each line, after get_ports) according to the top level signal names in the project


## Clock Signal
set_property -dict {PACKAGE_PIN R4 IOSTANDARD LVCMOS33} [get_ports EXT_CLK]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports EXT_CLK]

## Buttons
set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS15} [get_ports BTN_RESET]

## LEDs
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS25} [get_ports {LEDS[0]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS25} [get_ports {LEDS[1]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS25} [get_ports {LEDS[2]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS25} [get_ports {LEDS[3]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS25} [get_ports {LEDS[4]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS25} [get_ports {LEDS[5]}]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS25} [get_ports {LEDS[6]}]
set_property -dict {PACKAGE_PIN Y13 IOSTANDARD LVCMOS25} [get_ports {LEDS[7]}]

## Switches
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[0]}]
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[1]}]
set_property -dict {PACKAGE_PIN G21 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[2]}]
set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[3]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[4]}]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[5]}]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[6]}]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS12} [get_ports {SWITCHES[7]}]

## Pmod header JC
set_property -dict {PACKAGE_PIN Y6 IOSTANDARD LVCMOS33} [get_ports I2S_SCLK]
set_property -dict {PACKAGE_PIN AA6 IOSTANDARD LVCMOS33} [get_ports I2S_WSEL]
set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS33} [get_ports I2S_SDATA]
set_property -dict {PACKAGE_PIN AB8 IOSTANDARD LVCMOS33} [get_ports MIDI_RX]

# UART
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS33} [get_ports UART_TX]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports UART_RX]

## Configuration options, can be used for all designs
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list arbiter/sdram_controller/u_mig_gen_mig/u_ddr3_infrastructure/CLK]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 128 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {arbiter/sdram_controller/app_wdf_data[0]} {arbiter/sdram_controller/app_wdf_data[1]} {arbiter/sdram_controller/app_wdf_data[2]} {arbiter/sdram_controller/app_wdf_data[3]} {arbiter/sdram_controller/app_wdf_data[4]} {arbiter/sdram_controller/app_wdf_data[5]} {arbiter/sdram_controller/app_wdf_data[6]} {arbiter/sdram_controller/app_wdf_data[7]} {arbiter/sdram_controller/app_wdf_data[8]} {arbiter/sdram_controller/app_wdf_data[9]} {arbiter/sdram_controller/app_wdf_data[10]} {arbiter/sdram_controller/app_wdf_data[11]} {arbiter/sdram_controller/app_wdf_data[12]} {arbiter/sdram_controller/app_wdf_data[13]} {arbiter/sdram_controller/app_wdf_data[14]} {arbiter/sdram_controller/app_wdf_data[15]} {arbiter/sdram_controller/app_wdf_data[16]} {arbiter/sdram_controller/app_wdf_data[17]} {arbiter/sdram_controller/app_wdf_data[18]} {arbiter/sdram_controller/app_wdf_data[19]} {arbiter/sdram_controller/app_wdf_data[20]} {arbiter/sdram_controller/app_wdf_data[21]} {arbiter/sdram_controller/app_wdf_data[22]} {arbiter/sdram_controller/app_wdf_data[23]} {arbiter/sdram_controller/app_wdf_data[24]} {arbiter/sdram_controller/app_wdf_data[25]} {arbiter/sdram_controller/app_wdf_data[26]} {arbiter/sdram_controller/app_wdf_data[27]} {arbiter/sdram_controller/app_wdf_data[28]} {arbiter/sdram_controller/app_wdf_data[29]} {arbiter/sdram_controller/app_wdf_data[30]} {arbiter/sdram_controller/app_wdf_data[31]} {arbiter/sdram_controller/app_wdf_data[32]} {arbiter/sdram_controller/app_wdf_data[33]} {arbiter/sdram_controller/app_wdf_data[34]} {arbiter/sdram_controller/app_wdf_data[35]} {arbiter/sdram_controller/app_wdf_data[36]} {arbiter/sdram_controller/app_wdf_data[37]} {arbiter/sdram_controller/app_wdf_data[38]} {arbiter/sdram_controller/app_wdf_data[39]} {arbiter/sdram_controller/app_wdf_data[40]} {arbiter/sdram_controller/app_wdf_data[41]} {arbiter/sdram_controller/app_wdf_data[42]} {arbiter/sdram_controller/app_wdf_data[43]} {arbiter/sdram_controller/app_wdf_data[44]} {arbiter/sdram_controller/app_wdf_data[45]} {arbiter/sdram_controller/app_wdf_data[46]} {arbiter/sdram_controller/app_wdf_data[47]} {arbiter/sdram_controller/app_wdf_data[48]} {arbiter/sdram_controller/app_wdf_data[49]} {arbiter/sdram_controller/app_wdf_data[50]} {arbiter/sdram_controller/app_wdf_data[51]} {arbiter/sdram_controller/app_wdf_data[52]} {arbiter/sdram_controller/app_wdf_data[53]} {arbiter/sdram_controller/app_wdf_data[54]} {arbiter/sdram_controller/app_wdf_data[55]} {arbiter/sdram_controller/app_wdf_data[56]} {arbiter/sdram_controller/app_wdf_data[57]} {arbiter/sdram_controller/app_wdf_data[58]} {arbiter/sdram_controller/app_wdf_data[59]} {arbiter/sdram_controller/app_wdf_data[60]} {arbiter/sdram_controller/app_wdf_data[61]} {arbiter/sdram_controller/app_wdf_data[62]} {arbiter/sdram_controller/app_wdf_data[63]} {arbiter/sdram_controller/app_wdf_data[64]} {arbiter/sdram_controller/app_wdf_data[65]} {arbiter/sdram_controller/app_wdf_data[66]} {arbiter/sdram_controller/app_wdf_data[67]} {arbiter/sdram_controller/app_wdf_data[68]} {arbiter/sdram_controller/app_wdf_data[69]} {arbiter/sdram_controller/app_wdf_data[70]} {arbiter/sdram_controller/app_wdf_data[71]} {arbiter/sdram_controller/app_wdf_data[72]} {arbiter/sdram_controller/app_wdf_data[73]} {arbiter/sdram_controller/app_wdf_data[74]} {arbiter/sdram_controller/app_wdf_data[75]} {arbiter/sdram_controller/app_wdf_data[76]} {arbiter/sdram_controller/app_wdf_data[77]} {arbiter/sdram_controller/app_wdf_data[78]} {arbiter/sdram_controller/app_wdf_data[79]} {arbiter/sdram_controller/app_wdf_data[80]} {arbiter/sdram_controller/app_wdf_data[81]} {arbiter/sdram_controller/app_wdf_data[82]} {arbiter/sdram_controller/app_wdf_data[83]} {arbiter/sdram_controller/app_wdf_data[84]} {arbiter/sdram_controller/app_wdf_data[85]} {arbiter/sdram_controller/app_wdf_data[86]} {arbiter/sdram_controller/app_wdf_data[87]} {arbiter/sdram_controller/app_wdf_data[88]} {arbiter/sdram_controller/app_wdf_data[89]} {arbiter/sdram_controller/app_wdf_data[90]} {arbiter/sdram_controller/app_wdf_data[91]} {arbiter/sdram_controller/app_wdf_data[92]} {arbiter/sdram_controller/app_wdf_data[93]} {arbiter/sdram_controller/app_wdf_data[94]} {arbiter/sdram_controller/app_wdf_data[95]} {arbiter/sdram_controller/app_wdf_data[96]} {arbiter/sdram_controller/app_wdf_data[97]} {arbiter/sdram_controller/app_wdf_data[98]} {arbiter/sdram_controller/app_wdf_data[99]} {arbiter/sdram_controller/app_wdf_data[100]} {arbiter/sdram_controller/app_wdf_data[101]} {arbiter/sdram_controller/app_wdf_data[102]} {arbiter/sdram_controller/app_wdf_data[103]} {arbiter/sdram_controller/app_wdf_data[104]} {arbiter/sdram_controller/app_wdf_data[105]} {arbiter/sdram_controller/app_wdf_data[106]} {arbiter/sdram_controller/app_wdf_data[107]} {arbiter/sdram_controller/app_wdf_data[108]} {arbiter/sdram_controller/app_wdf_data[109]} {arbiter/sdram_controller/app_wdf_data[110]} {arbiter/sdram_controller/app_wdf_data[111]} {arbiter/sdram_controller/app_wdf_data[112]} {arbiter/sdram_controller/app_wdf_data[113]} {arbiter/sdram_controller/app_wdf_data[114]} {arbiter/sdram_controller/app_wdf_data[115]} {arbiter/sdram_controller/app_wdf_data[116]} {arbiter/sdram_controller/app_wdf_data[117]} {arbiter/sdram_controller/app_wdf_data[118]} {arbiter/sdram_controller/app_wdf_data[119]} {arbiter/sdram_controller/app_wdf_data[120]} {arbiter/sdram_controller/app_wdf_data[121]} {arbiter/sdram_controller/app_wdf_data[122]} {arbiter/sdram_controller/app_wdf_data[123]} {arbiter/sdram_controller/app_wdf_data[124]} {arbiter/sdram_controller/app_wdf_data[125]} {arbiter/sdram_controller/app_wdf_data[126]} {arbiter/sdram_controller/app_wdf_data[127]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 28 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {arbiter/sdram_controller/app_addr[0]} {arbiter/sdram_controller/app_addr[1]} {arbiter/sdram_controller/app_addr[2]} {arbiter/sdram_controller/app_addr[3]} {arbiter/sdram_controller/app_addr[4]} {arbiter/sdram_controller/app_addr[5]} {arbiter/sdram_controller/app_addr[6]} {arbiter/sdram_controller/app_addr[7]} {arbiter/sdram_controller/app_addr[8]} {arbiter/sdram_controller/app_addr[9]} {arbiter/sdram_controller/app_addr[10]} {arbiter/sdram_controller/app_addr[11]} {arbiter/sdram_controller/app_addr[12]} {arbiter/sdram_controller/app_addr[13]} {arbiter/sdram_controller/app_addr[14]} {arbiter/sdram_controller/app_addr[15]} {arbiter/sdram_controller/app_addr[16]} {arbiter/sdram_controller/app_addr[17]} {arbiter/sdram_controller/app_addr[18]} {arbiter/sdram_controller/app_addr[19]} {arbiter/sdram_controller/app_addr[20]} {arbiter/sdram_controller/app_addr[21]} {arbiter/sdram_controller/app_addr[22]} {arbiter/sdram_controller/app_addr[23]} {arbiter/sdram_controller/app_addr[24]} {arbiter/sdram_controller/app_addr[25]} {arbiter/sdram_controller/app_addr[26]} {arbiter/sdram_controller/app_addr[27]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {arbiter/sdram_controller/app_cmd[0]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 128 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {arbiter/sdram_controller/app_rd_data[0]} {arbiter/sdram_controller/app_rd_data[1]} {arbiter/sdram_controller/app_rd_data[2]} {arbiter/sdram_controller/app_rd_data[3]} {arbiter/sdram_controller/app_rd_data[4]} {arbiter/sdram_controller/app_rd_data[5]} {arbiter/sdram_controller/app_rd_data[6]} {arbiter/sdram_controller/app_rd_data[7]} {arbiter/sdram_controller/app_rd_data[8]} {arbiter/sdram_controller/app_rd_data[9]} {arbiter/sdram_controller/app_rd_data[10]} {arbiter/sdram_controller/app_rd_data[11]} {arbiter/sdram_controller/app_rd_data[12]} {arbiter/sdram_controller/app_rd_data[13]} {arbiter/sdram_controller/app_rd_data[14]} {arbiter/sdram_controller/app_rd_data[15]} {arbiter/sdram_controller/app_rd_data[16]} {arbiter/sdram_controller/app_rd_data[17]} {arbiter/sdram_controller/app_rd_data[18]} {arbiter/sdram_controller/app_rd_data[19]} {arbiter/sdram_controller/app_rd_data[20]} {arbiter/sdram_controller/app_rd_data[21]} {arbiter/sdram_controller/app_rd_data[22]} {arbiter/sdram_controller/app_rd_data[23]} {arbiter/sdram_controller/app_rd_data[24]} {arbiter/sdram_controller/app_rd_data[25]} {arbiter/sdram_controller/app_rd_data[26]} {arbiter/sdram_controller/app_rd_data[27]} {arbiter/sdram_controller/app_rd_data[28]} {arbiter/sdram_controller/app_rd_data[29]} {arbiter/sdram_controller/app_rd_data[30]} {arbiter/sdram_controller/app_rd_data[31]} {arbiter/sdram_controller/app_rd_data[32]} {arbiter/sdram_controller/app_rd_data[33]} {arbiter/sdram_controller/app_rd_data[34]} {arbiter/sdram_controller/app_rd_data[35]} {arbiter/sdram_controller/app_rd_data[36]} {arbiter/sdram_controller/app_rd_data[37]} {arbiter/sdram_controller/app_rd_data[38]} {arbiter/sdram_controller/app_rd_data[39]} {arbiter/sdram_controller/app_rd_data[40]} {arbiter/sdram_controller/app_rd_data[41]} {arbiter/sdram_controller/app_rd_data[42]} {arbiter/sdram_controller/app_rd_data[43]} {arbiter/sdram_controller/app_rd_data[44]} {arbiter/sdram_controller/app_rd_data[45]} {arbiter/sdram_controller/app_rd_data[46]} {arbiter/sdram_controller/app_rd_data[47]} {arbiter/sdram_controller/app_rd_data[48]} {arbiter/sdram_controller/app_rd_data[49]} {arbiter/sdram_controller/app_rd_data[50]} {arbiter/sdram_controller/app_rd_data[51]} {arbiter/sdram_controller/app_rd_data[52]} {arbiter/sdram_controller/app_rd_data[53]} {arbiter/sdram_controller/app_rd_data[54]} {arbiter/sdram_controller/app_rd_data[55]} {arbiter/sdram_controller/app_rd_data[56]} {arbiter/sdram_controller/app_rd_data[57]} {arbiter/sdram_controller/app_rd_data[58]} {arbiter/sdram_controller/app_rd_data[59]} {arbiter/sdram_controller/app_rd_data[60]} {arbiter/sdram_controller/app_rd_data[61]} {arbiter/sdram_controller/app_rd_data[62]} {arbiter/sdram_controller/app_rd_data[63]} {arbiter/sdram_controller/app_rd_data[64]} {arbiter/sdram_controller/app_rd_data[65]} {arbiter/sdram_controller/app_rd_data[66]} {arbiter/sdram_controller/app_rd_data[67]} {arbiter/sdram_controller/app_rd_data[68]} {arbiter/sdram_controller/app_rd_data[69]} {arbiter/sdram_controller/app_rd_data[70]} {arbiter/sdram_controller/app_rd_data[71]} {arbiter/sdram_controller/app_rd_data[72]} {arbiter/sdram_controller/app_rd_data[73]} {arbiter/sdram_controller/app_rd_data[74]} {arbiter/sdram_controller/app_rd_data[75]} {arbiter/sdram_controller/app_rd_data[76]} {arbiter/sdram_controller/app_rd_data[77]} {arbiter/sdram_controller/app_rd_data[78]} {arbiter/sdram_controller/app_rd_data[79]} {arbiter/sdram_controller/app_rd_data[80]} {arbiter/sdram_controller/app_rd_data[81]} {arbiter/sdram_controller/app_rd_data[82]} {arbiter/sdram_controller/app_rd_data[83]} {arbiter/sdram_controller/app_rd_data[84]} {arbiter/sdram_controller/app_rd_data[85]} {arbiter/sdram_controller/app_rd_data[86]} {arbiter/sdram_controller/app_rd_data[87]} {arbiter/sdram_controller/app_rd_data[88]} {arbiter/sdram_controller/app_rd_data[89]} {arbiter/sdram_controller/app_rd_data[90]} {arbiter/sdram_controller/app_rd_data[91]} {arbiter/sdram_controller/app_rd_data[92]} {arbiter/sdram_controller/app_rd_data[93]} {arbiter/sdram_controller/app_rd_data[94]} {arbiter/sdram_controller/app_rd_data[95]} {arbiter/sdram_controller/app_rd_data[96]} {arbiter/sdram_controller/app_rd_data[97]} {arbiter/sdram_controller/app_rd_data[98]} {arbiter/sdram_controller/app_rd_data[99]} {arbiter/sdram_controller/app_rd_data[100]} {arbiter/sdram_controller/app_rd_data[101]} {arbiter/sdram_controller/app_rd_data[102]} {arbiter/sdram_controller/app_rd_data[103]} {arbiter/sdram_controller/app_rd_data[104]} {arbiter/sdram_controller/app_rd_data[105]} {arbiter/sdram_controller/app_rd_data[106]} {arbiter/sdram_controller/app_rd_data[107]} {arbiter/sdram_controller/app_rd_data[108]} {arbiter/sdram_controller/app_rd_data[109]} {arbiter/sdram_controller/app_rd_data[110]} {arbiter/sdram_controller/app_rd_data[111]} {arbiter/sdram_controller/app_rd_data[112]} {arbiter/sdram_controller/app_rd_data[113]} {arbiter/sdram_controller/app_rd_data[114]} {arbiter/sdram_controller/app_rd_data[115]} {arbiter/sdram_controller/app_rd_data[116]} {arbiter/sdram_controller/app_rd_data[117]} {arbiter/sdram_controller/app_rd_data[118]} {arbiter/sdram_controller/app_rd_data[119]} {arbiter/sdram_controller/app_rd_data[120]} {arbiter/sdram_controller/app_rd_data[121]} {arbiter/sdram_controller/app_rd_data[122]} {arbiter/sdram_controller/app_rd_data[123]} {arbiter/sdram_controller/app_rd_data[124]} {arbiter/sdram_controller/app_rd_data[125]} {arbiter/sdram_controller/app_rd_data[126]} {arbiter/sdram_controller/app_rd_data[127]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list arbiter/sdram_controller/app_rdy]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list arbiter/sdram_controller/app_en]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list arbiter/sdram_controller/app_rd_data_end]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 1 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list arbiter/sdram_controller/app_rd_data_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 1 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list arbiter/sdram_controller/app_wdf_end]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list arbiter/sdram_controller/app_wdf_rdy]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list arbiter/sdram_controller/app_wdf_wren]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list arbiter/sdram_controller/init_calib_complete]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list arbiter/sdram_controller/ui_clk_sync_rst]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets s_system_clk]
