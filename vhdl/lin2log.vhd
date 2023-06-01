library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;

-- Convert a linear 16 bit control value to a 32-bit logaritmic mapping. 
-- A 1024 entry LUT is used with linear interpolation based on the remaining 6 lsb.
-- Interpolation is performed by adding shifted values of B - A to A.
entity lin2log is
    generic (
        init_file               : string := "log.hex"
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        data_in_valid           : in  std_logic;
        data_in                 : in  t_ctrl_value;
        data_out_valid          : out std_logic;
        data_out                : out unsigned(31 downto 0)
    );
end entity;


architecture arch of lin2log is 

    constant PIPE_LEN_MEM       : integer := 1;
    constant PIPE_LEN_MULT      : integer := 4;
    constant PIPE_SUM_MULT      : integer := PIPE_LEN_MEM + PIPE_LEN_MULT;

    type t_state is (idle, store_a, store_b, interpolate, finalize);

    type t_envelope_reg is record 
        state                   : t_state;
        address_b               : unsigned(9 downto 0);
        value_d                 : signed(6 downto 0);
        diff_ab                 : signed(32 downto 0); 
        accumulator             : signed(38 downto 0);
        counter                 : integer range 0 to 5;
        data_out_valid          : std_logic;
        data_out                : unsigned(31 downto 0);
    end record;

    constant REG_INIT : t_envelope_reg := (
        state                   => idle,
        address_b               => (others => '0'),
        value_d                 => (others => '0'),
        diff_ab                 => (others => '0'),
        accumulator             => (others => '0'),
        counter                 => 0,
        data_out_valid          => '0',
        data_out                => (others => '0')
    ); 

    -- Register.
    signal r, r_in              : t_envelope_reg;

    signal s_rom_address        : std_logic_vector(9 downto 0);
    signal s_rom_data           : std_logic_vector(31 downto 0);
    
begin 

    rom : entity wave.lin2log_rom
    generic map (
        init_file               => init_file
    )
    port map (
        clk                     => clk,
        address                 => s_rom_address,
        data                    => s_rom_data
    );

    combinatorial : process (r, data_in_valid, data_in, s_rom_data) 
        variable v_address : unsigned(9 downto 0);
    begin

        r_in <= r;
        r_in.data_out_valid <= '0';

        s_rom_address <= (others => '0');

        data_out_valid <= r.data_out_valid;
        data_out <= r.data_out;

        case r.state is 
        when idle => 
            if data_in_valid = '1' then 

                v_address := data_in(15 downto 6);

                -- Read A.
                s_rom_address <= std_logic_vector(v_address);

                -- Calculate address for B
                r_in.address_b <= v_address when v_address = 10x"3FF" else v_address + 1;

                -- Store msb part for interpolation.
                r_in.value_d <= signed('0' & data_in(5 downto 0));

                r_in.state <= store_a;
            end if;

        when store_a => 

            -- Store A.
            r_in.accumulator <= "0" & signed(s_rom_data) & 6x"00";

            -- Read B.
            s_rom_address <= std_logic_vector(r.address_b);

            r_in.state <= store_b;

        
        when store_b => 

            -- Store B - A.
            r_in.diff_ab <= signed('0' & s_rom_data) - r.accumulator(38 downto 6);

            r_in.counter <= 0;
            r_in.state <= interpolate;

        -- Interpolate between A and B by adding shifted values of B - A to A.
        when interpolate => 

            if r.diff_ab(r.counter) = '1' then 
                r_in.accumulator <= r.accumulator + resize(shift_left(r.diff_ab, r.counter), 38);
            end if;

            if r.counter < 5 then 
                r_in.counter <= r.counter + 1;
            else 
                r_in.state <= finalize;
            end if;

        when finalize => 

            r_in.data_out_valid <= '1';
            r_in.data_out <= unsigned(r.accumulator(37 downto 6));
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