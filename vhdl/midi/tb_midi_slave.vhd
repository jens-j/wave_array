library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;

library oscillator;
library i2s;


entity tb_midi_slave is
end entity;


architecture arch of tb_midi_slave is

    constant MIDI_CHANNEL       : std_logic_vector(3 downto 0) := x"5";

    signal clk_s                : std_logic := '1';
    signal reset_ah_s           : std_logic := '1';
    signal midi_channel_s       : std_logic_vector(3 downto 0) := MIDI_CHANNEL;
    signal voices_s             : t_voice_array(0 downto 0);
    signal next_sample_s        : std_logic;
    signal sample_s             : t_mono_sample;
    signal sample_in_s          : t_stereo_sample;
    signal uart_s               : std_logic;

    signal i2s_sdata_s          : std_logic;
    signal i2s_sclk_s           : std_logic;
    signal i2s_wsel_s           : std_logic;

begin

    sample_in_s(0) <= sample_s;
    sample_in_s(1) <= sample_s;

    tester : entity midi.midi_tester
    port map (
        clk                     => clk_s,
        reset                   => reset_ah_s,
        uart_tx                 => uart_s
    );

    slave : entity midi.midi_slave
    generic map (
        n_voices                => 1
    )
    port map (
        clk                     => clk_s,
        reset                   => reset_ah_s,
        uart_rx                 => uart_s,
        midi_channel            => midi_channel_s,
        voices                  => voices_s
    );

    oscillator : entity oscillator.oscillator
    port map (
        clk                     => clk_s,
        reset                   => reset_ah_s,
        midi_voice              => voices_s(0),
        next_sample             => next_sample_s,
        sample                  => sample_s
    );

    i2s_interface : entity i2s.i2s_interface
    port map(
        clk                     => clk_s,
        reset                   => reset_ah_s,
        sample_in               => sample_in_s,
        next_sample             => next_sample_s,
        sdata                   => i2s_sdata_s,
        sclk                    => i2s_sclk_s,
        wsel                    => i2s_wsel_s
    );

    clk_s <= not clk_s after 5 ns;
    reset_ah_s <= '1', '0' after 100 ns;

end architecture;
