library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity register_file is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;

        register_input          : in  t_register_input;
        register_output         : out t_register_output;

        status                  : in  t_status;
        config                  : out t_config
    );
end entity;

architecture arch of register_file is

    type t_state is (idle);

    type t_packet_engine_reg is record
        state                   : t_state;
        register_output         : t_register_output;
        faults                  : std_logic_vector(15 downto 0);
        led                     : std_logic;
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state                   => idle,
        register_output         => ('0', '0', (others => '0')),
        faults                  => (others => '0'),
        led                     => '0'
    );

    signal r, r_in              : t_packet_engine_reg;

begin

    register_output <= r.register_output;
    config.led <= r.led;

    comb_process : process (r, register_input, status)
    begin

        r_in <= r;
        r_in.register_output <= ('0', '0', (others => '0'));

        -- Register fault sticky bits.
        if status.uart_timeout = '1' then
            r_in.faults(FAULT_UART_TIMEOUT) <= '1';
        end if;

        -- Handle register read.
        if register_input.read_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_ADDR_LED then
                r_in.register_output.read_data <= (1 to 15 => '0') & r.led;
            elsif register_input.address = REG_ADDR_FAULT then
                r_in.register_output.read_data <= r.faults;
            else
                r_in.register_output.fault <= '1';
                r_in.faults(FAULT_ADDRESS) <= '1';
            end if;

        -- Handle register write.
        elsif register_input.write_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_ADDR_LED then
                r_in.led <= register_input.write_data(0);
            elsif register_input.address = REG_ADDR_FAULT then
                r_in.faults <= (others => '0');
            else
                r_in.register_output.fault <= '1';
                r_in.faults(FAULT_ADDRESS) <= '1';
            end if;
        end if;
    end process;

    reg_process : process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= REG_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
