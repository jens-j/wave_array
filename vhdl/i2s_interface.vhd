library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

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

    signal serializer_next_sample_s : std_logic;
    signal serializer_sample_in_s   : std_logic_vector(2 * SAMPLE_WIDTH - 1 downto 0);
    signal fifo_full_s              : std_logic;

    component i2s_fifo
    port (
        rst : in std_logic;
        wr_clk : in std_logic;
        rd_clk : in std_logic;
        din : in std_logic_vector(31 downto 0);
        wr_en : in std_logic;
        rd_en : in std_logic;
        dout : out std_logic_vector(31 downto 0);
        full : out std_logic;
        empty : out std_logic);
    end component;

begin

    next_sample <= not fifo_full_s;

    fifo : i2s_fifo
    port map (
        rst                     => reset,
        wr_clk                  => system_clk,
        rd_clk                  => i2s_clk,
        din                     => std_logic_vector(sample_in(1)) & std_logic_vector(sample_in(0)),
        wr_en                   => not fifo_full_s,
        rd_en                   => serializer_next_sample_s,
        dout                    => serializer_sample_in_s,
        full                    => fifo_full_s,
        empty                   => open
    );
    --
    -- i2s_fifo : entity wave.i2s_fifo
    -- port map (
    --     rst                     => reset,
    --     wr_clk                  => system_clk,
    --     rd_clk                  => i2s_clk,
    --     din                     => std_logic_vector'(sample_in(1) & sample_in(0)),
    --     wr_en                   => not fifo_full_s,
    --     rd_en                   => serializer_next_sample_s,
    --     dout                    => serializer_sample_in_s,
    --     full                    => fifo_full_s,
    --     empty                   => open
    -- );

    i2s_serializer : entity wave.i2s_serializer
    port map (
        i2s_clk                 => i2s_clk,
        reset                   => reset,
        sample_in               => serializer_sample_in_s,
        next_sample             => serializer_next_sample_s,
        sdata                   => sdata,
        wsel                    => wsel
    );

end architecture;
