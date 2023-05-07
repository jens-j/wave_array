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

    constant BURST_LENGTH       : integer := 272; -- Two full bursts + 16.

    signal s_clk                : std_logic := '0';
    signal s_sys_clk            : std_logic;
    signal s_reset              : std_logic;
    signal s_sdram_clk_enable   : std_logic;
    signal s_locked             : std_logic;

    signal s_sdram_inputs       : t_sdram_input_array(0 to 1) := (SDRAM_INPUT_INIT, SDRAM_INPUT_INIT);
    signal s_sdram_outputs      : t_sdram_output_array(0 to 1);

    signal s_sdram_clk           : std_logic;
    signal s_sdram_advn          : std_logic;
    signal s_sdram_cen           : std_logic;
    signal s_sdram_cre           : std_logic;
    signal s_sdram_oen           : std_logic;
    signal s_sdram_wen           : std_logic;
    signal s_sdram_lbn           : std_logic;
    signal s_sdram_ubn           : std_logic;
    signal s_sdram_wait          : std_logic;
    signal s_sdram_address       : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
    signal s_sdram_dq            : std_logic_vector(SDRAM_WIDTH - 1 downto 0);

    component cellram is
    port (
        clk                     : in    std_logic;
        adv_n                   : in    std_logic;
        cre                     : in    std_logic;
        o_wait                  : out   std_logic;
        ce_n                    : in    std_logic;
        oe_n                    : in    std_logic;
        we_n                    : in    std_logic;
        lb_n                    : in    std_logic;
        ub_n                    : in    std_logic;
        addr                    : in    std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        dq                      : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0));
    end component;

begin

    s_clk <= not s_clk after 10 ns;
    s_reset <= '1', '0' after 1200 ns;

    test_inputs : process 

    begin 

        wait until s_reset = '0';

        -- Burst write.
        s_sdram_inputs(0).write_enable <= '1';
        s_sdram_inputs(0).burst_length <= BURST_LENGTH;
        s_sdram_inputs(0).address <= 23x"000000";

        wait until rising_edge(s_sys_clk) and s_sdram_outputs(0).ack = '1';
        s_sdram_inputs(0).write_enable <= '0';

        for i in 0 to BURST_LENGTH - 1 loop 
            s_sdram_inputs(0).write_data <= std_logic_vector(to_unsigned(i, SDRAM_WIDTH));
            wait until rising_edge(s_sys_clk) and 
                (s_sdram_outputs(0).write_req = '1' or s_sdram_outputs(0).done = '1');
        end loop;

        -- Burst read.
        s_sdram_inputs(1).read_enable <= '1';
        s_sdram_inputs(1).burst_length <= BURST_LENGTH;
        s_sdram_inputs(1).address <= 23x"000000";

        wait until rising_edge(s_sys_clk) and s_sdram_outputs(1).ack = '1';
        s_sdram_inputs(1).read_enable <= '0';        

    end process;

    sys_clk : entity xil_defaultlib.sys_clk_generator
    port map (
        ext_clk                 => s_clk,
        system_clk              => s_sys_clk,
        sdram_clk               => s_sdram_clk,
        reset                   => s_reset,
        sdram_clk_ce            => s_sdram_clk_enable,
        locked                  => s_locked
    );

    arbiter : entity adram.sdram_arbiter
    generic map (
        N_CLIENTS               => 2
    )
    port map (
        clk                     => s_sys_clk,
        sdram_clk               => s_sdram_clk,
        reset                   => s_reset,
        pll_locked              => s_locked,
        sdram_clk_enable        => s_sdram_clk_enable,
        sdram_inputs            => s_sdram_inputs,
        sdram_outputs           => s_sdram_outputs,
        SDRAM_ADVN              => s_sdram_advn,
        SDRAM_CEN               => s_sdram_cen,
        SDRAM_CRE               => s_sdram_cre,
        SDRAM_OEN               => s_sdram_oen,
        SDRAM_WEN               => s_sdram_wen,
        SDRAM_LBN               => s_sdram_lbn,
        SDRAM_UBN               => s_sdram_ubn,
        SDRAM_WAIT              => s_sdram_wait,
        SDRAM_ADDRESS           => s_sdram_address,
        SDRAM_DQ                => s_sdram_dq
    );

    sdram : cellram
    port map (
        clk                     => s_sdram_clk,
        adv_n                   => s_sdram_advn,
        cre                     => s_sdram_cre,
        o_wait                  => s_sdram_wait,
        ce_n                    => s_sdram_cen,
        oe_n                    => s_sdram_oen,
        we_n                    => s_sdram_wen,
        lb_n                    => s_sdram_lbn,
        ub_n                    => s_sdram_ubn,
        addr                    => s_sdram_address,
        dq                      => s_sdram_dq
    );

end architecture;
