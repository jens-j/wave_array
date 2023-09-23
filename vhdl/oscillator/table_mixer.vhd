library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;


-- Mixes together multiple wavetable outputs into a single waveform.
-- This is done for a each voice in parallel.
-- Every cycle one tabe sample is multiplied with a mix control value. 
-- Samples of each wavetable are added to create the output sample for each voice. 
-- When unison > 1, the control values corresponding to each polyphonic voice are used for multiple oscillators. 
-- Since these are later mixed together in the unison mixer. 
entity table_mixer is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic;
        control                 : in  t_osc_ctrl_array;
        samples_in              : in  t_osc_sample_array;
        samples_out             : out t_mono_sample_array(0 to N_VOICES - 1)
    );
end entity;

architecture arch of table_mixer is

    constant PIPE_LEN_MUX_IN    : integer := 1;
    constant PIPE_LEN_MULT      : integer := 1;
    constant PIPE_LEN_ADD       : integer := 1;
    constant PIPE_LEN_MUX_OUT   : integer := 1;

    constant PIPE_SUM_MULT      : integer := PIPE_LEN_MUX_IN + PIPE_LEN_MULT;
    constant PIPE_SUM_ADD       : integer := PIPE_SUM_MULT + PIPE_LEN_ADD;
    constant PIPE_SUM_MUX_OUT   : integer := PIPE_SUM_ADD + PIPE_LEN_MUX_OUT;

    type t_state is (idle, running);

    type t_osc_count_array is array (0 to PIPE_SUM_MUX_OUT - 1) of integer range 0 to N_VOICES - 1;
    type t_table_count_array is array (0 to PIPE_SUM_MUX_OUT - 1) of integer range 0 to N_TABLES - 1;

    type t_table_mixer_reg is record
        state                   : t_state;
        mix_buffer              : signed(SAMPLE_SIZE + N_TABLES_LOG2 - 1 downto 0);
        samples_out             : t_mono_sample_array(0 to N_VOICES - 1);
        samples_out_buffer      : t_mono_sample_array(0 to N_VOICES - 1);
        osc_count               : t_osc_count_array;
        table_count             : t_table_count_array;
        unison_count            : integer range 0 to UNISON_MAX - 1;
        voice_count             : integer range 0 to POLYPHONY_MAX - 1;
        sample_buffer           : t_mono_sample;
        coefficient_buffer      : t_ctrl_value;
        mult_buffer             : t_mono_sample;
        pipeline_valid          : std_logic_vector(PIPE_SUM_MUX_OUT - 1 downto 0);
        active_oscillators_minus_one : integer range 0 to N_VOICES - 1;
        active_voices_minus_one : integer range 0 to N_VOICES - 1;
    end record;

    constant REG_INIT : t_table_mixer_reg := (
        state                   => idle,
        mix_buffer              => (others => '0'),
        samples_out             => (others => (others => '0')),
        samples_out_buffer      => (others => (others => '0')),
        osc_count               => (others => 0),
        table_count             => (others => 0),
        unison_count            => 0,
        voice_count             => 0,
        sample_buffer           => (others => '0'),
        coefficient_buffer      => (others => '0'),
        mult_buffer             => (others => '0'),
        pipeline_valid          => (others => '0'),
        active_oscillators_minus_one => 1,
        active_voices_minus_one => 1
    );

    signal r, r_in              : t_table_mixer_reg;

begin

    combinatorial : process (r, config, status, next_sample, control, samples_in)
        variable v_mult_result : signed(SAMPLE_SIZE + CTRL_SIZE - 1 downto 0);
    begin

        r_in <= r;
        r_in.pipeline_valid(0) <= '0';

        -- Connect output registers.
        samples_out <= r.samples_out;

        case r.state is 

        when idle => 
            if next_sample = '1' then 

                -- Write new samples to output buffers.
                r_in.samples_out <= r.samples_out_buffer;
                
                r_in.samples_out_buffer <= (others => (others => '0'));
                r_in.mix_buffer <= (others => '0');
                r_in.osc_count(0) <= 0;
                r_in.table_count(0) <= 0;
                r_in.unison_count <= 0;
                r_in.voice_count <= 0;
                r_in.active_oscillators_minus_one <= status.active_oscillators - 1;
                r_in.active_voices_minus_one <= status.active_voices - 1;
        
                r_in.state <= running;
            end if;

        when running => 

            -- Pipeline stage 0: mux input sample and coefficient.
            r_in.pipeline_valid(0) <= '1';
            r_in.sample_buffer <= samples_in(r.table_count(0))(r.osc_count(0));
            r_in.coefficient_buffer <= control(r.table_count(0))(r.voice_count);

            -- Update counters.
            if r.table_count(0) < N_TABLES - 1 then 
                r_in.table_count(0) <= r.table_count(0) + 1;
            else 
                r_in.table_count(0) <= 0;

                if r.osc_count(0) < r.active_oscillators_minus_one then 
                    r_in.osc_count(0) <= r.osc_count(0) + 1;

                    -- Count unison duplicates within polyphonic voices. Since all oscillators within the same group share mix control.
                    if r.unison_count < config.unison_n - 1 then 
                        r_in.unison_count <= r.unison_count + 1;
                    else 
                        r_in.unison_count <= 0;
                        if r.voice_count < r.active_voices_minus_one then 
                            r_in.voice_count <= r.voice_count + 1;
                        end if;
                    end if;
                else 
                    r_in.state <= idle;
                end if;
            end if;

        end case;

        -- Pipeline stage 1: multiply sample with coefficient.
        v_mult_result := r.sample_buffer * r.coefficient_buffer;
        r_in.mult_buffer <= v_mult_result(SAMPLE_SIZE + CTRL_SIZE - 2 downto CTRL_SIZE - 1); -- Drop msb because of signed multiplication.

        -- Pipeline stage 2: add sample to accumulator.
        if r.pipeline_valid(PIPE_SUM_ADD - 2) = '1' then 

            if r.table_count(PIPE_SUM_ADD - 1) = 0 then 
                r_in.mix_buffer <= resize(r.mult_buffer, SAMPLE_SIZE + N_TABLES_LOG2);
            else 
                r_in.mix_buffer <= r.mix_buffer + resize(r.mult_buffer, SAMPLE_SIZE + N_TABLES_LOG2);
            end if;
        end if;

        -- Pipeline stage 3: output mux.
        if r.pipeline_valid(PIPE_SUM_MUX_OUT - 2) = '1' then  
            r_in.samples_out_buffer(r.osc_count(PIPE_SUM_MUX_OUT - 1)) <= 
                r.mix_buffer(SAMPLE_SIZE + N_TABLES_LOG2 - 2 downto N_TABLES_LOG2 - 1);
        end if;

        -- Update shift registers.
        r_in.pipeline_valid(PIPE_SUM_MUX_OUT - 2 downto 1) <= r.pipeline_valid(PIPE_SUM_MUX_OUT - 3 downto 0);
        r_in.osc_count(1 to PIPE_SUM_MUX_OUT - 1) <= r.osc_count(0 to PIPE_SUM_MUX_OUT - 2);
        r_in.table_count(1 to PIPE_SUM_MUX_OUT - 1) <= r.table_count(0 to PIPE_SUM_MUX_OUT - 2);

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
