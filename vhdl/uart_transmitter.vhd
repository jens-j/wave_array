library IEEE;
use IEEE.std_logic_1164.all;

library xil_defaultlib;

library wave;
use wave.wave_array_pkg.all;


-- UART transmitter with 8-bit fifo buffer
entity uart_transmitter is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        data_valid              : in  std_logic;
        data_in                 : in  std_logic_vector(7 downto 0);
        full                    : out std_logic;
        UART_TX                 : out std_logic
    );
end entity;

architecture arch of uart_transmitter is

    signal s_fifo_dout          : std_logic_vector(7 downto 0);
    signal s_fifo_empty         : std_logic;
    signal s_uart_done          : std_logic;
    -- signal r_uart_done          : std_logic;


begin

    -- reg_proc : process (clk)
    -- begin
    --     if rising_edge(clk) then
    --         r_uart_done <= s_uart_done;
    --     end if;
    -- end process;


    tx_fifo : entity xil_defaultlib.uart_tx_fifo_gen
    port map (
        clk                     => clk,
        srst                    => reset,
        din                     => data_in,
        wr_en                   => data_valid,
        rd_en                   => s_uart_done and not s_fifo_empty,
        dout                    => s_fifo_dout,
        full                    => full,
        empty                   => s_fifo_empty
    );

    uart : entity wave.uart_tx
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / UART_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map(
        i_Clk                   => clk,
        i_TX_DV                 => not s_fifo_empty,
        i_TX_Byte               => s_fifo_dout,
        o_TX_Active             => open,
        o_TX_Serial             => UART_TX,
        o_TX_Done               => s_uart_done
    );


end architecture;
