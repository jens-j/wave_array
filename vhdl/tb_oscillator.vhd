library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;

entity tb_oscillator is
end entity;

architecture arch of tb_oscillator is

    constant MIDI_INIT : t_midi_voice := ('1', '1', 60, 4);

    signal clk_s             : std_logic := '0';
    signal reset_s           : std_logic := '1';
    signal midi_voice_s      : t_midi_voice := MIDI_INIT;
    signal next_sample_s     : std_logic := '1';
    signal sample_s          : t_mono_sample;

begin

    dut : entity wave.oscillator
    port map(
        clk                     => clk_s,
        reset                   => reset_s,
        midi_voice              => midi_voice_s,
        next_sample             => next_sample_s,
        sample                  => sample_s
    );

    clk_s <= not clk_s after 5 ns;
    reset_s <= '0' after 100 ns;


end architecture;
