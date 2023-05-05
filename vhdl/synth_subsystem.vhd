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
        frame_control           : in  t_ctrl_value;
        voices                  : in  t_voice_array(0 to N_VOICES - 1);
        addrgen_output          : out t_addrgen2table_array(0 to N_VOICES - 1); -- Debug output.
        sample                  : out t_stereo_sample;
        sdram_outputs           : in  t_sdram_output_array(0 to N_TABLES - 1);
        sdram_inputs            : out t_sdram_input_array(0 to N_TABLES - 1);
        dma_inputs              : in  t_dma_input_array(0 to N_TABLES - 1)
    );
end entity;

architecture arch of synth_subsystem is

    signal s_osc_inputs         : t_osc_input_array(0 to N_VOICES - 1);
    signal s_osc_samples        : t_mono_sample_array(N_VOICES - 1 downto 0);
    signal s_mixer_sample_out   : t_mono_sample;
    signal s_dma_outputs        : t_dma_output_array(0 to N_TABLES - 1);
    signal s_dma_inputs         : t_dma_input_array(0 to N_TABLES - 1);
    signal s_lfo_sine           : t_ctrl_value_array(0 to 0);
    signal s_lfo_square         : t_ctrl_value_array(0 to 0);
    signal s_lfo_saw            : t_ctrl_value_array(0 to 0);
    signal s_lfo_velocity       : t_ctrl_value_array(0 to 0);
    signal s_frame_position      : t_osc_position;


begin

    sample(0) <= s_mixer_sample_out;
    sample(1) <= s_mixer_sample_out;

    s_lfo_velocity(0) <= x"3FFF";

    -- Connect the LFO sine output to the frame index and position in the dma and table interpolator respectively.
    dma_input_proc : process(dma_inputs, s_lfo_sine, frame_control)
    begin
        s_dma_inputs <= dma_inputs;

        if dma_inputs(0).n_frames_log2 = 0 then 
            s_dma_inputs(0).frame_index <= 0;
            s_frame_position <= unsigned(frame_control(CTRL_SIZE - 1 downto CTRL_SIZE - OSC_SAMPLE_FRAC));
        else
            s_dma_inputs(0).frame_index <= to_integer( 
                frame_control(CTRL_SIZE - 1 downto CTRL_SIZE - dma_inputs(0).n_frames_log2));

            s_frame_position <= unsigned(frame_control(CTRL_SIZE - dma_inputs(0).n_frames_log2 - 1 
                downto CTRL_SIZE - dma_inputs(0).n_frames_log2 - OSC_SAMPLE_FRAC));
        end if;

        -- s_frame_position <= t_osc_position(s_lfo_sine(0)(CTRL_SIZE - s_dma_inputs(0).n_frames_log2 - 1 
        --     downto CTRL_SIZE - s_dma_inputs(0).n_frames_log2 - OSC_SAMPLE_FRAC));

        
    end process;

    
    lfo : entity wave.lfo
    generic map (
        N_OUTPUTS               => 1
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        velocity                => s_lfo_velocity,
        sine_out                => s_lfo_sine,
        square_out              => s_lfo_square,
        saw_out                 => s_lfo_saw
    );

    osc_controller : entity wave.osc_controller
    port map(
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        voices                  => voices,
        frame_position          => s_frame_position,
        osc_inputs              => s_osc_inputs
    );


    oscillator : entity wave.oscillator
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        dma_output              => s_dma_outputs(0),
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
    port map(
        clk                     => clk,
        reset                   => reset,
        dma_inputs              => s_dma_inputs,
        dma_outputs             => s_dma_outputs,
        sdram_inputs            => sdram_inputs,
        sdram_outputs           => sdram_outputs
    );

end architecture;
