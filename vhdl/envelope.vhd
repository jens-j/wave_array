library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;


entity envelope is
    generic (
        N_INPUTS                : positive
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic;
        config                  : in  t_config;
        osc_inputs              : in  t_osc_input_array(0 to N_INPUTS - 1);
        ctrl_out                : out t_ctrl_value_array;
        envelope_active         : out std_logic_vector(N_VOICES - 1 downto 0)
    );
end entity;


architecture linear of envelope is

    -- Length of pipeline stages in cycles. 
    constant PIPE_LEN_PHASE     : integer := 1;
    constant PIPE_LEN_CORDIC    : integer := 22;
    constant PIPE_LEN_MULT      : integer := 4;

    -- Cumulative length of pipeline stages in cycles. 
    constant PIPE_SUM_CORDIC    : integer := PIPE_LEN_PHASE + PIPE_LEN_CORDIC;
    constant PIPE_SUM_MULT      : integer := PIPE_SUM_CORDIC + PIPE_LEN_MULT;

    -- Calculate minimum and maximum velocity.
    constant ATTACK_MIN         : real := 1.0 / (ENV_MAX_ATTACK_T * real(SAMPLE_RATE)); 
    constant ATTACK_MAX         : real := 1.0 / (ENV_MIN_ATTACK_T * real(SAMPLE_RATE));      
    constant ATTACK_A           : std_logic_vector := std_logic_vector(to_unsigned(
        integer((ATTACK_MAX - ATTACK_MIN) * real(2**CTRL_SIZE)), 16));
    constant ATTACK_C           : std_logic_vector := std_logic_vector(to_unsigned(
        integer(ATTACK_MIN * real(2**(2 * CTRL_SIZE))), 32));

    constant DECAY_MIN          : real := 1.0 / real(ENV_MAX_DECAY_T * real(SAMPLE_RATE)); 
    constant DECAY_MAX          : real := 1.0 / real(ENV_MIN_DECAY_T * real(SAMPLE_RATE));      
    constant DECAY_A            : std_logic_vector := std_logic_vector(to_unsigned(
        integer((DECAY_MAX - DECAY_MIN) * real(2**CTRL_SIZE)), 16));
    constant DECAY_C            : std_logic_vector := std_logic_vector(to_unsigned(
        integer(DECAY_MIN * real(2**(2 * CTRL_SIZE))), 32));

    constant RELEASE_MIN        : real := 1.0 / real(ENV_MAX_RELEASE_T * real(SAMPLE_RATE)); 
    constant RELEASE_MAX        : real := 1.0 / real(ENV_MIN_RELEASE_T * real(SAMPLE_RATE));      
    constant RELEASE_A          : std_logic_vector := std_logic_vector(to_unsigned(
        integer((RELEASE_MAX - RELEASE_MIN) * real(2**CTRL_SIZE)), 16));
    constant RELEASE_C          : std_logic_vector := std_logic_vector(to_unsigned(
        integer(ATTACK_MIN * real(2**(2 * CTRL_SIZE))), 32));


    type t_state is (idle, wait_valid, map_attack, map_decay, map_release, running);

    type t_adsr_state is (attack, decay, sustain, state_release, closed);
    type t_adsr_state_array is array (0 to N_INPUTS - 1) of t_adsr_state;
    type t_phase_array is array (0 to N_INPUTS - 1) of unsigned(31 downto 0);
    type t_index_array is array (0 to PIPE_SUM_MULT) of integer range 0 to N_INPUTS - 1;

    type t_envelope_reg is record
        state                   : t_state;
        next_state              : t_state;
        adsr_state              : t_adsr_state_array;
        ctrl_out                : t_ctrl_value_array(0 to N_INPUTS - 1);
        ctrl_buffer             : t_ctrl_value_array(0 to N_INPUTS - 1);
        latency_count           : integer range 0 to PIPE_LEN_MULT - 1;
        velocity_attack         : unsigned(31 downto 0);
        velocity_decay          : unsigned(31 downto 0);
        velocity_release        : unsigned(31 downto 0);
        phase                   : t_phase_array; -- Cordic phase inputs in [0 - 1].
        index_array             : t_index_array;
        valid_array             : std_logic_vector(0 to PIPE_SUM_MULT);
        release_amp             : t_ctrl_value_array(0 to N_INPUTS - 1); -- Amplitude at start of release. Normally equal to sustain except when the note is released early.
    end record;

    constant REG_INIT : t_envelope_reg := (
        state                   => idle,
        next_state              => idle,
        adsr_state              => (others => closed),
        ctrl_out                => (others => (others => '0')),
        ctrl_buffer             => (others => (others => '0')),
        latency_count           => 0,
        velocity_attack         => (others => '0'),
        velocity_decay          => (others => '0'),
        velocity_release        => (others => '0'),        
        phase                   => (others => (others => '0')),
        index_array             => (others => 0),
        valid_array             => (others => '0'),
        release_amp             => (others => (others => '0'))
    ); 

    -- Register.
    signal r, r_in              : t_envelope_reg;

    signal s_mult_a             : std_logic_vector(16 downto 0);
    signal s_mult_b             : std_logic_vector(16 downto 0);
    signal s_mult_c             : std_logic_vector(32 downto 0); 
    signal s_mult_p             : std_logic_vector(34 downto 0); 
    signal s_mult_sel           : std_logic_vector(0 downto 0);

    signal s_phase_tvalid       : std_logic;
    signal s_phase_tdata        : std_logic_vector(39 downto 0); -- IP core adds 4 unused bits. 
    signal s_dout_tvalid        : std_logic;
    signal s_dout_tdata         : std_logic_vector(47 downto 0); -- Sin & cos.

    signal s_cordic_sin         : signed(16 downto 0); -- 1.16 fixed point.
    signal s_cordic_cos         : signed(16 downto 0);

    signal s_data_in_valid      : std_logic;
    signal s_data_in            : t_ctrl_value;
    signal s_data_out_valid     : std_logic;
    signal s_data_out           : unsigned(31 downto 0);

    -- Increment phase with a velocity based on the adsr state.
    procedure increment_phase(signal r          : in  t_envelope_reg;
                              signal r_in       : out t_envelope_reg;
                              signal velocity   : in  unsigned(31 downto 0);
                              constant next_state : in  t_adsr_state) is
        
        variable v_phase : unsigned(31 downto 0);
    begin
        -- Increment phase .
        v_phase := r.phase(r.index_array(0)) + velocity;

        -- Check for overflow.
        if v_phase(31) = '0' and r.phase(r.index_array(0))(31) = '1' then 
            r_in.phase(r.index_array(0)) <= (others => '0');
            r_in.adsr_state(r.index_array(0)) <= next_state;
        else 
            r_in.phase(r.index_array(0)) <= v_phase;
        end if;
    end procedure;
 
    -- Check if the voice is still enabled and go to release state if not.
    procedure check_relase(signal r          : in  t_envelope_reg;
                           signal r_in       : out t_envelope_reg;
                           signal osc_inputs : in  t_osc_input_array(0 to N_INPUTS - 1)) is
    begin
        if osc_inputs(r.index_array(0)).enable = '0' then 
            r_in.phase(r.index_array(0)) <= (others => '0');
            r_in.release_amp(r.index_array(0)) <= r.ctrl_buffer(r.index_array(0));
            r_in.adsr_state(r.index_array(0)) <= state_release;
        end if;
    end procedure;

