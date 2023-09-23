library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


-- This entity uses a single multiplier to pre-process the configuration input of the unison system. 
-- The multiplier does a 27 * 16 bits multiplication. The second operand is always a 1.15 signed (but always positive)
-- fixed point value. So after each multiplication the result is normalized by 15 bits. The multiplier inputs are 
-- registered so the delay is 2 cycles. 
entity unison_step is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic;
        spread_ctrl             : in  t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        pitched_osc_inputs      : in  t_pitched_osc_inputs;
        unison_start            : out t_unison_step_array;
        unison_step             : out t_unison_step_array
    );
end entity;

architecture arch of unison_step is 

    -- Constant 2**(1/12) * 2**15.
    constant D_SEMITONE         : signed(15 downto 0) := x"079C";
    constant DIV_COEFF          : t_div_coeff_array := GENERATE_DIV_COEFF_ARRAY;

    type t_state is (idle, prepare, busy_0, busy_1, busy_2, busy_3, mult_delay);

    type t_unison_step_reg is record
        state                   : t_state;
        next_state              : t_state;
        unison_start            : t_unison_step_array;
        unison_step             : t_unison_step_array;
        unison_start_buffer     : t_unison_step_array;
        unison_step_buffer      : t_unison_step_array;
        unison_start_temp       : t_osc_phase;
        table_count             : integer range 0 to N_TABLES - 1;
        voice_count             : integer range 0 to POLYPHONY_MAX - 1;
        mult_a                  : signed(OSC_PHASE_SIZE downto 0);
        mult_b                  : signed(CTRL_SIZE - 1 downto 0);
        mult_d                  : signed(OSC_PHASE_SIZE downto 0);
        center_velocity         : t_osc_phase;
    end record;

    constant REG_INIT : t_unison_step_reg := (
        state                   => idle,
        next_state              => idle,
        unison_start            => (others => (others => (others => '0'))),
        unison_step             => (others => (others => (others => '0'))),
        unison_start_buffer     => (others => (others => (others => '0'))),
        unison_step_buffer      => (others => (others => (others => '0'))),
        unison_start_temp       => (others => '0'),
        table_count             => 0,
        voice_count             => 0,
        mult_a                  => (others => '0'),
        mult_b                  => (others => '0'),
        mult_d                  => (others => '0'),
        center_velocity         => (others => '0')
    );

    signal r, r_in : t_unison_step_reg;

begin 

    comb_process : process (r, status, next_sample, config, spread_ctrl, pitched_osc_inputs)

        variable v_mult_result : signed(OSC_PHASE_SIZE + CTRL_SIZE downto 0);

    begin

        r_in <= r;

        -- Default inputs.
        r_in.mult_a <= (others => '0');
        r_in.mult_b <= (others => '0');

        -- Connect output registers.1
        unison_start <= r.unison_start;
        unison_step <= r.unison_step;

        -- Infer multiplier.
        v_mult_result := r.mult_a * r.mult_b;

        -- Multiplier output register. Normalize by 15 bits.
        r_in.mult_d <= v_mult_result(OSC_PHASE_SIZE + CTRL_SIZE - 1 downto CTRL_SIZE - 1);

        case r.state is 

        when idle => 
            r_in.voice_count <= 0;
            r_in.table_count <= 0;
            
            if next_sample = '1' then 
                r_in.unison_start <= r.unison_start_buffer;
                r_in.unison_step <= r.unison_step_buffer;
                r_in.unison_start_buffer <= (others => (others => (others => '0')));
                r_in.unison_step_buffer <= (others => (others => (others => '0')));
                r_in.state <= prepare;
            end if;

        -- Pre-calculate stuff which depends on config or status. 
        -- Also skip if unison = 1 and set start to note velocity and step to zero.
        when prepare => 
            if config.unison_n = 1 then 
                for i in 0 to N_TABLES - 1 loop
                    for j in 0 to POLYPHONY_MAX - 1 loop
                        r_in.unison_start_buffer(i)(j) <= pitched_osc_inputs(i)(j).velocity;
                        r_in.unison_step_buffer(i)(j) <= (others => '0');
                    end loop;
                end loop;
                r_in.state <= idle;
            else 
                r_in.state <= busy_0;
            end if;

        -- Calculate f * ctrl.
        when busy_0 =>
            r_in.mult_a <= signed(resize(pitched_osc_inputs(r.table_count)(r.voice_count).velocity, OSC_PHASE_SIZE + 1));
            r_in.center_velocity <= pitched_osc_inputs(r.table_count)(r.voice_count).velocity;
            r_in.mult_b <= spread_ctrl(r.voice_count);
            r_in.next_state <= busy_1;
            r_in.state <= mult_delay;
        
        -- Calculate D by multiplying the result of the previous stage with 2**(1/12) (one semitone).
        when busy_1 =>
            r_in.mult_a <= r.mult_d;
            r_in.mult_b <= D_SEMITONE;
            r_in.next_state <= busy_2;
            r_in.state <= mult_delay;

        -- Calculate d = 2 * D / N and U0 = f - D (step and start respectively).
        when busy_2 => 
            r_in.mult_a <= r.mult_d(OSC_PHASE_SIZE - 1 downto 0) & '0';
            r_in.mult_b <= DIV_COEFF(config.unison_n);
            r_in.unison_start_temp <= r.center_velocity - unsigned(r.mult_d(OSC_PHASE_SIZE - 1 downto 0));
            r_in.next_state <= busy_3;
            r_in.state <= mult_delay;

        -- Register last output and update counters.
        when busy_3 => 
            r_in.unison_start_buffer(r.table_count)(r.voice_count) <= r.unison_start_temp;
            r_in.unison_step_buffer(r.table_count)(r.voice_count) <= unsigned(r.mult_d(OSC_PHASE_SIZE - 1 downto 0));

            r_in.state <= busy_0;

            if r.voice_count < status.active_voices - 1 then 
                r_in.voice_count <= r.voice_count + 1;
            else 
                r_in.voice_count <= 0;
                if r.table_count < N_TABLES - 1 then
                    r_in.table_count <= r.table_count + 1;
                else
                    r_in.state <= idle;
                end if;
            end if;

        -- Wait one cycle for the multiplier.
        when mult_delay => 
            r_in.state <= r.next_state;

        end case;

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