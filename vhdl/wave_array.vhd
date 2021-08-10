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
        SWITCHES                : in  std_logic_vector(15 downto 0);
        LEDS                    : out std_logic_vector(15 downto 0);
        UART_RX                 : in  std_logic;
        UART_TX                 : out std_logic;
        I2S_SCLK                : out std_logic;
        I2S_WSEL                : out std_logic;
        I2S_SDATA               : out std_logic
    );
end entity;

architecture arch of wave_array is

    signal clk_s                : std_logic;
    signal reset_al_s           : std_logic;
    signal reset_ah_s           : std_logic;
    signal sample_s             : sample_t;
    signal next_sample_s        : std_logic;
    signal saw_slope_s          : std_logic_vector(15 downto 0);

    component BUFG
    port (
        I: in std_logic;
        O: out std_logic);
    end component;

begin

    -- Connect inputs.
    reset_ah_s <= not BTN_RESET;
    reset_al_s <= BTN_RESET;

    -- Connect outputs
    LEDS(15) <= BTN_RESET;

    clk_buffer : BUFG
    port map(
        I => EXT_CLK,
        O => clk_s
    );

    saw : entity work.saw
    port map(
        clk                     => clk_s,
        reset                   => reset_ah_s,
        slope                   => saw_slope_s,
        next_sample             => next_sample_s,
        sample_out              => sample_s
    );

    i2s_interface : entity work.i2s_interface
    port map(
        clk                     => clk_s,
        reset                   => reset_ah_s,
        sample_in               => sample_s,
        next_sample             => next_sample_s,
        sdata                   => I2S_SDATA,
        sclk                    => I2S_SCLK,
        wsel                    => I2S_WSEL
    );

    microblaze_sys : entity work.microblaze_sys_wrapper
    port map(
        clk_100MHz              => clk_s,
        reset_rtl_0             => reset_al_s,
        uart_rtl_0_rxd          => UART_RX,
        uart_rtl_0_txd          => UART_TX,
        leds                    => LEDS(14 downto 0),
        switches                => SWITCHES,
        saw_slope               => saw_slope_s
    );

end architecture;
