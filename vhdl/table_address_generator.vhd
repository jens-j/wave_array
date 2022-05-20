library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


-- This entity keeps trach of the phase of multiple oscillators and generates an address into a
-- mipmap table for each oscillator each cycle.
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

    type t_state is (idle, select_level, calculate_address, increment_phase);

    type s_mag_reg is record
        state                   : t_state;
        osc_counter             : integer range 0 to N_OSCILLATORS - 1;
        level_counter           : integer range 1 to MIPMAP_LEVELS - 1;
        table_phases            : t_osc_phase_array(0 to N_OSCILLATORS - 1);
        mipmap_addresses        : t_mipmap_address_array(0 to N_OSCILLATORS - 1);
        address_buffers         : t_mipmap_address_array(0 to N_OSCILLATORS - 1);
        phases_frac             : t_osc_phase_frac_array(0 to N_OSCILLATORS - 1);
        mipmap_levels           : t_mipmap_level_array(0 to N_OSCILLATORS - 1);
        mipmap_level_buffers    : t_mipmap_level_array(0 to N_OSCILLATORS - 1);
    end record;

    constant REG_INIT : s_mag_reg := (
        state                   => idle,
        osc_counter             => 0,
        level_counter           => 1,
        table_phases            => (others => (others => '0')),
        mipmap_addresses        => (others => (others => '0')),
        address_buffers         => (others => (others => '0')),
        phases_frac             => (others => (others => '0')),
        mipmap_levels           => (others => 0),
        mipmap_level_buffers    => (others => 0)
    );

    signal r, r_in              : s_mag_reg;

begin



    combinatorial : process (r, next_sample, osc_inputs)
        variable v_level : integer range 0 to MIPMAP_LEVELS - 1;
    begin

        r_in <= r;

        for i in 0 to N_OSCILLATORS - 1 loop
            addrgen_output(i).mipmap_address <= r.mipmap_addresses(i);
            addrgen_output(i).phase_frac <= r.phases_frac(i);
            addrgen_output(i).mipmap_level <= r.mipmap_levels(i);
        end loop;

        if r.state = idle and next_sample = '1' then
            r_in.mipmap_addresses <= r.address_buffers;
            r_in.state <= select_level;
            r_in.osc_counter <= 0;
            r_in.level_counter <= MIPMAP_LEVELS - 1;
            r_in.address_buffers <= (others => (others => '0'));
            r_in.mipmap_levels <= r.mipmap_level_buffers;
            r_in.mipmap_level_buffers <= (others => 0);

            for i in 0 to N_OSCILLATORS - 1 loop
                r_in.phases_frac(i) <=
                    r.table_phases(i)(t_osc_phase_frac'length - 1 downto 0);
            end loop;

        -- Compare the velocity with the threshold for each mipmap level.
        elsif r.state = select_level then

            if osc_inputs(r.osc_counter).velocity < MIPMAP_THRESHOLDS(r.level_counter - 1) then
                r_in.mipmap_level_buffers(r.osc_counter) <= r.level_counter;
            end if;

            if r.level_counter > 1 then
                r_in.level_counter <= r.level_counter - 1;
            else
                r_in.state <= calculate_address;
            end if;

        -- Generate the mipmap address by adding the integer part of the phase
        -- (shifted right by the mipmap level) to the mipmap table offset
        elsif r.state = calculate_address then

            v_level := r.mipmap_levels(r.osc_counter);

            r_in.address_buffers(r.osc_counter) <=
                MIPMAP_LEVEL_OFFSETS(v_level)
                + ((v_level - 1 downto 0 => '0')
                & r.table_phases(r.osc_counter)
                    (t_osc_phase'length - 1 downto v_level + t_osc_phase_frac'length));


            r_in.state <= increment_phase;

        -- Increment the phase of each oscillator.
        elsif r.state = increment_phase then
            r_in.table_phases(r.osc_counter) <=
                r.table_phases(r.osc_counter) + osc_inputs(r.osc_counter).velocity;

            if r.osc_counter < N_OSCILLATORS - 1 then
                r_in.osc_counter <= r.osc_counter + 1;
                r_in.level_counter <= 1;
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
