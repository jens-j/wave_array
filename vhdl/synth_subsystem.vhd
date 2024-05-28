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
        voices                  : in  t_voice_array(0 to POLYPHONY_MAX - 1);
        sample                  : out t_stereo_sample;
        sdram_output            : in  t_sdram_output;
        sdram_input             : out t_sdram_input;
        envelope_0_active       : out std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        envelope_1_active       : out std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        mod_sources             : out t_mods_array;
        mod_destinations        : out t_modd_array;
        pitched_osc_inputs      : out t_pitched_osc_inputs;
        spread_osc_inputs       : out t_spread_osc_inputs;
        lowest_velocity         : out t_osc_phase;
        osc_samples             : out t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        filter_samples          : out t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        addrgen_outputs         : out t_addrgen_output_array
    );
end entity;

architecture arch of synth_subsystem is

    signal s_osc_inputs             : t_osc_input_array(0 to POLYPHONY_MAX - 1);
    signal s_osc_samples            : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
    signal s_filter_samples         : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
    signal s_dma2table              : t_dma2table_array(0 to N_TABLES - 1);
    signal s_table2dma              : t_table2dma_array(0 to N_TABLES - 1);
    signal s_mod_sources            : t_mods_array;
    signal s_mod_destinations       : t_modd_array;
    signal s_pitch_ctrl             : t_osc_ctrl_array;
    signal s_pitched_osc_inputs     : t_pitched_osc_inputs;
    signal s_lfo_out                : t_lfo_out(0 to LFO_N - 1);
    signal s_envelope_out           : t_envelope_out(0 to ENV_N - 1);
    signal s_envelope_active        : std_logic_vector(ENV_N * POLYPHONY_MAX - 1 downto 0);
    signal s_unison_mixer_output    : t_unison_mixer_output;

begin

    -- Connect output ports.
    mod_destinations <= s_mod_destinations;
    mod_sources <= s_mod_sources;
    pitched_osc_inputs <= s_pitched_osc_inputs;
    osc_samples <= s_osc_samples;
    filter_samples <= s_filter_samples;
    envelope_0_active <= s_envelope_active(POLYPHONY_MAX - 1 downto 0);
    envelope_1_active <= s_envelope_active(2 * POLYPHONY_MAX - 1 downto POLYPHONY_MAX);

    s_pitch_ctrl(0) <= s_mod_destinations(MODD_OSC_0_FREQ);
    s_pitch_ctrl(1) <= s_mod_destinations(MODD_OSC_1_FREQ);
    
    -- Connect mod source array.
    mods_assign : for i in 0 to POLYPHONY_MAX - 1 generate
        s_mod_sources(MODS_NONE)(i)       <= (others => '0');
        s_mod_sources(MODS_ENVELOPE_0)(i) <= s_envelope_out(0)(i);
        s_mod_sources(MODS_ENVELOPE_1)(i) <= s_envelope_out(1)(i);
        s_mod_sources(MODS_LFO_0)(i)      <= s_lfo_out(0)(i);
        s_mod_sources(MODS_LFO_1)(i)      <= s_lfo_out(1)(i);
        s_mod_sources(MODS_VELOCITY)(i)   <= '0' & signed(voices(i).midi_velocity) & (0 to 7 => '0'); -- Extend 7 bit midi velocity to signed 16 bit control value.
        s_mod_sources(MODS_TABLE_0)(i)    <= s_unison_mixer_output(0)(i);
        s_mod_sources(MODS_TABLE_1)(i)    <= s_unison_mixer_output(1)(i);
    end generate;

    osc_controller : entity osc.osc_controller
    port map(
        clk                     => clk,
        reset                   => reset,
        status                  => status,
        next_sample             => next_sample,
        voices                  => voices,
        osc_inputs              => s_osc_inputs
    );

    pitch_mod : entity wave.pitch_modulator
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        pitch_ctrl              => s_pitch_ctrl,
        osc_inputs              => s_osc_inputs,
        pitched_osc_inputs      => s_pitched_osc_inputs
    );

    osc_subsys : entity osc.oscillator_subsystem
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
        spread_osc_inputs       => spread_osc_inputs,
        lowest_velocity         => lowest_velocity,
        addrgen_outputs         => addrgen_outputs,
        unison_mixer_output     => s_unison_mixer_output
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
        N_INSTANCES             => LFO_N,
        N_OUTPUTS               => POLYPHONY_MAX
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        lfo_input               => config.lfo_input,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        lfo_out                 => s_lfo_out
    );

    envelope : entity wave.envelope 
    generic map(
        N_INSTANCES             => ENV_N,
        N_OUTPUTS               => POLYPHONY_MAX
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        envelope_input          => config.envelope_input,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        envelope_out            => s_envelope_out,
        envelope_active         => s_envelope_active
    );

    voice_mixer_subsys : entity wave.voice_mixer_subsystem
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        ctrl_in                 => s_mod_destinations(MODD_VOLUME),
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
