library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


-- This entity keeps track of the phase of multiple oscillators and generates two addresses into a
-- mipmap table for each oscillator each sample cycle. Two addresses are needed because the table
-- interpolator has to generate two samples before downsampling.
-- Besides the table addresses, this entity also outputs the fractional phase (used for polyphase
-- coefficient selection) and a mipmap level (used for address increment overflow).
-- This module performs a valid/read_enable handshake pattern with the table interpolator to output one set of data
-- at a time. The module loops over all oscillators twice in a row. 
entity table_address_generator is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample(s) trigger.
        osc_inputs              : in  t_osc_input_array(0 to N_VOICES - 1);
        table2addrgen           : in  t_table2addrgen;           
        addrgen2table           : out t_addrgen2table
    );
end entity;

architecture arch of table_address_generator is

    type t_state is (idle, select_level_0, select_level_1, calculate_address_0, calculate_address_1, increment_phase, 
        handshake);

    type t_tag_reg is record
        state                   : t_state;
        osc_counter             : integer range 0 to N_VOICES - 1;
        sample_counter          : integer range 0 to 1; -- Two samples are needed before downsampling.
        table_phases            : t_osc_phase_array(0 to N_VOICES - 1);
        local_address           : t_mipmap_address;
        valid                   : std_logic;
        mipmap_address          : t_mipmap_address;
        phase                   : t_osc_phase;
        mipmap_level            : t_mipmap_level; -- Both output samples always have the same mipmap level
        meet_threshold          : std_logic_vector(MIPMAP_LEVELS - 1 downto 1);
    end record;

    -- Generate initial phases that are shifted to accommodate binaural stuff.
    function GENERATE_PHASES return t_osc_phase_array is 
        variable phases : t_osc_phase_array(0 to N_VOICES - 1);
    begin 
        for i in 0 to N_VOICES - 1 loop 
            phases(i) := to_unsigned(2**26 / N_VOICES * i, 26);
        end loop;

        return phases;
    end function;

    function GET_MSB_ONE_INDEX (input_vector : in std_logic_vector(MIPMAP_LEVELS - 1 downto 1)) return integer is
        variable index : integer range 0 to MIPMAP_LEVELS - 1 := 0;
    begin 
        for i in 1 to MIPMAP_LEVELS - 1 loop 
            index := i when input_vector(i) = '1' else index;
        end loop;
        return index;
    end function;

    constant REG_INIT : t_tag_reg := (
        state                   => idle,
        osc_counter             => 0,
        sample_counter          => 0,
        table_phases            => GENERATE_PHASES,
        local_address           => (others => '0'),
        valid                   => '0',
        mipmap_address          => (others => '0'),
        phase                   => (others => '0'),
        mipmap_level            => 0,
        meet_threshold          => (others => '0')
    );

    signal r, r_in              : t_tag_reg;

begin

    combinatorial : process (r, next_sample, osc_inputs, table2addrgen)
    begin

        r_in <= r;
        r_in.valid <= '0';

        -- Connect outputs
        addrgen2table.valid <= r.valid;
        addrgen2table.mipmap_level <= r.mipmap_level;
        addrgen2table.mipmap_address <= r.mipmap_address;
        addrgen2table.phase <= r.phase;

        -- Wait for next cycle.
        if r.state = idle and next_sample = '1' then

            r_in.osc_counter <= 0;
            r_in.sample_counter <= 0;
            r_in.state <= select_level_0;

        -- Compare velocity with all mipmap level thresholds.
        elsif r.state = select_level_0 then
            
            for i in 1 to MIPMAP_LEVELS - 1 loop 
                r_in.meet_threshold(i) <= '1' when osc_inputs(r.osc_counter).velocity > MIPMAP_THRESHOLDS(i) else '0';
            end loop;

            r_in.state <= select_level_1;

        -- Select highest mipmap level threshold.
        elsif r.state = select_level_1 then

            r_in.mipmap_level <= GET_MSB_ONE_INDEX(r.meet_threshold);

            r_in.state <= calculate_address_0;

        -- Calculate address in mipmap table based on level.
        elsif r.state = calculate_address_0 then
            
            r_in.local_address <= "0" & shift_right(r.table_phases(r.osc_counter)
                (t_osc_phase'length - 1 downto t_osc_phase_frac'length), r.mipmap_level);

            r_in.state <= calculate_address_1;

        -- Generate the mipmap address by adding the integer part of the phase
        -- (shifted right by the mipmap level) to the mipmap table offset
        elsif r.state = calculate_address_1 then

            -- Add address to level table offset.
            r_in.mipmap_address <= MIPMAP_LEVEL_OFFSETS(r.mipmap_level) + r.local_address;

            r_in.state <= increment_phase;

        -- Increment the phase of each oscillator.
        elsif r.state = increment_phase then

            -- Buffer old phase so it can be output to the table interpolator.
            r_in.phase <= r.table_phases(r.osc_counter);

            -- Increment phase
            r_in.table_phases(r.osc_counter) <= r.table_phases(r.osc_counter) + osc_inputs(r.osc_counter).velocity;

            r_in.state <= handshake;

        -- Wait for the table interpolator to acknowledge the data. 
        elsif r.state = handshake then 

            r_in.valid <= '1';

            if table2addrgen.read_enable = '1' then 

                r_in.state <= select_level_0;

                if r.osc_counter < N_VOICES - 1 then 
                    r_in.osc_counter <= r.osc_counter + 1;
                elsif r.sample_counter = 0 then 
                    r_in.sample_counter <= 1;
                    r_in.osc_counter <= 0;
                else 
                    r_in.state <= idle;
                end if;
            end if;
        end if;

    end process;

    reg_process : process(clk)
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
