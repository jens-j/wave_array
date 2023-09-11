library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;


entity halfband_filter is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample trigger.
        input_samples           : in  t_stereo_sample_array(0 to N_VOICES - 1);
        output_samples          : out t_mono_sample_array(0 to N_VOICES - 1)
    );
end entity;

architecture arch of halfband_filter is

    constant PIPE_LEN_LOAD      : integer := 1;
    constant PIPE_LEN_MULT      : integer := 4;

    constant PIPE_SUM_MULT      : integer := PIPE_LEN_LOAD + PIPE_LEN_MULT;

    type t_state is (idle, load_samples, run_filter);

    type t_osc_counter is array (0 to PIPE_SUM_MULT) of integer range 0 to N_VOICES - 1;
    type t_coeff_counter is array (0 to PIPE_SUM_MULT) of integer range 0 to HALFBAND_PHASE_N / 2;

    type t_halfband_reg is record
        state                   : t_state;
        osc_counter             : t_osc_counter;
        coeff_counter           : t_coeff_counter;
        output_samples          : t_mono_sample_array(0 to N_VOICES - 1);
        output_buffers          : t_mono_sample_array(0 to N_VOICES - 1);
        write_pointer_odd       : unsigned(HALFBAND_PHASE_N_LOG2 - 2 downto 0);
        write_pointer_even      : unsigned(HALFBAND_PHASE_N_LOG2 - 1 downto 0);
        read_pointer_odd        : unsigned(HALFBAND_PHASE_N_LOG2 - 2 downto 0);
        read_pointer_even       : unsigned(HALFBAND_PHASE_N_LOG2 - 1 downto 0);
        index_past              : unsigned(HALFBAND_PHASE_N_LOG2 - 1 downto 0);
        index_future            : unsigned(HALFBAND_PHASE_N_LOG2 - 1 downto 0);
        pipeline_valid          : std_logic_vector(PIPE_SUM_MULT downto 0);
    end record;

    constant REG_INIT : t_halfband_reg := (
        state                   => idle,
        osc_counter             => (others => 0),
        coeff_counter           => (others => 0),
        output_samples          => (others => (others => '0')),
        output_buffers          => (others => (others => '0')),
        write_pointer_odd       => (others => '0'),
        write_pointer_even      => (others => '0'),
        read_pointer_odd        => to_unsigned(1, HALFBAND_PHASE_N_LOG2 - 1), -- Write pointer + 1.
        read_pointer_even       => to_unsigned(HALFBAND_PHASE_N / 2 + 1, HALFBAND_PHASE_N_LOG2), -- Write pointer + size / 2.
        index_past              => (others => '0'),
        index_future            => (others => '0'),
        pipeline_valid          => (others => '0')
    );

    signal r, r_in              : t_halfband_reg;
    signal s_macc_sel           : std_logic_vector(1 downto 0);
    signal s_macc_a             : std_logic_vector(15 downto 0);
    signal s_macc_b             : std_logic_vector(15 downto 0);
    signal s_macc_d             : std_logic_vector(15 downto 0);
    signal s_macc_p             : std_logic_vector(47 downto 0);

    -- Even ram signals.
    signal s_write_enable_a_even: std_logic_vector(0 downto 0);
    signal s_address_a_even     : std_logic_vector(HALFBAND_DEPTH_EVEN_LOG2 - 1 downto 0);
    signal s_write_data_a_even  : std_logic_vector(HALFBAND_COEFF_SIZE - 1 downto 0);
    signal s_read_data_a_even   : std_logic_vector(HALFBAND_COEFF_SIZE - 1 downto 0);
    
    signal s_address_b_even     : std_logic_vector(HALFBAND_DEPTH_EVEN_LOG2 - 1 downto 0);
    signal s_read_data_b_even   : std_logic_vector(HALFBAND_COEFF_SIZE - 1 downto 0);

    -- Odd ram signals.
    signal s_write_enable_a_odd : std_logic_vector(0 downto 0);
    signal s_address_a_odd      : std_logic_vector(HALFBAND_DEPTH_ODD_LOG2 - 1 downto 0);
    signal s_write_data_a_odd   : std_logic_vector(HALFBAND_COEFF_SIZE - 1 downto 0);

    signal s_address_b_odd      : std_logic_vector(HALFBAND_DEPTH_ODD_LOG2 - 1 downto 0);
    signal s_read_data_b_odd    : std_logic_vector(HALFBAND_COEFF_SIZE - 1 downto 0);

