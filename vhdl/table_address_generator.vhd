library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


-- This entity keeps track of the phase of multiple oscillators and generates two addresses into a
-- mipmap table for each oscillator each cycle. Two addresses are needed because the table
-- interpolator has to generate two samples before downsampling. The address generator only supplies
-- the base addess for the first input sample. The other addresses are incremented in the interpolator.
-- Besides the table addresses, this entity also outputs the fractional phase (used for polyphase
-- coefficient selection) and a mipmap level (used for address increment overflow).
entity table_address_generator is
    generic (
        N_OSCILLATORS           : natural
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample(s) trigger.
        osc_inputs              : in  t_osc_input_array(0 to N_OSCILLATORS - 1);
        addrgen_output          : out t_addrgen_to_tableinterp_array(0 to N_OSCILLATORS - 1)
    );
end entity;

architecture arch of table_address_generator is

    type t_state is (idle, init, select_level, calculate_address_0, calculate_address_1,
        increment_phase);

    type s_tag_reg is record
        state                   : t_state;
        osc_counter             : integer range 0 to N_OSCILLATORS - 1;
        sample_counter          : integer range 0 to 1; -- Twe samples are needed before downsampling.
        level_counter           : integer range 0 to MIPMAP_LEVELS - 1;
        table_phases            : t_osc_phase_array(0 to N_OSCILLATORS - 1);
        local_address           : t_mipmap_address;
        mipmap_addresses        : t_mipmap_address_array(0 to 2 * N_OSCILLATORS - 1);
        address_buffers         : t_mipmap_address_array(0 to 2 * N_OSCILLATORS - 1);
        phases                  : t_osc_phase_array(0 to 2 * N_OSCILLATORS - 1);
        phases_buffer           : t_osc_phase_array(0 to 2 * N_OSCILLATORS - 1);
        mipmap_levels           : t_mipmap_level_array(0 to N_OSCILLATORS - 1); -- Both output samples always have the same mipmap level
        mipmap_level_buffers    : t_mipmap_level_array(0 to N_OSCILLATORS - 1);
        enable                  : std_logic_vector(N_OSCILLATORS - 1 downto 0);
        enable_buffer           : std_logic_vector(N_OSCILLATORS - 1 downto 0);
    end record;

    constant REG_INIT : s_tag_reg := (
        state                   => idle,
        osc_counter             => 0,
        sample_counter          => 0,
        level_counter           => 0,
        table_phases            => (others => (others => '0')),
        local_address           => (others => '0'),
        mipmap_addresses        => (others => (others => '0')),
        address_buffers         => (others => (others => '0')),
        phases                  => (others => (others => '0')),
        phases_buffer           => (others => (others => '0')),
        mipmap_levels           => (others => 0),
        mipmap_level_buffers    => (others => 0),
        enable                  => (others => '0'),
        enable_buffer           => (others => '0')
    );

    signal r, r_in              : s_tag_reg;

begin



    combinatorial : process (r, next_sample, osc_inputs)
        variable v_level : integer range 0 to MIPMAP_LEVELS - 1;
        variable v_index : integer range 0 to 2 * MIPMAP_LEVELS - 1;
        variable v_local_addr : t_mipmap_address;
    begin

        v_index := 2 * r.osc_counter + r.sample_counter;
        v_level := r.mipmap_level_buffers(r.osc_counter);

        r_in <= r;

        for i in 0 to N_OSCILLATORS - 1 loop
            addrgen_output(i).enable <= r.enable(i);
            addrgen_output(i).mipmap_level <= r.mipmap_levels(i);
            addrgen_output(i).mipmap_address(0) <= r.mipmap_addresses(2 * i);
            addrgen_output(i).mipmap_address(1) <= r.mipmap_addresses(2 * i + 1);
            addrgen_output(i).phase(0) <= r.phases(2 * i);
            addrgen_output(i).phase(1) <= r.phases(2 * i + 1);
        end loop;

        if r.state = idle and next_sample = '1' then

            r_in.enable <= r.enable_buffer;
            r_in.mipmap_addresses <= r.address_buffers;
            r_in.osc_counter <= 0;
            r_in.sample_counter <= 0;
            r_in.level_counter <= 0;
            r_in.address_buffers <= (others => (others => '0'));
            r_in.mipmap_levels <= r.mipmap_level_buffers;
            r_in.mipmap_level_buffers <= (others => 0);
            r_in.phases <= r.phases_buffer;
            r_in.phases_buffer <= (others => (others => '0'));
            r_in.state <= init;

        -- Regiater signals from the osc_controller.
        elsif r.state = init then

            for i in 0 to N_OSCILLATORS - 1 loop
                r_in.enable_buffer(i) <= osc_inputs(i).enable;
            end loop;

            r_in.state <= select_level;

        -- Compare the velocity with the threshold for each mipmap level.
        elsif r.state = select_level then

            -- Both samples have the same mipmap level.
            if osc_inputs(r.osc_counter).velocity > MIPMAP_THRESHOLDS(r.level_counter) then
                r_in.mipmap_level_buffers(r.osc_counter) <= r.level_counter + 1;
            end if;

            if r.level_counter < MIPMAP_LEVELS - 2 then
                r_in.level_counter <= r.level_counter + 1;
            else
                r_in.state <= calculate_address_0;
            end if;

        elsif r.state = calculate_address_0 then

            -- Create address in mipmap level table.
            v_local_addr := "0" & shift_right(r.table_phases(r.osc_counter)
                (t_osc_phase'length - 1 downto t_osc_phase_frac'length), v_level);

            -- Subtract half of the filter length to comensate for the filter delay.
            -- But underflow the address if it goes below zero.
            if v_local_addr < POLY_N / 2 - 1 then
                v_local_addr := v_local_addr + 2**(MIPMAP_L0_SIZE_LOG2 - v_level);
            end if;

            r_in.local_address <= v_local_addr - POLY_N / 2 - 1;

            r_in.state <= calculate_address_1;

        -- Generate the mipmap address by adding the integer part of the phase
        -- (shifted right by the mipmap level) to the mipmap table offset
        elsif r.state = calculate_address_1 then

            -- Add address to level table offset.
            r_in.address_buffers(v_index) <=
                MIPMAP_LEVEL_OFFSETS(v_level) + r.local_address;

            r_in.state <= increment_phase;

        -- Increment the phase of each oscillator.
        elsif r.state = increment_phase then

            -- Buffer old phase so it can be output to the table interpolator.
            r_in.phases_buffer(v_index) <= r.table_phases(r.osc_counter);

            if osc_inputs(r.osc_counter).enable = '1' then
                r_in.table_phases(r.osc_counter) <=
                    r.table_phases(r.osc_counter) + osc_inputs(r.osc_counter).velocity;
            else
                r_in.table_phases(r.osc_counter) <= (others => '0');
            end if;

            if r.sample_counter = 0 then
                r_in.sample_counter <= 1;
                r_in.state <= calculate_address_0;

            elsif r.osc_counter < N_OSCILLATORS - 1 then
                r_in.osc_counter <= r.osc_counter + 1;
                r_in.sample_counter <= 0;
                r_in.level_counter <= 0;
                r_in.state <= select_level;
            else
                r_in.state <= idle;
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
