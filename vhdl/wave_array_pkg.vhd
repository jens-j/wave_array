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

    constant SAMPLE_SIZE            : integer := 16;
    constant SAMPLE_MAX             : integer := 2**SAMPLE_SIZE - 1;
    constant SAMPLE_RATE            : integer := 96_000; -- Oversampling by 2x simplifies mip-mapping

    -- Constants related to a single period wave table.
    constant WAVE_SIZE_LOG2         : integer := 11;
    constant WAVE_SIZE              : integer := 2**WAVE_SIZE_LOG2; -- Number of samples per wave table.
    constant WAVE_ADDR_FRAC         : integer := 8; -- Precision used for interpolating between table samples.
    constant WAVE_ADDR_SIZE         : integer := WAVE_SIZE_LOG2 + WAVE_ADDR_FRAC;

    -- Constants relating to complete mipmap table with multiple waves.
    constant MIPMAP_LEVELS          : integer := 10; -- 1 per octave for octaves 0 - 9. This covers the entire midi range except octave -1 which is inaudible.
    constant MIPMAP_L0_SIZE         : integer := 2048;
    constant MIPMAP_TABLE_SIZE      : integer := 4092;
    constant MIPMAP_ADDR_SIZE       : integer := 12;

    constant ADC_SAMPLE_SIZE        : integer := 12;
    constant ADC_FILTER_FRAC        : integer := 8;

    -- Audio sample types.
    subtype t_mono_sample is signed(SAMPLE_SIZE - 1 downto 0);
    type t_stereo_sample is array (1 downto 0) of t_mono_sample;
    type t_mono_sample_array is array (integer range <>) of t_mono_sample;
    type t_stereo_sample_array is array (integer range <>) of t_stereo_sample;

    -- Oscillator types.
    subtype t_mipmap_address is std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0);
    type t_mipmap_address_array is array (integer range <>) of t_mipmap_address;

    subtype t_table_phase is unsigned(WAVE_ADDR_SIZE - 1 downto 0);
    type t_table_phase_array is array (integer range <>) of t_table_phase;

    -- Wave table arbiter signals.
    type t_table_arb_input is record
        read_enable                 : std_logic;
        address                     : std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0);
    end record;

    type t_table_arb_output is record
        ack                         : std_logic;
        valid                       : std_logic;
        data                        : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    end record;

    type t_table_arb_input_array is array (integer range <>) of t_table_arb_input;
    type t_table_arb_output_array is array (integer range <>) of t_table_arb_output;

    -- Mipmap table upper velocity limit. The top table has no upper limit.
    constant MIPMAP_THRESHOLDS : t_table_phase_array(0 to MIPMAP_LEVELS - 2) := (
        19x"00200",
        19x"00400",
        19x"00800",
        19x"01000",
        19x"02000",
        19x"04000",
        19x"08000",
        19x"10000",
        19x"20000" -- Table velocity corresponding to 1/4 of the sample rate.
    );

    -- Mipmap table address offsets for each mipmap level.
    constant MIPMAP_OFFSETS : t_mipmap_address_array(0 to MIPMAP_LEVELS - 1) := (
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
