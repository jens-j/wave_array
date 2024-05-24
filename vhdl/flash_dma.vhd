library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;


-- DMA engine to transfer data between the SDRAM and flash memories.
entity flash_dma is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        sdram_output            : in  t_sdram_output;
        sdram_input             : out t_sdram_input;
        flash_output            : in  t_flash_output;
        flash_input             : out t_flash_input;
        dma_busy                : out std_logic
    );
end entity;


architecture arch of flash_dma is

    type t_flash_dma_reg is record
        sdram_read_enable       : std_logic;
        sdram_write_enable      : std_logic;
        sdram_burst_n           : integer range 1 to SDRAM_MAX_BURST;
        sdram_address           : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        flash_read_enable       : std_logic;
        flash_write_enable      : std_logic;
        flash_erase_enable      : std_logic;
        flash_bytes_n           : integer range 1 to FLASH_PAGE_SIZE;
        flash_address           : unsigned(FLASH_DEPTH_LOG2 - 1 downto 0);
        flash_address_buf       : unsigned(FLASH_DEPTH_LOG2 - 1 downto 0);
        sector_n                : integer range 1 to FLASH_SECTOR_N;
        dma_busy                : std_logic;
        erase_req               : std_logic;
        fetch_flash_req         : std_logic;
        fetch_sdram_req         : std_logic;
        fetch_flash_busy        : std_logic;
        fetch_sdram_busy        : std_logic;
        write_flash_req         : std_logic;
        write_flash_busy        : std_logic;
        write_sdram_busy        : std_logic;
        fetch_pages             : integer range 0 to FLASH_PAGES_N;
        write_pages             : integer range 0 to FLASH_PAGES_N;
    end record;

    constant REG_INIT : t_flash_dma_reg := (
        sdram_read_enable       => '0',
        sdram_write_enable      => '0',
        sdram_burst_n           => 1,
        sdram_address           => (others => '0'),
        flash_read_enable       => '0',
        flash_write_enable      => '0',
        flash_erase_enable      => '0',
        flash_bytes_n           => 1,
        flash_address           => (others => '0'),
        flash_address_buf       => (others => '0'),
        sector_n                => 1,
        dma_busy                => '0',
        erase_req               => '0',
        fetch_flash_req         => '0',
        fetch_sdram_req         => '0',
        fetch_flash_busy        => '0',
        fetch_sdram_busy        => '0',
        write_flash_req         => '0',
        write_flash_busy        => '0',
        write_sdram_busy        => '0',
        fetch_pages             => FLASH_PAGES_PER_SECTOR,
        write_pages             => FLASH_PAGES_PER_SECTOR
    );

    signal r, r_in              : t_flash_dma_reg;

    signal s_flash2sdram_full       : std_logic;
    signal s_flash2sdram_empty      : std_logic;
    signal s_flash2sdram_wr_en      : std_logic;
    signal s_flash2sdram_din        : std_logic_vector(FLASH_WIDTH - 1 downto 0);
    signal s_flash2sdram_rd_en      : std_logic;
    signal s_flash2sdram_dout       : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    signal s_flash2sdram_rd_count   : std_logic_vector(10 downto 0);
    signal s_flash2sdram_wr_count   : std_logic_vector(11 downto 0);

    signal s_sdram2flash_full       : std_logic;
    signal s_sdram2flash_empty      : std_logic;
    signal s_sdram2flash_wr_en      : std_logic;
    signal s_sdram2flash_din        : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    signal s_sdram2flash_rd_en      : std_logic;
    signal s_sdram2flash_dout       : std_logic_vector(FLASH_WIDTH - 1 downto 0);
    signal s_sdram2flash_rd_count   : std_logic_vector(11 downto 0);
    signal s_sdram2flash_wr_count   : std_logic_vector(10 downto 0);
    
