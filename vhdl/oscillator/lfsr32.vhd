library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity lfsr32 is 
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        read_enable             : in  std_logic;
        output_valid            : out std_logic;
        output_data             : out std_logic
    );
end entity;


architecture arch of lfsr32 is

    signal s_shift_register : std_logic_vector(31 downto 0);
    signal s_output_valid   : std_logic;

begin

    output_data <= s_shift_register(0);
    output_valid <= s_output_valid;

    clk_proc : process (clk, reset)
    begin
        if rising_edge(clk) then 
        
            s_output_valid <= '0';

            if reset = '1' then 
                s_shift_register <= x"0000_0001";
            elsif read_enable = '1' then  
                s_output_valid <= '1';
                s_shift_register(31 downto 1) <= s_shift_register(30 downto 0);
                s_shift_register(0) <= s_shift_register(0) xor s_shift_register(1) 
                    xor s_shift_register(21) xor s_shift_register(31);
            end if;
        end if;
    end process;

end architecture;

