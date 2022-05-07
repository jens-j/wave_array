library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity oscillator is
    generic (
        N_OSCILLATORS           : positive := 16
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample(s) trigger.
        frame_0_index           : in  integer range 0 to 3; -- Frame x buffer index.
        frame_1_index           : in  integer range 0 to 3; -- Frame x+1 buffer index.
        osc_inputs              : in  t_osc_input_array(0 to N_OSCILLATORS - 1);
        osc_outputs             : out t_mono_sample_array(0 to N_OSCILLATORS - 1);
        overflow                : out std_logic; -- Flag numeric overflow.
        timeout                 : out std_logic -- Flag that the oscillator could not keep up.
    );
end entity;

architecture arch of oscillator is

    -- Pipeline stage lengths.
    constant PIPE_LEN_ADDR      : integer := 1; -- Mipmap address generation.
    constant PIPE_LEN_MEM       : integer := 2; -- Sample & coefficient memory access.
    constant PIPE_LEN_INTP      : integer := 4; -- Sample & coefficient linear interpolation.
    constant PIPE_LEN_MACC      : integer := 3; -- Polyphase filter multiply-accumulate.
    constant PIPE_LEN_TOTAL     : integer := PIPE_LEN_MEM + PIPE_LEN_INTP + PIPE_LEN_MACC; -- Total pipeline length.

    -- Cumulative pipeline lengths.
    constant PIPE_SUM_MEM       : integer := PIPE_LEN_ADDR + PIPE_LEN_MEM;
    constant PIPE_SUM_INTP      : integer := PIPE_SUM_MEM + PIPE_LEN_INTP;
    constant PIPE_SUM_MACC      : integer := PIPE_SUM_INTP + PIPE_LEN_MACC;


    type t_state is (idle, running);
    type t_mipmap_level_array is array 0 to N_OSCILLATORS - 1
        of integer range 0 to MIPMAP_LEVELS - 1;
    type t_counter_array is array 0 to PIPE_LEN_TOTAL - 1 of integer range 0 to N_OSCILLATORS - 1;

    type t_oscillator_reg is record
        state                   : t_state;
        frame_0_index           : integer range 0 to 3; -- Frame x buffer index.
        frame_1_index           : integer range 0 to 3; -- Frame x+1 buffer index.
        pipeline_counter        : integer range 0 to POLY_N + PIPELINE_LENGTH; -- Count pipeline cycles.
        osc_counter             : t_counter_array; -- The counter is registered for each cycle of the pipeline.
        even_odd                : std_logic; -- Indicate if busy with the first (even) or second sample (odd).
        phases                  : t_osc_phase_array(0 to N_OSCILLATORS - 1);
        mipmap_levels           : t_mipmap_level_array;
        mipmap_address          : t_wave_buffer_address;
        osc_outputs             : t_mono_sample_array(0 to N_OSCILLATORS - 1); -- Output sample buffers.
        overflow                : integer; -- Sticky bit.
        timeout                 : integer; -- Sticky bit.
    end record;

    constant R_INIT : t_oscillator_reg := (
        state                   => idle,
        frame_0_index           => 0,
        frame_1_index           => 1,
        pipeline_counter        => 0,
        osc_counter             => 0
        even_odd                => 1,
        phases                  => (others => (others => '0'),
        mipmap_levels           => (others => 0),
        mipmap_address          => (others => '0'),
        osc_outputs             => (others => (others => '0')),
        overflow                => '0';
        timeout                 => '0';
    );

    signal r, r_in : t_oscillator_reg := R_INIT;

begin

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
    signal s_macc_sel           : std_logic; -- 0: macc, 1: mul.
    signal s_macc_a             : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_macc_b             : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_macc_p             : std_logic_vector(47 downto 0); -- Full width output.

    signal s_wave_mem_wea       : std_logic;
    signal s_wave_mem_addra     : unsigned(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 0);
    signal s_wave_mem_dina      : t_mono_sample;
    signal s_wave_mem_addrb     : t_mipmap_address;
    signal s_wave_mem_doutb     : std_logic_vector(4 * SAMPLE_SIZE - 1 downto 0);

    signal s_coeff_even_addra   : t_coeff_address;
    signal s_coeff_even_douta   : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);
    signal s_coeff_odd_addra    : t_coeff_address;
    signal s_coeff_odd_douta    : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);



    -- Wave table memory.
    -- It has a 16 bit wide write port (A) and 64 bit wide read port (B).
    -- four mipmap tables are stored interleaved. Two are actively used by the oscillator, while
    -- the other two can be used as buffers for writing new tables. A sample is read from all buffers
    -- at the same time while writing can be done to single samples of single buffers.
    wave_mem : entity ip.osc_wave_memory_gen
    port map (
        clka                    => clk,
        wea                     => s_wave_mem_wea,
        addra                   => s_wave_mem_addra,
        dina                    => s_wave_mem_dina,
        clkb                    => clk,
        addrb                   => s_wave_mem_addrb,
        doutb                   => s_wave_mem_doutb
    );

    -- ROM that holds the filter coefficients for the even phases.
    coeff_mem_even : entity ip.osc_coeff_memory_gen
    port map (
        clka                    => clk,
        addra                   => s_coeff_even_addra,
        douta                   => s_coeff_even_douta
    );

    -- ROM that holds the filter coefficients for the odd phases.
    coeff_mem_odd : entity ip.osc_coeff_memory_gen
    port map (
        clka                    => clk,
        addra                   => s_coeff_odd_addra,
        douta                   => s_coeff_odd_douta
    );

    -- DSP slice confifgured to perform linear interpolation of two frames (samples).
    -- Implements (A - D) * B + C = P.
    frame_interp: entity ip.osc_interpolation_gen
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
    coeff_interp: entity ip.osc_interpolation_gen
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
    filter_macc: entity ip.osc_macc_gen
    port map (
        CLK                     => clk,
        SEL                     => s_macc_sel,
        A                       => s_macc_a,
        B                       => s_macc_b,
        P                       => s_macc_p
    );

    -- Output connections.
    osc_outputs <= r.osc_outputs;
    overflow <= r.overflow;
    timeout <= r.timeout

    combinatorial : process (r, osc_inputs, next_sample)
        variable v_mipmap_level : integer range 0 to MIPMAP_LEVELS - 1;
        variable v_idx_0 : integer range 0 to 3;
        variable v_idx_1 : integer range 0 to 3;
        variable v_phase_int : unsigned(POLY_M_LOG2 - 1 downto 0);
        variable v_phase_frac : unsigned(OSC_COEFF_FRAC - 1 downto 0);
    begin

        r_in <= r;

        if next_sample = '1' then

            -- Flag an error if still busy when the next trigger comes.
            if r.state /= idle then
                r_in.timeout <= '1';
            end if;

            -- Start new cycle
            r_in.frame_0_index <= frame_0_index;
            r_in.frame_1_index <= frame_1_index;
            r_in.state <= running;
            r_in.osc_counter(0) <= 0;
            r_in.even_odd <= '0';
        end if;

        -- Check for end of (half) cycle.
        if r.counter = POLY_N + PIPELINE_LENGTH - 1 then
            if r.even_odd = '0' then
                r_in.osc_counter(0)
                r_in.even_odd <= '1';
            else
                r_in.state <= idle;
            end if;
        else
            r_in.osc_counter(0) <= r.osc_counter(0) + 1;
        end if;

        -- Register osc_counter PIPE_LEN_TOTAL TIMES for use later in the pipeline.
        for i in range PIPE_LEN_TOTAL - 1 downto 1 loop
            r_in.osc_counter(i) <= r.osc_counter(i - 1)
        end loop;

        -- Pipeline stage 0: generate the mipmap address by adding the integer part of the phase
        -- (shifted right by the mipmap level) to the mipmap table offset.
        v_mipmap_level := r.mipmap_levels(r.osc_counter(0))
        r_in.mipmap_address <= MIPMAP_LEVEL_OFFSETS(v_mipmap_level) + resize(
            r.osc_phases(r.osc_counter(0))(t_osc_phase'length - 1 downto v_mipmap_level),
            MIPMAP_TABLE_SIZE_LOG2 - 1);

        -- Pipeline stage 1: Wave memory access.
        s_wave_mem_addrb <= r.mipmap_address;

        -- Pipeline stage 1: Coefficient memory access.
        -- Get coefficient for phase m and m+1 from the two coefficient memories.
        v_phase_int := r.phases(r.osc_counter(PIPE_LEN_MEM)
            (POLY_M_LOG2 + OSC_COEFF_FRAC - 1 downto OSC_COEFF_FRAC));

        if v_phase_int(0) = '0' then
            s_coeff_even_addra <= v_phase_int(POLY_M_LOG2 - 1 downto 1);
            s_coeff_odd_addra <= v_phase_int(POLY_M_LOG2 - 1 downto 1);
        else
            s_coeff_even_addra <= resize(v_phase_int(POLY_M_LOG2 - 1 downto 1) + 1,
                                         POLY_M_LOG2 * POLY_N_LOG2 - 1);
            s_coeff_odd_addra <= v_phase_int(POLY_M_LOG2 - 1 downto 1);
        end if;

        -- Pipeline stage 3: Read wave memory (mux by active buffer indices) and send to frame
        -- interpolator. Interpolation is performed in a single DSP slice (4 stage pipeline).
        -- (A - D) * B + C = (sampleB - sampleA) * frac(position) + sampleA
        s_frame_interp_b <= osc_inputs(r.osc_counter(PIPE_SUM_MEM).position;
        s_frame_interp_a <= s_wave_mem_doutb(
            (r.frame_1_index + 1) * SAMPLE_SIZE - 1 downto r.frame_1_index * SAMPLE_SIZE);
        s_frame_interp_c <= s_wave_mem_doutb(
            (r.frame_0_index + 1) * SAMPLE_SIZE - 1 downto r.frame_0_index * SAMPLE_SIZE);
        s_frame_interp_d <= s_wave_mem_doutb(
            (r.frame_0_index + 1) * SAMPLE_SIZE - 1 downto r.frame_0_index * SAMPLE_SIZE);

        -- Pipeline stage 3: Read coefficient memory and send to interpolator. The values for the
        -- even and odd coefficient memories are swapped if the phase m is odd.
        v_phase_int := r.phases(r.osc_counter(PIPE_SUM_MEM)
            (POLY_M_LOG2 + OSC_COEFF_FRAC - 1 downto OSC_COEFF_FRAC));

        if v_phase_int(0) = '0' then
            s_coeff_interp_a <= s_coeff_odd_douta;
            s_coeff_interp_c <= s_coeff_even_douta
            s_coeff_interp_d <= s_coeff_even_douta;
        else
            s_coeff_interp_a <= s_coeff_even_douta;
            s_coeff_interp_c <= s_coeff_odd_douta
            s_coeff_interp_d <= s_coeff_odd_douta;
        end if;

        s_coeff_interp_b <= r.phases(r.osc_counter(PIPE_SUM_MEM)(OSC_COEFF_FRAC - 1 downto 0);

        -- Pipeline stage 7: Connect linear interpolator outputs to the MACC.
        s_macc_a <= s_frame_interp_p(SAMPLE_SIZE - 1 downto 0);
        s_macc_b <= s_coeff_interp_p(POLY_COEFF_SIZE - 1 downto 0);
        if r.osc_counter(PIPE_SUM_INTP) = (others => '0') then -- First cycle: mul, rest: macc.
            s_macc_sel <= '1';
        else
            s_macc_sel <= '0';
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
