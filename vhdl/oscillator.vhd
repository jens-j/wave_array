library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;


entity oscillator is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        midi_voice              : in  t_midi_voice;
        next_sample             : in  std_logic;
        sample                  : out t_mono_sample
    );
end entity;

architecture arch of oscillator is

    constant TABLE_IDX_MSB  : integer := WAVE_RES_LOG2 + WAVE_PREC - 1;
    constant TABLE_IDX_LSB  : integer := WAVE_PREC;
    constant TABLE_IDX_SIZE : integer := 2**(WAVE_RES_LOG2 + WAVE_PREC);
    constant PREC_ZEROS     : unsigned(WAVE_PREC - 1 downto 0) := (others => '0');

    -- Used for both addresses and step values. Fixed point 11.16.
    subtype t_table_address is std_logic_vector(TABLE_IDX_MSB downto 0);

    type t_midi_state is (idle, shift_octave);
    type t_sample_state is (idle, fetch_a, fetch_b, interpolate_a, interpolate_b,
        store, sum, scale, finalize);
    type t_table_address_array is array (0 to 11) of t_table_address;
    type t_scale_array is array (0 to 11) of real;

    -- Frequencies of the 9th octave (starting at C)
    constant OCT9_FREQS : t_scale_array := (
        8372.16,  -- C
        8869.76,  -- C#
        9397.12,  -- D
        9956.16,  -- D#
        10548.16, -- E
        11175.36, -- F
        11839.68, -- F#
        12544.00, -- G
        13289.60, -- G#
        14080.00, -- A
        14917.12, -- A#
        15804.16  -- B
    );

    function generate_base_step_array return t_table_address_array is
        -- variable v_real : real;
        -- variable v_integer : integer;
        -- variable v_unsigned : unsigned(t_table_address'length - 1 downto 0);
        variable v_base_step_array : t_table_address_array;
    begin
        for i in 0 to 11  loop
            -- v_real := real(TABLE_IDX_MAX) / (real(SAMPLE_RATE) * OCT9_FREQS(i));
            -- v_integer := integer(v_real);
            -- v_unsigned := to_unsigned(v_integer, t_table_address'length);
            -- v_base_step_array(i) := std_logic_vector(v_unsigned);

            v_base_step_array(i) :=
                std_logic_vector(
                    to_unsigned(
                        integer(real(TABLE_IDX_SIZE) * OCT9_FREQS(i) / real(SAMPLE_RATE)),
                        t_table_address'length
                    )
                );
        end loop;

        return v_base_step_array;
    end function;

    -- Step values (angular velocity) for notes c9 to b9, the highest octave in midi.
    -- These values are shifted to the right for lower octaves.
    constant BASE_STEP : t_table_address_array := generate_base_step_array;

    type t_osc_reg is record
        midi_state              : t_midi_state;
        midi_voice              : t_midi_voice;
        sample_state            : t_sample_state;
        sample                  : t_mono_sample;
        sample_buffer           : t_mono_sample;
        table_address           : t_table_address; -- fixed point wave table index
        table_step              : t_table_address; -- fixed point wave table velocity
        octave_shift            : integer range 0 to 10; -- number of shifts from BASE_STEP to current octave
        sample_a                : t_mono_sample;
        sample_b                : t_mono_sample;
        interpolation_buffer_a  : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC downto 0);
        interpolation_buffer_b  : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC downto 0);
        mul_z                   : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC downto 0);
        address_frac_inv        : std_logic_vector(WAVE_PREC - 1 downto 0); -- 1 - table address fraction
        offset_velocity         : std_logic_vector(7 downto 0); -- offset midi velocity range to [1 - 128] to allow easy normalization
    end record;

    constant REG_INIT : t_osc_reg := (
        midi_state              => idle,
        midi_voice              => MIDI_VOICE_INIT,
        sample_state            => idle,
        sample                  => (others => '0'),
        sample_buffer           => (others => '0'),
        table_address           => (others => '0'),
        table_step              => (others => '0'),
        octave_shift            => 0,
        sample_a                => (others => '0'),
        sample_b                => (others => '0'),
        interpolation_buffer_a  => (others => '0'),
        interpolation_buffer_b  => (others => '0'),
        mul_z                   => (others => '0'),
        address_frac_inv        => (others => '0'),
        offset_velocity         => (others => '0')
    );

    -- Register.
    signal r, r_in              : t_osc_reg;

    -- Blockram signals.
    signal ren_s                : std_logic;
    signal raddr_s              : std_logic_vector(WAVE_RES_LOG2-1 downto 0);
    signal rdata_s              : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal wen_s                : std_logic;
    signal waddr_s              : std_logic_vector(WAVE_RES_LOG2-1 downto 0);
    signal wdata_s              : std_logic_vector(SAMPLE_WIDTH-1 downto 0);

    -- Multipler signals.
    signal mul_x_s              : std_logic_vector(SAMPLE_WIDTH - 1 downto 0); -- Sample input.
    signal mul_y_s              : std_logic_vector(WAVE_PREC downto 0); -- Table address fraction input. Add one bit for 2's comp encoding.

