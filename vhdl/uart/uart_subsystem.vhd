library IEEE;
use IEEE.std_logic_1164.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;
library uart;

-- This entity receives packets over the UART interface and handles the protocol to perform
-- register and SDRAM reads and writes. Two 2048 word deep FWFT FIFO's connect the UART tranceiver
-- and transmitter to the packet engine.
entity uart_subsystem is
    port (
        clk                     : in  std_logic; -- System clock.
        reset                   : in  std_logic;

        -- Register file interface.
        register_output         : in  t_register_output;
        register_input          : out t_register_input;

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

        -- UART ports.
        UART_RX                 : in  std_logic;
        UART_TX                 : out std_logic;

        debug_flags             : out std_logic_vector(3 downto 0);
        debug_state             : out integer;
        debug_hk_fifo_count     : out integer
    );
end entity;

architecture arch of uart_subsystem is

    signal s_tx_done            : std_logic;
    signal s_tx_dv              : std_logic;
    signal s_tx_active          : std_logic;
    signal s_tx_fifo_dout       : std_logic_vector(7 downto 0);

    signal s_rx_fifo_wr_en      : std_logic;
    signal s_rx_fifo_din        : std_logic_vector(7 downto 0);

    signal s_tx_fifo_wr_en      : std_logic;
    signal s_tx_fifo_empty      : std_logic;
    signal s_tx_fifo_rd_en      : std_logic;
    signal s_tx_fifo_din        : std_logic_vector(7 downto 0);
    signal s_tx_fifo_full       : std_logic;
    signal s_tx_fifo_data_count : std_logic_vector(11 downto 0);

    signal s_rx_fifo_empty      : std_logic;
    signal s_rx_fifo_rd_en      : std_logic;
    signal s_rx_fifo_dout       : std_logic_vector(7 downto 0);
    signal s_rx_fifo_full       : std_logic;

begin

    s_tx_fifo_rd_en <= not s_tx_fifo_empty and not s_tx_active;
    s_tx_dv <= not s_tx_fifo_empty;


    packet_engine : entity uart.uart_packet_engine
    port map (
        clk                     => clk,
        reset                   => reset,
        rx_empty                => s_rx_fifo_empty,
        rx_read_enable          => s_rx_fifo_rd_en,
        rx_data                 => s_rx_fifo_dout,
        tx_write_enable         => s_tx_fifo_wr_en,
        tx_data                 => s_tx_fifo_din,
        tx_data_count           => s_tx_fifo_data_count,
        register_output         => register_output,
        register_input          => register_input,
        sdram_input             => sdram_input,
        sdram_output            => sdram_output,
        hk_write_enable         => hk_write_enable,
        hk_data                 => hk_data,
        hk_full                 => hk_full,
        hk_count                => hk_count,
        wave_write_enable       => wave_write_enable,
        wave_data               => wave_data,
        wave_full               => wave_full,
        wave_count              => wave_count,
        debug_flags             => debug_flags,
        debug_state             => debug_state,
        debug_hk_fifo_count     => debug_hk_fifo_count
    );


    rx_uart : entity uart.uart_rx
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / UART_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map(
        i_Clk                   => clk,
        o_RX_DV                 => s_rx_fifo_wr_en,
        o_RX_Byte               => s_rx_fifo_din,
        i_RX_Serial             => UART_RX
    );


    rx_fifo : entity xil_defaultlib.uart_fifo_gen
    port map (
        clk                     => clk,
        srst                    => reset,
        din                     => s_rx_fifo_din,
        wr_en                   => s_rx_fifo_wr_en,
        rd_en                   => s_rx_fifo_rd_en,
        dout                    => s_rx_fifo_dout,
        full                    => s_rx_fifo_full,
        empty                   => s_rx_fifo_empty,
        data_count              => open
    );


    tx_uart : entity uart.uart_tx
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / UART_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map(
        i_Clk                   => clk,
        i_TX_DV                 => s_tx_dv,
        i_TX_Byte               => s_tx_fifo_dout,
        o_TX_Active             => s_tx_active,
        o_TX_Serial             => UART_TX,
        o_TX_Done               => s_tx_done
    );


    tx_fifo : entity xil_defaultlib.uart_fifo_gen
    port map (
        clk                     => clk,
        srst                    => reset,
        din                     => s_tx_fifo_din,
        wr_en                   => s_tx_fifo_wr_en,
        rd_en                   => s_tx_fifo_rd_en,
        dout                    => s_tx_fifo_dout,
        full                    => s_tx_fifo_full,
        empty                   => s_tx_fifo_empty,
        data_count              => s_tx_fifo_data_count
    );
end architecture;
