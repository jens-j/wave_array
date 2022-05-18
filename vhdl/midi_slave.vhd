library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;


entity midi_slave is
    generic (
        N_VOICES                : integer
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        uart_rx                 : in  std_logic;
        midi_channel            : in  std_logic_vector(3 downto 0);
        voices                  : out t_voice_array(N_VOICES - 1 downto 0);
        status_byte             : out t_byte
    );
end entity;


architecture arch of midi_slave is

    type t_state is (idle, parse_note, find_free_voice, find_active_voice,
        voice_on_0, voice_on_1, voice_off_0, voice_off_1);

    type t_midi_slave_reg is record
        state                   : t_state;
        next_state              : t_state;
        voice_enable            : std_logic_vector(N_VOICES - 1 downto 0);
        voices                  : t_voice_array(N_VOICES - 1 downto 0);
        voice_select            : integer range 0 to N_VOICES - 1;
        octave                  : t_midi_octave;
        midi_note               : integer range 0 to 127; -- conversion buffer from midi note to t_midi_key
        midi_velocity           : t_midi_word;
        midi_command            : std_logic_vector(3 downto 0);
        table_velocity          : t_osc_phase;
    end record;

    constant REG_INIT : t_midi_slave_reg := (
        state                   => idle,
        next_state              => idle,
        voice_enable            => (others => '0'),
        voices                  => (others => MIDI_VOICE_INIT),
        voice_select            => 0,
        octave                  => 0,
        midi_note               => 0,
        midi_velocity           => (others => '0'),
        midi_command            => (others => '0'),
        table_velocity          => (others => '0')
    );

    -- Register.
    signal r, r_in              : t_midi_slave_reg;

    signal midi_message_s       : t_midi_message;
    signal message_valid_s      : std_logic;

begin

    midi_receiver : entity wave.midi_receiver
    port map (
        clk                     => clk,
        reset                   => reset,
        uart_rx                 => uart_rx,
        midi_channel            => midi_channel,
        midi_message            => midi_message_s,
        message_valid           => message_valid_s
    );


    combinatorial : process (r, message_valid_s, midi_message_s)
        variable v_enable : std_logic;
    begin

        -- Default register input.
        r_in        <= r;

        -- Outputs.
        voices <= r.voices;
        status_byte <= midi_message_s.status_byte;

        for i in 0 to N_VOICES - 1 loop
            r_in.voices(i).change <= '0';
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
                    r_in.midi_note <= to_integer(unsigned(midi_message_s.data(0)(6 downto 0)));
                end if;

            -- First check if the note is already playing, otherwise find an free voice.
            when voice_on_0 =>
                r_in.next_state <= voice_on_1;
                r_in.state <= parse_note;

            -- Find first unused voice.
            when voice_on_1 =>
                v_enable := '0' when r.midi_velocity = (0 to 6 => '0') else '1';
                r_in.voices(r.voice_select) <= (v_enable, '1', (r.midi_note, r.octave), r.midi_velocity);
                r_in.state <= idle;

            when voice_off_0 =>
                r_in.next_state <= voice_off_1;
                r_in.state <= parse_note;

            when voice_off_1 =>
                r_in.voices(r.voice_select) <= ('0', '1', (r.midi_note, r.octave), (others => '0'));
                r_in.state <= idle;

            -- Find first unused voice
            when find_free_voice =>
                if r.voices(r.voice_select).enable = '0' then
                    r_in.state <= r.next_state;
                elsif r.voice_select = N_VOICES - 1 then
                    r_in.state <= idle; -- No free voices.
                else
                    r_in.voice_select <= r.voice_select + 1;
                end if;

            -- Find voice playing a certain voice
            when find_active_voice =>

                if r.voices(r.voice_select).note.key = r.midi_note and
                        r.voices(r.voice_select).note.octave = r.octave then
                    r_in.state <= r.next_state;
                elsif r.voice_select = N_VOICES - 1 then
                    if r.midi_command = MIDI_VOICE_MSG_ON then
                        r_in.state <= find_free_voice;
                        r_in.voice_select <= 0;
                    else
                        r_in.state <= idle; -- Note not found in active voices.
                    end if;
                else
                    r_in.voice_select <= r.voice_select + 1;
                end if;

            -- Translate midi note number to note + octave
            when parse_note =>
                if r.midi_note > 11 then
                    r_in.octave <= r.octave + 1;
                    r_in.midi_note <= r.midi_note - 12;
                else
                    r_in.state <= find_active_voice;
                end if;

            --
            -- when calc_velocity =>
            --     r_in.table_velocity <= shift_right(BASE_OCT_VELOCITIES(r.midi_note), 9 - r.octave);
            --     r_in.state <= find_active_voice;

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
