library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_clk_enable is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        enable                  : out std_logic
    );
end entity;

architecture arch of i2s_clk_enable is

    signal counter : unsigned(1 downto 0) := "00";

begin

    proc : process (clk, counter)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter <= "00";
            else
                counter <= counter + 1;
            end if;
        end if;

        if counter = 0 then
            enable <= '1';
        else
            enable <= '0';
        end if;
    end process;

end architecture;
