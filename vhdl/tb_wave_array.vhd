library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity tb_wave_array is
end entity;


architecture arch of tb_wave_array is

    signal clk              : std_logic := '0';
    signal reset            : std_logic := '0';
    signal sdata            : std_logic;
    signal sclk             : std_logic;
    signal wsel             : std_logic;
    signal uart_rx          : std_logic;
    signal uart_tx          : std_logic;
    signal midi_uart        : std_logic;
    signal leds             : std_logic_vector(15 downto 0);
    signal switches         : std_logic_vector(15 downto 0);
    signal xadc_3p          : std_logic;
    signal xadc_3n          : std_logic;
    signal display_segments : std_logic_vector(6 downto 0);
    signal display_anodes   : std_logic_vector(7 downto 0);

begin

    midi_tester : entity wave.midi_tester
    generic map (
        FILENAME                => "four_notes.txt"
    )
    port map (
        clk                     => clk,
        reset                   => not reset,
        uart_tx                 => midi_uart
    );

    uart_tester : entity wave.uart_tester
    port map (
        clk                     => clk,
        reset                   => not reset,
        uart_tx                 => uart_rx
    );

    wave_array : entity wave.wave_array
    port map(
        EXT_CLK                 => clk,
        BTN_RESET               => reset,
        LEDS                    => leds,
        SWITCHES                => switches,
        UART_RX                 => uart_rx,
        UART_TX                 => uart_tx,
        MIDI_RX                 => midi_uart,
        I2S_SCLK                => sclk,
        I2S_WSEL                => wsel,
        I2S_SDATA               => sdata,
        XADC_3P                 => xadc_3p,
        XADC_3N                 => xadc_3n,
        DISPLAY_SEGMENTS        => display_segments,
        DISPLAY_ANODES          => display_anodes
    );

    clk <= not clk after 5 ns;
    reset <= '1' after 1 us;
    switches <= x"9400";

end architecture;
