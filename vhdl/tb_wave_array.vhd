library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.wave_array_pkg.all;


entity tb_wave_array is
end entity;


architecture arch of tb_wave_array is

    signal clk              : std_logic := '0';
    signal reset            : std_logic := '0';
    signal sdata            : std_logic;
    signal sclk             : std_logic;
    signal wsel             : std_logic;

begin

    dut : entity work.wave_array
    port map(
        EXT_CLK                 => clk,
        BTN_RESET               => reset,
        I2S_SCLK                => sdata,
        I2S_WSEL                => sclk,
        I2S_SDATA               => wsel
    );

    clk <= not clk after 5 ns;
    reset <= '1' after 100 ns;

end architecture;
