library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity osc_wave_memory is
    generic (
        init_file               : string := "osc_wave_memory.coe"
    );
    port (
        read_clk                : in  std_logic;
        read_address            : in  std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 - 1 downto 0);
        read_data               : out std_logic_vector(4 * SAMPLE_SIZE - 1 downto 0);
        write_clk               : in  std_logic;
        write_enable            : in  std_logic_vector(0 downto 0);
        write_address           : in  std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 0);
        write_data              : in  std_logic_vector(SAMPLE_SIZE - 1 downto 0)
    );
end entity;

architecture arch of osc_wave_memory is

    type t_memory is array(0 to MIPMAP_TABLE_SIZE - 1)
        of std_logic_vector(4 * SAMPLE_SIZE - 1 downto 0);

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
    signal s_read_data_reg : std_logic_vector(4 * SAMPLE_SIZE - 1 downto 0);

    attribute syn_ramstyle : string;
    attribute syn_ramstyle of s_memory : signal is "no_rw_check";

begin

    read_data <= s_read_data_reg;

    clk_proc : process (read_clk, write_clk)
        -- variable v_sub : integer range 0 to 3; -- Sub address.
        variable v_addr : integer range 0 to MIPMAP_TABLE_SIZE_LOG2 - 1;
    begin

        if rising_edge(read_clk) then
            s_read_data_reg <= s_memory(to_integer(unsigned(read_address)));
        end if;

        if rising_edge(write_clk) then
            if write_enable = "1" then

                v_addr := to_integer(unsigned(write_address(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 2)));

                -- The lowest 2 bits of the write address select the word within the memory line.
                case write_address(1 downto 0) is
                    when "00" =>
                        s_memory(v_addr)(SAMPLE_SIZE - 1 downto 0) <= write_data;
                    when "01" =>
                        s_memory(v_addr)(2 * SAMPLE_SIZE - 1 downto SAMPLE_SIZE) <= write_data;
                    when "10" =>
                        s_memory(v_addr)(3 * SAMPLE_SIZE - 1 downto 2 * SAMPLE_SIZE) <= write_data;
                    when others =>
                        s_memory(v_addr)(4 * SAMPLE_SIZE - 1 downto 3 * SAMPLE_SIZE) <= write_data;
                end case;
            end if;
        end if;
    end process;


end architecture;
