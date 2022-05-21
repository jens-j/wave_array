library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity osc_coeff_memory is
    generic (
        init_file               : string := "osc_coeff_memory_even.coe"
    );
    port (
        clk                     : in  std_logic;
        address                : in  std_logic_vector(POLY_M_LOG2 + POLY_N_LOG2 - 2 downto 0);
        data                    : out std_logic_vector(POLY_COEFF_SIZE - 1 downto 0)
    );
end entity;

architecture arch of osc_coeff_memory is

    type t_memory is array(0 to POLY_M * POLY_N / 2 - 1)
        of std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);

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
    signal s_output_reg : std_logic_vector(POLY_COEFF_SIZE - 1 downto 0);

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
