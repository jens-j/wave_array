library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.wave_array_pkg.all;


entity mixer is
    generic (
        N_INPUTS                : natural
    )
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample_in          : out std_logic_vector(N_INPUTS - 1 downto 0);
        sample_in               : in  t_mono_sample_array(0 to N_INPUTS - 1);
        next_sample_out         : in  std_logic;
        sample_out              : out t_mono_sample
    );
end entity;

architecture arch of mixer is

    constant N_INPUTS_LOG2 : integer := integer(ceil(log2(N_INPUTS)));

    type t_state is (idle, running);

    type t_mixer_reg is record
        state                   : t_state;
        mix_buffer              : t_mono_sample;
        sample_out              : t_mono_sample;
        counter                 : integer range 0 to N_INPUTS - 1;
    end record;

    constant REG_INIT : t_midi_slave_reg := (
        state                   => idle,
        mix_buffer              => (others => '0'),
        sample_out              => (others => '0'),
        counter                 => 0
    );

    signal r, r_in              : t_midi_slave_reg;

begin

    combinatorial : process (r, sample_in, next_sample_out)
        variable v_shifted_sample : t_mono_sample;
    begin

        -- Set outputs.
        sample_out <= r.sample_out;
        next_sample_in <= (others -> '0');

        if r.state = idle then
            if next_sample_out = '1' then
                r_in.state      <= running;
                r_in.sample_out <= r.mix_buffer;
                r_in.mix_buffer <= (others => '0');
                r_in.counter    <= 0;
            end if;
        else
            -- Shift each input by the ceiling of the log2 of the number of inputs.
            v_shifted_sample := sample_in(r.counter)(t_mono_sample'length - N_INPUTS_LOG2 downto 0)
                & (N_INPUTS_LOG2 - 1 downto 0);

            -- Add shifted sample to accumulator.
            r_in.mix_buffer <= r.mix_buffer + v_shifted_sample;

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
