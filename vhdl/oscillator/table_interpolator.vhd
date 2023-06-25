library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;
library osc;


-- This entity performs interpolation on samples from the mipmap table.
-- The mipmap table addresses used are generated by an external entity.
-- Interpolation is performed using a polyphase filter implemented as a pipeline consisting of
-- 3 DSP slices that needs to be executed POLY_N times for each output sample. In the first stage,
-- 2 slices perform linear interpolation between samples from two different frames of the wavetable,
-- and on the polyphase filter coefficients. In the second stage a single slice implements a
-- multiply accumulate operation to sum the partial products of the polyphase filter. This process
-- is run twice for every oscillator to generate two samples for the downsampling stage.
entity table_interpolator is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;

        -- Next sample trigger.
        next_sample             : in  std_logic;

        -- Frame DMA interface.
        dma2table               : in  t_dma2table;
        table2dma               : out t_table2dma;

        osc_inputs              : in  t_osc_input_array(0 to N_VOICES - 1);
        frame_control           : in  t_ctrl_value_array(0 to N_VOICES - 1);
        addrgen_input           : in  t_addrgen2table_array(0 to N_VOICES - 1);
        output_samples          : out t_stereo_sample_array(0 to N_VOICES - 1); -- Two samples are needed for the downsampling.

        -- Debug ports.
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


    type t_state is (idle, init, running, update_table);
    type t_counter_array is array (0 to PIPE_LEN_TOTAL) of integer range 0 to N_VOICES - 1; -- One extra register to use in the writeback stage which is not really part of the pipeline.
    type t_sample_counter_array is array (0 to PIPE_LEN_TOTAL) of integer range 0 to 2;
    type t_frame_index_array is array (0 to N_VOICES - 1) of natural range 0 to FRAMES_MAX_LOG2 - 1;

    type t_oscillator_reg is record
        state                   : t_state;
        coeff_counter           : integer range 0 to POLY_N - 1; -- Count coeffients/input samples (inner loop).
        osc_counter_next        : integer range 0 to N_VOICES; -- The value of the next oscillator (osc_counter + 1).
        sample_counter_next     : integer range 0 to 2;
        output_samples          : t_stereo_sample_array(0 to N_VOICES - 1);
        sample_buffers          : t_stereo_sample_array(0 to N_VOICES - 1);
        mipmap_address          : t_mipmap_address; -- Increment to get successive input samples.
        coeff_base_address      : unsigned(POLY_M_LOG2 - 2 downto 0); -- Concatenated with coeff_counter gives the coeff memory address.
        table2dma               : t_table2dma;

        -- Writeback pipeline registers (9 cycles).
        sample_counter          : t_sample_counter_array;  -- Count the two output samples plus one for pipeline winddown.
        osc_counter             : t_counter_array; -- Count oscillators (outer loop). Registered PIPE_LEN_TOTAL times to be used for writeback.
        writeback               : std_logic_vector(PIPE_LEN_TOTAL downto 0);

        -- Interpolation pipeline registers (2 cycles).
        odd_phase               : std_logic_vector(PIPE_LEN_MEM downto 0); -- '1' when m is odd (changes coefficient memory access).
        phase_position          : t_osc_phase_position_array(0 to PIPE_LEN_MEM); -- Interpolation coefficient for phase interpolation.

        zero_coeff              : std_logic_vector(PIPE_SUM_INTP downto 0);

        -- Sticky error bits.
        overflow                : std_logic;
        timeout                 : std_logic;

    end record;

    constant REG_INIT : t_oscillator_reg := (
        state                   => idle,
        coeff_counter           => 0,
        osc_counter_next        => 0,
        sample_counter_next     => 0,
        output_samples          => (others => (others => (others => '0'))),
        sample_buffers  	    => (others => (others => (others => '0'))),
        mipmap_address          => (others => '0'),
        coeff_base_address      => (others => '0'),
        table2dma               => (ack => '0'),
        sample_counter          => (others => 0),
        osc_counter             => (others => 0),
        writeback               => (others => '0'),
        odd_phase               => (others => '0'),
        phase_position          => (others => (others => '0')),
        zero_coeff              => (others => '0'),
        overflow                => '0',
        timeout                 => '0'
    );

    signal r, r_in : t_oscillator_reg := REG_INIT;

    -- Frame interpolation signals ((a - d) * b + c = p).
    signal s_frame_interp_a     : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_frame_interp_b     : std_logic_vector(OSC_SAMPLE_FRAC downto 0); -- Add '0' msb to make unsigned (1.8 fixed point).
    signal s_frame_interp_c     : std_logic_vector(SAMPLE_SIZE + OSC_SAMPLE_FRAC downto 0); -- 17.8 fixed point.
    signal s_frame_interp_d     : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_frame_interp_p     : std_logic_vector(SAMPLE_SIZE + 1 downto 0); -- Output is only the integer part + two overflow bits

    -- Coefficient interpolation signals ([a - d] * b + c = p).
    signal s_coeff_interp_a     : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_coeff_interp_b     : std_logic_vector(OSC_COEFF_FRAC downto 0);
    signal s_coeff_interp_c     : std_logic_vector(POLY_COEFF_SIZE + OSC_COEFF_FRAC downto 0); -- 17.8 fixed point.
    signal s_coeff_interp_d     : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_coeff_interp_p     : std_logic_vector(POLY_COEFF_SIZE + 1 downto 0); -- Output is only the integer part + two overflow bits

    -- Polyphase filter macc signals (a * b [+ p] = p).
    signal s_macc_sel           : std_logic_vector(0 downto 0); -- 0: macc, 1: mul.
    signal s_macc_a             : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_macc_b             : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_macc_p             : std_logic_vector(47 downto 0); -- Full width output.

    -- Wave array read inteface.
    signal s_wave_address_a     : std_logic_vector(WAVETABLE_SIZE_LOG2 - 1 downto 0);
    signal s_wave_read_data_a   : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_wave_write_data_a  : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_wave_address_b     : std_logic_vector(WAVETABLE_SIZE_LOG2 - 1 downto 0);
    signal s_wave_read_data_b   : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_wave_write_enable_a: std_logic_vector(0 downto 0);

    -- Coefficient memories interface.
    signal s_coeff_even_addra   : std_logic_vector(POLY_N_LOG2 + POLY_M_LOG2 - 2 downto 0);
    signal s_coeff_even_douta   : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_coeff_odd_addra    : std_logic_vector(POLY_N_LOG2 + POLY_M_LOG2 - 2 downto 0);
    signal s_coeff_odd_douta    : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);

