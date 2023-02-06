library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity lfo is
    generic (
        N_OUTPUTS               : natural
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic;
        velocity                : in  t_ctrl_value;
        sine_out                : out t_ctrl_value;
        square_out              : out t_ctrl_value;
        saw_out                 : out t_ctrl_value
    );
end entity;

architecture arch of lfo is

    type t_lfo_phase_array is array (0 to N_OUTPUTS - 1) of unsigned(LFO_PHASE_WIDTH - 1 downto 0);

    type t_mixer_reg is record
        phases                  : t_lfo_phase_array;
        sine_out                : t_mono_sample;
        square_out              : t_mono_sample;
        saw_out                 : t_mono_sample;
    end record;

    constant REG_INIT : t_mixer_reg := (
        phases                  => (others => (others => '0')),
        sine_out                => (others => '0'),
        square_out              => (others => '0'),
        saw_out                 => (others => '0')
    );

    signal r, r_in              : t_mixer_reg;

begin

    combinatorial : process (r, next_sample, velocity)
    begin

        r_in <= r;

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
