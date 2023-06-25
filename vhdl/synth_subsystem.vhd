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
        pot_value               : in  std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
        voices                  : in  t_voice_array(0 to N_VOICES - 1);
        addrgen_output          : out t_addrgen2table_array(0 to N_VOICES - 1); -- Debug output.
        sample                  : out t_stereo_sample;
        sdram_output            : in  t_sdram_output;
        sdram_input             : out t_sdram_input;
        envelope_active         : out std_logic_vector(N_VOICES - 1 downto 0);
        mod_sources             : out t_mods_array;
        mod_destinations        : out t_modd_array
    );
end entity;

architecture arch of synth_subsystem is

    signal s_osc_inputs         : t_osc_input_array(0 to N_VOICES - 1);
    signal s_osc_samples        : t_mono_sample_array(0 to N_VOICES - 1);
    signal s_filter_samples     : t_mono_sample_array(0 to N_VOICES - 1);
    signal s_mixer_sample_out   : t_mono_sample;
    signal s_dma2table          : t_dma2table_array(0 to N_TABLES - 1);
    signal s_table2dma          : t_table2dma_array(0 to N_TABLES - 1);
    signal s_lfo_sine           : t_ctrl_value_array(0 to 0);
    signal s_lfo_square         : t_ctrl_value_array(0 to 0);
    signal s_lfo_saw            : t_ctrl_value_array(0 to 0);
    signal s_envelope_ctrl      : t_ctrl_value_array(0 to N_VOICES - 1);
    signal s_mod_sources        : t_mods_array;
    signal s_mod_destinations   : t_modd_array;
    signal s_ctrl_pot           : t_ctrl_value;

begin

    -- Connect output samples.
    sample(0) <= s_mixer_sample_out;
    sample(1) <= s_mixer_sample_out;
    
    mod_destinations <= s_mod_destinations;
    mod_sources <= s_mod_sources;
    
    -- Convert potentiometer value to a control_value.
    s_ctrl_pot <= '0' & signed(pot_value) & (CTRL_SIZE - ADC_SAMPLE_SIZE - 2 downto 0 => '0');

    -- Connect mod source array.
    mods_assigne : for i in 0 to N_VOICES - 1 generate
        s_mod_sources(MODS_NONE)(i)     <= (others => '0');
        s_mod_sources(MODS_POT)(i)      <= s_ctrl_pot;
        s_mod_sources(MODS_ENVELOPE)(i) <= s_envelope_ctrl(i);
        s_mod_sources(MODS_LFO)(i)      <= s_lfo_sine(0);
    end generate;

    -- This does not synthesize correctly.
    -- s_mod_sources(MODS_NONE)     <= (0 to N_VOICES - 1 => (others => '0'));
    -- s_mod_sources(MODS_POT)      <= (0 to N_VOICES - 1 => s_ctrl_pot);
    -- s_mod_sources(MODS_ENVELOPE) <= s_envelope_ctrl;
    -- s_mod_sources(MODS_LFO)      <= (0 to N_VOICES - 1 => s_lfo_sine(0));

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
        osc_inputs              => s_osc_inputs
    );


    oscillator : entity osc.oscillator
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        osc_inputs              => s_osc_inputs,
        dma2table               => s_dma2table(0),
        table2dma               => s_table2dma(0),
        frame_control           => s_mod_destinations(2),
        -- frame_control           => s_mod_sources(1),
        output_samples          => s_osc_samples,
        addrgen_output          => addrgen_output
    );

    filter : entity wave.state_variable_filter
    generic map (
        N_INPUTS                => N_VOICES
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        cutoff_control          => s_mod_destinations(0),
        resonance_control       => s_mod_destinations(1),
        -- cutoff_control          => (0 to N_VOICES - 1 => config.base_ctrl(0)),
        -- resonance_control       => (0 to N_VOICES - 1 => config.base_ctrl(1)),
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
        ctrl_out                => s_envelope_ctrl,
        envelope_active         => envelope_active
    );

    mixer : entity wave.mixer
    generic map (
        N_INPUTS                => N_VOICES
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        sample_in               => s_filter_samples,
        ctrl_in                 => s_mod_destinations(3),
        -- ctrl_in                 => s_mod_sources(3),
        next_sample             => next_sample,
        sample_out              => s_mixer_sample_out
    );

    mod_matrix : entity wave.mod_matrix 
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
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
