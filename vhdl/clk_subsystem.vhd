library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xil_defaultlib;

library unisim;
use unisim.vcomponents.all;

library ip;


entity clk_subsystem is
    port (
        reset                   : in  std_logic;
        ext_clk                 : in  std_logic; -- 100 MHz.
        system_clk              : out std_logic; -- 100 MHz.
        i2s_clk                 : out std_logic; -- 1.5360175 MHz.
        mig_ref_clk             : out std_logic; -- 400 MHz.
        pll_locked              : out std_logic  -- SDRAM clock PLL locked.
    );
end entity;

architecture arch of clk_subsystem is

    signal s_system_clk           : std_logic;
    signal s_i2s_intermediate_clk : std_logic;
    signal s_counter              : unsigned(1 downto 0) := "00";

    -- Component is necessary because the ip is in verilog.
    component sys_clk_generator
    port (
        system_clk             : out std_logic;
        mig_ref_clk            : out std_logic;
        reset                  : in  std_logic;
        ext_clk                : in  std_logic;
        locked              : out std_logic
    );
    end component;
    
    -- Component is necessary because the ip is in verilog.
    component i2s_clk_generator
    port (
        i2s_intermediate_clk   : out std_logic;
        reset                  : in  std_logic;
        sys_clk                : in  std_logic
    );
    end component;

begin

    system_clk <= s_system_clk;

    sys_clk_gen : sys_clk_generator
    port map (
        system_clk             => s_system_clk,
        mig_ref_clk            => mig_ref_clk,
        reset                  => reset,
        ext_clk                => ext_clk,
        locked                 => pll_locked
    );

    i2s_clk_gen : i2s_clk_generator
    port map (
        i2s_intermediate_clk   => s_i2s_intermediate_clk,
        reset                  => reset,
        sys_clk                => s_system_clk
    );

    -- Global clock buffer for the I2S clock.
    i2s_bufg : BUFG
    port map (
        I => s_counter(1),
        O => i2s_clk
    );

    -- Devide the clock by four using a counter.
    proc : process (s_i2s_intermediate_clk)
    begin
        if rising_edge(s_i2s_intermediate_clk) then
            if reset = '1' then
                s_counter <= "00";
            else
                s_counter <= s_counter + 1;
            end if;
        end if;
    end process;


end architecture;
