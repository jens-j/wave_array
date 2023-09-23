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
        next_sample             : in  std_logic;
        pitch_ctrl              : in  t_osc_ctrl_array;
        osc_inputs              : in  t_osc_input_array(0 to POLYPHONY_MAX - 1);
        pitched_osc_inputs      : out t_pitched_osc_inputs -- Different for each table.
    );
end entity;


architecture arch of pitch_modulator is 

    type t_state is (idle, load_buffer, map_exp);

    type t_pitch_mod_reg is record
        state                   : t_state;
        pitched_osc_inputs      : t_pitched_osc_inputs;
        pitched_osc_inputs_buffer : t_pitched_osc_inputs;
        count_voice_in          : integer range 0 to POLYPHONY_MAX - 1;
        count_table_in          : integer range 0 to N_TABLES - 1;
        count_pipeline          : integer range 0 to 4;
        count_voice_out         : integer range 0 to POLYPHONY_MAX - 1;
        count_table_out         : integer range 0 to N_TABLES - 1;
        mult_buffer             : t_osc_phase;
        velocity                : t_osc_phase;
        data_out                : t_ctrl_value;
    end record;

    constant REG_INIT : t_pitch_mod_reg := (
        state                   => idle,
        pitched_osc_inputs      => (others => (others => (enable => '0', velocity => (others => '0')))),
        pitched_osc_inputs_buffer => (others => (others => (enable => '0', velocity => (others => '0')))),
        count_voice_in          => 0,
        count_table_in          => 0,
        count_pipeline          => 0,
        count_voice_out         => 0,
        count_table_out         => 0,
        mult_buffer             => (others => '0'),
        velocity                => (others => '0'),
        data_out                => (others => '0')        
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

    comb_process : process (r, next_sample, pitch_ctrl, osc_inputs, s_busy, s_data_out_valid, s_data_out)

        variable v_mult_result : unsigned(t_osc_phase'length + CTRL_SIZE - 1 downto 0);

    begin

        r_in <= r;

        s_data_in_valid <= '0';
        s_data_in <= (others => '0');
        
        pitched_osc_inputs <= r.pitched_osc_inputs;

        case r.state is 

        -- Wait for next sample pulse.
        when idle => 
            if next_sample = '1' then 
                r_in.pitched_osc_inputs <= r.pitched_osc_inputs_buffer;
                r_in.count_voice_in <= 0;
                r_in.count_table_in <= 0;
                r_in.count_pipeline <= 0;
                r_in.count_voice_out <= 0;
                r_in.count_table_out <= 0;
                r_in.state <= load_buffer;
            end if;

        when load_buffer => 

            for i in 0 to N_TABLES - 1 loop
                for j in 0 to POLYPHONY_MAX - 1 loop 
                    r_in.pitched_osc_inputs_buffer(i)(j).enable <= osc_inputs(j).enable;
                    r_in.pitched_osc_inputs_buffer(i)(j).velocity <= (others =>'0');
                end loop;
            end loop;

            r_in.state <= map_exp;

        -- Map control value to exponential range.
        when map_exp => 

            if s_busy = '0' then 

                s_data_in_valid <= '1';
                s_data_in <= pitch_ctrl(r.count_table_in)(r.count_voice_in);

                if r.count_voice_in < POLYPHONY_MAX - 1 then 
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

        -- Wait until converted control values appear and multiply three times with input velocities.
        if s_data_out_valid = '1' then 
            r_in.data_out <= s_data_out;
            r_in.velocity <= osc_inputs(r.count_voice_out).velocity;
        end if;

        -- Multiply input velocity with (converted) control value.
        -- Converted control value is signed 2.14 bit fixed point. So normalize by shifting right 14 bits.
        if r.count_pipeline = 1 then 
            v_mult_result := r.velocity * unsigned(r.data_out);
            r_in.mult_buffer <= v_mult_result(t_osc_phase'length + CTRL_SIZE - 3 downto CTRL_SIZE - 2);

        -- Write back result.
        elsif r.count_pipeline = 4 then 
            r_in.pitched_osc_inputs_buffer(r.count_table_out)(r.count_voice_out).velocity <= r.mult_buffer;

        -- Multiply with the same exponential factor to get higher range.
        else
            v_mult_result := r.mult_buffer * unsigned(s_data_out);
            r_in.mult_buffer <= v_mult_result(t_osc_phase'length + CTRL_SIZE - 3 downto CTRL_SIZE - 2);
        end if;

        -- Increment counters.
        if s_data_out_valid = '1' or r.count_pipeline > 0 then 

            if r.count_pipeline < 4 then 
                r_in.count_pipeline <= r.count_pipeline + 1;
            else 
                r_in.count_pipeline <= 0;
                if r.count_voice_out < POLYPHONY_MAX - 1 then 
                    r_in.count_voice_out <= r.count_voice_out + 1;
                else 
                    if r.count_table_out < N_TABLES - 1 then 
                        r_in.count_voice_out <= 0;
                        r_in.count_table_out <= r.count_table_out + 1;
                    end if;
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