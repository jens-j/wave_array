library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library wave;
use wave.wave_array_pkg.all;


entity sdram_controller is
    port (
        clk                     : in    std_logic; -- Max 104 MHz.
        sdram_clk               : in    std_logic;
        reset                   : in    std_logic;
        pll_locked              : in    std_logic; -- SDRAM clock needs to be running before becoming active.
        sdram_clk_enable        : out   std_logic;

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
        SDRAM_DQ                : inout std_logic_vector(SDRAM_WIDTH - 1 downto 0)
    );
end entity;

architecture arch of sdram_controller is

    constant ASYNC_CYCLES : integer :=
        integer(ceil(real(70) / (real(1_000_000_000) / real(SDRAM_FREQ))));

    constant INIT_CYCLES : integer := 150_000 / (1_000_000_000 / SYS_FREQ);

    type t_state is (init, idle, wait_for_pll, wait_tpu, write_bcr, latency, burst_read, burst_write, end_transfer);

    -- Registers that are clocked in a different way.
    signal r_sdram_dq_in        : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    signal r2_sdram_dq_in       : std_logic_vector(SDRAM_WIDTH - 1 downto 0);

    type t_sdram_reg is record
        state                   : t_state;
        next_state              : t_state;
        sdram_clk_enable        : std_logic;
        sdram_output            : t_sdram_output;
        sdram_advn              : std_logic;
        sdram_cen               : std_logic;
        sdram_cre               : std_logic;
        sdram_oen               : std_logic;
        sdram_wen               : std_logic;
        sdram_a                 : std_logic_vector(SDRAM_DEPTH_LOG2 - 1 downto 0);
        sdram_dq_out            : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
        sdram_wait              : std_logic;
        sdram_wait_r            : std_logic; -- Device is configured to assert wait one cycle early.
        counter                 : integer range 0 to SDRAM_DEPTH; -- Counter used for a number of things. 
        valid_data              : std_logic; -- Signal valid read data in the input register.
        output_enable           : std_logic; -- Used for IOB muxing.
        read_count              : integer;   -- Count words returned in a burts read.
        latency_counter         : integer;
    end record;

    constant REG_INIT : t_sdram_reg := (
        state                   => wait_for_pll,
        next_state              => idle,
        sdram_clk_enable        => '0',
        sdram_output            => ('0', '0', '0', '0', (others => '0')),
        sdram_advn              => '1',
        sdram_cen               => '1',
        sdram_cre               => '0',
        sdram_oen               => '1',
        sdram_wen               => '1',
        sdram_a                 => (others => '0'),
        sdram_dq_out            => (others => '0'),
        sdram_wait              => '0',
        sdram_wait_r            => '0',
        counter                 => 0,
        valid_data              => '0',
        output_enable           => '0',
        read_count              => 0,
        latency_counter         => 0
    );

    signal r, r_in              : t_sdram_reg;

