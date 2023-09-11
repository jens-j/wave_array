library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- Mix together multiple unison oscillators that form a single voice.
-- Gain is normalized at the end based on the number of inputs.
entity unison_mixer is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        next_sample             : in  std_logic;
        sample_in               : in  t_mono_sample_array(0 to N_VOICES - 1);
        sample_out              : out t_mono_sample_array(0 to POLYPHONY_MAX - 1)
    );
end entity;

architecture arch of unison_mixer is

    constant BUFFER_SIZE : integer := SAMPLE_SIZE + UNISON_MAX_LOG2;
    constant GAIN_COEFFS : t_gain_coeff_array := GENERATE_GAIN_COEFF_ARRAY;

    type t_state is (idle, running, normalize);
    subtype t_mix_buffer is signed(BUFFER_SIZE - 1 downto 0);

    type t_mixer_reg is record
        state                   : t_state;
        sample_out              : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        sample_out_buffer       : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        osc_count               : integer range 0 to N_VOICES - 1;
        unison_count            : integer range 0 to 2 * UNISON_MAX - 1;
        poly_count              : integer range 0 to POLYPHONY_MAX;
        mix_buffer              : t_mix_buffer;
        unison_minus_one        : integer range 1 to 2 * UNISON_MAX;
        active_voices_minus_one : integer range 1 to N_VOICES;
        group_done              : std_logic;
        poly_index              : integer range 0 to POLYPHONY_MAX - 1; 
        gain_coeff              : t_ctrl_value;
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        sample_out              => (others => (others => '0')),
        sample_out_buffer       => (others => (others => '0')),
        osc_count               => 0,
        unison_count            => 0,
        poly_count              => 0,
        mix_buffer              => (others => '0'),
        unison_minus_one        => 1,
        active_voices_minus_one => 1,
        group_done              => '0',
        poly_index              => 0,
        gain_coeff              => (others => '0')
    );

    signal r, r_in              : t_mixer_reg;

begin

    combinatorial : process (r, config, sample_in, next_sample)

        variable v_mult_result : signed(SAMPLE_SIZE + POLYPHONY_MAX_LOG2 + CTRL_SIZE - 1 downto 0);

    begin

        r_in <= r;
        r_in.group_done <= '0';

        sample_out <= r.sample_out;

        -- Wait for next_sample. 
        if r.state = idle then 
            if next_sample = '1' then 
                r_in.sample_out <= r.sample_out_buffer;
                r_in.sample_out_buffer <= (others => (others => '0'));
                r_in.active_voices_minus_one <= config.active_voices - 1;
                r_in.unison_minus_one <= config.unison_n - 1;
                r_in.gain_coeff <= GAIN_COEFFS(config.unison_n);
                r_in.osc_count <= 0;
                r_in.unison_count <= 0;
                r_in.poly_count <= 0;
                r_in.mix_buffer <= (others => '0');
                r_in.state <= running;
            end if;
        
        -- Add oscillator samples in groups for each output voice.
        elsif r.state = running then 

            if r.unison_count = 0 then
                r_in.mix_buffer <= resize(sample_in(r.osc_count), BUFFER_SIZE);
            else 
                r_in.mix_buffer <= r.mix_buffer + resize(sample_in(r.osc_count), BUFFER_SIZE);
            end if;

            if r.osc_count < r.active_voices_minus_one then 
                r_in.osc_count <= r.osc_count + 1;

                if r.unison_count < r.unison_minus_one then 
                    r_in.unison_count <= r.unison_count + 1;
                else 
                    r_in.group_done <= '1';
                    r_in.poly_index <= r.poly_count;
                    r_in.unison_count <= 0;
                    r_in.poly_count <= minimum(POLYPHONY_MAX - 1, r.poly_count + 1);
                end if;
            else 
                r_in.group_done <= '1';
                r_in.poly_index <= r.poly_count;
                r_in.state <= idle;
            end if;
        end if;

        -- Multiply with gain normalization coefficient.
        if r.group_done = '1' then 

            -- After normalization the signal is attenuated by POLYPHONY_MAX. Slice mult_result accordingly.
            v_mult_result := r.mix_buffer * r.gain_coeff;
            r_in.sample_out_buffer(r.poly_index) <= v_mult_result(SAMPLE_SIZE + CTRL_SIZE - 1 downto CTRL_SIZE);
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