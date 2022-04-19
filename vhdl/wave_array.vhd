library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

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

    signal system_clk_s         : std_logic;
    signal i2s_clk_s            : std_logic;
    signal reset_al_s           : std_logic;
    signal reset_ah_s           : std_logic;

    signal next_sample_s        : std_logic;
    signal sample_s             : t_stereo_sample;
    signal voices_s             : t_voice_array(NUMBER_OF_VOICES - 1 downto 0);
    signal midi_status_byte_s   : t_byte;
    signal analog_value_s       : std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
    signal mipmap_level_s       : integer range 0 to MIPMAP_LEVELS - 1;

begin

    -- Connect inputs.
    reset_ah_s <= not BTN_RESET;
    reset_al_s <= BTN_RESET;

    -- Connect outputs.
    gen_voice_led: for i in 0 to NUMBER_OF_VOICES - 1 generate
        LEDS(15 - i) <= voices_s(i).enable;
    end generate;

    LEDS(15 - NUMBER_OF_VOICES downto 8) <= (others => '0');
    LEDS(7 downto 0)   <= midi_status_byte_s;
    UART_TX            <= MIDI_RX;
    I2S_SCLK           <= i2s_clk_s;


    clk_gen : entity wave.clk_generator_wrapper
    port map (
        reset                   => reset_ah_s,
        ext_clk                 => EXT_CLK,         -- 100 MHz
        system_clk              => system_clk_s,    -- 100 MHz
        i2s_clk                 => i2s_clk_s        -- 1536017.5 Hz
    );

    slave : entity wave.midi_slave
    generic map (
        n_voices                => NUMBER_OF_VOICES
    )
    port map (
        clk                     => system_clk_s,
        reset                   => reset_ah_s,
        uart_rx                 => MIDI_RX,
        midi_channel            => SWITCHES(3 downto 0),
        voices                  => voices_s,
        status_byte             => midi_status_byte_s
    );

    synth : entity wave.synth_subsystem
    port map (
        clk                     => system_clk_s,
        reset                   => reset_ah_s,
        mipmap_enable           => SWITCHES(10),
        interpolate_enable      => SWITCHES(9),
        value                   => analog_value_s,
        next_sample             => next_sample_s,
        mipmap_level            => mipmap_level_s,
        sample                  => sample_s
    );

    i2s_interface : entity wave.i2s_interface
    port map (
        system_clk              => system_clk_s,
        i2s_clk                 => i2s_clk_s,
        reset                   => reset_ah_s,
        sample_in               => sample_s,
        next_sample             => next_sample_s,
        sdata                   => I2S_SDATA,
        wsel                    => I2S_WSEL
    );

    seven_segment : entity wave.seven_segment
    port map (
        clk                     => system_clk_s,
        reset                   => reset_ah_s,
        display_data            => std_logic_vector(to_unsigned(mipmap_level_s, 16))
            & (16 - ADC_SAMPLE_SIZE - 1 downto 0 => '0') & analog_value_s,
        segments                => DISPLAY_SEGMENTS,
        anodes                  => DISPLAY_ANODES
    );

    input : entity wave.input_subsystem
    port map (
        clk                     => system_clk_s,
        reset                   => reset_ah_s,
        vauxp3                  => XADC_3P,
        vauxn3                  => XADC_3N,
        average                 => SWITCHES(12 downto 11),
        filter_length           => SWITCHES(15 downto 13),
        value                   => analog_value_s
    );

    -- microblaze_sys : entity wave.microblaze_sys_wrapper
    -- port map(
    --     clk_100MHz              => system_clk_s,
    --     reset_rtl_0             => reset_al_s,
    --     uart_rtl_0_rxd          => UART_RX,
    --     uart_rtl_0_txd          => UART_TX,
    --     leds                    => open,
    --     switches                => SWITCHES,
    --     saw_slope               => saw_slope_s
    -- );

end architecture;
