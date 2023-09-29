

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library osc;


-- This entity generates the additional oscillator velocities of the unison spread.
-- unsion and binaural voices are combined. So a single voice is spead out over the group formed by both binaural unison oscillators.
-- The velocities are calculated as follows: 
-- 
-- f    = center velocity / midi note 
-- N    = unison_n * binaural
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
        spread_osc_inputs       : out t_spread_osc_inputs; -- osc_inputs but spread out for unison.
        frame_ctrl_index        : out t_frame_ctrl_index; -- Correponding frame control index. Avoid doing the osc to voice mapping again in the table interpolator.
        lowest_velocity         : out t_osc_phase
    );
end entity;


architecture arch of unison_spread is 

    type t_state is (idle, prepare, running);

    type t_unison_reg is record
        state                   : t_state;
        table_count             : integer range 0 to N_TABLES - 1;
        voice_count             : integer range 0 to POLYPHONY_MAX - 1;
        group_count             : integer range 0 to 2 * UNISON_MAX - 1;
        group_max               : integer range 0 to 2 * UNISON_MAX - 1;
        osc_count               : integer range 0 to N_VOICES - 1;
        mux_table               : integer range 0 to N_TABLES - 1;
        mux_osc                 : integer range 0 to N_VOICES - 1;
        mux_enable              : std_logic;
        mux_value               : t_osc_phase;
        mux_index               : integer range 0 to POLYPHONY_MAX - 1;
        step_value              : t_osc_phase;
        voice_enable            : std_logic;
        spread_osc_inputs       : t_spread_osc_inputs;
        spread_osc_inputs_buffer: t_spread_osc_inputs;
        frame_ctrl_index        : t_frame_ctrl_index;
        frame_ctrl_index_buffer : t_frame_ctrl_index;
        lowest_velocity         : t_osc_phase;
        lowest_velocity_buffer  : t_osc_phase;
    end record;

    constant REG_INIT : t_unison_reg := (
        state                   => idle,
        table_count             => 0,
        voice_count             => 0,
        group_count             => 0,
        group_max               => 0,
        osc_count               => 0,
        mux_table               => 0,
        mux_osc                 => 0,
        mux_enable              => '0',
        mux_value               => (others => '0'),
        mux_index   	        => 0,
        step_value              => (others => '0'),
        voice_enable            => '0',
        spread_osc_inputs       => (others => (others => ('0', (others => '0')))),
        spread_osc_inputs_buffer=> (others => (others => ('0', (others => '0')))),
        frame_ctrl_index       => (others => 0),
        frame_ctrl_index_buffer=> (others => 0),
        lowest_velocity         => (others => '0'),
        lowest_velocity_buffer  => (others => '0')
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
        frame_ctrl_index <= r.frame_ctrl_index;
        lowest_velocity <= r.lowest_velocity;

        case r.state is 
        when idle => 

            r_in.table_count <= 0;
            r_in.voice_count <= 0;
            r_in.group_count <= 0;
            r_in.osc_count <= 0;
            
            if next_sample = '1' then 
                r_in.spread_osc_inputs <= r.spread_osc_inputs_buffer;
                r_in.frame_ctrl_index <= r.frame_ctrl_index_buffer;
                r_in.lowest_velocity <= r.lowest_velocity_buffer;
                r_in.lowest_velocity_buffer <= (others => '1');
                r_in.spread_osc_inputs_buffer <= (others => (others => ('0', (others => '0'))));
                r_in.state <= prepare;
            end if;

        -- Wait one cycle for the config to update.
        when prepare => 
            r_in.group_max <= config.unison_n * 2 - 1 when config.binaural_enable = '1' else config.unison_n - 1;
                
            r_in.state <= running;

        -- Start with velocity U0 for each table/voice combination and calculate other unison velocities by iterating
        -- with unison_step. Resulting velocities are muxed to the output buffer in the subsequent cycle.
        when running =>

            r_in.mux_enable <= '1'; 
            r_in.mux_index <= 2 * r.voice_count when config.binaural_enable = '1' else r.voice_count;
            r_in.voice_enable <= pitched_osc_inputs(r.table_count)(2 * r.voice_count).enable 
                when config.binaural_enable = '1' else pitched_osc_inputs(r.table_count)(r.voice_count).enable;

            if r.group_count = 0 then 
                r_in.step_value <= s_unison_step(r.table_count)(r.voice_count);
                r_in.mux_value <= s_unison_start(r.table_count)(r.voice_count);
            else 
                r_in.mux_value <= r.mux_value + r.step_value;
            end if;

            -- Increment counters.
            r_in.osc_count <= minimum(N_VOICES - 1, r.osc_count + 1);

            if r.group_count < r.group_max then 
                r_in.group_count <= r.group_count + 1;
            else 
                r_in.group_count <= 0;

                if r.voice_count < status.polyphony - 1 then 
                    r_in.voice_count <= r.voice_count + 1; 
                else
                    r_in.osc_count <= 0;
                    r_in.voice_count <= 0;
                    if r.table_count < N_TABLES - 1 then 
                        r_in.table_count <= r.table_count + 1;
                    else 
                        r_in.state <= idle;
                    end if;
                end if;
            end if;
            
        end case; 

        -- Output mux calculated velocities in a separate cycle.
        if r.mux_enable = '1' then
            r_in.spread_osc_inputs_buffer(r.mux_table)(r.mux_osc).enable <= r.voice_enable;
            r_in.spread_osc_inputs_buffer(r.mux_table)(r.mux_osc).velocity <= r.mux_value;
            r_in.frame_ctrl_index_buffer(r.mux_osc) <= r.mux_index; -- This is the same for every table. So it will be overwritten for each table but with the same values.

            if r.voice_enable = '1' and r.mux_value < r.lowest_velocity_buffer then 
                r_in.lowest_velocity_buffer <= r.mux_value;
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