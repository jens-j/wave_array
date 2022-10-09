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
        next_sample             : in  std_logic;
        enable_midi             : in  std_logic; -- 1: use midi, 0: use potentiometer.
        analog_input            : in  std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
        voices                  : in  t_voice_array(0 to N_VOICES - 1);
        addrgen_output          : out t_addrgen_to_tableinterp_array(0 to N_VOICES - 1); -- Debug output.
        sample                  : out t_stereo_sample;
        sdram_input             : in  t_sdram_input;
        sdram_output            : out t_sdram_output;
        frame_dma_inputs        : in  t_frame_dma_output_array(0 to N_TABLES - 1)
    );
end entity;

architecture arch of synth_subsystem is

    signal s_osc_inputs         : t_osc_input_array(0 to N_VOICES - 1);
    signal s_osc_samples        : t_mono_sample_array(N_VOICES - 1 downto 0);
    signal s_mixer_sample_out   : t_mono_sample;
    signal s_frame_dma_outputs  : t_frame_dma_outputs(0 to N_TABLES - 1);
    signal s_frame_ctrl_values  : t_ctrl_value_array(0 to N_TABLES)

begin

    sample(0) <= s_mixer_sample_out;
    sample(1) <= s_mixer_sample_out;

    osc_controller : entity wave.osc_controller
    generic map (
        N_VOICES                => N_VOICES
    )
    port map(
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        enable_midi             => enable_midi,
        voices                  => voices,
        analog_input            => analog_input,
        osc_inputs              => s_osc_inputs
    );


    oscillator : entity wave.oscillator
    generic map (
        N_VOICES                => N_VOICES
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        frame_dma_output        => s_frame_dma_outputs(0),
        output_samples          => s_osc_samples,
        addrgen_output          => addrgen_output
    );


    mixer : entity wave.mixer
    generic map(
        N_INPUTS                => N_OSCILLATORS
    )
    port map(
        clk                     => clk,
        reset                   => reset,
        sample_in               => s_osc_samples,
        next_sample             => next_sample,
        sample_out              => s_mixer_sample_out
    );

    frame_dma : entity wave.frame_dma
    generic map (
        N_TABLES                => N_TABLES
    )
    port map(
        clk                     => clk,
        reset                   => reset,
        sdram_input             => sdram_input,
        sdram_output            => sdram_output,
        frame_dma_inputs        => frame_dma_inputs,
        frame_dma_outputs       => s_frame_dma_outputs
    );

end architecture;
