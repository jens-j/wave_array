library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity oscillator is
    generic (
        N_OSCILLATORS           : natural
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample trigger.
        osc_inputs              : in  t_osc_input_array(0 to N_OSCILLATORS - 1);
        output_samples          : out t_mono_sample_array(0 to N_OSCILLATORS - 1);
        addrgen_output          : out t_addrgen_to_tableinterp_array(0 to N_OSCILLATORS - 1) -- Debug output
    );
end entity;

architecture arch of oscillator is


    signal s_frame_0_index          : integer range 0 to 3;
    signal s_frame_1_index          : integer range 0 to 3;
    signal s_intermediate_samples   : t_stereo_sample_array(0 to N_OSCILLATORS - 1);
    signal s_addrgen_to_tableinterp : t_addrgen_to_tableinterp_array(0 to N_OSCILLATORS - 1);
    signal s_overflow               : std_logic;
    signal s_timeout                : std_logic;

begin

    addrgen_output <= s_addrgen_to_tableinterp;

    s_frame_0_index <= 0;
    s_frame_1_index <= 1;

    table_addr_gen : entity wave.table_address_generator
    generic map (
        N_OSCILLATORS           => N_OSCILLATORS
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        osc_inputs              => osc_inputs,
        addrgen_output          => s_addrgen_to_tableinterp
    );

    table_interpolator : entity wave.table_interpolator
    generic map (
        N_OSCILLATORS           => N_OSCILLATORS
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        frame_0_index           => s_frame_0_index,
        frame_1_index           => s_frame_1_index,
        osc_inputs              => osc_inputs,
        addrgen_input           => s_addrgen_to_tableinterp,
        output_samples          => s_intermediate_samples,
        overflow                => s_overflow,
        timeout                 => s_timeout
    );

    halfband : entity wave.halfband_filter
    generic map (
        N_OSCILLATORS           => N_OSCILLATORS
    )
    port map (
        clk                     => clk,
        reset                   => reset,
        next_sample             => next_sample,
        input_samples           => s_intermediate_samples,
        output_samples          => output_samples
    );

end architecture;
