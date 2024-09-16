library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library osc;


entity oscillator is
    generic (
        TABLE_INDEX             : integer range 0 to N_TABLES - 1
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic; -- Next sample trigger.
        osc_inputs              : in  t_osc_input_array(0 to N_VOICES - 1);
        frame_ctrl_index        : in  t_frame_ctrl_index;
        sync_in                 : in  t_hard_sync_array;
        sync_out                : out std_logic_vector(N_VOICES - 1 downto 0);
        dma2table               : in  t_dma2table;
        table2dma               : out t_table2dma;
        frame_control           : in  t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        output_samples          : out t_mono_sample_array(0 to N_VOICES - 1)
    );
end entity;

architecture arch of oscillator is

    signal s_intermediate_samples   : t_stereo_sample_array(0 to N_VOICES - 1);
    signal s_addrgen2table          : t_addrgen2table;
    signal s_table2addrgen          : t_table2addrgen;

begin

    table_addr_gen : entity osc.table_address_generator
    generic map (
        TABLE_INDEX             => TABLE_INDEX
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        next_sample             => next_sample,
        osc_inputs              => osc_inputs,
        sync_in                 => sync_in,
        sync_out                => sync_out,
        table2addrgen           => s_table2addrgen,
        addrgen2table           => s_addrgen2table
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
        addrgen2table           => s_addrgen2table,
        table2addrgen           => s_table2addrgen,
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
