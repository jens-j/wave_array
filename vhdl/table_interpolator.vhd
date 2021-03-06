library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;


-- This entity performs interpolation on samples from the mipmap table.
-- The mipmap table addresses used are generated by an external entity.
-- Interpolation is performed using a polyphase filter implemented as a pipeline consisting of
-- 3 DSP slices that needs to be executed POLY_N times for each output sample. In the first stage,
-- 2 slices perform linear interpolation between samples from two different frames of the wavetable,
-- and on the polyphase filter coefficients. In the second stage a single slice implements a
-- multiply accumulate operation to sum the partial products of the polyphase filter. This process
-- is run twice for every oscillator to generate two samples for the downsampling stage.
entity table_interpolator is
    generic (
        N_OSCILLATORS           : positive
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample trigger.
        frame_0_index           : in  integer range 0 to 3; -- Frame x buffer index.
        frame_1_index           : in  integer range 0 to 3; -- Frame x+1 buffer index.
        osc_inputs              : in  t_osc_input_array(0 to N_OSCILLATORS - 1);
        addrgen_input           : in  t_addrgen_to_tableinterp_array(0 to N_OSCILLATORS - 1);
        output_samples          : out t_stereo_sample_array(0 to N_OSCILLATORS - 1); -- Two samples are needed for the downsampling.
        overflow                : out std_logic; -- Flag numeric overflow.
        timeout                 : out std_logic -- Flag that the oscillator could not keep up.
    );
end entity;