begin

    -- One write port and two read ports. 4096 samples deep.
    even_ram : entity xil_defaultlib.halfband_ram_even
    port map (
        clka                    => clk,
        wea                     => s_write_enable_a_even,
        addra                   => s_address_a_even,
        dina                    => s_write_data_a_even,
        douta                   => s_read_data_a_even,
        clkb                    => clk,
        web                     => "0",
        addrb                   => s_address_b_even, 
        dinb                    => (others => '0'),
        doutb                   => s_read_data_b_even 
    );

    -- One write port and one read ports. 2048 samples deep.
    odd_ram : entity xil_defaultlib.halfband_ram_odd
    port map (
        clka                    => clk,
        wea                     => s_write_enable_a_odd,
        addra                   => s_address_a_odd,
        dina                    => s_write_data_a_odd,
        clkb                    => clk,
        addrb                   => s_address_b_odd, 
        doutb                   => s_read_data_b_odd
    );

    -- sel = 0: P = (A + D) * B
    -- sel = 1: P = (A + D) * B + P
    -- sel = 2: P = A * B + P
    macc : entity xil_defaultlib.halfband_macc_gen
    port map (
        CLK                     => clk,
        SEL                     => s_macc_sel,
        A                       => s_macc_a,
        B                       => s_macc_b,
        D                       => s_macc_d,
        P                       => s_macc_p
    );


    output_samples <= r.output_samples;

    combinatorial : process (r, next_sample, input_samples, s_macc_p, 
        s_read_data_a_even, s_read_data_b_even, s_read_data_b_odd)

    begin

        r_in                    <= r;

        s_macc_sel              <= "00";
        s_macc_a                <= (others => '0');
        s_macc_b                <= (others => '0');
        s_macc_d                <= (others => '0');
        s_write_enable_a_odd    <= "0";
        s_write_enable_a_even   <= "0";
        s_write_data_a_even     <= (others => '0');
        s_write_data_a_odd      <= (others => '0');
        s_address_a_even        <= (others => '0');
        s_address_b_even        <= (others => '0');
        s_address_a_odd         <= (others => '0');
        s_address_b_odd         <= (others => '0');

        if r.state = idle then
            if next_sample = '1' then

                r_in.output_samples <= r.output_buffers;
                r_in.osc_counter(0) <= 0;

                r_in.state <= load_samples;
            end if;

        -- Load new samples in the even and odd sample buffers.
        elsif r.state = load_samples then

            -- Write new samples to the RAMs.
            s_write_enable_a_even <= "1";
            s_write_data_a_even <= std_logic_vector(input_samples(r.osc_counter(0))(0));
            s_address_a_even <= 
                std_logic_vector(resize(to_unsigned(r.osc_counter(0), N_VOICES_MAX_LOG2), N_VOICES_MAX_LOG2))
                & std_logic_vector(r.write_pointer_even);

            s_write_enable_a_odd <= "1";
            s_write_data_a_odd <= std_logic_vector(input_samples(r.osc_counter(0))(1));
            s_address_a_odd <= 
                std_logic_vector(resize(to_unsigned(r.osc_counter(0), N_VOICES_MAX_LOG2), N_VOICES_MAX_LOG2))
                & std_logic_vector(r.write_pointer_odd);

            -- Increment osc counter and write pointers.
            if r.osc_counter(0) < N_VOICES - 1 then 
                r_in.osc_counter(0) <= r.osc_counter(0) + 1;
            else 
                r_in.osc_counter(0) <= 0;
                r_in.coeff_counter(0) <= 0;
                r_in.pipeline_valid(0) <= '1';
                r_in.write_pointer_even <= r.write_pointer_even + 1;
                r_in.write_pointer_odd <= r.write_pointer_odd + 1;
                r_in.index_past <= r.read_pointer_even;
                r_in.index_future <= r.read_pointer_even + 1;
                r_in.state <= run_filter;
            end if;

        -- Load load two samples from the even sample ram and multiply with even coefficient for each even coefficient.
        -- In the last cycle add one odd sample.
        elsif r.state = run_filter then

            r_in.pipeline_valid(0) <= '1';

            -- Pipeline stage 0: load samples from the rams.
            if r.coeff_counter(0) < HALFBAND_PHASE_N / 2 then

                s_address_a_even <= std_logic_vector(to_unsigned(r.osc_counter(0), N_VOICES_MAX_LOG2))
                    & std_logic_vector(r.index_past);

                s_address_b_even <= std_logic_vector(to_unsigned(r.osc_counter(0), N_VOICES_MAX_LOG2))
                    & std_logic_vector(r.index_future);

                r_in.index_past <= r.index_past - 1;
                r_in.index_future <= r.index_future + 1;

            elsif r.coeff_counter(0) = HALFBAND_PHASE_N / 2 then 

                s_address_b_odd <= std_logic_vector(to_unsigned(r.osc_counter(0), N_VOICES_MAX_LOG2))
                    & std_logic_vector(r.read_pointer_odd);
            end if;

            -- Increment counters. 
            if r.coeff_counter(0) < HALFBAND_PHASE_N / 2 then 
                r_in.coeff_counter(0) <= r.coeff_counter(0) + 1;
            else 
                r_in.coeff_counter(0) <= 0;
                r_in.index_past <= r.read_pointer_even;
                r_in.index_future <= r.read_pointer_even + 1;

                if r.osc_counter(0) < N_VOICES - 1 then 
                    r_in.osc_counter(0) <= r.osc_counter(0) + 1;
                else 
                    r_in.pipeline_valid(0) <= '0';
                    r_in.read_pointer_even <= r.read_pointer_even + 1;
                    r_in.read_pointer_odd <= r.read_pointer_odd + 1;
                    r_in.state <= idle;
                end if;
            end if;
        end if;

        -- Pipeline stage 1: input oparands to the multipler.
        if r.pipeline_valid(PIPE_LEN_LOAD) = '1' then 

            if r.coeff_counter(PIPE_LEN_LOAD) = 0 then 
                s_macc_sel <= "00";
            elsif r.coeff_counter(PIPE_LEN_LOAD) < HALFBAND_PHASE_N / 2 then
                s_macc_sel <= "01";
            else 
                s_macc_sel <= "10";
            end if;

            if r.coeff_counter(PIPE_LEN_LOAD) < HALFBAND_PHASE_N / 2 then

                s_macc_a <= s_read_data_a_even;
                s_macc_d <= s_read_data_b_even;
                s_macc_b <= HALFBAND_COEFFICIENTS(r.coeff_counter(PIPE_LEN_LOAD));
            
            elsif r.coeff_counter(PIPE_LEN_LOAD) = HALFBAND_PHASE_N / 2 then 

                s_macc_a <= s_read_data_b_odd;
                s_macc_b <= x"7FFF";
            end if;
        end if;
        
        -- Pipeline stage 5: Store result.
        if r.pipeline_valid(PIPE_SUM_MULT) = '1' then 

            if r.coeff_counter(PIPE_SUM_MULT) = HALFBAND_PHASE_N / 2 then

                r_in.output_buffers(r.osc_counter(PIPE_SUM_MULT)) <= signed(s_macc_p(30 downto 15));
            end if;
        end if;

        -- Update shift registers.
        r_in.pipeline_valid(PIPE_SUM_MULT downto 1) <= r.pipeline_valid(PIPE_SUM_MULT - 1 downto 0);
        r_in.osc_counter(1 to PIPE_SUM_MULT) <= r.osc_counter(0 to PIPE_SUM_MULT - 1);
        r_in.coeff_counter(1 to PIPE_SUM_MULT) <= r.coeff_counter(0 to PIPE_SUM_MULT - 1);

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
