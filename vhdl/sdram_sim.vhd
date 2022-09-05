library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- SDRAM simulation model. It can only handle burst reads and writes and writes to the configuration
-- register. Writing to this register does nothing. The model also does not consider page boundaries.
entity sdram_sim is
    generic (
        DEPTH_LOG2              : integer := 8
    );
    port (
        SDRAM_RESETN            : in    std_logic;
        SDRAM_CLK               : in    std_logic;
        SDRAM_ADVN              : in    std_logic;
        SDRAM_CEN               : in    std_logic;
        SDRAM_CRE               : in    std_logic;
        SDRAM_OEN               : in    std_logic;
        SDRAM_WEN               : in    std_logic;
        SDRAM_LBN               : in    std_logic;
        SDRAM_UBN               : in    std_logic;
        SDRAM_WAIT              : out   std_logic;
        SDRAM_ADDRESS           : in    std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        SDRAM_DQ                : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0)
    );
end entity;


architecture arch of sdram_sim is

    type t_state is (idle, config_write, delay, read_0, write_0, write_1);
    type t_memory is array (0 to 2**DEPTH_LOG2 - 1) of std_logic_vector(SDRAM_WIDTH - 1 downto 0);

    type t_sdram_reg is record
        state                   : t_state;
        next_state              : t_state;
        memory                  : t_memory;
        address                 : integer range 0 to 2**DEPTH_LOG2 - 1;
        counter                 : integer;
        sdram_wait              : std_logic;
        sdram_dq                : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
        config_bcr              : std_logic_vector(18 downto 0);
        config_rcr              : std_logic_vector(18 downto 0);
    end record;

    constant REG_INIT : t_sdram_reg := (
        state                   => idle,
        next_state              => idle,
        memory                  => (others => (others => '0')),
        address                 => 0,
        counter                 => 0,
        sdram_wait              => '0',
        sdram_dq                => (others => '0'),
        config_bcr              => (others => '0'),
        config_rcr              => (others => '0')
    );

    signal r, r_in              : t_sdram_reg;

begin

    combinatorial : process (r,
        SDRAM_ADVN, SDRAM_CEN, SDRAM_CRE, SDRAM_OEN, SDRAM_WEN, SDRAM_ADDRESS, SDRAM_DQ)
    begin

        r_in <= r;

        -- Connect outputs.
        SDRAM_DQ <= r.sdram_dq when SDRAM_OEN = '0' else (others => 'Z');
        SDRAM_WAIT <= r.sdram_wait;

        case r.state is

            when idle =>
                if SDRAM_CEN = '0' and SDRAM_ADVN = '0' then

                    r_in.address <= to_integer(unsigned(SDRAM_ADDRESS(DEPTH_LOG2 - 1 downto 0)));
                    r_in.sdram_wait <= '0';

                    if SDRAM_CRE = '1' then

                        if SDRAM_ADDRESS(19) = '1' then
                            r_in.config_bcr <= SDRAM_ADDRESS(18 downto 0);
                        else
                            r_in.config_rcr <= SDRAM_ADDRESS(18 downto 0);
                        end if;
                        r_in.state <= config_write;

                    elsif SDRAM_WEN = '0' then

                        r_in.counter <= 1;
                        r_in.state <= delay;
                        r_in.next_state <= write_0;

                    else
                        r_in.counter <= 2;
                        r_in.state <= delay;
                        r_in.next_state <= read_0;
                    end if;
                end if;

            when config_write =>
                if SDRAM_CEN = '1' then
                    r_in.sdram_wait <= '1';
                    r_in.state <= idle;
                end if;

            when delay =>
                if r.counter = 0 then
                    r_in.state <= r.next_state;
                    r_in.counter <= 0;
                else
                    r_in.counter <= r.counter - 1;
                end if;

            when read_0 =>

                if SDRAM_CEN = '0' then
                    r_in.sdram_wait <= '1';
                    r_in.sdram_dq <= r.memory(r.address);
                else
                    r_in.state <= idle;
                end if;

                if r.address < 2**DEPTH_LOG2 - 1 then
                    r_in.address <= r.address + 1;
                else
                    r_in.address <= 0;
                end if;

                if r.counter = SDRAM_MAX_BURST - 1 then
                    r_in.state <= idle;
                else
                    r_in.counter <= r.counter + 1;
                end if;

            when write_0 =>
                r_in.sdram_wait <= '1';
                r_in.state <= write_1;

            when write_1 =>

                if SDRAM_CEN = '0' then
                    r_in.sdram_wait <= '1';
                    r_in.memory(r.address) <= SDRAM_DQ;
                else
                    r_in.state <= idle;
                end if;

                if r.address < 2**DEPTH_LOG2 - 1 then
                    r_in.address <= r.address + 1;
                else
                    r_in.address <= 0;
                end if;

                if r.counter = SDRAM_MAX_BURST - 1 then
                    r_in.state <= idle;
                else
                    r_in.counter <= r.counter + 1;
                end if;

        end case;

    end process;

    reg_process : process(SDRAM_CLK)
    begin
        if rising_edge(SDRAM_CLK) then
            if SDRAM_RESETN = '0' then
                r <= REG_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
