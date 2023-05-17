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
        config                  : t_config;
        register_output         : t_register_output;
        faults                  : std_logic_vector(15 downto 0);
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state                   => idle,
        config                  => CONFIG_INIT,
        register_output         => ('0', '0', (others => '0')),
        faults                  => (others => '0')
    );

    signal r, r_in              : t_packet_engine_reg;

begin

    register_output             <= r.register_output;
    config                      <= r.config;

    comb_process : process (r, register_input, status)
    begin

        r_in <= r;
        r_in.register_output <= ('0', '0', (others => '0'));
        r_in.config.dma_new_table <= '0'; 

        -- Register fault sticky bits.
        if status.uart_timeout = '1' then
            r_in.faults(FAULT_UART_TIMEOUT) <= '1';
        end if;

        -- Handle register read.
        if register_input.read_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_LED then
                r_in.register_output.read_data <= (1 to 15 => '0') & r.config.led;

            elsif register_input.address = REG_FAULT then
                r_in.register_output.read_data <= r.faults;

            elsif register_input.address = REG_DBG_UART_COUNT then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.uart_count, REGISTER_WIDTH));

            elsif register_input.address = REG_DBG_UART_FIFO then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.uart_fifo_count, REGISTER_WIDTH));

            elsif register_input.address = REG_DBG_UART_STATE then
                r_in.register_output.read_data <=
                    std_logic_vector(to_unsigned(status.uart_state, REGISTER_WIDTH));

            elsif register_input.address = REG_TABLE_BASE_L then
                r_in.register_output.read_data <=
                    std_logic_vector(r.config.dma_base_address(REGISTER_WIDTH - 1 downto 0));

            elsif register_input.address = REG_TABLE_BASE_H then
                r_in.register_output.read_data(SDRAM_DEPTH_LOG2 - REGISTER_WIDTH - 1 downto 0) <=
                    std_logic_vector(r.config.dma_base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH));

            elsif register_input.address = REG_TABLE_FRAMES then
                r_in.register_output.read_data <= 
                    std_logic_vector(to_unsigned(r.config.dma_n_frames_log2, REGISTER_WIDTH));

            elsif register_input.address = REG_FRAME_INDEX then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(status.frame_index, REGISTER_WIDTH));

            elsif register_input.address = REG_FRAME_POSITION then
                r_in.register_output.read_data(OSC_SAMPLE_FRAC - 1 downto 0) <= std_logic_vector(status.frame_position);

            elsif register_input.address = REG_FRAME_BANK then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(status.frame_bank, REGISTER_WIDTH));

            elsif register_input.address = REG_POTENTIOMETER then
                r_in.register_output.read_data(ADC_SAMPLE_SIZE - 1 downto 0) <= status.pot_value;

            elsif register_input.address = REG_LFO_VELOCITY then
                r_in.register_output.read_data <= std_logic_vector(r.config.lfo_velocity);

            elsif register_input.address = REG_LFO_VELOCITY then
                r_in.register_output.read_data <= std_logic_vector(r.config.lfo_velocity);

            elsif register_input.address = REG_FILTER_CUTOFF then
                r_in.register_output.read_data <= std_logic_vector(r.config.filter_cutoff);

            elsif register_input.address = REG_FILTER_RESONANCE then
                r_in.register_output.read_data <= std_logic_vector(r.config.filter_resonance);
            
            elsif register_input.address = REG_FILTER_SELECT then
                r_in.register_output.read_data(2 downto 0) <= std_logic_vector(to_unsigned(r.config.filter_select, 3));

            else
                r_in.register_output.fault <= '1';
                r_in.faults(FAULT_REG_ADDRESS) <= '1';
            end if;

        -- Handle register write.
        elsif register_input.write_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_LED then
                r_in.config.led <= register_input.write_data(0);

            elsif register_input.address = REG_FAULT then
                r_in.faults <= (others => '0');

            elsif register_input.address = REG_TABLE_BASE_L then
                r_in.config.dma_base_address(REGISTER_WIDTH - 1 downto 0) <= unsigned(register_input.write_data);

            elsif register_input.address = REG_TABLE_BASE_H then
                r_in.config.dma_base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH) <= unsigned(
                    register_input.write_data(SDRAM_DEPTH_LOG2 - REGISTER_WIDTH - 1 downto 0));

            elsif register_input.address = REG_TABLE_FRAMES then
                r_in.config.dma_n_frames_log2 <= to_integer(unsigned(
                    register_input.write_data(WAVE_MAX_FRAMES_LOG2_LOG2 - 1 downto 0)));

            elsif register_input.address = REG_TABLE_NEW then
                r_in.config.dma_new_table <= '1';

            elsif register_input.address = REG_LFO_VELOCITY then
                r_in.config.lfo_velocity <= unsigned(register_input.write_data);

            elsif register_input.address = REG_FILTER_CUTOFF then
                r_in.config.filter_cutoff <= unsigned(register_input.write_data);

            elsif register_input.address = REG_FILTER_RESONANCE then
                r_in.config.filter_resonance <= unsigned(register_input.write_data);

            elsif register_input.address = REG_FILTER_SELECT then
                if unsigned(register_input.write_data) < 4 then 
                    r_in.config.filter_select <= to_integer(unsigned(register_input.write_data));
                else 
                    r_in.config.filter_select <= 4;
                end if;
                
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
