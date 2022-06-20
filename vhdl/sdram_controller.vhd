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
        pll_lock                : in    std_logic; -- SDRAM clock needs to be running before becoming active.

        -- Read and write interface.
        sdram_input             : in    t_sdram_input;
        sdram_output            : out   t_sdram_output;

        -- SDRAM interface.
        CRAM_ADVN               : out   std_logic;
        CRAM_CEN                : out   std_logic;
        CRAM_CRE                : out   std_logic;
        CRAM_OEN                : out   std_logic;
        CRAM_WEN                : out   std_logic;
        CRAM_LBN                : out   std_logic;
        CRAM_UBN                : out   std_logic;
        CRAM_WAIT               : in    std_logic;
        CRAM_A                  : out   std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        CRAM_DQ                 : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0)
    );
end entity;

architecture arch of sdram_controller is

    constant ASYNC_CYCLES : integer :=
        integer(ceil(real(70) / (real(1_000_000_000) / real(SDRAM_FREQ)))) + 1;

    type t_state is (init_0, init_1, idle, delay, burst_read, burst_write, end_burst);

    type t_sdram_reg is record
        state                   : t_state;
        next_state              : t_state;
        sdram_output            : t_sdram_output;
        cram_advn               : std_logic;
        cram_cen                : std_logic;
        cram_cre                : std_logic;
        cram_oen                : std_logic;
        cram_wen                : std_logic;
        cram_a                  : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        cram_dq                 : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
        counter                 : integer range 0 to SDRAM_DEPTH;
    end record;

    constant REG_INIT : t_sdram_reg := (
        state                   => init_0,
        next_state              => idle,
        sdram_output            => ('0', '0', '0', (others => '0')),
        cram_advn               => '1',
        cram_cen                => '1',
        cram_cre                => '0',
        cram_oen                => '1',
        cram_wen                => '1',
        cram_a                  => (others => '0'),
        cram_dq                 => (others => '0'),
        counter                 => 0
    );

    signal r, r_in              : t_sdram_reg;


begin

    -- Connect read/write interface output registers.
    sdram_output <= r.sdram_output;

    -- Connect SDRAM interface output registers.
    CRAM_LBN <= '0';
    CRAM_UBN <= '0';
    CRAM_ADVN <= r.cram_advn;
    CRAM_CEN <= r.cram_cen;
    CRAM_CRE <= r.cram_cre;
    CRAM_OEN <= r.cram_oen;
    CRAM_WEN <= r.cram_wen;
    CRAM_A <= r.cram_a;
    CRAM_DQ <= r.cram_dq;


    combinatorial : process (r, pll_lock, sdram_input, CRAM_WAIT, CRAM_DQ)
    begin

        r_in <= r;

        r_in.sdram_output.ack <= '0';
        r_in.sdram_output.valid <= '0';
        r_in.sdram_output.done <= '0';
        r_in.sdram_output.read_data <= (others => '0');

        r_in.cram_advn <= '1';
        r_in.cram_cen <= '1';
        r_in.cram_cen <= '1';
        r_in.cram_cre <= '0';
        r_in.cram_oen <= '1';
        r_in.cram_wen <= '1';
        r_in.cram_cen <= '1';
        r_in.cram_a <= (others => '0');
        r_in.cram_dq <= (others => 'Z');

        case r.state is

            when init_0 =>
                if pll_lock = '1' then
                    r_in.counter <= ASYNC_CYCLES - 1;
                    r_in.state <= init_1;
                end if;

            -- Set to continuous burst mode with 4 cycle latency.
            when init_1 =>
                r_in.cram_cre <= '1';
                r_in.cram_cen <= '0';
                r_in.cram_advn <= '0';
                r_in.cram_wen <= '0';
                r_in.cram_a <= 23x"081D1F";

                -- Wait until the asynchronuous configuration register write completes.
                if r.counter > 0 then
                    r_in.counter <= r.counter - 1;
                else
                    r_in.cram_cen <= '1';
                    r_in.cram_wen <= '1';
                    r_in.cram_advn <= '1';
                    r_in.state <= idle;
                end if;

            -- Wait for a read- or write-enable.
            when idle =>
                if sdram_input.read_enable = '1' or sdram_input.write_enable = '1' then

                    r_in.cram_cen <= '0';
                    r_in.cram_advn <= '0';
                    r_in.cram_a <= sdram_input.address;
                    r_in.counter <= 3;
                    r_in.state <= delay;
                    r_in.next_state <= burst_read;

                    if sdram_input.write_enable = '1' then
                        r_in.cram_wen <= '0';
                        r_in.next_state <= burst_write;
                    end if;
                end if;

            -- Wait 3 cycles.
            when delay =>
                r_in.cram_cen <= '0';
                if r.counter > 0 then
                    r_in.counter <= r.counter - 1;
                else
                    r_in.counter <= sdram_input.burst_length;
                    r_in.state <= r.next_state;
                end if;

            when burst_read =>
                r_in.cram_cen <= '0';
                r_in.cram_oen <= '0';
                if cram_wait = '0' then
                    r_in.sdram_output.valid <= '1';
                    r_in.sdram_output.read_data <= CRAM_DQ;
                    if r.counter > 0 then
                        r_in.counter <= r.counter - 1;
                    else
                        r_in.sdram_output.done <= '1';
                        r_in.state <= end_burst;
                    end if;
                end if;

            when burst_write =>
                r_in.cram_cen <= '0';
                if cram_wait = '0' then
                    r_in.sdram_output.valid <= '1';
                    r_in.cram_dq <= sdram_input.write_data;
                    if r.counter > 0 then
                        r_in.counter <= r.counter - 1;
                    else
                        r_in.sdram_output.done <= '1';
                        r_in.state <= end_burst;
                    end if;
                end if;

            -- De-assert CRAM_CEN.
            when end_burst =>
                r_in.state <= idle;

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
