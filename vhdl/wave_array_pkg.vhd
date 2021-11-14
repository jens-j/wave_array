library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package wave_array_pkg is

    constant SYS_FREQ               : integer := 100_000_000;

    constant NUMBER_OF_VOICES       : positive := 4;

    constant SAMPLE_WIDTH           : integer := 16;
    constant SAMPLE_MAX             : integer := 2**SAMPLE_WIDTH - 1;
    constant SAMPLE_RATE            : integer := 50_000; -- SYS_FREQ should be an integer multiple of SAMPLE_RATE

    constant WAVE_RES_LOG2          : integer := 11;
    constant WAVE_RES               : integer := 2**WAVE_RES_LOG2; -- Number of samples per wave table.
    constant WAVE_PREC              : integer := 16; -- Precision used interpolating between table samples.

    constant I2S_CLK_DIV            : integer := SYS_FREQ / (SAMPLE_RATE * SAMPLE_WIDTH * 2); -- Divider used to generate I2S clock.

    -- Samples are unsigned throughout the design but are converted to 2s complement when sent over I2S.
    subtype t_mono_sample is std_logic_vector(SAMPLE_WIDTH - 1 downto 0); -- Mono audio sample.
    type t_stereo_sample is array (1 downto 0) of t_mono_sample; -- L/R audio sample.

    type t_mono_sample_array is array (integer range <>) of t_mono_sample;
    type t_stereo_sample_array is array (integer range <>) of t_stereo_sample;

    -- Re-scale sample from unsigned to signed while preserving the full range.
    function mono_sample_to_2sc (x : t_mono_sample) return t_mono_sample;

    -- Re-scale sample from unsigned to signed while preserving the full range.
    function stereo_sample_to_2sc (x : t_stereo_sample) return t_stereo_sample;

end package;


package body wave_array_pkg is

    -- Re-scale sample from unsigned to signed while preserving the full range.
    function mono_sample_to_2sc (x : t_mono_sample) return t_mono_sample is
        variable v_return : t_mono_sample := x;
    begin
        -- Flip the msb.
        v_return(t_mono_sample'length - 1) := not v_return(t_mono_sample'length - 1);
        return v_return;
    end function;

    -- Re-scale sample from unsigned to signed while preserving the full range.
    function stereo_sample_to_2sc (x : t_stereo_sample) return t_stereo_sample is
    begin
        return (mono_sample_to_2sc(x(0)), mono_sample_to_2sc(x(1)));
    end function;

end wave_array_pkg;
