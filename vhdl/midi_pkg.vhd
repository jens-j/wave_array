library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package midi_pkg is

    subtype t_midi_word is std_logic_vector(6 downto 0);
    subtype t_midi_dword is std_logic_vector(13 downto 0);

    type t_midi_note is (C, Db, D, Eb, E, F, Gb, G, Ab, A, Bb);
    subtype t_midi_octave is integer range 0 to 10; -- Corresponds with octaves -1 to 9 (C-1 to G9)

    type t_midi_voice is record
        enable                  : std_logic;
        change                  : std_logic; -- pulse high upon change
        note                    : t_midi_note;
        octave                  : t_midi_octave;
        -- velocity                : t_midi_word;
        -- bend                    : t_midi_dword;
    end record;

    constant MIDI_VOICE_MSG_OFF             : t_midi_word := 7x"08";
    constant MIDI_VOICE_MSG_ON              : t_midi_word := 7x"09";
    constant MIDI_VOICE_MSG_POLY_PRESS      : t_midi_word := 7x"0A";
    constant MIDI_VOICE_MSG_CONTROL         : t_midi_word := 7x"0B";
    constant MIDI_VOICE_MSG_PROGRAM         : t_midi_word := 7x"0C";
    constant MIDI_VOICE_MSG_CH_PRESS        : t_midi_word := 7x"0D";
    constant MIDI_VOICE_MSG_BEND            : t_midi_word := 7x"0E";

    constant MIDI_CH_MODE_MSG_SOUND_OFF     : t_midi_word := 7x"78";
    constant MIDI_CH_MODE_MSG_RESET         : t_midi_word := 7x"79";
    constant MIDI_CH_MODE_MSG_LOCAL         : t_midi_word := 7x"7A";
    constant MIDI_CH_MODE_MSG_NOTES_OFF     : t_midi_word := 7x"7B";
    constant MIDI_CH_MODE_MSG_OMNI_OFF      : t_midi_word := 7x"7C";
    constant MIDI_CH_MODE_MSG_OMNI_ON       : t_midi_word := 7x"7D";
    constant MIDI_CH_MODE_MSG_MONO          : t_midi_word := 7x"7E";
    constant MIDI_CH_MODE_MSG_POLY          : t_midi_word := 7x"7F";

end package;