architecture arch of table_interpolator is

    -- Pipeline stage lengths.
    constant PIPE_LEN_MEM       : integer := 1; -- Sample & coefficient memory access.
    constant PIPE_LEN_INTP      : integer := 4; -- Sample & coefficient linear interpolation.
    constant PIPE_LEN_MACC      : integer := 4; -- Polyphase filter multiply-accumulate.
    constant PIPE_LEN_TOTAL     : integer := PIPE_LEN_MEM + PIPE_LEN_INTP + PIPE_LEN_MACC; -- Total pipeline length.

    -- Cumulative pipeline lengths.
    constant PIPE_SUM_INTP      : integer := PIPE_LEN_MEM + PIPE_LEN_INTP;


    type t_state is (idle, init, running);
    type t_counter_array is array (0 to PIPE_LEN_TOTAL) of integer range 0 to N_OSCILLATORS - 1; -- One extra register to use in the writeback stage which is not really part of the pipeline.
    type t_sample_counter_array is array (0 to PIPE_LEN_TOTAL) of integer range 0 to 2;

    type t_oscillator_reg is record
        state                   : t_state;
        frame_0_index           : integer range 0 to 3; -- Frame x buffer index.
        frame_1_index           : integer range 0 to 3; -- Frame x+1 buffer index.
        coeff_counter           : integer range 0 to POLY_N - 1; -- Count coeffients/input samples (inner loop).
        osc_counter_next        : integer range 0 to N_OSCILLATORS; -- The value of the next oscillator (osc_counter + 1).
        sample_counter_next     : integer range 0 to 2;
        output_samples          : t_stereo_sample_array(0 to N_OSCILLATORS - 1);
        sample_buffers          : t_stereo_sample_array(0 to N_OSCILLATORS - 1);
        mipmap_address          : t_mipmap_address; -- Increment to get successive input samples.
        coeff_base_address      : unsigned(POLY_M_LOG2 - 2 downto 0); -- Concatenated with coeff_counter gives the coeff memory address.

        -- Writeback pipeline registers (9 cycles).
        sample_counter          : t_sample_counter_array;  -- Count the two output samples plus one for pipeline winddown.
        osc_counter             : t_counter_array; -- Count oscillators (outer loop). Registered PIPE_LEN_TOTAL times to be used for writeback.
        writeback               : std_logic_vector(PIPE_LEN_TOTAL downto 0);

        -- Interpolation pipeline regiisters (2 cycles).
        frame_position          : t_osc_position_array(0 to PIPE_LEN_MEM); -- Interpolation coefficient for sample interpolation.
        odd_phase               : std_logic_vector(PIPE_LEN_MEM downto 0); -- '1' when m is odd (changes coefficient memory access).
        phase_position          : t_osc_phase_position_array(0 to PIPE_LEN_MEM); -- Interpolation coefficient for phase interpolation.

        zero_coeff              : std_logic_vector(PIPE_SUM_INTP downto 0);

        -- Sticky error bits.
        overflow                : std_logic;
        timeout                 : std_logic;
    end record;

    constant REG_INIT : t_oscillator_reg := (
        state                   => idle,
        frame_0_index           => 0,
        frame_1_index           => 1,
        coeff_counter           => 0,
        osc_counter_next        => 0,
        sample_counter_next     => 0,
        output_samples          => (others => (others => (others => '0'))),
        sample_buffers  	    => (others => (others => (others => '0'))),
        mipmap_address          => (others => '0'),
        coeff_base_address      => (others => '0'),

        sample_counter          => (others => 0),
        osc_counter             => (others => 0),
        writeback               => (others => '0'),
        frame_position          => (others => (others => '0')),
        odd_phase               => (others => '0'),
        phase_position          => (others => (others => '0')),

        zero_coeff              => (others => '0'),

        overflow                => '0',
        timeout                 => '0'
    );

    signal r, r_in : t_oscillator_reg := REG_INIT;

    -- Frame interpolation signals ((a - d) * b + c = p).
    signal s_frame_interp_a     : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_frame_interp_b     : std_logic_vector(OSC_SAMPLE_FRAC - 1 downto 0);
    signal s_frame_interp_c     : std_logic_vector(SAMPLE_SIZE + OSC_SAMPLE_FRAC - 1 downto 0); -- 16.8 fixed point.
    signal s_frame_interp_d     : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_frame_interp_p     : std_logic_vector(SAMPLE_SIZE + 1 downto 0); -- Output is only the integer part + two overflow bits

    -- Coefficient interpolation signals ([a - d] * b + c = p).
    signal s_coeff_interp_a     : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_coeff_interp_b     : std_logic_vector(OSC_COEFF_FRAC - 1 downto 0);
    signal s_coeff_interp_c     : std_logic_vector(POLY_COEFF_SIZE + OSC_COEFF_FRAC - 1 downto 0); -- 16.8 fixed point.
    signal s_coeff_interp_d     : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_coeff_interp_p     : std_logic_vector(POLY_COEFF_SIZE + 1 downto 0); -- Output is only the integer part + two overflow bits

    -- Polyphase filter macc signals (a * b [+ p] = p).
    signal s_macc_sel           : std_logic_vector(0 downto 0); -- 0: macc, 1: mul.
    signal s_macc_a             : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_macc_b             : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_macc_p             : std_logic_vector(47 downto 0); -- Full width output.

    signal s_wave_mem_wea       : std_logic_vector(0 downto 0);
    signal s_wave_mem_addra     : std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 0);
    signal s_wave_mem_dina      : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_wave_mem_addrb     : std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 - 1 downto 0);
    signal s_wave_mem_doutb     : std_logic_vector(4 * SAMPLE_SIZE - 1 downto 0);

    signal s_coeff_even_addra   : std_logic_vector(POLY_N_LOG2 + POLY_M_LOG2 - 2 downto 0);
    signal s_coeff_even_douta   : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_coeff_odd_addra    : std_logic_vector(POLY_N_LOG2 + POLY_M_LOG2 - 2 downto 0);
    signal s_coeff_odd_douta    : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);

