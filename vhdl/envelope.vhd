library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;

-- Implements N_INSTANCES separate envelopes that each track the envelope for all voices. 
-- The envelopes generate a circular shape for the decay and release stages using a cordic. 
-- The mapping from control value to velocity done using a ROM that maps the control values logarithmically for 
-- more fine control at high rates. The min and max periods are also hidden in that transformation. 
entity envelope is
    generic (
        N_INSTANCES             : natural -- Number of envelopes this entity implements.
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic;
        envelope_input          : in  t_envelope_input_array(0 to N_INSTANCES - 1);
        osc_inputs              : in  t_osc_input_array(0 to POLYPHONY_MAX - 1);
        envelope_out            : out t_envelope_out;
        envelope_active         : out std_logic_vector(POLYPHONY_MAX - 1 downto 0) -- Array of envelope active OR-ed per voice.
    );
end entity;


architecture arch of envelope is

    -- Length of pipeline stages in cycles. 
    constant PIPE_LEN_MUX_IN    : integer := 1;
    constant PIPE_LEN_PHASE     : integer := 1;
    constant PIPE_LEN_MUX_OUT   : integer := 1; 
    constant PIPE_LEN_CORDIC    : integer := 22;
    constant PIPE_LEN_MULT      : integer := 4;

    -- Cumulative length of pipeline stages in cycles. 
    constant PIPE_SUM_PHASE     : integer := PIPE_LEN_MUX_IN + PIPE_LEN_PHASE;
    constant PIPE_SUM_MUX_OUT   : integer := PIPE_SUM_PHASE + PIPE_LEN_MUX_OUT;
    constant PIPE_SUM_CORDIC    : integer := PIPE_SUM_MUX_OUT + PIPE_LEN_CORDIC;
    constant PIPE_SUM_MULT      : integer := PIPE_SUM_CORDIC + PIPE_LEN_MULT;

    type t_state is (idle, wait_valid, map_attack, map_decay, map_release, running);
    type t_adsr_state is (attack, decay, sustain, state_release, closed);
    type t_adsr_state_array is array (0 to POLYPHONY_MAX - 1) of t_adsr_state;
    type t_adsr_state_2d_array is array (0 to N_INSTANCES - 1) of t_adsr_state_array;
    type t_envelope_phase_array is array (0 to POLYPHONY_MAX - 1) of unsigned(31 downto 0);
    type t_envelope_phase_2d_array is array (0 to N_INSTANCES - 1) of t_envelope_phase_array;
    type t_index_array is array (0 to PIPE_SUM_MULT) of integer range 0 to POLYPHONY_MAX - 1;

    type t_envelope_reg is record
        state                   : t_state;
        adsr_state              : t_adsr_state_2d_array;
        adsr_state_in           : t_adsr_state;
        adsr_state_out          : t_adsr_state;
        update_adsr_state       : std_logic;
        update_phase            : std_logic;
        update_release_amp      : std_logic;
        envelope_out            : t_envelope_out;
        envelope_buffer         : t_envelope_out;
        velocity_attack         : unsigned(31 downto 0);
        velocity_decay          : unsigned(31 downto 0);
        velocity_release        : unsigned(31 downto 0);
        phase                   : t_envelope_phase_2d_array; -- Cordic phase inputs in [0 - 1] for each instance for each output.
        phase_in                : unsigned(31 downto 0);
        phase_out               : unsigned(31 downto 0);
        index_array             : t_index_array;
        valid_array             : std_logic_vector(0 to PIPE_SUM_MULT);
        release_amp             : t_envelope_out; -- Amplitude at start of release. Normally equal to sustain except when the note is released early.
        release_amp_out         : t_ctrl_value;
        instance_counter        : integer range 0 to N_INSTANCES - 1;
        pipeline_done           : std_logic;
        envelope_active         : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
    end record;

    constant REG_INIT : t_envelope_reg := (
        state                   => idle,
        adsr_state              => (others => (others => closed)),
        adsr_state_in           => closed,
        adsr_state_out          => closed,
        update_adsr_state       => '0',
        update_phase            => '0',
        update_release_amp      => '0',
        envelope_out            => (others => (others => (others => '0'))),
        envelope_buffer         => (others => (others => (others => '0'))),
        velocity_attack         => (others => '0'),
        velocity_decay          => (others => '0'),
        velocity_release        => (others => '0'),        
        phase                   => (others => (others => (others => '0'))),
        phase_in                => (others => '0'),
        phase_out               => (others => '0'),
        index_array             => (others => 0),
        valid_array             => (others => '0'),
        release_amp             => (others => (others => (others => '0'))),
        release_amp_out         => (others => '0'),
        instance_counter        => 0,
        pipeline_done           => '0',
        envelope_active         => (others => '0')
    ); 

    -- Register.
    signal r, r_in              : t_envelope_reg;

    signal s_mult_a             : std_logic_vector(17 downto 0);
    signal s_mult_b             : std_logic_vector(16 downto 0);
    signal s_mult_c             : std_logic_vector(32 downto 0); 
    signal s_mult_p             : std_logic_vector(35 downto 0); 
    signal s_mult_sel           : std_logic_vector(0 downto 0);

    signal s_phase_tvalid       : std_logic;
    signal s_phase_tdata        : std_logic_vector(39 downto 0); -- IP core adds 4 unused bits. 
    signal s_dout_tvalid        : std_logic;
    signal s_dout_tdata         : std_logic_vector(47 downto 0); -- Sin & cos.

    signal s_cordic_sin         : signed(17 downto 0); -- 2.16 fixed point.
    signal s_cordic_cos         : signed(17 downto 0);

    signal s_data_in_valid      : std_logic;
    signal s_data_in            : t_ctrl_value;
    signal s_data_out_valid     : std_logic;
    signal s_data_out           : unsigned(31 downto 0);

