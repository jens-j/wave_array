library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;


entity mixer is
    generic (
        N_INPUTS                : natural
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        sample_in               : in  t_mono_sample_array(0 to N_INPUTS - 1);
        next_sample             : in  std_logic;
        sample_out              : out t_mono_sample
    );
end entity;

architecture arch of mixer is

    constant N_INPUTS_LOG2 : integer := integer(ceil(log2(real(N_INPUTS))));

    -- Add some guard bits to the accumulator
    subtype t_mix_buffer is std_logic_vector(t_mono_sample'length + N_INPUTS_LOG2 - 1 downto 0);
    type t_state is (idle, running);

    type t_mixer_reg is record
        state                   : t_state;
        mix_buffer              : signed(t_mix_buffer'length - 1 downto 0);
        sample_out              : t_mono_sample;
        counter                 : integer range 0 to N_INPUTS - 1;
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        mix_buffer              => (others => '0'),
        sample_out              => (others => '0'),
        counter                 => 0
    );

    signal r, r_in              : t_mixer_reg;

begin

    combinatorial : process (r, sample_in, next_sample)
        variable v_extended_sample : t_mix_buffer;
    begin

        r_in <= r;

        -- Set outputs.
        sample_out <= r.sample_out;

        if r.state = idle then
            if next_sample = '1' then
                r_in.state      <= running;
                r_in.sample_out <= r.mix_buffer(t_mix_buffer'length - 1 downto N_INPUTS_LOG2);
                r_in.mix_buffer <= (others => '0');
                r_in.counter    <= 0;
            end if;
        else

            r_in.mix_buffer <= resize(signed(r.mix_buffer), t_mono_sample'length + N_INPUTS_LOG2)
                + resize(signed(sample_in(r.counter)), t_mono_sample'length + N_INPUTS_LOG2);

            if r.counter = N_INPUTS - 1 then
                r_in.state <= idle;
            else
                r_in.counter <= r.counter + 1;
            end if;
        end if;
    end process;

    reg_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= REG_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
