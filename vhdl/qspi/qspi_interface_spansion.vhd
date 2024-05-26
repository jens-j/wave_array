library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

Library UNISIM;
use UNISIM.vcomponents.all;

library xil_defaultlib;

library wave;
use wave.wave_array_pkg.all;


entity qspi_interface_spansion is
    port (
        system_clk              : in  std_logic;
        spi_clk                 : in  std_logic;
        reset                   : in  std_logic;
        flash_input             : in  t_flash_input;
        flash_output            : out t_flash_output;
        QSPI_CS                 : out std_logic;
        QSPI_SCK                : out std_logic;
        QSPI_DQ                 : inout std_logic_vector(3 downto 0);
        reg_jedec_vendor        : out std_logic_vector(7 downto 0);
        reg_jedec_device        : out std_logic_vector(15 downto 0);
        reg_status_1            : out std_logic_vector(7 downto 0);
        reg_config              : out std_logic_vector(7 downto 0)
    );
end entity;


architecture arch of qspi_interface_spansion is 

    -- JEDEC FLASH commands.
    constant FLASH_CMD_READ_JEDEC           : std_logic_vector(7 downto 0) := x"9F";
    constant FLASH_CMD_READ_STATUS_1        : std_logic_vector(7 downto 0) := x"05";
    constant FLASH_CMD_READ_STATUS_2        : std_logic_vector(7 downto 0) := x"07";
    constant FLASH_CMD_READ_CONFIG          : std_logic_vector(7 downto 0) := x"35";
    constant FLASH_CMD_WRITE_ENABLE         : std_logic_vector(7 downto 0) := x"06";
    constant FLASH_CMD_WRITE_REGISTERS      : std_logic_vector(7 downto 0) := x"01";
    constant FLASH_CMD_4BYTE_PROGRAM        : std_logic_vector(7 downto 0) := x"12";
    constant FLASH_CMD_4BYTE_READ           : std_logic_vector(7 downto 0) := x"13";
    constant FLASH_CMD_4BYTE_QUAD_READ      : std_logic_vector(7 downto 0) := x"6C";
    constant FLASH_CMD_4BYTE_SECTOR_ERASE   : std_logic_vector(7 downto 0) := x"DC";

    type t_state is 
        (init_0, init_1, init_2, init_3, init_4, 
         idle, tx_stream_start, erase_start, wait_rx_done, poll_wip_0, poll_wip_1, poll_wip_2);

    type t_qspi_if_reg is record
        -- State regster.
        state                   : t_state;
        next_state              : t_state;

        -- Output registers.
        flash_output            : t_flash_output;
        qspi_cs                 : std_logic;
        qspi_dq                 : std_logic_vector(3 downto 0);
        reg_jedec_vendor        : std_logic_vector(7 downto 0);
        reg_jedec_device        : std_logic_vector(15 downto 0);
        reg_status_1            : std_logic_vector(7 downto 0);
        reg_config              : std_logic_vector(7 downto 0);

        -- IF control registers.
        clock_enable            : std_logic;
        output_enable           : std_logic_vector(3 downto 0);

        -- flash_input registers.
        address                 : unsigned(FLASH_DEPTH_LOG2 - 1 downto 0);
        prefetch_counter        : integer range 0 to FLASH_PAGE_SIZE;
        fifo_wr_en              : std_logic;

        -- TX registers.
        tx_req                  : std_logic;                                        -- Request TX start.
        tx_stream               : std_logic;                                        -- TX stream flag.
        tx_busy                 : std_logic;                                        -- TX busy flag.
        tx_counter              : natural range 0 to 39 + FLASH_PAGE_SIZE_BITS;     -- TX bit counter.
        tx_buffer               : std_logic_vector(39 downto 0);                    -- TX output buffer.

        -- RX registers.
        rx_req                  : std_logic;                                        -- Request RX start.
        rx_stream               : std_logic;                                        -- RX stream (and quad mode) flag.
        rx_busy                 : std_logic;                                        -- RX busy flag.
        rx_counter              : natural range 0 to 7 + FLASH_PAGE_SIZE_NIBBLES;   -- RX bit counter.
        rx_buffer               : std_logic_vector(31 downto 0);                    -- RX receive buffer.                    
        rx_done                 : std_logic;                                        -- RX done strobe.

        -- Misc registers. 
        sleep_counter           : integer range 0 to 999;                           -- Count sleep cycles for WIP polling. 
        dummy_counter           : integer range 0 to 8;                             -- Count dummy cycles in quad read.
    end record;

    constant R_INIT : t_qspi_if_reg := (
        state                   => init_0,
        next_state              => init_0,
        flash_output            => FLASH_OUTPUT_INIT,
        qspi_cs                 => '1',
        qspi_dq                 => (others => '0'),
        reg_jedec_vendor        => (others => '0'),
        reg_jedec_device        => (others => '0'),
        reg_status_1            => (others => '0'),
        reg_config              => (others => '0'),
        clock_enable            => '0',
        output_enable           => (others => '0'),
        address                 => (others => '0'),
        prefetch_counter        => 0,
        fifo_wr_en              => '0',
        tx_req                  => '0',
        tx_stream               => '0',
        tx_busy                 => '0',
        tx_counter              => 0,
        tx_buffer               => (others => '0'),
        rx_req                  => '0',
        rx_stream               => '0',
        rx_busy                 => '0',
        rx_counter              => 0,
        rx_buffer               => (others => '0'),
        rx_done                 => '0',
        sleep_counter           => 0,
        dummy_counter           => 0
    );


    signal r, r_in : t_qspi_if_reg := R_INIT;

    signal s_fifo_rd_en         : std_logic;
    signal s_fifo_dout          : std_logic_vector(FLASH_WIDTH - 1 downto 0);
    signal s_fifo_full          : std_logic;
    signal s_fifo_empty         : std_logic;
    signal s_fifo_data_count    : std_logic_vector(4 downto 0);

    procedure cmd_write_enable (
        signal r_in             : out t_qspi_if_reg;
        constant next_state     : in  t_state
    ) is 
    begin 
        r_in.tx_req <= '1';
        r_in.tx_buffer <= FLASH_CMD_WRITE_ENABLE & (0 to 31 => '0');
        r_in.tx_counter <= 7;
        r_in.rx_counter <= 0;
        r_in.state <= next_state;
    end procedure;

