library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wave_array_pkg.all;
use work.midi_pkg.all;


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

    constant TABLE_IDX_MSB : integer := WAVE_RES_LOG2 + WAVE_PREC - 1;
    constant TABLE_IDX_LSB : integer := WAVE_PREC;
    constant PREC_ZEROS    : unsigned(WAVE_PREC - 1 downto 0) := (others => '0');

    -- Used for both addresses and step values. Fixed point 11.16.
    subtype t_table_address is std_logic_vector(TABLE_IDX_MSB downto 0);

    type t_midi_state is (idle, shift_octave);
    type t_sample_state is
        (idle, step_index, fetch_a, fetch_b, interpolate_a, interpolate_b, store, sum);
    type t_table_address_array is array (0 to 11) of t_table_address;

    -- Step values (angular velocity) for notes c9 to b9, the highest octave in midi.
    -- These values are shifted to the right for lower octaves.
    constant BASE_STEP : t_table_address_array := (
        27x"16534C8", -- C9
        27x"17A724E", -- C#9
        27x"190F323", -- D9
        27x"1A8CAB9", -- D#9
        27x"1C20D29", -- E9
        27x"1DCD013", -- F9
        27x"1F92A68", -- F#9
        27x"2173466", -- G9
        27x"237079E", -- G#9
        27x"258BF25", -- A9
        27x"27C780A", -- A#9
        27x"2A250A9"  -- B9
    );

    type t_osc_reg is record
        midi_state              : t_midi_state;
        sample_state            : t_sample_state;
        sample                  : t_mono_sample;
        next_sample             : t_mono_sample;
        table_address           : t_table_address; -- fixed point wave table index
        table_step              : t_table_address; -- fixed point wave table velocity
        octave_shift            : integer range 0 to 10; -- number of shifts from BASE_STEP to current octave
        sample_a                : t_mono_sample;
        sample_b                : t_mono_sample;
        interpolation_buffer_a  : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC - 1 downto 0);
        interpolation_buffer_b  : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC - 1 downto 0);
        mul_z                   : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC - 1 downto 0);
        address_frac_inv        : std_logic_vector(WAVE_PREC - 1 downto 0); -- 1 - table address fraction
    end record;

    constant REG_INIT : t_osc_reg := (
        midi_state              => idle,
        sample_state            => step_index, -- Prefetch one sample.
        sample                  => (others => '0'),
        next_sample             => (others => '0'),
        table_address           => (others => '0'),
        table_step              => (others => '0'),
        octave_shift            => 0,
        sample_a                => (others => '0'),
        sample_b                => (others => '0'),
        interpolation_buffer_a  => (others => '0'),
        interpolation_buffer_b  => (others => '0'),
        mul_z                   => (others => '0'),
        address_frac_inv        => (others => '0')
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
    signal mul_x_s              : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    signal mul_y_s              : std_logic_vector(WAVE_PREC - 1 downto 0);

begin

    -- Wave table ram
    wave_ram : entity work.blockram
    generic map (
        abits       => WAVE_RES_LOG2,
        dbits       => SAMPLE_WIDTH,
        init_file   => "saw.data"
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
    -- multiplier : entity work.mul
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
        variable v_interpolation_sum : std_logic_vector(SAMPLE_WIDTH + WAVE_PREC - 1 downto 0);
    begin

        v_base_step := BASE_STEP(midi_voice.note);

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
        r_in.mul_z  <= std_logic_vector(unsigned(mul_x_s) * unsigned(mul_y_s));

        -- State machine that calculates a new table_step value based on the midi note.
        case (r.midi_state) is

            -- Wait for a midi update.
            when idle =>
                if midi_voice.change = '1' then
                    r_in.midi_state     <= shift_octave;
                    r_in.octave_shift   <= 10 - midi_voice.octave;
                end if;

            -- Shift base step value down to match correct octave.
            when shift_octave =>
                r_in.midi_state <= idle;

                for i in 0 to t_table_address'length - 1 loop
                    if i < WAVE_RES_LOG2 - r.octave_shift - 1 then
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
                if next_sample = '1' then
                    r_in.sample_state           <= step_index;
                    r_in.sample                 <= r.next_sample;
                    r_in.interpolation_buffer_a <= (others => '0');
                    r_in.interpolation_buffer_b <= (others => '0');
                end if;

            -- Increment the table address.
            when step_index =>
                r_in.sample_state   <= fetch_a;
                r_in.table_address  <= std_logic_vector(
                    unsigned(r.table_address) + unsigned(r.table_step));

            -- Fetch the floor of the table address.
            when fetch_a =>
                r_in.sample_state       <= fetch_b;
                ren_s                   <= '1';
                raddr_s                 <= r.table_address(TABLE_IDX_MSB downto TABLE_IDX_LSB);

                -- Pre  calculate 1 - table index fraction.
                r_in.address_frac_inv   <= std_logic_vector(PREC_ZEROS
                    - unsigned(r.table_address(WAVE_PREC-1 downto 0)));

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
                mul_y_s             <= r.address_frac_inv;

            -- Multiply second part of interpolation.
            when interpolate_b =>
                r_in.sample_state           <= store;
                r_in.interpolation_buffer_a <= r.mul_z;
                mul_x_s                     <= r.sample_b;
                mul_y_s                     <= r.table_address(WAVE_PREC-1 downto 0);

            when store =>
                r_in.sample_state           <= sum;
                r_in.interpolation_buffer_b <= r.mul_z;

            -- Sum the two interpolation parts.
            when sum =>
                r_in.sample_state           <= idle;

                v_interpolation_sum := std_logic_vector(
                    unsigned(r.interpolation_buffer_a) + unsigned(r.interpolation_buffer_b));

                -- Round to integer
                r_in.next_sample    <=
                    v_interpolation_sum(SAMPLE_WIDTH + WAVE_PREC - 1 downto WAVE_PREC);

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
