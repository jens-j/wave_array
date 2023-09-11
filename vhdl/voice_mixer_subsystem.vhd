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
        next_sample             : in  std_logic;
        sample_in               : in  t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        ctrl_in                 : in  t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
        sample_out              : out t_stereo_sample
    );
end entity;


architecture arch of voice_mixer_subsystem is

    constant ACTIVE_VOICES_DEFAULT : t_active_voices_array := calculate_active_voices('0');
    constant ACTIVE_VOICES_BINAURAL : t_active_voices_array := calculate_active_voices('1');
    

    type t_mixer_subsys_reg is record 
        n_inputs                : integer range 1 to POLYPHONY_MAX;
        sample_in_left          : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
        sample_in_right         : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
    end record;

    constant REG_INIT : t_mixer_subsys_reg := (
        n_inputs                => POLYPHONY_MAX,
        sample_in_left          => (others => (others => '0')),
        sample_in_right         => (others => (others => '0'))
    );

    signal s_sample_in_left     : t_mono_sample_array(0 to POLYPHONY_MAX - 1); 
    signal s_sample_in_right    : t_mono_sample_array(0 to POLYPHONY_MAX - 1);

    signal r, r_in              : t_mixer_subsys_reg;

begin 

    voice_mixer_left : entity wave.voice_mixer 
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        n_inputs                => r.n_inputs,
        ctrl_in                 => ctrl_in,
        sample_in               => s_sample_in_left,
        sample_out              => sample_out(0)
    );

    voice_mixer_right : entity wave.voice_mixer 
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        n_inputs                => r.n_inputs,
        ctrl_in                 => ctrl_in,
        sample_in               => s_sample_in_right,
        sample_out              => sample_out(1)
    );

    -- Mux input samples depending on whether binaural mode is enabled and the number of available voices.
    combinatorial : process (r, config, next_sample, ctrl_in, sample_in)
    begin

        r_in <= r;
        
        -- Connect output registers to voice mixers.
        s_sample_in_left <= r.sample_in_left;
        s_sample_in_right <= r.sample_in_right;

        r_in.n_inputs <= config.polyphony;

        -- Assign the same samples to the left and right channel.
        if config.binaural_enable = '0' then 
            
            for i in 0 to POLYPHONY_MAX - 1 loop
                if i < config.active_voices then  
                    r_in.sample_in_left(i) <= sample_in(i);
                    r_in.sample_in_right(i) <= sample_in(i);
                else 
                    r_in.sample_in_left(i) <= (others => '0');
                    r_in.sample_in_right(i) <= (others => '0');
                end if;
            end loop;
        
        -- In binaural mode, left and right are separate. The input samples are interleaved.
        else 
            for i in 0 to POLYPHONY_MAX / 2 - 1 loop
                if i < config.active_voices then  
                    r_in.sample_in_left(i) <= sample_in(2 * i);
                else 
                    r_in.sample_in_left(i) <= (others => '0');
                end if;
            end loop;

            for i in 0 to POLYPHONY_MAX / 2 - 1 loop
                if i < config.active_voices then  
                    r_in.sample_in_right(i) <= sample_in(2 * i + 1);
                else 
                    r_in.sample_in_left(i) <= (others => '0');
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
