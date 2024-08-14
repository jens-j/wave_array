library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity sample_hold is 
    generic (
        N_INSTANCES             : natural -- Number of sample and holds this entity implements.
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        status                  : in  t_status;
        next_sample             : in  std_logic;
        sample_hold_input       : in  t_sample_hold_input_array(0 to SAMPLE_HOLD_N - 1);
        sample_hold_out         : out t_sample_hold_out
    );
end entity;

architecture arch of sample_hold is 

    type t_state is (idle, map_slew, store_slew, select_velocity, map_velocity, store_velocity, 
        increment_phase, check_overflow, update_target, scale_target, assign_target, select_target, update_slew, 
        update_value, update_counters);

    type t_sample_hold_phase_array is array (0 to POLYPHONY_MAX - 1) of unsigned(31 downto 0);
    type t_sample_hold_phase_2d_array is array (0 to N_INSTANCES - 1) of t_sample_hold_phase_array;
    type t_sample_hold_buffer_array is array (0 to POLYPHONY_MAX - 1) of signed(CTRL_SIZE + 3 downto 0);
    type t_sample_hold_buffer_2d_array is array (0 to N_INSTANCES - 1) of t_sample_hold_buffer_array;

    type t_sh_reg is record
        state                   : t_state;
        sample_hold_out         : t_sample_hold_out;
        sample_hold_buffer      : t_sample_hold_buffer_2d_array;
        sample_hold_target      : t_sample_hold_out;
        instance_counter        : integer range 0 to N_INSTANCES - 1;
        voice_counter           : integer range 0 to POLYPHONY_MAX - 1;
        phase                   : t_sample_hold_phase_2d_array;
        selected_phase          : unsigned(31 downto 0);
        new_phase               : unsigned(31 downto 0);
        mapped_velocity         : unsigned(31 downto 0);
        mapped_slew             : signed(19 downto 0);
        new_target              : t_ctrl_value;
        selected_amplitude      : t_ctrl_value;
        selected_velocity       : t_ctrl_value;
        target                  : t_ctrl_value;
        value                   : signed(CTRL_SIZE + 3 downto 0);
        new_value               : signed(CTRL_SIZE + 4 downto 0); -- Extra guard bit to prevent overflow.
    end record;

    constant REG_INIT : t_sh_reg := (
        state                   => idle,
        sample_hold_out         => (others => (others => (others => '0'))),
        sample_hold_buffer      => (others => (others => (others => '0'))),
        sample_hold_target      => (others => (others => (others => '0'))),
        instance_counter        => 0,
        voice_counter           => 0,
        phase                   => (others => (others => (others => '0'))),
        selected_phase          => (others => '0'),
        new_phase               => (others => '0'),
        mapped_velocity         => (others => '0'),
        mapped_slew             => (others => '0'),
        new_target              => (others => '0'),
        selected_amplitude      => (others => '0'),
        selected_velocity       => (others => '0'),
        target                  => (others => '0'),
        value                   => (others => '0'),
        new_value               => (others => '0')
    );

    signal r, r_in              : t_sh_reg;

    signal s_log_vel_data_in_valid  : std_logic;
    signal s_log_vel_data_in        : t_ctrl_value;
    signal s_log_vel_data_out_valid : std_logic;
    signal s_log_vel_data_out       : unsigned(31 downto 0);

    signal s_log_slew_data_in_valid  : std_logic;
    signal s_log_slew_data_in        : t_ctrl_value;
    signal s_log_slew_data_out_valid : std_logic;
    signal s_log_slew_data_out       : unsigned(19 downto 0);

