library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;


entity sdram_controller is
    port (
        clk                     : in    std_logic; -- Max 104 MHz.
        reset                   : in    std_logic;
        pll_locked              : in    std_logic; -- SDRAM clock needs to be running before becoming active.

        -- Read and write interface.
        sdram_input             : in    t_sdram_input;
        sdram_output            : out   t_sdram_output;

        -- SDRAM interface.
        SDRAM_ADVN              : out   std_logic;
        SDRAM_CEN               : out   std_logic;
        SDRAM_CRE               : out   std_logic;
        SDRAM_OEN               : out   std_logic;
        SDRAM_WEN               : out   std_logic;
        SDRAM_LBN               : out   std_logic;
        SDRAM_UBN               : out   std_logic;
        SDRAM_WAIT              : in    std_logic;
        SDRAM_ADDRESS           : out   std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        SDRAM_DQ                : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0);

        -- Debug outputs.
        sdram_state             : out   integer;
        sdram_count             : out   integer
    );
end entity;

architecture arch of sdram_controller is

    constant ASYNC_CYCLES : integer :=
        integer(ceil(real(85) / (real(1_000_000_000) / real(SDRAM_FREQ)))) + 1;

    type t_state is (idle, wait_for_pll, set_burstmode, latency, burst_read, burst_write, end_burst);

    type t_sdram_reg is record
        state                   : t_state;
        next_state              : t_state;
        sdram_output            : t_sdram_output;
        sdram_advn              : std_logic;
        sdram_cen               : std_logic;
        sdram_cre               : std_logic;
        sdram_oen               : std_logic;
        sdram_wen               : std_logic;
        sdram_a                 : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        sdram_dq                : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
        sdram_wait              : std_logic;
        counter                 : integer range 0 to SDRAM_DEPTH;
        valid_data              : std_logic; -- Signal valid read data in the input register.
        output_enable           : std_logic; -- Used for IOB muxing.
        read_count              : integer;   -- Count words returned in a burts read.
        latency_counter         : integer range 0 to 2;
    end record;

    constant REG_INIT : t_sdram_reg := (
        state                   => wait_for_pll,
        next_state              => idle,
        sdram_output            => ('0', '0', '0', '0', (others => '0')),
        sdram_advn              => '1',
        sdram_cen               => '1',
        sdram_cre               => '0',
        sdram_oen               => '1',
        sdram_wen               => '1',
        sdram_a                 => (others => '0'),
        sdram_dq                => (others => '0'),
        sdram_wait              => '0',
        counter                 => 0,
        valid_data              => '0',
        output_enable           => '0',
        read_count              => 0,
        latency_counter         => 0
    );

    signal r, r_in              : t_sdram_reg;

