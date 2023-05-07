library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;

library uart;


entity tb_wave_array is
end entity;


architecture arch of tb_wave_array is

    signal clk              : std_logic := '0';
    signal resetn           : std_logic := '0';
    signal reset            : std_logic := '0';
    signal sdata            : std_logic := '0';
    signal sclk             : std_logic := '0';
    signal wsel             : std_logic := '0';
    signal uart_rx          : std_logic := '0';
    signal uart_tx          : std_logic := '0';
    signal midi_uart        : std_logic := '0';
    signal leds             : std_logic_vector(15 downto 0) := (others => '0');
    signal switches         : std_logic_vector(15 downto 0) := (others => '0');
    signal xadc_3p          : std_logic := '0';
    signal xadc_3n          : std_logic := '0';
    signal display_segments : std_logic_vector(6 downto 0) := (others => '0');
    signal display_anodes   : std_logic_vector(7 downto 0) := (others => '0');
    signal sdram_clk        : std_logic := '0';
    signal sdram_advn       : std_logic := '0';
    signal sdram_cen        : std_logic := '0';
    signal sdram_cre        : std_logic := '0';
    signal sdram_oen        : std_logic := '0';
    signal sdram_wen        : std_logic := '0';
    signal sdram_lbn        : std_logic := '0';
    signal sdram_ubn        : std_logic := '0';
    signal sdram_wait       : std_logic := '0';
    signal sdram_address    : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0) := (others => '0');
    signal sdram_dq         : std_logic_vector(SDRAM_WIDTH - 1 downto 0) := (others => '0');

    component cellram is
    port (
        clk                     : in    std_logic;
        adv_n                   : in    std_logic;
        cre                     : in    std_logic;
        o_wait                  : out   std_logic;
        ce_n                    : in    std_logic;
        oe_n                    : in    std_logic;
        we_n                    : in    std_logic;
        lb_n                    : in    std_logic;
        ub_n                    : in    std_logic;
        addr                    : in    std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        dq                      : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0));
    end component;

begin

   

    uart_tester : entity uart.uart_tester
    generic map (
        FILENAME                => SIM_FILE_PATH & "uart.txt"
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        uart_rx                 => uart_tx,
        uart_tx                 => uart_rx
    );

    midi_tester : entity midi.midi_tester
    generic map (
        FILENAME                => SIM_FILE_PATH & "four_notes.txt"
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        uart_tx                 => midi_uart
    );

    wave_array : entity wave.wave_array
    port map (
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

    sdram_verilog : cellram
    port map (
        clk                     => sdram_clk,
        adv_n                   => sdram_advn,
        cre                     => sdram_cre,
        o_wait                  => sdram_wait,
        ce_n                    => sdram_cen,
        oe_n                    => sdram_oen,
        we_n                    => sdram_wen,
        lb_n                    => sdram_lbn,
        ub_n                    => sdram_ubn,
        addr                    => sdram_address,
        dq                      => sdram_dq
    );

    -- sdram_sim : entity wave.sdram_sim
    -- generic map (
    --     DEPTH_LOG2              => 15
    -- )
    -- port map (
    --     SDRAM_RESETN            => resetn,
    --     SDRAM_CLK               => sdram_clk,
    --     SDRAM_ADVN              => sdram_advn,
    --     SDRAM_CEN               => sdram_cen,
    --     SDRAM_CRE               => sdram_cre,
    --     SDRAM_OEN               => sdram_oen,
    --     SDRAM_WEN               => sdram_wen,
    --     SDRAM_LBN               => sdram_lbn,
    --     SDRAM_UBN               => sdram_ubn,
    --     SDRAM_WAIT              => sdram_wait,
    --     SDRAM_ADDRESS           => sdram_address,
    --     SDRAM_DQ                => sdram_dq
    -- );

    clk <= not clk after 5 ns;
    resetn <= '1' after 1 us;
    reset <= not resetn;
    switches <= x"9400";


end architecture;
