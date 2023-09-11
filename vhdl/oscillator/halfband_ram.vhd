library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity halfband_ram is
    generic (
        DEPTH_LOG2              : integer;
    );
    port (
        clk                     : in  std_logic;
        write_enable            : in  std_logic;
        address                 : in  std_logic_vector(DEPTH_LOG2 - 1 downto 0);
        write_data              : in  std_logic_vector(SAMPLE_SIZE - 1 downto 0);
        read_data               : out std_logic_vector(SAMPLE_SIZE - 1 downto 0)
    );
end entity;

architecture arch of halfband_ram is

    constant DEPTH : integer := 2**DEPTH_LOG2;

    type t_memory is array(0 to DEPTH - 1)
        of std_logic_vector(SAMPLE_SIZE - 1 downto 0);


    signal s_memory : t_memory := init_wave_rom(init_file);
    signal s_read_data_reg : std_logic_vector(SAMPLE_SIZE - 1 downto 0);

    -- attribute syn_ramstyle : string;
    -- attribute syn_ramstyle of s_memory : signal is "no_rw_check";

    attribute ram_style : string;
    attribute ram_style of s_memory : signal is "block";

begin

    read_data <= s_read_data_reg;

    clk_proc : process (clk)
    begin

        if rising_edge(clk) then 

            s_read_data_reg <= s_memory(to_integer(unsigned(address)));

            if write_enable_a = '1' then 
                s_memory(to_integer(unsigned(address))) <= write_data;
            end if;

        end if;
    end process;

end architecture;