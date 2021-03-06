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

    type t_state is (init_0, init_1, init_2, init_3, running);

    signal r_state                  : t_state;
    signal s_state                  : t_state;
    signal s_serializer_next_sample : std_logic;
    signal s_serializer_sample_in   : std_logic_vector(2 * SAMPLE_SIZE - 1 downto 0);
    signal s_fifo_full              : std_logic;
    signal s_fifo_din               : std_logic_vector(2 * SAMPLE_SIZE - 1 downto 0);
    signal s_fifo_wr_data_count     : std_logic_vector(3 downto 0);

begin

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
        empty                       => open,
        wr_data_count               => s_fifo_wr_data_count
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

    -- Fill the fifo with zero's at startup to avoid sending too many fast next_sample pulses;
    zero_proc : process (r_state, sample_in, s_fifo_full)
    begin
        s_state <= r_state;

        s_fifo_din <= (others => '0');
        next_sample <= '0';

        -- The fifo says it's full before it actually is three times.
        if r_state = init_0 then
            if s_fifo_full = '1' then s_state <= init_1; end if;

        elsif r_state = init_1 then
            if s_fifo_full = '0' then s_state <= init_2; end if;

        elsif r_state = init_2 then
            if s_fifo_full = '0' then s_state <= init_3; end if;

        elsif r_state = init_3 then
            if s_fifo_full = '0' then s_state <= running; end if;

        else
            s_fifo_din <= std_logic_vector(sample_in(1)) & std_logic_vector(sample_in(0));
            next_sample <= not s_fifo_full; -- Generate a next_sample pulse when the fifo not full.
        end if;
    end process;

    reg_proc : process (system_clk)
    begin
        if rising_edge(system_clk) then
            if reset = '1' then
                r_state <= init_0;
            else
                r_state <= s_state;
            end if;
        end if;
    end process;

end architecture;
