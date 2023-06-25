library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity frame_dma is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        table2dma               : in  t_table2dma_array(0 to N_TABLES - 1);
        dma2table               : out t_dma2table_array(0 to N_TABLES - 1);
        sdram_output            : in  t_sdram_output;
        sdram_input             : out t_sdram_input
    );
end entity;

architecture arch of frame_dma is

    type t_state is (idle, wait_ack, sdram_read, transfer);

    type t_dma_ctrl_reg is record
        state                   : t_state;
        dma2table               : t_dma2table_array(0 to N_TABLES - 1);
        sdram_input             : t_sdram_input;
        new_table               : std_logic_vector(N_TABLES - 1 downto 0); -- Register to avoid missing new_table strobes.
        table_index             : integer range 0 to N_TABLES - 1;
        wavetable_address       : std_logic_vector(WAVETABLE_SIZE_LOG2 - 1 downto 0);
        frames_log2             : integer range 0 to FRAMES_MAX_LOG2; 
    end record;

    constant REG_INIT : t_dma_ctrl_reg := (
        state                   => idle,
        dma2table               => (others => DMA2TABLE_INIT),
        sdram_input             => SDRAM_INPUT_INIT,
        new_table               => (others => '0'),
        table_index             => 0,
        wavetable_address       => (others => '0'),
        frames_log2             => 0
    );

    signal r, r_in              : t_dma_ctrl_reg;

begin

    comb_process : process (r, config, sdram_output, table2dma)
    begin

    r_in <= r;
    r_in.sdram_input <= SDRAM_INPUT_INIT;

    dma2table <= r.dma2table;
    sdram_input <= r.sdram_input;
    
    for i in 0 to N_TABLES - 1 loop
        r_in.dma2table(i).done <= '0';
        r_in.dma2table(i).write_enable <= '0';
        r_in.dma2table(i).write_address <= (others => '0');
        r_in.dma2table(i).write_data <= (others => '0');

        -- Register new_table strobes as sticky bits.
        r_in.new_table(i) <= '1' when config.dma_input(i).new_table = '1';
    end loop;

    case r.state is 

    -- Check new table strobes in round robin.
    when idle => 

        if r.new_table(r.table_index) = '1' then 
            r_in.new_table(r.table_index) <= '0';
            r_in.dma2table(r.table_index).req <= '1';
            r_in.state <= wait_ack;

        elsif r.table_index = N_TABLES - 1 then 
            r_in.table_index <= 0;
        else 
            r_in.table_index <= r.table_index + 1;
        end if;

    -- Wait for the wavetable to acknowledge the DMA transfer.
    when wait_ack => 
        if table2dma(r.table_index).ack = '1' then 
            r_in.dma2table(r.table_index).req <= '0';
            r_in.state <= sdram_read;
        end if;

    -- Initiate wavetable DMA by issueing an SDRAM read. 
    when sdram_read => 

        r_in.sdram_input.address <= config.dma_input(r.table_index).base_address;
        r_in.sdram_input.burst_length <= 2**config.dma_input(r.table_index).frames_log2 * MIPMAP_TABLE_SIZE;

        -- Register and wait until the DMA transfer is complete to update the table size.
        r_in.frames_log2 <= config.dma_input(r.table_index).frames_log2;

        if sdram_output.ack = '1' then
            r_in.wavetable_address <= (others => '0');
            r_in.state <= transfer ;
        else
            r_in.sdram_input.read_enable <= '1';
        end if;

    -- Perform wavetable DMA by forwarding data from the SDRAM read to the oscillator wavetable RAM.
    when transfer  => 

        if sdram_output.read_valid = '1' then

            r_in.dma2table(r.table_index).write_enable <= '1';
            r_in.dma2table(r.table_index).write_address <= r.wavetable_address;

            -- Filter out X signals to avoid issues with simulating IIR filters downstream.
            if SIMULATION then 
                for i in 0 to SDRAM_WIDTH - 1 loop 
                    r_in.dma2table(r.table_index).write_data(i) <= '0' when sdram_output.read_data(i) = 'X' else sdram_output.read_data(i);
                end loop;
            else 
                r_in.dma2table(r.table_index).write_data <= sdram_output.read_data;
            end if;

            if sdram_output.done = '1' then
                r_in.dma2table(r.table_index).frames_log2 <= r.frames_log2;
                r_in.dma2table(r.table_index).done <= '1';
        
                r_in.state <= idle;
            else
                r_in.wavetable_address <= std_logic_vector(unsigned(r.wavetable_address) + 1);
            end if;
        end if;

    end case;

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
 