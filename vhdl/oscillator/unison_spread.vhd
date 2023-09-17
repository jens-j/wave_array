

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library osc;


-- This entity generates the additional oscillator velocities of the unison spread.
-- It also duplicates the output velocities if binaural mode is enabled.
-- The velocities are calculated as follows: 
-- 
-- f    = center velocity / midi note 
-- N    = unison_n 
-- ctrl = unison spread control value 
-- 
-- D = ctrl * f * 2**(1/12) | D is the maximum distance to the center velocity (one semitone scaled by the control value). 
--                          | U0 = f - ctrl.
-- d = 2 * D / N            | d is the distance between unison voices Un = Un-1 + d.
-- 
-- U0 and d are pre-calculated by the unison_step sub entity.
entity unison_spread is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic;
        spread_ctrl             : in  t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        pitched_osc_inputs      : in  t_pitched_osc_inputs;
        spread_osc_inputs       : out t_spread_osc_inputs
    );
end entity;


architecture arch of unison_spread is 


    type t_state is (idle, prepare, running);

    type t_unison_reg is record
        state                   : t_state;
        table_count             : integer range 0 to N_TABLES - 1;
        voice_count             : integer range 0 to POLYPHONY_MAX - 1;
        unison_count            : integer range 0 to UNISON_MAX - 1;
        osc_count               : integer range 0 to N_VOICES - 1;
        mux_table               : integer range 0 to N_TABLES - 1;
        mux_osc                 : integer range 0 to N_VOICES - 1;
        mux_enable              : std_logic;
        mux_value               : t_osc_phase;
        step_value              : t_osc_phase;
        unison_n_minus_one      : integer range 0 to UNISON_MAX - 1;
        voice_enable            : std_logic;
        spread_osc_inputs       : t_spread_osc_inputs;
        spread_osc_inputs_buffer: t_spread_osc_inputs;
        voice_max               : integer range 0 to POLYPHONY_MAX - 1;
    end record;

    constant REG_INIT : t_unison_reg := (
        state                   => idle,
        table_count             => 0,
        voice_count             => 0,
        unison_count            => 0,
        osc_count               => 0,
        mux_table               => 0,
        mux_osc                 => 0,
        mux_enable              => '0',
        mux_value               => (others => '0'),
        step_value              => (others => '0'),
        unison_n_minus_one      => 0,
        voice_enable            => '0',
        spread_osc_inputs       => (others => (others => ('0', (others => '0')))),
        spread_osc_inputs_buffer=> (others => (others => ('0', (others => '0')))),
        voice_max               => 0
    );

    signal r, r_in : t_unison_reg;

    signal s_unison_start            : t_unison_step_array;
    signal s_unison_step             : t_unison_step_array;

begin 

    unison_step_inst : entity osc.unison_step 
    port map (
        clk                     => clk,
        reset                   => reset,
        config                  => config,
        status                  => status,
        next_sample             => next_sample,
        spread_ctrl             => spread_ctrl,
        pitched_osc_inputs      => pitched_osc_inputs,
        unison_start            => s_unison_start,
        unison_step             => s_unison_step
    );

    comb_process : process (r, config, status, next_sample, pitched_osc_inputs, s_unison_start, s_unison_step)
    begin

        r_in <= r;

        r_in.mux_enable <= '0'; 
        r_in.mux_table <= r.table_count;
        r_in.mux_osc <= r.osc_count;

        -- Connect output registers.
        spread_osc_inputs <= r.spread_osc_inputs;

        case r.state is 
        when idle => 

            r_in.table_count <= 0;
            r_in.voice_count <= 0;
            r_in.unison_count <= 0;
            r_in.osc_count <= 0;
            
            if next_sample = '1' then 
                r_in.spread_osc_inputs <= r.spread_osc_inputs_buffer;
                r_in.spread_osc_inputs_buffer <= (others => (others => ('0', (others => '0'))));
                r_in.state <= prepare;
            end if;

        -- Wait one cycle for the config to update.
        when prepare => 
            r_in.unison_n_minus_one <= config.unison_n - 1;
            r_in.voice_max <= 2 * status.polyphony - 1 when config.binaural_enable = '1' else status.polyphony - 1;
            r_in.state <= running;

        -- Start with velocity U0 for each table/voice combination and calculate other unison velocities by iterating
        -- with unison_step. Resulting velocities are muxed to the output buffer in the subsequent cycle.
        when running =>

            r_in.mux_enable <= '1'; 
            r_in.voice_enable <= pitched_osc_inputs(r.table_count)(r.voice_count).enable;

            if r.unison_count = 0 then 
                r_in.step_value <= s_unison_step(r.table_count)(r.voice_count);
                r_in.mux_value <= s_unison_start(r.table_count)(r.voice_count);
            else 
                r_in.mux_value <= r.mux_value + r.step_value;
            end if;

            -- Increment counters.
            r_in.osc_count <= minimum(N_VOICES - 1, r.osc_count + 1);

            if r.unison_count < r.unison_n_minus_one then 
                r_in.unison_count <= r.unison_count + 1;
            else 
                r_in.unison_count <= 0;

                if r.voice_count = r.voice_max then 
                    r_in.osc_count <= 0;
                    r_in.voice_count <= 0;
                    if r.table_count < N_TABLES - 1 then 
                        r_in.table_count <= r.table_count + 1;
                    else 
                        r_in.state <= idle;
                    end if;
                else
                    r_in.voice_count <= r.voice_count + 1;                  
                end if;
            end if;
            
        end case; 

        -- Output mux calculated velocities in a separate cycle.
        if r.mux_enable = '1' then
            r_in.spread_osc_inputs_buffer(r.mux_table)(r.mux_osc).enable <= r.voice_enable;
            r_in.spread_osc_inputs_buffer(r.mux_table)(r.mux_osc).velocity <= r.mux_value;
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