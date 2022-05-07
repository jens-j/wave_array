library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package wave_array_pkg is

    constant SIMULATION             : boolean := false
    --pragma synthesis_off
                                      or true
    --pragma synthesis_on
    ;

    constant SYS_FREQ               : integer := 100_000_000;
    constant NUMBER_OF_VOICES       : positive := 1;

    -- Audio sample constants.
    constant SAMPLE_SIZE            : integer := 16;
    constant SAMPLE_MAX             : integer := 2**SAMPLE_SIZE - 1;
    constant SAMPLE_RATE            : integer := 96_000; -- Oversampling by 2x simplifies mip-mapping

    -- Constants related to wavetables.
    constant WAVE_SIZE_LOG2         : integer := 11;
    constant WAVE_SIZE              : integer := 2**WAVE_SIZE_LOG2; -- Number of samples per wave table.
    constant WAVE_MAX_FRAMES        : integer := 256;

    -- Constants relating to complete mipmap table with multiple waves.
    constant MIPMAP_LEVELS          : integer := 10; -- 1 per octave for octaves 0 - 9. This covers the entire midi range except octave -1 which is inaudible.
    constant MIPMAP_L0_SIZE_LOG2    : integer := 11
    constant MIPMAP_L0_SIZE         : integer := 2**MIPMAP_L0_SIZE_LOG2;
    constant MIPMAP_TABLE_SIZE_LOG2 : integer := MIPMAP_L0_SIZE_LOG2 + 1;
    constant MIPMAP_TABLE_SIZE      : integer := 2**MIPMAP_TABLE_SIZE_LOG2;

    -- Oscillator constants
    constant OSC_SAMPLE_FRAC        : integer := 8; -- Fractional bits used for sample interpolation
    constant OSC_COEFF_FRAC         : integer := 8; -- Fractional bits used for coefficient interpolation.

    -- Oscillator polyphase interpolation filter coefficient.
    constant POLY_COEFF_SIZE        : integer := 16;
    constant POLY_M_LOG2            : integer := 7;
    constant POLY_M                 : integer := 2**POLY_M_LOG2;
    constant POLY_N_LOG2            : integer := 4;
    constant POLY_N                 : integer := 2**POLY_N_LOG2;

    constant ADC_SAMPLE_SIZE        : integer := 12;
    constant ADC_FILTER_FRAC        : integer := 8;

    -- Audio sample types.
    subtype t_mono_sample is signed(SAMPLE_SIZE - 1 downto 0);
    type t_stereo_sample is array (0 to 1) of t_mono_sample;
    type t_mono_sample_array is array (positive range <>) of t_mono_sample;
    type t_stereo_sample_array is array (positive range <>) of t_stereo_sample;

    -- Address in the oscillator coefficient memory. It consists of two memories that each hold
    -- either the even or odd coefficients.
    subtype t_coeff_address is unsigned(POLY_M_LOG2 * POLY_N_LOG2 - 2 downto 0);

    -- Mipmap table types.
    subtype t_mipmap_address is unsigned(MIPMAP_TABLE_SIZE_LOG2 - 1 downto 0);
    type t_mipmap_address_array is array (positive <>) of t_mipmap_address

    -- Oscillator types.
    subtype t_osc_phase is -- Wavetable phase (including fractional part).
        unsigned(MIPMAP_L0_SIZE_LOG2 + POLY_M_LOG2 + OSC_COEFF_FRAC - 1 downto 0);
    type t_osc_phase_array is array (positive <>) of t_osc_phase;


    subtype t_osc_position is unsigned(OSC_SAMPLE_FRAC - 1 downto 0); -- Oscillator frame position (only fractional).

    type t_osc_input is record
        velocity                    : t_osc_phase; -- Table velocity.
        position                    : t_osc_position; -- Frame position.
    end record;

    type t_osc_input_array is array (positive <>) of t_osc_input;

    -- Mipmap table upper velocity limi. The top table has no upper limit.
    constant MIPMAP_THRESHOLDS : t_osc_phase_array(0 to MIPMAP_LEVELS - 2) := (
        26x"0010000",
        26x"0020000",
        26x"0040000",
        26x"0080000",
        26x"0100000",
        26x"0200000",
        26x"0400000",
        26x"0800000",
        26x"1000000" -- Table velocity corresponding to 1/4 of the sample rate.
    );

    -- Mipmap table address offsets for each mipmap level.
    constant MIPMAP_LEVEL_OFFSETS : t_mipmap_address_array(0 to MIPMAP_LEVELS - 1) := (
        x"000",
        x"800",
        x"C00",
        x"E00",
        x"F00",
        x"F80",
        x"FC0",
        x"FE0",
        x"FF0",
        x"FF8"
    );


end package;
