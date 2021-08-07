library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package wave_array_pkg is

    constant SYS_FREQ               : integer := 100_000_000;

    constant SAMPLE_WIDTH           : integer := 16;
    constant SAMPLE_MAX             : integer := 2**SAMPLE_WIDTH - 1;
    constant SAMPLE_RATE            : integer := 48_000;

    constant I2S_CLK_DIV            : integer := SYS_FREQ / (SAMPLE_RATE * SAMPLE_WIDTH * 2);

    type sample_t is array (1 downto 0) of std_logic_vector(SAMPLE_WIDTH - 1 downto 0);

end package;
