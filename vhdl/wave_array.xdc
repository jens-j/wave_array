
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_nets clk_s]

## Bank = 35, Pin name = IO_L12P_T1_MRCC_35, Sch name = CLK100MHZ
set_property PACKAGE_PIN E3 [get_ports EXT_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports EXT_CLK]

## Bank = 15, Pin name = IO_L3P_T0_DQS_AD1P_15, Sch name = CPU_RESET
set_property PACKAGE_PIN C12 [get_ports BTN_RESET]
set_property IOSTANDARD LVCMOS33 [get_ports BTN_RESET]

## Bank = 15, Pin name = IO_L1N_T0_AD0N_15, Sch name = JA1
set_property PACKAGE_PIN B13 [get_ports {I2S_SDATA}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_SDATA}]

## Bank = 15, Pin name = IO_L5N_T0_AD9N_15, Sch name = JA2
set_property PACKAGE_PIN F14 [get_ports {I2S_SCLK}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_SCLK}]

## Bank = 15, Pin name = IO_L16N_T2_A27_15, Sch name = JA3
set_property PACKAGE_PIN D17 [get_ports {I2S_WSEL}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_WSEL}]
