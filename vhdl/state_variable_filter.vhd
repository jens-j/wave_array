library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xilinx;

-- This entity calculates one sample of a state variable filter for each channel every next_sample pulse. 
-- Each filter step consists of a five stages. Each stage is calculated for every channel before continuing with 
-- the next stage. 
--
-- Pipeline stages:
-- 1) LP = F * BP-1 + LP-1 
-- 2) HP_temp = INPUT - Q * BP-1
-- 3) HP = HP_temp - LP
-- 4) BP = F * HP + BP-1
-- 5) N = HP + LP
entity state_variable_filter is 
    generic (
        N_INPUTS                : integer
        );
    port (
        clk                     : in  std_logic; -- System clock.
        reset                   : in  std_logic;
        config                  : in  t_config;
        next_sample             : in  std_logic;
        sample_in               : in  t_mono_sample_array(0 to N_INPUTS - 1);
        lowpass_out             : out t_mono_sample_array(0 to N_INPUTS - 1);
        highpass_out            : out t_mono_sample_array(0 to N_INPUTS - 1);
        bandpass_out            : out t_mono_sample_array(0 to N_INPUTS - 1);
        notch_out               : out t_mono_sample_array(0 to N_INPUTS - 1)
    );
end entity;


architecture arch of state_variable_filter is 

    constant N_STAGES : integer := 5;

    -- Length of pipeline stages in cycles. 
    constant PIPE_LEN_MACC : integer := 4;
    constant PIPE_LEN_SAT : integer := 1;
    constant PIPE_LEN_WB : integer := 1;

    -- Cumulative pipeline length in cycle.
    constant PIPE_SUM_SAT : integer := PIPE_LEN_MACC + PIPE_LEN_SAT;
    constant PIPE_SUM_WB : integer := PIPE_SUM_SAT + PIPE_LEN_WB;

    -- Number of empty slots inserted at every stage to avoid RAW hazards.
    constant EMPTY_SLOTS : integer := maximum(0, PIPE_SUM_WB - N_INPUTS);

    -- MACC instructions for each pipeline stage
    -- 0 = A * B + C
    -- 1 = C - A * B
    -- 2 = D + A
    -- 3 = D - A

    type t_instruction_array is array (0 to N_STAGES - 1) of std_logic_vector(1 downto 0);
    constant MACC_INSTRUCTION : t_instruction_array := ("00", "01", "11", "00", "10");

    type t_index_array is array (natural range <>) of integer;
    type t_state is (idle, running);

    type t_svf_reg is record
        state                   : t_state;
        lowpass_out             : t_mono_sample_array(0 to N_INPUTS - 1);
        lowpass_buffer          : t_mono_sample_array(0 to N_INPUTS - 1);
        highpass_out            : t_mono_sample_array(0 to N_INPUTS - 1);
        highpass_buffer         : t_mono_sample_array(0 to N_INPUTS - 1);
        bandpass_out            : t_mono_sample_array(0 to N_INPUTS - 1);
        bandpass_buffer         : t_mono_sample_array(0 to N_INPUTS - 1);
        notch_out               : t_mono_sample_array(0 to N_INPUTS - 1);
        notch_buffer            : t_mono_sample_array(0 to N_INPUTS - 1);
        highpass_temp           : t_mono_sample_array(0 to N_INPUTS - 1);
        stage_count_in          : integer range 0 to N_STAGES - 1; -- Count pipeline stages.
        sample_count_in         : integer range 0 to N_INPUTS - 1; -- Count input samples to the MACC.
        empty_count_in          : integer range 0 to EMPTY_SLOTS; -- Insert empty pipeline slots to avoid RAW pipeline hazards. 
        stage_count_array       : t_index_array(0 to PIPE_SUM_WB - 1);
        sample_count_array      : t_index_array(0 to PIPE_SUM_WB - 1);
        pipeline_valid          : std_logic_vector(PIPE_SUM_WB - 1 downto 0); -- shift signals valid data in pipeline for each stage.
        saturation_buffer       : std_logic_vector(2 * SAMPLE_SIZE - 1 downto 0);
        overflow                : std_logic;
    end record;

    constant REG_INIT : t_svf_reg := (
        state                   => idle,
        lowpass_out             => (others => (others => '0')),
        lowpass_buffer          => (others => (others => '0')),
        highpass_out            => (others => (others => '0')),
        highpass_buffer         => (others => (others => '0')),
        bandpass_out            => (others => (others => '0')),
        bandpass_buffer         => (others => (others => '0')),
        notch_out               => (others => (others => '0')),
        notch_buffer            => (others => (others => '0')),
        highpass_temp           => (others => (others => '0')),
        stage_count_in          => 0,
        sample_count_in         => 0,
        empty_count_in          => 0,
        stage_count_array       => (others => 0),
        sample_count_array      => (others => 0),
        pipeline_valid          => (others => '0'),
        saturation_buffer       => (others => '0'),
        overflow                => '0'
    );

    signal r, r_in              : t_svf_reg;
    signal s_macc_a             : std_logic_vector(15 downto 0); -- 16 bit signed.
    signal s_macc_b             : std_logic_vector(17 downto 0); -- Coefficient 2.16b fixed point in [0 - 2) (always positive).
    signal s_macc_c             : std_logic_vector(31 downto 0); -- Should be shifted 16 bits to accomodate for A.
    signal s_macc_d             : std_logic_vector(15 downto 0); -- 16 bit signed.
    signal s_macc_p             : std_logic_vector(35 downto 0); 
    signal s_macc_sel           : std_logic_vector(1 downto 0);
    signal s_macc_carryout      : std_logic;

