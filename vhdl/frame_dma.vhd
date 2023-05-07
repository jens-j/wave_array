library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity frame_dma is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        frame_index             : in  integer range 0 to WAVE_MAX_FRAMES - 1;
        dma2table               : out t_dma2table_array(0 to N_TABLES - 1);
        sdram_outputs           : in  t_sdram_output_array(0 to N_TABLES - 1);
        sdram_inputs            : out t_sdram_input_array(0 to N_TABLES - 1)
    );
end entity;

architecture arch of frame_dma is

    signal s_dma2ctrl           : t_dma2ctrl_array(0 to N_TABLES - 1);
    signal s_ctrl2dma           : t_ctrl2dma_array(0 to N_TABLES - 1);
    signal s_dma2table          : t_dma2table_array(0 to N_TABLES - 1);

begin

    dma2table <= s_dma2table;

    dma_control_gen : for i in 0 to N_TABLES - 1 generate

        dma_control : entity wave.dma_control
        port map (
            clk                     => clk,
            reset                   => reset,
            config                  => config,
            frame_index             => frame_index,
            dma2ctrl                => s_dma2ctrl(i),
            ctrl2dma                => s_ctrl2dma(i),
            buffer_index            => s_dma2table(i).buffer_index 
        );

        dma : entity wave.dma
        port map (
            clk                     => clk,
            reset                   => reset,
            ctrl2dma                => s_ctrl2dma(i),
            dma2ctrl                => s_dma2ctrl(i),
            sdram_output            => sdram_outputs(i),
            sdram_input             => sdram_inputs(i),
            wave_mem_wea            => s_dma2table(i).wave_mem_wea,
            wave_mem_addra          => s_dma2table(i).wave_mem_addra,
            wave_mem_dina           => s_dma2table(i).wave_mem_dina
        );

    end generate;



end architecture;
