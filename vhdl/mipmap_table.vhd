library ieee;
use ieee.std_logic_1164.all;

library wave;
use wave.wave_array_pkg.all;


entity mapmap_table is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        table_inputs            : in  t_table_arb_input_array(0 to NUMBER_OF_VOICES - 1);
        table_outputs           : out t_table_arb_output_array(0 to NUMBER_OF_VOICES - 1)
    );
end entity;

architecture arch of mapmap_table is

    -- Blockram signals.
    signal ren_s                : std_logic;
    signal raddr_s              : std_logic_vector(WAVE_RES_LOG2-1 downto 0);
    signal rdata_s              : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal wen_s                : std_logic;
    signal waddr_s              : std_logic_vector(WAVE_RES_LOG2-1 downto 0);
    signal wdata_s              : std_logic_vector(SAMPLE_WIDTH-1 downto 0);

begin

    arbiter : entity wave.table_arbiter
    port map (
        clk                     => clk,
        reset                   => reset,
        table_inputs            => table_inputs,
        table_outputs           => table_outputs,
        ram_read_enable         => ren_s,
        ram_address             => raddr_s,
        ram_data                => rdata_s
    );

    -- Wave table ram
    wave_ram : entity wave.blockram
    generic map (
        abits       => TABLE_ADDR_SIZE,
        dbits       => SAMPLE_WIDTH,
        init_file   => "sine.data"
    )
    port map(
        rclk        => clk,
        wclk        => clk,
        ren         => ren_s,
        raddr       => raddr_s,
        rdata       => rdata_s,
        wen         => wen_s,
        waddr       => waddr_s,
        wdata       => wdata_s
    );

end architecture;