begin

    -- Wave table ram
    wave_ram : entity wave.blockram
    generic map (
        abits       => WAVE_RES_LOG2,
        dbits       => SAMPLE_WIDTH,
        init_file   => "sine.data"
    )
    port map(
        rclk        => clk,
        wclk        => clk,
        ren         => ren_s,
        raddr       => raddr_s,
        rdata       => rdata_s,
        wen         => wen_s,
        waddr       => waddr_s,
        wdata       => wdata_s
    );

    -- -- Multiplier used for interpolation
    -- multiplier : entity wave.mul
    -- generic map (
    --     size_x      => SAMPLE_WIDTH,
    --     size_y      => WAVE_PREC
    -- )
    -- port map (
    --     clk         => clk,
    --     x           => mul_x_s,
    --     y           => mul_y_s,
    --     z           => mul_z_s
    -- );

    combinatorial : process (r, midi_voice, next_sample, rdata_s, mul_x_s, mul_y_s)
        variable v_table_index_int : integer;
        variable v_base_step : t_table_address;
        variable v_interpolation_sum : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC downto 0);
    begin

        v_base_step := BASE_STEP(midi_voice.note.key);

        v_table_index_int :=
            to_integer(unsigned(r.table_address(TABLE_IDX_MSB downto TABLE_IDX_LSB)));

        -- Default register input.
        r_in        <= r;

        -- Default RAM inputs.
        ren_s       <= '0';
        raddr_s     <= (others => '0');
        wen_s       <= '0';
        waddr_s     <= (others => '0');
        wdata_s     <= (others => '0');

        -- Default multiplier inputs.
        mul_x_s     <= (others => '0');
        mul_y_s     <= (others => '0');

        -- Outputs.
        sample      <= r.sample;

        -- Instantiate multiplier.
        r_in.mul_z  <= std_logic_vector(signed(mul_x_s) * signed(mul_y_s));
        r_in.midi_voice <= midi_voice;

        -- State machine that calculates a new table_step value based on the midi note.
        case (r.midi_state) is

            -- Wait for a midi update.
            when idle =>
                if r.midi_voice.change = '1' then
                    r_in.midi_state     <= shift_octave;
                    r_in.octave_shift   <= 10 - r.midi_voice.note.octave;
                end if;

            -- Shift base step value down to match correct octave.
            when shift_octave =>
                r_in.midi_state <= idle;

                for i in 0 to t_table_address'length - 1 loop
                    if i < t_table_address'length - r.octave_shift - 1 then
                        r_in.table_step(i) <= v_base_step(i + r.octave_shift);
                    else
                        r_in.table_step(i) <= '0';
                    end if;
                end loop;
        end case;

        -- State machine that generates a new sample when triggered by next_sample.
        case (r.sample_state) is

            -- Wait for a pulse on next_sample.
            when idle =>
                r_in.interpolation_buffer_a <= (others => '0');
                r_in.interpolation_buffer_b <= (others => '0');

                if next_sample = '1' then
                    r_in.sample <= r.sample_buffer;

                    if r.midi_voice.enable = '0' or r.midi_voice.velocity = (0 to 6 => '0') then
                        r_in.sample_state <= idle;
                        r_in.sample_buffer <= (others => '0');
                        r_in.table_address <= (others => '0'); -- Reset phase when voice is disabled.
                    else
                        r_in.sample_state <= fetch_a;

                        -- Update table address.
                        r_in.table_address <= std_logic_vector(
                            unsigned(r.table_address) + unsigned(r.table_step));
                    end if;
                end if;

            -- Fetch the floor of the table address.
            when fetch_a =>
                r_in.sample_state       <= fetch_b;
                ren_s                   <= '1';
                raddr_s                 <= r.table_address(TABLE_IDX_MSB downto TABLE_IDX_LSB);

                -- Pre-calculate 1 - table index fraction.
                r_in.address_frac_inv   <= std_logic_vector(PREC_ZEROS
                    - unsigned(r.table_address(WAVE_PREC-1 downto 0)));

                -- offset midi velocity to [1 - 128] to allow for easy normalization.
                r_in.offset_velocity <= std_logic_vector(
                    resize(unsigned(r.midi_voice.velocity), 8) + 1);

            -- Fetch the ceiling of the table address.
            when fetch_b =>
                r_in.sample_state   <= interpolate_a;
                r_in.sample_a       <= rdata_s;
                ren_s               <= '1';
                raddr_s             <= std_logic_vector(
                    to_unsigned(v_table_index_int + 1, WAVE_RES_LOG2));

            -- Multiply first part of interpolation.
            when interpolate_a =>
                r_in.sample_state   <= interpolate_b;
                r_in.sample_b       <= rdata_s;
                mul_x_s             <= r.sample_a;
                mul_y_s             <= '0' & r.address_frac_inv;

            -- Multiply second part of interpolation.
            when interpolate_b =>
                r_in.sample_state           <= store;
                r_in.interpolation_buffer_a <= r.mul_z;
                mul_x_s                     <= r.sample_b;
                mul_y_s                     <= '0' & r.table_address(WAVE_PREC-1 downto 0);

            when store =>
                r_in.sample_state           <= sum;
                r_in.interpolation_buffer_b <= r.mul_z;

            -- Sum the two interpolation parts.
            when sum =>
                r_in.sample_state <= scale;

                v_interpolation_sum := std_logic_vector(
                    signed(r.interpolation_buffer_a) + signed(r.interpolation_buffer_b));

                -- Round to integer
                r_in.sample_buffer <=
                    v_interpolation_sum(SAMPLE_WIDTH + WAVE_PREC - 1 downto WAVE_PREC);

            -- Apply note enable and velocity.
            when scale =>
                r_in.sample_state <= finalize;
                mul_x_s           <= r.sample_buffer;
                mul_y_s           <= (8 to WAVE_PREC => '0') & r.offset_velocity;

            -- Normalize through dividing by 128
            when finalize =>
                r_in.sample_state  <= idle;
                r_in.sample_buffer <= r.mul_z(SAMPLE_WIDTH - 1 + 7  downto 7);

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
