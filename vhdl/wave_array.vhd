library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;

library sdram;
library i2s;
library uart;


entity wave_array is
    port (
        EXT_CLK                 : in  std_logic;
        BTN_RESET               : in  std_logic;

        -- Board I/O.
        SWITCHES                : in  std_logic_vector(15 downto 0);
        LEDS                    : out std_logic_vector(15 downto 0);
        DISPLAY_SEGMENTS        : out std_logic_vector(6 downto 0);
        DISPLAY_ANODES          : out std_logic_vector(7 downto 0);

        -- PC UART interface.
        UART_RX                 : in  std_logic;
        UART_TX                 : out std_logic;

        -- Midi slave interface.
        MIDI_RX                 : in  std_logic;

        -- I2S audio output interface.
        I2S_SCLK                : out std_logic;
        I2S_WSEL                : out std_logic;
        I2S_SDATA               : out std_logic;

        -- XADC analog input.
        XADC_3P                 : in  std_logic;
        XADC_3N                 : in  std_logic;

        -- SDRAM interface.
        SDRAM_CLK               : out   std_logic;
        SDRAM_ADVN              : out   std_logic;
        SDRAM_CEN               : out   std_logic;
        SDRAM_CRE               : out   std_logic;
        SDRAM_OEN               : out   std_logic;
        SDRAM_WEN               : out   std_logic;
        SDRAM_LBN               : out   std_logic;
        SDRAM_UBN               : out   std_logic;
        SDRAM_WAIT              : in    std_logic;
        SDRAM_ADDRESS           : out   std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        SDRAM_DQ                : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0)
    );
end entity;

architecture arch of wave_array is

    signal s_system_clk         : std_logic;
    signal s_sdram_clk          : std_logic;
    signal s_i2s_clk            : std_logic;
    signal s_reset_al           : std_logic;
    signal s_reset_ah           : std_logic;
    signal s_pll_locked         : std_logic;
    signal s_sdram_clk_enable   : std_logic;

    signal s_next_sample        : std_logic;
    signal s_voices             : t_voice_array(0 to N_VOICES - 1);
    signal s_midi_status_byte   : t_byte;
    signal s_lowest_voice       : integer range 0 to N_VOICES - 1;
    signal s_pot_value          : std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
    signal s_sample             : t_stereo_sample;
    signal s_display_data       : std_logic_vector(31 downto 0);

    signal s_register_input     : t_register_input;
    signal s_register_output    : t_register_output;
    signal s_status             : t_status;
    signal s_config             : t_config;

    signal s_sdram_inputs       : t_sdram_input_array(0 to N_TABLES); -- 1 for the UART and 1 for each wavetable.
    signal s_sdram_outputs      : t_sdram_output_array(0 to N_TABLES);

    signal s_uart_timeout       : std_logic;
    signal s_uart_state         : integer;
    signal s_uart_count         : integer;
    signal s_uart_fifo_count    : integer;

    signal s_envelope_active    : std_logic_vector(N_VOICES - 1 downto 0); 

    signal s_mod_sources        : t_mods_array;
    signal s_mod_destinations   : t_modd_array;

    signal s_hk_write_enable    : std_logic;
    signal s_hk_data            : std_logic_vector(15 downto 0);
    signal s_hk_full            : std_logic;

    signal s_wave_write_enable  : std_logic;
    signal s_wave_data          : std_logic_vector(15 downto 0);
    signal s_wave_full          : std_logic;

    signal s_new_period         : std_logic_vector(N_VOICES - 1 downto 0);
    signal s_debug_wave_state_offload : integer;
    signal s_debug_wave_state_sample : integer;
    signal s_debug_wave_fifo_count : integer range 0 to 2047;
    signal s_debug_wave_timer   : std_logic_vector(15 downto 0);
    signal s_debug_wave_flags   : std_logic_vector(5 downto 0);
    signal s_debug_uart_flags   : std_logic_vector(3 downto 0);

