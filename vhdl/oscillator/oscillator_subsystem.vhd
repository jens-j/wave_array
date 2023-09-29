library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library osc;

-- Contrains multiple wavetables that are mixed together into a single waveform.
entity oscillator_subsystem is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic; -- Next sample trigger.
        pitched_osc_inputs      : in  t_pitched_osc_inputs;
        dma2table               : in  t_dma2table_array(0 to N_TABLES - 1);
        table2dma               : out t_table2dma_array(0 to N_TABLES - 1);
        mod_destinations        : in  t_modd_array; -- 2D array of frame control values for each table, for each voice.
        output_samples          : out t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        spread_osc_inputs       : out t_spread_osc_inputs;
        lowest_velocity         : out t_osc_phase;
        addrgen_outputs         : out t_addrgen_output_array
    );
end entity;

architecture arch of oscillator_subsystem is

    type t_new_period_array is array (0 to N_TABLES - 1) of std_logic_vector(N_VOICES - 1 downto 0);
    
    signal s_osc_samples : t_osc_sample_array;
    signal s_mixer_ctrl  : t_osc_ctrl_array;
    signal s_table_mixer_samples : t_mono_sample_array(0 to N_VOICES - 1);
    signal s_spread_osc_inputs : t_spread_osc_inputs;
    signal s_frame_ctrl_index : t_frame_ctrl_index;
    signal s_addrgen_outputs : t_addrgen_output_array;

begin 

    spread_osc_inputs <= s_spread_osc_inputs;
    addrgen_outputs <= s_addrgen_outputs;

    mix_ctrl_gen : for i in 0 to N_TABLES - 1 generate 
        s_mixer_ctrl(i) <= mod_destinations(MODD_OSC_0_MIX + i);
    end generate; 

    unison : Entity osc.unison_spread 
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        spread_ctrl             => mod_destinations(MODD_UNISON),
        pitched_osc_inputs      => pitched_osc_inputs,
        spread_osc_inputs       => s_spread_osc_inputs,
        frame_ctrl_index        => s_frame_ctrl_index,
        lowest_velocity         => lowest_velocity
    );

    osc_gen : for n in 0 to N_TABLES - 1 generate
        osc_n : entity osc.oscillator
        port map (
            clk                     => clk,
            reset                   => reset,
            config                  => config,
            status                  => status,
            next_sample             => next_sample,
            osc_inputs              => s_spread_osc_inputs(n),
            frame_ctrl_index        => s_frame_ctrl_index,
            dma2table               => dma2table(n),
            table2dma               => table2dma(n),
            frame_control           => mod_destinations(MODD_OSC_0_FRAME + n),
            output_samples          => s_osc_samples(n),
            addrgen_output          => s_addrgen_outputs(n)
        );
    end generate;

    table_mixer : entity osc.table_mixer
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        control                 => s_mixer_ctrl,
        samples_in              => s_osc_samples,
        samples_out             => s_table_mixer_samples
    );

    unison_mixer : entity osc.unison_mixer 
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        sample_in               => s_table_mixer_samples,
        sample_out              => output_samples
    );

end architecture;