begin 

    -- Instantiate spi clock gate.
    -- This is sketchy because the clock enable signal has 180 phase difference with the input clock.
    BUFGCE_inst : BUFGCE_1
    port map (
        O   => QSPI_SCK,        -- 1-bit output: Clock output
        CE  => r.clock_enable,  -- 1-bit input: Clock enable input for I0
        I   => spi_clk          -- 1-bit input: Primary clock
    );

    -- Intantiate tri-state buffers for data lines.
    tristate_gen: for i in 0 to 3 generate 
        QSPI_DQ(i) <= r.qspi_dq(i) when r.output_enable(i) = '1' else 'Z';
    end generate;

    -- 18 word deep FWFT fifo.
    prefetch : entity xil_defaultlib.flash_fifo
    port map (
        clk                     => system_clk,
        srst                    => reset,
        din                     => flash_input.write_data,
        wr_en                   => r.fifo_wr_en,
        rd_en                   => s_fifo_rd_en,
        dout                    => s_fifo_dout,
        full                    => s_fifo_full,
        empty                   => s_fifo_empty,
        data_count              => s_fifo_data_count
    );

    -- Connect output registers.
    qspi_cs <= r.qspi_cs;
    flash_output <= r.flash_output;
    reg_jedec_vendor <= r.reg_jedec_vendor;
    reg_jedec_device <= r.reg_jedec_device;
    reg_status_1 <= r.reg_status_1;
    reg_config <= r.reg_config;


    state_proc : process (r, QSPI_DQ, flash_input, s_fifo_dout, s_fifo_data_count)
    begin 

        r_in <= r;
        r_in.flash_output.ack <= '0';
        r_in.flash_output.read_valid <= '0';
        r_in.flash_output.write_req <= '0';
        r_in.flash_output.done <= '0';
        r_in.fifo_wr_en <= '0';
        r_in.rx_done <= '0';
        s_fifo_rd_en <= '0';

        -- Prefetch write words to avoid latency issues with handshaking. Wait for the write_enable is deasserted to start prefetching after the ack is returned. 
        if r.prefetch_counter > 0 and to_integer(unsigned(s_fifo_data_count)) < 16  
                and flash_input.write_enable = '0' then

            r_in.fifo_wr_en <= '1';
            r_in.prefetch_counter <= r.prefetch_counter - 1;
            
            if r.prefetch_counter = 1 then
                r_in.flash_output.done <= '1';
            else
                r_in.flash_output.write_req <= '1';
            end if;
        end if;
        
        case r.state is 

        -- Read JEDEC register.
        when init_0 => 
            r_in.tx_req <= '1';
            r_in.tx_buffer <= FLASH_CMD_READ_JEDEC & (0 to 31 => '0');
            r_in.tx_counter <= 7;
            r_in.rx_counter <= 23;
            r_in.state <= init_1;

        -- register JEDEC values, enter 4-byte address mode.
        when init_1 => 
            if r.rx_done = '1' then 
                r_in.reg_jedec_vendor <= r.rx_buffer(23 downto 16);
                r_in.reg_jedec_device <= r.rx_buffer(15 downto 0);

                r_in.tx_req <= '1';
                r_in.tx_buffer <= FLASH_CMD_READ_JEDEC & (0 to 31 => '0');
                r_in.tx_counter <= 7;
            end if;

        -- Write registers. 
        when init_2 =>
            if r.rx_done = '1' then 
                r_in.tx_req <= '1';
                r_in.tx_buffer <= FLASH_CMD_WRITE_REGISTERS & x"0002" & (0 to 15 => '0');
                r_in.tx_counter <= 23;
                r_in.rx_counter <= 0;
                r_in.next_state <= init_3;
                r_in.state <= poll_wip_0;
            end if;

        -- Issue read config command.
        when init_3 => 
            r_in.tx_req <= '1';
            r_in.tx_buffer <= FLASH_CMD_READ_CONFIG & (0 to 31 => '0');
            r_in.tx_counter <= 7;
            r_in.rx_counter <= 7;
            r_in.state <= init_4;

        -- Register config value.
        when init_4 => 
            if r.rx_done = '1' then 
                r_in.reg_config <= r.rx_buffer(7 downto 0);
                r_in.state <= idle;
            end if;

        -- Wait for read_ or write_enable.
        when idle => 
            if flash_input.read_enable = '1' then 

                r_in.flash_output.ack <= '1';
                r_in.tx_req <= '1';
                r_in.tx_buffer <= FLASH_CMD_4BYTE_QUAD_READ 
                    & (0 to 31 - FLASH_DEPTH_LOG2 => '0') & std_logic_vector(flash_input.address); -- Extend address to 32 bits.
                r_in.tx_counter <= 39;
                r_in.rx_stream <= '1';
                r_in.rx_counter <= to_integer(to_unsigned(flash_input.bytes_n, FLASH_PAGE_SIZE_LOG2 + 1) & "0") + 7; -- Convert to nibbles and add delay cycles.
                r_in.dummy_counter <= 8;
                r_in.state <= wait_rx_done;
            
            elsif flash_input.write_enable = '1' then 

                r_in.flash_output.ack <= '1';
                r_in.address <= flash_input.address;
                r_in.prefetch_counter <= flash_input.bytes_n;

                -- First a write enable command must be sent.
                cmd_write_enable(r_in, tx_stream_start);

            elsif flash_input.erase_enable = '1' then 

                r_in.flash_output.ack <= '1';
                r_in.address <= flash_input.address;

                -- First a write enable command must be sent.
                cmd_write_enable(r_in, erase_start);

            end if;

        when tx_stream_start => 
            if r.rx_done = '1' then 
                r_in.tx_req <= '1';
                r_in.tx_stream <= '1';
                r_in.tx_buffer <= FLASH_CMD_4BYTE_PROGRAM 
                    & (0 to 31 - FLASH_DEPTH_LOG2 => '0') & std_logic_vector(r.address);
                r_in.tx_counter <= 39 + to_integer(to_unsigned(flash_input.bytes_n, FLASH_PAGE_SIZE_LOG2 + 1) & "000"); -- Convert to bits.
                r_in.next_state <= idle;
                r_in.state <= poll_wip_0;
            end if;

        when erase_start => 
            if r.rx_done = '1' then 
                r_in.tx_req <= '1';
                r_in.tx_buffer <= FLASH_CMD_4BYTE_SECTOR_ERASE 
                    & (0 to 31 - FLASH_DEPTH_LOG2 => '0') -- Extend address to 32 bits.
                    & std_logic_vector( r.address(FLASH_DEPTH_LOG2 - 1 downto FLASH_SECTOR_SIZE_LOG2))
                    & (0 to FLASH_SECTOR_SIZE_LOG2 - 1 => '0');
                r_in.tx_counter <= 39;
                r_in.next_state <= idle;
                r_in.state <= poll_wip_0;
            end if;

        -- Wait for the rx_done flag.
        when wait_rx_done => 
            if r.rx_done = '1' then 
                r_in.state <= idle;
            end if;

        -- Wait for the rx_done flag.
        when poll_wip_0 => 
            if r.rx_done = '1' then 
                r_in.state <= poll_wip_1;
            end if;

        -- Read the status_1 register once every 1000 cycle.
        when poll_wip_1 => 
            if r.sleep_counter < 999 then 
                r_in.sleep_counter <= r.sleep_counter + 1;
            else 
                r_in.sleep_counter <= 0;
                r_in.tx_req <= '1';
                r_in.tx_buffer <= FLASH_CMD_READ_STATUS_1 & (0 to 31 => '0');
                r_in.tx_counter <= 7;
                r_in.rx_counter <= 7;
                r_in.state <= poll_wip_2;
            end if; 

        -- Check WIP bit.
        when poll_wip_2 => 
            if r.rx_done = '1' then 
                r_in.reg_status_1 <= r.rx_buffer(7 downto 0);

                if r.rx_buffer(0) = '0' then 
                    r_in.state <= r.next_state;
                else   
                    r_in.state <= poll_wip_1;
                end if;
            end if;

        end case;

        -- Start transmission.
        if r.tx_req = '1' then 
            r_in.tx_req <= '0';
            r_in.tx_busy <= '1';
            r_in.qspi_cs <= '0';
            r_in.clock_enable <= '1';
            r_in.qspi_dq <= "0000";
            r_in.output_enable <= "0001";
        end if;

        -- Output TX bits.
        if r.tx_busy = '1' then 

            -- Shift out TX bits
            r_in.qspi_dq(0) <= r.tx_buffer(39);
            r_in.tx_buffer <= r.tx_buffer(38 downto 0) & '0';

            -- Insert bytes from the fifo into the TX buffer
            if r.tx_stream = '1' and unsigned(s_fifo_data_count) > 0
                    and to_unsigned(r.tx_counter, FLASH_PAGE_SIZE_BITS + 1)(2 downto 0) = "000" then 

                r_in.tx_buffer(7 downto 0) <= s_fifo_dout;
                s_fifo_rd_en <= '1';
            else 
                
            end if;

            if r.tx_counter > 0 then 
                r_in.tx_counter <= r.tx_counter - 1;
            else 
                r_in.tx_busy <= '0';
                r_in.tx_stream <= '0';
                r_in.rx_req <= '1';

                if r.rx_counter = 0 then 
                    r_in.clock_enable <= '0';
                end if;
            end if;
        end if;

        -- Start RX, end transaction if no RX data is expected. 
        if r.rx_req = '1' then 
            r_in.rx_req <= '0';
            r_in.output_enable <= "0000";
            r_in.rx_buffer <= (others => '0');

            if r.rx_counter = 0 then 
                r_in.qspi_cs <= '1';
                r_in.rx_done <= '1';
            else 
                r_in.rx_busy <= '1';
            end if;

        end if; 

        -- Receive RX data.
        if r.rx_busy = '1' then 

            -- Shift in RX bits.
            if r.rx_stream = '1' then 
                r_in.flash_output.read_data <= r.flash_output.read_data(3 downto 0) & QSPI_DQ;
            else 
                r_in.rx_buffer <= r.rx_buffer(30 downto 0) & QSPI_DQ(1);
            end if;

            if r.dummy_counter > 0 then 
                r_in.dummy_counter <= r.dummy_counter - 1;
            end if;

            -- Send received bytes to the flash_ouput interface (after 8 dummy cycles) every even cycle.
            if r.rx_stream = '1' and r.dummy_counter = 0  
                    and to_unsigned(r.rx_counter, FLASH_PAGE_SIZE_BITS + 1)(0) = '0' then 

                r_in.flash_output.read_valid <= '1';
            end if; 

            if r.rx_counter = 1 then 
                r_in.clock_enable <= '0';
            end if;

            if r.rx_counter > 0 then 
                r_in.rx_counter <= r.rx_counter - 1;
            else 
                r_in.rx_busy <= '0';
                r_in.rx_stream <= '0';
                r_in.rx_done <= '1';
                r_in.qspi_cs <= '1';
                r_in.flash_output.done <= r.rx_stream;
            end if;
        end if;


    end process;


    tx_proc : process (r)
    begin 

        

    end process; 

    reg_process : process(system_clk)
    begin
        if rising_edge(system_clk) then
            if reset = '1' then
                r <= R_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;