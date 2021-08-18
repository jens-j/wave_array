library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.wave_array_pkg.all;


entity i2s_interface is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        sample_in               : in  t_stereo_sample;
        next_sample             : out std_logic; -- strobe to request next sample
        -- I2S outputs
        sdata                   : out std_logic;
        sclk                    : out std_logic;
        wsel                    : out std_logic
    );
end entity;


architecture arch of i2s_interface is

    type t_i2s_reg is record
        send_buffer             : t_stereo_sample;
        word_select             : std_logic;
        clk_count               : integer range 0 to I2S_CLK_DIV - 1;
        bit_count               : integer range 0 to 2 * SAMPLE_WIDTH - 1;
        next_sample             : std_logic;
        sdata                   : std_logic;
        sclk                    : std_logic;
    end record;

    constant R_INIT : t_i2s_reg := (
        send_buffer             => (others => (others => '0')),
        word_select             => '0',
        clk_count               => 0,
        bit_count               => SAMPLE_WIDTH - 1,
        next_sample             => '1',
        sdata                   => '0',
        sclk                    => '0'
    );

    signal r, r_in : t_i2s_reg;

begin

    -- This process
    combinatorial : process (r, sample_in)
    begin

        r_in <= r;

        -- default values
        r_in.next_sample <= '0';

        if r.clk_count = I2S_CLK_DIV - 1 then

            r_in.clk_count <= 0;
            r_in.sclk <= '1';

            if r.word_select = '0' then
                r_in.sdata <= r.send_buffer(0)(r.bit_count);
            else
                r_in.sdata <= r.send_buffer(1)(r.bit_count);
            end if;

            if r.bit_count = 0 then
                r_in.bit_count <= SAMPLE_WIDTH - 1;
                r_in.word_select <= not r.word_select;
                if r.word_select = '1' then
                    r_in.send_buffer <= sample_in;
                    r_in.next_sample <= '1';
                end if;
            else
                r_in.bit_count <= r.bit_count - 1;
            end if;

        else
            r_in.clk_count <= r.clk_count + 1;
        end if;

        if r.clk_count = I2S_CLK_DIV / 2 - 1 then
            r_in.sclk <= '0';
        end if;

        -- connect register to outputs
        next_sample <= r.next_sample;
        sdata <= r.sdata;
        sclk <= r.sclk;
        wsel <= r.word_select;

    end process;

    reg_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= R_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
