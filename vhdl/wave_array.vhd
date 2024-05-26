library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library wave;
use wave.wave_array_pkg.all;

library midi;
use midi.midi_pkg.all;

library sdram;
library i2s;
library uart;
library qspi;


entity wave_array is
    generic (
        NO_MIG                  : boolean := false
    );
    port (
        EXT_CLK                 : in  std_logic;
        BTN_RESET               : in  std_logic;

        -- Board I/O.
        SWITCHES                : in  std_logic_vector(7 downto 0);
        LEDS                    : out std_logic_vector(7 downto 0);

        -- PC UART interface.
        UART_RX                 : in  std_logic;
        UART_TX                 : out std_logic;

        -- Midi slave interface.
        MIDI_RX                 : in  std_logic;

        -- I2S audio output interface.
        I2S_SCLK                : out std_logic;
        I2S_WSEL                : out std_logic;
        I2S_SDATA               : out std_logic;

        -- -- XADC analog input.
        -- XADC_3P                 : in  std_logic;
        -- XADC_3N                 : in  std_logic;

        -- FLASH interface.
        QSPI_SCK                : out std_logic;   
        QSPI_CS                 : out std_logic;
        QSPI_DQ                 : inout std_logic_vector(3 downto 0);

        -- SDRAM interface.
        DDR3_DQ                 : inout std_logic_vector(15 downto 0);
        DDR3_DQS_P              : inout std_logic_vector(1 downto 0);
        DDR3_DQS_N              : inout std_logic_vector(1 downto 0);
        DDR3_ADDR               : out   std_logic_vector(14 downto 0);
        DDR3_BA                 : out   std_logic_vector(2 downto 0);
        DDR3_RAS_N              : out   std_logic;
        DDR3_CAS_N              : out   std_logic;
        DDR3_WE_N               : out   std_logic;
        DDR3_RESET_N            : out   std_logic;
        DDR3_CK_P               : out   std_logic;
        DDR3_CK_N               : out   std_logic;
        DDR3_CKE                : out   std_logic;
        DDR3_DM                 : out   std_logic_vector(1 downto 0);
        DDR3_ODT                : out   std_logic
    );
end entity;

