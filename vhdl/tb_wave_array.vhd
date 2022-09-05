library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity tb_wave_array is
end entity;


architecture arch of tb_wave_array is

    signal clk              : std_logic := '0';
    signal resetn           : std_logic := '0';
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
    signal sdram_clk        : std_logic;
    signal sdram_advn       : std_logic;
    signal sdram_cen        : std_logic;
    signal sdram_cre        : std_logic;
    signal sdram_oen        : std_logic;
    signal sdram_wen        : std_logic;
    signal sdram_lbn        : std_logic;
    signal sdram_ubn        : std_logic;
    signal sdram_wait       : std_logic;
    signal sdram_address    : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
    signal sdram_dq         : std_logic_vector(SDRAM_WIDTH - 1 downto 0);

begin

    midi_tester : entity wave.midi_tester
    generic map (
        FILENAME                => "four_notes.txt"
    )
    port map (
        clk                     => clk,
        reset                   => not resetn,
        uart_tx                 => midi_uart
    );

    uart_tester : entity wave.uart_tester
    generic map (
        FILENAME                => "uart.txt"
    )
    port map (
        clk                     => clk,
        reset                   => not resetn,
        uart_rx                 => uart_tx,
        uart_tx                 => uart_rx
    );

    wave_array : entity wave.wave_array
    port map(
        EXT_CLK                 => clk,
        BTN_RESET               => resetn,
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
        DISPLAY_ANODES          => display_anodes,
        SDRAM_CLK               => sdram_clk,
        SDRAM_ADVN              => sdram_advn,
        SDRAM_CEN               => sdram_cen,
        SDRAM_CRE               => sdram_cre,
        SDRAM_OEN               => sdram_oen,
        SDRAM_WEN               => sdram_wen,
        SDRAM_LBN               => sdram_lbn,
        SDRAM_UBN               => sdram_ubn,
        SDRAM_WAIT              => sdram_wait,
        SDRAM_ADDRESS           => sdram_address,
        SDRAM_DQ                => sdram_dq
    );

    sdram : entity wave.sdram_sim
    generic map (
        DEPTH_LOG2              => 8
    )
    port map (
        SDRAM_RESETN            => resetn,
        SDRAM_CLK               => sdram_clk,
        SDRAM_ADVN              => sdram_advn,
        SDRAM_CEN               => sdram_cen,
        SDRAM_CRE               => sdram_cre,
        SDRAM_OEN               => sdram_oen,
        SDRAM_WEN               => sdram_wen,
        SDRAM_LBN               => sdram_lbn,
        SDRAM_UBN               => sdram_ubn,
        SDRAM_WAIT              => sdram_wait,
        SDRAM_ADDRESS           => sdram_address,
        SDRAM_DQ                => sdram_dq
    );

    clk <= not clk after 5 ns;
    resetn <= '1' after 1 us;
    switches <= x"9400";

end architecture;
