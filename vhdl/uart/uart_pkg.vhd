library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package uart_pkg is

    -- Opcodes.
    constant UART_READ_REQ          : std_logic_vector(7 downto 0) := x"00";
    constant UART_READ_REP          : std_logic_vector(7 downto 0) := x"01";
    constant UART_WRITE_REQ         : std_logic_vector(7 downto 0) := x"02";
    constant UART_WRITE_REP         : std_logic_vector(7 downto 0) := x"03";
    constant UART_READ_BLOCK_REQ    : std_logic_vector(7 downto 0) := x"04";
    constant UART_READ_BLOCK_REP    : std_logic_vector(7 downto 0) := x"05";
    constant UART_WRITE_BLOCK_REQ   : std_logic_vector(7 downto 0) := x"06";
    constant UART_WRITE_BLOCK_REP   : std_logic_vector(7 downto 0) := x"07";
    constant UART_ERROR_REP         : std_logic_vector(7 downto 0) := x"08";
    constant UART_AUTO_OFFLOAD      : std_logic_vector(7 downto 0) := x"09";

    -- Auto offload channels.
    constant UART_AO_HK             : std_logic_vector(7 downto 0) := x"00";
    constant UART_AO_WAVE           : std_logic_vector(7 downto 0) := x"01";

    -- UART error codes.
    constant UART_ERR_TIMEOUT       : std_logic_vector(7 downto 0) := x"00";
    constant UART_ERR_READ_FAULT    : std_logic_vector(7 downto 0) := x"01";
    constant UART_ERR_WRITE_FAULT   : std_logic_vector(7 downto 0) := x"02";
end package;
