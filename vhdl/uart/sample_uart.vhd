library IEEE;
use IEEE.std_logic_1164.all;

library wave;
use wave.wave_array_pkg.all;

library uart;

-- This entity outputs the output audio samples on the UART interface delimited by newline
-- characters. An unusually high baudrate is necessary to keep up.
-- It assumes the SAMPLE_SIZE is a byte multiple (it will always be 16 bit).
entity sample_uart is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic;
        sample                  : in  t_mono_sample;
        UART_TX                 : out std_logic
    );
end entity;


architecture arch of sample_uart is

    type t_state is (idle, write_fifo);

    type s_uart_reg is record
        state                   : t_state;
        sample                  : t_mono_sample;
        byte_counter            : integer range 0 to 2;
    end record;

    constant REG_INIT : s_uart_reg := (
        state                   => idle,
        sample                  => (others => '0'),
        byte_counter            => 0
    );

    signal r, r_in              : s_uart_reg;
    signal s_data_valid         : std_logic;
    signal s_full               : std_logic;
    signal s_data_in            : std_logic_vector(7 downto 0);

begin

    uart : entity uart.uart_transmitter
    port map(
        clk                     => clk,
        reset                   => reset,
        data_valid              => s_data_valid,
        data_in                 => s_data_in,
        full                    => s_full,
        UART_TX                 => UART_TX
    );

    comb_process : process (r, next_sample, sample, s_full)
    begin

        r_in <= r;

        s_data_valid <= '0';
        s_data_in <= (others => '0');

        if r.state = idle then
            if next_sample = '1' then
                r_in.byte_counter <= 0;
                r_in.sample <= sample;
                r_in.state <= write_fifo;
            end if;

        elsif r.state = write_fifo then

            if s_full = '0' then

                s_data_valid <= '1';

                case r.byte_counter is
                    when 0 => s_data_in <= std_logic_vector(r.sample(15 downto 8));
                    when 1 => s_data_in <= std_logic_vector(r.sample(7 downto 0));
                    when 2 => s_data_in <= x"00"; -- \r
                    -- when 3 => s_data_in <= x"0A"; -- \n
                end case;

                -- if r.byte_counter = SAMPLE_SIZE / 8 then
                --     s_uart_byte <= x"00";
                -- else
                --     s_data_in <= std_logic_vector(
                --         r.sample((r.byte_counter + 1) * 8 - 1 downto r.byte_counter * 8));
                -- end if;

                if r.byte_counter < 2 then
                    r_in.byte_counter <= r.byte_counter + 1;
                else
                    r_in.state <= idle;
                end if;

            end if;
        end if;

    end process;

    reg_process : process(clk)
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