begin

    lin2log : entity wave.lin2log 
    generic map (
        init_file => GET_INPUT_FILE_PATH & "log.hex"
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

    combinatorial : process (r, next_sample, config, osc_inputs, s_mult_p, s_dout_tvalid, s_dout_tdata, 
            s_cordic_cos, s_cordic_sin, s_data_out_valid, s_data_out)
    begin

        -- Default register input.
        r_in <= r;

        -- Connect outputs.
        ctrl_out <= r.ctrl_out;
        for i in 0 to N_INPUTS - 1 loop 
            envelope_active(i) <= '0' when r.adsr_state(i) = closed else '1';
        end loop;

        -- Default multiplier inputs.
        s_mult_a <= (others => '0');
        s_mult_b <= (others => '0');
        s_mult_c <= (others => '0');
        s_mult_sel <= (others => '0'); -- "0": A * B + C, "1": A * B 

        -- Default cordic inputs.
        s_phase_tvalid <= '0';
        s_phase_tdata <= (others => '0');

        s_cordic_cos <= signed(s_dout_tdata(16 downto 0));
        s_cordic_sin <= signed(s_dout_tdata(40 downto 24));

        s_data_in_valid <= '0';
        s_data_in <= (others => '0');

        case r.state is 
        when idle => 

            r_in.valid_array <= (others => '0');
            r_in.index_array <= (others => 0);

            if next_sample = '1' then 
                r_in.ctrl_out <= r.ctrl_buffer;
                r_in.state <= map_attack;
            end if;

        when map_attack =>

            s_data_in_valid <= '1';
            s_data_in <= x"0000" when config.envelope_attack < 0 else config.envelope_attack;

            r_in.state <= map_decay;

        when map_decay =>

            if s_data_out_valid = '1' then 
                r_in.velocity_attack <= s_data_out;
                s_data_in_valid <= '1';
                s_data_in <= x"0000" when config.envelope_decay < 0 else config.envelope_decay;
                r_in.state <= map_release;
            end if;

        when map_release =>

            if s_data_out_valid = '1' then 
                r_in.velocity_decay <= s_data_out;
                s_data_in_valid <= '1';
                s_data_in <= x"0000" when config.envelope_release < 0 else config.envelope_release;
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
            if r.index_array(0) < N_INPUTS - 1 then 
                r_in.valid_array(0) <= '1';
                r_in.index_array(0) <= r.index_array(0) + 1;
            else 
                r_in.valid_array(0) <= '0';
            end if;

            -- Pipeline stage 0: increment phase based on adsr state. Also do adsr state transitions.
            if r.valid_array(0) = '1' then 
                case r.adsr_state(r.index_array(0)) is 

                    when closed => 

                        if osc_inputs(r.index_array(0)).enable = '1' then 
                            r_in.phase(r.index_array(0)) <= (others => '0');
                            r_in.adsr_state(r.index_array(0)) <= attack;
                        end if;
                
                    when attack =>
                        increment_phase(r, r_in, r.velocity_attack, decay);
                        check_relase(r, r_in, osc_inputs);

                    when decay => 
                        increment_phase(r, r_in, r.velocity_decay, sustain);
                        check_relase(r, r_in, osc_inputs);

                    when sustain => 
                        check_relase(r, r_in, osc_inputs);

                    when state_release => 
                        increment_phase(r, r_in, r.velocity_release, closed);

                        -- Note is re-triggered during release.
                        if osc_inputs(r.index_array(0)).enable = '1' then 
                            r_in.phase(r.index_array(0)) <= (others => '0');
                            r_in.adsr_state(r.index_array(0)) <= attack;
                        end if;

                end case;
            end if;

            -- Pipeline stage 1: cordic phase input.
            if r.valid_array(PIPE_LEN_PHASE) = '1' then 
                s_phase_tvalid <= '1';
                s_phase_tdata <= x"01" & std_logic_vector(r.phase(r.index_array(PIPE_LEN_PHASE))); -- [0.5, 1] in signed 8.32 fixed point. 
            end if;

            -- Pipeline stage 21: offset and scale cordic output.
            if r.valid_array(PIPE_SUM_CORDIC) = '1' then 

                case (r.adsr_state(r.index_array(PIPE_SUM_CORDIC))) is 

                -- This state does not use the cordic.
                -- envelope = phase
                when attack => 
                    s_mult_c <= "00" & std_logic_vector(r.phase(r.index_array(PIPE_SUM_CORDIC))(31 downto 1));

                -- envelope = 1 + (1 - sustain) * cordic_output
                when decay => 
                    s_mult_a <= std_logic_vector(s_cordic_cos);
                    s_mult_b <= std_logic_vector(17x"0_7FFF" - resize(config.envelope_sustain, 17));
                    s_mult_c <= 33x"0_7FFF_FFFF";

                -- envelope = sustain
                when sustain =>
                    s_mult_c <= 33x"000000000" when config.envelope_sustain < 0 
                        else '0' & std_logic_vector(config.envelope_sustain) & x"0000";

                -- envelope = release_amp + release_amp * cordic_output
                when state_release => 
                    s_mult_a <= std_logic_vector(s_cordic_cos);
                    s_mult_b <= std_logic_vector(resize(r.release_amp(r.index_array(PIPE_SUM_CORDIC)), 17));
                    s_mult_c <= std_logic_vector(resize(r.release_amp(r.index_array(PIPE_SUM_CORDIC)) & x"FFFF", 33));

                when others =>
                end case;
            end if;

            -- Pipeline stage 25: writeback.
            if r.valid_array(PIPE_SUM_MULT) = '1' then 
                r_in.ctrl_buffer(r.index_array(PIPE_SUM_MULT)) <= signed(s_mult_p(31 downto 16));
            end if;

            -- Update shift registers.
            r_in.valid_array(1 to PIPE_SUM_MULT) <= r.valid_array(0 to PIPE_SUM_MULT - 1);
            r_in.index_array(1 to PIPE_SUM_MULT) <= r.index_array(0 to PIPE_SUM_MULT - 1);

            -- End of pipeline.
            if r.index_array(PIPE_SUM_MULT) = N_INPUTS - 1 then 
                r_in.state <= idle;
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
