library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wave_array_pkg.all;
use work.midi_pkg.all;


entity midi_receiver is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        uart_rx                 : in  std_logic;
        midi_channel            : in  std_logic_vector(3 downto 0);
        midi_message            : out t_midi_message;
        message_valid           : out std_logic
    );
end entity;


architecture arch of midi_receiver is

    type t_state is (init, recv_1b_msg, recv_2b_msg);

    type t_midi_receiver_reg is record
        state                   : t_state;
        midi_message            : t_midi_message;
        message_valid           : std_logic;
        midi_channel            : std_logic_vector(3 downto 0);
        databyte_count          : integer;
    end record;

    constant REG_INIT : t_midi_receiver_reg := (
        state                   => init,
        midi_message            => (x"00", (others => x"00")),
        message_valid           => '0',
        midi_channel            => x"0",
        databyte_count          => 0
    );

    -- Register.
    signal r, r_in              : t_midi_receiver_reg;

    signal uart_valid_s         : std_logic;
    signal uart_data_s          : std_logic_vector(7 downto 0);

begin

    midi_receiver : entity work.UART_RX
    generic map (
        g_CLKS_PER_BIT          => SYS_FREQ / MIDI_BAUD,
        g_BIT_POLARITY          => '1'
    )
    port map (
        i_Clk                   => clk,
        i_RX_Serial             => uart_rx,
        o_RX_DV                 => uart_valid_s,
        o_RX_Byte               => uart_data_s
    );


    combinatorial : process (r, uart_valid_s, uart_data_s, midi_channel)
    begin

        -- Default register input.
        r_in        <= r;

        -- Outputs.
        midi_message <= r.midi_message;
        message_valid <= r.message_valid;

        -- Inputs.
        r_in.midi_channel <= midi_channel;
        r_in.message_valid <= '0';

        if uart_valid_s = '1' then

            -- Process status byte.
            if uart_data_s(7) = '1' then

                r_in.databyte_count <= 0;
                r_in.midi_message.status_byte <= uart_data_s;
                r_in.midi_message.data <= (others => (others => '0'));

                -- System messages, only timing is supported.
                if uart_data_s(7 downto 4) = "1111" then
                    r_in.state <= init;
                    if uart_data_s(3) = '1' then
                        r_in.message_valid <= '1';
                    end if;

                -- 1 byte long messages program change and channel pressure.
                elsif uart_data_s(6 downto 5) = "10" then
                    r_in.state <= recv_1b_msg;

                -- 2 byte messages.
                else
                    r_in.state <= recv_2b_msg;
                end if;

            -- Process data byte.
            else

                r_in.midi_message.data(r.databyte_count) <= uart_data_s;

                case(r.state) is

                    when recv_1b_msg =>
                        r_in.message_valid <= '1';

                    when recv_2b_msg =>
                        if r.databyte_count = 1 then
                            r_in.message_valid <= '1';
                            r_in.databyte_count <= 0;
                        else
                            r_in.databyte_count <= 1;
                        end if;

                    -- Receive data byte without prior status byte.
                    when others =>
                        -- Do nothing.

                end case;
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
