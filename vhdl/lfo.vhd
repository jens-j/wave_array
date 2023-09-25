library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;


entity lfo is
    generic (
        N_OUTPUTS               : natural
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        next_sample             : in  std_logic;
        osc_inputs              : in  t_osc_input_array(0 to N_OUTPUTS - 1);
        lfo_out                 : out t_ctrl_value_array(0 to N_OUTPUTS - 1)
    );
end entity;

architecture arch of lfo is

    constant PIPE_LEN_MULT      : integer := 1;
    constant PIPE_LEN_ADD       : integer := 1;
    constant PIPE_LEN_ACC       : integer := 1;
    constant PIPE_LEN_CLIP      : integer := 1;
    constant PIPE_LEN_CORDIC    : integer := 1;

    constant PIPE_SUM_ADD       : integer := PIPE_LEN_MULT + PIPE_LEN_ADD;
    constant PIPE_SUM_ACC       : integer := PIPE_SUM_ADD + PIPE_LEN_ACC;
    constant PIPE_SUM_CLIP      : integer := PIPE_SUM_ACC + PIPE_LEN_CLIP;
    constant PIPE_SUM_CORDIC    : integer := PIPE_SUM_CLIP + PIPE_LEN_CORDIC;

    type t_state is (idle, running);
    type t_lfo_phase_array is array (0 to N_OUTPUTS - 1) of signed(LFO_PHASE_SIZE - 1 downto 0);
    type t_counter_array is array (0 to PIPE_SUM_CORDIC - 1) of integer range 0 to N_OUTPUTS - 1;

    type t_mixer_reg is record
        state                   : t_state;
        lfo_velocity            : unsigned(CTRL_SIZE - 1 downto 0);
        lfo_velocity_clipped    : unsigned(CTRL_SIZE - 1 downto 0);
        phase                   : t_lfo_phase_array;
        sine_out                : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        square_out              : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        saw_out                 : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        sine_buffer             : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        cosine_buffer           : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        square_buffer           : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        saw_buffer              : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        valid_shift             : std_logic_vector(PIPE_SUM_CORDIC - 1 downto 0); -- Pipeline valid shift register.
        index_shift             : t_counter_array; -- Output index shift register.
        read_counter            : integer range 0 to N_OUTPUTS - 1;
        phase_mul               : unsigned(CTRL_SIZE + 24 downto 0);
        phase_delta             : unsigned(LFO_PHASE_SIZE - 1 downto 0);
        phase_raw               : signed(LFO_PHASE_SIZE - 1 downto 0);
        sync                    : std_logic_vector(N_OUTPUTS - 1 downto 0);
        osc_enable              : std_logic_vector(N_OUTPUTS - 1 downto 0);
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        lfo_velocity            => (others => '0'),
        lfo_velocity_clipped    => (others => '0'),
        phase                   => (others => (others => '0')),
        sine_out                => (others => (others => '0')),
        square_out              => (others => (others => '0')),
        saw_out                 => (others => (others => '0')),
        sine_buffer             => (others => (others => '0')),
        cosine_buffer           => (others => (others => '0')),
        square_buffer           => (others => (others => '0')),
        saw_buffer              => (others => (others => '0')),
        valid_shift             => (others => '0'),
        index_shift             => (others => 0),
        read_counter            => N_OUTPUTS - 1,
        phase_mul               => (others => '0'),
        phase_delta             => (others => '0'),
        phase_raw               => (others => '0'),
        sync                    => (others => '0'),
        osc_enable              => (others => '0')
    );

    -- Clip the cordic output.
    -- The msb is dropped because it is only used for the single highest and lowest values.
    function clip_sine (raw : std_logic_vector(16 downto 0))
        return signed is
    begin
        if raw = 17x"08000" then
            return x"7FFF";
        elsif raw = 17x"18000" then
            return x"8001";
        else
            return signed(raw(15 downto 0));
        end if;
    end function;

    signal r, r_in              : t_mixer_reg;

    signal s_phase_tvalid       : std_logic;
    signal s_phase_tdata        : std_logic_vector(LFO_PHASE_SIZE - 1 downto 0);
    signal s_dout_tvalid        : std_logic;
    signal s_dout_tdata         : std_logic_vector(47 downto 0);