begin 

    -- Used to map velocity control values.
    lin2log32 : entity wave.lin2log 
    generic map (
        WIDTH                   => 32,
        INIT_FILE               => GET_INPUT_FILE_PATH & "log_velocity.hex"
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        data_in_valid           => s_log_vel_data_in_valid,
        data_in                 => s_log_vel_data_in,
        data_out_valid          => s_log_vel_data_out_valid,
        data_out                => s_log_vel_data_out
    );

    -- Used to map slew rate.
    lin2log20 : entity wave.lin2log 
    generic map (
        WIDTH                   => CTRL_SIZE + 4,
        INIT_FILE               => GET_INPUT_FILE_PATH & "log_slew.hex"
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        data_in_valid           => s_log_slew_data_in_valid,
        data_in                 => s_log_slew_data_in,
        data_out_valid          => s_log_slew_data_out_valid,
        data_out                => s_log_slew_data_out
    );

    combinatorial : process (r, next_sample, sample_hold_input, status, 
            s_log_vel_data_out_valid, s_log_vel_data_out, s_log_slew_data_out_valid, s_log_slew_data_out)

        variable v_mult_result : signed(2 * CTRL_SIZE - 1 downto 0);
    begin

        r_in <= r;

        -- Connect outputs. 
        sample_hold_out <= r.sample_hold_out;

        -- Default inputs.
        s_log_vel_data_in_valid <= '0';
        s_log_vel_data_in <= (others => '0');

        -- Connect slew rate lin2log input.
        s_log_slew_data_in <= 
            to_signed(2**(CTRL_SIZE - 1) - 1, CTRL_SIZE) when sample_hold_input(r.instance_counter).slew_rate < 0 
            else sample_hold_input(r.instance_counter).slew_rate;

        case r.state is 

        -- Check for next_sample pulse.
        when idle => 
            if next_sample = '1' then 

                for i in 0 to N_INSTANCES - 1 loop 
                    for j in 0 to POLYPHONY_MAX - 1 loop
                        r_in.sample_hold_out(i)(j) <= r.sample_hold_buffer(i)(j)(CTRL_SIZE + 3 downto 4);
                    end loop;
                end loop;
    
                r_in.instance_counter <= 0;
                r_in.voice_counter <= 0;
                r_in.state <= map_slew;
            end if;        

        -- Input (clipped) slew rate into lin2log.
        when map_slew => 
            s_log_slew_data_in_valid <= '1';    
            r_in.state <= store_slew;

        -- Mux phase and store mapped velocity.
        when store_slew =>

            if s_log_slew_data_out_valid = '1' then
                r_in.mapped_slew <= signed(s_log_slew_data_out);
                r_in.state <= select_velocity;
            end if;

        -- Mux velocity (MODD) value.
        when select_velocity => 
            r_in.selected_velocity <= status.mod_destinations(MODD_SH_VELOCITY + r.instance_counter)(r.voice_counter);
            r_in.state <= map_velocity;

        -- Input (clipped and inverted) velocity into lin2log.
        when map_velocity => 
            s_log_vel_data_in_valid <= '1';
            s_log_vel_data_in <= to_signed(2**(CTRL_SIZE - 1) - 1, CTRL_SIZE) when r.selected_velocity < 0 
                else to_signed(2**(CTRL_SIZE - 1) - 1, CTRL_SIZE) - r.selected_velocity;
    
            r_in.state <= store_velocity;

        -- Mux phase and store mapped velocity.
        when store_velocity =>

            r_in.selected_phase <= r.phase(r.instance_counter)(r.voice_counter);

            if s_log_vel_data_out_valid = '1' then
                r_in.mapped_velocity <= s_log_vel_data_out;
                r_in.state <= increment_phase;
            end if;

        -- Increment phase.
        when increment_phase => 
            r_in.new_phase <= r.selected_phase + r.mapped_velocity;
            r_in.state <= check_overflow;

        -- Store incremented phase and check for overflow.
        when check_overflow => 

            r_in.phase(r.instance_counter)(r.voice_counter) <= r.new_phase;

            -- Check for phase overflow.
            if r.new_phase < r.selected_phase then 
                r_in.state <= update_target;
            else 
                r_in.state <= select_target;
            end if;
        
        -- Select amplitude (MODD) value and generate new output value.
        when update_target => 

            r_in.selected_amplitude <= 
                status.mod_destinations(MODD_SH_AMPLITUDE + r.instance_counter)(r.voice_counter);
            r_in.new_target <= 
                status.mod_sources(sample_hold_input(r.instance_counter).input_select)(r.voice_counter);

            r_in.state <= scale_target;

        -- Multiply new value with amplitude.
        when scale_target =>
            v_mult_result := r.new_target * r.selected_amplitude;
            r_in.new_target <= v_mult_result(2 * CTRL_SIZE - 2 downto CTRL_SIZE - 1);
            r_in.state <= assign_target;

        -- Assign new output value(s).
        when assign_target =>
            r_in.sample_hold_target(r.instance_counter)(r.voice_counter) <= r.new_target;
            r_in.state <= select_target;

        -- Mux target and output values.
        when select_target => 
            r_in.target <= r.sample_hold_target(r.instance_counter)(r.voice_counter);
            r_in.value <= r.sample_hold_buffer(r.instance_counter)(r.voice_counter);
            r_in.state <= update_slew;

        -- Move output value to target with slew rate.
        -- The slew rate has 4 more lsb than the value and target to allow slow slew rates.
        -- One msb guard bit is added to avoid overflow.
        when update_slew => 
            if r.value(19 downto 20 - CTRL_SIZE) < r.target then 
                r_in.new_value <= minimum(resize(r.target & "0000", CTRL_SIZE + 5),
                    resize(r.value, CTRL_SIZE + 5) + resize(r.mapped_slew, CTRL_SIZE + 5));

            elsif r.value(19 downto 20 - CTRL_SIZE) > r.target then 
                r_in.new_value <= maximum(resize(r.target & "0000", CTRL_SIZE + 5),
                    resize(r.value, CTRL_SIZE + 5) - resize(r.mapped_slew, CTRL_SIZE + 5));
            else 
                r_in.new_value <= resize(r.target & "0000", CTRL_SIZE + 5);
            end if;  

            r_in.state <= update_value;

        -- Mux update output value to buffer.
        when update_value => 
            r_in.sample_hold_buffer(r.instance_counter)(r.voice_counter) <= r.new_value(CTRL_SIZE + 3 downto 0);
            r_in.state <= update_counters;

        -- Update voice and instance counters. 
        when update_counters =>
            if r.voice_counter = POLYPHONY_MAX - 1 then
                if r.instance_counter = N_INSTANCES - 1 then 
                    r_in.state <= idle;
                else 
                    r_in.instance_counter <= r.instance_counter + 1;
                    r_in.voice_counter <= 0;
                    r_in.state <= select_velocity;
                end if; 
            else
                r_in.voice_counter <= r.voice_counter + 1;
                r_in.state <= select_velocity;
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