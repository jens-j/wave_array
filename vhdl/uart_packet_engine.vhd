library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library xil_defaultlib;

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
        register_input          : out t_register_input;
        register_output         : in  t_register_output;

        -- SDRAM interface.
        sdram_input             : out t_sdram_input;
        sdram_output            : in  t_sdram_output;

        -- Debug ports.
        timeout                 : out std_logic;
        uart_state              : out integer;
        uart_count              : out integer;
        fifo_count              : out integer
    );
end entity;

architecture arch of uart_packet_engine is

    -- Make watchdog timer wide enough for 1 second.
    constant WDT_WIDTH : integer := integer(ceil(log2(real(SYS_FREQ))));

    type t_state is (idle, read_word, read_reg_0, read_reg_1, read_reg_2,
        read_reg_3, write_reg_0, write_reg_1, write_reg_2, read_block_0, read_block_1, read_block_2,
        read_block_3, write_block_0, write_block_1, write_block_2, write_block_3);

    type t_packet_engine_reg is record
        state                   : t_state;
        next_state              : t_state;
        tx_write_enable         : std_logic;
        tx_data                 : std_logic_vector(7 downto 0);
        register_input          : t_register_input;
        sdram_read_enable       : std_logic;
        sdram_write_enable      : std_logic;
        sdram_burst_length      : integer range 1 to SDRAM_MAX_BURST;
        sdram_address           : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        timeout                 : std_logic;
        byte_counter            : integer range 0 to 2 * SDRAM_MAX_BURST - 1;
        burst_counter           : integer;
        word_buffer             : std_logic_vector(31 downto 0); -- Buffer used to receive words byte for byte.
        address                 : unsigned(31 downto 0); -- Address field buffer.
        watchdog                : unsigned(WDT_WIDTH downto 0);
        uart_count              : integer range 0 to 2**16 - 1;
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state                   => idle,
        next_state              => idle,
        tx_write_enable         => '0',
        tx_data                 => (others => '0'),
        register_input          => ('0', '0', (others => '0'), (others => '0')),
        sdram_read_enable       => '0',
        sdram_write_enable      => '0',
        sdram_burst_length      => 1,
        sdram_address           => (others => '0'),
        timeout                 => '0',
        byte_counter            => 0,
        burst_counter           => 0,
        word_buffer             => (others => '0'),
        address                 => (others => '0'),
        watchdog                => (others => '0'),
        uart_count              => 0
    );

    signal r, r_in              : t_packet_engine_reg;

    signal s_s2u_fifo_din       : std_logic_vector(15 downto 0);
    signal s_s2u_fifo_wr_en     : std_logic;
    signal s_s2u_fifo_rd_en     : std_logic;
    signal s_s2u_fifo_dout      : std_logic_vector(7 downto 0);
    signal s_s2u_fifo_empty     : std_logic;
    signal s_s2u_fifo_rd_data_count : std_logic_vector(10 downto 0);

    signal s_u2s_fifo_din       : std_logic_vector(7 downto 0);
    signal s_u2s_fifo_wr_en     : std_logic;
    signal s_u2s_fifo_rd_en     : std_logic;
    signal s_u2s_fifo_dout      : std_logic_vector(15 downto 0);
    signal s_u2s_fifo_empty     : std_logic;
    signal s_u2s_fifo_rd_data_count : std_logic_vector(9 downto 0);



