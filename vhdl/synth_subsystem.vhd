library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;


entity synth_subsystem is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        voices                  : in  t_voice_array(NUMBER_OF_VOICES - 1 downto 0);
        next_sample             : in  std_logic;
        sample                  : out t_stereo_sample
    );
end entity;

architecture arch of synth_subsystem is


    signal osc_samples_s        : t_mono_sample_array(NUMBER_OF_VOICES - 1 downto 0);
    signal mono_sample_s        : t_mono_sample;

begin

    sample(0) <= mono_sample_s;
    sample(1) <= mono_sample_s;

    voice_gen : for i in 0 to NUMBER_OF_VOICES - 1 generate
        voice_n : entity wave.oscillator
        port map (
            clk                 => clk,
            reset               => reset,
            midi_voice          => voices(i),
            next_sample         => next_sample,
            sample              => osc_samples_s(i)
        );
    end generate;

    mixer : entity wave.mixer
    generic map (
        N_INPUTS                => NUMBER_OF_VOICES
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        sample_in               => osc_samples_s,
        next_sample             => next_sample,
        sample_out              => mono_sample_s
    );

end architecture;
