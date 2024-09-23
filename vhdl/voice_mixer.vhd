library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;

-- Mix together groups of voices. The amount of voices can be dynamically changed (in support of unison and binaural mode). 
-- Scaling is done by multiplicating with a constant to keep unity gain.
-- Voices are muted when they are neither activated and no envelope is active.
entity voice_mixer is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic;
        n_inputs                : in  integer range 1 to POLYPHONY_MAX;
        voice_enable            : in  std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        envelope_active         : in  std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        ctrl_in                 : in  t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        sample_in               : in  t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        sample_out              : out t_mono_sample
    );
end entity;

architecture arch of voice_mixer is

    constant GAIN_COEFFS : t_gain_coeff_array := GENERATE_GAIN_COEFF_ARRAY;

    -- Add some guard bits to the accumulator
    subtype t_mix_buffer is std_logic_vector(SAMPLE_SIZE + POLYPHONY_MAX_LOG2 - 1 downto 0);
    type t_state is (idle, running, normalize);

    type t_mixer_reg is record
        state                   : t_state;
        n_inputs                : integer range 1 to POLYPHONY_MAX;
        ctrl_clipped            : t_ctrl_value;
        mult_buffer             : signed(SAMPLE_SIZE + CTRL_SIZE downto 0);
        mix_buffer              : signed(t_mix_buffer'length - 1 downto 0);
        sample_out              : t_mono_sample;
        sample_out_buffer       : t_mono_sample;
        counter                 : integer range 0 to POLYPHONY_MAX + 1;
        gain_coeff              : t_ctrl_value;
        zero_voice              : std_logic_vector(1 downto 0);
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        n_inputs                => 1,
        ctrl_clipped            => (others => '0'),
        mult_buffer             => (others => '0'),
        mix_buffer              => (others => '0'),
        sample_out              => (others => '0'),
        sample_out_buffer       => (others => '0'),
        counter                 => 0,
        gain_coeff              => (others => '0'),
        zero_voice              => "00"
    );

    signal r, r_in              : t_mixer_reg;

begin

    combinatorial : process (r, n_inputs, sample_in, voice_enable, envelope_active, next_sample, ctrl_in)
        variable v_mult_buffer : signed(SAMPLE_SIZE + POLYPHONY_MAX_LOG2 + CTRL_SIZE downto 0);
    begin

        r_in <= r;

        -- Set outputs.
        sample_out <= r.sample_out;
        r_in.zero_voice(1) <= r.zero_voice(0);
        

        if r.state = idle then
            if next_sample = '1' then
                r_in.state      <= running;
                r_in.sample_out <= r.sample_out_buffer;
                r_in.n_inputs   <= n_inputs;
                r_in.gain_coeff <= GAIN_COEFFS(n_inputs);
                r_in.mix_buffer <= (others => '0');
                r_in.counter    <= 0;
            end if;

        elsif r.state = running then 

            -- Pipeline stage 0: clip control value to positive only. 
            if r.counter < r.n_inputs then 
                r_in.ctrl_clipped <= x"0000" when ctrl_in(r.counter) < 0 else ctrl_in(r.counter);
                r_in.zero_voice(0) <= voice_enable(r.counter) nand envelope_active(r.counter); -- Zero when voice and envelope are not active.
            end if;

            -- Pipeline stage 1: multiply sample with control value.
            if r.counter > 0 and r.counter < r.n_inputs + 1 then 
                r_in.mult_buffer <= signed(sample_in(r.counter - 1)) * signed('0' & r.ctrl_clipped);
            end if;

            -- Pipeline stage 2: slice and extend 16 bit output and add to accumulator.
            if r.counter > 1 and r.zero_voice(1) = '0' then  
                r_in.mix_buffer <= r.mix_buffer + resize(
                    r.mult_buffer(SAMPLE_SIZE + CTRL_SIZE - 2 downto CTRL_SIZE - 1), 
                    t_mono_sample'length + POLYPHONY_MAX_LOG2);
            end if;

            if r.counter = r.n_inputs + 1 then
                r_in.state <= normalize;
            else
                r_in.counter <= r.counter + 1;
            end if;

        -- Multiply with normalization constant.
        elsif r.state = normalize then 

            v_mult_buffer := signed(r.mix_buffer(t_mix_buffer'length - 1 downto 0)) * signed('0' & r.gain_coeff);
            r_in.sample_out_buffer <= v_mult_buffer(SAMPLE_SIZE + CTRL_SIZE - 3 downto CTRL_SIZE - 2);

            r_in.state <= idle;
        else

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
