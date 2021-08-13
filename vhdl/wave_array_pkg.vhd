library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package wave_array_pkg is

    constant SYS_FREQ               : integer := 100_000_000;

    constant SAMPLE_WIDTH           : integer := 16;
    constant SAMPLE_MAX             : integer := 2**SAMPLE_WIDTH - 1;
    constant SAMPLE_RATE            : integer := 48_000;

    constant WAVE_RES_LOG2          : integer := 11;
    constant WAVE_RES               : integer := 2**WAVE_RES_LOG2; -- Number of samples per wave table
    constant WAVE_PREC              : integer := 16; -- Precision used interpolating between table samples

    constant I2S_CLK_DIV            : integer := SYS_FREQ / (SAMPLE_RATE * SAMPLE_WIDTH * 2); -- Divider used to generate I2S clock

    subtype t_mono_sample is std_logic_vector(SAMPLE_WIDTH - 1 downto 0); -- Mono audio sample
    type t_stereo_sample is array (1 downto 0) of t_mono_sample; -- L/R audio sample

end package;
