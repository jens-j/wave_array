library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wave_array_pkg.all;
use work.midi_pkg.all;

entity tb_oscillator is
end entity;

architecture arch of tb_oscillator is

    constant MIDI_INIT : t_midi_voice := ('1', '0', Eb, 4);

    signal clk_s             : std_logic := '0';
    signal reset_s           : std_logic := '1';
    signal midi_s            : t_midi_voice := MIDI_INIT;
    signal next_sample_s     : std_logic := '1';
    signal sample_s          : t_mono_sample;

begin

    dut : entity work.oscillator
    port map(
        clk                     => clk_s,
        reset                   => reset_s,
        midi                    => midi_s,
        next_sample             => next_sample_s,
        sample                  => sample_s
    );

    clk_s <= not clk_s after 5 ns;
    reset_s <= '0' after 100 ns;


end architecture;
