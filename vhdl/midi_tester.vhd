library ieee;
use ieee.std_logic_1164.all;

library ip;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;


entity midi_tester is
    generic (
        FILENAME                : string := "midi.txt"
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        uart_tx                 : out std_logic
    );
end entity;

architecture arch of midi_tester is

    signal uart_byte_s          : std_logic_vector(7 downto 0);
    signal uart_dv_s            : std_logic;
    signal uart_active_s        : std_logic;
    signal uart_done_s          : std_logic;

    signal fifo_din_s           : std_logic_vector(7 downto 0);
    signal fifo_rd_en_s         : std_logic;
    signal fifo_wr_en_s         : std_logic;
    signal fifo_empty_s         : std_logic;
    signal fifo_full_s          : std_logic;
    signal fifo_count_s         : std_logic_vector(4 downto 0);

begin

    uart_dv_s    <= not fifo_empty_s;
    fifo_rd_en_s <= uart_done_s and not uart_active_s and not fifo_empty_s;

    reader : entity wave.midi_reader
    generic map(
        FILENAME                => FILENAME
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        full                    => fifo_full_s,
        write_enable            => fifo_wr_en_s,
        data                    => fifo_din_s
    );

    uart : entity wave.uart_tx
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / MIDI_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map (
        i_Clk                   => clk,
        i_TX_DV                 => uart_dv_s,
        i_TX_Byte               => uart_byte_s,
        o_TX_Active             => uart_active_s,
        o_TX_Serial             => uart_tx,
        o_TX_Done               => uart_done_s
    );

    midi_fifo : entity ip.midi_fifo
    port map (
        clk                     => clk,
        srst                    => reset,
        din                     => fifo_din_s,
        wr_en                   => fifo_wr_en_s,
        rd_en                   => fifo_rd_en_s,
        dout                    => uart_byte_s,
        full                    => fifo_full_s,
        empty                   => fifo_empty_s,
        data_count              => fifo_count_s
    );

end architecture;
