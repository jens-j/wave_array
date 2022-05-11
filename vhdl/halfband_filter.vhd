library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity halfband_filter is
    generic (
        N_OSCILLATORS           : positive
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        next_sample             : in  std_logic; -- Next sample trigger.
        input_samples           : in  t_stereo_sample_array(0 to N_OSCILLATORS - 1);
        output_samples          : out t_mono_sample_array(0 to N_OSCILLATORS - 1)
    );
end entity;

architecture arch of halfband_filter is

    constant PIPELINE_LENGTH    : integer := 4;

    type t_state is (idle, load, running);
    type t_input_buffer is array 0 to HALFBAND_N // 2 - 1
        of t_mono_sample_array(0 to N_OSCILLATORS - 1);

    type t_mixer_reg is record
        state                   : t_state;
        pipeline_counter        : integer range 0 to HALFBAND_N // 2;
        osc_counter             : integer range 0 to N_OSCILLATORS;
        input_buffer            : t_input_buffer; -- Store HALFBAND_N odd samples for each oscillator.
        output_samples          : t_mono_sample_array;
        output_buffers          : t_mono_sample_array;
    end record;

    constant REG_INIT : t_mixer_reg := (
        state                   => idle,
        counter                 => 0,
        input_samples           => (others => (others => '0')),
    );

    signal r, r_in              : t_mixer_reg;
    signal s_macc_a             : std_logic;
    signal s_macc_a             : std_logic_vector(15 downto 0);
    signal s_macc_b             : std_logic_vector(15 downto 0);
    signal s_macc_d             : std_logic_vector(15 downto 0);
    signal s_macc_p             : std_logic_vector(47 downto 0);


begin

    macc : entity ip.halfband_macc_gen
    port map (
        CLK                     => clk,
        SEL                     => s_macc_sel,
        A                       => s_macc_a,
        B                       => s_macc_b,
        D                       => s_macc_d,
        P                       => s_macc_p
    );


    combinatorial : process (r, sample_in, next_sample)
        variable v_sample_index : integer range 0 to HALFBAND_N - 1;
    begin

        r_in <= r;

        s_macc_sel <= '0';
        s_macc_c <= (others => '0');
        s_macc_a <= (others => '0');
        s_macc_d <= (others => '0');

        if r.state = idle then
            if next_sample = '1' then

                r_in.output_samples <= r.output_buffers;

                -- Wait one cycle for the new samples to become available.
                r_in.state <= load;

        elsif r.state = load then

            -- Shift samples in the input buffer.
            for i in HALFBAND_N // 2 - 1 downto 1 loop
                for j in N_OSCILLATORS - 1 downto 0 loop
                    r_in.input_samples(i)(j) <= r.input_samples(i - 1)(j);
                end loop;
            end loop;

            -- Store the new (odd) samples.
            for j in N_OSCILLATORS - 1 downto 0 loop
                r_in.input_samples(0)(j) <= input_samples(j)(1);
            end loop;

            r_in.state <= running;

        elsif r.state = running then

            -- First cycle of new oscillator is mull while the rest is macc.
            if r.pipeline_counter = 0 then
                s_macc_sel <= '1';

                -- Input the latest even sample.
                s_macc_a <= input_samples(r.osc_counter)(0);
                s_macc_d <= (others => '0');

                -- Input coeffient = 1.
                s_macc_c <= x"7FFF";

            elsif r.osc_counter < N_OSCILLATORS then
                -- Input samples.
                v_sample_index := HALFBAND_N - r.pipeline_counter - 1;
                s_macc_a <= r.input_samples(r.pipeline_counter)(r.osc_counter);
                s_macc_d <= r.input_samples(v_sample_index)(r.osc_counter);

                -- Input coeffient.
                s_macc_c <= HALFBAND_COEFFICIENTS(r.pipeline_counter);

            end if;

            -- Store output sample.
            if r.osc_counter > 1 and r.pipeline_counter = PIPELINE_LENGTH then
                r_in.output_buffers(r.osc_counter) <= s_macc_p;
            end if;

            -- Update counters.
            if r.osc_counter = N_OSCILLATORS and r.pipeline_counter = PIPELINE_LENGTH then
                r_in.state <= idle;
            elsif r.pipeline_counter < HALFBAND_N // 2 then
                r_in.pipeline_counter <= r.pipeline_counter + 1;
            else
                r_in.pipeline_counter <= 0;
                r_in.osc_counter <= r.osc_counter + 1;
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
