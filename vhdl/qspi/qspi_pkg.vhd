library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package qspi_pkg is

    constant QSPI_REG_CONTROL       : std_logic_vector(6 downto 0) := 7x"60";
    constant QSPI_REG_STATUS        : std_logic_vector(6 downto 0) := 7x"64";
    constant QSPI_REG_DRR           : std_logic_vector(6 downto 0) := 7x"6C";
    constant QSPI_REG_DTR           : std_logic_vector(6 downto 0) := 7x"68";
    constant QSPI_REG_SLAVE_SELECT  : std_logic_vector(6 downto 0) := 7x"70";

    constant FLASH_CMD_READ_JEDEC   : std_logic_vector(7 downto 0) := x"9F";
    constant FLASH_CMD_READ_STATUS_1: std_logic_vector(7 downto 0) := x"05";
    constant FLASH_CMD_READ_STATUS_2: std_logic_vector(7 downto 0) := x"07";

end package;