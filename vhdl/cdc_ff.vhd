library ieee;
use ieee.std_logic_1164.all;

-- Simply double buffer the input. 
entity cdc_ff is
    port (
        clk                     : in  std_logic;
        input                   : in  std_logic;
        output                  : out std_logic
    );
end entity;

architecture arch of cdc_ff is

    signal input_r : std_logic;
    signal input_r2 : std_logic;

begin

    output <= input_r2;

    ff_proc : process (clk)
    begin
        if rising_edge(clk) then 
            input_r <= input;
            input_r2 <= input_r;
        end if;
    end process;

end architecture;