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
        value                   : in  std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
        next_sample             : in  std_logic;
        sample                  : out t_stereo_sample
    );
end entity;

architecture arch of synth_subsystem is

    signal velocities_s         : t_table_phase_array(NUMBER_OF_VOICES - 1 downto  0);
    signal osc_samples_s        : t_mono_sample_array(NUMBER_OF_VOICES - 1 downto 0);

begin

    sample(0) <= osc_samples_s(0);
    sample(1) <= osc_samples_s(0);

    -- Map value to 0 - 1/4 phase max phase
    velocities_s(0) <=
        "00" & unsigned(value) & (0 to t_table_phase'length - ADC_SAMPLE_SIZE - 3 => '0');

    oscillator : entity wave.oscillator
    generic map (
        N_OSCILLATORS       => NUMBER_OF_VOICES,
        INIT_FILE           => string'("saw_mipmap.data")
    )
    port map (
        clk                 => clk,
        reset               => reset,
        velocities          => velocities_s,
        next_sample         => next_sample,
        samples             => osc_samples_s
    );
end architecture;
