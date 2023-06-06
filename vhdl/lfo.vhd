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
        sine_out                : out t_ctrl_value_array(0 to N_OUTPUTS - 1);
        square_out              : out t_ctrl_value_array(0 to N_OUTPUTS - 1);
        saw_out                 : out t_ctrl_value_array(0 to N_OUTPUTS - 1)
    );
end entity;

architecture arch of lfo is

    type t_lfo_phase_array is array (0 to N_OUTPUTS - 1) of signed(LFO_PHASE_SIZE - 1 downto 0);

    type t_mixer_reg is record
        lfo_velocity            : unsigned(CTRL_SIZE - 1 downto 0);
        phase                   : t_lfo_phase_array;
        sine_out                : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        square_out              : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        saw_out                 : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        sine_buffer             : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        cosine_buffer           : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        square_buffer           : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        saw_buffer              : t_ctrl_value_array(0 to N_OUTPUTS - 1);
        write_counter           : integer range 0 to N_OUTPUTS;
        read_counter            : integer range 0 to N_OUTPUTS;
    end record;

    constant REG_INIT : t_mixer_reg := (
        -- -- Initialize phase to -1 in 3.45 format.
        -- phase                   => (others => (LFO_PHASE_SIZE - 1 downto LFO_PHASE_FRAC => '1',
        --                                        LFO_PHASE_FRAC - 1 downto 0 => '0')),
        lfo_velocity            => (others => '0'),
        phase                   => (others => (others => '0')),
        sine_out                => (others => (others => '0')),
        square_out              => (others => (others => '0')),
        saw_out                 => (others => (others => '0')),
        sine_buffer             => (others => (others => '0')),
        cosine_buffer           => (others => (others => '0')),
        square_buffer           => (others => (others => '0')),
        saw_buffer              => (others => (others => '0')),
        write_counter           => N_OUTPUTS,
        read_counter            => N_OUTPUTS
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

    signal s_phase_trunc        : signed(CTRL_SIZE - 1 downto 0);
    signal s_phase_offset       : signed(CTRL_SIZE - 1 downto 0);

begin

    cordic : entity xil_defaultlib.cordic_lfo_sine
    port map (
        aclk                    => clk,
        s_axis_phase_tvalid     => s_phase_tvalid,
        s_axis_phase_tdata      => s_phase_tdata,
        m_axis_dout_tvalid      => s_dout_tvalid,
        m_axis_dout_tdata       => s_dout_tdata
    );

    -- Connect output registers.
    sine_out <= r.sine_out;
    square_out <= r.square_out;
    saw_out <= r.saw_out;

    combinatorial : process (r, next_sample, config, s_dout_tvalid, s_dout_tdata)
        variable v_phase_mul    : unsigned(CTRL_SIZE + LFO_PHASE_SIZE - 1 downto 0);
        variable v_phase_delta  : unsigned(LFO_PHASE_SIZE - 1 downto 0);
        variable v_phase_raw    : signed(LFO_PHASE_SIZE - 1 downto 0);
    begin

        r_in <= r;
        s_phase_tvalid <= '0';
        s_phase_tdata <= (others => '0');

        -- Clip ctrl value to positive only.
        r_in.lfo_velocity <= unsigned(maximum(x"0000", config.lfo_velocity));

        if next_sample = '1' then

            -- Load new output samples from buffer.
            r_in.sine_out <= r.sine_buffer;
            r_in.square_out <= r.square_buffer;
            r_in.saw_out <= r.saw_buffer;

            -- Increment phase.
            for i in 0 to N_OUTPUTS - 1 loop

                -- Calculate the phase increase.
                v_phase_mul := unsigned(r.lfo_velocity) * LFO_VELOCITY_STEP;
                v_phase_delta := LFO_MIN_VELOCITY + v_phase_mul(LFO_PHASE_SIZE - 1 downto 0);
                v_phase_raw := r.phase(i) + signed(v_phase_delta);

                -- Check for overflow in the fixed point phase value.
                if v_phase_raw >= shift_left(to_signed(1, LFO_PHASE_SIZE), LFO_PHASE_FRAC) then
                    r_in.phase(i) <= v_phase_raw - shift_left(
                        to_signed(1, LFO_PHASE_SIZE), LFO_PHASE_FRAC + 1);
                else
                    r_in.phase(i) <= v_phase_raw;
                end if;
            end loop;

            r_in.write_counter <= 0;
            r_in.read_counter <= 0;

        end if;

        if r.write_counter < N_OUTPUTS then
            s_phase_tvalid <= '1';

            -- Add 1 to the phase accumulator to start the sine and cosine at 0 phase.
            s_phase_tdata <= std_logic_vector(r.phase(r.write_counter));
            r_in.write_counter <= r.write_counter + 1;
        end if;

        -- Generate new samples.
        if r.read_counter < N_OUTPUTS and s_dout_tvalid = '1' then

            -- Take sine and cosine sample from the cordic output.
            r_in.sine_buffer(r.read_counter) <= clip_sine(s_dout_tdata(40 downto 24));
            r_in.cosine_buffer(r.read_counter) <= clip_sine(s_dout_tdata(16 downto 0));

            -- Trunctate the phase to get the saw output.
            r_in.saw_buffer(r.read_counter) <=
                r.phase(r.read_counter)(LFO_PHASE_FRAC downto LFO_PHASE_FRAC - CTRL_SIZE + 1);

            -- Generate square output.
            r_in.square_buffer(r.read_counter) <= (CTRL_SIZE - 1 => '0', CTRL_SIZE - 2 downto 0 => '1')
                when r.phase(r.read_counter) >= 0 else (CTRL_SIZE - 1 => '1', CTRL_SIZE - 2 downto 0 => '0');

            r_in.read_counter <= r.read_counter + 1;

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
