library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Linear feedback shift register with a cycle of 2**16 - 1
-- (all combinations of 16 bits except zero).
-- This gives an unique value for each pixel
-- The output is updated when readEnable is asserted.
entity lfsr16 is
    generic (
        INIT_VALUE              : std_logic_vector(15 downto 0) := x"0001"
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        read_enable             : in  std_logic;
        bit_out                 : out std_logic
    );
end entity;

architecture arch of lfsr16 is

    signal shift_reg : std_logic_vector(15 downto 0);

begin

    bit_out <= shift_reg(0);

    reg_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                shift_reg <= INIT_VALUE;
            elsif read_enable = '1' then
                shift_reg(15 downto 1) <= shift_reg(14 downto 0);
                shift_reg(0) <= shift_reg(15) xnor shift_reg(14) xnor shift_reg(12) xnor shift_reg(3);
            end if;
        end if;
    end process;

end architecture;
