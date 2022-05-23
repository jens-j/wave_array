library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library ip;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;


entity wave_array is
    port (
        EXT_CLK                 : in  std_logic;
        BTN_RESET               : in  std_logic;
        SWITCHES                : in  std_logic_vector(15 downto 0);
        LEDS                    : out std_logic_vector(15 downto 0);
        UART_RX                 : in  std_logic;
        UART_TX                 : out std_logic;
        MIDI_RX                 : in  std_logic;
        I2S_SCLK                : out std_logic;
        I2S_WSEL                : out std_logic;
        I2S_SDATA               : out std_logic;
        XADC_3P                 : in  std_logic;
        XADC_3N                 : in  std_logic;
        DISPLAY_SEGMENTS        : out std_logic_vector(6 downto 0);
        DISPLAY_ANODES          : out std_logic_vector(7 downto 0)
    );
end entity;

architecture arch of wave_array is

    signal s_system_clk         : std_logic;
    signal s_i2s_clk            : std_logic;
    signal s_reset_al           : std_logic;
    signal s_reset_ah           : std_logic;

    signal s_next_sample        : std_logic;
    signal s_voices             : t_voice_array(N_VOICES - 1 downto 0);
    signal s_midi_status_byte   : t_byte;
    signal s_analog_value       : std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
    signal s_sample             : t_stereo_sample;


begin

    -- Connect inputs.
    s_reset_ah <= not BTN_RESET;
    s_reset_al <= BTN_RESET;

    -- Connect outputs.
    gen_voice_led: for i in 0 to N_VOICES - 1 generate
        LEDS(15 - i) <= s_voices(i).enable;
    end generate;

    LEDS(15 - N_VOICES downto 8) <= (others => '0');
    LEDS(7 downto 0)   <= s_midi_status_byte;
    UART_TX            <= MIDI_RX;
    I2S_SCLK           <= s_i2s_clk;


    clk_gen : entity ip.clk_generator
    port map (
        reset                   => s_reset_ah,
        ext_clk                 => EXT_CLK,         -- 100 MHz
        system_clk              => s_system_clk,    -- 100 MHz
        i2s_clk                 => s_i2s_clk        -- 1536017.5 Hz
    );

    midi_slave : entity wave.midi_slave
    generic map (
        n_voices                => N_VOICES
    )
    port map (
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        uart_rx                 => MIDI_RX,
        midi_channel            => SWITCHES(3 downto 0),
        voices                  => s_voices,
        status_byte             => s_midi_status_byte
    );

    synth_subsys : entity wave.synth_subsystem
    generic map(
        N_OSCILLATORS           => N_VOICES
    )
    port map(
        clk                     => s_system_clk,
        reset                   => s_reset_ah,
        next_sample             => s_next_sample,
        enable_midi             => SWITCHES(15),
        analog_input            => s_analog_value,
        voices                  => s_voices,
        sample                  => s_sample
    );

    i2s_interface : entity wave.i2s_interface
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
        value                   => s_analog_value
    );
    -- seven_segment : entity wave.seven_segment
    -- port map (
    --     clk                     => s_system_clk,
    --     reset                   => s_reset_ah,
    --     display_data            => std_logic_vector(to_unsigned(mipmap_level_s, 16))
    --         & (16 - ADC_SAMPLE_SIZE - 1 downto 0 => '0') & s_analog_value,
    --     segments                => DISPLAY_SEGMENTS,
    --     anodes                  => DISPLAY_ANODES
    -- );

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