architecture arch of wave_array is

    -- component dff is 
    --     port (
    --         i_D                 : in  std_logic;
    --         i_clk               : in  std_logic;
    --         o_Q                 : out std_logic
    --     );
    -- end component;

    signal s_system_clk         : std_logic;
    signal s_mig_ctrl_clk       : std_logic;
    signal s_mig_ref_clk        : std_logic;
    signal s_i2s_clk            : std_logic;
    signal s_spi_clk            : std_logic;
    signal s_system_reset       : std_logic; -- Active high.
    signal s_i2s_reset          : std_logic; -- Active high.
    signal s_pll_locked         : std_logic;

    signal s_next_sample        : std_logic;
    signal s_voices             : t_voice_array(0 to POLYPHONY_MAX - 1);
    signal s_midi_status_byte   : t_byte;
    signal s_lowest_voice       : integer range 0 to POLYPHONY_MAX - 1;
    signal s_sample             : t_stereo_sample;
    signal s_display_data       : std_logic_vector(31 downto 0);

    signal s_register_input     : t_register_input;
    signal s_register_output    : t_register_output;
    signal s_status             : t_status;
    signal s_config             : t_config;
    signal s_software_reset     : std_logic;
    signal s_mig_ui_reset       : std_logic;
    signal s_mig_reset          : std_logic;

    signal s_sdram_inputs       : t_sdram_input_array(0 to 2); -- UART, flash and table DMA.
    signal s_sdram_outputs      : t_sdram_output_array(0 to 2);

    signal s_flash_input        : t_flash_input;
    signal s_flash_output       : t_flash_output;

    signal s_uart_timeout       : std_logic;
    signal s_uart_state         : integer;
    signal s_uart_count         : integer;
    signal s_uart_fifo_count    : integer;

    signal s_envelope_0_active  : std_logic_vector(POLYPHONY_MAX - 1 downto 0); 
    signal s_envelope_1_active  : std_logic_vector(POLYPHONY_MAX - 1 downto 0);
    signal s_envelope_active    : std_logic_vector(POLYPHONY_MAX - 1 downto 0);

    signal s_mod_sources        : t_mods_array;
    signal s_mod_destinations   : t_modd_array;

    signal s_hk_write_enable    : std_logic;
    signal s_hk_data            : std_logic_vector(15 downto 0);
    signal s_hk_full            : std_logic;

    signal s_wave_write_enable  : std_logic;
    signal s_wave_data          : std_logic_vector(15 downto 0);
    signal s_wave_full          : std_logic;
    signal s_wave_count         : std_logic_vector(12 downto 0);

    signal s_polyphony          : integer range 1 to POLYPHONY_MAX;
    signal s_active_voices      : integer range 1 to POLYPHONY_MAX;
    signal s_active_oscillators : integer range 1 to N_VOICES;

    signal s_debug_wave_state   : integer;
    signal s_debug_wave_fifo_count : integer range 0 to 2047;
    signal s_debug_wave_timer   : std_logic_vector(15 downto 0);
    signal s_debug_wave_flags   : std_logic_vector(5 downto 0);
    signal s_debug_uart_flags   : std_logic_vector(3 downto 0);
    signal s_debug_uart_state   : integer;
    signal s_debug_hk_fifo_count: integer;

    signal s_pitched_osc_inputs : t_pitched_osc_inputs;
    signal s_spread_osc_inputs  : t_spread_osc_inputs;
    signal s_lowest_velocity    : t_osc_phase;
    signal s_osc_samples        : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
    signal s_filter_samples     : t_mono_sample_array(0 to POLYPHONY_MAX - 1);
    signal s_addrgen_outputs    : t_addrgen_output_array;

    signal s_qspi_jedec_vendor   : std_logic_vector(7 downto 0);
    signal s_qspi_jedec_device   : std_logic_vector(15 downto 0);
    signal s_qspi_status         : std_logic_vector(7 downto 0);
    signal s_qspi_config         : std_logic_vector(15 downto 0);

    signal s_flash_dma_busy      : std_logic;
    

