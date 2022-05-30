library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library ip;


entity clk_subsystem is
    port (
        reset                   : in  std_logic;
        ext_clk                 : in  std_logic;
        system_clk              : out std_logic;
        i2s_clk                 : out std_logic
    );
end entity;

architecture arch of clk_subsystem is

    signal s_i2s_intermediate_clk : std_logic;
    signal s_counter : unsigned(1 downto 0) := "00";

    -- Component is necessary because the ip is in verilog.
    component clk_generator
    port (
         system_clk             : out std_logic;
         i2s_intermediate_clk   : out std_logic;
         reset                  : in  std_logic;
         ext_clk                : in  std_logic
        );
    end component;

begin

    clk_gen : clk_generator
    port map (
         system_clk             => system_clk,
         i2s_intermediate_clk   => s_i2s_intermediate_clk,
         reset                  => reset,
         ext_clk                => ext_clk
    );

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
