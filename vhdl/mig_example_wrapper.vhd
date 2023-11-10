library ieee;
use ieee.std_logic_1164.all;


entity mig_example_wrapper is 
   port (
      EXT_CLK                 : in    std_logic;
      BTN_RESET               : in    std_logic;
      LEDS                    : out   std_logic_vector(7 downto 0);

      ddr3_dq                 : inout std_logic_vector(15 downto 0);
      ddr3_dqs_n              : inout std_logic_vector(1 downto 0);
      ddr3_dqs_p              : inout std_logic_vector(1 downto 0);
      ddr3_addr               : out   std_logic_vector(14 downto 0);
      ddr3_ba                 : out   std_logic_vector(2 downto 0);
      ddr3_ras_n              : out   std_logic;
      ddr3_cas_n              : out   std_logic;
      ddr3_we_n               : out   std_logic;
      ddr3_reset_n            : out   std_logic;
      ddr3_ck_p               : out   std_logic_vector(0 downto 0);
      ddr3_ck_n               : out   std_logic_vector(0 downto 0);
      ddr3_cke                : out   std_logic_vector(0 downto 0);
      ddr3_dm                 : out   std_logic_vector(1 downto 0);
      ddr3_odt                : out   std_logic_vector(0 downto 0)
   );
end entity;


architecture arch of mig_example_wrapper is 

   component wrapper_clk_gen
      port (
         ext_clk                 : in  std_logic;
         mig_sys_clk             : out std_logic;
         mig_ref_clk             : out std_logic;
         locked                  : out std_logic
      );
   end component;

   component example_top 
      port (
         ddr3_dq                 : inout std_logic_vector(15 downto 0);
         ddr3_dqs_n              : inout std_logic_vector(1 downto 0);
         ddr3_dqs_p              : inout std_logic_vector(1 downto 0);
         ddr3_addr               : out   std_logic_vector(14 downto 0);
         ddr3_ba                 : out   std_logic_vector(2 downto 0);
         ddr3_ras_n              : out   std_logic;
         ddr3_cas_n              : out   std_logic;
         ddr3_we_n               : out   std_logic;
         ddr3_reset_n            : out   std_logic;
         ddr3_ck_p               : out   std_logic_vector(0 downto 0);
         ddr3_ck_n               : out   std_logic_vector(0 downto 0);
         ddr3_cke                : out   std_logic_vector(0 downto 0);
         ddr3_dm                 : out   std_logic_vector(1 downto 0);
         ddr3_odt                : out   std_logic_vector(0 downto 0);
         sys_clk_i               : in    std_logic;
         clk_ref_i               : in    std_logic;
         tg_compare_error        : out   std_logic;
         init_calib_complete     : out   std_logic;         
         sys_rst                 : in    std_logic
      ); 
   end component;

   signal s_sys_clk              : std_logic;
   signal s_ref_clk              : std_logic;
   signal s_locked               : std_logic;
   signal s_tg_compare_error     : std_logic;
   signal s_init_calib_complete  : std_logic;
   signal s_reset                : std_logic;
   
begin

   s_reset <= not BTN_RESET;

   LEDS <= (7 downto 3 => '0') & s_tg_compare_error & s_init_calib_complete & s_reset;

   pll : wrapper_clk_gen 
   port map (
      ext_clk                 => EXT_CLK,
      mig_sys_clk             => s_sys_clk,
      mig_ref_clk             => s_ref_clk,
      locked                  => s_locked
   );

   mig_ex : example_top
   port map (
      ddr3_dq                 => ddr3_dq,
      ddr3_dqs_n              => ddr3_dqs_n,
      ddr3_dqs_p              => ddr3_dqs_p,
      ddr3_addr               => ddr3_addr,
      ddr3_ba                 => ddr3_ba,
      ddr3_ras_n              => ddr3_ras_n,
      ddr3_cas_n              => ddr3_cas_n,
      ddr3_we_n               => ddr3_we_n,
      ddr3_reset_n            => ddr3_reset_n,
      ddr3_ck_p               => ddr3_ck_p,
      ddr3_ck_n               => ddr3_ck_n,
      ddr3_cke                => ddr3_cke,
      ddr3_dm                 => ddr3_dm,
      ddr3_odt                => ddr3_odt,
      sys_clk_i               => s_sys_clk,
      clk_ref_i               => s_ref_clk,
      tg_compare_error        => s_tg_compare_error,
      init_calib_complete     => s_init_calib_complete,         
      sys_rst                 => s_reset
   );

end architecture;