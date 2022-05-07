library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


-- This entity keeps trach of the phase of multiple oscillators and generates an address into a
-- mipmap table for each oscillator each cycle.
entity mipmap_address_generator is
    generic (
        N_OSCILLATORS           : natural
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample(s) trigger.
        osc_inputs              : in  t_osc_input_array(0 to N_OSCILLATORS - 1);
        mipmap_addresses        : out t_mipmap_address_array(0 to N_OSCILLATORS - 1)
    );
end entity;

architecture arch of mipmap_address_generator is

    type t_state is (idle, select_level, calculate_address, increment_phase);
    type t_level_array is array 0 to N_OSCILLATORS - 1 of integer range 0 to MIPMAP_LEVELS - 1;

    type s_mag_reg is record
        state                   : t_state;
        osc_counter             : integer range 0 to N_OSCILLATORS - 1;
        level_counter           : integer range 0 to MIPMAP_LEVELS - 2;
        phases                  : t_osc_phase_array;
        levels                  : t_level_array;
        mipmap_addresses        : t_mipmap_address_array(0 to N_OSCILLATORS - 1);
        address_buffers         : t_mipmap_address_array(0 to N_OSCILLATORS - 1);
    end record;

    constant REG_INIT : s_mag_reg := (
        state                   => idle,
        osc_counter             => 0,
        level_counter           => 0,
        phases                  => (others => (others => '0')),
        levels                  => (others => 0),
        mipmap_address          => (others => (others => '0')),
        address_buffers         => (others => (others => '0'))
    );

    signal r, r_in              : s_mag_reg;

begin

    combinatorial : process (r, next_sample, osc_inputs)
        variable v_mipmap_level : integer range 0 to MIPMAP_LEVELS - 1;
    begin

        r_in <= r;

        if r.state = idle and next_sample = '1' then
            r.mipmap_addresses <= r.address_buffers;
            r_in.state <= select_level;
            r_in.osc_counter <= 0;
            r_in.level_counter <= 0;
            r_in.address_buffer <= (others => (others => '0'));

        -- Compare the velocity with the threshold for each mipmap level.
        elsif r.state = select_level then

            if osc_inputs(r.osc_counter).velocity < MIPMAP_THRESHOLDS(r.level_counter) then
                r_in.levels(r.osc_counter) <= r.level_counter;
            end if;

            if r.level_counter < MIPMAP_LEVELS - 2 then
                r_in.level_counter <= r.level_counter + 1;
            else
                r_in.state <= calculate_address;
            end if;

        -- Generate the mipmap address by adding the integer part of the phase
        -- (shifted right by the mipmap level) to the mipmap table offset
        elsif r.state = calculate_address then
            v_mipmap_level := r.levels(r.osc_counter);

            r_in.address_buffer(r.osc_counter) <=  MIPMAP_LEVEL_OFFSETS(v_mipmap_level)
                + resize(
                    r.phases(r.osc_counter(0))(t_osc_phase'length - 1 downto v_mipmap_level),
                    MIPMAP_TABLE_SIZE_LOG2 - 1);

            r_in.state <= increment_phase;

        -- Increment the phase of each oscillator.
        elsif r.state = increment_phase then
            r_in.phases(r.osc_counter) <=
                r.phases(r.osc_counter) + osc_inputs(r.osc_counter).velocity;

            if r.osc_counter < N_OSCILLATORS - 1 then
                r_in.osc_counter <= r.osc_counter + 1;
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
