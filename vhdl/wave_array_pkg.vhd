library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package wave_array_pkg is

    constant SIMULATION             : boolean := false
    --pragma synthesis_off
                                      or true
    --pragma synthesis_on
    ;

    constant SIM_FILE_PATH          : string := "../../../../../../data/";
    constant SYNTH_FILE_PATH        : string := "../../../../data/";

    constant SYS_FREQ               : integer := 100_000_000;
    constant SDRAM_FREQ             : integer := 100_000_000;

    constant UART_BAUD              : integer := 1_000_000 -- 115_200;
    --pragma synthesis_off
                                      * 50
    --pragma synthesis_on
    ;

    constant UART_MAX_BURST_LOG2    : integer := 12;
    constant UART_MAX_BURST         : integer := 2**UART_MAX_BURST_LOG2;

    constant N_TABLES               : positive := 1; -- Number of parallel wave tables.
    constant N_VOICES               : positive := 4; -- Number of parallel oscillators per table.
    constant N_OSCILLATORS          : positive := N_TABLES * N_VOICES; -- Total number of oscillators.

    -- Audio sample constants.
    constant SAMPLE_SIZE            : integer := 16;
    constant SAMPLE_MAX             : integer := 2**(SAMPLE_SIZE - 1) - 1;
    constant SAMPLE_MIN             : integer := -2**(SAMPLE_SIZE - 1);
    constant SAMPLE_RATE            : integer := 48_000;

    -- Constants related to wavetables.
    constant WAVE_SIZE_LOG2         : integer := 11;
    constant WAVE_SIZE              : integer := 2**WAVE_SIZE_LOG2; -- Number of samples per wave table.
    constant WAVE_MAX_FRAMES_LOG2   : integer := 8;
    constant WAVE_MAX_FRAMES_LOG2_LOG2 : integer := integer(ceil(log2(real(WAVE_MAX_FRAMES_LOG2)))); -- Needed for register width.
    constant WAVE_MAX_FRAMES        : integer := 2**WAVE_MAX_FRAMES_LOG2;

    -- Constants relating to complete mipmap table of a single frame.
    constant MIPMAP_LEVELS          : integer := 10; -- 1 per octave for octaves 0 - 9. This covers the entire midi range except octave -1 which is inaudible.
    constant MIPMAP_L0_SIZE_LOG2    : integer := 11;
    constant MIPMAP_L0_SIZE         : integer := 2**MIPMAP_L0_SIZE_LOG2;
    constant MIPMAP_TABLE_SIZE_LOG2 : integer := MIPMAP_L0_SIZE_LOG2 + 1;
    constant MIPMAP_TABLE_SIZE      : integer := 2**MIPMAP_TABLE_SIZE_LOG2;

    -- Oscillator constants.
    constant OSC_SAMPLE_FRAC        : integer := 8; -- Fractional bits used for sample interpolation
    constant OSC_COEFF_FRAC         : integer := 8; -- Fractional bits used for coefficient interpolation.

    -- Oscillator polyphase interpolation filter coefficient.
    constant POLY_COEFF_SIZE        : integer := 16;
    constant POLY_M_LOG2            : integer := 7;
    constant POLY_M                 : integer := 2**POLY_M_LOG2;
    constant POLY_N_LOG2            : integer := 4;
    constant POLY_N                 : integer := 2**POLY_N_LOG2;

    -- Constants relating to control values such as LFO's or evelopes.
    constant CTRL_SIZE              : integer := 16;

    -- LFO contants.
    constant LFO_PHASE_SIZE         : integer := 48; -- Phase accumulator bit width.
    constant LFO_PHASE_INT          : integer := 3; -- Integer bit width of phase.
    constant LFO_PHASE_FRAC         : integer := LFO_PHASE_SIZE - LFO_PHASE_INT; -- Fractional bit width of phase.
    constant LFO_MIN_RATE           : real := 0.125;
    constant LFO_MAX_RATE           : real := 256.0;

    -- Some of these constants are to big to pre calculate using 32 bit integers.
    constant LFO_MIN_VELOCITY       : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"aec33e1", LFO_PHASE_SIZE); -- 0.125 Hz
    -- constant LFO_MAX_VELOCITY       : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"57619f0fb", LFO_PHASE_SIZE); -- 16 Hz
    constant LFO_MAX_VELOCITY       : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"57619f0fb3", LFO_PHASE_SIZE); -- 256 Hz:
    -- constant LFO_VELOCITY_STEP      : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"56b2d", LFO_PHASE_SIZE);-- Velocity increase for every bit of the LFO input control value.
    constant LFO_VELOCITY_STEP      : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"5756b2", LFO_PHASE_SIZE);-- Velocity increase for every bit of the LFO input control value.

    -- Oscillator downsample halfband filter constants.
    -- The odd phase (m = 1) is all zeroes except c(0) = 1.
    -- The even phase is symmetric so only half of the coefficients for m = 0 are stored.
    -- The coeffients are reversed in time to allow easy convolution.
    constant HALFBAND_COEFF_SIZE    : integer := 16;
    constant HALFBAND_N             : integer := 60; -- Length of one phase (half of the total length).
    -- ADC constants.
    constant ADC_SAMPLE_SIZE        : integer := 12;
    constant ADC_FILTER_FRAC        : integer := 8;

    -- Address constants.
    constant ADDR_DEPTH_LOG2        : integer := 32;
    -- constant ADDR_DEPTH             : integer := 2**ADDR_DEPTH_LOG2;

    -- SDRAM constants.
    constant SDRAM_WIDTH            : integer := 16;
    constant SDRAM_DEPTH_LOG2       : integer := 23;
    constant SDRAM_DEPTH            : integer := 2**SDRAM_DEPTH_LOG2;
    constant SDRAM_MAX_BURST_LOG2   : integer := 7;
    constant SDRAM_MAX_BURST        : integer := 2**SDRAM_MAX_BURST_LOG2;

    -- Register file constants.
    constant REGISTER_WIDTH         : integer := 16;

    constant REG_RESET              : unsigned := x"0000000"; -- wo 1 bit  | Soft reset.
    constant REG_FAULT              : unsigned := x"0000001"; -- rw 16 bit | Fault flags.
    constant REG_LED                : unsigned := x"0000002"; -- rw 1 bit  | On-board led register.

    constant REG_DBG_UART_COUNT     : unsigned := x"0000100"; -- ro 16 bit | UART burst read byte count.
    constant REG_DBG_UART_FIFO      : unsigned := x"0000101"; -- ro 16 bit | SDRAM to UART fifo count.
    constant REG_DBG_UART_STATE     : unsigned := x"0000102"; -- ro 16 bit | UART packet engine state.

    constant REG_TABLE_BASE_L       : unsigned := x"0000200"; -- rw 16 bit | Bit 15 downto 0 of the wavetable base SDRAM address.
    constant REG_TABLE_BASE_H       : unsigned := x"0000201"; -- rw 7 bit  | Bit 22 downto 16 of the wavetable base SDRAM address.
    constant REG_TABLE_FRAMES       : unsigned := x"0000202"; -- rw 4 bit  | Log2 of the number of frames in the wavetable. Cannot be > WAVE_MAX_FRAMES_LOG2.
    constant REG_TABLE_NEW          : unsigned := x"0000203"; -- wo 1 bit  | Writing to this register triggers initialization of the wavetable BRAMS.

    constant REG_FRAME_INDEX        : unsigned := x"0000300"; -- ro 16 bit | UART burst read byte count.
    constant REG_FRAME_POSITION     : unsigned := x"0000301"; -- ro 16 bit | SDRAM to UART fifo count.
    constant REG_FRAME_BANK         : unsigned := x"0000302"; -- ro 16 bit | UART packet engine state. 

    constant REG_POTENTIOMETER      : unsigned := x"0000400"; -- ro 12 bit | potentiometer value. 

    constant REG_LFO_VELOCITY       : unsigned := x"0000500"; -- rw 16 bit | LFO velocity control value. 

    constant REG_FILTER_CUTOFF      : unsigned := x"0000600"; -- rw 16 bit | Filter cutoff control value. 
    constant REG_FILTER_RESONANCE   : unsigned := x"0000601"; -- rw 16 bit | Filter resonance control value. 

    -- fault register (sticky-)bit indices.
    constant FAULT_UART_TIMEOUT     : integer := 0; -- UART packet engine timout.
    constant FAULT_REG_ADDRESS      : integer := 1; -- Register address undefined.
    constant FAULT_BURST_ALIGN      : integer := 2; -- Burst address is not page aligned (128 words).

    -- Audio sample types.
    subtype t_mono_sample is signed(SAMPLE_SIZE - 1 downto 0);
    type t_stereo_sample is array (0 to 1) of t_mono_sample;
    type t_mono_sample_array is array (natural range <>) of t_mono_sample;
    type t_stereo_sample_array is array (natural range <>) of t_stereo_sample;

    subtype t_ctrl_value is unsigned(CTRL_SIZE - 1 downto 0);
    type t_ctrl_value_array is array (natural range <>) of t_ctrl_value;

    -- Address in the oscillator coefficient memory. It consists of two memories that each hold
    -- either the even or odd coefficients.
    subtype t_coeff_address is unsigned(POLY_M_LOG2 * POLY_N_LOG2 - 2 downto 0);

    -- Mipmap table types.
    subtype t_mipmap_level is integer range 0 to MIPMAP_LEVELS - 1;
    type t_mipmap_level_array is array (natural range <>) of t_mipmap_level;
    subtype t_mipmap_address is unsigned(MIPMAP_TABLE_SIZE_LOG2 - 1 downto 0);
    type t_mipmap_address_array is array (natural range <>) of t_mipmap_address;

    -- Oscillator types.
    subtype t_osc_phase is -- Wavetable phase (index in wavetable + fractional part).
        unsigned(MIPMAP_L0_SIZE_LOG2 + POLY_M_LOG2 + OSC_COEFF_FRAC - 1 downto 0); -- Fractional part of phase (m + fractional part).
    subtype t_osc_phase_frac is unsigned(POLY_M_LOG2 + OSC_COEFF_FRAC - 1 downto 0); -- Fractional part of m (phase interpolation position).
    subtype t_osc_phase_position is unsigned(OSC_COEFF_FRAC - 1 downto 0);

    type t_osc_phase_array is array (natural range <>) of t_osc_phase;
    type t_osc_phase_frac_array is array (natural range <>) of t_osc_phase_frac;
    type t_osc_phase_position_array is array (natural range <>) of t_osc_phase_position;

    -- Downsample filter types.
    type t_halfband_coeff_array is array (0 to HALFBAND_N / 2 - 1) -- Half the odd phase coefficients (they are symmetric).
        of std_logic_vector(HALFBAND_COEFF_SIZE - 1 downto 0);

    subtype t_osc_position is unsigned(OSC_SAMPLE_FRAC - 1 downto 0); -- Oscillator frame position (only fractional).
    type t_osc_position_array is array (natural range <>) of t_osc_position;

    -- Register file outputs.
    type t_config is record
        led                     : std_logic;
        lfo_velocity            : t_ctrl_value;
        filter_cutoff           : t_ctrl_value;
        filter_resonance        : t_ctrl_value;
        dma_new_table           : std_logic; -- Pulse indicating a new table should be loaded.
        dma_base_address        : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0); -- SDRAM base address of current mipmap table.
        dma_n_frames_log2       : integer range 0 to WAVE_MAX_FRAMES_LOG2; -- Log2 of number of frames in the wavetable - 1.
    end record;

    -- Register file inputs.
    type t_status is record
        pot_value               : std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
        frame_index             : integer range 0 to WAVE_MAX_FRAMES - 1;
        frame_position          : t_osc_position;
        frame_bank              : integer range 0 to 3;
        uart_timeout            : std_logic;
        uart_state              : integer;
        uart_count              : integer;
        uart_fifo_count         : integer;
    end record;

    type t_osc_input is record
        enable                  : std_logic; -- Voice enable (outputs zero when not enabled).
        velocity                : t_osc_phase; -- Table velocity.
        position                : t_osc_position; -- Frame position.
    end record;

    type t_addrgen2table is record
        enable                  : std_logic; -- Oscillator enable (outputs zero when not enabled).
        mipmap_level            : t_mipmap_level; -- Active mipmap level for each oscillator.
        mipmap_address          : t_mipmap_address_array(0 to 1); -- Start mipmap address of input samples.
        phase                   : t_osc_phase_array(0 to 1); -- Oscillator phase.
    end record;

    type t_ctrl2dma is record
        start                   : std_logic; -- Start DMA of frame.
        address                 : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0); -- Base address of frame (source).
        index                   : integer range 0 to 3; -- Table address (destination).
    end record;

    type t_dma2ctrl is record
        busy                    : std_logic;
    end record;


    type t_dma2table is record
        buffer_index            : integer range 0 to 3; -- Lower table buffer index.
        wave_mem_wea            : std_logic_vector(0 downto 0);
        wave_mem_addra          : std_logic_vector(MIPMAP_TABLE_SIZE_LOG2 + 1 downto 0);
        wave_mem_dina           : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
    end record;

    type t_sdram_input is record
        read_enable             : std_logic;
        write_enable            : std_logic;
        burst_length            : integer range 1 to SDRAM_DEPTH;
        address                 : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        write_data              : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    end record;

    type t_sdram_output is record
        ack                     : std_logic; -- Signal the read- or write-enable has been seen.
        read_valid              : std_logic; -- Signal valid read word.
        write_req               : std_logic; -- Request next write word.
        done                    : std_logic; -- Signal end of read or write in last valid cycle.
        read_data               : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    end record;

    -- Register file interface.
    -- Does not support block reads and writes.
    type t_register_input is record
        read_enable             : std_logic;
        write_enable            : std_logic;
        address                 : unsigned(ADDR_DEPTH_LOG2 - 1 downto 0);
        write_data              : std_logic_vector(REGISTER_WIDTH - 1 downto 0);
    end record;

    type t_register_output is record
        valid                   : std_logic; -- Indicates read data is valid
        fault                   : std_logic;
        read_data               : std_logic_vector(REGISTER_WIDTH - 1 downto 0);
    end record;

    type t_osc_input_array is array (natural range <>) of t_osc_input;
    type t_sdram_input_array is array (natural range <>) of t_sdram_input;
    type t_addrgen2table_array is array (natural range <>) of t_addrgen2table;
    type t_ctrl2dma_array is array (natural range <>) of t_ctrl2dma;
    type t_dma2ctrl_array is array (natural range <>) of t_dma2ctrl;
    type t_sdram_output_array is array (natural range <>) of t_sdram_output;
    type t_dma2table_array is array (natural range <>) of t_dma2table;
    type t_register_input_array is array (natural range <>) of t_register_input;
    type t_register_output_array is array (natural range <>) of t_register_output;

    constant CONFIG_INIT : t_config := (
        led                     => '0',
        lfo_velocity            => (others => '0'),
        filter_cutoff           => (others => '0'),
        filter_resonance        => (others => '0'),
        dma_new_table           => '0',
        dma_base_address        => (others => '0'),
        dma_n_frames_log2       => 0
    );

    constant SDRAM_INPUT_INIT : t_sdram_input := (
        read_enable             => '0',
        write_enable            => '0',
        burst_length            => 1,
        address                 => (others => '0'),
        write_data              => (others => '0')
    );

    constant SDRAM_OUTPUT_INIT : t_sdram_output := (
        ack                     => '0',
        read_valid              => '0',
        write_req               => '0',
        done                    => '0',
        read_data               => (others => '0')
    );

    constant DMA2TABLE_INIT : t_dma2table := (
        buffer_index            => 0,
        wave_mem_wea            => (others => '0'),
        wave_mem_addra          => (others => '0'),
        wave_mem_dina           => (others => '0')
    );

    constant CTRL2DMA_INIT : t_ctrl2dma := (
         start                  => '0',
         address                => (others => '0'),
         index                  => 0
    );

    constant MIPMAP_THRESHOLDS : t_osc_phase_array(0 to MIPMAP_LEVELS - 2) := (
        to_unsigned(2**(t_osc_phase_frac'length), t_osc_phase'length), -- Go to next level when resample rate r < 1 (less than 1x supersampling).
        to_unsigned(2**(t_osc_phase_frac'length + 1), t_osc_phase'length),
        to_unsigned(2**(t_osc_phase_frac'length + 2), t_osc_phase'length),
        to_unsigned(2**(t_osc_phase_frac'length + 3), t_osc_phase'length),
        to_unsigned(2**(t_osc_phase_frac'length + 4), t_osc_phase'length),
        to_unsigned(2**(t_osc_phase_frac'length + 5), t_osc_phase'length),
        to_unsigned(2**(t_osc_phase_frac'length + 6), t_osc_phase'length),
        to_unsigned(2**(t_osc_phase_frac'length + 7), t_osc_phase'length),
        to_unsigned(2**(t_osc_phase_frac'length + 8), t_osc_phase'length)
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

    -- Highest mipmap address for each mipmap level.
    constant MIPMAP_LEVEL_LIMITS : t_mipmap_address_array(0 to MIPMAP_LEVELS - 1) := (
        x"7FF",
        x"BFF",
        x"DFF",
        x"EFF",
        x"F7F",
        x"FBF",
        x"FDF",
        x"FEF",
        x"FF7",
        x"FFF"
    );

    -- Table of oscillator velocities for each note of the highest octave supported (9).
    -- Shifting these to the right gives the velocity for lower octaves.
    -- Note that the wavetable runs at 2x the sample rate before it downsamples.
    constant BASE_OCT_VELOCITIES : t_osc_phase_array(0 to 11) := (
         to_unsigned(Integer(2**t_osc_phase'length * 8372.16 / Real(2 * SAMPLE_RATE)), t_osc_phase'length),  -- C
         to_unsigned(Integer(2**t_osc_phase'length * 8869.76 / Real(2 * SAMPLE_RATE)), t_osc_phase'length),  -- C#
         to_unsigned(Integer(2**t_osc_phase'length * 9397.12 / Real(2 * SAMPLE_RATE)), t_osc_phase'length),  -- D
         to_unsigned(Integer(2**t_osc_phase'length * 9956.16 / Real(2 * SAMPLE_RATE)), t_osc_phase'length),  -- D#
         to_unsigned(Integer(2**t_osc_phase'length * 10548.16 / Real(2 * SAMPLE_RATE)), t_osc_phase'length), -- E
         to_unsigned(Integer(2**t_osc_phase'length * 11175.36 / Real(2 * SAMPLE_RATE)), t_osc_phase'length), -- F
         to_unsigned(Integer(2**t_osc_phase'length * 11839.68 / Real(2 * SAMPLE_RATE)), t_osc_phase'length), -- F#
         to_unsigned(Integer(2**t_osc_phase'length * 12544.00 / Real(2 * SAMPLE_RATE)), t_osc_phase'length), -- G
         to_unsigned(Integer(2**t_osc_phase'length * 13289.60 / Real(2 * SAMPLE_RATE)), t_osc_phase'length), -- G#
         to_unsigned(Integer(2**t_osc_phase'length * 14080.00 / Real(2 * SAMPLE_RATE)), t_osc_phase'length), -- A
         to_unsigned(Integer(2**t_osc_phase'length * 14917.12 / Real(2 * SAMPLE_RATE)), t_osc_phase'length), -- A#
         to_unsigned(Integer(2**t_osc_phase'length * 15804.16 / Real(2 * SAMPLE_RATE)), t_osc_phase'length)  -- B
    );

    constant HALFBAND_COEFFICIENTS : t_halfband_coeff_array := (
        x"FFFC", x"0003", x"FFFB", x"0009", x"FFF2", x"0014", x"FFE4", x"0027",
        x"FFCB", x"0046", x"FFA5", x"0075", x"FF6C", x"00B9", x"FF1A", x"011C",
        x"FEA5", x"01A6", x"FE01", x"026A", x"FD16", x"0385", x"FBB9", x"053E",
        x"F97B", x"0850", x"F4F2", x"0FE0", x"E518", x"5166"
    );

    function GET_INPUT_FILE_PATH return string;

end package;

package body wave_array_pkg is

    function GET_INPUT_FILE_PATH return string is
    begin
        if SIMULATION then 
            return SIM_FILE_PATH;
        else 
            return SYNTH_FILE_PATH;
        end if;
    end;

end package body wave_array_pkg;