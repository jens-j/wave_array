library ieee;
use ieee.std_logic_1164.all;

library wave;
use wave.wave_array_pkg.all;


-- Double buffer the external reset input (active low) and or with the software reset signal to create the system reset.
-- Keep reset high for a while and also double buffer the reset signal to all other clock domains.
entity reset_subsystem is
    port (
        system_clk              : in  std_logic;
        i2s_clk                 : in  std_logic;
        BTN_RESET               : in  std_logic;
        software_reset          : in  std_logic;
        system_reset            : out std_logic;
        i2s_reset               : out std_logic
    );
end entity;

architecture arch of reset_subsystem is

    constant RESET_PULSE_NS     : integer := 10_000;
    constant COUNT_MAX          : integer := RESET_PULSE_NS / (1_000_000_000 / SYS_FREQ);

    type t_state is (idle, reset_active);

    type t_reset_reg is record
        state                   : t_state;
        count                   : integer range 0 to COUNT_MAX - 1;
        system_reset            : std_logic;
    end record;

    constant REG_INIT : t_reset_reg := (
        state                   => idle,
        count                   => 0,
        system_reset            => '0'
    );

    signal r, r_in              : t_reset_reg;
    signal s_btn_reset          : std_logic;
    signal s_i2s_reset          : std_logic;

begin

    -- Double buffer external reset button.
    btn_ff : entity wave.cdc_ff
    port map (
        clk                     => system_clk,
        input                   => BTN_RESET,
        output                  => s_btn_reset
    );

    -- Double buffer system reset to i2s clock domain.
    sys2i2s_ff : entity wave.cdc_ff
    port map (
        clk                     => i2s_clk,
        input                   => r.system_reset,
        output                  => s_i2s_reset
    );

    comb_process : process (r, software_reset, s_btn_reset, s_i2s_reset)
    begin

        r_in <= r;

        system_reset <= r.system_reset;
        i2s_reset <= s_i2s_reset;
        
        if r.state = idle then

            r_in.system_reset <= '0';

            if s_btn_reset = '0' or software_reset = '1' then 
                r_in.count <= COUNT_MAX - 1;
                r_in.state <= reset_active;
            end if;

        else 
            r_in.system_reset <= '1'; 

            if r.count = 0 then 
                r_in.state <= idle;
            else 
                r_in.count <= r.count - 1;
            end if;
        end if;

    end process;

    reg_process : process (system_clk)
    begin
        if rising_edge(system_clk) then
            r <= r_in;
        end if;
    end process;

end architecture;
 