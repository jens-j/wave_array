library ieee;
use ieee.std_logic_1164.all;

library wave;
use wave.wave_array_pkg.all;


entity i2s_serializer is
    port (
        i2s_clk                 : in  std_logic;
        reset                   : in  std_logic;
        sample_in               : in  std_logic_vector(2 * SAMPLE_WIDTH - 1 downto 0);
        next_sample             : out std_logic;
        sdata                   : out std_logic;
        wsel                    : out std_logic
    );
end entity;

architecture arch of i2s_serializer is

    type t_i2s_serializer_reg is record
        send_buffer             : std_logic_vector(2 * SAMPLE_WIDTH - 1 downto 0);
        word_select             : std_logic; -- 1 cycle ahead of sdata
        bit_count               : integer range 0 to 2 * SAMPLE_WIDTH - 1;
        next_sample             : std_logic;
        sdata                   : std_logic;
    end record;

    constant R_INIT : t_i2s_serializer_reg := (
        send_buffer             => (others => '0'),
        word_select             => '0',
        bit_count               => SAMPLE_WIDTH - 1,
        next_sample             => '0',
        sdata                   => '0'
    );

    signal r, r_in : t_i2s_serializer_reg;

begin

    combinatorial : process (r, sample_in)
    begin

        -- Regiister inputs.
        r_in <= r;
        r_in.sdata <= r.send_buffer(r.bit_count);
        r_in.next_sample <= '0';

        -- Outputs.
        next_sample <= r.next_sample;
        sdata <= r.sdata;
        wsel <= r.word_select;

        -- Toggle word select output one cycle ahead of the data line compliant to the protocol.
        if r.bit_count = SAMPLE_WIDTH then
            r_in.word_select <= '1';
        end if;

        -- Load next sample.
        if r.bit_count = 0 then
            r_in.bit_count <= 2 * SAMPLE_WIDTH - 1;
            r_in.send_buffer <= sample_in;
            r_in.next_sample <= '1';
            r_in.word_select <= '0';
        else
            r_in.bit_count <= r.bit_count - 1;
            r_in.next_sample <= '0';
        end if;

    end process;

    reg_process : process(i2s_clk)
    begin
        if falling_edge(i2s_clk) then
            if reset = '1' then
                r <= R_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
