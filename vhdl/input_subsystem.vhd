library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity input_subsystem is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        vauxp0                  : in  std_logic;
        vauxn0                  : in  std_logic;
        value                   : out std_logic_vector(15 downto 0)
    );
end entity;

architecture arch of input_subsystem is

    type t_state is (idle, waiting);

    type t_seven_segment_reg is record
        state                   : t_state;
    end record;

    constant R_INIT : t_seven_segment_reg := (
        state                   => idle
    );

    constant GND                : std_logic := '0';

    signal r, r_in              : t_seven_segment_reg := R_INIT;

    signal xadc_busy_s          : std_logic;
    signal xadc_eoc_s           : std_logic;
    signal xadc_eos_s           : std_logic;

    signal drp_di_s             : std_logic_vector(15 downto 0);
    signal drp_do_s             : std_logic_vector(15 downto 0);
    signal drp_daddr_s          : std_logic_vector(6 downto 0);
    signal drp_den_s            : std_logic;
    signal drp_dwe_s            : std_logic;
    signal drp_drdy_s           : std_logic;

    component xadc_gen is
    port (
        daddr_in                : in   std_logic_vector (6 downto 0);
        den_in                  : in   std_logic;
        di_in                   : in   std_logic_vector (15 downto 0);
        dwe_in                  : in   std_logic;
        do_out                  : out  std_logic_vector (15 downto 0);
        drdy_out                : out  std_logic;
        dclk_in                 : in   std_logic;
        reset_in                : in   std_logic;
        vauxp0                  : in   std_logic;
        vauxn0                  : in   std_logic;
        busy_out                : out  std_logic;
        channel_out             : out  std_logic_vector (4 downto 0);
        eoc_out                 : out  std_logic;
        eos_out                 : out  std_logic;
        alarm_out               : out  std_logic;
        vp_in                   : in   std_logic;
        vn_in                   : in   std_logic
    );
    end component;

begin

    XADC_inst : xadc_gen
    port map (
        daddr_in                => drp_daddr_s,  -- Address bus for the dynamic reconfiguration port
        den_in                  => drp_den_s,    -- Enable Signal for the dynamic reconfiguration port
        di_in                   => drp_di_s,     -- Input data bus for the dynamic reconfiguration port
        dwe_in                  => drp_dwe_s,    -- Write Enable for the dynamic reconfiguration port
        do_out                  => drp_do_s,     -- Output data bus for dynamic reconfiguration port
        drdy_out                => drp_drdy_s,   -- Data ready signal for the dynamic reconfiguration port
        dclk_in                 => clk,          -- Clock input for the dynamic reconfiguration port
        reset_in                => reset,        -- Reset signal for the System Monitor control logic
        vauxp0                  => vauxp0,       -- Auxiliary Channel 0
        vauxn0                  => vauxn0,
        busy_out                => xadc_busy_s,  -- ADC Busy signal
        channel_out             => open,         -- Channel Selection Outputs
        eoc_out                 => xadc_eoc_s,   -- End of Conversion Signal
        eos_out                 => xadc_eos_s,   -- End of Sequence Signal
        alarm_out               => open,         -- OR'ed output of all the Alarms
        vp_in                   => GND,          -- Dedicated Analog Input Pair
        vn_in                   => GND           -- Wont synthsize without the explicit type
    );


    comb_proc : process (r, drp_drdy_s)
    begin

        drp_dwe_s <= '0';
        drp_daddr_s <= 7x"10";
        drp_di_s <= (others => '0');
        value <= drp_do_s;

        case (r.state) is

            when idle =>
                drp_den_s <= '1';
                r_in.state <= waiting;

            when waiting =>
                drp_den_s <= '0';
                if drp_drdy_s = '1' then
                    r_in.state <= idle;
                end if;

        end case;
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
