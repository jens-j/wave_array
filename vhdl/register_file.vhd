library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity register_file is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic;
        status                  : in  t_status;
        config                  : out t_config;
        polyphony               : out integer range 1 to POLYPHONY_MAX;
        active_voices           : out integer range 1 to POLYPHONY_MAX;
        active_oscillators      : out integer range 1 to N_VOICES;
        register_input          : in  t_register_input;
        register_output         : out t_register_output;
        software_reset          : out std_logic
    );
end entity;

architecture arch of register_file is

    constant ACTIVE_OSCILLATORS_DEFAULT     : t_active_oscillators_array := CALCULATE_ACTIVE_OSCILLATORS('0');
    constant ACTIVE_OSCILLATORS_BINAURAL    : t_active_oscillators_array := CALCULATE_ACTIVE_OSCILLATORS('1');
    constant POLYPHONY_DEFAULT              : t_polyphony_array := calculate_polyphony('0');
    constant POLYPHONY_BINAURAL             : t_polyphony_array := calculate_polyphony('1');

    type t_packet_engine_reg is record
        software_reset          : std_logic;
        config                  : t_config;
        config_buffer           : t_config;
        register_output         : t_register_output;
        faults                  : std_logic_vector(15 downto 0);
        polyphony               : integer range 1 to POLYPHONY_MAX;
        active_voices           : integer range 1 to POLYPHONY_MAX;
        active_oscillators      : integer range 1 to N_VOICES;
        polyphony_buffer        : integer range 1 to POLYPHONY_MAX;
        active_voices_buffer    : integer range 1 to POLYPHONY_MAX;
        active_oscillators_buffer : integer range 1 to N_VOICES;
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        software_reset          => '0',
        config                  => INITIALIZE_CONFIG,
        config_buffer           => INITIALIZE_CONFIG,
        register_output         => REGISTER_OUTPUT_INIT,
        faults                  => (others => '0'),
        polyphony               => 1,
        active_voices           => 1,
        active_oscillators      => 1,
        polyphony_buffer        => 1,
        active_voices_buffer    => 1,
        active_oscillators_buffer => 1
    );

    signal r, r_in              : t_packet_engine_reg;

