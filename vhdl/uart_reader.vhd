library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xil_defaultlib;

library wave;
use wave.wave_array_pkg.all;
use wave.uart_pkg.all;


entity uart_reader is
    generic (
        FILENAME                : string
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;

        -- UART rx fifo interface.
        empty                   : in  std_logic;
        read_enable             : out std_logic;
        read_data               : in  std_logic_vector(7 downto 0);

        -- UART tx fifo interface.
        full                    : in  std_logic;
        write_enable            : out std_logic;
        write_data              : out std_logic_vector(7 downto 0)
    );
end entity;

architecture arch of uart_reader is

    type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    type t_data_array is array (0 to UART_MAX_BURST - 1) of std_logic_vector(15 downto 0);

    procedure write_packet (
        signal clk                  : in  std_logic;
        signal write_enable         : out std_logic;
        signal write_data           : out std_logic_vector(7 downto 0);
        variable v_serial_packet    : in  std_logic_vector(2119 downto 0);
        variable v_serial_length    : in  integer range 1 to 265 -- In bytes.
        ) is
    begin
        for i in v_serial_length - 1 downto 0 loop
            wait until rising_edge(clk);
            write_enable <= '1';
            write_data <= v_serial_packet((i + 1) * 8 - 1 downto i * 8);
        end loop;
        wait until rising_edge(clk);
        write_enable <= '0';
    end procedure;

    procedure read_word (
        signal clk                  : in  std_logic;
        signal empty                : in  std_logic;
        signal read_enable          : out std_logic;
        signal read_data            : in  std_logic_vector(7 downto 0);
        variable length             : in  integer;
        variable read_buffer        : out std_logic_vector(31 downto 0)
        ) is
        variable v_count            : integer;
    begin
        v_count := length - 1;
        read_buffer := (31 downto 0 => '0');
        while v_count >= 0 loop
            read_enable <= '0';
            wait until empty = '0';
            read_enable <= '1';
            read_buffer((v_count + 1) * 8 - 1 downto v_count * 8) := read_data;
            v_count := v_count - 1;
            wait until rising_edge(clk);
        end loop;

        wait until rising_edge(clk);
        read_enable <= '0';

    end procedure;

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
        variable v_command          : string(1 to 6); -- Strings cannot start at 0.
        variable v_string_length    : integer := 0;
        variable v_address          : std_logic_vector(31 downto 0);
        variable v_length           : std_logic_vector(31 downto 0);
        variable v_write_data       : std_logic_vector(16 * SDRAM_MAX_BURST - 1 downto 0);
        variable v_serial_packet    : std_logic_vector(2119 downto 0);
        variable v_byte_packet      : t_byte_array(264 downto 0);
        variable v_serial_length    : integer range 1 to 265;
        variable v_burst_length     : std_logic_vector(31 downto 0);
        variable v_reply_opcode     : std_logic_vector(31 downto 0);
        variable v_wait_time        : integer;
        variable v_hread_success    : boolean;
        variable v_read_data        : std_logic_vector(31 downto 0);
        variable v_hexfile          : string(1 to 120);
        variable v_

    begin

        read_enable <= '0';
        write_enable <= '0';

        file_open(input_file, FILENAME,  read_mode);

        wait until reset = '0';
        wait for 1 us; -- Wait for pll lock.

        while not endfile(input_file) loop

            string_init(v_command); -- Initialize command string to spaces.

            readline(input_file, v_line_in);
            next when v_line_in'length = 0;  -- Skip empty lines
            string_read(v_line_in, v_command, v_string_length);

            -- Skip comment lines (strings start at 1).
            next when v_command(1) = '#';

            if v_command = "wait  " then
                -- Read wait time in ms from line
                read(v_line_in, v_wait_time, v_hread_success);
                report "wait " & integer'image(v_wait_time) & " ms";
                wait for v_wait_time * 1 ms;

            elsif v_command = "read  " then
                hread(v_line_in, v_address);
                v_serial_length := 5;
                v_serial_packet := (2119 downto 8 * v_serial_length => '0') & UART_READ_REQ & v_address;
                write_packet(clk, write_enable, write_data, v_serial_packet, v_serial_length);

                v_serial_length := 1;
                read_word(clk, empty, read_enable, read_data, v_serial_length, v_reply_opcode);
                if v_reply_opcode /= x"000000" & UART_READ_REP then
                    report "received "
                        & integer'image(to_integer(unsigned(v_reply_opcode(7 downto 0))));
                else
                    v_serial_length := 2;
                    read_word(clk, empty, read_enable, read_data, v_serial_length,
                        v_read_data(31 downto 0));
                    report "read = " & integer'image(to_integer(unsigned(v_read_data(15 downto 0))));
                end if;

            elsif v_command = "write " then
                hread(v_line_in, v_address);
                hread(v_line_in, v_write_data(15 downto 0));
                v_serial_length := 7;
                v_serial_packet := (2119 downto 8 * v_serial_length => '0') & UART_WRITE_REQ
                    & v_address & v_write_data(15 downto 0);
                write_packet(clk, write_enable, write_data, v_serial_packet, v_serial_length);

                v_serial_length := 1;
                read_word(clk, empty, read_enable, read_data, v_serial_length, v_reply_opcode);
                if v_reply_opcode /= x"000000" & UART_WRITE_REP then
                    report "received "
                        & integer'image(to_integer(unsigned(v_reply_opcode(7 downto 0))));
                end if;

            elsif v_command = "readb " then
                hread(v_line_in, v_address);
                hread(v_line_in, v_burst_length);
                v_serial_length := 9;
                v_serial_packet := (2119 downto 8 * v_serial_length => '0')
                    & UART_READ_BLOCK_REQ & v_address & v_burst_length;
                write_packet(clk, write_enable, write_data, v_serial_packet, v_serial_length);

                v_serial_length := 1;
                read_word(clk, empty, read_enable, read_data, v_serial_length, v_reply_opcode);
                if v_reply_opcode /= x"000000" & UART_READ_BLOCK_REP then
                    report "received "
                        & integer'image(to_integer(unsigned(v_reply_opcode(7 downto 0))));
                else
                    v_serial_length := 2;

                    report "read block = ";
                    for i in 0 to to_integer(unsigned(v_burst_length)) - 1 loop
                        read_word(clk, empty, read_enable, read_data, v_serial_length, v_read_data);
                        report integer'image(to_integer(unsigned(v_read_data(15 downto 0))));
                    end loop;
                end if;

            elsif v_command = "writeb" then
                hread(v_line_in, v_address);
                sread(v_line_in, v_hexfile);
                hread(v_line_in,
                    v_write_data(16 * to_integer(unsigned(v_burst_length)) - 1 downto 0));
                v_serial_length := 9 + 2 * to_integer(unsigned(v_burst_length));
                v_serial_packet := (2119 downto 8 * v_serial_length => '0')
                    & UART_WRITE_BLOCK_REQ & v_address & v_burst_length
                    & v_write_data(16 * to_integer(unsigned(v_burst_length)) - 1 downto 0);
                write_packet(clk, write_enable, write_data, v_serial_packet, v_serial_length);

                v_serial_length := 1;
                read_word(clk, empty, read_enable, read_data, v_serial_length, v_reply_opcode);
                if v_reply_opcode /= x"000000" & UART_WRITE_BLOCK_REP then
                    report "received "
                        & integer'image(to_integer(unsigned(v_reply_opcode(7 downto 0))));
                end if;
            end if;

        elsif v_command = "writef" then


        end loop;

        report "end of file";
        file_close(input_file);
        wait;

    end process;
end architecture;
