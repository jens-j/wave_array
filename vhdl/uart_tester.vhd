library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xil_defaultlib;

library wave;
use wave.wave_array_pkg.all;


entity uart_tester is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        uart_tx                 : out std_logic
    );
end entity;

architecture arch of uart_tester is

        signal s_tx_done            : std_logic;
        signal s_tx_dv              : std_logic;
        signal s_tx_active          : std_logic;
        signal s_tx_byte            : std_logic_vector(7 downto 0);

        signal s_tx_fifo_wr_en      : std_logic;
        signal s_tx_fifo_empty      : std_logic;
        signal s_tx_fifo_rd_en      : std_logic;
        signal s_tx_fifo_din        : std_logic_vector(7 downto 0);

begin

    -- Write to led register ([0x00000002] = 0x01).
    s_tx_fifo_wr_en <= '0',
                       '1' after 1000 ns,
                       '0' after 1070 ns;
    s_tx_fifo_din <= x"00",
                     x"02" after 1000 ns,-- opcode
                     x"00" after 1010 ns,-- address
                     x"00" after 1020 ns,
                     x"00" after 1030 ns,
                     x"02" after 1040 ns,
                     x"00" after 1050 ns, -- data
                     x"01" after 1060 ns;

    s_tx_fifo_rd_en <= not s_tx_fifo_empty and not s_tx_active;
    s_tx_dv <= not s_tx_fifo_empty;


    tx_uart : entity wave.uart_tx
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / UART_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map(
        i_Clk                   => clk,
        i_TX_DV                 => s_tx_dv,
        i_TX_Byte               => s_tx_byte,
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
        dout                    => s_tx_byte,
        full                    => open,
        empty                   => s_tx_fifo_empty
    );

end architecture;
