library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.wave_array_pkg.all;


entity saw is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        slope                   : in  std_logic_vector(15 downto 0);
        next_sample             : in  std_logic;
        sample_out              : out sample_t
    );
end entity;

architecture arch of saw is

    type saw_r is record
        sample                  : integer range 0 to SAMPLE_MAX;
    end record;

    constant R_INIT : saw_r := (sample => 0);

    signal r, r_in : saw_r := R_INIT;

begin

    combinatorial : process (r, next_sample, slope)
    begin

        r_in <= r;

        sample_out(0) <= std_logic_vector(to_unsigned(r.sample, SAMPLE_WIDTH));
        sample_out(1) <= std_logic_vector(to_unsigned(r.sample, SAMPLE_WIDTH));

        if next_sample = '1' then
            r_in.sample <= r.sample + to_integer(unsigned(slope));
        end if;

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
