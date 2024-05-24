library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xil_defaultlib;

library unisim;
use unisim.vcomponents.all;

library wave;
use wave.wave_array_pkg.all;


entity clk_subsystem is
    port (
        reset                   : in  std_logic;
        ext_clk                 : in  std_logic; -- 100 MHz.
        mig_ctrl_clk            : out std_logic; -- 100 MHz.
        mig_ref_clk             : out std_logic; -- 200 MHz.
        i2s_clk                 : out std_logic; -- 1.5360175 MHz.
        spi_clk                 : out std_logic; -- 100 MHz 180 degrees out of phase.
        pll_locked              : out std_logic  -- SDRAM clock PLL locked.
    );
end entity;

architecture arch of clk_subsystem is

    signal s_mig_ctrl_clk         : std_logic;
    signal s_mig_ref_clk          : std_logic;
    signal s_i2s_intermediate_clk : std_logic;
    signal s_counter              : unsigned(1 downto 0) := "00";

    -- Component is necessary because the ip is in verilog.
    component sys_clk_generator
    port (
        mig_ctrl_clk           : out std_logic;
        mig_ref_clk            : out std_logic;
        spi_clk                : out std_logic;
        reset                  : in  std_logic;
        ext_clk                : in  std_logic;
        locked                 : out std_logic
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

    mig_ctrl_clk <= s_mig_ctrl_clk;
    mig_ref_clk <= s_mig_ref_clk;


    sys_clk_gen : sys_clk_generator
    port map (
        mig_ctrl_clk           => s_mig_ctrl_clk,
        mig_ref_clk            => s_mig_ref_clk,
        spi_clk                => spi_clk,
        reset                  => '0',
        ext_clk                => ext_clk,
        locked                 => pll_locked
    );

    i2s_clk_gen : i2s_clk_generator
    port map (
        i2s_intermediate_clk   => s_i2s_intermediate_clk,
        reset                  => '0',
        sys_clk                => s_mig_ctrl_clk
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
