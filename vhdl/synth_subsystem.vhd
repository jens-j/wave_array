library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;


entity synth_subsystem is
    generic (
        N_OSCILLATORS           : natural
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic;
        enable_midi             : in  std_logic; -- 1: use midi, 0: use potentiometer.
        analog_input            : in  std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
        voices                  : in  t_voice_array(0 to N_OSCILLATORS - 1);
        addrgen_output          : out t_addrgen_to_tableinterp_array(0 to N_OSCILLATORS - 1); -- Debug output.
        sample                  : out t_stereo_sample;
        UART_TX                 : out std_logic
    );
end entity;

architecture arch of synth_subsystem is

    signal s_osc_inputs         : t_osc_input_array(0 to N_OSCILLATORS - 1);
    signal s_osc_samples        : t_mono_sample_array(N_OSCILLATORS - 1 downto 0);
    signal s_mixer_sample_out   : t_mono_sample;

begin

    sample(0) <= s_mixer_sample_out;
    sample(1) <= s_mixer_sample_out;

    osc_controller : entity wave.osc_controller
    generic map (
        N_OSCILLATORS           => N_OSCILLATORS
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
        N_OSCILLATORS           => N_OSCILLATORS
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
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


    sample_uart : entity wave.sample_uart
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        sample                  => s_mixer_sample_out,
        UART_TX                 => UART_TX
    );

end architecture;
