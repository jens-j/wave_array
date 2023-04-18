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

        -- Frame DMA outputs.
        base_address            : out unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        n_frames_log2           : out integer range 0 to 8;
        new_table               : out std_logic;

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
        base_address            : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        n_frames_log2           : integer range 0 to 8;
        new_table               : std_logic;
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state                   => idle,
        register_output         => ('0', '0', (others => '0')),
        faults                  => (others => '0'),
        led                     => '0',
        base_address            => (others => '0'),
        n_frames_log2           => 0,
        new_table               => '0'
    );

    signal r, r_in              : t_packet_engine_reg;

begin

    register_output             <= r.register_output;
    config.led                  <= r.led;
    base_address                <= r.base_address;
    n_frames_log2               <= r.n_frames_log2;
    new_table                   <= r.new_table;

    comb_process : process (r, register_input, status)
    begin

        r_in <= r;
        r_in.register_output <= ('0', '0', (others => '0'));
        r_in.new_table <= '0'; 

        -- Register fault sticky bits.
        if status.uart_timeout = '1' then
            r_in.faults(FAULT_UART_TIMEOUT) <= '1';
        end if;

        if status.burst_align_fault = '1' then
            r_in.faults(FAULT_BURST_ALIGN) <= '1';
        end if;

        -- Handle register read.
        if register_input.read_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_LED then
                r_in.register_output.read_data <= (1 to 15 => '0') & r.led;

            elsif register_input.address = REG_FAULT then
                r_in.register_output.read_data <= r.faults;

            elsif register_input.address = REG_DEBUG_UART_COUNT then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.uart_count, REGISTER_WIDTH));

            elsif register_input.address = REG_DEBUG_UART_FIFO_COUNT then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.uart_fifo_count, REGISTER_WIDTH));

            elsif register_input.address = REG_DEBUG_UART_STATE then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.uart_state, REGISTER_WIDTH));

            elsif register_input.address = REG_DEBUG_SDRAM_COUNT then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.sdram_count, REGISTER_WIDTH));

            elsif register_input.address = REG_DEBUG_SDRAM_STATE then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.sdram_state, REGISTER_WIDTH));

            elsif register_input.address = REG_TABLE_BASE_L then
                r_in.register_output.read_data <=
                    std_logic_vector(r.base_address(REGISTER_WIDTH - 1 downto 0));

            elsif register_input.address = REG_TABLE_BASE_H then
                r_in.register_output.read_data(SDRAM_DEPTH_LOG2 - REGISTER_WIDTH - 1 downto 0) <=
                    std_logic_vector(r.base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH));

            elsif register_input.address = REG_TABLE_FRAMES then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(r.n_frames_log2, WAVE_MAX_FRAMES_LOG2_LOG2));

            else
                r_in.register_output.fault <= '1';
                r_in.faults(FAULT_REG_ADDRESS) <= '1';
            end if;

        -- Handle register write.
        elsif register_input.write_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_LED then
                r_in.led <= register_input.write_data(0);

            elsif register_input.address = REG_FAULT then
                r_in.faults <= (others => '0');

            elsif register_input.address = REG_TABLE_BASE_L then
                r_in.base_address(REGISTER_WIDTH - 1 downto 0) <= unsigned(register_input.write_data);

            elsif register_input.address = REG_TABLE_BASE_H then
                r_in.base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH) <= unsigned(
                    register_input.write_data(SDRAM_DEPTH_LOG2 - REGISTER_WIDTH - 1 downto 0));

            elsif register_input.address = REG_TABLE_FRAMES then
                r_in.n_frames_log2 <= to_integer(unsigned(
                    register_input.write_data(WAVE_MAX_FRAMES_LOG2_LOG2 - 1 downto 0)));

            elsif register_input.address = REG_TABLE_NEW then
                r_in.new_table <= register_input.write_data(0);

            else
                r_in.register_output.fault <= '1';
                r_in.faults(FAULT_REG_ADDRESS) <= '1';
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
