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

    type t_state is (idle, select_velocity, map_velocity, store_velocity, increment_phase, check_overflow,
        update_value, scale_value, assign_value, update_counters);
    type t_sample_hold_phase_array is array (0 to POLYPHONY_MAX - 1) of unsigned(31 downto 0);
    type t_sample_hold_phase_2d_array is array (0 to N_INSTANCES - 1) of t_sample_hold_phase_array;

    type t_mixer_reg is record
        state                   : t_state;
        sample_hold_out         : t_sample_hold_out;
        sample_hold_buffer      : t_sample_hold_out;
        instance_counter        : integer range 0 to N_INSTANCES - 1;
        voice_counter           : integer range 0 to POLYPHONY_MAX - 1;
        bit_counter             : integer range 0 to 15;
        phase                   : t_sample_hold_phase_2d_array;
        selected_phase          : unsigned(31 downto 0);
        new_phase               : unsigned(31 downto 0);
        mapped_velocity         : unsigned(31 downto 0);
        new_value               : t_ctrl_value;
        selected_amplitude      : t_ctrl_value;
        selected_velocity       : t_ctrl_value;
        individual              : std_logic;
        binaural                : std_logic;
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        sample_hold_out         => (others => (others => (others => '0'))),
        sample_hold_buffer      => (others => (others => (others => '0'))),
        instance_counter        => 0,
        voice_counter           => 0,
        bit_counter             => 0,
        phase                   => (others => (others => (others => '0'))),
        selected_phase          => (others => '0'),
        new_phase               => (others => '0'),
        mapped_velocity         => (others => '0'),
        new_value               => (others => '0'),
        selected_amplitude      => (others => '0'),
        selected_velocity       => (others => '0'),
        individual              => '0',
        binaural                => '0'
    );

    signal r, r_in              : t_mixer_reg;

    signal s_data_in_valid      : std_logic;
    signal s_data_in            : t_ctrl_value;
    signal s_data_out_valid     : std_logic;
    signal s_data_out           : unsigned(31 downto 0);

    signal s_lfsr_read_enable   : std_logic;
    signal s_lfsr_bit_out       : std_logic;

begin 

    lin2log : entity wave.lin2log 
    port map (
        clk                     => clk,
        reset                   => reset,
        data_in_valid           => s_data_in_valid,
        data_in                 => s_data_in,
        data_out_valid          => s_data_out_valid,
        data_out                => s_data_out
    );

    lsfr : entity wave.lfsr16 
    port map (
        clk                     => clk,
        reset                   => reset,
        read_enable             => s_lfsr_read_enable,
        bit_out                 => s_lfsr_bit_out
    );

    combinatorial : process (r, next_sample, sample_hold_input, status, s_data_out_valid, s_data_out, s_lfsr_bit_out)
        variable v_mult_result : signed(2 * CTRL_SIZE - 1 downto 0);
    begin

        r_in <= r;

        -- Connect outputs. 
        sample_hold_out <= r.sample_hold_out;

        -- Default inputs.
        s_data_in_valid <= '0';
        s_data_in <= (others => '0');
        s_lfsr_read_enable <= '0';

        case r.state is 

        -- Check for next_sample pulse.
        when idle => 
            if next_sample = '1' then 
                r_in.sample_hold_out <= r.sample_hold_buffer;
                r_in.instance_counter <= 0;
                r_in.voice_counter <= 0;
                r_in.state <= select_velocity;
            end if;

        -- Mux velocity (MODD) value and latch intput values so they don't change during operation.
        when select_velocity => 
            r_in.individual <= sample_hold_input(r.instance_counter).individual;
            r_in.binaural <= sample_hold_input(r.instance_counter).binaural;
            r_in.selected_velocity <= status.mod_destinations(MODD_SH_VELOCITY + r.instance_counter)(r.voice_counter);
            r_in.state <= map_velocity;

        -- Input (clipped) velocity into lin2log.
        when map_velocity => 
            s_data_in_valid <= '1';
            s_data_in <= x"0000" when r.selected_velocity < 0 else r.selected_velocity;
            r_in.state <= store_velocity;

        -- Mux phase value and store mapped velocity.
        when store_velocity =>
            r_in.selected_phase <= r.phase(r.instance_counter)(r.voice_counter);

            if s_data_out_valid = '1' then
                r_in.mapped_velocity <= s_data_out;
                r_in.state <= increment_phase;
            end if;
            
        -- Increment phase.
        when increment_phase => 
            r_in.new_phase <= r.selected_phase + r.mapped_velocity;
            r_in.state <= check_overflow;

        -- Store incremented phase and check for overflow.
        when check_overflow => 

            -- Store new phase.
            if r.individual = '0' then 
                for i in 0 to POLYPHONY_MAX - 1 loop 
                    r_in.phase(r.instance_counter)(i) <= r.new_phase;
                end loop;
            else 
                r_in.phase(r.instance_counter)(r.voice_counter) <= r.new_phase;
                if r.binaural = '0' then 
                    r_in.phase(r.instance_counter)(r.voice_counter + 1) <= r.new_phase;
                end if;
            end if;

            -- Check for phase overflow.
            if r.new_phase < r.selected_phase then 
                r_in.bit_counter <= 0;
                r_in.state <= update_value;
            else 
                r_in.state <= update_counters;
            end if;
        
        -- Select amplitude (MODD) value and generate new output value.
        when update_value => 

            r_in.selected_amplitude <= status.mod_destinations(MODD_SH_AMPLITUDE + r.instance_counter)(r.voice_counter);

            s_lfsr_read_enable <= '1';
            r_in.new_value(r.bit_counter) <= s_lfsr_bit_out;

            if r.bit_counter < 15 then 
                r_in.bit_counter <= r.bit_counter + 1;
            else 
                r_in.state <= scale_value;
            end if;

        -- Multiply new value with amplitude.
        when scale_value =>
            v_mult_result := r.new_value * r.selected_amplitude;
            r_in.new_value <= v_mult_result(2 * CTRL_SIZE - 2 downto CTRL_SIZE - 1);
            r_in.state <= assign_value;

        -- Assign new output value(s).
        when assign_value =>
        
            if r.individual = '0' then 
                for i in 0 to POLYPHONY_MAX - 1 loop
                    r_in.sample_hold_buffer(r.instance_counter)(i) <= r.new_value;
                end loop;
            else 
                r_in.sample_hold_buffer(r.instance_counter)(r.voice_counter) <= r.new_value;
                if r.binaural = '0' then 
                    r_in.sample_hold_buffer(r.instance_counter)(r.voice_counter + 1) <= r.new_value;
                end if;
            end if; 

            r_in.state <= update_counters;

        -- Update voice and instance counters. 
        when update_counters =>

            if r.individual = '0' 
                    or (r.binaural = '1' and r.voice_counter = POLYPHONY_MAX - 1) 
                    or (r.binaural = '0' and r.voice_counter = POLYPHONY_MAX - 2) then 

                if r.instance_counter = N_INSTANCES - 1 then 
                    r_in.state <= idle;
                else 
                    r_in.instance_counter <= r.instance_counter + 1;
                    r_in.voice_counter <= 0;
                    r_in.state <= select_velocity;
                end if; 
            else 
                if r.binaural = '1' then 
                    r_in.voice_counter <= r.voice_counter + 1;
                else 
                    r_in.voice_counter <= r.voice_counter + 2;
                end if;

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