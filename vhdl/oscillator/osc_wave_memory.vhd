library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity osc_wave_memory is
    generic (
        init_file               : string
    );
    port (
        clk                     : in  std_logic;
        write_enable_a          : in  std_logic;
        address_a               : in  std_logic_vector(WAVETABLE_SIZE_LOG2 - 1 downto 0);
        write_data_a            : in  std_logic_vector(SAMPLE_SIZE - 1 downto 0);
        read_data_a             : out std_logic_vector(SAMPLE_SIZE - 1 downto 0);
        address_b               : in  std_logic_vector(WAVETABLE_SIZE_LOG2 - 1 downto 0);
        read_data_b             : out std_logic_vector(SAMPLE_SIZE - 1 downto 0)        
    );
end entity;

architecture arch of osc_wave_memory is

    type t_memory is array(0 to WAVETABLE_SIZE - 1)
        of std_logic_vector(SAMPLE_SIZE - 1 downto 0);

    impure function init_wave_rom (file_name : in string) return t_memory is
        FILE ram_file : text;
        variable ram_line : line;
        variable ram : t_memory;
    begin
        file_open(ram_file, file_name, read_mode);
        for i in t_memory'range loop
            readline(ram_file, ram_line);
            hread(ram_line, ram(i));
        end loop;
        return ram;
   end function;

    signal s_memory : t_memory := init_wave_rom(init_file);
    signal s_read_data_a_reg : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    signal s_read_data_b_reg : std_logic_vector(SAMPLE_SIZE - 1 downto 0);

    -- attribute syn_ramstyle : string;
    -- attribute syn_ramstyle of s_memory : signal is "no_rw_check";

    attribute ram_style : string;
    attribute ram_style of s_memory : signal is "block";

begin

    read_data_a <= s_read_data_a_reg;
    read_data_b <= s_read_data_b_reg;

    clk_proc : process (clk)
    begin

        if rising_edge(clk) then 

            s_read_data_a_reg <= s_memory(to_integer(unsigned(address_a)));
            s_read_data_b_reg <= s_memory(to_integer(unsigned(address_b)));

            if write_enable_a = '1' then 
                s_memory(to_integer(unsigned(address_a))) <= write_data_a;
            end if;

        end if;
    end process;

end architecture;
