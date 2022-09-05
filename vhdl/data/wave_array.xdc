
create_clock -add -name system_clk -period 10.00 -waveform {0 5} [get_ports EXT_CLK]
create_clock -add -name i2s_clk -period 651.00 -waveform {0 5} [get_pins clk_subsys/i2s_bufg/O]
# create_generated_clock -name i2s_clk -source [get_ports EXT_CLK] -divide_by 118 -multiply_by 7.25 [get_pins clk_subsystem/i2s_bufg/O]

## Bank = 35, Pin name = IO_L12P_T1_MRCC_35, Sch name = CLK100MHZ
set_property PACKAGE_PIN E3 [get_ports EXT_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports EXT_CLK]

## Bank = 15, Pin name = IO_L3P_T0_DQS_AD1P_15, Sch name = CPU_RESET
set_property PACKAGE_PIN C12 [get_ports BTN_RESET]
set_property IOSTANDARD LVCMOS33 [get_ports BTN_RESET]

## Bank = 35, Pin name = IO_L23P_T3_35, Sch name = JC1
set_property PACKAGE_PIN K2 [get_ports {I2S_SCLK}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_SCLK}]
## Bank = 35, Pin name = IO_L6P_T0_35, Sch name = JC2
set_property PACKAGE_PIN E7 [get_ports {I2S_WSEL}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_WSEL}]
## Bank = 35, Pin name = IO_L22P_T3_35, Sch name = JC3
set_property PACKAGE_PIN J3 [get_ports {I2S_SDATA}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_SDATA}]
## Bank = 35, Pin name = IO_L21P_T3_DQS_35, Sch name = JC4
set_property PACKAGE_PIN J4 [get_ports {MIDI_RX}]
set_property IOSTANDARD LVCMOS33 [get_ports {MIDI_RX}]
## Bank = 35, Pin name = IO_L23N_T3_35, Sch name = JC7
#set_property PACKAGE_PIN K1 [get_ports {DEBUG_UART_TX}]
#set_property IOSTANDARD LVCMOS33 [get_ports {DEBUG_UART_TX}]

## USB-RS232 Interface (Nexys labels from the PC perspective)
## Bank = 35, Pin name = IO_L7P_T1_AD6P_35, Sch name = UART_TXD_IN
set_property PACKAGE_PIN C4 [get_ports UART_RX]
set_property IOSTANDARD LVCMOS33 [get_ports UART_RX]
## Bank = 35, Pin name = IO_L11N_T1_SRCC_35, Sch name = UART_RXD_OUT
set_property PACKAGE_PIN D4 [get_ports UART_TX]
set_property IOSTANDARD LVCMOS33 [get_ports UART_TX]