begin

    combinatorial : process (r, pll_locked, sdram_input, SDRAM_WAIT, SDRAM_DQ)
    begin

        r_in <= r;

        r_in.valid_data <= '0';
        r_in.output_enable <= '0';

        r_in.sdram_output.ack <= '0';
        r_in.sdram_output.read_valid <= '0';
        r_in.sdram_output.write_req <= '0';
        r_in.sdram_output.done <= '0';
        r_in.sdram_output.read_data <= (others => '0');

        r_in.sdram_advn <= '1';
        r_in.sdram_cen <= '1';
        r_in.sdram_cen <= '1';
        r_in.sdram_cre <= '0';
        r_in.sdram_oen <= '1';
        r_in.sdram_wen <= '1';
        r_in.sdram_cen <= '1';
        r_in.sdram_a <= (others => '0');
        r_in.sdram_wait <= SDRAM_WAIT;

        -- Connect SDRAM interface output registers.
        SDRAM_LBN <= '0';
        SDRAM_UBN <= '0';
        SDRAM_ADVN <= r.sdram_advn;
        SDRAM_CEN <= r.sdram_cen;
        SDRAM_CRE <= r.sdram_cre;
        SDRAM_OEN <= r.sdram_oen;
        SDRAM_WEN <= r.sdram_wen;
        SDRAM_ADDRESS <= r.sdram_a;

        -- infer IOB.
        SDRAM_DQ <= r.sdram_dq when r.output_enable = '1' else (others => 'Z');

        -- Connect read/write interface output registers.
        sdram_output <= r.sdram_output;
        sdram_output.write_req <= '0';

        -- Connect degug ports.
        sdram_state <= t_state'pos(r.state);
        sdram_count <= r.read_count;

        case r.state is

            when wait_for_pll =>
                if pll_locked = '1' then
                    r_in.counter <= ASYNC_CYCLES - 1;
                    r_in.state <= set_burstmode;
                end if;

            -- Set to continuous burst mode with 4 cycle latency.
            when set_burstmode =>
                r_in.sdram_cre <= '1';
                r_in.sdram_cen <= '0';
                r_in.sdram_advn <= '0';
                r_in.sdram_wen <= '0';
                r_in.sdram_a <= 23x"08191F";

                -- Wait until the asynchronuous configuration register write completes.
                if r.counter > 0 then
                    r_in.counter <= r.counter - 1;
                else
                    r_in.sdram_cen <= '1';
                    r_in.sdram_wen <= '1';
                    r_in.sdram_advn <= '1';
                    r_in.sdram_cre <= '0';
                    r_in.state <= idle;
                end if;

            -- Wait for a read- or write-enable.
            when idle =>
                if sdram_input.read_enable = '1' or sdram_input.write_enable = '1' then

                    r_in.sdram_output.ack <= '1';
                    r_in.sdram_cen <= '0';
                    r_in.sdram_advn <= '0';
                    r_in.sdram_a <= sdram_input.address;
                    r_in.counter <= sdram_input.burst_length - 1;
                    r_in.read_count <= 0;
                    r_in.latency_counter <= 2;
                    r_in.state <= latency;
                    r_in.next_state <= burst_read;

                    if sdram_input.write_enable = '1' then
                        r_in.sdram_wen <= '0';
                        r_in.next_state <= burst_write;
                    else
                        r_in.sdram_oen <= '0';
                    end if;
                end if;

            -- Do not poll the WAIT signal during latency. In contrast with the datasheet, the
            -- WAIT signal can be de-asserted during the latency leading to an incorrect 1st word
            -- Suring a burst read.
            when latency =>
                r_in.sdram_cen <= '0';
                r_in.sdram_oen <= r.sdram_oen;
                if r.latency_counter > 0 then
                    r_in.latency_counter <= r.latency_counter - 1;
                else
                    r_in.state <= r.next_state;
                end if;

            when burst_read =>
                r_in.sdram_cen <= '0';
                r_in.sdram_oen <= '0';
                if r.sdram_wait = '1' then
                    r_in.read_count <= r.read_count + 1;
                    r_in.sdram_output.read_valid <= '1';
                    r_in.sdram_output.read_data <= SDRAM_DQ;
                    if r.counter > 0 then
                        r_in.counter <= r.counter - 1;
                    else
                        r_in.sdram_output.done <= '1';
                        r_in.state <= end_burst;
                    end if;
                end if;

            -- Keep the OEN low one more cycle to allow enough hold time for the last word.
            when end_burst =>
                r_in.sdram_cen <= '1';
                r_in.sdram_oen <= '1';
                r_in.state <= idle;

            when burst_write =>

                -- This path is unregistered to allow easy handshaking.
                sdram_output.write_req <= SDRAM_WAIT;

                r_in.sdram_cen <= '0';
                if SDRAM_WAIT = '1' then
                    r_in.output_enable <= '1';
                    r_in.sdram_dq <= sdram_input.write_data;
                    if r.counter > 0 then
                        r_in.counter <= r.counter - 1;
                    else
                        r_in.sdram_output.done <= '1';
                        r_in.sdram_output.write_req <= '0';
                        r_in.state <= idle;
                    end if;
                end if;

            end case;
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
