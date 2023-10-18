library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;
library sdram;


entity tb_sdram is
end entity;


architecture arch of tb_sdram is

    constant N_BURSTS           : integer := 3; -- 3 SDRAM bursts of 8 words.

    signal s_clk                : std_logic := '0';
    signal s_system_clk         : std_logic;
    signal s_reset              : std_logic;
    signal s_mig_ref_clk        : std_logic;
    signal s_pll_locked         : std_logic;

    signal s_sdram_inputs       : t_sdram_input_array(0 to 1) := (SDRAM_INPUT_INIT, SDRAM_INPUT_INIT);
    signal s_sdram_outputs      : t_sdram_output_array(0 to 1);

    signal s_rst_n              : std_logic;
    signal s_ck                 : std_logic;
    signal s_ck_n               : std_logic;
    signal s_cke                : std_logic;
    signal s_ras_n              : std_logic;
    signal s_cas_n              : std_logic;
    signal s_we_n               : std_logic;
    signal s_dm_tdqs            : std_logic_vector(1 downto 0);
    signal s_ba                 : std_logic_vector(2 downto 0);
    signal s_addr               : std_logic_vector(14 downto 0);
    signal s_dq                 : std_logic_vector(15 downto 0);
    signal s_dqs                : std_logic_vector(1 downto 0);
    signal s_dqs_n              : std_logic_vector(1 downto 0);
    signal s_tdqs_n             : std_logic_vector(1 downto 0);
    signal s_odt                : std_logic; 

    component ddr3 is
    port (
        rst_n                       : in    std_logic;
        ck                          : in    std_logic;
        ck_n                        : in    std_logic;
        cke                         : in    std_logic;
        cs_n                        : in    std_logic;
        ras_n                       : in    std_logic;
        cas_n                       : in    std_logic;
        we_n                        : in    std_logic;
        dm_tdqs                     : inout std_logic_vector(1 downto 0);
        ba                          : in    std_logic_vector(2 downto 0);
        addr                        : in    std_logic_vector(14 downto 0);
        dq                          : inout std_logic_vector(15 downto 0);
        dqs                         : inout std_logic_vector(1 downto 0);
        dqs_n                       : inout std_logic_vector(1 downto 0);
        tdqs_n                      : out   std_logic_vector(1 downto 0);
        odt                         : in    std_logic);    
    end component;

begin

    s_clk <= not s_clk after 5 ns;
    s_reset <= '1', '0' after 200 us;

    test_inputs : process 

    begin 

        wait until s_reset = '0';

        -- Burst write.
        s_sdram_inputs(0).write_enable <= '1';
        s_sdram_inputs(0).burst_n <= N_BURSTS;
        s_sdram_inputs(0).address <= to_unsigned(0, SDRAM_DEPTH_LOG2);

        wait until rising_edge(s_system_clk) and s_sdram_outputs(0).ack = '1';
        s_sdram_inputs(0).write_enable <= '0';

        for i in 0 to 8 * N_BURSTS - 1 loop 
            s_sdram_inputs(0).write_data <= std_logic_vector(to_unsigned(i, SDRAM_WIDTH));
            wait until rising_edge(s_system_clk) and 
                (s_sdram_outputs(0).write_req = '1' or s_sdram_outputs(0).done = '1');
        end loop;

        -- Burst read.
        s_sdram_inputs(1).read_enable <= '1';
        s_sdram_inputs(1).burst_n <= N_BURSTS;
        s_sdram_inputs(1).address <= to_unsigned(0, SDRAM_DEPTH_LOG2);

        wait until rising_edge(s_system_clk) and s_sdram_outputs(1).ack = '1';
        s_sdram_inputs(1).read_enable <= '0';        

    end process;

    sys_clk : entity wave.clk_subsystem
    port map (
        ext_clk                 => s_clk,
        system_clk              => s_system_clk,
        i2s_clk                 => open,
        reset                   => s_reset,
        mig_ref_clk             => s_mig_ref_clk,
        pll_locked              => s_pll_locked
    );

    arbiter : entity sdram.ddr_arbiter
    generic map (
        N_CLIENTS               => 2
    )
    port map (
        clk                     => s_system_clk,
        mig_ref_clk             => s_mig_ref_clk,
        reset                   => s_reset,
        pll_locked              => s_pll_locked,
        sdram_inputs            => s_sdram_inputs,
        sdram_outputs           => s_sdram_outputs,
        DDR3_DQ                 => s_dq,
        DDR3_DQS_P              => s_dqs,
        DDR3_DQS_N              => s_dqs_n,
        DDR3_ADDR               => s_addr,
        DDR3_BA                 => s_ba,
        DDR3_RAS_N              => s_ras_n,
        DDR3_CAS_N              => s_cas_n,
        DDR3_WE_N               => s_we_n,
        DDR3_RESET_N            => s_rst_n,
        DDR3_CK_P               => s_ck,
        DDR3_CK_N               => s_ck_n,
        DDR3_CKE                => s_cke,
        DDR3_DM                 => s_dm_tdqs,
        DDR3_ODT                => s_odt
    );

    ddr3_verilog : ddr3
    port map (
        rst_n                   => s_rst_n,
        ck                      => s_ck,
        ck_n                    => s_ck_n,
        cke                     => s_cke,
        cs_n                    => '0',
        ras_n                   => s_ras_n,
        cas_n                   => s_cas_n,
        we_n                    => s_we_n,
        dm_tdqs                 => s_dm_tdqs,
        ba                      => s_ba,
        addr                    => s_addr,
        dq                      => s_dq,
        dqs                     => s_dqs,
        dqs_n                   => s_dqs_n,
        tdqs_n                  => s_tdqs_n,
        odt                     => s_odt 
    );

end architecture;
