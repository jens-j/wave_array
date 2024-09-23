library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- Mixes together all voices to create a single mono or stereo output stream depending whether binaural mode is enabled.
entity voice_mixer_subsystem is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic;
        osc_inputs              : in  t_osc_input_array(0 to POLYPHONY_MAX - 1);
        envelope_active         : in  std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        sample_in               : in  t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        ctrl_in                 : in  t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        sample_out              : out t_stereo_sample
    );
end entity;


architecture arch of voice_mixer_subsystem is

    constant ACTIVE_OSCILLATORS_DEFAULT : t_active_oscillators_array := CALCULATE_ACTIVE_OSCILLATORS('0');
    constant ACTIVE_OSCILLATORS_BINAURAL : t_active_oscillators_array := CALCULATE_ACTIVE_OSCILLATORS('1');
    
    type t_mixer_subsys_reg is record 
        n_inputs                : integer range 1 to POLYPHONY_MAX;
        sample_in_left          : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        sample_in_right         : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        ctrl_left               : t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        ctrl_right              : t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        voice_enable_left       : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        voice_enable_right      : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        envelope_active_left    : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
        envelope_active_right   : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
    end record;

    constant REG_INIT : t_mixer_subsys_reg := (
        n_inputs                => POLYPHONY_MAX,
        sample_in_left          => (others => (others => '0')),
        sample_in_right         => (others => (others => '0')),
        ctrl_left               => (others => (others => '0')),
        ctrl_right              => (others => (others => '0')),
        voice_enable_left       => (others => '0'),
        voice_enable_right      => (others => '0'),
        envelope_active_left    => (others => '0'),
        envelope_active_right   => (others => '0')
    );

    signal r, r_in              : t_mixer_subsys_reg;
    signal s_voice_enable       : std_logic_vector(POLYPHONY_MAX - 1 downto 0);

begin 

    voice_mixer_left : entity wave.voice_mixer 
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        n_inputs                => r.n_inputs,
        voice_enable            => r.voice_enable_left,
        envelope_active         => r.voice_enable_right,
        ctrl_in                 => r.ctrl_left,
        sample_in               => r.sample_in_left,
        sample_out              => sample_out(0)
    );

    voice_mixer_right : entity wave.voice_mixer 
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        n_inputs                => r.n_inputs,
        voice_enable            => r.envelope_active_left,
        envelope_active         => r.envelope_active_right,
        ctrl_in                 => r.ctrl_right,
        sample_in               => r.sample_in_right,
        sample_out              => sample_out(1)
    );

    -- Mux input samples depending on whether binaural mode is enabled and the number of available voices.
    combinatorial : process (r, config, status, next_sample, ctrl_in, sample_in)
    begin

        r_in <= r;
        r_in.n_inputs <= status.polyphony;

        -- Combine voice active bits into array.
        for i in 0 to POLYPHONY_MAX - 1 loop 
            s_voice_enable(i) <= osc_inputs(i).enable;
        end loop;

        -- Assign the same samples to the left and right channel.
        if config.binaural_enable = '0' then 
            
            for i in 0 to POLYPHONY_MAX - 1 loop
                if i < status.active_voices then  
                    r_in.sample_in_left(i) <= sample_in(i);
                    r_in.sample_in_right(i) <= sample_in(i);
                    r_in.ctrl_left(i) <= ctrl_in(i);
                    r_in.ctrl_right(i) <= ctrl_in(i);
                    r_in.voice_enable_left(i) <= osc_inputs(i).enable;
                    r_in.voice_enable_right(i) <= osc_inputs(i).enable;
                    r_in.envelope_active_left(i) <= envelope_active(i);
                    r_in.envelope_active_right(i) <= envelope_active(i);
                else 
                    r_in.sample_in_left(i) <= (others => '0');
                    r_in.sample_in_right(i) <= (others => '0');
                    r_in.ctrl_left(i) <= (others => '0');
                    r_in.ctrl_right(i) <= (others => '0');
                    r_in.voice_enable_left(i) <= '0';
                    r_in.voice_enable_right(i) <= '0';
                    r_in.envelope_active_left(i) <= '0';
                    r_in.envelope_active_right(i) <= '0';
                end if;
            end loop;
        
        -- In binaural mode, left and right are separate. The input samples are interleaved.
        else 

            r_in.sample_in_left <= (others => (others => '0'));
            r_in.sample_in_right <= (others => (others => '0'));
            r_in.ctrl_left <= (others => (others => '0'));
            r_in.ctrl_right <= (others => (others => '0'));
            r_in.voice_enable_left <= (others => '0');
            r_in.voice_enable_right <= (others => '0');
            r_in.envelope_active_left <= (others => '0');
            r_in.envelope_active_right <= (others => '0');

            for i in 0 to POLYPHONY_MAX / 2 - 1 loop
                if i < status.active_voices then  
                    r_in.sample_in_left(i) <= sample_in(2 * i);
                    r_in.sample_in_right(i) <= sample_in(2 * i + 1);
                    r_in.ctrl_left(i) <= ctrl_in(2 * i);
                    r_in.ctrl_right(i) <= ctrl_in(2 * i + 1);
                    r_in.voice_enable_left(i) <= osc_inputs(2 * i).enable;
                    r_in.voice_enable_right(i) <= osc_inputs(2 * i + 1).enable;
                    r_in.envelope_active_left(i) <= envelope_active(2 * i);
                    r_in.envelope_active_right(i) <= envelope_active(2 * i + 1);
                end if;
            end loop;
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
