library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library xil_defaultlib;

library wave;
use wave.wave_array_pkg.all;


entity i2s_interface is
    port (
        system_clk              : in  std_logic;
        i2s_clk                 : in  std_logic; -- I2S serial clock
        reset                   : in  std_logic;
        sample_in               : in  t_stereo_sample;
        next_sample             : out std_logic; -- strobe to request next sample
        -- I2S outputs
        sdata                   : out std_logic;
        wsel                    : out std_logic
    );
end entity;


architecture arch of i2s_interface is

    signal s_serializer_next_sample : std_logic;
    signal s_serializer_sample_in   : std_logic_vector(2 * SAMPLE_SIZE - 1 downto 0);
    signal s_fifo_full              : std_logic;
    signal s_fifo_din               : std_logic_vector(2 * SAMPLE_SIZE - 1 downto 0);

begin

    next_sample <= not s_fifo_full;
    s_fifo_din <= std_logic_vector(sample_in(1)) & std_logic_vector(sample_in(0));

    fifo : entity xil_defaultlib.i2s_fifo
    port map (
        rst                         => reset,
        wr_clk                      => system_clk,
        rd_clk                      => i2s_clk,
        din                         => s_fifo_din,
        wr_en                       => not s_fifo_full,
        rd_en                       => s_serializer_next_sample,
        dout                        => s_serializer_sample_in,
        full                        => s_fifo_full,
        empty                       => open
    );

    i2s_serializer : entity wave.i2s_serializer
    port map (
        clk                         => i2s_clk,
        reset                       => reset,
        sample_in                   => s_serializer_sample_in,
        next_sample                 => s_serializer_next_sample,
        sdata                       => sdata,
        wsel                        => wsel
    );

end architecture;
