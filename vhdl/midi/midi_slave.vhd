library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;


entity midi_slave is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        uart_rx                 : in  std_logic;
        midi_channel            : in  std_logic_vector(3 downto 0);
        envelope_active         : in  std_logic_vector(N_VOICES - 1 downto 0); 
        voices                  : out t_voice_array(0 to N_VOICES - 1);
        status_byte             : out t_byte
    );
end entity;


architecture arch of midi_slave is

    type t_state is (idle, parse_note, find_active_voice, find_free_voice, find_released_voice, steal_voice, 
        find_min_max_0, find_min_max_1, voice_on_0, voice_on_1, voice_off_0, voice_off_1);

    type t_midi_slave_reg is record
        state                   : t_state;
        next_state              : t_state;
        voices                  : t_voice_array(0 to N_VOICES - 1);
        voice_select            : integer range 0 to N_VOICES - 1;
        octave                  : t_midi_octave;
        midi_number             : t_midi_number;
        midi_key                : t_midi_number; -- conversion buffer from midi note to t_midi_key
        midi_velocity           : t_midi_word;
        midi_command            : std_logic_vector(3 downto 0);
        table_velocity          : t_osc_phase;
        lowest_note             : t_midi_number;
        lowest_voice            : integer range 0 to N_VOICES - 1;
        highest_note            : t_midi_number;
        highest_voice           : integer range 0 to N_VOICES - 1;
    end record;

    constant REG_INIT : t_midi_slave_reg := (
        state                   => idle,
        next_state              => idle,
        voices                  => (others => MIDI_VOICE_INIT),
        voice_select            => 0,
        octave                  => 0,
        midi_number             => 0,
        midi_key                => 0,
        midi_velocity           => (others => '0'),
        midi_command            => (others => '0'),
        table_velocity          => (others => '0'),
        lowest_note             => 127,
        lowest_voice            => 0,
        highest_note            => 0,
        highest_voice           => 0
    );

    -- Register.
    signal r, r_in              : t_midi_slave_reg;

    signal midi_message_s       : t_midi_message;
    signal message_valid_s      : std_logic;
    signal s_voice_enable       : std_logic_vector(N_VOICES - 1 downto 0);