begin

    cordic : entity xil_defaultlib.cordic_lfo_sine
    port map (
        aclk                    => clk,
        s_axis_phase_tvalid     => s_phase_tvalid,
        s_axis_phase_tdata      => s_phase_tdata,
        m_axis_dout_tvalid      => s_dout_tvalid,
        m_axis_dout_tdata       => s_dout_tdata
    );

    combinatorial : process (r, next_sample, config, osc_inputs, s_dout_tvalid, s_dout_tdata)
        variable v_lfo_velocity_squared : unsigned(2 * CTRL_SIZE - 1 downto 0);
    begin

        r_in <= r;

        -- Select which waveform to output.
        lfo_out <= r.sine_out when config.lfo_wave_select = 0 else
                   r.saw_out when config.lfo_wave_select = 1 else 
                   r.square_out;

        -- Default inputs.
        s_phase_tvalid <= '0';
        s_phase_tdata <= (others => '0');

        -- Update shift registers.
        r_in.valid_shift(0) <= '0';
        r_in.valid_shift(PIPE_SUM_CORDIC - 1 downto 1) <= r.valid_shift(PIPE_SUM_CORDIC - 2 downto 0);
        r_in.index_shift(0) <= 0;
        r_in.index_shift(1 to PIPE_SUM_CORDIC - 1) <= r.index_shift(0 to PIPE_SUM_CORDIC - 2);

        -- Clip ctrl value to positive only.
        r_in.lfo_velocity_clipped <= x"0000" when config.lfo_velocity < 0 else unsigned(config.lfo_velocity);

        -- Square clipped control value.
        v_lfo_velocity_squared := r.lfo_velocity_clipped * r.lfo_velocity_clipped;
        r_in.lfo_velocity <= v_lfo_velocity_squared(2 * CTRL_SIZE - 2 downto CTRL_SIZE - 1);

        -- Detect edge of voice enable to use as sync pulse.
        for i in 0 to N_OUTPUTS - 1 loop 
            r_in.osc_enable(i) <= osc_inputs(i).enable;
            if config.lfo_trigger = '1' and osc_inputs(i).enable = '1' and r.osc_enable(i) = '0' then 
                r_in.sync(i) <= '1';
            end if;
        end loop;

        if r.state = idle and next_sample = '1' then

            -- Load new output samples from buffer.
            r_in.sine_out <= r.sine_buffer;
            r_in.square_out <= r.square_buffer;
            r_in.saw_out <= r.saw_buffer;

            r_in.valid_shift(0) <= '1';
            r_in.read_counter <= 0;
            r_in.state <= running;

        elsif r.state = running then

            -- Pipeline stage 0: multiply LFO velocity control value with constant. 
            r_in.phase_mul <= unsigned(r.lfo_velocity) * LFO_VELOCITY_STEP;

            if r.index_shift(0) < N_OUTPUTS - 1 then
                r_in.valid_shift(0) <= '1';
                r_in.index_shift(0) <= r.index_shift(0) + 1;
            else 
                r_in.state <= idle;
            end if;

        end if;

        -- Pipeline stage 1: add constant to scaled control value.
        if r.valid_shift(PIPE_SUM_ADD - 1) = '1' then 

            r_in.phase_delta <= resize(r.phase_mul + LFO_MIN_VELOCITY, LFO_PHASE_SIZE);
        end if;

        -- Pipeline stage 2: add to phase accumulator.
        if r.valid_shift(PIPE_SUM_ACC - 1) = '1' then 

            r_in.phase_raw <= r.phase(r.index_shift(PIPE_SUM_ACC - 1)) + signed(r.phase_delta);
        end if;

        -- Pipeline stage 3: clip accumulator. Reset phase if a sync pulse is received or the LFO phase is reset.
        if r.valid_shift(PIPE_SUM_CLIP - 1) = '1' then 

            if config.lfo_reset = '1' or r.sync(r.index_shift(PIPE_SUM_CLIP - 1)) = '1' then 

                r_in.sync(r.index_shift(PIPE_SUM_CLIP - 1)) <= '0';
                r_in.phase(r.index_shift(PIPE_SUM_CLIP - 1)) <= (others => '0');

            elsif r.phase_raw >= shift_left(to_signed(1, LFO_PHASE_SIZE), LFO_PHASE_FRAC) then

                r_in.phase(r.index_shift(PIPE_SUM_CLIP - 1)) <= 
                    r.phase_raw - shift_left(to_signed(1, LFO_PHASE_SIZE), LFO_PHASE_FRAC + 1);
            else
                r_in.phase(r.index_shift(PIPE_SUM_CLIP - 1)) <= r.phase_raw;
            end if;
        end if;

        -- Pipeline stage 4: input phase into cordic.
        if r.valid_shift(PIPE_SUM_CORDIC - 1) = '1' then 
            s_phase_tvalid <= '1';
            s_phase_tdata <= std_logic_vector(r.phase(r.index_shift(PIPE_SUM_CORDIC - 1)));
        end if;

        -- Pipeline state 5: read cordic ouput and process.
        -- This pipeline does not use the pipeline shift registers because the cordic delay is quite long.
        if s_dout_tvalid = '1' then

            -- Take sine and cosine sample from the cordic output.
            r_in.sine_buffer(r.read_counter) <= clip_sine(s_dout_tdata(40 downto 24));
            r_in.cosine_buffer(r.read_counter) <= clip_sine(s_dout_tdata(16 downto 0));

            -- Trunctate the phase to get the saw output.
            r_in.saw_buffer(r.read_counter) <=
                r.phase(r.read_counter)(LFO_PHASE_FRAC downto LFO_PHASE_FRAC - CTRL_SIZE + 1);

            -- Generate square output.
            r_in.square_buffer(r.read_counter) <= (CTRL_SIZE - 1 => '0', CTRL_SIZE - 2 downto 0 => '1')
                when r.phase(r.read_counter) >= 0 else (CTRL_SIZE - 1 => '1', CTRL_SIZE - 2 downto 0 => '0');

            if r.read_counter < N_OUTPUTS - 1 then
                r_in.read_counter <= r.read_counter + 1;
            end if;

        end if;

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