begin

    -- Connect reset signals.
    s_reset_ah <= not BTN_RESET;
    s_reset_al <= BTN_RESET;

    -- Connect outputs.
    gen_voice_led : for i in 0 to minimum(4, N_VOICES - 1) generate
        LEDS(15 - i) <= s_voices(i).enable;
    end generate;

    LEDS(1) <= s_reset_ah;
    LEDS(0) <= s_config.led;

    I2S_SCLK <= s_i2s_clk;
    SDRAM_CLK <= s_sdram_clk;

    -- 7 segment display.
    s_display_data <=
        (15 downto 0 => '0') & std_logic_vector(s_mod_destinations(MODD_OSC_0_FRAME)(0));

        -- std_logic_vector(to_unsigned(s_voices(0).note.octave, 4))           -- 1 char octave
        -- & std_logic_vector(to_unsigned(s_voices(0).note.key, 4))            -- 1 char note
        -- -- & "0" & s_voices(0).midi_velocity                                -- 2 char midi velocity
        -- & (0 to 16 - ADC_SAMPLE_SIZE - 1 => '0') & s_pot_value;             -- 4 char potentiometer value

    s_status.pot_value          <= s_pot_value;
    s_status.mod_destinations   <= s_mod_destinations;
    s_status.mod_sources        <= s_mod_sources;

    s_status.debug_wave_state_offload <= s_debug_wave_state_offload;
    s_status.debug_wave_state_sample <= s_debug_wave_state_sample;
    s_status.debug_wave_fifo_count <= s_debug_wave_fifo_count;
    s_status.debug_wave_timer   <= s_debug_wave_timer;
    s_status.debug_wave_flags   <= s_debug_wave_flags;
    s_status.debug_uart_flags   <= s_debug_uart_flags;

    status_gen : for i in 0 to N_VOICES - 1 generate 
        s_status.voice_enabled(i) <= s_voices(i).enable;
        s_status.voice_active(i)  <= s_envelope_active(i);
    end generate;

    clk_subsys : entity wave.clk_subsystem
    port map (
        reset                   => s_reset_ah,
        ext_clk                 => EXT_CLK,         -- 100 MHz.
        system_clk              => s_system_clk,    -- 100 MHz.
        i2s_clk                 => s_i2s_clk,       -- 1.5360175 MHz.
        sdram_clk               => s_sdram_clk,     -- 100 MHz gated output clock shifted -72 degrees (2 ns early).
        sdram_clk_enable        => s_sdram_clk_enable,
        pll_locked              => s_pll_locked
    );

    midi_slave : entity midi.midi_slave
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        uart_rx                 => MIDI_RX,
        midi_channel            => SWITCHES(3 downto 0),
        envelope_active         => s_envelope_active,
        voices                  => s_voices,
        status_byte             => s_midi_status_byte,
        lowest_voice            => s_lowest_voice
    );

    uart_subsys : entity uart.uart_subsystem
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        register_input          => s_register_input,
        register_output         => s_register_output,
        sdram_input             => s_sdram_inputs(0),
        sdram_output            => s_sdram_outputs(0),
        hk_write_enable         => s_hk_write_enable,
        hk_data                 => s_hk_data,
        hk_full                 => s_hk_full,
        wave_write_enable       => s_wave_write_enable,
        wave_data               => s_wave_data,
        wave_full               => s_wave_full,
        UART_RX                 => UART_RX,
        UART_TX                 => UART_TX,
        debug_flags             => s_debug_uart_flags
    );

    hk_offload : entity wave.hk_offload
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        config                  => s_config,
        status                  => s_status,
        hk_write_enable         => s_hk_write_enable,
        hk_data                 => s_hk_data,
        hk_full                 => s_hk_full
    );

    wave_offload : entity wave.wave_offload
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        config                  => s_config,
        next_sample             => s_next_sample,
        new_period              => s_new_period,
        sample_in               => s_sample(0),
        lowest_voice            => s_lowest_voice,
        wave_write_enable       => s_wave_write_enable,
        wave_data               => s_wave_data,
        wave_full               => s_wave_full,
        debug_state_offload     => s_debug_wave_state_offload,
        debug_state_sample      => s_debug_wave_state_sample,
        debug_fifo_count        => s_debug_wave_fifo_count,
        debug_timer             => s_debug_wave_timer,
        debug_flags             => s_debug_wave_flags
    );

    reg_file : entity wave.register_file
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        register_output         => s_register_output,
        register_input          => s_register_input,
        new_period              => s_new_period,
        status                  => s_status,
        config                  => s_config
    );

    synth_subsys : entity wave.synth_subsystem
    port map(
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        config                  => s_config,
        next_sample             => s_next_sample,
        pot_value               => s_pot_value,
        voices                  => s_voices,
        sample                  => s_sample,
        sdram_input             => s_sdram_inputs(1),
        sdram_output            => s_sdram_outputs(1),
        envelope_active         => s_envelope_active,
        mod_sources             => s_mod_sources,
        mod_destinations        => s_mod_destinations,
        new_period              => s_new_period
    );

    i2s_interface : entity i2s.i2s_interface
    port map (
        system_clk              => s_system_clk,
        i2s_clk                 => s_i2s_clk,
        reset                   => s_reset_ah,
        sample_in               => s_sample,
        next_sample             => s_next_sample,
        sdata                   => I2S_SDATA,
        wsel                    => I2S_WSEL
    );

    input : entity wave.input_subsystem
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        vauxp3                  => XADC_3P,
        vauxn3                  => XADC_3N,
        average                 => SWITCHES(11 downto 10),
        filter_length           => SWITCHES(14 downto 12),
        value                   => s_pot_value
    );

    seven_segment : entity wave.seven_segment
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        display_data            => s_display_data,
        segments                => DISPLAY_SEGMENTS,
        anodes                  => DISPLAY_ANODES
    );

    arbiter : entity sdram.sdram_arbiter
    generic map (
        N_CLIENTS               => 1 + N_TABLES
    )
    port map (
        clk                     => s_system_clk,
        sdram_clk               => s_sdram_clk,
        reset                   => s_reset_ah,
        pll_locked              => s_pll_locked,
        sdram_clk_enable        => s_sdram_clk_enable,
        sdram_inputs            => s_sdram_inputs,
        sdram_outputs           => s_sdram_outputs,
        SDRAM_ADVN              => SDRAM_ADVN,
        SDRAM_CEN               => SDRAM_CEN,
        SDRAM_CRE               => SDRAM_CRE,
        SDRAM_OEN               => SDRAM_OEN,
        SDRAM_WEN               => SDRAM_WEN,
        SDRAM_LBN               => SDRAM_LBN,
        SDRAM_UBN               => SDRAM_UBN,
        SDRAM_WAIT              => SDRAM_WAIT,
        SDRAM_ADDRESS           => SDRAM_ADDRESS,
        SDRAM_DQ                => SDRAM_DQ
    );


    -- microblaze_sys : entity wave.microblaze_sys_wrapper
    -- port map(
    --     clk_100MHz              => s_system_clk,
    --     reset_rtl_0             => s_reset_al,
    --     uart_rtl_0_rxd          => UART_RX,
    --     uart_rtl_0_txd          => UART_TX,
    --     leds                    => open,
    --     switches                => SWITCHES,
    --     saw_slope               => saw_slope_s
    -- );

end architecture;
