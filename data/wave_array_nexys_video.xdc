### This file is a general .xdc for the Nexys Video Rev. A
### To use it in a project:
### - uncomment the lines corresponding to used pins
### - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

# Configuration options, can be used for all designs
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# Clock Signal
set_property -dict {PACKAGE_PIN R4 IOSTANDARD LVCMOS33} [get_ports EXT_CLK]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports EXT_CLK]

# Buttons
set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS15} [get_ports BTN_RESET]

# LEDs
set_property -dict {PACKAGE_PIN T14  IOSTANDARD LVCMOS25} [get_ports LEDS[0]]
set_property -dict {PACKAGE_PIN T15  IOSTANDARD LVCMOS25} [get_ports LEDS[1]]
set_property -dict {PACKAGE_PIN T16  IOSTANDARD LVCMOS25} [get_ports LEDS[2]]
set_property -dict {PACKAGE_PIN U16  IOSTANDARD LVCMOS25} [get_ports LEDS[3]]
set_property -dict {PACKAGE_PIN V15  IOSTANDARD LVCMOS25} [get_ports LEDS[4]]
set_property -dict {PACKAGE_PIN W16  IOSTANDARD LVCMOS25} [get_ports LEDS[5]]
set_property -dict {PACKAGE_PIN W15  IOSTANDARD LVCMOS25} [get_ports LEDS[6]] 
set_property -dict {PACKAGE_PIN Y13  IOSTANDARD LVCMOS25} [get_ports LEDS[7]] 

# Switches
set_property -dict {PACKAGE_PIN E22  IOSTANDARD LVCMOS12} [get_ports SWITCHES[0]]
set_property -dict {PACKAGE_PIN F21  IOSTANDARD LVCMOS12} [get_ports SWITCHES[1]]
set_property -dict {PACKAGE_PIN G21  IOSTANDARD LVCMOS12} [get_ports SWITCHES[2]]
set_property -dict {PACKAGE_PIN G22  IOSTANDARD LVCMOS12} [get_ports SWITCHES[3]]
set_property -dict {PACKAGE_PIN H17  IOSTANDARD LVCMOS12} [get_ports SWITCHES[4]]
set_property -dict {PACKAGE_PIN J16  IOSTANDARD LVCMOS12} [get_ports SWITCHES[5]]
set_property -dict {PACKAGE_PIN K13  IOSTANDARD LVCMOS12} [get_ports SWITCHES[6]]
set_property -dict {PACKAGE_PIN M17  IOSTANDARD LVCMOS12} [get_ports SWITCHES[7]]

# MIDI in and I2S out on PMOD header JC
# set_property -dict {PACKAGE_PIN Y6   IOSTANDARD LVCMOS33} [get_ports I2S_SCLK ]
# set_property -dict {PACKAGE_PIN AA6  IOSTANDARD LVCMOS33} [get_ports I2S_WSEL ]
# set_property -dict {PACKAGE_PIN AA8  IOSTANDARD LVCMOS33} [get_ports I2S_SDATA]
# set_property -dict {PACKAGE_PIN AB8  IOSTANDARD LVCMOS33} [get_ports MIDI_RX  ]

# MIDI in and I2S out on PMOD header JA
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS33} [get_ports I2S_SCLK ]
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports I2S_WSEL ]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports I2S_SDATA]
set_property -dict {PACKAGE_PIN AB18 IOSTANDARD LVCMOS33} [get_ports MIDI_RX  ]

# UART
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS33} [get_ports UART_TX]
set_property -dict {PACKAGE_PIN V18  IOSTANDARD LVCMOS33} [get_ports UART_RX]

# # QSPI flash on PMOD header JA                                                    # pmod data pin/header pin index
# set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS33} [get_ports QSPI_CS];    # 0/1
# set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[0]]; # 1/2 
# set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[1]]; # 2/3
# set_property -dict {PACKAGE_PIN AB18 IOSTANDARD LVCMOS33} [get_ports QSPI_SCK];   # 3/4
# set_property -dict {PACKAGE_PIN AA20 IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[2]]; # 6/9 
# set_property -dict {PACKAGE_PIN AA18 IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[3]]; # 7/10 

# QSPI flash on PMOD header JC                                                    # pmod data pin/header pin index
set_property -dict {PACKAGE_PIN Y6   IOSTANDARD LVCMOS33} [get_ports QSPI_CS];    # 0/1
set_property -dict {PACKAGE_PIN AA6  IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[0]]; # 1/2 
set_property -dict {PACKAGE_PIN AA8  IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[1]]; # 2/3
set_property -dict {PACKAGE_PIN AB8  IOSTANDARD LVCMOS33} [get_ports QSPI_SCK];   # 3/4
set_property -dict {PACKAGE_PIN AB7  IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[2]]; # 6/9 
set_property -dict {PACKAGE_PIN AB6  IOSTANDARD LVCMOS33} [get_ports QSPI_DQ[3]]; # 7/10 