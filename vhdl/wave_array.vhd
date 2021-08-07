library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.wave_array_pkg.all;

entity wave_array is
    port (
        EXT_CLK                 : in  std_logic;
        BTN_RESET               : in  std_logic;
        I2S_SCLK                : out std_logic;
        I2S_WSEL                : out std_logic;
        I2S_SDATA               : out std_logic
    );
end entity;

architecture arch of wave_array is

    signal clk_s                : std_logic;
    signal reset_s              : std_logic;
    signal sample_s             : sample_t;
    signal next_sample_s        : std_logic;

    component BUFG
    port (
        I: in std_logic;
        O: out std_logic);
    end component;

begin

    -- Connect inputs.
    reset_s <= not BTN_RESET;

    clk_buffer : BUFG
    port map(
        I => EXT_CLK,
        O => clk_s
    );
    -- clk_s <= EXT_CLK;

    saw : entity work.saw
    port map(
        clk                     => clk_s,
        reset                   => reset_s,
        next_sample             => next_sample_s,
        sample_out              => sample_s
    );

    i2s_interface : entity work.i2s_interface
    port map(
        clk                     => clk_s,
        reset                   => reset_s,
        sample_in               => sample_s,
        next_sample             => next_sample_s,
        sdata                   => I2S_SDATA,
        sclk                    => I2S_SCLK,
        wsel                    => I2S_WSEL
    );

end architecture;
