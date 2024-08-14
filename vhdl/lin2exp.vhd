

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

-- Maps control value input in [-2**15, 2**15-1] to exponential curve in [0.5, 2] using y = 2**(x / 2**15).
-- Output value is in fixed point format. 
-- The 10 MSBs of the input value are used to look up an value from a pre-calculated table. The 6 LSBs are used 
-- to interpolate linearly between two values from the table. The interpolation is performed using
-- A + d * (B - A). Where d is the 6 LSBs. 
entity lin2exp is
    generic (
        init_file               : string := "exp.hex"
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        data_in_valid           : in  std_logic;
        data_in                 : in  t_ctrl_value;
        busy                    : out std_logic;
        data_out_valid          : out std_logic;
        data_out                : out t_ctrl_value -- 2.14 signed fixed point.
    );
end entity;


architecture arch of lin2exp is 

    constant PIPE_LEN          : integer := 7;

    type t_state is (idle, read_a, store_a_read_b, store_b, multiply, add, finalize);

    type t_lin2exp_reg is record 
        state                   : t_state;
        address_a               : unsigned(9 downto 0);
        address_b               : unsigned(9 downto 0);
        value_d                 : signed(6 downto 0);
        diff_ab                 : signed(15 downto 0); 
        value_a                 : signed(CTRL_SIZE - 1 downto 0);
        accumulator             : signed(CTRL_SIZE + 6 downto 0);
        data_out_valid          : std_logic;
        valid_shift             : std_logic_vector(PIPE_LEN - 1 downto 0);
        data_out                : signed(CTRL_SIZE - 1 downto 0);
    end record;

    constant REG_INIT : t_lin2exp_reg := (
        state                   => idle,
        address_a               => (others => '0'),
        address_b               => (others => '0'),
        value_d                 => (others => '0'),
        diff_ab                 => (others => '0'),
        value_a                 => (others => '0'),
        accumulator             => (others => '0'),
        data_out_valid          => '0',
        valid_shift             => (others => '0'),
        data_out                => (others => '0')
    ); 

    -- Register.
    signal r, r_in              : t_lin2exp_reg;

    signal s_rom_address        : std_logic_vector(9 downto 0);
    signal s_rom_data           : std_logic_vector(CTRL_SIZE - 1 downto 0);
    
begin 

    rom : entity wave.rom
    generic map (
        WIDTH                   => CTRL_SIZE,
        DEPTH_LOG2              => 10,
        INIT_FILE               => GET_INPUT_FILE_PATH & "exp.hex"
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
        r_in.valid_shift(0) <= '0';

        s_rom_address <= (others => '0');

        data_out_valid <= r.valid_shift(PIPE_LEN - 1);
        data_out <= r.data_out;
        busy <= '0' when r.state = idle else '1';

        -- Update valid shift register.
        r_in.valid_shift(PIPE_LEN - 1 downto 1) <= r.valid_shift(PIPE_LEN - 2 downto 0);

        case r.state is 
        when idle => 
            if data_in_valid = '1' then 

                -- Calculate address A. Map msb part of signed input to 10 bit unsigned address.
                v_address := unsigned(data_in(15 downto 6));
                r_in.address_a <= v_address + to_unsigned(2**9, 10);

                -- Store lsb part for interpolation.
                r_in.value_d <= '0' & data_in(5 downto 0); 

                r_in.valid_shift(0) <= '1';

                r_in.state <= read_a;
            end if;

        -- Convert signed input to address.
        when read_a=>    

            -- Read A.
            s_rom_address <= std_logic_vector(r.address_a);

            -- Calculate address for B
            r_in.address_b <= r.address_a when r.address_a = 10x"3FF" else r.address_a + 1;

            r_in.state <= store_a_read_b;

        when store_a_read_b => 

            -- Store A.
            r_in.value_a <= signed(s_rom_data);

            -- Read B.
            s_rom_address <= std_logic_vector(r.address_b);

            r_in.state <= store_b;

        
        when store_b => 

            -- Store B - A.
            r_in.diff_ab <= signed(s_rom_data) - r.value_a;
            r_in.state <= multiply;

        when multiply => 

            r_in.accumulator <= r.diff_ab * r.value_d;
            r_in.state <= add;

        when add => 

            r_in.accumulator <= r.accumulator + resize('0' & r.value_a & 6x"00", CTRL_SIZE + 7);
            r_in.state <= finalize;

        when finalize =>
            r_in.data_out_valid <= '1';
            r_in.data_out <= r.accumulator(21 downto 6);
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