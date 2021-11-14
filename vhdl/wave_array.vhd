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
        I2S_SDATA               : out std_logic
    );
end entity;

architecture arch of wave_array is

    signal clk_s                : std_logic;
    signal reset_al_s           : std_logic;
    signal reset_ah_s           : std_logic;
    signal osc_samples_s        : t_mono_sample_array(NUMBER_OF_VOICES - 1 downto 0);
    signal mono_mix_s           : t_mono_sample;
    signal stereo_mix_s         : t_stereo_sample;
    signal next_sample_s        : std_logic;
    signal voices_s             : t_voice_array(NUMBER_OF_VOICES - 1 downto 0);
    signal status_byte_s        : t_byte;

    component BUFG
    port (
        I: in std_logic;
        O: out std_logic);
    end component;

begin

    -- Connect inputs.
    reset_ah_s <= not BTN_RESET;
    reset_al_s <= BTN_RESET;

    -- Connect outputs
    gen_voice_led: for i in 0 to NUMBER_OF_VOICES - 1 generate
        LEDS(15 - i) <= voices_s(i).enable;
    end generate;

    LEDS(15 - NUMBER_OF_VOICES downto 8) <= (others => '0');
    LEDS(7 downto 0)   <= status_byte_s;
    UART_TX            <= MIDI_RX;
    stereo_mix_s(0)    <= mono_mix_s;
    stereo_mix_s(1)    <= mono_mix_s;

    clk_buffer : BUFG
    port map(
        I => EXT_CLK,
        O => clk_s
    );

    slave : entity wave.midi_slave
    generic map (
        n_voices                => NUMBER_OF_VOICES
    )
    port map (
        clk                     => clk_s,
        reset                   => reset_ah_s,
        uart_rx                 => MIDI_RX,
        midi_channel            => SWITCHES(3 downto 0),
        voices                  => voices_s,
        status_byte             => status_byte_s
    );

    voice_gen : for i in 0 to NUMBER_OF_VOICES - 1 generate
        voice_n : entity wave.oscillator
        port map (
            clk                     => clk_s,
            reset                   => reset_ah_s,
            midi_voice              => voices_s(i),
            next_sample             => next_sample_s,
            sample                  => osc_samples_s(i)
        );
    end generate;

    mixer : entity wave.mixer
    generic map (
        N_INPUTS                => NUMBER_OF_VOICES
    )
    port map (
        clk                     => clk_s,
        reset                   => reset_ah_s,
        sample_in               => osc_samples_s,
        next_sample             => next_sample_s,
        sample_out              => mono_mix_s
    );

    i2s_interface : entity wave.i2s_interface
    port map(
        clk                     => clk_s,
        reset                   => reset_ah_s,
        sample_in               => stereo_mix_s,
        next_sample             => next_sample_s,
        sdata                   => I2S_SDATA,
        sclk                    => I2S_SCLK,
        wsel                    => I2S_WSEL
    );

    -- microblaze_sys : entity wave.microblaze_sys_wrapper
    -- port map(
    --     clk_100MHz              => clk_s,
    --     reset_rtl_0             => reset_al_s,
    --     uart_rtl_0_rxd          => UART_RX,
    --     uart_rtl_0_txd          => UART_TX,
    --     leds                    => open,
    --     switches                => SWITCHES,
    --     saw_slope               => saw_slope_s
    -- );

end architecture;