begin

    midi_receiver : entity midi.midi_receiver
    port map (
        clk                     => clk,
        reset                   => reset,
        uart_rx                 => uart_rx,
        midi_channel            => midi_channel,
        midi_message            => midi_message_s,
        message_valid           => message_valid_s
    );


    combinatorial : process (r, message_valid_s, midi_message_s, s_voice_enable, envelope_active)
        variable v_enable : std_logic;
    begin

        -- Default register input.
        r_in        <= r;

        -- Outputs.
        voices <= r.voices;
        status_byte <= midi_message_s.status_byte;

        for i in 0 to N_VOICES - 1 loop
            r_in.voices(i).change <= '0';
            s_voice_enable(i) <= r.voices(i).enable;
        end loop;     

        case (r.state) is

            when idle =>
                if message_valid_s = '1' then

                    case (midi_message_s.status_byte(7 downto 4)) is
                        when MIDI_VOICE_MSG_ON => r_in.state <= voice_on_0;
                        when MIDI_VOICE_MSG_OFF => r_in.state <= voice_off_0;
                        when others => r_in.state <= idle;
                    end case;

                    -- with midi_message_s.status_byte(7 downto 4) select r_in.state <=
                    --     voice_on_0 when MIDI_VOICE_MSG_ON,
                    --     voice_off_0 when MIDI_VOICE_MSG_OFF,
                    --     idle when others;

                    r_in.octave <= -1;
                    r_in.voice_select <= 0;
                    r_in.midi_command <= midi_message_s.status_byte(7 downto 4);
                    r_in.midi_velocity <= midi_message_s.data(1)(6 downto 0);
                    r_in.midi_number <= to_integer(unsigned(midi_message_s.data(0)(6 downto 0)));
                    r_in.midi_key <= to_integer(unsigned(midi_message_s.data(0)(6 downto 0))); -- Convert to octave + key later.
                end if;

            -- First check if the note is already playing, otherwise try to find a free voice.
            when voice_on_0 =>
                r_in.next_state <= voice_on_1;
                r_in.state <= parse_note;

            -- Assign new note.
            when voice_on_1 =>
                v_enable := '0' when r.midi_velocity = (0 to 6 => '0') else '1';
                r_in.voices(r.voice_select) <= (v_enable, '1', (r.midi_number, r.midi_key, r.octave), r.midi_velocity);

                -- Update lowest and highest notes and voices.
                if r.midi_number < r.lowest_note then 
                    r_in.lowest_voice <= r.voice_select;
                    r_in.lowest_note <= r.midi_number;
                end if;
                if r.midi_number > r.highest_note then 
                    r_in.highest_voice <= r.voice_select;
                    r_in.highest_note <= r.midi_number;
                end if; 

                r_in.state <= idle;

            when voice_off_0 =>
                r_in.next_state <= voice_off_1;
                r_in.state <= parse_note;

            when voice_off_1 =>
                r_in.voices(r.voice_select) <= ('0', '1', (r.midi_number, r.midi_key, r.octave), (others => '0'));

                -- Always run the min max search when a note is released. Even when there are no active notes, 
                -- this at least resets the min and max values.
                r_in.state <= find_min_max_0;
                r_in.next_state <= idle; 

            -- Find voice playing a certain voice (or last played).
            when find_active_voice =>

                if r.voices(r.voice_select).note.number = r.midi_number then
                    r_in.state <= r.next_state;
                elsif r.voice_select = N_VOICES - 1 then
                    if r.midi_command = MIDI_VOICE_MSG_ON then
                        r_in.voice_select <= 0;
                        r_in.state <= find_free_voice;
                    else
                        r_in.state <= idle; -- Note not found in active voices.
                    end if;
                else
                    r_in.voice_select <= r.voice_select + 1;
                end if;

            -- Find first inactive voice (envelope finished).
            when find_free_voice =>
                if envelope_active(r.voice_select) = '0' then
                    r_in.state <= r.next_state;
                elsif r.voice_select = N_VOICES - 1 then
                    r_in.voice_select <= 0;
                    r_in.state <= find_released_voice; -- No free voices.
                else
                    r_in.voice_select <= r.voice_select + 1;
                end if;   

            -- Find first unused voice (note released).
            when find_released_voice =>
                if r.voices(r.voice_select).enable = '0' then
                    r_in.state <= r.next_state;
                elsif r.voice_select = N_VOICES - 1 then
                    r_in.voice_select <= 0;
                    r_in.state <= steal_voice; -- No free voices.
                else
                    r_in.voice_select <= r.voice_select + 1;
                end if;

            -- Loop over all voices and replace the first active voice that is not the lowest or highest note.
            when steal_voice =>
                
                if s_voice_enable(r.voice_select) = '1' 
                        and r.voice_select /= r.lowest_voice and r.voice_select /= r.highest_voice then 
                    
                    r_in.state <= voice_on_1;
                
                elsif r.voice_select < N_VOICES then 
                    r_in.voice_select <= r.voice_select + 1;
                else 
                    r_in.state <= idle; -- This should never happen
                end if;

            -- Translate midi note number to note + octave.
            when parse_note =>
                if r.midi_key > 11 then
                    r_in.octave <= r.octave + 1;
                    r_in.midi_key <= r.midi_key - 12;
                else
                    r_in.state <= find_active_voice;
                end if;
            
            when find_min_max_0 =>
                r_in.lowest_note <= 127;
                r_in.highest_note <= 0;
                r_in.lowest_voice <= 0;
                r_in.highest_voice <= 0;
                r_in.voice_select <= 0;
                if s_voice_enable = (N_VOICES - 1 downto 0 => '0') then 
                    r_in.state <= idle;
                else 
                    r_in.state <= find_min_max_1;
                end if;

            -- find the highest and lowest enabled note.
            when find_min_max_1 =>

                if r.voices(r.voice_select).enable = '1' then 
                    if r.voices(r.voice_select).note.number < r.lowest_note then 
                        r_in.lowest_note <= r.voices(r.voice_select).note.number;
                        r_in.lowest_voice <= r.voice_select;
                    end if;
                    if r.voices(r.voice_select).note.number > r.highest_note then 
                        r_in.highest_note <= r.voices(r.voice_select).note.number;
                        r_in.highest_voice <= r.voice_select;
                    end if;
                end if;

                if r.voice_select = N_VOICES - 1 then 
                    r_in.state <= r.next_state;
                else 
                    r_in.voice_select <= r.voice_select + 1;
                end if;

        end case;

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
