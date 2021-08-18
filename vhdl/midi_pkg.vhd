library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package midi_pkg is

    subtype t_byte is std_logic_vector(7 downto 0);
    type t_byte_array is array (integer range <>) of t_byte;
    subtype t_midi_word is std_logic_vector(6 downto 0);
    subtype t_midi_dword is std_logic_vector(13 downto 0);

    subtype t_midi_note is integer range 0 to 11; -- C, C#, D, D#, E, F, F#, G, G#, A, A#, B;
    subtype t_midi_octave is integer range 0 to 10; -- Corresponds with octaves -1 to 9 (C-1 to G9)

    type t_midi_voice is record
        enable                  : std_logic;
        change                  : std_logic; -- pulse high upon change
        note                    : t_midi_note;
        octave                  : t_midi_octave;
        -- velocity                : t_midi_word;
        -- bend                    : t_midi_dword;
    end record;

    type t_midi_message is record
        status_byte             : t_byte;
        data                    : t_byte_array(0 to 1);
    end record;

    type t_voice_array is array (integer range <>) of t_midi_voice;

    constant MIDI_BAUD                      : integer := 31250;

    -- Midi voice message opcodes.
    constant MIDI_VOICE_MSG_OFF             : std_logic_vector(3 downto 0) := x"8";
    constant MIDI_VOICE_MSG_ON              : std_logic_vector(3 downto 0) := x"9";
    constant MIDI_VOICE_MSG_POLY_PRESS      : std_logic_vector(3 downto 0) := x"A";
    constant MIDI_VOICE_MSG_CONTROL         : std_logic_vector(3 downto 0) := x"B";
    constant MIDI_VOICE_MSG_PROGRAM         : std_logic_vector(3 downto 0) := x"C";
    constant MIDI_VOICE_MSG_CH_PRESS        : std_logic_vector(3 downto 0) := x"D";
    constant MIDI_VOICE_MSG_BEND            : std_logic_vector(3 downto 0) := x"E";

    -- Midi channel message opcodes.
    constant MIDI_CH_MODE_MSG_SOUND_OFF     : t_midi_word := 7x"78";
    constant MIDI_CH_MODE_MSG_RESET         : t_midi_word := 7x"79";
    constant MIDI_CH_MODE_MSG_LOCAL         : t_midi_word := 7x"7A";
    constant MIDI_CH_MODE_MSG_NOTES_OFF     : t_midi_word := 7x"7B";
    constant MIDI_CH_MODE_MSG_OMNI_OFF      : t_midi_word := 7x"7C";
    constant MIDI_CH_MODE_MSG_OMNI_ON       : t_midi_word := 7x"7D";
    constant MIDI_CH_MODE_MSG_MONO          : t_midi_word := 7x"7E";
    constant MIDI_CH_MODE_MSG_POLY          : t_midi_word := 7x"7F";

    -- Midi system message opcodes
    constant MIDI_SYS_CLOCK                 : t_byte := x"F8";


end package;