begin

    flash2sdram_fifo : entity xil_defaultlib.flash_to_sdram_dma_fifo 
    port map (
        srst                    => reset,
        clk                     => clk,
        din                     => s_flash2sdram_din,
        wr_en                   => s_flash2sdram_wr_en,
        rd_en                   => s_flash2sdram_rd_en,
        dout                    => s_flash2sdram_dout,
        full                    => s_flash2sdram_full,
        empty                   => s_flash2sdram_empty,
        rd_data_count           => s_flash2sdram_rd_count,
        wr_data_count           => s_flash2sdram_wr_count
    );

    sdram2flash_fifo : entity xil_defaultlib.sdram_to_flash_dma_fifo 
    port map (
        srst                    => reset,
        clk                     => clk,
        din                     => s_sdram2flash_din,
        wr_en                   => s_sdram2flash_wr_en,
        rd_en                   => s_sdram2flash_rd_en,
        dout                    => s_sdram2flash_dout,
        full                    => s_sdram2flash_full,
        empty                   => s_sdram2flash_empty,
        rd_data_count           => s_sdram2flash_rd_count,
        wr_data_count           => s_sdram2flash_wr_count
    ); 



    comb_process : process (r, config, sdram_output, flash_output, 
        s_flash2sdram_rd_count, s_flash2sdram_wr_count, s_flash2sdram_dout,
        s_sdram2flash_rd_count, s_sdram2flash_wr_count, s_sdram2flash_dout)

        variable v_pages_n : integer range 1 to FLASH_PAGES_N;

    begin

        r_in <= r;

        -- Connect output registers.
        dma_busy                 <= r.dma_busy;
        flash_input.read_enable  <= r.flash_read_enable;
        flash_input.write_enable <= r.flash_write_enable;
        flash_input.erase_enable <= r.flash_erase_enable;
        flash_input.bytes_n      <= r.flash_bytes_n;
        flash_input.address      <= r.flash_address;
        sdram_input.read_enable  <= r.sdram_read_enable;
        sdram_input.write_enable <= r.sdram_write_enable;
        sdram_input.burst_n      <= r.sdram_burst_n;
        sdram_input.address      <= r.sdram_address;

        -- Connect flash to sdram fifo signals.
        s_flash2sdram_wr_en    <= flash_output.read_valid;
        s_flash2sdram_din      <= flash_output.read_data;
        s_flash2sdram_rd_en    <= sdram_output.write_req or sdram_output.done;
        sdram_input.write_data <= s_flash2sdram_dout; -- Directly connect to fifo output to avoid problems with handshaking.

        -- Connect sdram to flash fifo signals. 
        s_sdram2flash_wr_en    <= sdram_output.read_valid;
        s_sdram2flash_din      <= sdram_output.read_data;
        s_sdram2flash_rd_en    <= flash_output.write_req or flash_output.done;
        flash_input.write_data <= s_sdram2flash_dout; -- Directly connect to fifo output to avoid problems with handshaking.

        -- Wait for new DMA requests.
        if r.dma_busy = '0' and 
                (config.flash_dma_input.start_flash_to_sdram or config.flash_dma_input.start_sdram_to_flash) = '1' then 

            if config.flash_dma_input.start_flash_to_sdram = '1' then 
                r_in.fetch_flash_req <= '1';
            else 
                r_in.fetch_sdram_req <= '1';
                r_in.erase_req <= '1';
            end if;

            v_pages_n := to_integer(shift_left(to_unsigned(
                    config.flash_dma_input.sector_n, FLASH_PAGES_N_LOG2), FLASH_PAGES_PER_SECTOR_LOG2));

            r_in.fetch_pages <= v_pages_n;
            r_in.write_pages <= v_pages_n;
            r_in.sector_n <= config.flash_dma_input.sector_n;
            r_in.dma_busy <= '1';

            -- Round addresses to sector boundary.
            r_in.sdram_address <= 
                config.flash_dma_input.sdram_address(SDRAM_DEPTH_LOG2 - 1 downto FLASH_SECTOR_SIZE_LOG2) 
                & (0 to FLASH_SECTOR_SIZE_LOG2 - 1 => '0');

            r_in.flash_address_buf <= 
                config.flash_dma_input.flash_address(FLASH_DEPTH_LOG2 - 1 downto FLASH_SECTOR_SIZE_LOG2) 
                & (0 to FLASH_SECTOR_SIZE_LOG2 - 1 => '0');

            r_in.flash_address <= 
                config.flash_dma_input.flash_address(FLASH_DEPTH_LOG2 - 1 downto FLASH_SECTOR_SIZE_LOG2) 
                & (0 to FLASH_SECTOR_SIZE_LOG2 - 1 => '0');
            
        end if;        

        -- Erase flash sectors. 
        if r.erase_req = '1' then 

            r_in.flash_erase_enable <= '1';

            if flash_output.ack = '1' then 

                if r.sector_n > 1 then 
                    r_in.sector_n <= r.sector_n - 1;
                    r_in.flash_address <= r.flash_address + to_unsigned(FLASH_SECTOR_SIZE, FLASH_DEPTH_LOG2);
                else 
                    r_in.flash_erase_enable <= '0';
                    r_in.erase_req <= '0';
                    r_in.write_flash_req <= '1';
                    r_in.flash_address <= r.flash_address_buf; -- Restore base address.
                end if;
            end if;
        end if;

        -- Write to flash when a full page is in the fifo.
        if r.write_flash_req = '1' and r.write_flash_busy = '0' 
                and to_integer(unsigned(s_sdram2flash_rd_count)) >= FLASH_PAGE_SIZE then 

            r_in.flash_write_enable <= '1';
            r_in.flash_bytes_n <= FLASH_PAGE_SIZE;

            if flash_output.ack = '1' then 
                r_in.flash_write_enable <= '0';
                r_in.write_flash_busy <= '1';
                r_in.write_pages <= r.write_pages - 1;
            end if;
        end if;

        -- Check for end of flash write transfer. 
        if r.write_flash_busy = '1' and flash_output.done = '1' then

            r_in.write_flash_busy <= '0';

            if r.write_pages = 0 then 
                r_in.write_flash_req <= '0';
                r_in.dma_busy <= '0';
            else
                r_in.flash_address <= r.flash_address + to_unsigned(FLASH_PAGE_SIZE, FLASH_DEPTH_LOG2);
            end if;
        end if; 

        -- Write to sdram when a full page is in the fifo.
        if r.write_sdram_busy = '0' and to_integer(unsigned(s_flash2sdram_rd_count)) >= FLASH_PAGE_SIZE / 2 then 

            r_in.sdram_write_enable <= '1';
            r_in.sdram_burst_n <= FLASH_PAGE_SIZE / 2 / 8;

            if sdram_output.ack = '1' then 
                r_in.sdram_write_enable <= '0';
                r_in.write_sdram_busy <= '1';
                r_in.write_pages <= r.write_pages - 1;
            end if;
        end if;

        -- Check for end of sdram write transfer. 
        if r.write_sdram_busy = '1' and sdram_output.done = '1' then 

            r_in.write_sdram_busy <= '0';

            if r.write_pages = 0 then 
                r_in.dma_busy <= '0';
            else 
                r_in.sdram_address <= r.sdram_address + to_unsigned(FLASH_PAGE_SIZE / 2, SDRAM_DEPTH_LOG2);
            end if;
        end if; 

        -- Issue flash read if requested and there is room in the fifo.
        if r.fetch_flash_req = '1' and r.fetch_flash_busy = '0' 
                and to_integer(unsigned(s_flash2sdram_wr_count)) < 2048 - FLASH_PAGE_SIZE then 
            
            r_in.flash_read_enable <= '1';
            r_in.flash_bytes_n <= FLASH_PAGE_SIZE;

            if flash_output.ack = '1' then 
                r_in.flash_read_enable <= '0';
                r_in.fetch_flash_busy <= '1';
                r_in.fetch_pages <= r.fetch_pages - 1;
            end if;
        end if;

        -- Check for end of flash read transfer. 
        if r.fetch_flash_busy = '1' and flash_output.done = '1' then 

            r_in.fetch_flash_busy <= '0';

            if r.fetch_pages = 0 then 
                r_in.fetch_flash_req <= '0';
            else 
                r_in.flash_address <= r.flash_address + to_unsigned(FLASH_PAGE_SIZE, FLASH_DEPTH_LOG2);
            end if;
        end if;
        
        -- Issue sdram read if requested and there is room in the fifo.
        if r.fetch_sdram_req = '1' and r.fetch_sdram_busy = '0' 
                and to_integer(unsigned(s_sdram2flash_wr_count)) < 1024 - FLASH_PAGE_SIZE / 2 then 

            r_in.sdram_read_enable <= '1';
            r_in.sdram_burst_n <= FLASH_PAGE_SIZE / 2 / 8;

            if sdram_output.ack = '1' then 
                r_in.sdram_read_enable <= '0';
                r_in.fetch_sdram_busy <= '1';
                r_in.fetch_pages <= r.fetch_pages - 1;
            end if;
        end if;

        -- Check for end of sdram read transfer. 
        if r.fetch_sdram_busy = '1' and sdram_output.done = '1' then 

            r_in.fetch_sdram_busy <= '0';

            if r.fetch_pages = 0 then 
                r_in.fetch_sdram_req <= '0';
            else 
                r_in.sdram_address <= r.sdram_address + to_unsigned(FLASH_PAGE_SIZE / 2, SDRAM_DEPTH_LOG2);
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