library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xil_defaultlib;

library wave;
use wave.wave_array_pkg.all;


entity uart_tester is
    generic (
        FILENAME                : string
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;

        -- UART interface.
        uart_rx                 : in  std_logic;
        uart_tx                 : out std_logic
    );
end entity;

architecture arch of uart_tester is

        signal s_tx_done            : std_logic;
        signal s_tx_dv              : std_logic;
        signal s_tx_active          : std_logic;
        signal s_tx_fifo_wr_en      : std_logic;
        signal s_tx_fifo_empty      : std_logic;
        signal s_tx_fifo_rd_en      : std_logic;
        signal s_tx_fifo_full       : std_logic;
        signal s_tx_fifo_din        : std_logic_vector(7 downto 0);
        signal s_tx_fifo_dout       : std_logic_vector(7 downto 0);

        signal s_rx_fifo_wr_en      : std_logic;
        signal s_rx_fifo_rd_en      : std_logic;
        signal s_rx_fifo_empty      : std_logic;
        signal s_rx_fifo_din        : std_logic_vector(7 downto 0);
        signal s_rx_fifo_dout       : std_logic_vector(7 downto 0);

begin

    s_tx_fifo_rd_en <= not s_tx_fifo_empty and not s_tx_active;
    s_tx_dv <= not s_tx_fifo_empty;

    reader : entity wave.uart_reader
    generic map (
        FILENAME                => FILENAME
    )
    port map (
        clk                     => clk,
        reset                   => reset,

        -- UART rx fifo interface.
        empty                   => s_rx_fifo_empty,
        read_enable             => s_rx_fifo_rd_en,
        read_data               => s_rx_fifo_dout,

        -- UART tx fifo interface.
        full                    => s_tx_fifo_full,
        write_enable            => s_tx_fifo_wr_en,
        write_data              => s_tx_fifo_din
    );

    rx_uart : entity wave.uart_rx
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / UART_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map(
        i_Clk                   => clk,
        o_RX_DV                 => s_rx_fifo_wr_en,
        o_RX_Byte               => s_rx_fifo_din,
        i_RX_Serial             => uart_rx
    );

    rx_fifo : entity xil_defaultlib.uart_fifo_gen
    port map (
        clk                     => clk,
        srst                    => reset,
        din                     => s_rx_fifo_din,
        wr_en                   => s_rx_fifo_wr_en,
        rd_en                   => s_rx_fifo_rd_en,
        dout                    => s_rx_fifo_dout,
        full                    => open,
        empty                   => s_rx_fifo_empty
    );

    tx_uart : entity wave.uart_tx
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / UART_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map(
        i_Clk                   => clk,
        i_TX_DV                 => s_tx_dv,
        i_TX_Byte               => s_tx_fifo_dout,
        o_TX_Active             => s_tx_active,
        o_TX_Serial             => uart_tx,
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
        empty                   => s_tx_fifo_empty
    );

end architecture;