## LEDs
## Bank = 34, Pin name = IO_L24N_T3_34, Sch name = LED0
set_property PACKAGE_PIN T8 [get_ports {LEDS[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[0]}]
## Bank = 34, Pin name = IO_L21N_T3_DQS_34, Sch name = LED1
set_property PACKAGE_PIN V9 [get_ports {LEDS[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[1]}]
## Bank = 34, Pin name = IO_L24P_T3_34, Sch name = LED2
set_property PACKAGE_PIN R8 [get_ports {LEDS[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[2]}]
## Bank = 34, Pin name = IO_L23N_T3_34, Sch name = LED3
set_property PACKAGE_PIN T6 [get_ports {LEDS[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[3]}]
## Bank = 34, Pin name = IO_L12P_T1_MRCC_34, Sch name = LED4
set_property PACKAGE_PIN T5 [get_ports {LEDS[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[4]}]
## Bank = 34, Pin name = IO_L12N_T1_MRCC_34, Sch name = LED5
set_property PACKAGE_PIN T4 [get_ports {LEDS[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[5]}]
## Bank = 34, Pin name = IO_L22P_T3_34, Sch name = LED6
set_property PACKAGE_PIN U7 [get_ports {LEDS[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[6]}]
## Bank = 34, Pin name = IO_L22N_T3_34, Sch name = LED7
set_property PACKAGE_PIN U6 [get_ports {LEDS[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[7]}]
## Bank = 34, Pin name = IO_L10N_T1_34, Sch name = LED8
set_property PACKAGE_PIN V4 [get_ports {LEDS[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[8]}]
## Bank = 34, Pin name = IO_L8N_T1_34, Sch name = LED9
set_property PACKAGE_PIN U3 [get_ports {LEDS[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[9]}]
## Bank = 34, Pin name = IO_L7N_T1_34, Sch name = LED10
set_property PACKAGE_PIN V1 [get_ports {LEDS[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[10]}]
## Bank = 34, Pin name = IO_L17P_T2_34, Sch name = LED11
set_property PACKAGE_PIN R1 [get_ports {LEDS[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[11]}]
## Bank = 34, Pin name = IO_L13N_T2_MRCC_34, Sch name = LED12
set_property PACKAGE_PIN P5 [get_ports {LEDS[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[12]}]
## Bank = 34, Pin name = IO_L7P_T1_34, Sch name = LED13
set_property PACKAGE_PIN U1 [get_ports {LEDS[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[13]}]
## Bank = 34, Pin name = IO_L15N_T2_DQS_34, Sch name = LED14
set_property PACKAGE_PIN R2 [get_ports {LEDS[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[14]}]
## Bank = 34, Pin name = IO_L15P_T2_DQS_34, Sch name = LED15
set_property PACKAGE_PIN P2 [get_ports {LEDS[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LEDS[15]}]

## Switches
## Bank = 34, Pin name = IO_L21P_T3_DQS_34, Sch name = SW0
set_property PACKAGE_PIN U9 [get_ports {SWITCHES[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[0]}]
## Bank = 34, Pin name = IO_25_34, Sch name = SW1
set_property PACKAGE_PIN U8 [get_ports {SWITCHES[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[1]}]
## Bank = 34, Pin name = IO_L23P_T3_34, Sch name = SW2
set_property PACKAGE_PIN R7 [get_ports {SWITCHES[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[2]}]
## Bank = 34, Pin name = IO_L19P_T3_34, Sch name = SW3
set_property PACKAGE_PIN R6 [get_ports {SWITCHES[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[3]}]
## Bank = 34, Pin name = IO_L19N_T3_VREF_34, Sch name = SW4
set_property PACKAGE_PIN R5 [get_ports {SWITCHES[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[4]}]
## Bank = 34, Pin name = IO_L20P_T3_34, Sch name = SW5
set_property PACKAGE_PIN V7 [get_ports {SWITCHES[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[5]}]
## Bank = 34, Pin name = IO_L20N_T3_34, Sch name = SW6
set_property PACKAGE_PIN V6 [get_ports {SWITCHES[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[6]}]
## Bank = 34, Pin name = IO_L10P_T1_34, Sch name = SW7
set_property PACKAGE_PIN V5 [get_ports {SWITCHES[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[7]}]
## Bank = 34, Pin name = IO_L8P_T1-34, Sch name = SW8
set_property PACKAGE_PIN U4 [get_ports {SWITCHES[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[8]}]
## Bank = 34, Pin name = IO_L9N_T1_DQS_34, Sch name = SW9
set_property PACKAGE_PIN V2 [get_ports {SWITCHES[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[9]}]
## Bank = 34, Pin name = IO_L9P_T1_DQS_34, Sch name = SW10
set_property PACKAGE_PIN U2 [get_ports {SWITCHES[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[10]}]
## Bank = 34, Pin name = IO_L11N_T1_MRCC_34, Sch name = SW11
set_property PACKAGE_PIN T3 [get_ports {SWITCHES[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[11]}]
## Bank = 34, Pin name = IO_L17N_T2_34, Sch name = SW12
set_property PACKAGE_PIN T1 [get_ports {SWITCHES[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[12]}]
## Bank = 34, Pin name = IO_L11P_T1_SRCC_34, Sch name = SW13
set_property PACKAGE_PIN R3 [get_ports {SWITCHES[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[13]}]
## Bank = 34, Pin name = IO_L14N_T2_SRCC_34, Sch name = SW14
set_property PACKAGE_PIN P3 [get_ports {SWITCHES[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[14]}]
## Bank = 34, Pin name = IO_L14P_T2_SRCC_34, Sch name = SW15
set_property PACKAGE_PIN P4 [get_ports {SWITCHES[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SWITCHES[15]}]

## 7 segment display
## Bank = 34, Pin name = IO_L2N_T0_34, Sch name = CA
set_property PACKAGE_PIN L3 [get_ports {DISPLAY_SEGMENTS[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_SEGMENTS[0]}]
## Bank = 34, Pin name = IO_L3N_T0_DQS_34, Sch name = CB
set_property PACKAGE_PIN N1 [get_ports {DISPLAY_SEGMENTS[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_SEGMENTS[1]}]
## Bank = 34, Pin name = IO_L6N_T0_VREF_34, Sch name = CC
set_property PACKAGE_PIN L5 [get_ports {DISPLAY_SEGMENTS[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_SEGMENTS[2]}]
## Bank = 34, Pin name = IO_L5N_T0_34, Sch name = CD
set_property PACKAGE_PIN L4 [get_ports {DISPLAY_SEGMENTS[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_SEGMENTS[3]}]
## Bank = 34, Pin name = IO_L2P_T0_34, Sch name = CE
set_property PACKAGE_PIN K3 [get_ports {DISPLAY_SEGMENTS[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_SEGMENTS[4]}]
## Bank = 34, Pin name = IO_L4N_T0_34, Sch name = CF
set_property PACKAGE_PIN M2 [get_ports {DISPLAY_SEGMENTS[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_SEGMENTS[5]}]
## Bank = 34, Pin name = IO_L6P_T0_34, Sch name = CG
set_property PACKAGE_PIN L6 [get_ports {DISPLAY_SEGMENTS[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_SEGMENTS[6]}]

## Bank = 34, Pin name = IO_L18N_T2_34, Sch name = AN0
set_property PACKAGE_PIN N6 [get_ports {DISPLAY_ANODES[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[0]}]
## Bank = 34, Pin name = IO_L18P_T2_34, Sch name = AN1
set_property PACKAGE_PIN M6 [get_ports {DISPLAY_ANODES[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[1]}]
## Bank = 34, Pin name = IO_L4P_T0_34, Sch name = AN2
set_property PACKAGE_PIN M3 [get_ports {DISPLAY_ANODES[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[2]}]
## Bank = 34, Pin name = IO_L13_T2_MRCC_34, Sch name = AN3
set_property PACKAGE_PIN N5 [get_ports {DISPLAY_ANODES[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[3]}]
## Bank = 34, Pin name = IO_L3P_T0_DQS_34, Sch name = AN4
set_property PACKAGE_PIN N2 [get_ports {DISPLAY_ANODES[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[4]}]
## Bank = 34, Pin name = IO_L16N_T2_34, Sch name = AN5
set_property PACKAGE_PIN N4 [get_ports {DISPLAY_ANODES[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[5]}]
## Bank = 34, Pin name = IO_L1P_T0_34, Sch name = AN6
set_property PACKAGE_PIN L1 [get_ports {DISPLAY_ANODES[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[6]}]
## Bank = 34, Pin name = IO_L1N_T034, Sch name = AN7
set_property PACKAGE_PIN M1 [get_ports {DISPLAY_ANODES[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DISPLAY_ANODES[7]}]

## Pmod Header JXADC (schematic numbers do not match pcb print and example project [1,2,3,4] -> [3,10,2,11])
## Bank = 15, Pin name = IO_L9P_T1_DQS_AD3P_15,Sch name = XADC1_P -> XA1_P
set_property PACKAGE_PIN A13 [get_ports {XADC_3P}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_3P}]
## Bank = 15, Pin name = IO_L8P_T1_AD10P_15,Sch name = XADC2_P -> XA2_P
#set_property PACKAGE_PIN A15 [get_ports {XADC_10P}]
#set_property IOSTANDARD LVCMOS33 [get_ports {XADC_10P}]
## Bank = 15, Pin name = IO_L7P_T1_AD2P_15,Sch name = XADC3_P -> XA3_P
#set_property PACKAGE_PIN B16 [get_ports {XADC_2P}]
#set_property IOSTANDARD LVCMOS33 [get_ports {XADC_2P}]
## Bank = 15, Pin name = IO_L10P_T1_AD11P_15,Sch name = XADC4_P -> XA4_P
#set_property PACKAGE_PIN B18 [get_ports {XADC_11P}]
#set_property IOSTANDARD LVCMOS33 [get_ports {XADC_11P}]
## Bank = 15, Pin name = IO_L9N_T1_DQS_AD3N_15,Sch name = XADC1_N -> XA1_N
set_property PACKAGE_PIN A14 [get_ports {XADC_3N}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_3N}]
## Bank = 15, Pin name = IO_L8N_T1_AD10N_15,Sch name = XADC2_N -> XA2_N
#set_property PACKAGE_PIN A16 [get_ports {XADC_10N}]
#set_property IOSTANDARD LVCMOS33 [get_ports {XADC_10N}]
## Bank = 15, Pin name = IO_L7N_T1_AD2N_15,Sch name = XADC3_N -> XA3_N
#set_property PACKAGE_PIN B17 [get_ports {XADC_2N}]
#set_property IOSTANDARD LVCMOS33 [get_ports {XADC_2N}]
## Bank = 15, Pin name = IO_L10N_T1_AD11N_15,Sch name = XADC4_N -> XA4_N
#set_property PACKAGE_PIN A18 [get_ports {XADC_11N}]
#set_property IOSTANDARD LVCMOS33 [get_ports {XADC_11N}]

##Cellular RAM
## Bank = 14, Pin name = IO_L14N_T2_SRCC_14, Sch name = CRAM_CLK
set_property PACKAGE_PIN T15 [get_ports SDRAM_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_CLK]
## Bank = 14, Pin name = IO_L23P_T3_A03_D19_14, Sch name = CRAM_ADVN
set_property PACKAGE_PIN T13 [get_ports SDRAM_ADVN]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_ADVN]
## Bank = 14, Pin name = IO_L4P_T0_D04_14, Sch name = CRAM_CEN
set_property PACKAGE_PIN L18 [get_ports SDRAM_CEN]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_CEN]
## Bank = 15, Pin name = IO_L19P_T3_A22_15, Sch name = CRAM_CRE
set_property PACKAGE_PIN J14 [get_ports SDRAM_CRE]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_CRE]
## Bank = 15, Pin name = IO_L15P_T2_DQS_15, Sch name = CRAM_OEN
set_property PACKAGE_PIN H14 [get_ports SDRAM_OEN]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_OEN]
## Bank = 14, Pin name = IO_0_14, Sch name = CRAM_WEN
set_property PACKAGE_PIN R11 [get_ports SDRAM_WEN]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_WEN]
## Bank = 15, Pin name = IO_L24N_T3_RS0_15, Sch name = CRAM_LBN
set_property PACKAGE_PIN J15 [get_ports SDRAM_LBN]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_LBN]
## Bank = 15, Pin name = IO_L17N_T2_A25_15, Sch name = CRAM_UBN
set_property PACKAGE_PIN J13 [get_ports SDRAM_UBN]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_UBN]
## Bank = 14, Pin name = IO_L14P_T2_SRCC_14, Sch name = CRAM_WAIT
set_property PACKAGE_PIN T14 [get_ports SDRAM_WAIT]
set_property IOSTANDARD LVCMOS33 [get_ports SDRAM_WAIT]

## Bank = 14, Pin name = IO_L5P_T0_DQ06_14, Sch name = CRAM_DQ0
set_property PACKAGE_PIN R12 [get_ports {SDRAM_DQ[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[0]}]
## Bank = 14, Pin name = IO_L19P_T3_A10_D26_14, Sch name = CRAM_DQ1
set_property PACKAGE_PIN T11 [get_ports {SDRAM_DQ[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[1]}]
## Bank = 14, Pin name = IO_L20P_T3_A08)D24_14, Sch name = CRAM_DQ2
set_property PACKAGE_PIN U12 [get_ports {SDRAM_DQ[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[2]}]
## Bank = 14, Pin name = IO_L5N_T0_D07_14, Sch name = CRAM_DQ3
set_property PACKAGE_PIN R13 [get_ports {SDRAM_DQ[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[3]}]
## Bank = 14, Pin name = IO_L17N_T2_A13_D29_14, Sch name = CRAM_DQ4
set_property PACKAGE_PIN U18 [get_ports {SDRAM_DQ[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[4]}]
## Bank = 14, Pin name = IO_L12N_T1_MRCC_14, Sch name = CRAM_DQ5
set_property PACKAGE_PIN R17 [get_ports {SDRAM_DQ[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[5]}]
## Bank = 14, Pin name = IO_L7N_T1_D10_14, Sch name = CRAM_DQ6
set_property PACKAGE_PIN T18 [get_ports {SDRAM_DQ[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[6]}]
## Bank = 14, Pin name = IO_L7P_T1_D09_14, Sch name = CRAM_DQ7
set_property PACKAGE_PIN R18 [get_ports {SDRAM_DQ[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[7]}]
## Bank = 15, Pin name = IO_L22N_T3_A16_15, Sch name = CRAM_DQ8
set_property PACKAGE_PIN F18 [get_ports {SDRAM_DQ[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[8]}]
## Bank = 15, Pin name = IO_L22P_T3_A17_15, Sch name = CRAM_DQ9
set_property PACKAGE_PIN G18 [get_ports {SDRAM_DQ[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[9]}]
## Bank = 15, Pin name = IO_IO_L18N_T2_A23_15, Sch name = CRAM_DQ10
set_property PACKAGE_PIN G17 [get_ports {SDRAM_DQ[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[10]}]
## Bank = 14, Pin name = IO_L4N_T0_D05_14, Sch name = CRAM_DQ11
set_property PACKAGE_PIN M18 [get_ports {SDRAM_DQ[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[11]}]
## Bank = 14, Pin name = IO_L10N_T1_D15_14, Sch name = CRAM_DQ12
set_property PACKAGE_PIN M17 [get_ports {SDRAM_DQ[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[12]}]
## Bank = 14, Pin name = IO_L9N_T1_DQS_D13_14, Sch name = CRAM_DQ13
set_property PACKAGE_PIN P18 [get_ports {SDRAM_DQ[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[13]}]
## Bank = 14, Pin name = IO_L9P_T1_DQS_14, Sch name = CRAM_DQ14
set_property PACKAGE_PIN N17 [get_ports {SDRAM_DQ[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[14]}]
## Bank = 14, Pin name = IO_L12P_T1_MRCC_14, Sch name = CRAM_DQ15
set_property PACKAGE_PIN P17 [get_ports {SDRAM_DQ[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_DQ[15]}]

## Bank = 15, Pin name = IO_L23N_T3_FWE_B_15, Sch name = CRAM_A0
set_property PACKAGE_PIN J18 [get_ports {SDRAM_ADDRESS[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[0]}]
## Bank = 15, Pin name = IO_L18P_T2_A24_15, Sch name = CRAM_A1
set_property PACKAGE_PIN H17 [get_ports {SDRAM_ADDRESS[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[1]}]
## Bank = 15, Pin name = IO_L19N_T3_A21_VREF_15, Sch name = CRAM_A2
set_property PACKAGE_PIN H15 [get_ports {SDRAM_ADDRESS[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[2]}]
## Bank = 15, Pin name = IO_L23P_T3_FOE_B_15, Sch name = CRAM_A3
set_property PACKAGE_PIN J17 [get_ports {SDRAM_ADDRESS[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[3]}]
## Bank = 15, Pin name = IO_L13P_T2_MRCC_15, Sch name = CRAM_A4
set_property PACKAGE_PIN H16 [get_ports {SDRAM_ADDRESS[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[4]}]
## Bank = 15, Pin name = IO_L24P_T3_RS1_15, Sch name = CRAM_A5
set_property PACKAGE_PIN K15 [get_ports {SDRAM_ADDRESS[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[5]}]
## Bank = 15, Pin name = IO_L17P_T2_A26_15, Sch name = CRAM_A6
set_property PACKAGE_PIN K13 [get_ports {SDRAM_ADDRESS[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[6]}]
## Bank = 14, Pin name = IO_L11P_T1_SRCC_14, Sch name = CRAM_A7
set_property PACKAGE_PIN N15 [get_ports {SDRAM_ADDRESS[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[7]}]
## Bank = 14, Pin name = IO_L16N_T2_SRCC-14, Sch name = CRAM_A8
set_property PACKAGE_PIN V16 [get_ports {SDRAM_ADDRESS[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[8]}]
## Bank = 14, Pin name = IO_L22P_T3_A05_D21_14, Sch name = CRAM_A9
set_property PACKAGE_PIN U14 [get_ports {SDRAM_ADDRESS[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[9]}]
## Bank = 14, Pin name = IO_L22N_T3_A04_D20_14, Sch name = CRAM_A10
set_property PACKAGE_PIN V14 [get_ports {SDRAM_ADDRESS[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[10]}]
## Bank = 14, Pin name = IO_L20N_T3_A07_D23_14, Sch name = CRAM_A11
set_property PACKAGE_PIN V12 [get_ports {SDRAM_ADDRESS[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[11]}]
## Bank = 14, Pin name = IO_L8N_T1_D12_14, Sch name = CRAM_A12
set_property PACKAGE_PIN P14 [get_ports {SDRAM_ADDRESS[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[12]}]
## Bank = 14, Pin name = IO_L18P_T2_A12_D28_14, Sch name = CRAM_A13
set_property PACKAGE_PIN U16 [get_ports {SDRAM_ADDRESS[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[13]}]
## Bank = 14, Pin name = IO_L13N_T2_MRCC_14, Sch name = CRAM_A14
set_property PACKAGE_PIN R15 [get_ports {SDRAM_ADDRESS[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[14]}]
## Bank = 14, Pin name = IO_L8P_T1_D11_14, Sch name = CRAM_A15
set_property PACKAGE_PIN N14 [get_ports {SDRAM_ADDRESS[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[15]}]
## Bank = 14, Pin name = IO_L11N_T1_SRCC_14, Sch name = CRAM_A16
set_property PACKAGE_PIN N16 [get_ports {SDRAM_ADDRESS[16]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[16]}]
## Bank = 14, Pin name = IO_L6N_T0_D08_VREF_14, Sch name = CRAM_A17
set_property PACKAGE_PIN M13 [get_ports {SDRAM_ADDRESS[17]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[17]}]
## Bank = 14, Pin name = IO_L18N_T2_A11_D27_14, Sch name = CRAM_A18
set_property PACKAGE_PIN V17 [get_ports {SDRAM_ADDRESS[18]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[18]}]
## Bank = 14, Pin name = IO_L17P_T2_A14_D30_14, Sch name = CRAM_A19
set_property PACKAGE_PIN U17 [get_ports {SDRAM_ADDRESS[19]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[19]}]
## Bank = 14, Pin name = IO_L24N_T3_A00_D16_14, Sch name = CRAM_A20
set_property PACKAGE_PIN T10 [get_ports {SDRAM_ADDRESS[20]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[20]}]
## Bank = 14, Pin name = IO_L10P_T1_D14_14, Sch name = CRAM_A21
set_property PACKAGE_PIN M16 [get_ports {SDRAM_ADDRESS[21]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[21]}]
## Bank = 14, Pin name = IO_L23N_T3_A02_D18_14, Sch name = CRAM_A22
set_property PACKAGE_PIN U13 [get_ports {SDRAM_ADDRESS[22]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDRAM_ADDRESS[22]}]
