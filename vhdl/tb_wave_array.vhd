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

    signal clk                      : std_logic := '0';
    signal resetn                   : std_logic := '0';
    signal reset                    : std_logic := '0';
    signal sdata                    : std_logic := '0';
    signal sclk                     : std_logic := '0';
    signal wsel                     : std_logic := '0';
    signal uart_rx                  : std_logic := '0';
    signal uart_tx                  : std_logic := '0';
    signal midi_uart                : std_logic := '0';
    signal leds                     : std_logic_vector(15 downto 0) := (others => '0');
    signal switches                 : std_logic_vector(15 downto 0) := (others => '0');
    signal xadc_3p                  : std_logic := '0';
    signal xadc_3n                  : std_logic := '0';
    signal display_segments         : std_logic_vector(6 downto 0) := (others => '0');
    signal display_anodes           : std_logic_vector(7 downto 0) := (others => '0');

    signal s_rst_n                  : std_logic;
    signal s_ck                     : std_logic;
    signal s_ck_n                   : std_logic;
    signal s_cke                    : std_logic;
    signal s_ras_n                  : std_logic;
    signal s_cas_n                  : std_logic;
    signal s_we_n                   : std_logic;
    signal s_dm_tdqs                : std_logic_vector(1 downto 0);
    signal s_ba                     : std_logic_vector(2 downto 0);
    signal s_addr                   : std_logic_vector(14 downto 0);
    signal s_dq                     : std_logic_vector(15 downto 0);
    signal s_dqs                    : std_logic_vector(1 downto 0);
    signal s_dqs_n                  : std_logic_vector(1 downto 0);
    signal s_tdqs_n                 : std_logic_vector(1 downto 0);
    signal s_odt                    : std_logic; 

    -- signal sdram_clk                : std_logic := '0';
    -- signal sdram_advn               : std_logic := '0';
    -- signal sdram_cen                : std_logic := '0';
    -- signal sdram_cre                : std_logic := '0';
    -- signal sdram_oen                : std_logic := '0';
    -- signal sdram_wen                : std_logic := '0';
    -- signal sdram_lbn                : std_logic := '0';
    -- signal sdram_ubn                : std_logic := '0';
    -- signal sdram_wait               : std_logic := '0';
    -- signal sdram_address            : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0) := (others => '0');
    -- signal sdram_dq                 : std_logic_vector(SDRAM_WIDTH - 1 downto 0) := (others => '0');

    -- component cellram is
    -- port (
    --     clk                     : in    std_logic;
    --     adv_n                   : in    std_logic;
    --     cre                     : in    std_logic;
    --     o_wait                  : out   std_logic;
    --     ce_n                    : in    std_logic;
    --     oe_n                    : in    std_logic;
    --     we_n                    : in    std_logic;
    --     lb_n                    : in    std_logic;
    --     ub_n                    : in    std_logic;
    --     addr                    : in    std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
    --     dq                      : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0));
    -- end component;

    component ddr3 is
    port (
        rst_n                       : in    std_logic;
        ck                          : in    std_logic;
        ck_n                        : in    std_logic;
        cke                         : in    std_logic;
        cs_n                        : in    std_logic;
        ras_n                       : in    std_logic;
        cas_n                       : in    std_logic;
        we_n                        : in    std_logic;
        dm_tdqs                     : inout std_logic_vector(1 downto 0);
        ba                          : in    std_logic_vector(2 downto 0);
        addr                        : in    std_logic_vector(14 downto 0);
        dq                          : inout std_logic_vector(15 downto 0);
        dqs                         : inout std_logic_vector(1 downto 0);
        dqs_n                       : inout std_logic_vector(1 downto 0);
        tdqs_n                      : out   std_logic_vector(1 downto 0);
        odt                         : in    std_logic);    
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
        DDR3_DQ                 => s_dq,
        DDR3_DQS_P              => s_dqs,
        DDR3_DQS_N              => s_dqs_n,
        DDR3_ADDR               => s_addr,
        DDR3_BA                 => s_ba,
        DDR3_RAS_N              => s_ras_n,
        DDR3_CAS_N              => s_cas_n,
        DDR3_WE_N               => s_we_n,
        DDR3_RESET_N            => s_rst_n,
        DDR3_CK_P               => s_ck,
        DDR3_CK_N               => s_ck_n,
        DDR3_CKE                => s_cke,
        DDR3_DM                 => s_dm_tdqs,
        DDR3_ODT                => s_odt
    );

    ddr3_verilog : ddr3
    port map (
        rst_n                   => s_rst_n,
        ck                      => s_ck,
        ck_n                    => s_ck_n,
        cke                     => s_cke,
        cs_n                    => '0',
        ras_n                   => s_ras_n,
        cas_n                   => s_cas_n,
        we_n                    => s_we_n,
        dm_tdqs                 => s_dm_tdqs,
        ba                      => s_ba,
        addr                    => s_addr,
        dq                      => s_dq,
        dqs                     => s_dqs,
        dqs_n                   => s_dqs_n,
        tdqs_n                  => s_tdqs_n,
        odt                     => s_odt 
    );

    clk <= not clk after 5 ns;
    resetn <= '1' after 1 us;
    reset <= not resetn;
    switches <= x"9400";

end architecture;