begin

    wave_mem : entity wave.osc_wave_memory
    generic map (
        init_file               => "osc_wave_memory.coe"
    )
    port map (
        write_clk               => clk,
        write_enable            => s_wave_mem_wea,
        write_address           => s_wave_mem_addra,
        write_data              => s_wave_mem_dina,
        read_clk                => clk,
        read_address            => s_wave_mem_addrb,
        read_data               => s_wave_mem_doutb
    );

    -- ROM that holds the filter coefficients for the even phases.
    coeff_mem_even : entity wave.osc_coeff_memory
    generic map (
        init_file               => "osc_coeff_memory_even.coe"
    )
    port map (
        clk                     => clk,
        address                 => s_coeff_even_addra,
        data                    => s_coeff_even_douta
    );

    -- ROM that holds the filter coefficients for the odd phases.
    coeff_mem_odd : entity wave.osc_coeff_memory
    generic map (
        init_file               => "osc_coeff_memory_odd.coe"
    )
    port map (
        clk                     => clk,
        address                 => s_coeff_odd_addra,
        data                    => s_coeff_odd_douta
    );

    -- DSP slice confifgured to perform linear interpolation of two frames (samples).
    -- Implements (A - D) * B + C = P.
    frame_interp: entity xil_defaultlib.osc_interpolation_gen
    port map (
        CLK                     => clk,
        A                       => s_frame_interp_a,
        B                       => s_frame_interp_b,
        C                       => s_frame_interp_c,
        D                       => s_frame_interp_d,
        P                       => s_frame_interp_p
    );

    -- DSP slice confifgured to perform linear interpolation of filter phases (coefficients).
    -- Implements (A - D) * B + C = P.
    coeff_interp: entity xil_defaultlib.osc_interpolation_gen
    port map (
        CLK                     => clk,
        A                       => s_coeff_interp_a,
        B                       => s_coeff_interp_b,
        C                       => s_coeff_interp_c,
        D                       => s_coeff_interp_d,
        P                       => s_coeff_interp_p
    );

    -- DSP slice configured as polyphase filter multiply-accumulate.
    -- sel: 0 -> A * B + P = P
    -- sel: 1 -> A * B = P
    filter_macc: entity xil_defaultlib.osc_macc_gen
    port map (
        CLK                     => clk,
        SEL                     => s_macc_sel,
        A                       => s_macc_a,
        B                       => s_macc_b,
        P                       => s_macc_p
    );

    s_wave_mem_wea <= "0";
    s_wave_mem_dina <= (others => '0');
    s_wave_mem_addra <= (others => '0');

    -- Output connections.
    output_samples <= r.output_samples;
    overflow <= r.overflow;
    timeout <= r.timeout;

    combinatorial : process (r, osc_inputs, addrgen_input, next_sample, frame_0_index, frame_1_index,
                             s_frame_interp_p, s_coeff_interp_p, s_macc_p,
                             s_wave_mem_doutb, s_coeff_even_douta, s_coeff_odd_douta)

        variable v_level : t_mipmap_level;
        variable v_odd_phase_0 : std_logic;
        variable v_frame_interp_a : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
        variable v_frame_interp_c : std_logic_vector(SAMPLE_SIZE + OSC_SAMPLE_FRAC - 1 downto 0);
        variable v_frame_interp_d : std_logic_vector(SAMPLE_SIZE - 1 downto 0);

    begin

        r_in <= r;

        r_in.writeback(0) <= '0';
        r_in.zero_coeff(0) <= '0';

        s_frame_interp_a <= (others => '0');
        s_frame_interp_b <= (others => '0');
        s_frame_interp_c <= (others => '0');
        s_frame_interp_d <= (others => '0');

        s_coeff_interp_a <= (others => '0');
        s_coeff_interp_b <= (others => '0');
        s_coeff_interp_c <= (others => '0');
        s_coeff_interp_d <= (others => '0');

        s_macc_sel <= (others => '0');
        s_macc_a <= (others => '0');
        s_macc_b <= (others => '0');

        s_wave_mem_addrb <= (others => '0');
        s_coeff_odd_addra <= (others => '0');
        s_coeff_even_addra <= (others => '0');

        v_level := addrgen_input(r.osc_counter(0)).mipmap_level;

        if r.sample_counter(0) < 2 then
            v_odd_phase_0 := addrgen_input(
                r.osc_counter(0)).phase(r.sample_counter(0))(OSC_COEFF_FRAC + v_level);
        else
            v_odd_phase_0 := '0';
        end if;

        if r.state = idle then

            if next_sample = '1' then

                -- Flag an error if still busy when the next trigger comes.
                if r.state = idle then
                    r_in.output_samples <= r.sample_buffers;
                else
                    r_in.timeout <= '1';
                end if;

                r_in.sample_counter(0) <= 0;
                r_in.sample_counter_next <= 0;
                r_in.osc_counter(0) <= 0;
                r_in.coeff_counter <= 0;

                -- Wait one cycle for the input data to become valid.
                r_in.state <= init;
            end if;

        -- Start new cycle
        elsif r.state = init then
            r_in.frame_0_index <= frame_0_index;
            r_in.frame_1_index <= frame_1_index;
            r_in.odd_phase(0) <= v_odd_phase_0;
            r_in.phase_position(0) <= addrgen_input(0).phase(0)
                (OSC_COEFF_FRAC + v_level - 1 downto v_level);
            r_in.frame_position(0) <= osc_inputs(0).position;
            r_in.mipmap_address <= addrgen_input(0).mipmap_address(0);
            r_in.coeff_base_address <=
                shift_right(addrgen_input(0).phase(0), addrgen_input(0).mipmap_level)
                    (t_osc_phase_frac'length - 1 downto OSC_COEFF_FRAC + 1);

            r_in.state <= running;

        elsif r.state = running then

            -- Increment mipmap address (wrap around based on mipmap level).
            if r.mipmap_address = MIPMAP_LEVEL_LIMITS(v_level) then
                r_in.mipmap_address <= MIPMAP_LEVEL_OFFSETS(v_level);
            else
                r_in.mipmap_address <= r.mipmap_address + 1;
            end if;

            -- Increment coefficient counter.
            if r.coeff_counter < POLY_N - 1 then
                r_in.coeff_counter <= r.coeff_counter + 1;

                 -- Pre increment the osc_counter and sample_counter because they are needed for indexing in the next cycle.
                if r.coeff_counter = POLY_N - 2 then

                    if r.osc_counter(0) < N_OSCILLATORS - 1 then
                        r_in.osc_counter_next <= r.osc_counter(0) + 1;
                    else
                        r_in.osc_counter_next <= 0;

                       if r.coeff_counter = POLY_N - 2 and r.sample_counter(0) < 2 then
                           r_in.sample_counter_next <= r.sample_counter(0) + 1;
                       end if;
                    end if;

                    if r.sample_counter(0) < 2 then
                        r_in.writeback(0) <= '1';
                    end if;
                end if;
            else
                r_in.coeff_counter <= 0;

                -- Check for end of sample cycle.
                if r.osc_counter(0) = N_OSCILLATORS - 1 then
                    r_in.sample_counter(0) <= r.sample_counter_next;
                end if;

                r_in.osc_counter(0) <= r.osc_counter_next;

                -- Load sample and coeffient base addresses for next oscillator.
                if r.sample_counter_next < 2 then

                    r_in.mipmap_address <=
                        addrgen_input(r.osc_counter_next).mipmap_address(r.sample_counter_next);

                    r_in.coeff_base_address <= shift_right(
                        addrgen_input(r.osc_counter_next).phase(r.sample_counter_next),
                        addrgen_input(r.osc_counter_next).mipmap_level)
                            (t_osc_phase_frac'length - 1 downto OSC_COEFF_FRAC + 1);
                end if;
            end if;

            -- Check for end of pipeline
            if (r.sample_counter(0) = 2) and (r.coeff_counter = PIPE_LEN_TOTAL) then
                r_in.state <= idle;
            end if;

            -- Pipeline stage 0: Pipeline register inputs.
            if r.sample_counter(0) < 2 then
                r_in.frame_position(0) <= osc_inputs(r.osc_counter(0)).position;
                r_in.odd_phase(0) <= v_odd_phase_0;
                r_in.phase_position(0) <=
                    addrgen_input(r.osc_counter(0)).phase(r.sample_counter(0))
                        (OSC_COEFF_FRAC + v_level - 1 downto v_level);
            end if;

            -- Pipeline stage 0: Wave memory access.
            s_wave_mem_addrb <= std_logic_vector(r.mipmap_address);

            -- Pipeline stage 0: Coefficient memory access.
            -- Get coefficient for phase m and m+1 from the two coefficient memories.
            s_coeff_odd_addra <= std_logic_vector(r.coeff_base_address)
                & std_logic_vector(to_unsigned(r.coeff_counter, POLY_N_LOG2));

            if v_odd_phase_0 = '1' then

                -- Edge case where interpolation wraps around.
                -- Solve by shifting the coefficient forward one position and append with a zero.
                -- but since the coefficients are stored in reversed order. zero the first coeff
                -- and shift the rest back one position.
                if r.coeff_base_address = POLY_M / 2 - 1 then

                    -- if r.coeff_counter < POLY_N - 1 then
                    --     s_coeff_even_addra <= std_logic_vector(r.coeff_base_address + 1)
                    --         & std_logic_vector(to_unsigned(r.coeff_counter, POLY_N_LOG2) + 1);
                    -- else
                    --     r_in.zero_coeff(0) <= '1';
                    -- end if;

                    if r.coeff_counter = 0 then
                        r_in.zero_coeff(0) <= '1';
                    else
                        s_coeff_even_addra <= std_logic_vector(r.coeff_base_address + 1)
                            & std_logic_vector(to_unsigned(r.coeff_counter, POLY_N_LOG2) - 1);
                    end if;

                else
                    s_coeff_even_addra <= std_logic_vector(r.coeff_base_address + 1)
                        & std_logic_vector(to_unsigned(r.coeff_counter, POLY_N_LOG2));
                end if;
            else
                s_coeff_even_addra <= std_logic_vector(r.coeff_base_address)
                    & std_logic_vector(to_unsigned(r.coeff_counter, POLY_N_LOG2));
            end if;

            -- with v_odd_phase_0 select s_coeff_even_addra <=
            --     std_logic_vector(r.coeff_base_address)
            --         & std_logic_vector(to_unsigned(r.coeff_counter, POLY_N_LOG2)) when '0',
            --     std_logic_vector(r.coeff_base_address + 1)
            --         & std_logic_vector(to_unsigned(r.coeff_counter, POLY_N_LOG2)) when others;

            -- Pipeline stage 0 shift pipeline registers.
            for i in PIPE_LEN_MEM downto 1 loop
                r_in.frame_position(i) <= r.frame_position(i - 1);
                r_in.phase_position(i) <= r.phase_position(i - 1);
                r_in.odd_phase(i) <= r.odd_phase(i - 1);
            end loop;

            -- Pipeline stage 1: Read wave memory (mux by active buffer indices) and send to frame
            -- interpolator. Interpolation is performed in a single DSP slice (4 stage pipeline).
            -- (A - D) * B + C = (sampleB - sampleA) * frac(position) + sampleA.
            -- The input samples are also shifted right by one bit to leave some headroom to
            -- aavoid overflow in the filter.
            v_frame_interp_a := s_wave_mem_doutb((r.frame_1_index + 1) * SAMPLE_SIZE - 1
                                    downto r.frame_1_index * SAMPLE_SIZE);

            v_frame_interp_c := s_wave_mem_doutb((r.frame_0_index + 1) * SAMPLE_SIZE - 1
                                    downto r.frame_0_index * SAMPLE_SIZE)
                                    & (0 to OSC_SAMPLE_FRAC - 1 => '0');

            v_frame_interp_d := s_wave_mem_doutb((r.frame_0_index + 1) * SAMPLE_SIZE - 1
                                    downto r.frame_0_index * SAMPLE_SIZE);

            s_frame_interp_b <= std_logic_vector(r.frame_position(PIPE_LEN_MEM - 1));

            s_frame_interp_a <= v_frame_interp_a(SAMPLE_SIZE - 1)
                & v_frame_interp_a(SAMPLE_SIZE - 1 downto 1);

            s_frame_interp_c <= v_frame_interp_c(SAMPLE_SIZE + OSC_SAMPLE_FRAC - 1)
                & v_frame_interp_c(SAMPLE_SIZE + OSC_SAMPLE_FRAC - 1 downto 1);

            s_frame_interp_d <= v_frame_interp_d(SAMPLE_SIZE - 1)
                & v_frame_interp_d(SAMPLE_SIZE - 1 downto 1);

            -- Pipeline stage 1: Read coefficient memory and send to interpolator. The values for the
            -- even and odd coefficient memories are swapped if the phase m is odd.
            if r.odd_phase(PIPE_LEN_MEM) then
                s_coeff_interp_a <= s_coeff_even_douta;
                s_coeff_interp_c <= s_coeff_odd_douta & (0 to OSC_COEFF_FRAC - 1 => '0');
                s_coeff_interp_d <= s_coeff_odd_douta;
            else
                s_coeff_interp_a <= s_coeff_odd_douta;
                s_coeff_interp_c <= s_coeff_even_douta & (0 to OSC_COEFF_FRAC - 1 => '0');
                s_coeff_interp_d <= s_coeff_even_douta;
            end if;

            s_coeff_interp_b <= std_logic_vector(r.phase_position(PIPE_LEN_MEM - 1));

            -- Pipeline stage 5: Connect linear interpolator outputs to the MACC.
            if r.zero_coeff(PIPE_SUM_INTP) = '0' then
                s_macc_b <= s_coeff_interp_p(POLY_COEFF_SIZE - 1 downto 0);
            end if;
            s_macc_a <= s_frame_interp_p(SAMPLE_SIZE - 1 downto 0);
            s_macc_sel <= "1" when r.coeff_counter = PIPE_SUM_INTP else "0";

            -- Pipeline stage 0-5: zero coefficient pipeline registers.
            for i in PIPE_SUM_INTP downto 1 loop
                r_in.zero_coeff(i) <= r.zero_coeff(i - 1);
            end loop;

            -- Pipeline stage 0-7: Register writeback parameters.
            for i in PIPE_LEN_TOTAL downto 1 loop
                r_in.osc_counter(i) <= r.osc_counter(i - 1);
                r_in.sample_counter(i) <= r.sample_counter(i - 1);
                r_in.writeback(i) <= r.writeback(i - 1);
            end loop;

            -- Pipeline stage 9: Store output sample (store zero if oscillator is disabled).
            if r.writeback(PIPE_LEN_TOTAL) then
                if addrgen_input(r.osc_counter(PIPE_LEN_TOTAL)).enable = '1' then
                    r_in.sample_buffers(r.osc_counter(PIPE_LEN_TOTAL))
                        (r.sample_counter(PIPE_LEN_TOTAL)) <= t_mono_sample(
                            s_macc_p(SAMPLE_SIZE + POLY_COEFF_SIZE - 2 downto POLY_COEFF_SIZE - 1)); -- Shift by 15 because signed.
                else
                    r_in.sample_buffers(r.osc_counter(PIPE_LEN_TOTAL))
                        (r.sample_counter(PIPE_LEN_TOTAL)) <= (others => '0');
                end if;
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
