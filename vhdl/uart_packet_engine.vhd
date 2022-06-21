library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;
use wave.uart_pkg.all;



entity uart_packet_engine is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;

        -- RX fifo interface.
        rx_empty                : in  std_logic;
        rx_read_enable          : out std_logic;
        rx_data                 : in  std_logic_vector(7 downto 0);

        -- TX fifo interface.
        tx_write_enable         : out std_logic;
        tx_data                 : out std_logic_vector(7 downto 0);

        -- Register file interface.
        register_output         : in  t_register_output;
        register_input          : out t_register_input;

        -- Error flags.
        timeout                 : out std_logic
    );
end entity;

architecture arch of uart_packet_engine is

    -- Make watchdog timer wide enough for 1 second.
    constant WDT_WIDTH : integer := integer(ceil(log2(real(SYS_FREQ))));

    type t_state is (idle, read_word, read_reg_0, read_reg_1, read_reg_2,
        read_reg_3, write_reg_0, write_reg_1, write_reg_2);

    type t_packet_engine_reg is record
        state                   : t_state;
        next_state              : t_state;
        tx_write_enable         : std_logic;
        tx_data                 : std_logic_vector(7 downto 0);
        register_input          : t_register_input;
        timeout                 : std_logic;
        counter                 : integer range 0 to 3;
        word_buffer             : std_logic_vector(31 downto 0);
        address                 : unsigned(31 downto 0);
        watchdog                : unsigned(WDT_WIDTH downto 0);
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state                   => idle,
        next_state              => idle,
        tx_write_enable         => '0',
        tx_data                 => (others => '0'),
        register_input          => ('0', '0', (others => '0'), (others => '0')),
        timeout                 => '0',
        counter                 => 0,
        word_buffer             => (others => '0'),
        address                 => (others => '0'),
        watchdog                => (others => '0')
    );

    signal r, r_in              : t_packet_engine_reg;

begin

    -- Connect output registers.
    tx_write_enable             <= r.tx_write_enable;
    tx_data                     <= r.tx_data;
    timeout                     <= r.timeout;
    register_input              <= r.register_input;

    comb_process : process (r, rx_empty, rx_data, register_output)
    begin

        r_in <= r;
        r_in.tx_write_enable <= '0';
        r_in.tx_data <= (others => '0');
        r_in.register_input <= ('0', '0', (others => '0'), (others => '0'));
        r_in.timeout <= '0';

        -- This output is not registered to avoid a delay cycle when reading bytes from the fifo.
        rx_read_enable <= '0';

        -- Wait for a new opcode to appear at the rx fifo output.
        if r.state = idle then

            r_in.word_buffer <= (others => '0');
            r_in.watchdog <= (others => '0');

            if rx_empty = '0' then

                rx_read_enable <= '1';

                if rx_data = UART_READ_REQ then
                    r_in.counter <= 3;
                    r_in.next_state <= read_reg_0;
                    r_in.state <= read_word; -- Read 4 byte address.

                elsif rx_data = UART_WRITE_REQ then
                    r_in.counter <= 3;
                    r_in.next_state <= write_reg_0;
                    r_in.state <= read_word; -- Read 4 byte address.
                end if;
            end if;

        -- Read a predefined number of bytes MSB first from the rx fifo into the word buffer.
        elsif r.state = read_word then
            if rx_empty = '0' then

                rx_read_enable <= '1';
                r_in.word_buffer((r.counter + 1) * 8 - 1 downto r.counter * 8) <= rx_data;

                if r.counter > 0 then
                    r_in.counter <= r.counter - 1;
                else
                    r_in.state <= r.next_state;
                end if;
            end if;

        -- Issue a read to the register file and write the reply header to the tx fifo
        elsif r.state = read_reg_0 then
            r_in.register_input.read_enable <= '1';
            r_in.register_input.address <= unsigned(r.word_buffer);


            r_in.state <= read_reg_1;

        -- Register the read result and write reply header
        elsif r.state = read_reg_1 then
            if register_output.valid = '1' then
                r_in.tx_write_enable <= '1';

                if register_output.fault = '1' then
                    r_in.tx_data <= UART_ERROR_REP;
                    r_in.state <= idle;
                else
                    r_in.tx_data <= UART_READ_REP;
                    r_in.word_buffer(15 downto 0) <= register_output.read_data; -- Buffer read data.
                    r_in.state <= read_reg_2;
                end if;
            end if;

        -- Write the msb of the read data to the tx fifo.
        elsif r.state = read_reg_2 then
            r_in.tx_write_enable <= '1';
            r_in.tx_data <= r.word_buffer(15 downto 8);
            r_in.state <= read_reg_3;

        -- Write the lsb of the read data to the tx fifo.
        elsif r.state = read_reg_3 then
            r_in.tx_write_enable <= '1';
            r_in.tx_data <= r.word_buffer(7 downto 0);
            r_in.state <= idle;

        -- Read the 2 byte write data from the rx fifo.
        elsif r.state = write_reg_0 then
            r_in.address <= unsigned(r.word_buffer);
            r_in.counter <= 1;
            r_in.next_state <= write_reg_1;
            r_in.state <= read_word;

        -- Issue a write to the register file and write the reply header to the tx fifo
        elsif r.state = write_reg_1 then
            r_in.register_input.write_enable <= '1';
            r_in.register_input.write_data <= r.word_buffer(15 downto 0);
            r_in.register_input.address <= r.address;
            r_in.state <= write_reg_2;

        -- Send ack or error response.
        elsif r.state = write_reg_2 then
            if register_output.valid = '1' then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= UART_ERROR_REP when register_output.fault = '1' else UART_WRITE_REP;
                r_in.state <= idle;
            end if;
        end if;

        -- If a message takes more than a second an error response is send the state is set to idle.
        if r.state /= idle then
            if r.watchdog(WDT_WIDTH) = '0' then
                r_in.watchdog <= r.watchdog + 1;
            else
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= UART_ERROR_REP;
                r_in.timeout <= '1'; -- Strobe error flag.
                r_in.state <= idle;
            end if;
        end if;

    end process;

    reg_process : process (clk)
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
