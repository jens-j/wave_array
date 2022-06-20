library ieee;
use ieee.std_logic_1164.all;

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
        pll_lock                : in    std_logic; -- SDRAM clock needs to be running before becoming active.

        -- Client interfaces.
        sdram_inputs            : in    t_sdram_input_array(0 to N_CLIENTS - 1);
        sdram_outputs           : out   t_sdram_output_array(0 to N_CLIENTS - 1);

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

architecture arch of sdram_arbiter is

    type t_state is (idle, busy);

    type t_arbiter_reg is record
        state                   : t_state;
        index                   : integer range 0 to N_CLIENTS - 1;
        sdram_input             : t_sdram_input;
        sdram_outputs           : t_sdram_output_array(0 to N_CLIENTS - 1);
    end record;

    constant REG_INIT : t_arbiter_reg := (
        state                   => idle,
        index                   => 0,
        sdram_input             => ('0', '0', 1, (others => '0'), (others => '0')),
        sdram_outputs           => (others => ('0', '0', '0', (others => '0')))
    );

    signal r, r_in              : t_arbiter_reg;
    signal s_sdram_input        : t_sdram_input;
    signal s_sdram_output       : t_sdram_output;

begin

    sdram_controller : entity wave.sdram_controller
    port map (
        clk                     => clk,
        reset                   => reset,
        pll_lock                => pll_lock,
        sdram_input             => s_sdram_input,
        sdram_output            => s_sdram_output,
        CRAM_ADVN               => CRAM_ADVN,
        CRAM_CEN                => CRAM_CEN,
        CRAM_CRE                => CRAM_CRE,
        CRAM_OEN                => CRAM_OEN,
        CRAM_WEN                => CRAM_WEN,
        CRAM_LBN                => CRAM_LBN,
        CRAM_UBN                => CRAM_UBN,
        CRAM_WAIT               => CRAM_WAIT,
        CRAM_A                  => CRAM_A,
        CRAM_DQ                 => CRAM_DQ
    );

    s_sdram_input <= r.sdram_input;
    sdram_outputs <= r.sdram_outputs;

    comb_process : process (r, sdram_inputs, s_sdram_output)
    begin

        r_in <= r;
        r_in.sdram_input <= ('0', '0', 1, (others => '0'), (others => '0'));

        -- Default output.
        for i in 0 to N_CLIENTS - 1 loop
            r_in.sdram_outputs(i) <= ('0', '0', '0', (others => '0'));
        end loop;

        -- Check for read- or write-enables.
        if r.state = idle then
            for i in 0 to N_CLIENTS - 1 loop
                if sdram_inputs(i).read_enable = '1' or sdram_inputs(i).write_enable = '1' then
                    r_in.index <= i;
                    r_in.sdram_input <= sdram_inputs(i);
                    r_in.sdram_outputs(i).ack <= '1';
                    r_in.state <= busy;
                    exit;
                end if;
            end loop;

        -- Wait for the operation to finish.
        elsif r.state = busy then

            r_in.sdram_outputs(r.index) <= s_sdram_output;

            if s_sdram_output.done = '1' then
                r_in.state <= idle;
            else
                r_in.sdram_input <= sdram_inputs(r.index);
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
