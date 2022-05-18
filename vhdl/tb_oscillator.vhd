library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;
use wave.midi_pkg.all;

entity tb_oscillator is
end entity;

architecture arch of tb_oscillator is

    signal s_clk             : std_logic := '0';
    signal s_reset           : std_logic := '1';
    signal s_osc_inputs      : t_osc_input_array(0 to 0);
    signal s_next_sample     : std_logic := '0';
    signal s_output_samples  : t_mono_sample_array(0 to 0);

begin

    dut : entity wave.oscillator
    generic map(
        N_OSCILLATORS           => 1
    )
    port map(
        clk                     => s_clk,
        reset                   => s_reset,
        next_sample             => s_next_sample,
        osc_inputs              => s_osc_inputs,
        output_samples          => s_output_samples
    );

    s_osc_inputs(0).velocity <= shift_right(BASE_OCT_VELOCITIES(0), 5); -- C4
    s_osc_inputs(0).position <= (others => '0');

    s_clk <= not s_clk after 5 ns;
    s_reset <= '0' after 1 us;

    -- Generate the next sample pulse @ 48 kHz
    next_sample : process
    begin

        wait until s_clk'event and s_clk = '1';
        s_next_sample <= '1';
        wait until s_clk'event and s_clk = '1';
        s_next_sample <= '0';

        wait for 20833 ns; -- 48 kHz

    end process;


end architecture;
