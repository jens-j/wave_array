library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- Priority memory arbiter. Lowest index goes first.
-- Clients can assert their read- or write-enable lines and wait for the valid line.
entity sdram_arbiter is
    generic (
        N_CLIENTS               : integer
    );
    port (
        clk                     : in    std_logic;
        reset                   : in    std_logic;
        pll_locked              : in    std_logic; -- SDRAM clock needs to be running before becoming active.

        -- Client interfaces.
        sdram_inputs            : in    t_sdram_input_array(0 to N_CLIENTS - 1);
        sdram_outputs           : out   t_sdram_output_array(0 to N_CLIENTS - 1);

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

architecture arch of sdram_arbiter is

    type t_state is (idle, read_0, read_1, write_0, write_1, write_2);

    type t_arbiter_reg is record
        state                   : t_state;
        next_state              : t_state;
        index                   : integer range 0 to N_CLIENTS - 1;
        sdram_input             : t_sdram_input;
        sdram_outputs           : t_sdram_output_array(0 to N_CLIENTS - 1);
        frame_count             : integer range 0 to SDRAM_DEPTH;
        burst_count             : integer range 0 to SDRAM_MAX_BURST;
        address                 : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        write_buffer            : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    end record;

    constant REG_INIT : t_arbiter_reg := (
        state                   => idle,
        next_state              => idle,
        index                   => 0,
        sdram_input             => SDRAM_INPUT_INIT,
        sdram_outputs           => (others => SDRAM_OUTPUT_INIT),
        frame_count             => 0,
        burst_count             => 0,
        address                 => (others => '0'),
        write_buffer            => (others => '0')
    );

    signal r, r_in              : t_arbiter_reg;
    signal s_sdram_input        : t_sdram_input;
    signal s_sdram_output       : t_sdram_output;

begin

    sdram_controller : entity wave.sdram_controller
    port map (
        clk                     => clk,
        reset                   => reset,
        pll_locked              => pll_locked,
        sdram_input             => r.sdram_input,
        sdram_output            => s_sdram_output,
        SDRAM_ADVN              => SDRAM_ADVN,
        SDRAM_CEN               => SDRAM_CEN,
        SDRAM_CRE               => SDRAM_CRE,
        SDRAM_OEN               => SDRAM_OEN,
        SDRAM_WEN               => SDRAM_WEN,
        SDRAM_LBN               => SDRAM_LBN,
        SDRAM_UBN               => SDRAM_UBN,
        SDRAM_WAIT              => SDRAM_WAIT,
        SDRAM_ADDRESS           => SDRAM_ADDRESS,
        SDRAM_DQ                => SDRAM_DQ,
        sdram_state             => sdram_state,
        sdram_count             => sdram_count
    );

    -- Connect output registers.
    sdram_outputs <= r.sdram_outputs;

    comb_process : process (r, sdram_inputs, s_sdram_output)
    begin

        r_in <= r;
        r_in.sdram_outputs <= (others => SDRAM_OUTPUT_INIT);

        -- Check for read- or write-enables.
        if r.state = idle then

            r_in.sdram_input <= SDRAM_INPUT_INIT;

            for i in 0 to N_CLIENTS - 1 loop
                if sdram_inputs(i).read_enable = '1' or sdram_inputs(i).write_enable = '1' then
                    r_in.index <= i;
                    r_in.address <= sdram_inputs(i).address;
                    r_in.frame_count <= sdram_inputs(i).burst_length;
                    r_in.sdram_outputs(i).ack <= '1';
                    r_in.state <= read_0 when sdram_inputs(i).read_enable = '1' else write_0;
                    exit;
                end if;
            end loop;

        -- Issue burst reads untils the entire frame is read.
        elsif r.state = read_0 then
            if r.frame_count <= SDRAM_MAX_BURST then
                r_in.sdram_input.burst_length <= r.frame_count;
                r_in.frame_count <= 0;
            else
                r_in.sdram_input.burst_length <= SDRAM_MAX_BURST;
                r_in.frame_count <= r.frame_count - SDRAM_MAX_BURST;
                r_in.address <= r.address + SDRAM_MAX_BURST;
            end if;

            r_in.sdram_input.read_enable <= '1';
            r_in.sdram_input.address <= r.address;
            r_in.state <= read_1;

        -- Receive read data and forward to client.
        elsif r.state = read_1 then

            if s_sdram_output.ack = '1' then
                r_in.sdram_input.read_enable <= '0';
            end if;

            if s_sdram_output.read_valid = '1' then
                r_in.sdram_outputs(r.index).read_valid <= '1';
                r_in.sdram_outputs(r.index).read_data <= s_sdram_output.read_data;
            end if;

            if s_sdram_output.done = '1' then
                if r.frame_count = 0 then
                    r_in.state <= idle;
                    r_in.sdram_outputs(r.index).done <= '1';
                else
                    r_in.state <= read_0;
                end if;
            end if;

        -- Fill write buffer
        elsif r.state = write_0 then
            r_in.write_buffer <= sdram_inputs(r.index).write_data;
            r_in.sdram_outputs(r.index).write_req <= '1';
            r_in.state <= write_1;

        -- Issue burst reads untils the entire frame is read.
        elsif r.state <= write_1 then
            if r.frame_count <= SDRAM_MAX_BURST then
                r_in.sdram_input.burst_length <= r.frame_count;
                r_in.burst_count <= r.frame_count;
                r_in.frame_count <= 0;
            else
                r_in.sdram_input.burst_length <= SDRAM_MAX_BURST;
                r_in.burst_count <= SDRAM_MAX_BURST;
                r_in.frame_count <= r.frame_count - SDRAM_MAX_BURST;
                r_in.address <= r.address + SDRAM_MAX_BURST;
            end if;

            r_in.sdram_input.write_enable <= '1';
            r_in.sdram_input.address <= r.address;

            r_in.state <= write_2;

        -- Pass write words from the client to the SDRAM. Use a 1 word write buffer to accomodate
        -- the one cycle delay introduced by the arbiter.
        elsif r.state <= write_2 then

            if s_sdram_output.ack = '1' then
                r_in.sdram_input.write_enable <= '0';
            end if;

            r_in.sdram_input.write_data <= r.write_buffer;

            -- Load write buffer except on last write cycle.
            if s_sdram_output.write_req = '1' and r.burst_count > 1 then
                r_in.write_buffer <= sdram_inputs(r.index).write_data;
                r_in.sdram_outputs(r.index).write_req <= '1';
                r_in.burst_count <= r.burst_count - 1;
            end if;

            if s_sdram_output.done = '1' then
                if r.frame_count = 0 then
                    r_in.state <= idle;
                    r_in.sdram_outputs(r.index).done <= '1';
                else
                    r_in.state <= write_0;
                end if;
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