begin

    -- wave_mem : entity osc.osc_wave_memory
    -- generic map (
    --     init_file               => GET_INPUT_FILE_PATH & "osc_wave_memory_basic.hex"
    -- )
    -- port map (
    --     clk                     => clk,
    --     address_a               => s_wave_address_a,
    --     address_b               => s_wave_address_b,
    --     read_data_a             => s_wave_read_data_a,
    --     read_data_b             => s_wave_read_data_b,
    --     write_enable_a          => dma2table.write_enable,
    --     write_data_a            => dma2table.write_data
    -- );

    s_wave_write_enable_a(0) <= dma2table.write_enable;

    wave_mem : entity xil_defaultlib.wave_mem_gen
    port map (
        clka                    => clk,
        wea                     => s_wave_write_enable_a, -- 1 bit vector.
        addra                   => s_wave_address_a,
        dina                    => dma2table.write_data,
        douta                   => s_wave_read_data_a,
        clkb                    => clk,
        web                     => "0",
        addrb                   => s_wave_address_b,
        dinb                    => (others => '0'),
        doutb                   => s_wave_read_data_b
    );

    -- ROM that holds the filter coefficients for the even phases.
    coeff_mem_even : entity osc.osc_coeff_memory
    generic map (
        init_file               => GET_INPUT_FILE_PATH & "osc_coeff_memory_even.hex"
    )
    port map (
        clk                     => clk,
        address                 => s_coeff_even_addra,
        data                    => s_coeff_even_douta
    );

    -- ROM that holds the filter coefficients for the odd phases.
    coeff_mem_odd : entity osc.osc_coeff_memory
    generic map (
        init_file               => GET_INPUT_FILE_PATH & "osc_coeff_memory_odd.hex"
    )
    port map (
        clk                     => clk,
        address                 => s_coeff_odd_addra,
        data                    => s_coeff_odd_douta
    );

    -- DSP slice configured to perform linear interpolation of two frames (samples).
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

    -- DSP slice configured to perform linear interpolation of filter phases (coefficients).
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

    -- Output connections.
    output_samples <= r.output_samples;
    overflow <= r.overflow;
    timeout <= r.timeout;
    table2dma <= r.table2dma;

    combinatorial : process (r, osc_inputs, addrgen_input, next_sample, dma2table, frame_control,
                             s_frame_interp_p, s_coeff_interp_p, s_macc_p,
                             s_wave_read_data_a, s_wave_read_data_b, s_coeff_even_douta, s_coeff_odd_douta)

        variable v_level : t_mipmap_level;
        variable v_odd_phase_0 : std_logic;
        variable v_frame_interp_a : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
        variable v_frame_interp_c : std_logic_vector(SAMPLE_SIZE + OSC_SAMPLE_FRAC downto 0);
        variable v_frame_interp_d : std_logic_vector(SAMPLE_SIZE - 1 downto 0);

        variable v_frame_index_a : t_frame_index_array;
        variable v_frame_index_b : t_frame_index_array;
        variable v_frame_position : t_frame_position_array(0 to N_VOICES - 1);
        variable v_control_unsigned : t_ctrl_value;
        variable v_control_index_lsb : natural;

    begin

        r_in <= r;

        r_in.table2dma.ack <= '0';
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

        s_wave_address_a <= (others => '0');
        s_wave_address_b <= (others => '0');
        s_coeff_odd_addra <= (others => '0');
        s_coeff_even_addra <= (others => '0');

        v_level := addrgen_input(r.osc_counter(0)).mipmap_level;

        -- Split control value into frame index and position.
        for i in 0 to N_VOICES - 1 loop

            -- Clip the control value to positive only values.
            v_control_unsigned := x"0000" when frame_control(i) < 0 else frame_control(i);

            -- Calculate frame A and B indices and frame position.
            if dma2table.frames_log2 = 0 then -- Special case: dont do any frame interpolation.
                v_frame_index_a(i) := 0;
                v_frame_index_b(i) := 0;
                v_frame_position(i) := (others => '0');
            
            elsif dma2table.frames_log2 = 1 then -- Special case: always interpolate between frames 0 & 1.
                v_frame_index_a(i) := 0;
                v_frame_index_b(i) := 1;
                
                -- Use MSBs of frame_control as frame_position (msb is always 0)..
                v_frame_position(i) := unsigned(v_control_unsigned(CTRL_SIZE - 2 downto CTRL_SIZE - OSC_SAMPLE_FRAC - 1));

            -- Normal case: The last 1 / frames_log2 part of the control range is effectively clipped. 
            -- This allows the table size to be a power of two.
            else

                -- Pre calculate the lowest bit of the index part of the control value.
                -- Note that since  the control value is signed, bit 14 is the msb.
                v_control_index_lsb := CTRL_SIZE - dma2table.frames_log2 - 1;

                -- Slice frame index A and calculate index B.
                v_frame_index_a(i) := to_integer(unsigned(v_control_unsigned(CTRL_SIZE - 2 downto v_control_index_lsb)));
                v_frame_index_b(i) := minimum(2**dma2table.frames_log2, v_frame_index_a(i) + 1);

                -- Slice frame position.
                v_frame_position(i) := unsigned(
                    v_control_unsigned(v_control_index_lsb - 1 downto v_control_index_lsb - OSC_SAMPLE_FRAC));
            end if;    
                
        end loop;

        if r.sample_counter(0) < 2 then
            v_odd_phase_0 := addrgen_input(r.osc_counter(0)).phase(r.sample_counter(0))(OSC_COEFF_FRAC + v_level);
        else
            v_odd_phase_0 := '0';
        end if;

        if r.state = idle then

            -- Check for table update.
            if dma2table.req = '1' then 
                r_in.table2dma.ack <= '1';
                r_in.state <= update_table;

            -- Wait for next sample pulse.
            elsif next_sample = '1' then

                -- Load new output samples from buffer.
                r_in.output_samples <= r.sample_buffers;

                r_in.sample_counter(0) <= 0;
                r_in.sample_counter_next <= 0;
                r_in.osc_counter(0) <= 0;
                r_in.coeff_counter <= 0;

                -- Wait one cycle for the input data to become valid.
                r_in.state <= init;
            end if;

        -- Start new cycle
        elsif r.state = init then
            r_in.odd_phase(0) <= v_odd_phase_0;
            r_in.phase_position(0) <= addrgen_input(0).phase(0)(OSC_COEFF_FRAC + v_level - 1 downto v_level);
            r_in.mipmap_address <= addrgen_input(0).mipmap_address(0);
            r_in.coeff_base_address <= shift_right(addrgen_input(0).phase(0), addrgen_input(0).mipmap_level)
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

                 -- Pre-increment the osc_counter and sample_counter because they are needed for indexing in the next cycle.
                if r.coeff_counter = POLY_N - 2 then

                    if r.osc_counter(0) < N_VOICES - 1 then
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
                if r.osc_counter(0) = N_VOICES - 1 then
                    r_in.sample_counter(0) <= r.sample_counter_next;
                end if;

                r_in.osc_counter(0) <= r.osc_counter_next;

                -- Load sample and coeffient base addresses for next oscillator.
                if r.sample_counter_next < 2 then

                    r_in.mipmap_address <= addrgen_input(r.osc_counter_next).mipmap_address(r.sample_counter_next);

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
                r_in.odd_phase(0) <= v_odd_phase_0;
                r_in.phase_position(0) <= addrgen_input(r.osc_counter(0)).phase(r.sample_counter(0))
                    (OSC_COEFF_FRAC + v_level - 1 downto v_level);
            end if;

            -- Pipeline stage 0: Wave memory access.
            s_wave_address_a <=  std_logic_vector(to_unsigned(v_frame_index_a(r.osc_counter(0)), FRAMES_MAX_LOG2)) 
                & std_logic_vector(r.mipmap_address);

            s_wave_address_b <=  std_logic_vector(to_unsigned(v_frame_index_b(r.osc_counter(0)), FRAMES_MAX_LOG2)) 
                & std_logic_vector(r.mipmap_address);

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

            -- Pipeline stage 0 shift pipeline registers.
            for i in PIPE_LEN_MEM downto 1 loop
                r_in.phase_position(i) <= r.phase_position(i - 1);
                r_in.odd_phase(i) <= r.odd_phase(i - 1);
            end loop;

            -- Pipeline stage 1: Read wave memory (mux by active buffer indices) and send to frame
            -- interpolator. Interpolation is performed in a single DSP slice (4 stage pipeline).
            -- (D - A) * B + C = (sampleB - sampleA) * frac(position) + sampleA.
            -- The input samples are also shifted right by one bit to leave some headroom to
            -- avoid overflow in the interpolation filter and/or the low pass filter.
            s_frame_interp_a <= std_logic_vector(shift_right(unsigned(s_wave_read_data_a), 1));
            
            s_frame_interp_c <= 
                (1 downto 0 => s_wave_read_data_b(SAMPLE_SIZE - 1)) -- sign extention
                & s_wave_read_data_b                                -- operand
                & (0 to OSC_SAMPLE_FRAC - 2 => '0');              -- shift

            s_frame_interp_d <= std_logic_vector(shift_right(unsigned(s_wave_read_data_b), 1));
            s_frame_interp_b <= '0' & std_logic_vector(v_frame_position(r.osc_counter(1))); -- Add zero msb to make B unsigned.

            -- s_frame_interp_a <= s_wave_read_data_b((r.frame_0_index + 1) * SAMPLE_SIZE - 1
            --                         downto r.frame_0_index * SAMPLE_SIZE);

            -- -- C needs to be sign extended by one bit because of operand B.
            -- -- Also append zeros to align with the multiplication.
            -- s_frame_interp_c <= s_wave_read_data_b((r.frame_0_index + 1) * SAMPLE_SIZE - 1)                        -- sign extention
            --     & s_wave_read_data_b((r.frame_0_index + 1) * SAMPLE_SIZE - 1 downto r.frame_0_index * SAMPLE_SIZE) -- operand
            --     & (0 to OSC_SAMPLE_FRAC - 1 => '0');                                                             -- shift

            -- s_frame_interp_d <= s_wave_read_data_b((r.frame_1_index + 1) * SAMPLE_SIZE - 1
            --                         downto r.frame_1_index * SAMPLE_SIZE);

            -- s_frame_interp_b <= '0' & std_logic_vector(r.frame_position(PIPE_LEN_MEM - 1)); -- Add zero msb to make B unsigned.


            -- Pipeline stage 1: Read coefficient memory and send to interpolator. The values for the
            -- even and odd coefficient memories are swapped if the phase m is odd.
            if r.odd_phase(PIPE_LEN_MEM) = '1' then
                s_coeff_interp_a <= s_coeff_odd_douta;
                s_coeff_interp_d <= s_coeff_even_douta;
                s_coeff_interp_c <= s_coeff_odd_douta(POLY_COEFF_SIZE - 1) -- Sign extend by one bit to make unsigned.
                    & s_coeff_odd_douta & (0 to OSC_COEFF_FRAC - 1 => '0');
            else
                s_coeff_interp_a <= s_coeff_even_douta;
                s_coeff_interp_d <= s_coeff_odd_douta;
                s_coeff_interp_c <= s_coeff_even_douta(POLY_COEFF_SIZE - 1) -- Sign extend by one bit to make unsigned.
                    & s_coeff_even_douta & (0 to OSC_COEFF_FRAC - 1 => '0');
            end if;

            s_coeff_interp_b <= '0' & std_logic_vector(r.phase_position(PIPE_LEN_MEM - 1));

            -- Pipeline stage 5: Connect linear interpolator outputs to the MACC.
            if r.zero_coeff(PIPE_SUM_INTP) = '0' then
                s_macc_b <= s_coeff_interp_p(POLY_COEFF_SIZE - 1 downto 0);
            end if;
            s_macc_a <= s_frame_interp_p(SAMPLE_SIZE - 1 downto 0);
            s_macc_sel <= "1" when r.coeff_counter = PIPE_SUM_INTP else "0";

            -- Pipeline stage 0-5: Zero coefficient pipeline registers.
            for i in PIPE_SUM_INTP downto 1 loop
                r_in.zero_coeff(i) <= r.zero_coeff(i - 1);
            end loop;

            -- Pipeline stage 0-7: Register writeback parameters.
            for i in PIPE_LEN_TOTAL downto 1 loop
                r_in.osc_counter(i) <= r.osc_counter(i - 1);
                r_in.sample_counter(i) <= r.sample_counter(i - 1);
                r_in.writeback(i) <= r.writeback(i - 1);
            end loop;

            -- Pipeline stage 9: Store output sample.
            if r.writeback(PIPE_LEN_TOTAL) = '1' then
                -- if addrgen_input(r.osc_counter(PIPE_LEN_TOTAL)).enable = '1' then

                -- Shift by 15 because coefficient is 16 bit signed (+2 extra, not sure why necessary).
                r_in.sample_buffers(r.osc_counter(PIPE_LEN_TOTAL))(r.sample_counter(PIPE_LEN_TOTAL)) 
                    <= t_mono_sample(
                        s_macc_p(SAMPLE_SIZE + POLY_COEFF_SIZE - 4 downto POLY_COEFF_SIZE - 3)); 
                
                -- else
                --     r_in.sample_buffers(r.osc_counter(PIPE_LEN_TOTAL))
                --         (r.sample_counter(PIPE_LEN_TOTAL)) <= (others => '0');
                -- end if;
            end if;

        -- Mux wave memory address to dma to allow writing the wavetable.
        elsif r.state = update_table then 

            s_wave_address_a <= dma2table.write_address;

            if dma2table.done = '1' then 
                r_in.state <= idle;
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
