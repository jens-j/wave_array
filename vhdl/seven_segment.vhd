library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


-- 7 segment display driver for the Nexys 4 board.
-- It uses TDM to dislay the value of display_data on the 8 digit display.
-- The display uses a commong anode configuration and both the digit and segment outputs are inverted.
entity seven_segment is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        display_data            : in  std_logic_vector(31 downto 0);
        segments                : out std_logic_vector(6 downto 0); -- Segment enable, active low
        anodes                  : out std_logic_vector(7 downto 0) -- Digit select, active low
    );
end entity;

architecture arch of seven_segment is

    constant MUX_PERIOD_MS : integer := 1; -- Per digit.
    constant MUX_PERIOD_CYCLES : integer := SYS_FREQ / (MUX_PERIOD_MS * 1000);

    type t_seven_segment_reg is record
        counter                 : integer range 0 to MUX_PERIOD_CYCLES - 1;
        index                   : integer range 0 to 7;
        segments                : std_logic_vector(6 downto 0);
        anodes                  : std_logic_vector(7 downto 0);
    end record;

    constant R_INIT : t_seven_segment_reg := (
        counter                 => 0,
        index                   => 0,
        segments                => (others => '0'),
        anodes                  => (others => '0')
    );

    signal r, r_in : t_seven_segment_reg := R_INIT;

begin

    combinatorial : process (r, display_data)
    begin

        r_in <= r;
        r_in.anodes <= x"FF" nand std_logic_vector(to_unsigned(2**r.index, 8));

        -- Register segment outputs.
        case ( display_data(4 * r.index + 3 downto 4 * r.index) ) is
            when x"0"     => r_in.segments <= "1000000";
            when x"1"     => r_in.segments <= "1111001";
            when x"2"     => r_in.segments <= "0100100";
            when x"3"     => r_in.segments <= "0110000";
            when x"4"     => r_in.segments <= "0011001";
            when x"5"     => r_in.segments <= "0010010";
            when x"6"     => r_in.segments <= "0000010";
            when x"7"     => r_in.segments <= "1111000";
            when x"8"     => r_in.segments <= "0000000";
            when x"9"     => r_in.segments <= "0010000";
            when x"A"     => r_in.segments <= "0001000";
            when x"B"     => r_in.segments <= "0000011";
            when x"C"     => r_in.segments <= "1000110";
            when x"D"     => r_in.segments <= "0100001";
            when x"E"     => r_in.segments <= "0000110";
            when others   => r_in.segments <= "0001110";
        end case;

        -- Increment cycle counter
        if r.counter = MUX_PERIOD_CYCLES - 1 then
            r_in.counter <= 0;
        else
            r_in.counter <= r.counter + 1;
        end if;

        -- Increment digit index
        if r.counter = MUX_PERIOD_CYCLES - 1 then
            if r.index = 7 then
                r_in.index <= 0;
            else
                r_in.index <= r.index + 1;
            end if;
        end if;

        -- Assign outputs.
        anodes <= r.anodes;
        segments <= r.segments;

    end process;

    reg_process : process(clk)
    begin
        if falling_edge(clk) then
            if reset = '1' then
                r <= R_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
