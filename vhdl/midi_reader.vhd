library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity midi_reader is
    generic (
        FILENAME                : string
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

    procedure string_init (string_inout : inout string) is
    begin
        for i in string_inout'range loop
            string_inout(i) := ' ';
        end loop;
    end procedure string_init;


begin

    parse_file : process

        file input_file             : text;
        variable v_line_in          : line;
        variable v_command          : string(1 to 4); -- Strings cannot start at 0.
        variable v_string_length    : integer :=-1;
        variable v_wait_time        : integer;
        variable v_midi_byte        : std_logic_vector(7 downto 0);
        variable v_hread_success    : boolean;

    begin

        write_enable <= '0';
        data <= (others => '0');

        report "start";
        file_open(input_file, FILENAME,  read_mode);

        -- wait until reset = '1';
        wait until reset = '0';

        while not endfile(input_file) loop

            readline(input_file, v_line_in);
            report "line read: " & integer'image(v_line_in'length);
            next when v_line_in'length = 0;  -- Skip empty lines

            --string_init(v_command);
            string_read(v_line_in, v_command, v_string_length);

            -- Skip comment lines (strings start at 1).
            if v_command(1) = '#' then
                next;
            end if;

            if v_command = "wait" then

                -- Read wait time in ms from line
                read(v_line_in, v_wait_time, v_hread_success);
                report "wait for " & integer'image(v_wait_time) & " ms";
                wait for v_wait_time * 1 ms;

            elsif v_command = "send" then

                loop
                    -- Wait until the midi uart fifo has room
                    wait until clk'event and full = '0'; -- This does not work in modelsim

                    hread(v_line_in, v_midi_byte, v_hread_success);

                    if not v_hread_success then
                        exit;
                    end if;

                    report "send byte " & integer'image(to_integer(unsigned(v_midi_byte)));

                    -- report boolean'image(v_hread_success);
                        -- & boolean'image(v_hread_success));

                    wait until rising_edge(clk);
                    write_enable <= '1';
                    data <= v_midi_byte;
                    wait until rising_edge(clk);
                    write_enable <= '0';

                end loop;

            else
                report "unknown command: " & v_command & ".";
            end if;

        end loop;

        report "end of file";
        file_close(input_file);
        wait;

    end process;
end architecture;
