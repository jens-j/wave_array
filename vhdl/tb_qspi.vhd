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
    signal s_flash_input            : t_flash_input := FLASH_INPUT_INIT;
    signal s_flash_output           : t_flash_output := FLASH_OUTPUT_INIT;

    signal s_qspi_sck               : std_logic := '0';
    signal s_qspi_cs                : std_logic;
    signal s_qspi_dq                : std_logic_vector(3 downto 0);


    procedure write_flash (
        signal s_flash_input        : out t_flash_input;
        signal s_flash_output       : in  t_flash_output;
        constant address            : in  std_logic_vector(FLASH_DEPTH_LOG2 - 1 downto 0);
        constant start_value        : in  std_logic_vector(FLASH_WIDTH - 1 downto 0);
        constant length             : in  integer range 1 to FLASH_PAGE_SIZE
    ) is 
        variable value : signed(FLASH_WIDTH - 1 downto 0) := signed(start_value);
    begin 
        -- 4 byte write.
        s_flash_input.write_enable <= '1';
        s_flash_input.address <= address;
        s_flash_input.bytes_n <= length;
        s_flash_input.write_data <= std_logic_vector(value);

        wait until rising_edge(s_system_clk) and s_flash_output.ack = '1';
        s_flash_input.write_enable <= '0';

        for i in 1 to length - 1 loop 
            value := value + 1;
            wait until rising_edge(s_system_clk) and s_flash_output.write_req = '1';
            s_flash_input.write_data <= std_logic_vector(value);
        end loop;
    end procedure;


    procedure read_flash (
        signal s_flash_input        : out t_flash_input;
        signal s_flash_output       : in  t_flash_output;
        constant address            : in  std_logic_vector(FLASH_DEPTH_LOG2 - 1 downto 0);
        constant length             : in  integer range 1 to FLASH_PAGE_SIZE
    ) is 
    begin 
        -- 4 byte write.
        s_flash_input.read_enable <= '1';
        s_flash_input.address <= address;
        s_flash_input.bytes_n <= length;

        wait until rising_edge(s_system_clk) and s_flash_output.ack = '1';
        s_flash_input.read_enable <= '0';

        wait until rising_edge(s_system_clk) and s_flash_output.done = '1';
    end procedure;

    procedure erase_flash (
        signal s_flash_input        : out t_flash_input;
        signal s_flash_output       : in  t_flash_output;
        constant address            : in  std_logic_vector(FLASH_DEPTH_LOG2 - 1 downto 0)
    ) is 
    begin 
        -- 4 byte write.
        s_flash_input.erase_enable <= '1';
        s_flash_input.address <= address;

        wait until rising_edge(s_system_clk) and s_flash_output.ack = '1';
        s_flash_input.erase_enable <= '0';
    end procedure;


begin

    qspi_if: entity qspi.qspi_interface
    port map (
        system_clk              => s_system_clk,
        spi_clk                 => s_spi_clk,
        reset                   => s_reset,
        flash_input             => s_flash_input,
        flash_output            => s_flash_output,
        QSPI_CS                 => s_qspi_cs,
        QSPI_SCK                => s_qspi_sck,
        QSPI_DQ                 => s_qspi_dq,
        reg_jedec_vendor        => open,
        reg_jedec_device        => open,
        reg_status_1            => open,
        reg_config              => open
    );

    flash_model : entity flash.s25fl256s
    generic map (
        TimingModel             => "S25FL256SAGMFI000_R_30pF.sdf",
        MsgOn                   => true,
        LongTimming             => false
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

    test_proc : process 
    begin 
        wait until rising_edge(s_system_clk) and s_reset = '0';

        write_flash(s_flash_input, s_flash_output, 25x"000_0100", x"00", FLASH_PAGE_SIZE);
        read_flash(s_flash_input, s_flash_output, 25x"000_0100", FLASH_PAGE_SIZE);
        erase_flash(s_flash_input, s_flash_output, 25x"000_0000");
        write_flash(s_flash_input, s_flash_output, 25x"000_0100", x"55", FLASH_PAGE_SIZE);
        read_flash(s_flash_input, s_flash_output, 25x"000_0100", FLASH_PAGE_SIZE);

        wait;
    end process;

end architecture;