begin

    macc : entity xilinx.svf_macc_gen
    port map (
        CLK                     => clk,
        SEL                     => s_macc_sel,
        A                       => s_macc_a,
        B                       => s_macc_b,
        C                       => s_macc_c,
        D                       => s_macc_d,
        CARRYOUT                => s_macc_carryout,
        P                       => s_macc_p
    );

    lowpass_out                 <= r.lowpass_out;
    highpass_out                <= r.highpass_out;    
    bandpass_out                <= r.bandpass_out;    
    notch_out                   <= r.notch_out;    
    
    combinatorial : process (r, config, next_sample, sample_in, s_macc_a, s_macc_c, s_macc_d, s_macc_p)
    begin

        r_in <= r;
        r_in.overflow <= '0';

        -- MACC input default.
        s_macc_a <= (others => '0');
        s_macc_b <= (others => '0');
        s_macc_c <= (others => '0');
        s_macc_d <= (others => '0');
        s_macc_sel <= MACC_INSTRUCTION(r.stage_count_in);

        -- Update output buffers and calculate new samples.
        if r.state = idle then 

            r_in.stage_count_in         <= 0;
            r_in.sample_count_in        <= 0;
            r_in.empty_count_in         <= 0;
            r_in.pipeline_valid(0)      <= '0';

            if next_sample = '1' then 
                r_in.lowpass_out        <= r.lowpass_buffer;
                r_in.highpass_out       <= r.highpass_buffer;
                r_in.bandpass_out       <= r.bandpass_buffer;
                r_in.notch_out          <= r.notch_buffer; 
                r_in.state              <= running;
            end if;
        end if;

        if r.state = running then          

            r_in.pipeline_valid(0) <= '1' when r.empty_count_in = 0 else '0';   
            
            -- Don't input data on empty pipeline slots added to avoid RAW pipeline hazards. 
            case (r.stage_count_in) is 
            when 0 => -- A * B + C
                s_macc_a <= std_logic_vector(r.bandpass_out(r.sample_count_in));
                s_macc_b <= std_logic_vector('0' & config.filter_cutoff & '0'); -- 2.16 fixed point in [0 - 2).
                s_macc_c <= std_logic_vector(resize(r.lowpass_out(r.sample_count_in) & (15 downto 0 => '0'), 32));

            when 1 => -- C - A * B
                s_macc_a <= std_logic_vector(r.bandpass_out(r.sample_count_in));
                s_macc_b <= std_logic_vector('0' & config.filter_resonance & '0'); -- 2.16 fixed point in [0 - 2).
                s_macc_c <= std_logic_vector(resize(sample_in(r.sample_count_in) & (15 downto 0 => '0'), 32));

            when 2 => -- D - A
                s_macc_a <= std_logic_vector(r.lowpass_buffer(r.sample_count_in));
                s_macc_d <= std_logic_vector(r.highpass_temp(r.sample_count_in)); 
                
            when 3 => -- A * B + C
                s_macc_a <= std_logic_vector(r.highpass_buffer(r.sample_count_in));
                s_macc_b <= std_logic_vector('0' & config.filter_cutoff & '0'); -- 2.16 fixed point in [0 - 2).
                s_macc_c <= std_logic_vector(resize(r.bandpass_out(r.sample_count_in) & (15 downto 0 => '0'), 32));

            when 4 => -- D + A
                s_macc_a <= std_logic_vector(r.lowpass_buffer(r.sample_count_in)); 
                s_macc_d <= std_logic_vector(r.highpass_buffer(r.sample_count_in));
            end case;
            
            -- Update input counters and de-assert valid if counting empty cycles.
            if r.sample_count_in < N_INPUTS - 1 then 
                r_in.sample_count_in <= r.sample_count_in + 1;
            elsif r.empty_count_in < EMPTY_SLOTS then 
                r_in.empty_count_in <= r.empty_count_in + 1;
            else 
                r_in.sample_count_in <= 0;
                r_in.empty_count_in <= 0;
                if r.stage_count_in < N_STAGES - 1 then 
                    r_in.stage_count_in <= r.stage_count_in + 1;
                else 
                    r_in.stage_count_in <= 0;
                    r_in.state <= idle;
                end if;
            end if;

        end if;

        -- Overflow detection and saturation.
        if r.pipeline_valid(PIPE_LEN_MACC - 1) = '1' then 
            case (MACC_INSTRUCTION(r.stage_count_array(PIPE_LEN_MACC - 1))) is 
            when "00" => -- Clip A * B + C in [-2**31 - 2**31-1].

                -- If >= 0x10000000
                if s_macc_p(2 * SAMPLE_SIZE) = '0' and s_macc_p(2 * SAMPLE_SIZE - 1) = '1' then 

                    r_in.overflow <= '1';
                    r_in.saturation_buffer <= 
                        (2 * SAMPLE_SIZE - 1 downto 2 * SAMPLE_SIZE - 2 => '0', others => '1'); -- 0x7FFFFFFF

                -- If <= 0xF7FFFFFF
                elsif s_macc_p(2 * SAMPLE_SIZE) = '1' and s_macc_p(2 * SAMPLE_SIZE - 1) = '0' then 

                    r_in.overflow <= '1';
                    r_in.saturation_buffer <= 
                        (2 * SAMPLE_SIZE - 1 downto 2 * SAMPLE_SIZE - 2 => '1', others => '0'); -- 0x80000000
                else 
                    r_in.saturation_buffer <= s_macc_p(2 * SAMPLE_SIZE - 1 downto 0);
                end if;
            
            when "10" => -- Clip D + A in [-2**15 - 2**15-1].

                if s_macc_p(2 * SAMPLE_SIZE - 1) = '0' and s_macc_p(SAMPLE_SIZE) = '1' then 

                    r_in.overflow <= '1';
                    r_in.saturation_buffer <= 
                        (2 * SAMPLE_SIZE - 1 downto SAMPLE_SIZE - 1 => '0', others => '1'); -- 0x00007FFF

                elsif s_macc_p(2 * SAMPLE_SIZE - 1) = '1' and s_macc_p(SAMPLE_SIZE) = '0' then 

                    r_in.overflow <= '1';
                    r_in.saturation_buffer <= 
                        (2 * SAMPLE_SIZE - 1 downto SAMPLE_SIZE - 1 => '1', others => '0'); -- 0xFFFF8000
                else 
                    r_in.saturation_buffer <= s_macc_p(2 * SAMPLE_SIZE - 1 downto 0);
                end if;
            
            when others => 
                r_in.saturation_buffer <= s_macc_p(2 * SAMPLE_SIZE - 1 downto 0);
            end case;
        end if;

        -- Writeback stage.
        -- Multiplication outputs are 17.15 fixed point.
        if r.pipeline_valid(PIPE_SUM_SAT - 1) = '1' then 

            case (r.stage_count_array(PIPE_SUM_SAT - 1)) is 

            when 0 => 
                r_in.lowpass_buffer(r.sample_count_array(PIPE_SUM_SAT - 1)) <= 
                    signed(r.saturation_buffer(2 * SAMPLE_SIZE - 1 downto SAMPLE_SIZE));

            when 1 =>
                r_in.highpass_temp(r.sample_count_array(PIPE_SUM_SAT - 1)) <= 
                    signed(r.saturation_buffer(2 * SAMPLE_SIZE - 1 downto SAMPLE_SIZE));

            when 2 => 
                r_in.highpass_buffer(r.sample_count_array(PIPE_SUM_SAT - 1)) <= 
                    signed(r.saturation_buffer(SAMPLE_SIZE - 1 downto 0));

            when 3 => 
                r_in.bandpass_buffer(r.sample_count_array(PIPE_SUM_SAT - 1)) <= 
                    signed(r.saturation_buffer(2 * SAMPLE_SIZE - 1 downto SAMPLE_SIZE));

            when 4 => 
                r_in.notch_buffer(r.sample_count_array(PIPE_SUM_SAT - 1)) <= 
                    signed(r.saturation_buffer(SAMPLE_SIZE - 1 downto 0));
                
            -- Don't write back on empty pipeline slots added to avoid RAW pipeline hazards. 
            when others =>
            end case;
        end if;

        -- Pipeline shift registers.
        r_in.pipeline_valid(PIPE_SUM_WB - 1 downto 1) <= r.pipeline_valid(PIPE_SUM_WB - 2 downto 0);

        r_in.stage_count_array(0) <= r.stage_count_in;
        r_in.stage_count_array(1 to PIPE_SUM_WB - 1) <= r.stage_count_array(0 to PIPE_SUM_WB - 2);

        r_in.sample_count_array(0) <= r.sample_count_in;
        r_in.sample_count_array(1 to PIPE_SUM_WB - 1) <= r.sample_count_array(0 to PIPE_SUM_WB - 2);
            
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

