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

    constant N_TABLES               : positive := 2; -- Number of parallel wave tables.
    constant N_TABLES_LOG2          : natural  := integer(ceil(log2(real(N_TABLES))));
    constant N_VOICES_MAX_LOG2      : positive := 6;
    constant N_VOICES_MAX           : positive := 2**N_VOICES_MAX_LOG2; -- Max number of parallel oscillators per table.
    constant N_VOICES               : positive := 64 -- Number of parallel oscillators per table.
    --pragma synthesis_off
                                      / 8 -- Use only 8 voices in simulation to keep the wave view smaller.
    --pragma synthesis_on
    ;
    constant N_VOICES_LOG2          : natural := integer(ceil(log2(real(N_VOICES))));

    -- Max polyphony is lower than N_VOICES to avoid many fiters, envelopes and a larger mod matrix.
    -- Other voices can be used for unison. Binaural mode always halves to number of voices.
    constant POLYPHONY_MAX_LOG2     : positive := 4
    --pragma synthesis_off
                                      / 2 -- Use max 4 polyphony in simulation to accomodate for less voices.
    --pragma synthesis_on
    ;

    constant POLYPHONY_MAX          : positive := 2**POLYPHONY_MAX_LOG2;
    
    constant N_OSCILLATORS          : positive := N_TABLES * N_VOICES; -- Total number of oscillators.

    -- Audio sample constants.
    constant SAMPLE_SIZE            : integer := 16;
    constant SAMPLE_MAX             : integer := 2**(SAMPLE_SIZE - 1) - 1;
    constant SAMPLE_MIN             : integer := -2**(SAMPLE_SIZE - 1);
    constant SAMPLE_RATE            : integer := 48_000;

    constant FRAMES_MAX_LOG2        : integer := 4;
    constant FRAMES_MAX             : integer := 2**FRAMES_MAX_LOG2;

    -- Constants relating to mipmap table of a single frame.
    constant MIPMAP_LEVELS          : integer := 10; -- 1 per octave for octaves 0 - 9. This covers the entire midi range except octave -1 which is inaudible.
    constant MIPMAP_L0_SIZE_LOG2    : integer := 11;
    constant MIPMAP_L0_SIZE         : integer := 2**MIPMAP_L0_SIZE_LOG2;
    constant MIPMAP_TABLE_SIZE_LOG2 : integer := MIPMAP_L0_SIZE_LOG2 + 1;
    constant MIPMAP_TABLE_SIZE      : integer := 2**MIPMAP_TABLE_SIZE_LOG2;

    -- Constants related to complete wavetables consisting of one or multiple frames..
    constant WAVETABLE_SIZE_LOG2    : integer := MIPMAP_TABLE_SIZE_LOG2 + FRAMES_MAX_LOG2;
    constant WAVETABLE_SIZE         : integer := 2**WAVETABLE_SIZE_LOG2;

    -- Oscillator constants.
    constant OSC_SAMPLE_FRAC        : integer := 8; -- Fractional bits used for sample interpolation
    constant OSC_COEFF_FRAC         : integer := 8; -- Fractional bits used for coefficient interpolation.

    constant UNISON_MAX_LOG2        : integer := 4
    --pragma synthesis_off
                                      / 2 -- Use max unison 4 in simulation to accomodate for less voices.
    --pragma synthesis_on
    ;
    constant UNISON_MAX             : integer := 2**UNISON_MAX_LOG2;

    -- Oscillator polyphase interpolation filter coefficient.
    constant POLY_COEFF_SIZE        : integer := 16;
    constant POLY_M_LOG2            : integer := 7;
    constant POLY_M                 : integer := 2**POLY_M_LOG2;
    constant POLY_N_LOG2            : integer := 4;
    constant POLY_N                 : integer := 2**POLY_N_LOG2;

    constant OSC_PHASE_SIZE         : integer := MIPMAP_L0_SIZE_LOG2 + POLY_M_LOG2 + OSC_COEFF_FRAC; -- Fractional bits used for coefficient interpolation.

    -- Constants relating to control values such as LFO's or evelopes.
    constant CTRL_SIZE              : integer := 16;

    -- LFO contants.
    constant LFO_PHASE_SIZE         : integer := 48; -- Phase accumulator bit width.
    constant LFO_PHASE_INT          : integer := 3;  -- Integer bit width of phase.
    constant LFO_PHASE_FRAC         : integer := LFO_PHASE_SIZE - LFO_PHASE_INT; -- Fractional bit width of phase.
    constant LFO_MIN_RATE           : real := 0.125; -- in Hz.
    constant LFO_MAX_RATE           : real := 16.0;
    constant LFO_N_WAVEFORMS        : integer := 3;

    -- Some of these constants are to big to pre calculate using 32 bit integers.
    constant LFO_MIN_VELOCITY       : unsigned(CTRL_SIZE + 24 downto 0) := resize(x"aec33e1", CTRL_SIZE + 25); -- 0.125 Hz
    -- constant LFO_MAX_VELOCITY       : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"15d867c3e", LFO_PHASE_SIZE); -- 4 Hz:
    -- constant LFO_MAX_VELOCITY       : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"57619f0fb3", LFO_PHASE_SIZE); -- 256 Hz:
    -- constant LFO_VELOCITY_STEP      : unsigned(LFO_PHASE_SIZE - 1 downto 0) := resize(x"aead65", LFO_PHASE_SIZE);-- 256 Hz velocity increase for every bit of the LFO input control value.
    
    -- Velocity increase for every bit of the LFO input control value.
    -- Use a higher max LFO frequency for easy simulation.
    constant LFO_VELOCITY_STEP      : unsigned(24 downto 0) := resize( -- Max size for DSP.
                                     x"ad65b" -- 16 Hz
    --pragma synthesis_off
                                     & x"0"   -- 256 Hz
    --pragma synthesis_on
                                     , 25);

    constant ENV_MIN_ATTACK_T       : real := 1.0 / real(2**10); -- In seconds.
    constant ENV_MAX_ATTACK_T       : real := real(2**3);   
    constant ENV_MIN_DECAY_T        : real := 1.0 / real(2**10); 
    constant ENV_MAX_DECAY_T        : real := real(2**3);   
    constant ENV_MIN_RELEASE_T      : real := 1.0 / real(2**10);
    constant ENV_MAX_RELEASE_T      : real := real(2**3);   

    -- Oscillator downsample halfband filter constants.
    -- The odd phase (m = 1) is all zeroes except c(0) = 1.
    -- The even phase is symmetric so only half of the coefficients for m = 0 are stored.
    constant HALFBAND_COEFF_SIZE    : integer := 16;
    constant HALFBAND_PHASE_N_LOG2  : integer := 6;
    constant HALFBAND_PHASE_N       : integer := 2**HALFBAND_PHASE_N_LOG2; -- Length of one phase (half of the total filter length).
    constant HALFBAND_DEPTH_EVEN    : integer := N_VOICES_MAX * HALFBAND_PHASE_N;
    constant HALFBAND_DEPTH_ODD     : integer := N_VOICES_MAX * HALFBAND_PHASE_N / 2;
    constant HALFBAND_DEPTH_ODD_LOG2  : integer := integer(ceil(log2(real(HALFBAND_DEPTH_ODD))));
    constant HALFBAND_DEPTH_EVEN_LOG2 : integer := integer(ceil(log2(real(HALFBAND_DEPTH_EVEN))));

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

    -- Modulation source and destination constants.
    constant MODD_FILTER_CUTOFF     : natural := 0; 
    constant MODD_FILTER_RESONANCE  : natural := 1; 
    constant MODD_MIXER             : natural := 2;
    constant MODD_OSC_0_FRAME       : natural := 3;
    constant MODD_OSC_1_FRAME       : natural := 4;
    constant MODD_OSC_0_MIX         : natural := 5;
    constant MODD_OSC_1_MIX         : natural := 6;
    constant MODD_OSC_0_FREQ        : natural := 7;
    constant MODD_OSC_1_FREQ        : natural := 8;
    constant MODD_UNISON            : natural := 9;

    constant MODS_NONE              : natural := 0;
    constant MODS_POT               : natural := 1;
    constant MODS_ENVELOPE          : natural := 2;
    constant MODS_LFO               : natural := 3;
    constant MODS_VELOCITY          : natural := 4;

    constant MODS_LEN               : natural := 5;
    constant MODD_LEN               : natural := 10;
    constant MODS_LEN_LOG2          : natural := integer(ceil(log2(real(MODS_LEN))));
    constant MODD_LEN_LOG2          : natural := integer(ceil(log2(real(MODD_LEN))));

    -- Mod matrix constants.
    constant MAX_MOD_SOURCES_LOG2   : integer := 2; -- Maximum simulataneous mod sources for a mod destination.
    constant MAX_MOD_SOURCES        : integer := 2**MAX_MOD_SOURCES_LOG2; -- Maximum simulataneous mod sources for a mod destination.
    
    -- HK packet constants.
    constant HK_DATA_WORDS          : integer := 5 + (MODD_LEN + MODS_LEN) * POLYPHONY_MAX; -- word lenth of HK packet data in words.
    constant HK_PACKET_BYTES        : integer := 4 + 2 * HK_DATA_WORDS;                -- Byte length of entire HK packet in bytes.
    constant HK_DATA_WIDTH          : integer := 16 * HK_DATA_WORDS;                   -- Bit length of status record as vector of 16 bit words.
    constant HK_PACKET_WIDTH        : integer := 8 * HK_PACKET_BYTES;                  -- bit length of HK_DATA_WIDTH + auto offload header.

    -- Wave packet constants.
    constant WAVE_MAX_WORDS_LOG2    : integer := 11;
    constant WAVE_MAX_WORDS         : integer := 2**WAVE_MAX_WORDS_LOG2;

    -- Register addresses.
    constant REG_RESET              : unsigned := x"0000000"; -- wo 1 bit           | Software reset.
    constant REG_FAULT              : unsigned := x"0000001"; -- rw 16 bit          | Fault flags.
    constant REG_LED                : unsigned := x"0000002"; -- rw 1 bit           | On-board led register.
    constant REG_VOICES             : unsigned := x"0000003"; -- ro 16 bit unsigned | Number of voices.
    constant REG_UNISON_MAX         : unsigned := x"0000004"; -- ro 16 bit unsigned | Maximum unison amount.

    constant REG_DBG_WAVE_TIMER     : unsigned := x"0000103"; -- ro 16 bit unsigned | Wave offload timer value.
    constant REG_DBG_WAVE_FLAGS     : unsigned := x"0000104"; -- ro  6 bit          | Wave offload fifo_overflow & fifo_underflow & wave_req & wave_ready & fifo_empty & fifo_full.    
    constant REG_DBG_WAVE_FIFO      : unsigned := x"0000105"; -- ro 12 bit unsigned | Wave offload sample buffer fifo count.          
    constant REG_DBG_UART_FLAGS     : unsigned := x"0000110"; -- ro  4 bit          | s2u_fifo_full & u2s_fifo_full & hk2u_fifo_full & wave2u_fifo_full. 

    constant REG_BINAURAL           : unsigned := x"0000200"; -- rw 1 bit           | Enable binaural mode.
    constant REG_UNISON_N           : unsigned := x"0000201"; -- rw 4 bit           | Number of oscillators in unison per voices - 1 (so [1 - 16]). 
    constant REG_UNISON_SPREAD      : unsigned := x"0000202"; -- rw 16 bit          | Unison spread base control value. Maps onto 0 - 1 semitone. 
    constant REG_POLYPHONY          : unsigned := x"0000203"; -- ro 16 bit          | Available polyphony based on current unison setting.
    constant REG_ACTIVE_OSCILLATORS : unsigned := x"0000204"; -- ro 16 bit          | Total active oscillators based on current unison setting.

    constant REG_LFO_VELOCITY       : unsigned := x"0000500"; -- rw 15 bit unsigned | LFO velocity control value. 
    constant REG_LFO_WAVE           : unsigned := x"0000501"; -- rw 16 bit unsigned | Select LFO waveform. Clipped to LFO_N_WAVEFORMS - 1.
    constant REG_LFO_TRIGGER        : unsigned := x"0000502"; -- rw  1 bit          | Write '1' to enable LFO sync to voices. 
    constant REG_LFO_RESET          : unsigned := x"0000503"; -- wo  1 bit          | Write '1' reset all LFO phases.
    constant REG_FILTER_CUTOFF      : unsigned := x"0000600"; -- rw 15 bit unsigned | Filter cutoff control value. 
    constant REG_FILTER_RESONANCE   : unsigned := x"0000601"; -- rw 15 bit unsigned | Filter resonance control value. 
    constant REG_FILTER_SELECT      : unsigned := x"0000602"; -- rw 3  bit          | Filter output select. 1 = LP, 2 = HP, 3 = BP, 4 = BS, 5 = bypass.

    constant REG_ENVELOPE_ATTACK    : unsigned := x"0000700"; -- rw 15 bit unsigned | Envelope attack time control value.
    constant REG_ENVELOPE_DECAY     : unsigned := x"0000701"; -- rw 15 bit unsigned | Envelope decay time control value.
    constant REG_ENVELOPE_SUSTAIN   : unsigned := x"0000702"; -- rw 15 bit unsigned | Envelope sustain level control value.
    constant REG_ENVELOPE_RELEASE   : unsigned := x"0000703"; -- rw 15 bit unsigned | Envelope release time control value.

    constant REG_MIXER_CTRL         : unsigned := x"0000800"; -- rw 15 bit unsigned | Mixer base value value.

    constant REG_HK_ENABLE          : unsigned := x"0000900"; -- rw  1 bit          | Write '1' to enable HK.
    constant REG_HK_PERIOD          : unsigned := x"0000901"; -- rw 16 bit unsigned | HK update period in steps of 1024 cycles (~10 us).

    constant REG_WAVE_ENABLE        : unsigned := x"0000902"; -- rw  1 bit          | Write '1' to enable wave offload.
    constant REG_WAVE_PERIOD        : unsigned := x"0000903"; -- rw 16 bit unsigned | Wave offoad update period in steps of 1024 cycles (~10 us).

    -- Base addresses for stuff that has multiple similar registers.
    constant REG_MOD_MAP_BASE       : unsigned := x"0001000"; -- Mod mapping starts here. Ordered major to minor, [destination, source (address, value)]
    constant REG_MOD_DEST_BASE      : unsigned := x"0002000"; -- ro 16 bit signed   | Modulation destinations start here. Ordered major to minor, [destination, voice].
    constant REG_FRAME_CTRL_BASE    : unsigned := x"0004000"; -- rw 15 bit unsigned | Frame control base value for each wavetable.    
    constant REG_MIX_CTRL_BASE      : unsigned := x"0005000"; -- rw 15 bit unsigned | Table mixer control base value for each wavetable. 
    constant REG_FREQ_CTRL_BASE     : unsigned := x"0006000"; -- rw 16 bit signed   | Oscillator frequency mod control base value for each voice.    

    -- Wavetable registers base address. Contiguous blocks of 4 registers for each wavetable.
    constant REG_TABLE_BASE         : unsigned := x"0003000"; -- rw 16 bit unsigned | Bit 15 downto 0 of the wavetable base SDRAM address.
                                               -- x"0003XX1"; -- rw 16 bit unsigned | Bit 22 downto 16 of the wavetable base SDRAM address.
                                               -- x"0003XX2"; -- rw  4 bit unsigned | Log2 of the number of frames in the wavetable.
                                               -- x"0003XX3"; -- wo  1 bit          | Writing to this register triggers initialization of the wavetable BRAMS.
    -- fault register (sticky-)bit indices.
    constant FAULT_UART_TIMEOUT     : integer := 0; -- UART packet engine timout.
    constant FAULT_REG_ADDRESS      : integer := 1; -- Register address undefined.
    constant FAULT_BURST_ALIGN      : integer := 2; -- Burst address is not page aligned (128 words).

    -- Audio sample types.
    subtype t_mono_sample is signed(SAMPLE_SIZE - 1 downto 0);
    type t_stereo_sample is array (0 to 1) of t_mono_sample;
    type t_mono_sample_array is array (natural range <>) of t_mono_sample;
    type t_stereo_sample_array is array (natural range <>) of t_stereo_sample;

    type t_osc_sample_array is array (0 to N_TABLES - 1) of t_mono_sample_array(0 to N_VOICES - 1);

    subtype t_ctrl_value is signed(CTRL_SIZE - 1 downto 0);
    type t_ctrl_value_array is array (natural range <>) of t_ctrl_value;
    type t_ctrl_value_2d_array is array (natural range <>) of t_ctrl_value_array;

    type t_modd_array is array (0 to MODD_LEN - 1) of t_ctrl_value_array(0 to POLYPHONY_MAX - 1);
    type t_mods_array is array (0 to MODS_LEN - 1) of t_ctrl_value_array(0 to POLYPHONY_MAX - 1);

    -- 2D control array for oscillator parameters like frame position and table mixing coefficient.
    type t_osc_ctrl_array is array (0 to N_TABLES - 1) of t_ctrl_value_array(0 to POLYPHONY_MAX - 1);

    -- Address in the oscillator coefficient memory. It consists of two memories that each hold
    -- either the even or odd coefficients.
    subtype t_coeff_address is unsigned(POLY_M_LOG2 * POLY_N_LOG2 - 2 downto 0);

    -- Mipmap table types.
    subtype t_mipmap_level is integer range 0 to MIPMAP_LEVELS - 1;
    type t_mipmap_level_array is array (natural range <>) of t_mipmap_level;
    subtype t_mipmap_address is unsigned(MIPMAP_TABLE_SIZE_LOG2 - 1 downto 0);
    type t_mipmap_address_array is array (natural range <>) of t_mipmap_address;

    -- Oscillator types.
    -- Table phase consists of (table index [m]).(filter bank index).(bank interpolation position) => 11.7.8 bits.
    subtype t_osc_phase is unsigned(OSC_PHASE_SIZE - 1 downto 0);-- Wavetable phase (index in wavetable + fractional part).
    subtype t_osc_phase_frac is unsigned(POLY_M_LOG2 + OSC_COEFF_FRAC - 1 downto 0); -- Fractional part of m (phase interpolation index + position).
    subtype t_osc_phase_position is unsigned(OSC_COEFF_FRAC - 1 downto 0);

    type t_osc_phase_array is array (natural range <>) of t_osc_phase;
    type t_osc_phase_frac_array is array (natural range <>) of t_osc_phase_frac;
    type t_osc_phase_position_array is array (natural range <>) of t_osc_phase_position;

    -- Downsample filter types.
    type t_halfband_coeff_array is array (0 to HALFBAND_PHASE_N / 2 - 1) -- Half the odd phase coefficients (they are symmetric).
        of std_logic_vector(HALFBAND_COEFF_SIZE - 1 downto 0);

    subtype t_frame_position is unsigned(OSC_SAMPLE_FRAC - 1 downto 0); -- Oscillator frame position (only fractional).
    type t_frame_position_array is array (natural range <>) of t_frame_position;

    type t_gain_coeff_array is array (1 to POLYPHONY_MAX) of t_ctrl_value;
    type t_div_coeff_array is array (1 to 2 * UNISON_MAX) of t_ctrl_value;

    type t_active_oscillators_array is array (1 to UNISON_MAX) of integer range 1 to N_VOICES;

    type t_polyphony_array is array (1 to UNISON_MAX) of integer range 1 to POLYPHONY_MAX;

    -- type MOD_DEST_ENUM is (
    --     MODD_FILTER_CUTOFF,     -- 0
    --     MODD_FILTER_RESONANCE,  -- 1
    --     MODD_OSC_FRAME,         -- 2
    --     MODD_MIXER              -- 3
    --     -- MODD_OSC_FREQUENCY,     -- 3 (has no base control value but is controlled by midi)
    -- );

    -- type MOD_SOURCE_ENUM is (
    --     MODS_NONE,              -- 0
    --     MODS_POT,               -- 1
    --     MODS_ENVELOPE,          -- 2
    --     MODS_LFO                -- 3
    -- );

    -- type t_mod_source_enum_array is array (natural range <>) of MOD_SOURCE_ENUM;

    -- constant MODS_LEN           : integer := MOD_SOURCE_ENUM'pos(MOD_SOURCE_ENUM'high) + 1;
    -- constant MODD_LEN           : integer := MOD_DEST_ENUM'pos(MOD_DEST_ENUM'high) + 1;


    -- Record holding modulation mapping of all sources enabled for one destination.
    type t_mod_mapping is record 
        source                  : integer range 0 to MODS_LEN - 1;
        amount                  : t_ctrl_value;
    end record;

    type t_mod_mapping_array is array (0 to MAX_MOD_SOURCES - 1) of t_mod_mapping;
    type t_mod_mapping_2d_array is array (0 to MODD_LEN - 1) of t_mod_mapping_array;


    type t_dma_input is record 
        new_table               : std_logic;                               -- Pulse indicating a new table should be loaded.
        base_address            : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0); -- SDRAM base address of current mipmap table.
        frames_log2             : integer range 0 to FRAMES_MAX_LOG2; -- Log2 of number of frames in the wavetable - 1.
    end record;

    type t_dma_input_array is array (0 to N_TABLES - 1) of t_dma_input;

    -- Register file outputs.
    type t_config is record
        led                     : std_logic;
        base_ctrl               : t_ctrl_value_array(0 to MODD_LEN - 1); -- Base value for modulation destinations.
        mod_mapping             : t_mod_mapping_2d_array;
        hk_enable               : std_logic;
        hk_period               : unsigned(CTRL_SIZE - 1 downto 0); -- Housekeeping update period in steps of 1024 cycles (~10 ms).
        wave_enable             : std_logic;
        wave_period             : unsigned(CTRL_SIZE - 1 downto 0); -- Housekeeping update period in steps of 1024 cycles (~10 ms).
        binaural_enable         : std_logic;
        unison_n                : integer range 1 to UNISON_MAX; 
        lfo_wave_select         : integer range 0 to LFO_N_WAVEFORMS - 1;
        lfo_reset               : std_logic; -- phase reset strobe.
        filter_select           : integer range 0 to 4;
        lfo_velocity            : t_ctrl_value;
        lfo_trigger             : std_logic;
        envelope_attack         : t_ctrl_value;
        envelope_decay          : t_ctrl_value;
        envelope_sustain        : t_ctrl_value;
        envelope_release        : t_ctrl_value;
        dma_input               : t_dma_input_array;
    end record;

    -- Register file inputs.
    type t_status is record
        voice_enabled           : std_logic_vector(POLYPHONY_MAX - 1 downto 0); -- Notes actively playing.
        voice_active            : std_logic_vector(POLYPHONY_MAX - 1 downto 0); -- Envelopes active.
        polyphony               : integer range 1 to POLYPHONY_MAX; -- Available polyphony depending on the unison and binaural settings.
        active_voices           : integer range 1 to POLYPHONY_MAX; -- Voices in use. 2 * polyphony in binaural mode.
        active_oscillators      : integer range 1 to N_VOICES; -- Total active oscillators depending on the unison and binaural settings.
        mod_sources             : t_mods_array;
        mod_destinations        : t_modd_array;
        debug_wave_state        : integer;
        debug_wave_fifo_count   : integer;
        debug_wave_timer        : std_logic_vector(15 downto 0); -- Only 16 lsb.
        debug_wave_flags        : std_logic_vector(5 downto 0); -- Flags: wave_req & wave_ready & fifo_empty & fifo_full.
        debug_uart_flags        : std_logic_vector(3 downto 0); -- Fifo full flags: sdram2uart & uart2sdram & hk & wave.
    end record;

    type t_osc_input is record
        enable                  : std_logic; -- Voice enable (outputs zero when not enabled).
        velocity                : t_osc_phase; -- Table velocity.
    end record;

    type t_addrgen2table is record
        enable                  : std_logic; -- Oscillator enable (outputs zero when not enabled).
        mipmap_level            : t_mipmap_level; -- Active mipmap level for each oscillator.
        mipmap_address          : t_mipmap_address_array(0 to 1); -- Start mipmap address of input samples.
        phase                   : t_osc_phase_array(0 to 1); -- Oscillator phase.
    end record;

    type t_dma2table is record
        req                     : std_logic; -- Request transfer. Remains high until ack.
        done                    : std_logic; -- Signal last cycle of transfer.
        write_enable            : std_logic;
        write_address           : std_logic_vector(WAVETABLE_SIZE_LOG2 - 1 downto 0);
        write_data              : std_logic_vector(SAMPLE_SIZE - 1 downto 0);
        frames_log2             : integer range 0 to FRAMES_MAX_LOG2; -- Wavetable size is updated after writing a new table.
    end record;

    type t_table2dma is record 
        ack                     : std_logic; -- Acknowledge transfer.
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
    type t_sdram_output_array is array (natural range <>) of t_sdram_output;
    type t_dma2table_array is array (natural range <>) of t_dma2table;
    type t_table2dma_array is array (natural range <>) of t_table2dma;
    type t_register_input_array is array (natural range <>) of t_register_input;
    type t_register_output_array is array (natural range <>) of t_register_output;

    type t_pitched_osc_inputs is array (0 to N_TABLES - 1) of t_osc_input_array(0 to POLYPHONY_MAX - 1);
    type t_spread_osc_inputs is array (0 to N_TABLES - 1) of t_osc_input_array(0 to N_VOICES - 1);
    type t_unison_step_array is array (0 to N_TABLES - 1) of t_osc_phase_array(0 to POLYPHONY_MAX - 1);
    type t_addrgen_output_array is array (0 to N_TABLES - 1) of t_addrgen2table_array(0 to N_VOICES - 1);

    constant MOD_MAPPING_INIT : t_mod_mapping := (
        source                  => MODS_NONE,
        amount                  => (others => '0')
    );

    constant DMA_INPUT_INIT : t_dma_input := (
        new_table               => '0',             -- Pulse indicating a new table should be loaded.
        base_address            => (others => '0'), -- SDRAM base address of current mipmap table.
        frames_log2             => 0                -- Log2 of number of frames in the wavetable.
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
        req                     => '0',
        done                    => '0',
        write_enable            => '0',
        write_address           => (others => '0'),
        write_data              => (others => '0'),
        frames_log2             => 0
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
        x"5168", x"E510", x"0FED", x"F4E0", x"0866", x"F961", x"055C", x"FB98",
        x"03A9", x"FCF1", x"0290", x"FDDA", x"01CC", x"FE7F", x"0140", x"FEF7",
        x"00DA", x"FF4E", x"0090", x"FF8C", x"005C", x"FFB8", x"0038", x"FFD6",
        x"0020", x"FFE9", x"0011", x"FFF5", x"0008", x"FFFB", x"0003", x"FFFD"
    );


    function GET_INPUT_FILE_PATH return string;
    function serialize_status (status : in t_status) return std_logic_vector;
    function GENERATE_GAIN_COEFF_ARRAY return t_gain_coeff_array;
    function GENERATE_DIV_COEFF_ARRAY return t_div_coeff_array;
    function CALCULATE_POLYPHONY (binaural : in std_logic) return t_polyphony_array;
    function CALCULATE_ACTIVE_OSCILLATORS (binaural : in std_logic) return t_active_oscillators_array;
    function INITIALIZE_CONFIG return t_config;

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

    function INITIALIZE_CONFIG return t_config is
        variable mapping : t_mod_mapping_2d_array := (others => (others => MOD_MAPPING_INIT));
        variable config : t_config;
    begin

        -- Map envelope to mixer with max amount. 
        mapping(MODD_MIXER)(0) := (MODS_ENVELOPE, x"7FFF"); 

        config := (
            led                     => '0',
            base_ctrl               => (0 => x"4000",
                                        1 => x"0400",
                                        2 => x"0000",
                                        3 => x"0000",
                                        4 => x"0000",
                                        5 => x"7FFF",
                                        6 => x"7FFF",
                                        7 => x"0000",
                                        8 => x"0000",
                                        9 => x"0000"),

            mod_mapping             => mapping, 
            hk_enable               => '0',
            hk_period               => x"078F", -- 1935 ~= 20 ms => 50 Hz.
            wave_enable             => '0',
            wave_period             => x"0F1E", -- 2870 ~= 40 ms => 25 Hz.
            binaural_enable         => '0',
            unison_n                => 1,
            lfo_wave_select         => 0,
            lfo_velocity            => (others => '0'),
            lfo_trigger             => '0',
            lfo_reset               => '0',
            filter_select           => 0, -- Lowpass
            envelope_attack         => x"0010",
            envelope_decay          => x"0020",
            envelope_sustain        => x"4000",
            envelope_release        => x"0100",
            dma_input               => (others => DMA_INPUT_INIT)
        );

        return config;
    end;

    -- Serialize status record to a std_logic_vector. The debug entries are excluded.
    function serialize_status (status : in t_status) return std_logic_vector is
        variable v_ser : std_logic_vector(HK_DATA_WIDTH - 1 downto 0) := (others => '0');
        variable v_offset : integer;
        variable v_index : integer;
    begin 

        -- -- Sign extend to 16 bits if POLYPHONY_MAX < 16.
        -- if POLYPHONY_MAX < 16 then 
        --     v_ser(15 downto 0)  := (15 downto POLYPHONY_MAX => '0') & status.voice_enabled;
        --     v_ser(31 downto 16) := (15 downto POLYPHONY_MAX => '0') & status.voice_active;
        -- else 
        --     v_ser(15 downto 0)  := status.voice_enabled;
        --     v_ser(31 downto 16) := status.voice_active; 
        -- end if;

        v_ser(15 downto 0)  := std_logic_vector(resize(unsigned(status.voice_enabled), 16));
        v_ser(31 downto 16) := std_logic_vector(resize(unsigned(status.voice_active), 16));
        v_ser(47 downto 32) := std_logic_vector(to_unsigned(status.polyphony, 16));
        v_ser(63 downto 48) := std_logic_vector(to_unsigned(status.active_voices, 16));
        v_ser(79 downto 64) := std_logic_vector(to_unsigned(status.active_oscillators, 16));

        v_offset := 80;

        for source in 0 to MODS_LEN - 1 loop 
            for voice in 0 to POLYPHONY_MAX - 1 loop              
                v_ser(v_offset + 15 downto v_offset) := std_logic_vector(status.mod_sources(source)(voice));
                v_offset := v_offset + 16;
            end loop;
        end loop;

        for dest in 0 to MODD_LEN - 1 loop 
            for voice in 0 to POLYPHONY_MAX - 1 loop
                v_ser(v_offset + 15 downto v_offset) := std_logic_vector(status.mod_destinations(dest)(voice));
                v_offset := v_offset + 16;
            end loop;
        end loop;

        return v_ser;
    end;

    -- Calculate array of mixer gain normalization coefficients. These are multiplied with the mixer sum. 
    -- Since mixers don't always sum powers of two inputs, a shift is not enough for unity gain.
    function GENERATE_GAIN_COEFF_ARRAY return t_gain_coeff_array is
        variable v_coeff_array : t_gain_coeff_array;
    begin 
        for i in 1 to POLYPHONY_MAX loop 
            v_coeff_array(i) := to_signed((2**15 - 1) / i, CTRL_SIZE);
        end loop;

        return v_coeff_array;
    end;

    -- Pretty much identical to GENERATE_GAIN_COEFF_ARRAY but the lengths might change.
    function GENERATE_DIV_COEFF_ARRAY return t_div_coeff_array is
        variable v_coeff_array : t_div_coeff_array;
    begin 
        for i in 1 to 2 * UNISON_MAX loop 
            if i = 1 then 
                v_coeff_array(i) := (others => '0');
            else 
                v_coeff_array(i) := to_signed((2**15 - 1) / (i - 1), CTRL_SIZE);
            end if;
        end loop;

        return v_coeff_array;
    end;

    -- Calculate the number of actively used voices. This depends on the unison and binaural settings.
    function CALCULATE_ACTIVE_OSCILLATORS (binaural : in std_logic) return t_active_oscillators_array is
        variable v_result : t_active_oscillators_array;
        variable v_polyphony : integer range 1 to POLYPHONY_MAX;
        variable v_binaural : integer range 1 to 2;
    begin 

        v_binaural := 1 when binaural = '0' else 2;

        for i in 1 to UNISON_MAX loop 
            v_polyphony := maximum(1, minimum(POLYPHONY_MAX, N_VOICES / i) / v_binaural);
            v_result(i) := v_polyphony * i * v_binaural;
        end loop;

        return v_result;
    end;

    -- Calculate the number of actively used voices. This depends on the unison and binaural settings.
    function CALCULATE_POLYPHONY (binaural : in std_logic) return t_polyphony_array is
        variable v_result : t_polyphony_array;
        variable v_binaural : integer range 1 to 2;
    begin 

        v_binaural := 1 when binaural = '0' else 2;

        for i in 1 to UNISON_MAX loop 
            v_result(i) := maximum(1, minimum(POLYPHONY_MAX, N_VOICES / i) / v_binaural);
        end loop;

        return v_result;
    end;

end package body wave_array_pkg;