
create_clock -add -name system_clk -period 10.00 -waveform {0 5} [get_ports EXT_CLK]
create_generated_clock -name i2s_clk -source [get_ports EXT_CLK] -divide_by 1888 -multiply_by 29 [get_pins clk_gen/clk_buffer/O]

## Bank = 35, Pin name = IO_L12P_T1_MRCC_35, Sch name = CLK100MHZ
set_property PACKAGE_PIN E3 [get_ports EXT_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports EXT_CLK]

## Bank = 15, Pin name = IO_L3P_T0_DQS_AD1P_15, Sch name = CPU_RESET
set_property PACKAGE_PIN C12 [get_ports BTN_RESET]
set_property IOSTANDARD LVCMOS33 [get_ports BTN_RESET]

## Bank = 35, Pin name = IO_L23P_T3_35, Sch name = JC1
set_property PACKAGE_PIN K2 [get_ports {I2S_SDATA}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_SDATA}]
## Bank = 35, Pin name = IO_L6P_T0_35, Sch name = JC2
set_property PACKAGE_PIN E7 [get_ports {I2S_SCLK}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_SCLK}]
## Bank = 35, Pin name = IO_L22P_T3_35, Sch name = JC3
set_property PACKAGE_PIN J3 [get_ports {I2S_WSEL}]
set_property IOSTANDARD LVCMOS33 [get_ports {I2S_WSEL}]
## Bank = 35, Pin name = IO_L21P_T3_DQS_35, Sch name = JC4
set_property PACKAGE_PIN J4 [get_ports {MIDI_RX}]
set_property IOSTANDARD LVCMOS33 [get_ports {MIDI_RX}]

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

## Pmod Header JXADC
## Bank = 15, Pin name = IO_L9P_T1_DQS_AD3P_15,Sch name = XADC1_P -> XA1_P
set_property PACKAGE_PIN A13 [get_ports {XADC_IN_P[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_P[0]}]
## Bank = 15, Pin name = IO_L8P_T1_AD10P_15,Sch name = XADC2_P -> XA2_P
set_property PACKAGE_PIN A15 [get_ports {XADC_IN_P[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_P[1]}]
## Bank = 15, Pin name = IO_L7P_T1_AD2P_15,Sch name = XADC3_P -> XA3_P
set_property PACKAGE_PIN B16 [get_ports {XADC_IN_P[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_P[2]}]
## Bank = 15, Pin name = IO_L10P_T1_AD11P_15,Sch name = XADC4_P -> XA4_P
set_property PACKAGE_PIN B18 [get_ports {XADC_IN_P[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_P[3]}]
## Bank = 15, Pin name = IO_L9N_T1_DQS_AD3N_15,Sch name = XADC1_N -> XA1_N
set_property PACKAGE_PIN A14 [get_ports {XADC_IN_N[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_N[0]}]
## Bank = 15, Pin name = IO_L8N_T1_AD10N_15,Sch name = XADC2_N -> XA2_N
set_property PACKAGE_PIN A16 [get_ports {XADC_IN_N[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_N[1]}]
## Bank = 15, Pin name = IO_L7N_T1_AD2N_15,Sch name = XADC3_N -> XA3_N
set_property PACKAGE_PIN B17 [get_ports {XADC_IN_N[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_N[2]}]
## Bank = 15, Pin name = IO_L10N_T1_AD11N_15,Sch name = XADC4_N -> XA4_N
set_property PACKAGE_PIN A18 [get_ports {XADC_IN_N[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {XADC_IN_N[3]}]
