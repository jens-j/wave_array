library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- writes wavetable frames from the full wavetable in the SDRAM to the wave table memory.
-- Writes are done with a stride of 4 and are offset by the wavetable memory index.
-- This is to conform to the unusual wavetable memory layout.
entity dma is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;

        -- DMA control interface.
        ctrl2dma                : in  t_ctrl2dma;
        dma2ctrl                : out t_dma2ctrl;

        -- Sdram interface.
        sdram_output            : in  t_sdram_output;
        sdram_input             : out t_sdram_input;

        -- Wave table memory interface.
        wave_mem_wea            : out std_logic_vector(0 downto 0);
        wave_mem_addra          : out std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 0);
        wave_mem_dina           : out std_logic_vector(SAMPLE_SIZE - 1 downto 0)
    );
end entity;

architecture arch of dma is

    type t_state is (idle, sdram_read, transfer);

    type t_dma_reg is record
        state                   : t_state;
        busy                    : std_logic;
        sdram_input             : t_sdram_input;
        wave_mem_wea            : std_logic_vector(0 downto 0);
        wave_mem_addra          : std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 0);
        wave_mem_dina           : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
        sdram_address           : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        wavetable_address       : std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 0);
    end record;

    constant REG_INIT : t_dma_reg := (
        state                   => idle,
        busy                    => '0',
        sdram_input             => SDRAM_INPUT_INIT,
        wave_mem_wea            => (others => '0'),
        wave_mem_addra          => (others => '0'),
        wave_mem_dina           => (others => '0'),
        sdram_address           => (others => '0'),
        wavetable_address       => (others => '0')
    );

    signal r, r_in              : t_dma_reg;

begin

    -- Connect output registers.
    dma2ctrl.busy <= r.busy;
    sdram_input <= r.sdram_input;
    wave_mem_wea <= r.wave_mem_wea;
    wave_mem_addra <= r.wave_mem_addra;
    wave_mem_dina <= r.wave_mem_dina;

    comb_process : process (r, ctrl2dma, sdram_output)
    begin

        r_in <= r;
        r_in.sdram_input <= SDRAM_INPUT_INIT;
        r_in.wave_mem_wea <= "0";
        r_in.wave_mem_addra <= (others => '0');
        r_in.wave_mem_dina <= (others => '0');

        if r.state = idle then
            if ctrl2dma.start = '1' then

                r_in.sdram_address <= ctrl2dma.address;
                r_in.wavetable_address <= std_logic_vector(
                    to_unsigned(ctrl2dma.index, MIPMAP_TABLE_SIZE_LOG2 + 2));

                r_in.busy <= '1';
                r_in.state <= sdram_read;
            end if;

        -- Issue SDRAM read. and wait for ack.
        elsif r.state = sdram_read then

            r_in.sdram_input.address <= r.sdram_address;
            r_in.sdram_input.burst_length <= MIPMAP_TABLE_SIZE;

            if sdram_output.ack = '1' then
                r_in.state <= transfer;
            else
                r_in.sdram_input.read_enable <= '1';
            end if;

        -- Send SDRAM read data to wavetable.
        -- Samples are written with stride 4 and offset by the table index.
        elsif r.state = transfer then

            if sdram_output.read_valid = '1' then

                r_in.wave_mem_wea <= "1";
                r_in.wave_mem_dina <= sdram_output.read_data;
                r_in.wave_mem_addra <= r.wavetable_address;

                if sdram_output.done = '1' then
                    r_in.state <= idle;
                    r_in.busy <= '0';
                else
                    r_in.wavetable_address <= std_logic_vector(unsigned(r.wavetable_address) + 4);
                end if;
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
