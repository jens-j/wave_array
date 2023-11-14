library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;

library uart;


-- entity tb_wave_array is
-- end entity;


architecture arch_no_memory of tb_wave_array is

    signal s_clk                    : std_logic := '0';
    signal s_resetn                 : std_logic := '0';
    signal s_reset                  : std_logic := '0';
    signal s_sdata                  : std_logic := '0';
    signal s_sclk                   : std_logic := '0';
    signal s_wsel                   : std_logic := '0';
    signal s_uart_rx                : std_logic := '0';
    signal s_uart_tx                : std_logic := '0';
    signal s_midi_uart              : std_logic := '0';
    signal s_leds                   : std_logic_vector(7 downto 0) := (others => '0');
    signal s_switches               : std_logic_vector(7 downto 0) := (others => '0');

    signal s_sdram_rst_n            : std_logic;
    signal s_sdram_ck               : std_logic;
    signal s_sdram_ck_n             : std_logic;
    signal s_sdram_cke              : std_logic;
    signal s_sdram_ras_n            : std_logic;
    signal s_sdram_cas_n            : std_logic;
    signal s_sdram_we_n             : std_logic;
    signal s_sdram_dm_tdqs          : std_logic_vector(1 downto 0);
    signal s_sdram_ba               : std_logic_vector(2 downto 0);
    signal s_sdram_addr             : std_logic_vector(14 downto 0);
    signal s_sdram_dq               : std_logic_vector(15 downto 0);
    signal s_sdram_dqs              : std_logic_vector(1 downto 0);
    signal s_sdram_dqs_n            : std_logic_vector(1 downto 0);
    signal s_sdram_tdqs_n           : std_logic_vector(1 downto 0);
    signal s_sdram_odt              : std_logic; 

begin

    uart_tester : entity uart.uart_tester
    generic map (
        FILENAME                => SIM_FILE_PATH & "uart.txt"
    )
    port map (
        clk                     => s_clk,
        reset                   => s_reset,
        uart_rx                 => s_uart_tx,
        uart_tx                 => s_uart_rx
    );

    midi_tester : entity midi.midi_tester
    generic map (
        FILENAME                => SIM_FILE_PATH & "four_notes.txt"
    )
    port map (
        clk                     => s_clk,
        reset                   => s_reset,
        uart_tx                 => s_midi_uart
    );

    wave_array : entity wave.wave_array
    generic map (
        NO_MIG                  => true
    )
    port map (
        EXT_CLK                 => s_clk,
        BTN_RESET               => s_resetn,
        LEDS                    => s_leds,
        SWITCHES                => s_switches,
        UART_RX                 => s_uart_rx,
        UART_TX                 => s_uart_tx,
        MIDI_RX                 => s_midi_uart,
        I2S_SCLK                => s_sclk,
        I2S_WSEL                => s_wsel,
        I2S_SDATA               => s_sdata,
        DDR3_DQ                 => s_sdram_dq,
        DDR3_DQS_P              => s_sdram_dqs,
        DDR3_DQS_N              => s_sdram_dqs_n,
        DDR3_ADDR               => s_sdram_addr,
        DDR3_BA                 => s_sdram_ba,
        DDR3_RAS_N              => s_sdram_ras_n,
        DDR3_CAS_N              => s_sdram_cas_n,
        DDR3_WE_N               => s_sdram_we_n,
        DDR3_RESET_N            => s_sdram_rst_n,
        DDR3_CK_P               => s_sdram_ck,
        DDR3_CK_N               => s_sdram_ck_n,
        DDR3_CKE                => s_sdram_cke,
        DDR3_DM                 => s_sdram_dm_tdqs,
        DDR3_ODT                => s_sdram_odt
    );

    s_clk <= not s_clk after 5 ns;
    s_resetn <= '1' after 1 us;
    s_reset <= not s_resetn;
    s_switches <= x"00";

end architecture;
