library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library osc;


entity oscillator is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic; -- Next sample trigger.
        osc_inputs              : in  t_osc_input_array(0 to N_VOICES - 1);
        frame_ctrl_index        : in  t_frame_ctrl_index;
        dma2table               : in  t_dma2table;
        table2dma               : out t_table2dma;
        frame_control           : in  t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        output_samples          : out t_mono_sample_array(0 to N_VOICES - 1);
        addrgen_output          : out t_addrgen2table_array(0 to N_VOICES - 1)
    );
end entity;

architecture arch of oscillator is

    signal s_intermediate_samples   : t_stereo_sample_array(0 to N_VOICES - 1);
    signal s_addrgen2table          : t_addrgen2table_array(0 to N_VOICES - 1);

begin

    addrgen_output <= s_addrgen2table;

    table_addr_gen : entity osc.table_address_generator
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        osc_inputs              => osc_inputs,
        addrgen_output          => s_addrgen2table
    );

    table_interpolator : entity osc.table_interpolator
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        dma2table               => dma2table,
        table2dma               => table2dma,
        osc_inputs              => osc_inputs,
        frame_ctrl_index        => frame_ctrl_index,
        frame_control           => frame_control,
        addrgen_input           => s_addrgen2table,
        output_samples          => s_intermediate_samples
    );

    halfband : entity osc.halfband_filter
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        input_samples           => s_intermediate_samples,
        output_samples          => output_samples
    );

end architecture;
