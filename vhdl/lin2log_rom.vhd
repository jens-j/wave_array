library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;

library wave;
use wave.wave_array_pkg.all;


entity lin2log_rom is
    generic (
        init_file               : string := "log.hex"
    );
    port (
        clk                     : in  std_logic;
        address                 : in  std_logic_vector(9 downto 0);
        data                    : out std_logic_vector(31 downto 0)
    );
end entity;

architecture arch of lin2log_rom is

    type t_memory is array(0 to 1023)
        of std_logic_vector(31 downto 0);

    impure function init_coeff_rom (file_name : in string) return t_memory is
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

    signal s_memory : t_memory := init_coeff_rom(init_file);
    signal s_output_reg : std_logic_vector(31 downto 0);

    attribute syn_ramstyle : string;
    attribute syn_ramstyle of s_memory : signal is "no_rw_check";

begin

    data <= s_output_reg;

    clk_proc : process (clk)
    begin
        if rising_edge(clk) then
            s_output_reg <= s_memory(to_integer(unsigned(address)));
        end if;
    end process;


end architecture;