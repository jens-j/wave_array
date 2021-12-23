library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library wave;
use wave.wave_array_pkg.all;


-- Divides the I2S clock down by 4, further than the PLL can.
entity clk_generator_wrapper is
    port (
        reset               : in  std_logic;
        ext_clk             : in  std_logic;
        system_clk          : out std_logic;
        i2s_clk             : out std_logic
    );
end entity;

architecture arch of clk_generator_wrapper is

    signal i2s_intermediate_clk_s   : std_logic;
    signal counter_r                : unsigned(1 downto 0);

    component BUFG
    port (
        I: in std_logic;
        O: out std_logic);
    end component;

    component clk_generator
    port (
        system_clk        : out    std_logic;
        i2s_clk           : out    std_logic;
        reset             : in     std_logic;
        ext_clk           : in     std_logic
    );
    end component;

begin

    clk_gen : clk_generator
    port map (
        system_clk => system_clk,
        i2s_clk => i2s_intermediate_clk_s,
        reset => reset,
        ext_clk => ext_clk
     );

    clk_buffer : BUFG
    port map(
        I => counter_r(1),
        O => i2s_clk
    );

    divider_proc : process (i2s_intermediate_clk_s)
    begin
        if rising_edge(i2s_intermediate_clk_s) then
            if reset = '1' then
                counter_r <= (others => '0');
            else
                counter_r <= counter_r + 1;
            end if;
        end if;
    end process;

end architecture;
