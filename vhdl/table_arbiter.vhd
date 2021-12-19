library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity table_arbiter is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        table_inputs            : in  t_table_arb_input_array(0 to NUMBER_OF_VOICES - 1);
        table_outputs           : out t_table_arb_output_array(0 to NUMBER_OF_VOICES - 1);
        ram_read_enable         : out std_logic;
        ram_address             : out std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0);
        ram_data                : in  std_logic_vector(SAMPLE_SIZE - 1 downto 0)
    );
end entity;

architecture arch of table_arbiter is


    type t_table_arbiter_reg is record
        index                   : integer range 0 to NUMBER_OF_VOICES - 1;
        ram_read_enable         : std_logic;
        ram_address             : std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0);
        table_outputs           : t_table_arb_output_array(0 to NUMBER_OF_VOICES - 1);
        read_active             : std_logic;
        read_active_d           : std_logic;
        result_index            : integer range 0 to NUMBER_OF_VOICES - 1;
        result_index_d          : integer range 0 to NUMBER_OF_VOICES - 1;
    end record;

    constant TABLE_OUTPUTS_INIT : t_table_arb_output_array := (others => ('0', '0', (others => '0')));
    constant R_INIT : t_table_arbiter_reg := (
        state                   => idle,
        index                   => 0,
        ram_read_enable         => '0',
        ram_address             => (others => '0'),
        table_outputs           => TABLE_OUTPUTS_INIT,
        read_active             => '0',
        read_active_d           => '0',
        result_index            => 0,
        result_index_d          => 0
    );

    signal r, r_in : t_table_arbiter_reg;

begin

    combinatorial : process (r, sample_in)
    begin

        r_in <= r;
        r_in.table_outputs <= (others => TABLE_OUTPUTS_INIT);
        r_in.read_active_d <= r.read_active;
        r_in.result_index_d <= r.result_index

        if table_inputs(r.index).read_enable = '1' then
            r_in.ram_read_enable <= '1';
            r_in.ram_address <= r.table_inputs.address;
            r_in.table_outputs(r.index).ack <= '1';
            r_in.read_active <= '0';
            r_in.result_index <= r.index;
        else
            r_in.ram_read_enable <= '0';
            r_in.ram_address <= (others => '0');
            r_in.read_active <= '0';
        end if;

        if r.read_active_d = '1' then
            r_in.table_outputs(r.result_index_d).valid <= '1';
            r_in.table_outputs(r.result_index_d).data <= ram_data;
        end if;

        if r.index = NUMBER_OF_VOICES - 1 then
            r_in.index <= 0;
        else
            r_in.index <= r.index + 1;
        end if;

        ram_read_enable <= r.ram_read_enable;
        ram_address <= r.ram_address;
        table_outputs <= r.table_outputs;

    end process;

    reg_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= R_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
