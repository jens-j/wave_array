library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;


entity tb_cordic_envelope is 
end entity;


architecture arch of tb_cordic_envelope is 

    signal s_clk                : std_logic := '0';
    signal s_reset              : std_logic;
    
    signal s_phase_tvalid       : std_logic := '0';
    signal s_phase_tdata        : std_logic_vector(39 downto 0); -- IP core adds 4 unused bits. 
    signal s_dout_tvalid        : std_logic;
    signal s_dout_tdata         : std_logic_vector(47 downto 0); -- Sin & cos.

    signal s_phase              : unsigned(31 downto 0) := x"FFFF_FF00";
    signal s_sin                : signed(16 downto 0);
    signal s_cos                : signed(16 downto 0);
    
begin

    s_clk <= not s_clk after 5 ns;
    s_reset <= '1', '0' after 10 us;

    s_cos <= signed(s_dout_tdata(16 downto 0));
    s_sin <= signed(s_dout_tdata(40 downto 24));

    input_proc : process 
    begin 
        wait until rising_edge(s_clk) and s_reset = '0';
        s_phase_tvalid <= '1';
        s_phase_tdata <= x"01" & std_logic_vector(s_phase);

        wait until rising_edge(s_clk);
        s_phase_tvalid <= '0';

        wait until rising_edge(s_clk) and s_dout_tvalid = '1';

        if s_phase < x"FFFF_FFFF" then 
            s_phase <= s_phase + 1;
        else 
            wait;
        end if;

    end process;

    cordic : entity xil_defaultlib.envelope_cordic_gen
    port map (
        aclk                    => s_clk,
        s_axis_phase_tvalid     => s_phase_tvalid,
        s_axis_phase_tdata      => s_phase_tdata,
        m_axis_dout_tvalid      => s_dout_tvalid,
        m_axis_dout_tdata       => s_dout_tdata
    );
end architecture;