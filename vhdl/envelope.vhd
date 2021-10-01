library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

entity envelope is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;

        attack_slope            : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
        decay_slope             : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
        release_slope           : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
        sustain_amplitude       : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);

        enable                  : in  std_logic;
        next_sample             : in  std_logic;
        amplitude               : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0)
    );
end entity;

architecture linear of envelope is

    type t_state is (attack, decay, sustain, release, closed);

    type t_midi_slave_reg is record
        state                   : t_state;
        amplitude               : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    end record;

    constant REG_INIT : t_midi_slave_reg := (
        state                   => closed,
        amplitude               => (others => '0');
    );

    -- Register.
    signal r, r_in              : t_midi_slave_reg;

begin

    combinatorial : process (r, attack_slope, decay_slope, release_slope, sustain_amplitude, enable)
        variable v_next_amplitude_ext : std_logic_vector(SAMPLE_WIDTH downto 0); -- extra bit to detect overflow
        variable v_next_amplitude     : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    begin

        -- Default register input.
        r_in <= r;

        -- Outputs.
        amplitude <= r.amplitude;

        case (r.state) is

            if next_sample = '1' then

                when attack =>
                    v_next_amplitude_ext :=
                        std_logic_vector(resize(unsigned(r.amplitude), SAMPLE_WIDTH + 1)
                        + unsigned(attack_slope));

                    -- Check overflow to detect end of attack
                    if v_next_amplitude_ext(SAMPLE_WIDTH) = '1' then
                        r_in.amplitude <= (others => '1');
                        r_in.state <= decay;
                    else
                        r_in.amplitude <= v_next_amplitude_ext(SAMPLE_WIDTH - 1 downto 0);
                    end if;

                    if enable = '0' then
                        r_in.state <= release;
                    end if;

                when decay =>
                    v_next_amplitude_ext :=
                        std_logic_vector(resize(unsigned(r.amplitude), SAMPLE_WIDTH + 1)
                        - unsigned(attack_slope));

                    v_next_amplitude := v_next_amplitude_ext(SAMPLE_WIDTH - 1 downto 0);

                    -- Check overflow and compare to sustain_amplitude to detect end of decay
                    if v_next_amplitude_ext(SAMPLE_WIDTH) = '1'
                            or unsigned(v_next_amplitude) <= sustain_amplitude) then

                        r_in.amplitude <= sustain_amplitude;
                        r_in.state <= sustain;
                    else
                        r_in.amplitude <= v_next_amplitude;
                    end if;

                    if enable = '0' then
                        r_in.state <= release;
                    end if;

                when sustain =>
                    if enable = '0' then
                        r_in.state <= release;
                    end if;

                when release =>
                    v_next_amplitude_ext :=
                        std_logic_vector(resize(unsigned(r.amplitude), SAMPLE_WIDTH + 1)
                        - unsigned(attack_slope));

                    -- Check overflow to detect end of decay
                    if v_next_amplitude_ext(SAMPLE_WIDTH) = '1' then
                        r_in.amplitude <= (others => '0');
                        r_in.state <= closed;
                    else
                        r_in.amplitude <= v_next_amplitude_ext(SAMPLE_WIDTH - 1 downto 0);
                    end if;

                    if enable = '1' then
                        r_in.state <= attack;
                    end if;

                when closed =>
                    if enable = '1' then
                        r_in.state <= attack;
                    end if;

            end if;
        end case;
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
