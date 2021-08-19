library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_textio.all;
use ieee.numeric_std.all;


entity midi_reader is
    generic (
        file_name               : string := "midi.data"
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        full                    : in  std_logic;
        write_enable            : out std_logic;
        data                    : out std_logic_vector(7 downto 0)
    );
end entity;

architecture arch of midi_reader is

begin

    parse_file : process

        -- file input_file           : text;
        -- file input_file           : text open read_mode is "midi.txt";
        file input_file           : text is in file_name;
        variable line_in          : line;
        variable midi_byte        : std_logic_vector(7 downto 0);
        variable hread_success    : boolean;

    begin

        write_enable <= '0';
        data <= (others => '0');

        -- file_open(input_file, "midi.txt", read_mode);

        report "start";

        -- wait until reset = '1';
        wait until reset = '0';

        while not endfile(input_file) loop

            readline(input_file, line_in);

            -- for i in 0 to 2 loop
            -- while line_in'length > 0 loop
            loop

                -- wait until full = '0';

                hread(line_in, midi_byte, hread_success);
                report "read byte "
                    & integer'image(to_integer(unsigned(midi_byte)));
                report boolean'image(hread_success);
                    -- & boolean'image(hread_success));

                if not hread_success then
                    exit;
                end if;

                wait until rising_edge(clk);
                write_enable <= '1';
                data <= midi_byte;
                wait until rising_edge(clk);
                write_enable <= '0';

            end loop;
        end loop;

        report "end of file";
        -- file_close(input_file);

    end process;
end architecture;
