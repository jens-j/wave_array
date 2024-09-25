library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- Mix together multiple unison oscillators that form a single voice.
-- This is done for each table separately
entity unison_mixer is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic;
        -- sample_in               : in  t_mono_sample_array(0 to N_VOICES - 1);
        sample_in               : in  t_osc_sample_array;
        sample_out              : out t_unison_mixer_output
    );
end entity;

architecture arch of unison_mixer is

    constant BUFFER_SIZE : integer := SAMPLE_SIZE + UNISON_MAX_LOG2;
    constant GAIN_COEFFS : t_gain_coeff_array := GENERATE_GAIN_COEFF_ARRAY;

    type t_state is (idle, running, normalize);
    subtype t_mix_buffer is signed(BUFFER_SIZE - 1 downto 0);
    type t_poly_index_array is array (0 to 1) of integer range 0 to POLYPHONY_MAX - 1; 
    type t_table_index_array is array (0 to 1) of integer range 0 to N_TABLES - 1; 

    type t_mixer_reg is record
        state                   : t_state;
        sample_out              : t_unison_mixer_output;
        sample_out_buffer       : t_unison_mixer_output;
        osc_count               : integer range 0 to N_VOICES - 1;
        unison_count            : integer range 0 to 2 * UNISON_MAX - 1;
        poly_count              : integer range 0 to POLYPHONY_MAX;
        table_count             : integer range 0 to N_TABLES - 1;
        mix_buffer              : t_mix_buffer;
        unison_minus_one        : integer range 0 to UNISON_MAX - 1;
        active_oscillators_minus_one : integer range 0 to N_VOICES - 1;
        multipy_enable          : std_logic;
        wb_enable               : std_logic;
        poly_index_array        : t_poly_index_array;
        table_index_array       : t_table_index_array;
        gain_coeff              : t_ctrl_value;
        mult_result             : t_mono_sample;
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        sample_out              => (others => (others => (others => '0'))),
        sample_out_buffer       => (others => (others => (others => '0'))),
        osc_count               => 0,
        unison_count            => 0,
        poly_count              => 0,
        table_count             => 0,
        mix_buffer              => (others => '0'),
        unison_minus_one        => 0,
        active_oscillators_minus_one => 0,
        multipy_enable          => '0',
        wb_enable               => '0',
        poly_index_array        => (others => 0),
        table_index_array       => (others => 0),
        gain_coeff              => (others => '0'),
        mult_result             => (others => '0')
    );

    signal r, r_in              : t_mixer_reg;

begin

    combinatorial : process (r, config, status, sample_in, next_sample)

        variable v_mult_result : signed(SAMPLE_SIZE + UNISON_MAX_LOG2 + CTRL_SIZE - 1 downto 0);

    begin

        r_in <= r;

        -- Reset one-shots.
        r_in.multipy_enable <= '0';
        r_in.wb_enable <= '0';

        -- Shift index arrays.
        r_in.poly_index_array <= (0, r.poly_index_array(0));
        r_in.table_index_array <= (0, r.table_index_array(0));

        sample_out <= r.sample_out;

        -- Wait for next_sample. 
        if r.state = idle then 
            if next_sample = '1' then 
                r_in.sample_out <= r.sample_out_buffer;
                r_in.sample_out_buffer <= (others => (others => (others => '0')));
                r_in.active_oscillators_minus_one <= status.active_oscillators - 1;
                r_in.unison_minus_one <= config.unison_n - 1;
                r_in.gain_coeff <= GAIN_COEFFS(config.unison_n);
                r_in.osc_count <= 0;
                r_in.unison_count <= 0;
                r_in.poly_count <= 0;
                r_in.table_count <= 0;
                r_in.mix_buffer <= (others => '0');
                r_in.state <= running;
            end if;
        
        -- Add oscillator samples in groups for each output voice.
        elsif r.state = running then 

            if r.unison_count = 0 then
                r_in.mix_buffer <= resize(sample_in(r.table_count)(r.osc_count), BUFFER_SIZE);
            else 
                r_in.mix_buffer <= r.mix_buffer + resize(sample_in(r.table_count)(r.osc_count), BUFFER_SIZE);
            end if;

            if r.osc_count < r.active_oscillators_minus_one then 
                r_in.osc_count <= r.osc_count + 1;

                if r.unison_count < r.unison_minus_one then 
                    r_in.unison_count <= r.unison_count + 1;
                else 
                    r_in.multipy_enable <= '1';
                    r_in.poly_index_array(0) <= r.poly_count;
                    r_in.table_index_array(0) <= r.table_count;
                    r_in.unison_count <= 0;
                    r_in.poly_count <= minimum(POLYPHONY_MAX - 1, r.poly_count + 1);
                end if;
            else 
                r_in.multipy_enable <= '1';
                r_in.poly_index_array(0) <= r.poly_count;
                r_in.table_index_array(0) <= r.table_count;

                r_in.unison_count <= 0;
                r_in.osc_count <= 0;
                r_in.poly_count <= 0;

                if r.table_count < N_TABLES - 1 then 
                    r_in.table_count <= r.table_count + 1;
                else
                    r_in.state <= idle;
                end if;
            end if;
        end if;

        -- Multiply with gain normalization coefficient.
        if r.multipy_enable = '1' then 

            -- After normalization the signal is attenuated by POLYPHONY_MAX. Slice mult_result accordingly.
            v_mult_result := r.mix_buffer * r.gain_coeff;
            r_in.mult_result <= v_mult_result(SAMPLE_SIZE + CTRL_SIZE - 2 downto CTRL_SIZE - 1);
            r_in.wb_enable <= '1';
        end if;

        -- Writeback mutiplication result.
        if r.wb_enable = '1' then 
            r_in.sample_out_buffer(r.table_index_array(1))(r.poly_index_array(1)) <=  r.mult_result;
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