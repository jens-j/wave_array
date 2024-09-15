library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;

library uart;
use uart.uart_pkg.all;

library xil_defaultlib;


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
        tx_data_count           : in  std_logic_vector(11 downto 0);

        -- Register file interface.
        register_input          : out t_register_input;
        register_output         : in  t_register_output;

        -- SDRAM interface.
        sdram_input             : out t_sdram_input;
        sdram_output            : in  t_sdram_output;

        -- HK fifo interface.
        hk_write_enable         : in  std_logic;
        hk_data                 : in  std_logic_vector(15 downto 0);
        hk_full                 : out std_logic;
        hk_count                : out std_logic_vector(10 downto 0);

        -- Waveform fifo interface.
        wave_write_enable       : in  std_logic;
        wave_data               : in  std_logic_vector(15 downto 0);
        wave_full               : out std_logic;
        wave_count              : out std_logic_vector(11 downto 0);

        debug_flags             : out std_logic_vector(3 downto 0);
        debug_state             : out integer;
        debug_hk_fifo_count     : out integer
    );
end entity;

architecture arch of uart_packet_engine is

    -- Make watchdog timer wide enough for 0.1 second.
    constant WDT_WIDTH : integer := integer(ceil(log2(real(SYS_FREQ))));

    type t_state is (idle, read_word, read_reg_0, read_reg_1, read_reg_2,
        read_reg_3, write_reg_0, write_reg_1, write_reg_2, read_block_0, read_block_1, read_block_2,
        read_block_3, write_block_0, write_block_1, write_block_2, write_block_3, write_block_4,
        offload_hk, offload_wave_0, offload_wave_1, offload_wave_2, offload_wave_3, offload_wave_4,
        send_error_rep);

    -- Somehow this FSM is not recognized by vivado. So not sure what the encoding would be otherwise.
    -- Probably grey but that is not very readable.
    attribute enum_encoding : string;
    attribute enum_encoding of t_state : type is "11111 00001 00010 00011 00100 00101 00110 00111 01000 01001 01010 01011 01100 01101 01110 01111 10000 10001 10010 10011 10100 10101 10110 10111 11000";

    type t_packet_engine_reg is record
        state                   : t_state;
        next_state              : t_state;
        tx_write_enable         : std_logic;
        tx_data                 : std_logic_vector(7 downto 0);
        register_input          : t_register_input;
        sdram_read_enable       : std_logic;
        sdram_write_enable      : std_logic;
        sdram_burst_n           : integer range 1 to SDRAM_MAX_BURST;
        sdram_address           : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        timeout                 : std_logic;
        byte_counter            : integer range 0 to 2 * SDRAM_MAX_BURST - 1;
        fifo_counter            : integer range 1 to 16; -- Count 16 bytes for one 8 word SDRAM burst.
        burst_counter           : integer;
        word_buffer             : std_logic_vector(31 downto 0); -- Buffer used to receive words byte for byte.
        address                 : unsigned(31 downto 0); -- Address field buffer.
        watchdog                : unsigned(WDT_WIDTH downto 0);
        uart_count              : integer range 0 to 2**16 - 1;
        hk_count                : integer range 0 to HK_PACKET_BYTES - 1;
        wave_count              : integer range 0 to 2**CTRL_SIZE - 1;
        length_lsb              : std_logic_vector(7 downto 0);
        error_code              : std_logic_vector(7 downto 0);
        output_valid_sticky     : std_logic;
        length_byte_counter     : integer range 0 to 3;
        debug_flags_sticky      : std_logic_vector(3 downto 0);
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state                   => idle,
        next_state              => idle,
        tx_write_enable         => '0',
        tx_data                 => (others => '0'),
        register_input          => REGISTER_INPUT_INIT,
        sdram_read_enable       => '0',
        sdram_write_enable      => '0',
        sdram_burst_n           => 1,
        sdram_address           => (others => '0'),
        timeout                 => '0',
        byte_counter            => 0,
        fifo_counter            => 1,
        burst_counter           => 0,
        word_buffer             => (others => '0'),
        address                 => (others => '0'),
        watchdog                => (others => '0'),
        uart_count              => 0,
        hk_count                => 0,
        wave_count              => 0,
        length_lsb              => (others => '0'),
        error_code              => x"00",
        output_valid_sticky     => '0',
        length_byte_counter     => 0,
        debug_flags_sticky      => (others => '0')
    );

    signal r, r_in              : t_packet_engine_reg;

    signal s_s2u_fifo_din       : std_logic_vector(15 downto 0);
    signal s_s2u_fifo_wr_en     : std_logic;
    signal s_s2u_fifo_rd_en     : std_logic;
    signal s_s2u_fifo_dout      : std_logic_vector(7 downto 0);
    signal s_s2u_fifo_full      : std_logic;
    signal s_s2u_fifo_empty     : std_logic;
    signal s_s2u_fifo_rd_count  : std_logic_vector(10 downto 0);

    signal s_hk2u_fifo_rd_en    : std_logic;
    signal s_hk2u_fifo_dout     : std_logic_vector(7 downto 0);
    signal s_hk2u_fifo_full     : std_logic;
    signal s_hk2u_fifo_empty    : std_logic;
    signal s_hk2u_fifo_rd_count : std_logic_vector(11 downto 0);
    signal s_hk2u_fifo_wr_count : std_logic_vector(10 downto 0);

    signal s_wave2u_fifo_rd_en  : std_logic;
    signal s_wave2u_fifo_dout   : std_logic_vector(7 downto 0);
    signal s_wave2u_fifo_full   : std_logic;
    signal s_wave2u_fifo_empty  : std_logic;
    signal s_wave2u_fifo_wr_count : std_logic_vector(11 downto 0);

    signal s_u2s_fifo_din       : std_logic_vector(7 downto 0);
    signal s_u2s_fifo_wr_en     : std_logic;
    signal s_u2s_fifo_rd_en     : std_logic;
    signal s_u2s_fifo_dout      : std_logic_vector(15 downto 0);
    signal s_u2s_fifo_full      : std_logic;
    signal s_u2s_fifo_empty     : std_logic;
    signal s_u2s_fifo_rd_count  : std_logic_vector(9 downto 0);

