library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

Library UNISIM;
use UNISIM.vcomponents.all;

library wave;
use wave.wave_array_pkg.all;

library qspi;
use qspi.qspi_pkg.all;


entity qspi_interface is
    port (
        system_clk              : in  std_logic;
        spi_clk                 : in  std_logic;
        reset                   : in  std_logic;
        QSPI_CS                 : out std_logic;
        QSPI_SCK                : out std_logic;
        QSPI_DQ                 : inout std_logic_vector(3 downto 0)
    );
end entity;


architecture arch of qspi_interface is 

    type t_state is (idle, done,
        lower_cs, write_command, dummy_cycle, read_data);

    type t_qspi_wrapper_reg is record
        state                   : t_state;
        next_state              : t_state;
        register_output         : t_register_output;
        qspi_cs                 : std_logic;
        qspi_dq                 : std_logic_vector(3 downto 0);
        read_enable             : std_logic;
        read_address            : std_logic_vector(7 downto 0);
        read_data               : std_logic_vector(23 downto 0);
        write_enable            : std_logic;
        clock_enable            : std_logic;
        output_enable           : std_logic_vector(3 downto 0);
        command                 : std_logic_vector(7 downto 0);
        bit_counter             : integer range 0 to 23;
    end record;

    constant R_INIT : t_qspi_wrapper_reg := (
        state                   => idle,
        next_state              => idle,
        register_output         => REGISTER_OUTPUT_INIT,
        qspi_cs                 => '1',
        qspi_dq                 => (others => '0'),
        read_enable             => '0',
        read_address            => (others => '0'),
        read_data               => (others => '0'),
        write_enable            => '0',
        clock_enable            => '0',
        output_enable           => (others => '0'),
        command                 => (others => '0'),
        bit_counter             => 0
    );

    signal r, r_in : t_qspi_wrapper_reg := R_INIT;

begin 

    -- Instantiate spi clock gate.
    -- This is very sketchy because the clock enable signal has 180 phase difference with the input clock.
    BUFGCE_inst : BUFGCE_1
    port map (
        O   => QSPI_SCK,        -- 1-bit output: Clock output
        CE  => r.clock_enable,  -- 1-bit input: Clock enable input for I0
        I   => spi_clk          -- 1-bit input: Primary clock
    );

    -- Intantiate tri-state buffers for data lines.
    tristate_gen: for i in 0 to 3 generate 
        QSPI_DQ(i) <= r.qspi_dq(i) when r.output_enable(i) = '1' else 'Z';
    end generate;

    -- Connect output registers.
    qspi_cs <= r.qspi_cs;


    comb_proc : process (r, QSPI_DQ)
    begin 

        r_in <= r;
        
        case r.state is 
        when idle => 
            r_in.read_data <= (others => '0');
            r_in.command <= x"9F";
            r_in.bit_counter <= 7;
            r_in.state <= lower_cs;

        when lower_cs => 
            r_in.qspi_cs <= '0';
            r_in.clock_enable <= '1';
            r_in.output_enable <= "0001";
            r_in.state <= write_command;

        when write_command => 

            r_in.qspi_dq(0) <= r.command(r.bit_counter);
            
            if r.bit_counter > 0 then 
                r_in.bit_counter <= r.bit_counter - 1;
            else 
                r_in.state <= dummy_cycle;
            end if;

        when dummy_cycle =>
            r_in.output_enable <= "0000";
            r_in.bit_counter <= 23;
            r_in.state <= read_data;

        when read_data => 

            r_in.read_data(r.bit_counter) <= QSPI_DQ(1);

            if r.bit_counter = 1 then 
                r_in.clock_enable <= '0';
            end if;
            
            if r.bit_counter > 0 then 
                r_in.bit_counter <= r.bit_counter - 1;
            else 
                r_in.qspi_cs <= '1';
                r_in.state <= done;
            end if;

        when done =>

        end case;

    end process;

    reg_process : process(system_clk)
    begin
        if rising_edge(system_clk) then
            if reset = '1' then
                r <= R_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;