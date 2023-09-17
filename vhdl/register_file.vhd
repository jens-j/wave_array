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
        active_oscillators      : integer range 1 to N_VOICES;
        polyphony_buffer        : integer range 1 to POLYPHONY_MAX;
        active_oscillators_buffer : integer range 1 to N_VOICES;
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        software_reset          => '0',
        config                  => CONFIG_INIT,
        config_buffer           => CONFIG_INIT,
        register_output         => ('0', '0', (others => '0')),
        faults                  => (others => '0'),
        polyphony               => 1,
        active_oscillators      => 1,
        polyphony_buffer        => 1,
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
        variable v_voice_index : integer range 0 to POLYPHONY_MAX - 1;
        variable v_unison_n : integer range 1 to UNISON_MAX;
    begin

        r_in <= r;
        r_in.software_reset <= '0';
        r_in.register_output <= ('0', '0', (others => '0'));

        polyphony <= r.polyphony;
        active_oscillators <= r.active_oscillators;

        -- Clear new_table output after one cycle.
        for i in 0 to N_TABLES - 1 loop 
            r_in.config.dma_input(i).new_table <= '0'; 
        end loop;

        -- Update config on next_sample pulse. 
        if next_sample = '1' then 

            r_in.config <= r.config_buffer;
            r_in.polyphony <= r.polyphony_buffer;
            r_in.active_oscillators <= r.active_oscillators_buffer;

            -- Reset any new_table flags.
            for i in 0 to N_TABLES - 1 loop 
                r_in.config_buffer.dma_input(i).new_table <= '0'; 
            end loop;
        end if;

        -- Lookup derived parameters based on unison setting.
        -- Use the config_buffer to ensure the config and status record update simultaneously.
        if r.config.binaural_enable = '0' then 
            r_in.polyphony_buffer <= POLYPHONY_DEFAULT(r.config_buffer.unison_n);
            r_in.active_oscillators_buffer <= ACTIVE_OSCILLATORS_DEFAULT(r.config_buffer.unison_n);
        else 
            r_in.polyphony_buffer <= POLYPHONY_BINAURAL(r.config_buffer.unison_n);
            r_in.active_oscillators_buffer <= ACTIVE_OSCILLATORS_BINAURAL(r.config_buffer.unison_n);
        end if;

        -- Handle register read.
        if register_input.read_enable = '1' then

            r_in.register_output.valid <= '1';

            if register_input.address = REG_LED then
                r_in.register_output.read_data <= (1 to 15 => '0') & r.config.led;

            elsif register_input.address = REG_FAULT then
                r_in.register_output.read_data <= r.faults;

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

            elsif register_input.address = REG_VOICES then
                r_in.register_output.read_data <= std_logic_vector(to_unsigned(POLYPHONY_MAX, REGISTER_WIDTH));

            elsif register_input.address = REG_LFO_VELOCITY then
                r_in.register_output.read_data <= std_logic_vector(r.config.lfo_velocity);

            elsif register_input.address = REG_LFO_WAVE then
                r_in.register_output.read_data <= 
                    std_logic_vector(to_unsigned(r.config.lfo_wave_select, REGISTER_WIDTH));

            elsif register_input.address = REG_LFO_TRIGGER then
                r_in.register_output.read_data(0) <= r.config.lfo_trigger;

            elsif register_input.address = REG_FILTER_CUTOFF then
                r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_FILTER_CUTOFF));

            elsif register_input.address = REG_FILTER_RESONANCE then
                r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_FILTER_RESONANCE));
            
            elsif register_input.address = REG_FILTER_SELECT then
                r_in.register_output.read_data(2 downto 0) <= std_logic_vector(to_unsigned(r.config.filter_select, 3));

            elsif register_input.address = REG_ENVELOPE_ATTACK then
                r_in.register_output.read_data <= std_logic_vector(r.config.envelope_attack);

            elsif register_input.address = REG_ENVELOPE_DECAY then
                r_in.register_output.read_data <= std_logic_vector(r.config.envelope_decay);

            elsif register_input.address = REG_ENVELOPE_SUSTAIN then
                r_in.register_output.read_data <= std_logic_vector(r.config.envelope_sustain);

            elsif register_input.address = REG_ENVELOPE_RELEASE then
                r_in.register_output.read_data <= std_logic_vector(r.config.envelope_release);

            elsif register_input.address = REG_MIXER_CTRL then
                r_in.register_output.read_data <= std_logic_vector(r.config.base_ctrl(MODD_MIXER));

            -- Read oscillator frequency mod control base value registers.
            elsif register_input.address >= REG_FREQ_CTRL_BASE 
                    and register_input.address < REG_FREQ_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address - REG_FREQ_CTRL_BASE;

                v_voice_index := to_integer(unsigned(v_rel_address(POLYPHONY_MAX_LOG2 - 1 downto 0)));
                r_in.register_output.read_data <= std_logic_vector(
                    r.config.base_ctrl(MODD_OSC_0_FREQ + v_voice_index));

            -- Read table mixer control value registers.
            elsif register_input.address >= REG_MIX_CTRL_BASE 
                    and register_input.address < REG_MIX_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address - REG_MIX_CTRL_BASE;

                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 - 1 downto 0)));
                r_in.register_output.read_data <= std_logic_vector(
                    r.config.base_ctrl(MODD_OSC_0_MIX + v_table_index));

            -- Read frame control value registers.
            elsif register_input.address >= REG_FRAME_CTRL_BASE 
                    and register_input.address < REG_FRAME_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address - REG_FRAME_CTRL_BASE;

                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 - 1 downto 0)));
                r_in.register_output.read_data <= std_logic_vector(
                    r.config.base_ctrl(MODD_OSC_0_FRAME + v_table_index));
               
            -- Wavetable registers.
            -- Each wavetable has 4 registers.
            elsif register_input.address >= REG_TABLE_BASE 
                and register_input.address < REG_TABLE_BASE + N_TABLES * 4 then

                v_rel_address := register_input.address - REG_TABLE_BASE;
                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES + 1 downto 2)));

                case v_rel_address(1 downto 0) is 
                when "00" =>
                    r_in.register_output.read_data <= std_logic_vector(
                        r.config.dma_input(v_table_index).base_address(REGISTER_WIDTH - 1 downto 0));
                
                when "01" => 
                    r_in.register_output.read_data <= std_logic_vector(resize(
                        r.config.dma_input(v_table_index).base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH),
                        REGISTER_WIDTH));

                when "10" => 
                    r_in.register_output.read_data <= std_logic_vector(
                            to_unsigned(r.config.dma_input(v_table_index).frames_log2, REGISTER_WIDTH));
                
                -- New table register is not readable.
                when others => 
                    r_in.register_output.valid <= '0';
                end case;

                -- Read mod mapping registers.
                elsif register_input.address >= REG_MOD_MAP_BASE 
                        and register_input.address < REG_MOD_MAP_BASE + MODD_LEN * MAX_MOD_SOURCES * 2 then

                v_rel_address := register_input.address - REG_MOD_MAP_BASE;

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

            elsif register_input.address = REG_WAVE_PERIOD then
                r_in.config_buffer.binaural_enable <= register_input.write_data(0);

            elsif register_input.address = REG_LFO_VELOCITY then
                r_in.config_buffer.lfo_velocity <= signed(register_input.write_data);

            elsif register_input.address = REG_LFO_WAVE then
                r_in.config_buffer.lfo_wave_select <= minimum(LFO_N_WAVEFORMS - 1, 
                    to_integer(unsigned(register_input.write_data)));

            elsif register_input.address = REG_LFO_TRIGGER then
                r_in.config_buffer.lfo_trigger <= register_input.write_data(0);

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
            
            elsif register_input.address = REG_ENVELOPE_ATTACK then
                r_in.config_buffer.envelope_attack <= signed(register_input.write_data); 

            elsif register_input.address = REG_ENVELOPE_DECAY then
                r_in.config_buffer.envelope_decay <= signed(register_input.write_data); 

            elsif register_input.address = REG_ENVELOPE_SUSTAIN then
                r_in.config_buffer.envelope_sustain <= signed(register_input.write_data); 

            elsif register_input.address = REG_ENVELOPE_RELEASE then
                r_in.config_buffer.envelope_release <= signed(register_input.write_data); 

            elsif register_input.address = REG_MIXER_CTRL then
                r_in.config_buffer.base_ctrl(MODD_MIXER) <= signed(register_input.write_data); 

            
            -- oscillator frequency mod control base value registers.
            -- One for each wavetable.
            elsif register_input.address >= REG_FREQ_CTRL_BASE and 
                    register_input.address < REG_FREQ_CTRL_BASE + POLYPHONY_MAX then

                v_rel_address := register_input.address - REG_FREQ_CTRL_BASE;
                v_voice_index := to_integer(unsigned(v_rel_address(POLYPHONY_MAX_LOG2 - 1 downto 0)));
                
                r_in.config_buffer.base_ctrl(MODD_OSC_0_FREQ + v_voice_index) <= signed(register_input.write_data);

            -- Table mixer control base value registers.
            -- One for each wavetable.
            elsif register_input.address >= REG_MIX_CTRL_BASE and 
                    register_input.address < REG_MIX_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address - REG_MIX_CTRL_BASE;
                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 - 1 downto 0)));
                
                r_in.config_buffer.base_ctrl(MODD_OSC_0_MIX + v_table_index) <= signed(register_input.write_data);

            -- Frame control base value registers.
            -- One for each wavetable.
            elsif register_input.address >= REG_FRAME_CTRL_BASE and 
                    register_input.address < REG_FRAME_CTRL_BASE + N_TABLES then

                v_rel_address := register_input.address - REG_FRAME_CTRL_BASE;
                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 - 1 downto 0)));
                
                r_in.config_buffer.base_ctrl(MODD_OSC_0_FRAME + v_table_index) <= signed(register_input.write_data);

            -- Wavetable registers.
            -- Each wavetable has 4 registers.
            elsif register_input.address >= REG_TABLE_BASE 
                    and register_input.address < REG_TABLE_BASE + N_TABLES * 4 then

                v_rel_address := register_input.address - REG_TABLE_BASE;
                v_table_index := to_integer(unsigned(v_rel_address(N_TABLES_LOG2 + 1 downto 2)));

                case v_rel_address(1 downto 0) is 
                when "00" =>
                    r_in.config_buffer.dma_input(v_table_index).base_address(REGISTER_WIDTH - 1 downto 0) <= 
                        unsigned(register_input.write_data);
                
                when "01" => 
                    r_in.config_buffer.dma_input(v_table_index).base_address(SDRAM_DEPTH_LOG2 - 1 downto REGISTER_WIDTH) <= 
                        unsigned(register_input.write_data(SDRAM_DEPTH_LOG2 - REGISTER_WIDTH - 1 downto 0));

                when "10" => 
                    r_in.config_buffer.dma_input(v_table_index).frames_log2 <= 
                        minimum(FRAMES_MAX_LOG2, to_integer(unsigned(register_input.write_data)));
                
                when others => 
                    r_in.config_buffer.dma_input(v_table_index).new_table <= '1';

                end case;

            -- Mod matrix registers. 
            -- Each mod destination holds a list length MAX_MOD_SOURCES containing a (source_index, amount) pair.
            elsif register_input.address >= REG_MOD_MAP_BASE 
                    and register_input.address < REG_MOD_MAP_BASE + MODD_LEN * MAX_MOD_SOURCES * 2 then

                v_rel_address := register_input.address - REG_MOD_MAP_BASE;

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