begin

    combinatorial : process (r, r2_sdram_dq_in, pll_locked, sdram_input, SDRAM_WAIT, SDRAM_DQ)
    begin

        r_in <= r;

        r_in.valid_data <= '0';
        r_in.output_enable <= '0';

        r_in.sdram_output.ack <= '0';
        r_in.sdram_output.read_valid <= '0';
        r_in.sdram_output.write_req <= '0';
        r_in.sdram_output.done <= '0';
        r_in.sdram_output.read_data <= (others => '0');

        -- r_in.sdram_wait <= SDRAM_WAIT;
        -- r_in.sdram_wait_r <= r.sdram_wait;
        -- r_in.sdram_dq_in <= SDRAM_DQ;

        sdram_clk_enable <= r.sdram_clk_enable;

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
        SDRAM_DQ <= r.sdram_dq_out when r.output_enable = '1' else (others => 'Z');

        -- Connect read/write interface output registers.
        sdram_output <= r.sdram_output;
        sdram_output.write_req <= '0';

        case r.state is

            when init => 
                r_in.sdram_cen <= '1';
                r_in.sdram_advn <= '1';
                r_in.sdram_cre <= '0';
                r_in.sdram_oen <= '1';
                r_in.sdram_wen <= '1';
                r_in.sdram_a <= (others => '0');
                r_in.state <= wait_for_pll;

            when wait_for_pll =>
                if pll_locked = '1' then
                    r_in.counter <= INIT_CYCLES - 1;
                    r_in.state <= wait_tpu;
                end if;

            when wait_tpu => 
                if r.counter = 0 then 
                    r_in.counter <= ASYNC_CYCLES - 1;
                    r_in.state <= write_bcr;
                else 
                    r_in.counter <= r.counter - 1;
                end if;

            -- Wait for the BCR write to complete.
            when write_bcr =>

                if r.counter = 0 then
                    r_in.state <= end_transfer;
                else
                    r_in.counter <= r.counter - 1;
                    
                    r_in.sdram_cen <= '0';
                    r_in.sdram_cre <= '1';
                    r_in.sdram_advn <= '0';
                    r_in.sdram_wen <= '0';

                    -- Configure BCR:
                    -- - continuous burst
                    -- - wait asserted before delay
                    -- - wait active high
                    -- - 7 cycle accress latency (code 6)
                    -- - fixed access latency
                    -- - synchronous mode
                    r_in.sdram_a <= 23x"08751F"; 
                end if;

            when end_transfer => 
                r_in.sdram_cen <= '1';
                r_in.sdram_advn <= '1';
                r_in.sdram_cre <= '0';
                r_in.sdram_oen <= '1';
                r_in.sdram_wen <= '1';
                r_in.sdram_a <= (others => '0'); 
                r_in.state <= idle;

            -- Wait for a read- or write-enable.
            when idle =>
                
                r_in.sdram_clk_enable <= '1';

                if sdram_input.read_enable = '1' or sdram_input.write_enable = '1' then

                    r_in.sdram_output.ack <= '1';
                    r_in.sdram_cen <= '0';
                    r_in.sdram_advn <= '0';
                    r_in.sdram_a <= std_logic_vector(sdram_input.address);
                    r_in.counter <= sdram_input.burst_length - 1;
                    r_in.read_count <= 0;
                    r_in.next_state <= burst_read;
                    r_in.state <= latency;

                    if sdram_input.write_enable = '1' then
                        r_in.sdram_wen <= '0';
                        r_in.latency_counter <= 5;
                        r_in.next_state <= burst_write;
                    else
                        r_in.sdram_oen <= '0';
                        r_in.latency_counter <= 7;
                    end if;
                end if;

            -- Wait for the fixed latency.
            when latency =>
                r_in.sdram_advn <= '1';
                if r.latency_counter = 0 then 
                    r_in.state <= r.next_state;
                else 
                    r_in.latency_counter <= r.latency_counter - 1;
                end if;

            when burst_read =>

                r_in.read_count <= r.read_count + 1;
                r_in.sdram_output.read_valid <= '1';
                r_in.sdram_output.read_data <= r2_sdram_dq_in;

                if r.counter > 0 then
                    r_in.counter <= r.counter - 1;
                end if;

                -- End SDRAM transaction (last read words are already buffered).
                if r.counter < 2 then 
                    r_in.sdram_cen <= '1';
                    r_in.sdram_oen <= '1';
                end if;

                if r.counter = 0 then 
                    r_in.sdram_output.done <= '1';
                    r_in.state <= end_transfer;
                end if;

            when burst_write =>

                r_in.output_enable <= '1';
                r_in.sdram_dq_out <= sdram_input.write_data;

                if r.counter > 0 then
                    r_in.counter <= r.counter - 1;
                    sdram_output.write_req <= '1';
                else
                    r_in.sdram_output.done <= '1';
                    r_in.sdram_output.write_req <= '0';
                    r_in.state <= end_transfer;
                end if;

            end case;
    end process;

     -- Because of timing, The data input is registered on the rising edge of the sdram clk.
     -- Then again on the falling edge of the system clk before it goed into a normal register.
    sdram_clk_regs : process(sdram_clk)
    begin
        if rising_edge(sdram_clk) then
            if reset = '1' then
                r_sdram_dq_in <= (others => '0'); 
            else
                r_sdram_dq_in <= SDRAM_DQ; 
            end if;
        end if;
    end process;

    sys_clk_regs : process(clk)
    begin
        if falling_edge(clk) then 
            if reset = '1' then
                r2_sdram_dq_in <= (others => '0'); 
            else
                r2_sdram_dq_in <= r_sdram_dq_in;
            end if;
        end if; 

        if rising_edge(clk) then
            if reset = '1' then
                r <= REG_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