begin
    
    LEDS(0) <= s_config.led;
    LEDS(1) <= s_system_reset;
    LEDS(2) <= s_i2s_reset;
    gen_voice_led : for i in 0 to minimum(3, POLYPHONY_MAX - 1) generate
        LEDS(4 + i) <= s_voices(i).enable;
    end generate;

    I2S_SCLK <= s_i2s_clk;

    s_status.mod_destinations   <= s_mod_destinations;
    s_status.mod_sources        <= s_mod_sources;
    s_status.polyphony          <= s_polyphony;
    s_status.active_voices      <= s_active_voices;
    s_status.active_oscillators <= s_active_oscillators;
    s_status.debug_wave_state   <= s_debug_wave_state;
    s_status.debug_wave_fifo_count <= s_debug_wave_fifo_count;
    s_status.debug_wave_timer   <= s_debug_wave_timer;
    s_status.debug_wave_flags   <= s_debug_wave_flags;
    s_status.debug_uart_flags   <= s_debug_uart_flags;
    s_status.qspi_jedec_vendor  <= s_qspi_jedec_vendor;
    s_status.qspi_jedec_device  <= s_qspi_jedec_device;
    s_status.qspi_status        <= s_qspi_status;
    s_status.qspi_config        <= s_qspi_config;
    s_status.flash_dma_busy     <= s_flash_dma_busy;


    status_gen : for i in 0 to POLYPHONY_MAX - 1 generate 
        s_envelope_active(i)      <= s_envelope_0_active(i) or s_envelope_1_active(i);
        s_status.voice_enabled(i) <= s_voices(i).enable;
        s_status.voice_active(i)  <= s_envelope_active(i);
    end generate;

    clk_subsys : entity wave.clk_subsystem
    port map (
        reset                   => '0',             -- The reset system uses the clock.,
        ext_clk                 => EXT_CLK,         -- 100 MHz.
        mig_ctrl_clk            => s_mig_ctrl_clk,  -- 100 MHz. This goes to the MIG which outputs a ui clock that is used as system clock.
        i2s_clk                 => s_i2s_clk,       -- 1.5360175 MHz.
        spi_clk                 => s_spi_clk,       -- 100 MHz 180 degrees out of phase.
        mig_ref_clk             => s_mig_ref_clk,   -- 200 MHz.
        pll_locked              => s_pll_locked
    );

    -- NOTE: This uses the clk directly from the pll for now to avoid a deadlock. 
    reset_subsys : entity wave.reset_subsystem
    port map (
        system_clk              => s_mig_ctrl_clk,  
        i2s_clk                 => s_i2s_clk,
        BTN_RESET               => BTN_RESET,
        software_reset          => s_software_reset,
        mig_ui_reset            => s_mig_ui_reset,
        mig_reset               => s_mig_reset,
        system_reset            => s_system_reset,
        i2s_reset               => s_i2s_reset
    );

    midi_slave : entity midi.midi_slave
    port map (
        clk                     => s_system_clk,
        reset                   => s_system_reset,
        config                  => s_config,
        status                  => s_status,
        uart_rx                 => MIDI_RX,
        midi_channel            => '0' & SWITCHES(2 downto 0),
        envelope_active         => s_envelope_active,
        voices                  => s_voices,
        status_byte             => s_midi_status_byte,
        lowest_voice            => s_lowest_voice
    );

    uart_subsys : entity uart.uart_subsystem
    port map (
        clk                     => s_system_clk,
        reset                   => s_system_reset,
        register_input          => s_register_input,
        register_output         => s_register_output,
        sdram_input             => s_sdram_inputs(0),
        sdram_output            => s_sdram_outputs(0),
        hk_write_enable         => s_hk_write_enable,
        hk_data                 => s_hk_data,
        hk_full                 => s_hk_full,
        wave_write_enable       => s_wave_write_enable,
        wave_data               => s_wave_data,
        wave_full               => s_wave_full,
        wave_count              => s_wave_count,
        UART_RX                 => UART_RX,
        UART_TX                 => UART_TX,
        debug_flags             => s_debug_uart_flags,
        debug_state             => s_debug_uart_state,
        debug_hk_fifo_count     => s_debug_hk_fifo_count
    );

    hk_offload : entity wave.hk_offload
    port map (
        clk                     => s_system_clk,
        reset                   => s_system_reset,
        config                  => s_config,
        status                  => s_status,
        hk_write_enable         => s_hk_write_enable,
        hk_data                 => s_hk_data,
        hk_full                 => s_hk_full
    );

    wave_offload : entity wave.wave_offload
    port map (
        clk                     => s_system_clk,
        reset                   => s_system_reset,
        config                  => s_config,
        next_sample             => s_next_sample,
        sample_in               => s_sample(0),
        lowest_voice            => s_lowest_voice,
        lowest_velocity         => s_lowest_velocity,
        wave_write_enable       => s_wave_write_enable,
        wave_data               => s_wave_data,
        wave_full               => s_wave_full,
        wave_count              => s_wave_count,
        debug_state             => s_debug_wave_state,
        debug_fifo_count        => s_debug_wave_fifo_count,
        debug_timer             => s_debug_wave_timer,
        debug_flags             => s_debug_wave_flags
    );

    reg_file : entity wave.register_file
    port map (
        clk                     => s_system_clk,
        reset                   => s_system_reset,
        next_sample             => s_next_sample,
        register_output         => s_register_output,
        register_input          => s_register_input,
        software_reset          => s_software_reset,
        status                  => s_status,
        config                  => s_config,
        polyphony               => s_polyphony,
        active_voices           => s_active_voices,
        active_oscillators      => s_active_oscillators
    );

    synth_subsys : entity wave.synth_subsystem
    port map(
        clk                     => s_system_clk,
        reset                   => s_system_reset,
        config                  => s_config,
        status                  => s_status,
        next_sample             => s_next_sample,
        voices                  => s_voices,
        sample                  => s_sample,
        sdram_input             => s_sdram_inputs(2),
        sdram_output            => s_sdram_outputs(2),
        envelope_0_active       => s_envelope_0_active,
        envelope_1_active       => s_envelope_1_active,
        mod_sources             => s_mod_sources,
        mod_destinations        => s_mod_destinations,
        pitched_osc_inputs      => s_pitched_osc_inputs,
        spread_osc_inputs       => s_spread_osc_inputs,
        lowest_velocity         => s_lowest_velocity,
        osc_samples             => s_osc_samples,
        filter_samples          => s_filter_samples,
        addrgen_outputs         => s_addrgen_outputs
    );

    i2s_interface : entity i2s.i2s_interface
    port map (
        system_clk              => s_system_clk,
        i2s_clk                 => s_i2s_clk,
        system_reset            => s_system_reset,
        i2s_reset               => s_i2s_reset,
        sample_in               => s_sample,
        next_sample             => s_next_sample,
        sdata                   => I2S_SDATA,
        wsel                    => I2S_WSEL
    );

    flash_dma : entity wave.flash_dma 
    port map (
        clk                     => s_system_clk,
        reset                   => s_system_reset,
        config                  => s_config,
        sdram_output            => s_sdram_outputs(1),
        sdram_input             => s_sdram_inputs(1),
        flash_output            => s_flash_output,
        flash_input             => s_flash_input,
        dma_busy                => s_flash_dma_busy
    );

    -- input : entity wave.input_subsystem
    -- port map (
    --     clk                     => s_system_clk,
    --     reset                   => s_system_reset,
    --     vauxp3                  => XADC_3P,
    --     vauxn3                  => XADC_3N,
    --     average                 => SWITCHES(4 downto 3),
    --     filter_length           => SWITCHES(7 downto 5),
    --     value                   => s_pot_value
    -- );

    arbiter : entity sdram.ddr_arbiter
    generic map (
        NO_MIG                  => NO_MIG,
        N_CLIENTS               => 1 + N_TABLES
    )
    port map (
        mig_ctrl_clk            => s_mig_ctrl_clk,
        mig_ref_clk             => s_mig_ref_clk,
        mig_ui_clk              => s_system_clk,
        mig_reset               => s_mig_reset,
        mig_ui_reset            => s_mig_ui_reset,
        pll_locked              => s_pll_locked,
        sdram_inputs            => s_sdram_inputs,
        sdram_outputs           => s_sdram_outputs,
        DDR3_DQ                 => DDR3_DQ,
        DDR3_DQS_P              => DDR3_DQS_P,
        DDR3_DQS_N              => DDR3_DQS_N,
        DDR3_ADDR               => DDR3_ADDR,
        DDR3_BA                 => DDR3_BA,
        DDR3_RAS_N              => DDR3_RAS_N,
        DDR3_CAS_N              => DDR3_CAS_N,
        DDR3_WE_N               => DDR3_WE_N,
        DDR3_RESET_N            => DDR3_RESET_N,
        DDR3_CK_P               => DDR3_CK_P,
        DDR3_CK_N               => DDR3_CK_N,
        DDR3_CKE                => DDR3_CKE,
        DDR3_DM                 => DDR3_DM,
        DDR3_ODT                => DDR3_ODT
    );

    qspi_if: entity qspi.qspi_interface_micron
    port map (
        system_clk              => s_system_clk,
        spi_clk                 => s_spi_clk,
        reset                   => s_system_reset,
        flash_input             => s_flash_input,
        flash_output            => s_flash_output,
        QSPI_CS                 => QSPI_CS,
        QSPI_SCK                => QSPI_SCK,
        QSPI_DQ                 => QSPI_DQ,
        reg_jedec_vendor        => s_qspi_jedec_vendor,
        reg_jedec_device        => s_qspi_jedec_device,
        reg_status              => s_qspi_status,
        reg_config              => s_qspi_config
    );

    -- microblaze_sys : entity wave.microblaze_sys_wrapper
    -- port map(
    --     clk_100MHz              => s_system_clk,
    --     reset_rtl_0             => s_reset_al,
    --     uart_rtl_0_rxd          => UART_RX,
    --     uart_rtl_0_txd          => UART_TX,
    --     leds                    => open,
    --     switches                => SWITCHES,
    --     saw_slope               => saw_slope_s
    -- );

end architecture;
