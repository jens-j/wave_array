

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library uart;
use uart.uart_pkg.all;


entity hk_offload is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        status                  : in  t_status;

        -- Auto offload fifo interface.
        hk_write_enable         : out std_logic;
        hk_data                 : out std_logic_vector(CTRL_SIZE - 1 downto 0);
        hk_full                 : in  std_logic
    );
end entity;

architecture arch of hk_offload is 

    type t_state is (idle, hk_0, hk_1, hk_2);

    type t_packet_engine_reg is record
        state                   : t_state;
        hk_write_enable         : std_logic;
        hk_data                 : std_logic_vector(CTRL_SIZE - 1 downto 0);
        hk_timer                : integer range 0 to 2**(CTRL_SIZE + 10) - 1; -- Counts cycles. Compared to config.hk_period of which the value counts increments of 1024 cycles..
        hk_req                  : std_logic; -- HK timer overflow flag.
        hk_count                : integer range 0 to HK_DATA_WORDS - 1;
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state                   => idle,
        hk_write_enable         => '0',
        hk_data                 => (others => '0'),
        hk_timer                => 0,
        hk_req                  => '0',
        hk_count                => 0
    );

    signal r, r_in              : t_packet_engine_reg;

begin


    comb_process : process (r, config, status, hk_full)
        variable v_status_ser : std_logic_vector(HK_DATA_WIDTH - 1 downto 0);
        variable v_value : std_logic_vector(15 downto 0);
        variable v_length : std_logic_vector(15 downto 0);
    begin

        r_in <= r;
        r_in.hk_write_enable <= '0';
        r_in.hk_data <= (others => '0');

        -- Connect output registers.
        hk_write_enable <= r.hk_write_enable;
        hk_data <= r.hk_data;      

        -- Serialize status record.
        v_status_ser := serialize_status(status);

        case r.state is 
        when idle => 
            
            if r.hk_req = '1' then 
                r_in.hk_req <= '0';
                r_in.hk_count <= 0;

                if config.hk_enable = '1' then 
                    r_in.state <= hk_0;
                end if;
            end if;

        -- Write auto offload opcode and hk channel. 
        when hk_0 =>

            r_in.hk_write_enable <= '1';
            r_in.hk_data <= UART_AUTO_OFFLOAD & UART_AO_HK;
            r_in.state <= hk_1;
        
        -- write data length in 16 bit words.
        when hk_1 =>

            r_in.hk_write_enable <= '1';
            v_length := std_logic_vector(to_unsigned(HK_DATA_WORDS, CTRL_SIZE)); 
            r_in.hk_data <= v_length(7 downto 0) & v_length(15 downto 8); -- Switch bytes for little endian transfer.
            r_in.state <= hk_2;

        -- Write packet data to auto offload fifo.
        when hk_2 =>

            r_in.hk_write_enable <= '1';

            v_value := v_status_ser((r.hk_count + 1) * 16 - 1 downto r.hk_count * 16);

            -- r_in.hk_data <= v_value;
            r_in.hk_data <= v_value(7 downto 0) & v_value(15 downto 8); -- Switch bytes for little endian transfer.
            
            if r.hk_count < HK_DATA_WORDS - 1 then 
                r_in.hk_count <= r.hk_count + 1;
            else 
                r_in.state <= idle;
            end if;

        end case;

        -- Increment HK timer.
        if r.hk_timer = to_integer(shift_left(resize(config.hk_period, CTRL_SIZE + 10), 10)) then 
            r_in.hk_timer <= 0;
            r_in.hk_req <= '1';
        else 
            r_in.hk_timer <= r.hk_timer + 1;
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