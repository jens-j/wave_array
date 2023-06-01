library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;

library osc;


entity synth_subsystem is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        next_sample             : in  std_logic;
        frame_control           : in  t_ctrl_value;
        voices                  : in  t_voice_array(0 to N_VOICES - 1);
        addrgen_output          : out t_addrgen2table_array(0 to N_VOICES - 1); -- Debug output.
        sample                  : out t_stereo_sample;
        sdram_outputs           : in  t_sdram_output_array(0 to N_TABLES - 1);
        sdram_inputs            : out t_sdram_input_array(0 to N_TABLES - 1);
        frame_index             : out integer range 0 to WAVE_MAX_FRAMES - 1;
        frame_position          : out t_osc_position;
        frame_bank              : out integer range 0 to 3
    );
end entity;

architecture arch of synth_subsystem is

    signal s_osc_inputs         : t_osc_input_array(0 to N_VOICES - 1);
    signal s_osc_samples        : t_mono_sample_array(N_VOICES - 1 downto 0);
    signal s_filter_samples     : t_mono_sample_array(N_VOICES - 1 downto 0);
    signal s_mixer_sample_out   : t_mono_sample;
    signal s_dma2table          : t_dma2table_array(0 to N_TABLES - 1);
    signal s_lfo_sine           : t_ctrl_value_array(0 to 0);
    signal s_lfo_square         : t_ctrl_value_array(0 to 0);
    signal s_lfo_saw            : t_ctrl_value_array(0 to 0);
    signal s_envelope_ctrl      : t_ctrl_value_array(0 to N_VOICES - 1);

    signal s_frame_index        : integer range 0 to WAVE_MAX_FRAMES - 1;
    signal s_frame_position     : t_osc_position;

begin

    sample(0) <= s_mixer_sample_out;
    sample(1) <= s_mixer_sample_out;

    frame_index <= s_frame_index;
    frame_position <= s_frame_position;
    frame_bank <= s_dma2table(0).buffer_index;

    -- Control frame position with the lfo or the potentiometer for simulation or synthesis respectively.
    dma_input_proc : process(config, s_lfo_sine, frame_control)
        variable v_frame_control : t_ctrl_value;
    begin

        if SIMULATION then 
            v_frame_control := s_lfo_sine(0);
        else 
            v_frame_control := frame_control;
        end if;

        if config.dma_n_frames_log2 = 0 then 
            s_frame_index <= 0;
            s_frame_position <= unsigned(v_frame_control(CTRL_SIZE - 1 downto CTRL_SIZE - OSC_SAMPLE_FRAC));
        else
            s_frame_index <= to_integer( 
                v_frame_control(CTRL_SIZE - 1 downto CTRL_SIZE - config.dma_n_frames_log2));

            s_frame_position <= unsigned(v_frame_control(CTRL_SIZE - config.dma_n_frames_log2 - 1 
                downto CTRL_SIZE - config.dma_n_frames_log2 - OSC_SAMPLE_FRAC));
        end if;

    end process;

    
    lfo : entity wave.lfo
    generic map (
        N_OUTPUTS               => 1
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        sine_out                => s_lfo_sine,
        square_out              => s_lfo_square,
        saw_out                 => s_lfo_saw
    );

    osc_controller : entity osc.osc_controller
    port map(
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        voices                  => voices,
        frame_position          => s_frame_position,
        osc_inputs              => s_osc_inputs
    );


    oscillator : entity osc.oscillator
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        dma2table               => s_dma2table(0),
        output_samples          => s_osc_samples,
        addrgen_output          => addrgen_output
    );

    mixer : entity wave.mixer
    generic map(
        N_INPUTS                => N_VOICES
    )
    port map(
        clk                     => clk,
        reset                   => reset,
        sample_in               => s_filter_samples,
        ctrl_in                 => s_envelope_ctrl,
        next_sample             => next_sample,
        sample_out              => s_mixer_sample_out
    );

    filter : entity wave.state_variable_filter
    generic map(
        N_INPUTS                => N_VOICES
    )
    port map(
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        sample_in               => s_osc_samples,
        sample_out              => s_filter_samples
    );

    envelope : entity wave.envelope 
    generic map(
        N_INPUTS                => N_VOICES
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        ctrl_out                => s_envelope_ctrl
    );

    frame_dma : entity wave.frame_dma
    port map(
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        frame_index     	    => s_frame_index,
        dma2table               => s_dma2table,
        sdram_inputs            => sdram_inputs,
        sdram_outputs           => sdram_outputs
    );

end architecture;
