library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;


entity osc_controller is
    port (
        clk                     : std_logic;
        reset                   : std_logic;
        config                  : in  t_config;
        status                  : in  t_status;
        next_sample             : in  std_logic; -- Next sample trigger.
        voices                  : in  t_voice_array(0 to POLYPHONY_MAX - 1);
        osc_inputs              : out t_osc_input_array(0 to POLYPHONY_MAX - 1)
    );
end entity;

architecture arch of osc_controller is

    type t_state is (idle, running);

    type t_oscillator_reg is record
        state                   : t_state;
        voices                  : t_voice_array(0 to POLYPHONY_MAX - 1);
        osc_counter             : integer range 0 to POLYPHONY_MAX - 1;
        voice_counter           : integer range 0 to POLYPHONY_MAX - 1;  
        group_counter           : integer range 0 to 1;
        osc_inputs              : t_osc_input_array(0 to POLYPHONY_MAX - 1);
        osc_inputs_buffer       : t_osc_input_array(0 to POLYPHONY_MAX - 1);
    end record;

    constant REG_INIT : t_oscillator_reg := (
        state                   => idle,
        voices                  => (others => MIDI_VOICE_INIT),
        osc_counter             => 0,
        voice_counter           => 0,
        group_counter           => 1,
        osc_inputs              => (others => ('0', (others => '0'))),
        osc_inputs_buffer       => (others => ('0', (others => '0')))
    );

    signal r, r_in : t_oscillator_reg := REG_INIT;

begin

    osc_inputs <= r.osc_inputs;

    combinatorial : process (r, config, status, next_sample, voices)
        variable v_enable : std_logic;
        variable v_velocity : t_osc_phase;
    begin

        r_in <= r;

        if r.state = idle then
            if next_sample = '1' then
                r_in.osc_inputs <= r.osc_inputs_buffer;
                r_in.osc_inputs_buffer <= (others => ('0', (others => '0')));
                r_in.voices <= voices;
                r_in.osc_counter <= 0;
                r_in.voice_counter <= 0; 
                r_in.group_counter <= 0; 
                r_in.state <= running;
            end if;

        -- Assign velocities to oscillators. Mapping depends on unison and binaural settings.
        elsif r.state = running then

            v_enable := '0';
            v_velocity := (others => '0');

            -- Convert midi note to table velocity.
            -- Use the potentiometer as frame position input.
            v_enable := r.voices(r.voice_counter).enable;
            v_velocity := shift_right(BASE_OCT_VELOCITIES(r.voices(r.voice_counter).note.key),
                                      9 - r.voices(r.voice_counter).note.octave);

            r_in.osc_inputs_buffer(r.osc_counter) <= (v_enable, v_velocity);

            -- Iterate over voices. Double in binaural mode
            if config.binaural_enable = '0' or (config.binaural_enable = '1' and r.group_counter = 1) then 

                r_in.group_counter <= 0;

                if r.voice_counter < status.polyphony - 1 then
                    r_in.osc_counter <= r.osc_counter + 1;
                    r_in.voice_counter <= r.voice_counter + 1;
                else
                    r_in.state <= idle;
                end if;
            else 
                r_in.osc_counter <= r.osc_counter + 1;
                r_in.group_counter <= r.group_counter + 1;
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
