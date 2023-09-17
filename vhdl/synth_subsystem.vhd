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
        status                  : in  t_status;
        next_sample             : in  std_logic;
        pot_value               : in  std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
        voices                  : in  t_voice_array(0 to POLYPHONY_MAX - 1);
        sample                  : out t_stereo_sample;
        sdram_output            : in  t_sdram_output;
        sdram_input             : out t_sdram_input;
        envelope_active         : out std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        mod_sources             : out t_mods_array;
        mod_destinations        : out t_modd_array;
        new_period              : out std_logic_vector(N_VOICES - 1 downto 0); -- High in first cycle of waveform period.
        pitched_osc_inputs      : out t_pitched_osc_inputs;
        spread_osc_inputs       : out t_spread_osc_inputs
    );
end entity;

architecture arch of synth_subsystem is

    signal s_osc_inputs         : t_osc_input_array(0 to POLYPHONY_MAX - 1);
    signal s_osc_samples        : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
    signal s_filter_samples     : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
    signal s_mixer_left_sample_out  : t_mono_sample;
    signal s_mixer_right_sample_out : t_mono_sample;
    signal s_dma2table          : t_dma2table_array(0 to N_TABLES - 1);
    signal s_table2dma          : t_table2dma_array(0 to N_TABLES - 1);
    signal s_lfo_out            : t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
    signal s_envelope_ctrl      : t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
    signal s_mod_sources        : t_mods_array;
    signal s_mod_destinations   : t_modd_array;
    signal s_ctrl_pot           : t_ctrl_value;
    signal s_pitch_ctrl         : t_osc_ctrl_array;
    signal s_pitched_osc_inputs : t_pitched_osc_inputs;

begin

    mod_destinations <= s_mod_destinations;
    mod_sources <= s_mod_sources;
    pitched_osc_inputs <= s_pitched_osc_inputs;

    s_pitch_ctrl(0) <= s_mod_destinations(MODD_OSC_0_FREQ);
    s_pitch_ctrl(1) <= s_mod_destinations(MODD_OSC_1_FREQ);
    
    -- Convert potentiometer value to a (unsigned) control_value.
    s_ctrl_pot <= '0' & signed(pot_value) & (CTRL_SIZE - ADC_SAMPLE_SIZE - 2 downto 0 => '0');

    -- Connect mod source array.
    mods_assigne : for i in 0 to POLYPHONY_MAX - 1 generate
        s_mod_sources(MODS_NONE)(i)     <= (others => '0');
        s_mod_sources(MODS_POT)(i)      <= s_ctrl_pot;
        s_mod_sources(MODS_ENVELOPE)(i) <= s_envelope_ctrl(i);
        s_mod_sources(MODS_LFO)(i)      <= s_lfo_out(i);
    end generate;

    -- This does not synthesize correctly.
    -- s_mod_sources(MODS_NONE)     <= (0 to POLYPHONY_MAX - 1 => (others => '0'));
    -- s_mod_sources(MODS_POT)      <= (0 to POLYPHONY_MAX - 1 => s_ctrl_pot);
    -- s_mod_sources(MODS_ENVELOPE) <= s_envelope_ctrl;
    -- s_mod_sources(MODS_LFO)      <= (0 to POLYPHONY_MAX - 1 => s_lfo_out(0));

    osc_controller : entity osc.osc_controller
    port map(
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        voices                  => voices,
        osc_inputs              => s_osc_inputs
    );

    pitch_mod : entity wave.pitch_modulator
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        pitch_ctrl              => s_pitch_ctrl,
        osc_inputs              => s_osc_inputs,
        pitched_osc_inputs      => s_pitched_osc_inputs
    );

    osc_stack : entity osc.oscillator_subsystem
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        pitched_osc_inputs      => s_pitched_osc_inputs,
        dma2table               => s_dma2table,
        table2dma               => s_table2dma,
        mod_destinations        => s_mod_destinations,
        output_samples          => s_osc_samples,
        new_period              => new_period,
        spread_osc_inputs       => spread_osc_inputs
    );


    filter : entity wave.state_variable_filter
    generic map (
        N_INPUTS                => POLYPHONY_MAX
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        cutoff_control          => s_mod_destinations(MODD_FILTER_CUTOFF),
        resonance_control       => s_mod_destinations(MODD_FILTER_RESONANCE),
        sample_in               => s_osc_samples,
        sample_out              => s_filter_samples
    );

    lfo : entity wave.lfo
    generic map (
        N_OUTPUTS               => POLYPHONY_MAX
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        lfo_out                 => s_lfo_out
    );

    envelope : entity wave.envelope 
    generic map(
        N_INPUTS                => POLYPHONY_MAX
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        ctrl_out                => s_envelope_ctrl,
        envelope_active         => envelope_active
    );

    voice_mixer_subsys : entity wave.voice_mixer_subsystem
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        ctrl_in                 => s_mod_destinations(MODD_MIXER),
        sample_in               => s_filter_samples,
        sample_out              => sample
    );

    mod_matrix : entity wave.mod_matrix 
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        mod_sources             => s_mod_sources,
        mod_destinations        => s_mod_destinations 
    );

    frame_dma : entity wave.frame_dma
    port map(
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        dma2table               => s_dma2table,
        table2dma               => s_table2dma,
        sdram_input             => sdram_input,
        sdram_output            => sdram_output
    );

end architecture;