begin

    lin2log : entity wave.lin2log 
    generic map (
        WIDTH                   => 32,
        INIT_FILE               => GET_INPUT_FILE_PATH & "log_velocity.hex"
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        data_in_valid           => s_data_in_valid,
        data_in                 => s_data_in,
        data_out_valid          => s_data_out_valid,
        data_out                => s_data_out
    );

    mult : entity xil_defaultlib.envelope_mult_gen 
    port map (
        clk                     => clk,
        a                       => s_mult_a,
        b                       => s_mult_b,
        c                       => s_mult_c,
        p                       => s_mult_p,
        sel                     => s_mult_sel
    );

    cordic : entity xil_defaultlib.envelope_cordic_gen
    port map (
        aclk                    => clk,
        s_axis_phase_tvalid     => s_phase_tvalid,
        s_axis_phase_tdata      => s_phase_tdata,
        m_axis_dout_tvalid      => s_dout_tvalid,
        m_axis_dout_tdata       => s_dout_tdata
    );

    combinatorial : process (r, next_sample, envelope_input, osc_inputs, s_mult_p, s_dout_tvalid, s_dout_tdata, 
            s_cordic_cos, s_cordic_sin, s_data_out_valid, s_data_out)

        variable v_envelope_active : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        variable v_new_phase : unsigned(31 downto 0);
    begin

        -- Default register input.
        r_in <= r;
        r_in.update_adsr_state <= '0';
        r_in.update_phase <= '0';
        r_in.update_release_amp <= '0';

        -- Connect outputs.
        envelope_out <= r.envelope_out;
        envelope_active <= r.envelope_active;

        -- OR all adsr states into single array.
        v_envelope_active := (others => '0');
        for i in 0 to N_INSTANCES - 1 loop 
            for j in 0 to POLYPHONY_MAX - 1 loop 
                v_envelope_active(j) := v_envelope_active(j) when r.adsr_state(i)(j) = closed else '1';
            end loop;
        end loop;
        r_in.envelope_active <= v_envelope_active;

        -- Default multiplier inputs.
        s_mult_a <= (others => '0');
        s_mult_b <= (others => '0');
        s_mult_c <= (others => '0');
        s_mult_sel <= (others => '0'); -- "0": A * B + C, "1": A * B 

        -- Default cordic inputs.
        s_phase_tvalid <= '0';
        s_phase_tdata <= (others => '0');

        s_cordic_cos <= signed(s_dout_tdata(17 downto 0));
        s_cordic_sin <= signed(s_dout_tdata(41 downto 24));

        -- Default lin2log inputs.
        s_data_in_valid <= '0';
        s_data_in <= (others => '0');

        case r.state is 
        when idle => 

            r_in.valid_array <= (others => '0');
            r_in.index_array <= (others => 0);

            if next_sample = '1' or r.pipeline_done = '0' then 

                if next_sample = '1' then 
                    r_in.envelope_out <= r.envelope_buffer;
                    r_in.instance_counter <= 0;
                    r_in.pipeline_done <= '0';
                end if;

                r_in.state <= map_attack;
            end if;

        when map_attack =>

            s_data_in_valid <= '1';
            s_data_in <= x"0020" when envelope_input(r.instance_counter).attack < x"0040" 
                else envelope_input(r.instance_counter).attack; -- Use small minimum value to avoid clicking noise.

            r_in.state <= map_decay;

        when map_decay =>

            if s_data_out_valid = '1' then 
                r_in.velocity_attack <= s_data_out;
                s_data_in_valid <= '1';
                s_data_in <= x"0000" when envelope_input(r.instance_counter).decay < 0 
                    else envelope_input(r.instance_counter).decay;

                r_in.state <= map_release;
            end if;

        when map_release =>

            if s_data_out_valid = '1' then 
                r_in.velocity_decay <= s_data_out;
                s_data_in_valid <= '1';
                s_data_in <= x"0020" when envelope_input(r.instance_counter).release_value < x"0040" 
                    else envelope_input(r.instance_counter).release_value; -- Use small minimum value to avoid clicking noise.

                r_in.state <= wait_valid;
            end if;
            
    	when wait_valid => 

            if s_data_out_valid = '1' then 
                r_in.velocity_release <= unsigned(s_data_out);
                r_in.valid_array(0) <= '1';
                r_in.state <= running;
            end if;

        -- Run ADSR calculation pipeline.
        when running => 

            -- Increment index counter and set valid shift register input.
            if r.index_array(0) < POLYPHONY_MAX - 1 then 
                r_in.valid_array(0) <= '1';
                r_in.index_array(0) <= r.index_array(0) + 1;
            else 
                r_in.valid_array(0) <= '0';
            end if;

            -- Pipeline stage 0: Mux phase and adsr state of active instance and output for better timing.
            if r.valid_array(0) = '1' then 
                r_in.phase_in <= r.phase(r.instance_counter)(r.index_array(0));
                r_in.adsr_state_in <= r.adsr_state(r.instance_counter)(r.index_array(0));
            end if;

            -- Pipeline stage 1: increment phase based on adsr state and do adsr state transitions.
            if r.valid_array(PIPE_LEN_MUX_IN) = '1' then 

                -- Check for voice being triggered.
                if r.adsr_state_in = closed then 

                    if osc_inputs(r.index_array(PIPE_LEN_MUX_IN)).enable = '1' then 

                        r_in.update_adsr_state <= '1';
                        r_in.adsr_state_out <= attack;

                        r_in.update_phase <= '1';
                        r_in.phase_out <= (others => '0');
                    end if;

                -- Increment state phase.
                elsif r.adsr_state_in /= sustain then 
                    
                    -- Increment phase.
                    r_in.update_phase <= '1';
 
                    with r.adsr_state_in select v_new_phase := 
                        r.phase_in + r.velocity_attack when attack, 
                        r.phase_in + r.velocity_decay when decay, 
                        r.phase_in + r.velocity_release when others; -- state_release
                    
                    -- Check for overflow.
                    if v_new_phase(31) = '0' and r.phase_in(31) = '1' then 
                        r_in.phase_out <= (others => '0');
                        r_in.update_adsr_state <= '1';
                        with r.adsr_state_in select r_in.adsr_state_out <= decay when attack,
                                                                           sustain when decay,
                                                                           closed when others; -- state_release
                    else 
                        r_in.phase_out <= v_new_phase;
                    end if;
                end if; 

                -- Check if active voice is released. 
                if r.adsr_state_in = attack or r.adsr_state_in = decay or r.adsr_state_in = sustain then 

                    if osc_inputs(r.index_array(PIPE_LEN_MUX_IN)).enable = '0' then 

                        r_in.update_phase <= '1';
                        r_in.update_adsr_state <= '1';
                        r_in.update_release_amp <= '1';

                        r_in.phase_out <= (others => '0');
                        r_in.adsr_state_out <= state_release;
                        r_in.release_amp_out <= r.envelope_buffer(r.instance_counter)(r.index_array(PIPE_LEN_MUX_IN));
                    end if;
                end if;

                -- Check for voice retrigger in release state. 
                if r.adsr_state_in = state_release and osc_inputs(r.index_array(PIPE_LEN_MUX_IN)).enable = '1' then 

                    r_in.update_phase <= '1';
                    r_in.phase_out <= unsigned(r.envelope_buffer(r.instance_counter)
                        (r.index_array(PIPE_LEN_MUX_IN))(14 downto 0)) & (0 to 16 => '0');
                        
                    r_in.update_adsr_state <= '1';
                    r_in.adsr_state_out <= attack;
                end if;
            end if;

            --     case r.adsr_state(r.instance_counter)(r.index_array(PIPE_LEN_MUX_IN)) is 

            --         when closed => 

            --             if osc_inputs(r.index_array(PIPE_LEN_MUX_IN)).enable = '1' then 

            --                 r_in.update_adsr_state <= '1';
            --                 r_in.adsr_state_out <= attack;

            --                 r_in.update_phase <= '1';
            --                 r_in.phase_out <= (others => '0');
            --             end if;
                
            --         when attack =>
            --             increment_phase(r, r_in, r.velocity_attack, decay);
            --             check_release(r, r_in, osc_inputs); -- This function must be called after increment_phase.

            --         when decay => 
            --             increment_phase(r, r_in, r.velocity_decay, sustain);
            --             check_release(r, r_in, osc_inputs);

            --         when sustain => 
            --             check_release(r, r_in, osc_inputs);

            --         when state_release => 
            --             increment_phase(r, r_in, r.velocity_release, closed);

            --             -- Note is re-triggered during release.
            --             if osc_inputs(r.index_array(PIPE_LEN_MUX_IN)).enable = '1' then 

            --                 r_in.update_phase <= '1';
            --                 r_in.phase_out <= unsigned(r.envelope_buffer(r.instance_counter)
            --                     (r.index_array(PIPE_LEN_MUX_IN))(14 downto 0)) & (0 to 16 => '0');
                                
            --                 r_in.update_adsr_state <= '1';
            --                 r_in.adsr_state_out <= attack;
            --             end if;
            --     end case;
            -- end if;

            -- Pipeline stage 2: Mux new phase back to registers.
            if r.update_phase = '1' then 
                r_in.phase(r.instance_counter)(r.index_array(PIPE_SUM_PHASE)) <= r.phase_out;
            end if;

            -- Pipeline stage 2: Mux new state to registers.
            if r.update_adsr_state = '1' then 
                r_in.adsr_state(r.instance_counter)(r.index_array(PIPE_SUM_PHASE)) <= r.adsr_state_out;
            end if;

            -- Pipeline stage 2: Mux new release_amp to registers.
            if r.update_release_amp = '1' then 
                r_in.release_amp(r.instance_counter)(r.index_array(PIPE_SUM_PHASE)) <= r.release_amp_out;
            end if;

            -- Pipeline stage 3: cordic phase input.
            if r.valid_array(PIPE_SUM_MUX_OUT) = '1' then 
                s_phase_tvalid <= '1';
                s_phase_tdata <= x"01" & std_logic_vector(r.phase(r.instance_counter)(r.index_array(PIPE_SUM_MUX_OUT))); -- [0.5, 1] in signed 8.32 fixed point. 
            end if;

            -- Pipeline stage 25: offset and scale cordic output.
            if r.valid_array(PIPE_SUM_CORDIC) = '1' then 

                case r.adsr_state(r.instance_counter)(r.index_array(PIPE_SUM_CORDIC)) is 

                -- This state does not use the cordic.
                -- envelope = phase
                when attack => 
                    s_mult_c <= "00" 
                        & std_logic_vector(r.phase(r.instance_counter)(r.index_array(PIPE_SUM_CORDIC))(31 downto 1));

                -- envelope = 1 + (1 - sustain) * cordic_output
                when decay => 
                    s_mult_a <= std_logic_vector(s_cordic_cos);
                    s_mult_b <= std_logic_vector(17x"0_7FFF" - resize(envelope_input(r.instance_counter).sustain, 17));
                    s_mult_c <= 33x"0_7FFF_FFFF";

                -- envelope = sustain
                when sustain =>
                    s_mult_c <= 33x"000000000" when envelope_input(r.instance_counter).sustain < 0 
                        else '0' & std_logic_vector(envelope_input(r.instance_counter).sustain) & x"0000";

                -- envelope = release_amp + release_amp * cordic_output
                when state_release => 
                    s_mult_a <= std_logic_vector(s_cordic_cos);
                    s_mult_b <= std_logic_vector(
                        resize(r.release_amp(r.instance_counter)(r.index_array(PIPE_SUM_CORDIC)), 17));

                    s_mult_c <= std_logic_vector(
                        resize(r.release_amp(r.instance_counter)(r.index_array(PIPE_SUM_CORDIC)) & x"FFFF", 33));

                when others =>
                end case;
            end if;

            -- Pipeline stage 29: writeback.
            if r.valid_array(PIPE_SUM_MULT) = '1' then 
                r_in.envelope_buffer(r.instance_counter)(r.index_array(PIPE_SUM_MULT)) <= signed(s_mult_p(31 downto 16));
            end if;

            -- Pipeline stage 29: Check for end of pipeline.
            if r.valid_array(PIPE_SUM_MULT) = '1' and r.index_array(PIPE_SUM_MULT) = POLYPHONY_MAX - 1 then 

                r_in.state <= idle;

                if r.instance_counter < N_INSTANCES - 1 then
                    r_in.instance_counter <= r.instance_counter + 1;
                else 
                    r_in.pipeline_done <= '1';
                end if;
            end if;

            -- Update shift registers.
            r_in.valid_array(1 to PIPE_SUM_MULT) <= r.valid_array(0 to PIPE_SUM_MULT - 1);
            r_in.index_array(1 to PIPE_SUM_MULT) <= r.index_array(0 to PIPE_SUM_MULT - 1);

        end case;

    end process;

    reg_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= REG_INIT; -- This saves resources.
                -- r.state <= idle;
                -- r.adsr_state <= (others => (others => closed));
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
