library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package wave_array_pkg is

    constant SYS_FREQ               : integer := 100_000_000;

    constant NUMBER_OF_VOICES       : positive := 4;

    constant SAMPLE_WIDTH           : integer := 16;
    constant SAMPLE_MAX             : integer := 2**SAMPLE_WIDTH - 1;
    constant SAMPLE_RATE            : integer := 96_000; -- Oversampling by 2x simplifies mip-mapping

    constant TABLE_SIZE_LOG2        : integer := 11;
    constant TABLE_SIZE             : integer := 2**TABLE_SIZE_LOG2; -- Number of samples per wave table.
    constant TABLE_ADDR_FRAC        : integer := 8; -- Precision used for interpolating between table samples.
    constant TABLE_ADDR_SIZE        : integer := TABLE_SIZE + TABLE_ADDR_FRAC;

    constant MIPMAP_LEVELS          : integer := 10; -- 1 per octave for octaves 0 - 9. This covers the entire midi range except octave -1 which is inaudible.
    constant MIPMAP_L0_SIZE         : integer := 2048;
    constant MIPMAP_TABLE_SIZE      : integer := 4092;
    constant MIPMAP_ADDR_SIZE       : integer := 12;

    -- Audio sample types.
    subtype t_mono_sample is signed(SAMPLE_WIDTH - 1 downto 0);
    type t_stereo_sample is array (1 downto 0) of t_mono_sample;
    type t_mono_sample_array is array (integer range <>) of t_mono_sample;
    type t_stereo_sample_array is array (integer range <>) of t_stereo_sample;

    -- Wave table arbiter signals.
    type t_table_arb_input is record
        read_enable                 : std_logic;
        address                     : std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0);
    end record;

    type t_table_arb_output is record
        ack                         : std_logic;
        valid                       : std_logic;
        data                        : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    end record;

    type t_table_arb_input_array is array (integer range <>) of t_table_arb_input;
    type t_table_arb_output_array is array (integer range <>) of t_table_arb_output;

end package;
