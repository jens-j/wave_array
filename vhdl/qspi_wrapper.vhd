library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library qspi;


-- Wrapper around opencores IP.
-- Implements a DMA between the PMOD QSPI and the SDRAM.
entity qspi_wrapper is 
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        sdram_input             : out t_sdram_input;
        sdram_output            : in  t_sdram_output;
        i_in                    : in  std_logic;
        o_out                   : out std_logic;
        QSPI_SCLK               : out std_logic;
        QSPI_CS                 : out std_logic;
        QSPI_DQ                 : inout std_logic_vector(3 downto 0)
    );
end entity;


architecture arch of qspi_wrapper is 

    component test_wrapper is
        -- generic (
        --     LGFLASHSZ               : integer;
        --     OPT_PIPE                : std_logic;
        --     OPT_CFG                 : std_logic;
        --     OPT_STARTUP             : std_logic;
        --     OPT_CLKDIV              : integer;
        --     OPT_ENDIANSWAP          : std_logic;
        --     RDDELAY                 : integer;
        --     NDUMMY                  : integer;
        --     OPT_STARTUP_FILE        : String
        -- );
        port (
            i_clk                   : in  std_logic;
            i_reset                 : in  std_logic;
            i_in                    : in  std_logic;
            o_out                   : out std_logic

            -- i_wb_cyc                : in  std_logic;
            -- i_wb_stb                : in  std_logic;
            -- i_cfg_stb               : in  std_logic;
            -- i_wb_we                 : in  std_logic;
            -- i_wb_addr               : in  std_logic_vector(22 downto 0);
            -- i_wb_data               : in  std_logic_vector(31 downto 0);
            -- o_wb_stall              : out std_logic;
            -- o_wb_ack                : out std_logic;
            -- o_wb_data               : out std_logic_vector(31 downto 0);

            -- o_qspi_sck              : out std_logic;
            -- o_qspi_cs_n             : out std_logic;
            -- o_qspi_mod              : out std_logic_vector(1 downto 0);
            -- o_qspi_dat              : out std_logic_vector(3 downto 0);
            -- i_qspi_dat              : in  std_logic_vector(3 downto 0)
        );
    end component;

    -- component qflexpress_wrapper is 
    -- port (
    --     i_clk                   : in  std_logic;
    --     i_reset                 : in  std_logic;
    --     i_wb_cyc                : in  std_logic;
    --     i_wb_stb                : in  std_logic;
    --     i_cfg_stb               : in  std_logic;
    --     i_wb_we                 : in  std_logic;
    --     i_wb_addr               : in  std_logic_vector(22 downto 0);
    --     i_wb_data               : in  std_logic_vector(31 downto 0);
    --     o_wb_stall              : out std_logic;
    --     o_wb_ack                : out std_logic;
    --     o_wb_data               : out std_logic_vector(31 downto 0);

    --     o_qspi_sck              : out std_logic;
    --     o_qspi_cs_n             : out std_logic;
    --     o_qspi_mod              : out std_logic_vector(1 downto 0);
    --     o_qspi_dat              : out std_logic_vector(3 downto 0);
    --     i_qspi_dat              : in  std_logic_vector(3 downto 0));
    -- end component;

    signal s_i_wb_cyc           : std_logic;
    signal s_i_wb_stb           : std_logic;
    signal s_i_cfg_stb          : std_logic;
    signal s_i_wb_we            : std_logic;
    signal s_i_wb_addr          : std_logic_vector(FLASH_DEPTH_LOG2 - 3 downto 0);
    signal s_i_wb_data          : std_logic_vector(31 downto 0);
    signal s_o_wb_stall         : std_logic;
    signal s_o_wb_ack           : std_logic;
    signal s_o_wb_data          : std_logic_vector(31 downto 0);

    signal s_o_qspi_sck         : std_logic;
    signal s_o_qspi_cs_n        : std_logic;
    signal s_o_qspi_mod         : std_logic_vector(1 downto 0);
    signal s_o_qspi_dat         : std_logic_vector(3 downto 0);
    signal s_i_qspi_dat         : std_logic_vector(3 downto 0);

begin

    -- Generate tri-state buffer.
    QSPI_DQ <= "11Z" & s_o_qspi_dat(0) when s_o_qspi_mod(1) = '0' else -- ESPI mode 
               "ZZZZ" when s_o_qspi_mod(0) = '1' else                  -- QSPI read 
               s_o_qspi_dat;                                           -- QSPI write

    s_i_qspi_dat <= QSPI_DQ;

    qspi_inst : entity qspi.qflexpress_wrapper 
    port map (
        i_clk                   => clk,
        i_reset                 => reset,
        i_wb_cyc                => s_i_wb_cyc, 
        i_wb_stb                => s_i_wb_stb, 
        i_cfg_stb               => s_i_cfg_stb, 
        i_wb_we                 => s_i_wb_we, 
        i_wb_addr               => s_i_wb_addr, 
        i_wb_data               => s_i_wb_data, 
        o_wb_stall              => s_o_wb_stall, 
        o_wb_ack                => s_o_wb_ack, 
        o_wb_data               => s_o_wb_data, 

        o_qspi_sck              => s_o_qspi_sck, 
        o_qspi_cs_n             => s_o_qspi_cs_n, 
        o_qspi_mod              => s_o_qspi_mod, 
        o_qspi_dat              => s_o_qspi_dat, 
        i_qspi_dat              => s_i_qspi_dat
    );

    -- qspi_inst: test_wrapper
    -- -- generic map (
    -- --     LGFLASHSZ               => FLASH_DEPTH_LOG2,
    -- --     OPT_PIPE                => '1',
    -- --     OPT_CFG                 => '1',
    -- --     OPT_STARTUP             => '1',
    -- --     OPT_CLKDIV              => 0,
    -- --     OPT_ENDIANSWAP          => '1', -- Use little endian.
    -- --     RDDELAY                 => 3,
    -- --     NDUMMY                  => 10,
    -- --     OPT_STARTUP_FILE        => ""
    -- -- )
    -- port map (
    --     i_clk                   => clk,
    --     i_reset                 => reset,
    --     i_in                    => i_in,
    --     o_out                   => o_out
    --     -- i_wb_cyc                => s_i_wb_cyc, 
    --     -- i_wb_stb                => s_i_wb_stb, 
    --     -- i_cfg_stb               => s_i_cfg_stb, 
    --     -- i_wb_we                 => s_i_wb_we, 
    --     -- i_wb_addr               => s_i_wb_addr, 
    --     -- i_wb_data               => s_i_wb_data, 
    --     -- o_wb_stall              => s_o_wb_stall, 
    --     -- o_wb_ack                => s_o_wb_ack, 
    --     -- o_wb_data               => s_o_wb_data, 

    --     -- o_qspi_sck              => s_o_qspi_sck, 
    --     -- o_qspi_cs_n             => s_o_qspi_cs_n, 
    --     -- o_qspi_mod              => s_o_qspi_mod, 
    --     -- o_qspi_dat              => s_o_qspi_dat, 
    --     -- i_qspi_dat              => s_i_qspi_dat
    -- );

end architecture;