begin

    -- 16 bit to 8 bit fifo to buffer SDRAM block data.
    sdram_uart_fifo : entity xil_defaultlib.sdram_uart_fifo_gen
    port map (
        rst                     => reset,
        wr_clk                  => clk,
        rd_clk                  => clk,
        din                     => s_s2u_fifo_din,
        wr_en                   => s_s2u_fifo_wr_en,
        rd_en                   => s_s2u_fifo_rd_en,
        dout                    => s_s2u_fifo_dout,
        full                    => open,
        empty                   => s_s2u_fifo_empty,
        rd_data_count           => s_s2u_fifo_rd_data_count
    );

    -- 8 to 16 bit fifo to buffer UART write data.
    uart_sdram_fifo : entity xil_defaultlib.uart_sdram_fifo_gen
    port map (
        rst                     => reset,
        wr_clk                  => clk,
        rd_clk                  => clk,
        din                     => s_u2s_fifo_din,
        wr_en                   => s_u2s_fifo_wr_en,
        rd_en                   => s_u2s_fifo_rd_en,
        dout                    => s_u2s_fifo_dout,
        full                    => open,
        empty                   => s_u2s_fifo_empty,
        rd_data_count           => s_u2s_fifo_rd_data_count
    );

    -- Connect output registers.
    tx_write_enable             <= r.tx_write_enable;
    tx_data                     <= r.tx_data;
    timeout                     <= r.timeout;
    register_input              <= r.register_input;
    sdram_input.read_enable     <= r.sdram_read_enable;
    sdram_input.write_enable    <= r.sdram_write_enable;
    sdram_input.burst_length    <= r.sdram_burst_length;
    sdram_input.address         <= r.sdram_address;


    -- Connect asymmetric fifo read side to the sdram interface.
    sdram_input.write_data <= s_u2s_fifo_dout;
    s_u2s_fifo_rd_en <= sdram_output.write_req;

    comb_process : process (r, rx_empty, rx_data, register_output, sdram_output, s_s2u_fifo_dout,
        s_s2u_fifo_empty, s_u2s_fifo_rd_data_count, s_s2u_fifo_rd_data_count)

    begin

        r_in <= r;
        r_in.tx_write_enable <= '0';
        r_in.tx_data <= (others => '0');
        r_in.register_input <= ('0', '0', (others => '0'), (others => '0'));
        r_in.sdram_read_enable <= '0';
        r_in.sdram_write_enable <= '0';
        r_in.sdram_burst_length <= 1;
        r_in.sdram_address <= (others => '0');
        r_in.timeout <= '0';

        -- Default fifo inputs.
        s_s2u_fifo_wr_en <= '0';
        s_s2u_fifo_rd_en <= '0';
        s_u2s_fifo_wr_en <= '0';
        s_s2u_fifo_din <= sdram_output.read_data;
        s_u2s_fifo_din <= rx_data;

        -- This output is not registered to avoid a delay cycle when reading bytes from the fifo.
        rx_read_enable <= '0';

        uart_state <= t_state'pos(r.state);
        uart_count <= r.uart_count;
        fifo_count <= to_integer(unsigned(s_s2u_fifo_rd_data_count));

        -- Wait for a new opcode to appear at the rx fifo output.
        if r.state = idle then

            r_in.word_buffer <= (others => '0');
            r_in.watchdog <= (others => '0');

            if rx_empty = '0' then

                rx_read_enable <= '1';

                if rx_data = UART_READ_REQ then
                    r_in.byte_counter <= 3;
                    r_in.next_state <= read_reg_0;
                    r_in.state <= read_word; -- Read 4 byte address.

                elsif rx_data = UART_WRITE_REQ then
                    r_in.byte_counter <= 3;
                    r_in.next_state <= write_reg_0;
                    r_in.state <= read_word; -- Read 4 byte address.

                elsif rx_data = UART_READ_BLOCK_REQ then
                    r_in.byte_counter <= 3;
                    r_in.next_state <= read_block_0;
                    r_in.state <= read_word; -- Read 4 byte address.

                elsif rx_data = UART_WRITE_BLOCK_REQ then
                    r_in.byte_counter <= 3;
                    r_in.next_state <= write_block_0;
                    r_in.state <= read_word; -- Read 4 byte address.
                end if;
            end if;

        -- Read a predefined number of bytes MSB first from the rx fifo into the word buffer.
        elsif r.state = read_word then
            if rx_empty = '0' then

                rx_read_enable <= '1';
                r_in.word_buffer((r.byte_counter + 1) * 8 - 1 downto r.byte_counter * 8) <= rx_data;

                if r.byte_counter > 0 then
                    r_in.byte_counter <= r.byte_counter - 1;
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
            r_in.byte_counter <= 1;
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

        -- Read the 4 byte lenth field from the rx fifo.
        elsif r.state = read_block_0 then
            r_in.address <= unsigned(r.word_buffer);
            r_in.byte_counter <= 3;
            r_in.uart_count <= 0;
            r_in.next_state <= read_block_1;
            r_in.state <= read_word;

        -- Issue SDRAM read and wait for ack.
        elsif r.state = read_block_1 then

            r_in.sdram_burst_length <= to_integer(unsigned(r.word_buffer));
            r_in.sdram_address <= r.address(SDRAM_DEPTH_LOG2 - 1 downto 0);

            -- Write reply header to the tx fifo.
            if sdram_output.ack = '1' then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= UART_READ_BLOCK_REP;
                r_in.byte_counter <= 2 * r.sdram_burst_length - 1;
                r_in.state <= read_block_2;
            else
                r_in.sdram_read_enable <= '1';
            end if;

        -- Write SDRAM read data into the s2u fifo.
        -- Write bytes from the s2u fifo to the UART tx fifo.
        elsif r.state = read_block_2 then

            -- Write SDRAM words in the async fifo.
            if sdram_output.read_valid = '1' then
                s_s2u_fifo_wr_en <= '1';
            end if;

            if s_s2u_fifo_empty = '0' then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= s_s2u_fifo_dout;
                r_in.uart_count <= r.uart_count + 1;
                s_s2u_fifo_rd_en <= '1';

                if r.byte_counter > 0 then
                    r_in.byte_counter <= r.byte_counter - 1;
                else
                    r_in.state <= idle;
                end if;
            end if;

        -- Read the 4 byte length field from the rx fifo.
        elsif r.state = write_block_0 then
            r_in.address <= unsigned(r.word_buffer);
            r_in.byte_counter <= 3;
            r_in.burst_counter <= 1;
            r_in.next_state <= write_block_1;
            r_in.state <= read_word;

        -- Move data from the UART RX fifo to the SDRAM fifo.
        elsif r.state = write_block_1 then

            if rx_empty = '0' then
                rx_read_enable <= '1';
                s_u2s_fifo_wr_en <= '1';

                -- burst_counter counts bytes while the burst length is given in 16 bit words.
                if r.burst_counter = 2 * to_integer(unsigned(r.word_buffer)) then
                    r_in.state <= write_block_2;
                else
                    r_in.burst_counter <= r.burst_counter + 1;
                end if;
            end if;

        -- Issue SDRAM write and wait for ack.
        elsif r.state = write_block_2 then
            if sdram_output.ack = '1' then
                r_in.state <= write_block_3;
            else
                r_in.sdram_write_enable <= '1';
                r_in.sdram_burst_length <= to_integer(unsigned(r.word_buffer));
                r_in.sdram_address <= r.address(SDRAM_DEPTH_LOG2 - 1 downto 0);
            end if;

        -- Wait for the SDRAM arbiter to read all data from the async fifo.
        elsif r.state = write_block_3 then
            if sdram_output.done = '1' then
                r_in.state <= idle;
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= UART_WRITE_BLOCK_REP;
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
