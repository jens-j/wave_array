library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- Centralized entity that handles all forms of pitch modulation.
-- MIDI pitch bend, oscillator tuning, pitch modulation, unison spread.
entity pitch_modulator is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        next_sample             : in  std_logic;
        pitch_ctrl              : in  t_osc_ctrl_array;
        osc_inputs              : in  t_osc_input_array(0 to N_VOICES - 1);
        osc_outputs             : out t_pitched_osc_inputs -- Different for each table.
    );
end entity;


architecture arch of pitch_modulator is 

    type t_state is (idle, map_exp);

    type t_pitch_mod_reg is record
        state                   : t_state;
        osc_outputs             : t_pitched_osc_inputs;
        osc_outputs_buffer      : t_pitched_osc_inputs;
        count_voice_in          : integer range 0 to N_VOICES - 1;
        count_table_in          : integer range 0 to N_TABLES - 1;
        count_voice_out         : integer range 0 to N_VOICES - 1;
        count_table_out         : integer range 0 to N_TABLES - 1;
    end record;

    constant REG_INIT : t_pitch_mod_reg := (
        state                   => idle,
        osc_outputs             => (others => (others => (enable => '0', velocity => (others => '0')))),
        osc_outputs_buffer      => (others => (others => (enable => '0', velocity => (others => '0')))),
        count_voice_in          => 0,
        count_table_in          => 0,
        count_voice_out         => 0,
        count_table_out         => 0
    );

    signal r, r_in              : t_pitch_mod_reg;

    signal s_data_in_valid      : std_logic;
    signal s_data_in            : t_ctrl_value;
    signal s_busy               : std_logic;
    signal s_data_out_valid     : std_logic;
    signal s_data_out           : t_ctrl_value;

begin 

    lin2exp : entity wave.lin2exp
    port map (
        clk                     => clk,
        reset                   => reset,
        data_in_valid           => s_data_in_valid,
        data_in                 => s_data_in,
        busy                    => s_busy,
        data_out_valid          => s_data_out_valid,
        data_out                => s_data_out
    );

    comb_process : process (r, config, next_sample, pitch_ctrl, osc_inputs, s_busy, s_data_out_valid, s_data_out)

        variable v_mult_result : unsigned(t_osc_phase'length + CTRL_SIZE - 1 downto 0);

    begin

        r_in <= r;

        s_data_in_valid <= '0';
        
        osc_outputs <= r.osc_outputs;

        case r.state is 

        -- Wait for next sample pulse.
        when idle => 
            if next_sample = '1' then 
                r_in.osc_outputs <= r.osc_outputs_buffer;
                r_in.count_voice_in <= 0;
                r_in.count_table_in <= 0;
                r_in.count_voice_out <= 0;
                r_in.count_table_out <= 0;
                r_in.state <= map_exp;
            end if;

        -- Map control value to exponential range.
        when map_exp => 

            if s_busy = '0' then 

                s_data_in_valid <= '1';
                s_data_in <= pitch_ctrl(r.count_table_in)(r.count_voice_in);

                if r.count_voice_in < N_VOICES - 1 then 
                    r_in.count_voice_in <= r.count_voice_in + 1;
                else 
                    r_in.count_voice_in <= 0;
                    if r.count_table_in < N_TABLES - 1 then 
                        r_in.count_table_in <= r.count_table_in + 1;
                    else 
                        r_in.state <= idle;
                    end if;
                end if;
            end if;

        end case;

        -- Wait until converted control values appear and multiply with input velocities.
        if s_data_out_valid = '1' then 

            -- Multiply input velocity with (converted) control value.
            -- Converted control value is signed 2.14 bit fixed point. So normalize by shifting right 14 bits.
            v_mult_result := osc_inputs(r.count_voice_out).velocity * unsigned(s_data_out);

            r_in.osc_outputs_buffer(r.count_table_out)(r.count_voice_out).enable <= osc_inputs(r.count_voice_out).enable;
            r_in.osc_outputs_buffer(r.count_table_out)(r.count_voice_out).velocity
                <= v_mult_result(t_osc_phase'length + CTRL_SIZE - 3 downto CTRL_SIZE - 2);

            if r.count_voice_out < N_VOICES - 1 then 
                r_in.count_voice_out <= r.count_voice_out + 1;
            else 
                if r.count_table_out < N_TABLES - 1 then 
                    r_in.count_voice_out <= 0;
                    r_in.count_table_out <= r.count_table_out + 1;
                end if;
            end if;
        end if;

    end process;

    reg_process : process (clk)
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