begin

    hk_full <= s_hk2u_fifo_full;
    hk_count <= s_hk2u_fifo_wr_count;
    wave_full <= s_wave2u_fifo_full;
    wave_count <= s_wave2u_fifo_wr_count;
    debug_flags <= r.debug_flags_sticky;
    debug_state <= t_state'pos(r.state);
    debug_hk_fifo_count <= to_integer(unsigned(s_hk2u_fifo_rd_count));
    
    -- 16 bit to 8 bit fifo to buffer HK data (1024 words).
    hk_uart_fifo : entity xil_defaultlib.hk_uart_fifo_gen
    port map (
        srst                    => reset,
        clk                     => clk,
        din                     => hk_data,
        wr_en                   => hk_write_enable,
        rd_en                   => s_hk2u_fifo_rd_en,
        dout                    => s_hk2u_fifo_dout,
        full                    => s_hk2u_fifo_full,
        empty                   => s_hk2u_fifo_empty,
        rd_data_count           => s_hk2u_fifo_rd_count,
        wr_data_count           => s_hk2u_fifo_wr_count
    );

    -- 16 bit to 8 bit fifo to buffer wave data (2048 words).
    wave_uart_fifo : entity xil_defaultlib.wave_uart_fifo_gen
    port map (
        srst                    => reset,
        clk                     => clk,
        din                     => wave_data,
        wr_en                   => wave_write_enable,
        rd_en                   => s_wave2u_fifo_rd_en,
        dout                    => s_wave2u_fifo_dout,
        full                    => s_wave2u_fifo_full,
        empty                   => s_wave2u_fifo_empty,
        wr_data_count           => s_wave2u_fifo_wr_count
    );

    -- 16 bit to 8 bit fifo to buffer SDRAM block data (1024 words).
    sdram_uart_fifo : entity xil_defaultlib.sdram_uart_fifo_gen
    port map (
        rst                     => reset,
        wr_clk                  => clk,
        rd_clk                  => clk,
        din                     => s_s2u_fifo_din,
        wr_en                   => s_s2u_fifo_wr_en,
        rd_en                   => s_s2u_fifo_rd_en,
        dout                    => s_s2u_fifo_dout,
        full                    => s_s2u_fifo_full,
        empty                   => s_s2u_fifo_empty,
        rd_data_count           => s_s2u_fifo_rd_count
    );

    -- 8 to 16 bit fifo to buffer UART write data (1024 words).
    uart_sdram_fifo : entity xil_defaultlib.uart_sdram_fifo_gen
    port map (
        rst                     => reset,
        wr_clk                  => clk,
        rd_clk                  => clk,
        din                     => s_u2s_fifo_din,
        wr_en                   => s_u2s_fifo_wr_en,
        rd_en                   => s_u2s_fifo_rd_en,
        dout                    => s_u2s_fifo_dout,
        full                    => s_u2s_fifo_full,
        empty                   => s_u2s_fifo_empty,
        rd_data_count           => s_u2s_fifo_rd_count
    );

    -- Connect output registers.
    tx_write_enable             <= r.tx_write_enable;
    tx_data                     <= r.tx_data;
    register_input              <= r.register_input;
    sdram_input.read_enable     <= r.sdram_read_enable;
    sdram_input.write_enable    <= r.sdram_write_enable;
    sdram_input.burst_n         <= r.sdram_burst_n;
    sdram_input.address         <= r.sdram_address;


    -- Connect asymmetric fifo read side to the sdram interface.
    sdram_input.write_data <= s_u2s_fifo_dout;
    s_u2s_fifo_rd_en <= sdram_output.write_req or sdram_output.done;

    comb_process : process (r, rx_empty, rx_data, tx_data_count, register_output, sdram_output, s_s2u_fifo_dout,
            s_s2u_fifo_empty, s_u2s_fifo_rd_count, s_s2u_fifo_rd_count, 
            s_hk2u_fifo_rd_count, s_hk2u_fifo_dout, s_wave2u_fifo_dout, s_wave2u_fifo_empty)

        variable v_burst_n : std_logic_vector(31 downto 0);

    begin

        r_in <= r;
        r_in.tx_write_enable <= '0';
        r_in.tx_data <= (others => '0');
        r_in.register_input <= ('0', '0', (others => '0'), (others => '0'));
        r_in.sdram_read_enable <= '0';
        r_in.sdram_write_enable <= '0';
        r_in.sdram_address <= (others => '0');
        r_in.timeout <= '0';

        r_in.debug_flags_sticky(3) <= '1' when s_s2u_fifo_full else r.debug_flags_sticky(3);
        r_in.debug_flags_sticky(2) <= '1' when s_u2s_fifo_full else r.debug_flags_sticky(2);
        r_in.debug_flags_sticky(1) <= '1' when s_hk2u_fifo_full else r.debug_flags_sticky(1);
        r_in.debug_flags_sticky(0) <= '1' when s_wave2u_fifo_full else r.debug_flags_sticky(0);

        -- Default fifo inputs.
        s_s2u_fifo_wr_en <= '0';
        s_s2u_fifo_rd_en <= '0';
        s_u2s_fifo_wr_en <= '0';
        s_s2u_fifo_din <= sdram_output.read_data;
        s_u2s_fifo_din <= rx_data;
        s_hk2u_fifo_rd_en <= '0';
        s_wave2u_fifo_rd_en <= '0';

        -- This output is not registered to avoid a delay cycle when reading bytes from the fifo.
        rx_read_enable <= '0';

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

            elsif to_integer(unsigned(s_hk2u_fifo_rd_count)) >= HK_PACKET_BYTES then
                r_in.hk_count <= 0;
                r_in.state <= offload_hk;

            elsif s_wave2u_fifo_empty = '0' then
                r_in.state <= offload_wave_0;
            end if;

        -- Write opcode to UART.
        elsif r.state = offload_wave_0 then 

            if s_wave2u_fifo_empty = '0' and to_integer(unsigned(tx_data_count)) < 2046 then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= s_wave2u_fifo_dout;
                s_wave2u_fifo_rd_en <= '1';
                r_in.state <= offload_wave_1;
            end if;

        -- Write channel to UART.
        elsif r.state = offload_wave_1 then 

            if s_wave2u_fifo_empty = '0' and to_integer(unsigned(tx_data_count)) < 2046 then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= s_wave2u_fifo_dout;
                s_wave2u_fifo_rd_en <= '1';
                r_in.state <= offload_wave_2;
            end if;

        -- Write lsb byte of packet data length to UART.
        elsif r.state = offload_wave_2 then 

            if s_wave2u_fifo_empty = '0' and to_integer(unsigned(tx_data_count)) < 2046 then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= s_wave2u_fifo_dout;
                r_in.length_lsb <= s_wave2u_fifo_dout;
                s_wave2u_fifo_rd_en <= '1';
                r_in.state <= offload_wave_3;
            end if;

        -- Write msb and calculate length.
        elsif r.state = offload_wave_3 then 

            if s_wave2u_fifo_empty = '0' and to_integer(unsigned(tx_data_count)) < 2046 then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= s_wave2u_fifo_dout;
                s_wave2u_fifo_rd_en <= '1';
                r_in.wave_count <= minimum(65335, 2 * to_integer(unsigned(s_wave2u_fifo_dout) & unsigned(r.length_lsb))); -- Convert from words to bytes. Minimum is to avoid transient out of range simulation issues.  
                r_in.state <= offload_wave_4;
            end if;

        -- Write packet data bytes.
        elsif r.state = offload_wave_4 then 

            if s_wave2u_fifo_empty = '0' and to_integer(unsigned(tx_data_count)) < 2046 then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= s_wave2u_fifo_dout;
                s_wave2u_fifo_rd_en <= '1';

                if r.wave_count > 1 then 
                    r_in.wave_count <= r.wave_count - 1;
                else 
                    r_in.state <= idle;
                end if;
            end if;

        -- Write a hk packet from the hk fifo to the uart tx fifo.
        elsif r.state = offload_hk then 

            if to_integer(unsigned(tx_data_count)) < 2046 then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= s_hk2u_fifo_dout;
                s_hk2u_fifo_rd_en <= '1';

                if r.hk_count < HK_PACKET_BYTES - 1 then 
                    r_in.hk_count <= r.hk_count + 1;
                else
                    r_in.state <= idle;
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
                    r_in.error_code <= UART_ERR_READ_FAULT;
                    r_in.state <= send_error_rep;
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
            r_in.output_valid_sticky <= '0';
            r_in.register_input.write_enable <= '1';
            r_in.register_input.write_data <= r.word_buffer(15 downto 0);
            r_in.register_input.address <= r.address;
            r_in.state <= write_reg_2;

        -- Send ack or error response.
        elsif r.state = write_reg_2 then

            if register_output.valid = '1' or r.output_valid_sticky = '1' then 

                r_in.output_valid_sticky <= '1';
            
                if  to_integer(unsigned(tx_data_count)) < 2046 then

                    r_in.tx_write_enable <= '1';
                    if register_output.fault = '1' then 
                        r_in.tx_data <= UART_ERROR_REP;
                        r_in.error_code <= UART_ERR_WRITE_FAULT;
                        r_in.state <= send_error_rep;
                    else
                        r_in.tx_data <= UART_WRITE_REP;
                        r_in.state <= idle;
                    end if;          
                end if;      
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

            r_in.sdram_burst_n <= to_integer(unsigned(r.word_buffer));
            r_in.sdram_address <= r.address(SDRAM_DEPTH_LOG2 - 1 downto 0);

            -- Write reply header to the tx fifo.
            if sdram_output.ack = '1' then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= UART_READ_BLOCK_REP;
                r_in.byte_counter <= 16 * to_integer(unsigned(r.word_buffer)) - 1; -- Each burst is 8 x 2 byte words.
                r_in.length_byte_counter <= 0;
                r_in.state <= read_block_2;
            else
                r_in.sdram_read_enable <= '1';
            end if;

        -- Write burst_n field to the UART fifo. 
        elsif r.state = read_block_2 then

            v_burst_n := std_logic_vector(to_unsigned(r.sdram_burst_n, 32)); 

            r_in.tx_write_enable <= '1';
            r_in.tx_data <= v_burst_n((r.length_byte_counter + 1) * 8 - 1 downto r.length_byte_counter * 8);

            if r.length_byte_counter < 3 then 
                r_in.length_byte_counter <= r.length_byte_counter + 1;
            else 
                r_in.state <= read_block_3;
            end if;

        -- Write SDRAM read data into the s2u fifo.
        -- Write bytes from the s2u fifo to the UART tx fifo.
        elsif r.state = read_block_3 then

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

        -- Store the address field.
        -- Read the 4 byte length field from the rx fifo.
        elsif r.state = write_block_0 then
            r_in.address <= unsigned(r.word_buffer);
            r_in.byte_counter <= 3;
            r_in.fifo_counter <= 1;
            
            r_in.next_state <= write_block_1;
            r_in.state <= read_word;

        -- Store the length field (number of bursts).
        elsif r.state = write_block_1 then
            r_in.burst_counter <= to_integer(unsigned(r.word_buffer));
            r_in.state <= write_block_2;

        -- Move data from the UART RX fifo to the SDRAM fifo.
        -- The stream is spit in multiple 8 word bursts.
        elsif r.state = write_block_2 then

            if rx_empty = '0' then
                rx_read_enable <= '1';
                s_u2s_fifo_wr_en <= '1'; 

                -- A full burst of 8 words (16 bytes) is in the fifo.
                if r.fifo_counter = 16 then 
                    r_in.sdram_burst_n <= 1;
                    r_in.burst_counter <= r.burst_counter - 1;
                    r_in.state <= write_block_3;
                else
                    r_in.fifo_counter <= r.fifo_counter + 1;
                end if;
            end if;

        -- Issue SDRAM write and wait for ack.
        elsif r.state = write_block_3 then
            if sdram_output.ack = '1' then
                r_in.address <= r.address + to_unsigned(8, 32); -- Increase address by SDRAM burst size.
                r_in.state <= write_block_4;
            else
                r_in.sdram_write_enable <= '1';
                r_in.sdram_address <= r.address(SDRAM_DEPTH_LOG2 - 1 downto 0);
            end if;

        -- Wait for the SDRAM arbiter to read all data from the async fifo.
        -- Continue with next burst if block is not yet completed.
        elsif r.state = write_block_4 then
            if sdram_output.done = '1' then
                if r.burst_counter = 0 then 
                    r_in.state <= idle;
                    r_in.tx_write_enable <= '1';
                    r_in.tx_data <= UART_WRITE_BLOCK_REP;
                else 
                    r_in.fifo_counter <= 1;
                    r_in.state <= write_block_2;
                end if;
            end if;

        -- Send the error code that is part of an error response and return to the idle state.
        elsif r.state = send_error_rep then
            if to_integer(unsigned(tx_data_count)) < 2046 then
                r_in.tx_write_enable <= '1';
                r_in.tx_data <= r.error_code;
                r_in.state <= idle;
            end if;
        end if;

        -- -- If a message takes more than a second an error response is sent.
        -- if r.state /= idle then
        --     if r.watchdog(WDT_WIDTH) = '0' then
        --         r_in.watchdog <= r.watchdog + 1;
        --     else
        --         r_in.watchdog <= (others => '0');
        --         r_in.tx_write_enable <= '1';
        --         r_in.tx_data <= UART_ERROR_REP;
        --         r_in.timeout <= '1'; -- Strobe error flag.
        --         r_in.error_code <= UART_ERR_TIMEOUT;
        --         r_in.state <= send_error_rep;
        --     end if;
        -- end if;

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
