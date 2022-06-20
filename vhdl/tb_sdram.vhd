library ieee;
use ieee.std_logic_1164.all;

library wave;
use wave.wave_array_pkg.all;

library cellram;
library xil_defaultlib;


entity tb_sdram is
end entity;

architecture arch of tb_sdram is

    signal s_clk                : std_logic := '0';
    signal s_sys_clk            : std_logic;
    signal s_reset              : std_logic;
    signal s_locked             : std_logic;

    signal s_sdram_inputs       : t_sdram_input_array(0 to 1);
    signal s_sdram_outputs      : t_sdram_output_array(0 to 1);

    signal s_cram_clk           : std_logic;
    signal s_cram_advn          : std_logic;
    signal s_cram_cen           : std_logic;
    signal s_cram_cre           : std_logic;
    signal s_cram_oen           : std_logic;
    signal s_cram_wen           : std_logic;
    signal s_cram_lbn           : std_logic;
    signal s_cram_ubn           : std_logic;
    signal s_cram_wait          : std_logic;
    signal s_cram_a             : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
    signal s_cram_dq            : std_logic_vector(SDRAM_WIDTH - 1 downto 0);

begin

    s_clk <= not s_clk after 10 ns;
    s_reset <= '1', '0' after 1200 ns;

    s_sdram_inputs(0).burst_length <= 16;
    s_sdram_inputs(0).write_enable <= '1'; -- , '0' after 2 us;
    s_sdram_inputs(0).read_enable <= '0';
    s_sdram_inputs(1).write_data <= x"1234";
    s_sdram_inputs(0).address <= 23x"000000";

    s_sdram_inputs(1).burst_length <= 16;
    s_sdram_inputs(1).read_enable <= '1';
    s_sdram_inputs(1).write_enable <= '0';
    s_sdram_inputs(1).write_data <= (others => '0');
    s_sdram_inputs(1).address <= 23x"000000";

    sys_clk : entity xil_defaultlib.sys_clk_generator
    port map (
        ext_clk                 => s_clk,
        system_clk              => s_sys_clk,
        sdram_clk               => s_cram_clk,
        reset                   => s_reset,
        locked                  => s_locked
    );

    arbiter : entity wave.sdram_arbiter
    generic map (
        N_CLIENTS               => 2
    )
    port map (
        clk                     => s_clk,
        reset                   => s_reset,
        pll_lock                => s_locked,
        sdram_inputs            => s_sdram_inputs,
        sdram_outputs           => s_sdram_outputs,
        CRAM_ADVN               => s_cram_advn,
        CRAM_CEN                => s_cram_cen,
        CRAM_CRE                => s_cram_cre,
        CRAM_OEN                => s_cram_oen,
        CRAM_WEN                => s_cram_wen,
        CRAM_LBN                => s_cram_lbn,
        CRAM_UBN                => s_cram_ubn,
        CRAM_WAIT               => s_cram_wait,
        CRAM_A                  => s_cram_a,
        CRAM_DQ                 => s_cram_dq
    );

    memory : entity cellram.cellram
    port map (
        clk                     => s_clk,
        adv_n                   => s_cram_advn,
        cre                     => s_cram_cre,
        o_wait                  => s_cram_wait,
        ce_n                    => s_cram_cen,
        oe_n                    => s_cram_oen,
        we_n                    => s_cram_wen,
        lb_n                    => s_cram_lbn,
        ub_n                    => s_cram_ubn,
        addr                    => s_cram_a,
        dq                      => s_cram_dq
    );

end architecture;