begin

    register_output             <= r.register_output;
    config                      <= r.config;
    software_reset              <= r.software_reset;

    comb_process : process (r, register_input, status, next_sample)
        variable v_rel_address : unsigned(ADDR_DEPTH_LOG2 - 1 downto 0);
        variable v_mod_dest : integer range 0 to MODD_LEN - 1;
        variable v_mod_source : integer range 0 to MODS_LEN - 1;
        variable v_modd_destination : integer range 0 to MODD_LEN - 1;
        variable v_modd_voice : integer range 0 to POLYPHONY_MAX - 1;
        variable v_table_index : integer range 0 to N_TABLES - 1;
        variable v_lfo_index : integer range 0 to LFO_N - 1;
        variable v_env_index : integer range 0 to ENV_N - 1;
        variable v_sh_index : integer range 0 to SAMPLE_HOLD_N - 1;
        variable v_table_mix_index : integer range 0 to N_TABLES;
        variable v_voice_index : integer range 0 to POLYPHONY_MAX - 1;
        variable v_unison_n : integer range 1 to UNISON_MAX;
    begin

        r_in <= r;
        r_in.software_reset <= '0';
        r_in.register_output <= ('0', '0', (others => '0'));

        polyphony <= r.polyphony;
        active_voices <= r.active_voices;
        active_oscillators <= r.active_oscillators; 

        -- Clear new_table output after one cycle.
        for i in 0 to N_TABLES - 1 loop 
            r_in.config.frame_dma_input(i).new_table <= '0'; 
        end loop;

        -- Clear flash dma triggers after one cycle. 
        r_in.config.flash_dma_input.start_flash_to_sdram <= '0';
        r_in.config.flash_dma_input.start_sdram_to_flash <= '0';

        -- Update config on next_sample pulse. 
        if next_sample = '1' then 

            r_in.config <= r.config_buffer;
            r_in.polyphony <= r.polyphony_buffer;
            r_in.active_voices <= r.active_voices_buffer;
            r_in.active_oscillators <= r.active_oscillators_buffer;

            -- Reset new_table triggers.
            for i in 0 to N_TABLES - 1 loop 
                r_in.config_buffer.frame_dma_input(i).new_table <= '0'; 
            end loop;

            -- Reset LFO reset triggers.
            for i in 0 to LFO_N - 1 loop
                r_in.config_buffer.lfo_input(i).reset <= '0';
            end loop;

            -- Reset DMA triggers.
            r_in.config_buffer.flash_dma_input.start_flash_to_sdram <= '0';
            r_in.config_buffer.flash_dma_input.start_sdram_to_flash <= '0';
        end if;

        -- Lookup derived parameters based on unison setting.
        -- Use the config_buffer to ensure the config and status record update simultaneously.
        if r.config_buffer.binaural_enable = '1' then 
            r_in.polyphony_buffer <= POLYPHONY_BINAURAL(r.config_buffer.unison_n);
            r_in.active_voices_buffer <= 2 * POLYPHONY_BINAURAL(r.config_buffer.unison_n);
            r_in.active_oscillators_buffer <= ACTIVE_OSCILLATORS_BINAURAL(r.config_buffer.unison_n);
        else 
            r_in.polyphony_buffer <= POLYPHONY_DEFAULT(r.config_buffer.unison_n);
            r_in.active_voices_buffer <= POLYPHONY_DEFAULT(r.config_buffer.unison_n);
            r_in.active_oscillators_buffer <= ACTIVE_OSCILLATORS_DEFAULT(r.config_buffer.unison_n);
        end if;

        -- Handle register read.
        if register_input.read_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_LED then
                r_in.register_output.read_data(0) <= r.config.led;

            elsif register_input.address = REG_FAULT then
                r_in.register_output.read_data <= r.faults;
            
            elsif register_input.address = REG_UNISON_MAX then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(UNISON_MAX, REGISTER_WIDTH));

            elsif register_input.address = REG_ENVELOPE_N then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(ENV_N, REGISTER_WIDTH));

            elsif register_input.address = REG_LFO_N then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(LFO_N, REGISTER_WIDTH));

            elsif register_input.address = REG_MIDI_CHANNEL then
                r_in.register_output.read_data(3 downto 0) <= std_logic_vector(to_unsigned(r.config.midi_channel, 4));

            elsif register_input.address = REG_DBG_WAVE_TIMER then
                r_in.register_output.read_data <= status.debug_wave_timer; 

            elsif register_input.address = REG_DBG_WAVE_FIFO then
                r_in.register_output.read_data(11 downto 0) <= 
                    std_logic_vector(to_unsigned(status.debug_wave_fifo_count, 12)); 

            elsif register_input.address = REG_DBG_WAVE_FLAGS then
                r_in.register_output.read_data(5 downto 0) <= status.debug_wave_flags; 

            elsif register_input.address = REG_DBG_UART_FLAGS then
                r_in.register_output.read_data(3 downto 0) <= status.debug_uart_flags; 

            elsif register_input.address = REG_HK_ENABLE then
                r_in.register_output.read_data(0) <= r.config.hk_enable;

            elsif register_input.address = REG_HK_PERIOD then
                r_in.register_output.read_data <= std_logic_vector(r.config.hk_period);

            elsif register_input.address = REG_WAVE_ENABLE then
                r_in.register_output.read_data(0) <= r.config.wave_enable;

            elsif register_input.address = REG_WAVE_PERIOD then
                r_in.register_output.read_data <= std_logic_vector(r.config.wave_period);

            elsif register_input.address = REG_BINAURAL then
                r_in.register_output.read_data(0) <= r.config.binaural_enable;

            elsif register_input.address = REG_UNISON_N then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(r.config.unison_n - 1, REGISTER_WIDTH));

            elsif register_input.address = REG_UNISON_SPREAD then
                r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_UNISON));

            elsif register_input.address = REG_NOISE_SELECT then
                r_in.register_output.read_data(0) <= r.config.noise_select;

            elsif register_input.address = REG_VOICES then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(POLYPHONY_MAX, REGISTER_WIDTH));

            elsif register_input.address = REG_FILTER_CUTOFF then
                r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_FILTER_CUTOFF));

            elsif register_input.address = REG_FILTER_RESONANCE then
                r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_FILTER_RESONANCE));
            
            elsif register_input.address = REG_FILTER_SELECT then
                r_in.register_output.read_data(2 downto 0) <= std_logic_vector(to_unsigned(r.config.filter_select, 3));

            elsif register_input.address = REG_DMA_BUSY then
                r_in.register_output.read_data(0) <= status.flash_dma_busy;

            elsif register_input.address = REG_DMA_FLASH_ADDR_LO then
                r_in.register_output.read_data <= std_logic_vector(r.config.flash_dma_input.sdram_address(15 downto 0));

            elsif register_input.address = REG_DMA_FLASH_ADDR_HI then
                r_in.register_output.read_data(FLASH_DEPTH_LOG2 - 17 downto 0) 
                    <= std_logic_vector(r.config.flash_dma_input.sdram_address(FLASH_DEPTH_LOG2 - 1 downto 16));

            elsif register_input.address = REG_DMA_SDRAM_ADDR_LO then
                r_in.register_output.read_data <= std_logic_vector(r.config.flash_dma_input.sdram_address(15 downto 0));

            elsif register_input.address = REG_DMA_SDRAM_ADDR_HI then
                r_in.register_output.read_data(SDRAM_DEPTH_LOG2 - 17 downto 0) 
                    <= std_logic_vector(r.config.flash_dma_input.sdram_address(SDRAM_DEPTH_LOG2 - 1 downto 16));

            elsif register_input.address = REG_DMA_SECTOR_N then
                r_in.register_output.read_data(FLASH_SECTOR_N_LOG2 - 1 downto 0) 
                    <= std_logic_vector(to_unsigned(r.config.flash_dma_input.sector_n, FLASH_SECTOR_N_LOG2));

            elsif register_input.address = REG_VOLUME_CTRL then
                r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_VOLUME));

            elsif register_input.address = REG_QSPI_JEDEC_VENDOR then
                r_in.register_output.read_data(7 downto 0) <= status.qspi_jedec_vendor;

            elsif register_input.address = REG_QSPI_JEDEC_DEVICE then
                r_in.register_output.read_data <= status.qspi_jedec_device;

            elsif register_input.address = REG_QSPI_STATUS then
                r_in.register_output.read_data(7 downto 0) <= status.qspi_status;
            
            elsif register_input.address = REG_QSPI_CONFIG then
                r_in.register_output.read_data <= status.qspi_config;

            -- Read oscillator frequency mod control base value registers.
            elsif register_input.address >= REG_FREQ_CTRL_BASE 
                    and register_input.address < REG_FREQ_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address and x"0000_0FFF";

                v_voice_index := to_integer(unsigned(v_rel_address(POLYPHONY_MAX_LOG2 - 1 downto 0)));
                r_in.register_output.read_data <= std_logic_vector(
                    r.config.base_ctrl(MODD_OSC_0_FREQ + v_voice_index));

            -- Read table mixer control value registers.
            elsif register_input.address >= REG_MIX_CTRL_BASE 
                    and register_input.address < REG_MIX_CTRL_BASE + N_TABLES + 1 then

                v_rel_address := register_input.address and x"0000_0FFF";

                v_table_mix_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 downto 0)));
                r_in.register_output.read_data <= std_logic_vector(
                    r.config.base_ctrl(MODD_OSC_0_MIX + v_table_mix_index));

            -- Read frame control value registers.
            elsif register_input.address >= REG_FRAME_CTRL_BASE 
                    and register_input.address < REG_FRAME_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address and x"0000_0FFF";

                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 - 1 downto 0)));
                r_in.register_output.read_data <= std_logic_vector(
                    r.config.base_ctrl(MODD_OSC_0_FRAME + v_table_index));
               
            -- Wavetable registers.
            elsif register_input.address >= REG_TABLE_BASE 
                    and register_input.address < REG_TABLE_BASE + N_TABLES * x"10" then

                v_rel_address := register_input.address  and x"0000_0FFF";
                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 + 4 downto 4))); -- Index slice is 1 bit wider than necessary to accomodate N_TABLES_LOG2 = 0.

                case v_rel_address(3 downto 0) is 
                when REF_TABLE_ADDR_LOW =>
                    r_in.register_output.read_data <= std_logic_vector(
                        r.config.frame_dma_input(v_table_index).base_address(REGISTER_WIDTH - 1 downto 0));
                
                when REF_TABLE_ADDR_HIGH => 
                    r_in.register_output.read_data <= std_logic_vector(resize(
                        r.config.frame_dma_input(v_table_index).base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH),
                        REGISTER_WIDTH));

                when REF_TABLE_FRAMES => 
                    r_in.register_output.read_data <= std_logic_vector(
                            to_unsigned(r.config.frame_dma_input(v_table_index).frames_log2, REGISTER_WIDTH));
                
                when others => 
                    r_in.register_output.valid <= '0';
                end case;

            -- Envelope registers.
            elsif register_input.address >= REG_ENVELOPE_BASE 
                    and register_input.address < REG_ENVELOPE_BASE + ENV_N * x"10" then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_env_index := to_integer(unsigned(v_rel_address(ENV_N_LOG2 + 4 downto 4))); -- Index slice is 1 bit wider than necessary to accomodate ENV_N_LOG2 = 0.

                case v_rel_address(3 downto 0) is 
                when REG_ENVELOPE_ATTACK =>
                    r_in.register_output.read_data <= std_logic_vector(r.config.envelope_input(v_env_index).attack);
                
                when REG_ENVELOPE_DECAY => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.envelope_input(v_env_index).decay);

                when REG_ENVELOPE_SUSTAIN => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.envelope_input(v_env_index).sustain);

                when REG_ENVELOPE_RELEASE => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.envelope_input(v_env_index).release_value);

                when REG_ENVELOPE_LOOP => 
                    r_in.register_output.read_data(0) <= r.config.envelope_input(v_env_index).loop_envelope;

                when others => 
                    r_in.register_output.valid <= '0';
                end case;

            -- LFO registers.
            elsif register_input.address >= REG_LFO_BASE 
                    and register_input.address < REG_LFO_BASE + LFO_N * x"10" then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_lfo_index := to_integer(unsigned(v_rel_address(LFO_N_LOG2 + 4 downto 4))); -- Index slice is 1 bit wider than necessary to accomodate LFO_N_LOG2 = 0.

                case v_rel_address(3 downto 0) is 
                when REG_LFO_VELOCITY => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.lfo_input(v_lfo_index).velocity);

                when REG_LFO_WAVE =>
                    r_in.register_output.read_data <= 
                        std_logic_vector(to_unsigned(r.config.lfo_input(v_lfo_index).wave_select, REGISTER_WIDTH));

                when REG_LFO_TRIGGER => 
                    r_in.register_output.read_data(0) <= r.config.lfo_input(v_lfo_index).trigger;

                when REG_LFO_PHASE => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.lfo_input(v_lfo_index).phase_shift);    

                when REG_LFO_ONESHOT => 
                    r_in.register_output.read_data(0) <= r.config.lfo_input(v_lfo_index).oneshot;

                when REG_LFO_AMPLITUDE => 
                    r_in.register_output.read_data <= std_logic_vector(
                        r.config.base_ctrl(MODD_LFO_0_AMPLITUDE + v_lfo_index));

                when REG_LFO_BINAURAL => 
                    r_in.register_output.read_data(0) <= r.config.lfo_input(v_lfo_index).binaural;
                
                when others => 
                    r_in.register_output.valid <= '0';
                end case;

            -- Sample & hold registers.
            elsif register_input.address >= REG_SH_BASE 
                    and register_input.address < REG_SH_BASE + SAMPLE_HOLD_N * x"10" then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_sh_index := to_integer(unsigned(v_rel_address(SAMPLE_HOLD_N_LOG2 + 4 downto 4))); -- Index slice is 1 bit wider than necessary to accomodate SAMPLE_HOLD_N_LOG2 = 0.

                case v_rel_address(3 downto 0) is 

                when REG_SH_VELOCITY => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_SH_VELOCITY + v_sh_index));

                when REG_SH_AMPLITUDE => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_SH_AMPLITUDE + v_sh_index));

                when REG_SH_SLEW => 
                    r_in.register_output.read_data <= std_logic_vector(r.config.sample_hold_input(v_sh_index).slew_rate);

                when REG_SH_INPUT => 
                    r_in.register_output.read_data <= std_logic_vector(
                        to_unsigned(r.config.sample_hold_input(v_sh_index).input_select, REGISTER_WIDTH));

                when others => 
                    r_in.register_output.valid <= '0';
                end case;
                    
            -- Read mod mapping registers.
            elsif register_input.address >= REG_MOD_MAP_BASE 
                    and register_input.address < REG_MOD_MAP_BASE + MODD_LEN * MAX_MOD_SOURCES * 2 then

                v_rel_address := register_input.address and x"0000_0FFF";

                -- Slice source and destination indices from the address.
                v_mod_dest := to_integer(shift_right(v_rel_address, MAX_MOD_SOURCES_LOG2 + 1));
                v_mod_source := to_integer(v_rel_address(MAX_MOD_SOURCES_LOG2 downto 1));

                -- Differentiate between source_index and amount using the lsb.
                if v_rel_address(0) = '0' then 

                    r_in.register_output.read_data <= std_logic_vector(to_unsigned(
                        r.config.mod_mapping(v_mod_dest)(v_mod_source).source, REGISTER_WIDTH));
                else 
                    r_in.register_output.read_data <= std_logic_vector(
                        r.config.mod_mapping(v_mod_dest)(v_mod_source).amount);
                end if;

            -- Read mod destination control value for specific destination + voice.
            elsif register_input.address >= REG_MOD_DEST_BASE 
                    and register_input.address < REG_MOD_DEST_BASE + MODD_LEN * POLYPHONY_MAX then 

                v_modd_voice := to_integer(unsigned(register_input.address(POLYPHONY_MAX_LOG2 - 1 downto 0)));
                v_modd_destination := to_integer(unsigned(
                    register_input.address(MODD_LEN + POLYPHONY_MAX_LOG2 - 1 downto POLYPHONY_MAX_LOG2)));

                -- If POLYPHONY_MAX or MODD_LEN is not a power of two, some registers in the range are not valid.
                if v_modd_voice < POLYPHONY_MAX and v_modd_destination < MODD_LEN then 

                    r_in.register_output.read_data <= 
                        std_logic_vector(status.mod_destinations(v_modd_destination)(v_modd_voice));
                end if;

            else
                r_in.register_output.fault <= '1';
                r_in.faults(FAULT_REG_ADDRESS) <= '1';
            end if;

        -- Handle register write.
        elsif register_input.write_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_LED then
                r_in.software_reset <= '0';

            elsif register_input.address = REG_LED then
                r_in.config_buffer.led <= register_input.write_data(0);

            elsif register_input.address = REG_MIDI_CHANNEL then
                r_in.config_buffer.midi_channel <= to_integer(unsigned(register_input.write_data(3 downto 0)));

            elsif register_input.address = REG_FAULT then
                r_in.faults <= (others => '0');

            elsif register_input.address = REG_HK_ENABLE then
                r_in.config_buffer.hk_enable <= register_input.write_data(0);

            elsif register_input.address = REG_HK_PERIOD then
                r_in.config_buffer.hk_period <= unsigned(register_input.write_data);

            elsif register_input.address = REG_WAVE_ENABLE then
                r_in.config_buffer.wave_enable <= register_input.write_data(0);

            elsif register_input.address = REG_WAVE_PERIOD then
                r_in.config_buffer.wave_period <= unsigned(register_input.write_data);

            elsif register_input.address = REG_BINAURAL then
                r_in.config_buffer.binaural_enable <= register_input.write_data(0);

            elsif register_input.address = REG_UNISON_N then
                v_unison_n := minimum(UNISON_MAX, to_integer(unsigned(register_input.write_data)) + 1);
                r_in.config_buffer.unison_n <= v_unison_n;

            elsif register_input.address = REG_UNISON_SPREAD then
                r_in.config_buffer.base_ctrl(MODD_UNISON) <= signed(register_input.write_data);

            elsif register_input.address = REG_NOISE_SELECT then
                r_in.config_buffer.noise_select <= register_input.write_data(0);

            elsif register_input.address = REG_WAVE_PERIOD then
                r_in.config_buffer.binaural_enable <= register_input.write_data(0);

            elsif register_input.address = REG_FILTER_CUTOFF then
                r_in.config_buffer.base_ctrl(MODD_FILTER_CUTOFF) <= signed(register_input.write_data);

            elsif register_input.address = REG_FILTER_RESONANCE then
                r_in.config_buffer.base_ctrl(MODD_FILTER_RESONANCE) <= signed(register_input.write_data);

            elsif register_input.address = REG_FILTER_SELECT then
                if unsigned(register_input.write_data) < 4 then 
                    r_in.config_buffer.filter_select <= to_integer(unsigned(register_input.write_data));
                else 
                    r_in.config_buffer.filter_select <= 4;
                end if;

            elsif register_input.address = REG_DMA_START_S2F then
                r_in.config_buffer.flash_dma_input.start_sdram_to_flash <= register_input.write_data(0);

            elsif register_input.address = REG_DMA_START_F2S then
                r_in.config_buffer.flash_dma_input.start_flash_to_sdram <= register_input.write_data(0);

            elsif register_input.address = REG_DMA_START_S2F then
                r_in.config_buffer.flash_dma_input.start_sdram_to_flash <= register_input.write_data(0);

            elsif register_input.address = REG_DMA_FLASH_ADDR_LO then
                r_in.config_buffer.flash_dma_input.flash_address(15 downto 0) <= unsigned(register_input.write_data); 

            elsif register_input.address = REG_DMA_FLASH_ADDR_HI then
                r_in.config_buffer.flash_dma_input.flash_address(FLASH_DEPTH_LOG2 - 1 downto 16) 
                    <= unsigned(register_input.write_data(FLASH_DEPTH_LOG2 - 17 downto 0));  

            elsif register_input.address = REG_DMA_SDRAM_ADDR_LO then
                r_in.config_buffer.flash_dma_input.sdram_address(15 downto 0) <= unsigned(register_input.write_data); 

            elsif register_input.address = REG_DMA_SDRAM_ADDR_HI then
                r_in.config_buffer.flash_dma_input.sdram_address(SDRAM_DEPTH_LOG2 - 1 downto 16) 
                    <= unsigned(register_input.write_data(SDRAM_DEPTH_LOG2 - 17 downto 0));  

            elsif register_input.address = REG_DMA_SECTOR_N then
                r_in.config_buffer.flash_dma_input.sector_n 
                    <= to_integer(unsigned(register_input.write_data(FLASH_SECTOR_N_LOG2 - 1 downto 0)));
            
            -- oscillator frequency mod control base value registers.
            -- One for each wavetable.
            elsif register_input.address >= REG_FREQ_CTRL_BASE and 
                    register_input.address < REG_FREQ_CTRL_BASE + POLYPHONY_MAX then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_voice_index := to_integer(unsigned(v_rel_address(POLYPHONY_MAX_LOG2 - 1 downto 0)));
                
                r_in.config_buffer.base_ctrl(MODD_OSC_0_FREQ + v_voice_index) <= signed(register_input.write_data);

            -- Table mixer control base value registers.
            -- One for each wavetable.
            elsif register_input.address >= REG_MIX_CTRL_BASE and 
                    register_input.address < REG_MIX_CTRL_BASE + N_TABLES + 1 then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_table_mix_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 downto 0)));
                
                r_in.config_buffer.base_ctrl(MODD_OSC_0_MIX + v_table_mix_index) <= signed(register_input.write_data);

            -- Frame control base value registers.
            -- One for each wavetable.
            elsif register_input.address >= REG_FRAME_CTRL_BASE and 
                    register_input.address < REG_FRAME_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 - 1 downto 0)));
                
                r_in.config_buffer.base_ctrl(MODD_OSC_0_FRAME + v_table_index) <= signed(register_input.write_data);

            -- Wavetable registers.
            -- Each wavetable has 4 registers.
            elsif register_input.address >= REG_TABLE_BASE 
                    and register_input.address < REG_TABLE_BASE + N_TABLES * x"10" then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 + 4 downto 4)));

                case v_rel_address(3 downto 0) is 
                when REF_TABLE_ADDR_LOW =>
                    r_in.config_buffer.frame_dma_input(v_table_index).base_address(REGISTER_WIDTH - 1 downto 0) <= 
                        unsigned(register_input.write_data);
                
                when REF_TABLE_ADDR_HIGH => 
                    r_in.config_buffer.frame_dma_input(v_table_index).base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH) <= 
                        unsigned(register_input.write_data(SDRAM_DEPTH_LOG2 - REGISTER_WIDTH - 1 downto 0));

                when REF_TABLE_FRAMES => 
                    r_in.config_buffer.frame_dma_input(v_table_index).frames_log2 <= 
                        minimum(FRAMES_MAX_LOG2, to_integer(unsigned(register_input.write_data)));
                
                when REF_TABLE_UPDATE => 
                    r_in.config_buffer.frame_dma_input(v_table_index).new_table <= '1';

                when others => 
                    r_in.register_output.valid <= '0';

                end case;

            -- Envelope registers.
            -- Each wavetable has 4 registers.
            elsif register_input.address >= REG_ENVELOPE_BASE 
                    and register_input.address < REG_ENVELOPE_BASE + ENV_N * x"10" then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_env_index := to_integer(unsigned(v_rel_address(ENV_N_LOG2 + 4 downto 4)));

                case v_rel_address(3 downto 0) is 
                when REG_ENVELOPE_ATTACK =>
                    r_in.config_buffer.envelope_input(v_env_index).attack <= signed(register_input.write_data);
                
                when REG_ENVELOPE_DECAY => 
                    r_in.config_buffer.envelope_input(v_env_index).decay <= signed(register_input.write_data);

                when REG_ENVELOPE_SUSTAIN => 
                    r_in.config_buffer.envelope_input(v_env_index).sustain <= signed(register_input.write_data);

                when REG_ENVELOPE_RELEASE => 
                    r_in.config_buffer.envelope_input(v_env_index).release_value <= signed(register_input.write_data);

                when REG_ENVELOPE_LOOP => 
                    r_in.config_buffer.envelope_input(v_env_index).loop_envelope <= register_input.write_data(0);
                
                when others => 
                    r_in.register_output.valid <= '0';

                end case;

            -- LFO registers.
            -- Each wavetable has 5 registers.
            elsif register_input.address >= REG_LFO_BASE 
                    and register_input.address < REG_LFO_BASE + LFO_N * x"10" then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_lfo_index := to_integer(unsigned(v_rel_address(LFO_N_LOG2 + 4 downto 4)));

                case v_rel_address(3 downto 0) is 
                when REG_LFO_VELOCITY => 
                    r_in.config_buffer.lfo_input(v_lfo_index).velocity <= signed(register_input.write_data);

                when REG_LFO_WAVE =>
                    r_in.config_buffer.lfo_input(v_lfo_index).wave_select <= 
                        minimum(LFO_N_WAVEFORMS - 1, to_integer(unsigned(register_input.write_data)));                

                when REG_LFO_TRIGGER => 
                    r_in.config_buffer.lfo_input(v_lfo_index).trigger <= register_input.write_data(0);

                when REG_LFO_PHASE => 
                    r_in.config_buffer.lfo_input(v_lfo_index).phase_shift <= signed(register_input.write_data);

                when REG_LFO_ONESHOT => 
                    r_in.config_buffer.lfo_input(v_lfo_index).oneshot <= register_input.write_data(0);

                when REG_LFO_RESET => 
                    r_in.config_buffer.lfo_input(v_lfo_index).reset <= '1';

                when REG_LFO_AMPLITUDE => 
                    r_in.config_buffer.base_ctrl(MODD_LFO_0_AMPLITUDE + v_lfo_index) <= 
                        signed(register_input.write_data);

                when REG_LFO_BINAURAL => 
                    r_in.config_buffer.lfo_input(v_lfo_index).binaural <= register_input.write_data(0);
                
                when others => 
                    r_in.register_output.valid <= '0';
                end case;

            -- Sample and hold registers.
            elsif register_input.address >= REG_SH_BASE 
                    and register_input.address < REG_SH_BASE + SAMPLE_HOLD_N * x"10" then

                v_rel_address := register_input.address and x"0000_0FFF";
                v_sh_index := to_integer(unsigned(v_rel_address(SAMPLE_HOLD_N_LOG2 + 4 downto 4)));

                case v_rel_address(3 downto 0) is      

                when REG_SH_VELOCITY => 
                    r_in.config_buffer.base_ctrl(MODD_SH_VELOCITY + v_sh_index) <= signed(register_input.write_data);

                when REG_SH_AMPLITUDE => 
                    r_in.config_buffer.base_ctrl(MODD_SH_AMPLITUDE + v_sh_index) <= signed(register_input.write_data);

                when REG_SH_SLEW =>
                    r_in.config_buffer.sample_hold_input(v_sh_index).slew_rate <= signed(register_input.write_data);

                when REG_SH_INPUT =>
                    r_in.config_buffer.sample_hold_input(v_sh_index).input_select <= 
                        maximum(1, minimum(MODS_LEN - 1, to_integer(unsigned(register_input.write_data))));
                
                when others => 
                    r_in.register_output.valid <= '0';
                end case;

            -- Mod matrix registers. 
            -- Each mod destination holds a list length MAX_MOD_SOURCES containing a (source_index, amount) pair.
            elsif register_input.address >= REG_MOD_MAP_BASE 
                    and register_input.address < REG_MOD_MAP_BASE + MODD_LEN * MAX_MOD_SOURCES * 2 then

                v_rel_address := register_input.address and x"0000_0FFF";

                -- Slice source and destination indices from the address.
                v_mod_dest := to_integer(shift_right(v_rel_address, MAX_MOD_SOURCES_LOG2 + 1));
                v_mod_source := to_integer(v_rel_address(MAX_MOD_SOURCES_LOG2 downto 1));
                
                -- Differentiate between source_index and amount using the lsb.
                if v_rel_address(0) = '0' then 
                    r_in.config_buffer.mod_mapping(v_mod_dest)(v_mod_source).source
                        <= minimum(MODS_LEN - 1, to_integer(unsigned(register_input.write_data))); 
                else 
                    r_in.config_buffer.mod_mapping(v_mod_dest)(v_mod_source).amount <= signed(register_input.write_data); 
                end if;

            else
                r_in.register_output.fault <= '1';
                r_in.faults(FAULT_REG_ADDRESS) <= '1';
            end if;
        end if;
    end process;

    reg_process : process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= REG_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
