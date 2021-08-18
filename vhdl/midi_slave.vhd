library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wave_array_pkg.all;
use work.midi_pkg.all;


entity midi_slave is
    generic (
        n_voices                : integer
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        uart_rx                 : in  std_logic;
        midi_channel            : in  std_logic_vector(3 downto 0);
        voices                  : out t_voice_array(n_voices - 1 downto 0)
    );
end entity;


architecture arch of midi_slave is

    type t_state is (idle, parse_note, voice_on_0, voice_on_1, voice_on_2, voice_off_0, voice_off_1);

    type t_midi_slave_reg is record
        state                   : t_state;
        next_state              : t_state;
        voice_enable            : std_logic_vector(n_voices - 1 downto 0);
        voices                  : t_voice_array(n_voices - 1 downto 0);
        voice_select            : integer range 0 to n_voices - 1;
        octave                  : t_midi_octave;
        midi_note               : integer range 0 to 127;
    end record;

    constant VOICE_INIT : t_midi_voice := ('0', '0', 0, 0);

    constant REG_INIT : t_midi_slave_reg := (
        state                   => idle,
        next_state              => idle,
        voice_enable            => (others => '0'),
        voices                  => (others => VOICE_INIT),
        voice_select            => 0,
        octave                  => 0,
        midi_note               => 0
    );

    -- Register.
    signal r, r_in              : t_midi_slave_reg;

    signal midi_message_s       : t_midi_message;
    signal message_valid_s      : std_logic;

begin

    midi_receiver : entity work.midi_receiver
    port map (
        clk                     => clk,
        reset                   => reset,
        uart_rx                 => uart_rx,
        midi_channel            => midi_channel,
        midi_message            => midi_message_s,
        message_valid           => message_valid_s
    );


    combinatorial : process (r, message_valid_s, midi_message_s)
    begin

        -- Default register input.
        r_in        <= r;

        -- Outputs.
        voices <= r.voices;


        for i in 0 to n_voices - 1 loop
            r_in.voices(i).change <= '0';
        end loop;


        case(r.state) is

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

                    r_in.octave <= 10;
                    r_in.voice_select <= 0;
                    r_in.midi_note <=
                        to_integer(unsigned(midi_message_s.data(0)(6 downto 0)));
                end if;

            -- Play note if an empty voice is available.
            when voice_on_0 =>
                if r.voice_enable /= (n_voices - 1 downto 0 => '1') then
                    r_in.next_state <= voice_on_1;
                    r_in.state <= parse_note;
                else
                    r_in.state <= idle;
                end if;

            -- Find first unused voice.
            when voice_on_1 =>
                if r.voices(r.voice_select).enable = '0' then
                    r_in.state <= voice_on_2;
                elsif r.voice_select = n_voices - 1 then
                    r_in.state <= idle;
                else
                    r_in.voice_select <= r.voice_select + 1;
                end if;

            -- Write voice output
            when voice_on_2 =>
                r_in.voices(r.voice_select) <= ('1', '1', r.midi_note, r.octave);
                r_in.state <= idle;

            when voice_off_0 =>
                r_in.next_state <= voice_off_1;
                r_in.state <= parse_note;

            when voice_off_1 =>
                if r.voices(r.voice_select).note = r.midi_note then
                    r_in.voices(r.voice_select) <= ('0', '1', 0, 0);
                end if;
                if r.voice_select < n_voices - 1 then
                    r_in.voice_select <= r.voice_select + 1;
                else
                    r_in.state <= idle;
                end if;

            -- Translate midi note number to note + octave
            when parse_note =>
                if r.midi_note > 11 then
                    r_in.octave <= r.octave - 1;
                    r_in.midi_note <= r.midi_note - 12;
                else
                    r_in.state <= r.next_state;
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
