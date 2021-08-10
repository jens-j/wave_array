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
    signal rx               : std_logic;
    signal tx               : std_logic;
    signal leds             : std_logic_vector(15 downto 0);
    signal switches         : std_logic_vector(15 downto 0);

begin

    dut : entity work.wave_array
    port map(
        EXT_CLK                 => clk,
        BTN_RESET               => reset,
        LEDS                    => leds,
        SWITCHES                => switches,
        I2S_SCLK                => sclk,
        I2S_WSEL                => wsel,
        I2S_SDATA               => sdata,
        UART_RX                 => rx,
        UART_TX                 => tx
    );

    clk <= not clk after 5 ns;
    reset <= '1' after 100 ns;
    switches <= x"0033";

end architecture;
