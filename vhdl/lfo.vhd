library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;


entity lfo is
    generic (
        N_INSTANCES             : natural; -- Number of LFOs this entity implements.
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        lfo_input               : in  t_lfo_input_array(0 to N_INSTANCES - 1);
        next_sample             : in  std_logic;
        osc_inputs              : in  t_osc_input_array(0 to POLYPHONY_MAX - 1);
        lfo_out                 : out t_lfo_out
    );
end entity;

architecture arch of lfo is

    constant PIPE_LEN_MULT      : integer := 1;
    constant PIPE_LEN_ADD       : integer := 1;
    constant PIPE_LEN_ACC       : integer := 1;
    constant PIPE_LEN_PHASE     : integer := 1;
    constant PIPE_LEN_CLIP      : integer := 1;
    constant PIPE_LEN_MUX       : integer := 1;
    constant PIPE_LEN_CORDIC    : integer := 1;
    constant PIPE_LEN_PROCESS   : integer := 21;
    constant PIPE_LEN_SCALE     : integer := 1;
    constant PIPE_LEN_WRITEBACK : integer := 1;

    constant PIPE_SUM_ADD       : integer := PIPE_LEN_MULT + PIPE_LEN_ADD;
    constant PIPE_SUM_ACC       : integer := PIPE_SUM_ADD + PIPE_LEN_ACC;
    constant PIPE_SUM_PHASE     : integer := PIPE_SUM_ACC + PIPE_LEN_PHASE;
    constant PIPE_SUM_CLIP      : integer := PIPE_SUM_PHASE + PIPE_LEN_CLIP;
    constant PIPE_SUM_MUX       : integer := PIPE_SUM_CLIP + PIPE_LEN_MUX;
    constant PIPE_SUM_CORDIC    : integer := PIPE_SUM_MUX + PIPE_LEN_CORDIC;
    constant PIPE_SUM_PROCESS   : integer := PIPE_SUM_CORDIC + PIPE_LEN_PROCESS;
    constant PIPE_SUM_SCALE     : integer := PIPE_SUM_PROCESS + PIPE_LEN_SCALE;
    constant PIPE_SUM_WRITEBACK : integer := PIPE_SUM_SCALE + PIPE_LEN_WRITEBACK;
    

    type t_state is (idle, square_velocity, running);
    type t_lfo_phase_array is array (0 to POLYPHONY_MAX - 1) of signed(LFO_PHASE_SIZE - 1 downto 0);
    type t_lfo_phase_2d_array is array (0 to N_INSTANCES - 1) of t_lfo_phase_array;
    type t_index_shift_array is array (0 to PIPE_SUM_CORDIC - 1) of integer range 0 to POLYPHONY_MAX - 1;
    type t_instance_shift_array is array (0 to PIPE_SUM_CORDIC - 1) of integer range 0 to N_INSTANCES - 1;
    type t_sync is array (0 to N_INSTANCES - 1) of std_logic_vector(POLYPHONY_MAX - 1 downto 0);
    type t_phase_shift_array is array (0 to N_INSTANCES - 1) of signed(CTRL_SIZE + LFO_PHASE_INT - 2 downto 0);

    type t_mixer_reg is record
        state                   : t_state;
        lfo_velocity_squared    : t_ctrl_value;
        lfo_velocity_clipped    : t_ctrl_value_array(0 to N_INSTANCES - 1);
        lfo_out                 : t_lfo_out(0 to N_INSTANCES - 1);
        lfo_buffer              : t_lfo_out(0 to N_INSTANCES - 1);
        raw_buffer              : t_ctrl_value;
        scaled_buffer           : t_ctrl_value;
        scale_buffer            : t_ctrl_value;
        valid_shift             : std_logic_vector(PIPE_SUM_WRITEBACK - 1 downto 0); -- Pipeline valid shift register.
        index_shift             : t_index_shift_array; -- Output index shift register.
        instance_shift          : t_instance_shift_array;
        phase                   : t_lfo_phase_2d_array; -- Separate phases for all LFO instances.
        phase_mul               : unsigned(CTRL_SIZE + 24 downto 0);
        phase_delta             : unsigned(LFO_PHASE_SIZE - 1 downto 0);
        phase_raw               : signed(LFO_PHASE_SIZE - 1 downto 0);
        phase_offset            : signed(LFO_PHASE_SIZE - 1 downto 0);
        sync                    : t_sync;
        osc_enable              : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        instance_wb             : integer range 0 to N_INSTANCES - 1;
        index_wb                : integer range 0 to POLYPHONY_MAX - 1;
        instance_cordic         : integer range 0 to N_INSTANCES - 1;
        index_cordic            : integer range 0 to POLYPHONY_MAX - 1;
        pipeline_done           : std_logic;
        prev_phase_raw          : signed(LFO_PHASE_SIZE - 1 downto 0);
        phase_shift_array       : t_phase_shift_array;
        phase_clipped           : signed(LFO_PHASE_SIZE - 1 downto 0);
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        lfo_velocity_squared    => (others => '0'),
        lfo_velocity_clipped    => (others => (others => '0')),
        lfo_out                 => (others => (others => (others => '0'))),
        lfo_buffer              => (others => (others => (others => '0'))),
        raw_buffer              => (others => '0'),
        scaled_buffer           => (others => '0'),
        scale_buffer            => (others => '0'),
        valid_shift             => (others => '0'),
        index_shift             => (others => 0),
        instance_shift          => (others => 0),
        phase                   => (others => (others => (others => '0'))),
        phase_mul               => (others => '0'),
        phase_delta             => (others => '0'),
        phase_raw               => (others => '0'),
        phase_offset            => (others => '0'),
        sync                    => (others => (others => '0')),
        osc_enable              => (others => '0'),
        instance_wb             => 0,
        index_wb                => 0,
        instance_cordic         => 0,
        index_cordic            => 0,
        pipeline_done           => '0',
        prev_phase_raw          => (others => '0'),
        phase_shift_array       => (others => (others => '0')),
        phase_clipped           => (others => '0')
    );

    -- Clip the cordic output.
    -- The msb is dropped because it is only used for the single highest and lowest values.
    function clip_sine (raw : std_logic_vector(16 downto 0))
        return signed is
    begin
        if signed(raw) >= 17x"08000" then
            return x"7FFF";
        elsif signed(raw) <= 17x"18000" then
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

    combinatorial : process (r, config, status, next_sample, lfo_input, osc_inputs, s_dout_tvalid, s_dout_tdata)
        variable v_lfo_velocity_squared : signed(2 * CTRL_SIZE - 1 downto 0);
        variable v_index_unsigned : unsigned(15 downto 0);
        variable v_amp_mult : signed(2 * CTRL_SIZE - 1 downto 0);
    begin

        r_in <= r;

        -- Default inputs.
        s_phase_tvalid <= '0';
        s_phase_tdata <= (others => '0');

        lfo_out <= r.lfo_out;

        -- Update shift registers.
        r_in.valid_shift(0) <= '0';
        r_in.valid_shift(PIPE_SUM_WRITEBACK - 1 downto 1) <= r.valid_shift(PIPE_SUM_WRITEBACK - 2 downto 0);

        -- Index and instance shift registers are only used at the first part of the pipeline. 
        r_in.index_shift(1 to PIPE_SUM_CORDIC - 1) <= r.index_shift(0 to PIPE_SUM_CORDIC - 2);
        r_in.instance_shift(1 to PIPE_SUM_CORDIC - 1) <= r.instance_shift(0 to PIPE_SUM_CORDIC - 2);

        -- Register and extend phase shift for each LFO instance.
        for i in 0 to N_INSTANCES - 1 loop 
            r_in.phase_shift_array(i) <= resize(config.lfo_input(i).phase_shift, CTRL_SIZE + LFO_PHASE_INT - 1);
        end loop;

        -- Clip ctrl value to positive only.
        for i in 0 to N_INSTANCES - 1 loop
            r_in.lfo_velocity_clipped(i) <= 
                x"0000" when lfo_input(i).velocity < 0 else signed(lfo_input(i).velocity);
        end loop;

        -- Detect edge of voice enable to use as sync pulse.
        for j in 0 to POLYPHONY_MAX - 1 loop 

            r_in.osc_enable(j) <= osc_inputs(j).enable;

            for i in 0 to N_INSTANCES - 1 loop
            
                if lfo_input(i).trigger = '1' and osc_inputs(j).enable = '1' and r.osc_enable(j) = '0' then 
                    r_in.sync(i)(j) <= '1';
                end if;
            end loop;
        end loop;

        if r.state = idle and (next_sample = '1' or r.pipeline_done = '0') then

            if next_sample = '1' then 

                -- Load new output samples from buffer.
                r_in.lfo_out <= r.lfo_buffer;

                r_in.index_shift(0) <= 0;
                r_in.instance_shift(0) <= 0; 
                r_in.instance_wb <= 0;
                r_in.instance_cordic <= 0;
                r_in.pipeline_done <= '0';
            end if;

            r_in.index_wb <= 0;
            r_in.index_cordic <= 0;
            r_in.state <= square_velocity;

        elsif r.state = square_velocity then 

            -- Square clipped control value.
            v_lfo_velocity_squared := 
                r.lfo_velocity_clipped(r.instance_shift(0)) * r.lfo_velocity_clipped(r.instance_shift(0));
                
            r_in.lfo_velocity_squared <= v_lfo_velocity_squared(2 * CTRL_SIZE - 2 downto CTRL_SIZE - 1);
            r_in.valid_shift(0) <= '1';

            r_in.state <= running;


        elsif r.state = running then

            -- Pipeline stage 0: multiply LFO velocity control value with constant. 
            r_in.phase_mul <= unsigned(r.lfo_velocity_squared) * LFO_VELOCITY_STEP;

            if r.index_shift(0) < POLYPHONY_MAX - 1 then
                r_in.valid_shift(0) <= '1';
                r_in.index_shift(0) <= r.index_shift(0) + 1;
            else 
                r_in.state <= idle;
                r_in.index_shift(0) <= 0;

                if r.instance_shift(0) < N_INSTANCES - 1 then 
                    r_in.instance_shift(0) <= r.instance_shift(0) + 1;
                else 
                    r_in.pipeline_done <= '1';
                end if;
            end if;
        end if;

        -- Pipeline stage 1: add constant to scaled control value.
        if r.valid_shift(PIPE_SUM_ADD - 1) = '1' then 

            r_in.phase_delta <= resize(r.phase_mul + LFO_MIN_VELOCITY, LFO_PHASE_SIZE);
        end if;

        -- Pipeline stage 2: add to phase accumulator.
        if r.valid_shift(PIPE_SUM_ACC - 1) = '1' then 

            r_in.phase_raw <= 
                r.phase(r.instance_shift(PIPE_SUM_ACC - 1))(r.index_shift(PIPE_SUM_ACC - 1)) + signed(r.phase_delta);
        end if;

        -- Pipeline stage 3: in binaural mode, overwrite the right channel phase by an offset value of the left channel. 
        r_in.prev_phase_raw <= r.phase_raw;

        v_index_unsigned := to_unsigned(r.index_shift(PIPE_SUM_PHASE - 1), 16);
        if config.binaural_enable = '1' and v_index_unsigned(0) = '1' then 

            r_in.phase_offset <= r.prev_phase_raw 
                + (r.phase_shift_array(r.instance_shift(PIPE_SUM_PHASE - 1)) & (0 to LFO_PHASE_FRAC - CTRL_SIZE => '0'));
                
        else 
            r_in.phase_offset <= r.phase_raw;
        end if;

        -- Pipeline stage 4: clip accumulator. Reset phase if a sync pulse is received or the LFO phase is reset.
        if r.valid_shift(PIPE_SUM_CLIP - 1) = '1' then 

            if lfo_input(r.instance_shift(PIPE_SUM_CLIP - 1)).reset = '1' 
                    or r.sync(r.instance_shift(PIPE_SUM_CLIP - 1))(r.index_shift(PIPE_SUM_CLIP - 1)) = '1' then 

                r_in.sync(r.instance_shift(PIPE_SUM_CLIP - 1))(r.index_shift(PIPE_SUM_CLIP - 1)) <= '0';

                v_index_unsigned := to_unsigned(r.index_shift(PIPE_SUM_CLIP - 1), 16);

                -- Reset to zero of the phase offset if in binaural mode and voice is odd.
                if config.binaural_enable = '1' and v_index_unsigned(0) = '1' then 
                    r_in.phase_clipped <= r.phase_shift_array(r.instance_shift(PIPE_SUM_CLIP - 1)) 
                        & (0 to LFO_PHASE_FRAC - CTRL_SIZE => '0');
                else 
                    r_in.phase_clipped <= (others => '0');
                end if;

            elsif r.phase_offset >= shift_left(to_signed(1, LFO_PHASE_SIZE), LFO_PHASE_FRAC) then
                r_in.phase_clipped <= r.phase_offset - shift_left(to_signed(1, LFO_PHASE_SIZE), LFO_PHASE_FRAC + 1);

            elsif r.phase_offset < shift_left(to_signed(-1, LFO_PHASE_SIZE), LFO_PHASE_FRAC) then
                r_in.phase_clipped <= r.phase_offset + shift_left(to_signed(1, LFO_PHASE_SIZE), LFO_PHASE_FRAC + 1);
            else
                r_in.phase_clipped <= r.phase_offset;
            end if;
        end if;

        -- Pipeline stage 5: mux clipped phase to voice/instance buffer.
        r_in.phase(r.instance_shift(PIPE_SUM_MUX - 1))(r.index_shift(PIPE_SUM_MUX - 1)) <= r.phase_clipped;
        
        -- Pipeline stage 6: input phase into cordic.
        if r.valid_shift(PIPE_SUM_CORDIC - 1) = '1' then 
            s_phase_tvalid <= '1';
            s_phase_tdata <= std_logic_vector(r.phase(r.instance_shift(PIPE_SUM_CORDIC - 1))
                (r.index_shift(PIPE_SUM_CORDIC - 1))(LFO_PHASE_SIZE - 1 downto 0));
        end if;

        -- Pipeline stage 27: read cordic ouput and process.
        if r.valid_shift(PIPE_SUM_PROCESS - 1) = '1' then

            -- Take sine and cosine sample from the cordic output.
            if lfo_input(r.instance_cordic).wave_select = 0 then 

                r_in.raw_buffer <= clip_sine(s_dout_tdata(40 downto 24));

            -- Trunctate the phase to get the saw output.
            elsif lfo_input(r.instance_cordic).wave_select = 1 then 

                r_in.raw_buffer <=
                    r.phase(r.instance_cordic)(r.index_cordic)(LFO_PHASE_FRAC downto LFO_PHASE_FRAC - CTRL_SIZE + 1);

            -- Generate square output.
            else  
                r_in.raw_buffer <= 
                    (CTRL_SIZE - 1 => '0', CTRL_SIZE - 2 downto 0 => '1') when r.phase(r.instance_cordic)(r.index_cordic) >= 0 
                    else (CTRL_SIZE - 1 => '1', CTRL_SIZE - 2 downto 0 => '0');
            end if;

            -- Mux scale value.
            r_in.scale_buffer <= status.mod_destinations(MODD_LFO_0_AMPLITUDE + r.instance_cordic)(r.index_cordic);

            -- Inrement counters
            if r.index_cordic < POLYPHONY_MAX - 1 then
                r_in.index_cordic <= r.index_cordic + 1;
            else 
                r_in.index_cordic <= 0;

                if r.instance_cordic < N_INSTANCES - 1 then 
                    r_in.instance_cordic <= r.instance_cordic + 1;
                end if;
            end if;
        end if;

        -- Pipeline stage 28: scale lfo output with amplitude
        if r.valid_shift(PIPE_SUM_SCALE - 1) = '1' then
            v_amp_mult := r.raw_buffer * r.scale_buffer;
            r_in.scaled_buffer <= v_amp_mult(2 * CTRL_SIZE - 2 downto CTRL_SIZE - 1);
        end if;

        -- Pipeline stage 29: write scaled LFO value to buffer
        if r.valid_shift(PIPE_SUM_WRITEBACK - 1) = '1' then
            r_in.lfo_buffer(r.instance_wb)(r.index_wb) <= r.scaled_buffer;

            -- Inrement counters
            if r.index_wb < POLYPHONY_MAX - 1 then
                r_in.index_wb <= r.index_wb + 1;
            else 
                r_in.index_wb <= 0;

                if r.instance_wb < N_INSTANCES - 1 then 
                    r_in.instance_wb <= r.instance_wb + 1;
                end if;
            end if;
        end if;

    end process;

    reg_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= REG_INIT;
                -- r.state <= idle; 
                -- r.phase <= (others => (others => (others => '0')));
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
