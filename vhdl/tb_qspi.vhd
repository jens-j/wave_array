library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library qspi;
library flash;


entity tb_qspi is
end entity;


architecture arch_no_sdram of tb_qspi is

    signal s_system_clk             : std_logic := '0'; -- 100 MHz
    signal s_spi_clk                : std_logic := '0'; -- 100 MHz
    signal s_resetn                 : std_logic := '0';
    signal s_reset                  : std_logic := '1';

    signal s_qspi_sck               : std_logic := '0';
    signal s_qspi_cs                : std_logic;
    signal s_qspi_dq                : std_logic_vector(3 downto 0);

begin

    qspi_if: entity qspi.qspi_interface
    port map (
        system_clk              => s_system_clk,
        spi_clk                 => s_spi_clk,
        reset                   => s_reset,
        QSPI_CS                 => s_qspi_cs,
        QSPI_SCK                => s_qspi_sck,
        QSPI_DQ                 => s_qspi_dq
    );

    flash_model : entity flash.s25fl256s
    generic map (
        TimingModel             => "s25fl256s_vhdl.sdf",
        MsgOn                   => true
    )
    port map (

        SI                      => s_qspi_dq(0), -- serial data input/IO0
        SO                      => s_qspi_dq(1), -- serial data output/IO1
        SCK                     => s_qspi_sck,   -- serial clock input
        CSNeg                   => s_qspi_cs,    -- chip select input
        RSTNeg                  => s_resetn,     -- hardware reset pin
        WPNeg                   => s_qspi_dq(2), -- write protect input/IO2
        HOLDNeg                 => s_qspi_dq(3)  -- hold input/IO3
    );

    s_system_clk <= not s_system_clk after 5 ns;
    s_spi_clk <= not s_system_clk;
    s_resetn <= '1' after 320 us;
    s_reset <= not s_resetn;

end architecture;
