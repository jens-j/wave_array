library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity input_subsystem is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        vauxp3                  : in  std_logic;
        vauxn3                  : in  std_logic;
        average                 : in  std_logic_vector(1 downto 0);
        filter_length           : in  std_logic_vector(2 downto 0); -- taps = 2**(filter_length)
        value                   : out std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0)
    );
end entity;

architecture arch of input_subsystem is

    function get_period_us return integer
    is begin
        if SIMULATION then
            return 10;
        else
            return 250000;
        end if;
    end function;

    -- Input filter types.
    subtype t_filter_coeff is std_logic_vector(ADC_FILTER_FRAC downto 0); -- Input has one extra bit to allow unsigned.
    subtype t_filter_sample is std_logic_vector(ADC_SAMPLE_SIZE + ADC_FILTER_FRAC downto 0); -- Input has one extra bit to allow unsigned.
    subtype t_filter_acc is std_logic_vector(t_filter_sample'length + t_filter_coeff'length - 1 downto 0);
    subtype t_filter_result is std_logic_vector(t_filter_sample'length + t_filter_coeff'length downto 0);

    constant COEFF_ONE          : t_filter_coeff := '1' & (0 to t_filter_coeff'length - 2 => '0');
    constant DSPL_UPDATE_MS     : integer := get_period_us;
    constant DSPL_UPDATE_CYCLES : integer := SYS_FREQ / 1000_000 * DSPL_UPDATE_MS;
    constant GND                : std_logic := '0';

    type t_state is (idle, s1, s2, s3, s4, s5, s6);
    type t_input_sys_reg is record
        state                   : t_state;
        display_count           : integer range 0 to DSPL_UPDATE_CYCLES - 1;
        filter_accumulator      : t_filter_acc;
        value                   : std_logic_vector(ADC_SAMPLE_SIZE - 1 downto 0);
        filter_b0               : t_filter_coeff;
        filter_a0               : t_filter_coeff;
        drp_do                  : std_logic_vector(15 downto 0);
    end record;

    constant R_INIT : t_input_sys_reg := (
        state                   => idle,
        display_count           => 0,
        filter_accumulator      => (others => '0'),
        value                   => (others => '0'),
        filter_b0               => (others => '0'),
        filter_a0               => (others => '0'),
        drp_do                  => (others => '0')
    );

    signal r, r_in              : t_input_sys_reg := R_INIT;

    signal xadc_busy_s          : std_logic;
    signal xadc_eoc_s           : std_logic;
    signal xadc_eos_s           : std_logic;

    signal drp_di_s             : std_logic_vector(15 downto 0);
    signal drp_do_s             : std_logic_vector(15 downto 0);
    signal drp_daddr_s          : std_logic_vector(6 downto 0);
    signal drp_den_s            : std_logic;
    signal drp_dwe_s            : std_logic;
    signal drp_drdy_s           : std_logic;

    -- p = a * b + c
    signal mul_a                : t_filter_sample;
    signal mul_b                : t_filter_coeff;
    signal mul_c                : t_filter_acc;
    signal mul_p                : t_filter_result;
    signal mul_carryout         : std_logic;

    component adc_mul_gen is
    port (
        clk                     : in  std_logic;
        a                       : in  t_filter_sample;
        b                       : in  t_filter_coeff;
        c                       : in  t_filter_acc;
        p                       : out t_filter_result;
        carryout                : out std_logic
    );
    end component;

    component xadc_gen is
    port (
        daddr_in                : in   std_logic_vector (6 downto 0);
        den_in                  : in   std_logic;
        di_in                   : in   std_logic_vector (15 downto 0);
        dwe_in                  : in   std_logic;
        do_out                  : out  std_logic_vector (15 downto 0);
        drdy_out                : out  std_logic;
        dclk_in                 : in   std_logic;
        reset_in                : in   std_logic;
        vauxp3                  : in   std_logic;
        vauxn3                  : in   std_logic;
        busy_out                : out  std_logic;
        channel_out             : out  std_logic_vector (4 downto 0);
        eoc_out                 : out  std_logic;
        eos_out                 : out  std_logic;
        alarm_out               : out  std_logic;
        vp_in                   : in   std_logic;
        vn_in                   : in   std_logic
    );
    end component;

begin

    -- p = a * b + c after 1 cycle, c is delayed must be issued in the same cycle as the result
    mul : adc_mul_gen
    port map (
        clk                     => clk,
        a                       => mul_a,
        b                       => mul_b,
        c                       => mul_c,
        p                       => mul_p,
        carryout                => mul_carryout
    );

    XADC_inst : xadc_gen
    port map (
        daddr_in                => drp_daddr_s,  -- Address bus for the dynamic reconfiguration port
        den_in                  => drp_den_s,    -- Enable Signal for the dynamic reconfiguration port
        di_in                   => drp_di_s,     -- Input data bus for the dynamic reconfiguration port
        dwe_in                  => drp_dwe_s,    -- Write Enable for the dynamic reconfiguration port
        do_out                  => drp_do_s,     -- Output data bus for dynamic reconfiguration port
        drdy_out                => drp_drdy_s,   -- Data ready signal for the dynamic reconfiguration port
        dclk_in                 => clk,          -- Clock input for the dynamic reconfiguration port
        reset_in                => reset,        -- Reset signal for the System Monitor control logic
        vauxp3                  => vauxp3,       -- Auxiliary Channel 0
        vauxn3                  => vauxn3,
        busy_out                => xadc_busy_s,  -- ADC Busy signal
        channel_out             => open,         -- Channel Selection Outputs
        eoc_out                 => xadc_eoc_s,   -- End of Conversion Signal
        eos_out                 => xadc_eos_s,   -- End of Sequence Signal
        alarm_out               => open,         -- OR'ed output of all the Alarms
        vp_in                   => GND,          -- Dedicated Analog Input Pair
        vn_in                   => GND           -- Will not synthsize without the explicit type
    );


    comb_proc : process (r, filter_length, average, drp_do_s, drp_drdy_s, xadc_eoc_s, mul_p)
        variable v_filter_b0 : t_filter_coeff;
        variable v_xadc_control0 : std_logic_vector(15 downto 0);
    begin

        r_in <= r;
        r_in.filter_b0 <= (others => '0');
        r_in.filter_a0 <= (others => '0');

        -- DRP port default values.
        drp_den_s <= '0';
        drp_dwe_s <= '0';
        drp_daddr_s <= 7x"13";
        drp_di_s <= (others => '0');

        -- Multiplier default values.
        mul_a <= (others => '0');
        mul_b <= (others => '0');
        mul_c <= (others => '0');

        -- Outputs.
        value <= r.value;

        -- Calculate filter coefficients from configuration input.
        if filter_length = b"000" then
            r_in.filter_b0 <= (others => '1');
        else
            v_filter_b0 := (others => '0');
            v_filter_b0(ADC_FILTER_FRAC - 1 - to_integer(unsigned(filter_length))) := '1';
            r_in.filter_b0 <= v_filter_b0;
            r_in.filter_a0 <= std_logic_vector(unsigned(COEFF_ONE) - unsigned(v_filter_b0));
        end if;

        -- Update the output value if the update time has passed and the state machine is idle.
        if r.display_count < DSPL_UPDATE_CYCLES - 1 then
            r_in.display_count <= r.display_count + 1;
        else
            if r.state = idle then
                r_in.display_count <= 0;
                r_in.value <= std_logic_vector(r.filter_accumulator(
                        t_filter_sample'length + ADC_FILTER_FRAC - 2 downto 2 * ADC_FILTER_FRAC));
            end if;
        end if;

        case (r.state) is

            when idle =>

                -- Read a new ADC sample from the XADC.
                if xadc_eoc_s = '1' then
                    drp_den_s <= '1';
                    r_in.state <= s1;
                end if;

            -- Issue a[0] * acc; wait for drp_drdy_s and issue b[0] * sample.
            when s1 =>
                if drp_drdy_s = '1' then
                    mul_b <= r.filter_b0;
                    mul_a <= '0' & drp_do_s(15 downto 16 - ADC_SAMPLE_SIZE)
                        & (0 to ADC_FILTER_FRAC - 1 => '0');
                    r_in.filter_accumulator <= mul_p(t_filter_acc'length - 1 downto 0);
                    r_in.state <= s2;
                else
                    mul_b <= r.filter_a0;
                    mul_a <= r.filter_accumulator(
                        t_filter_sample'length + ADC_FILTER_FRAC - 1 downto ADC_FILTER_FRAC);
                end if;

            when s2 =>
                mul_c <= r.filter_accumulator;
                r_in.filter_accumulator <= mul_p(t_filter_acc'length - 1 downto 0);
                r_in.state <= s3;

            when s3 =>
                drp_daddr_s <= 7x"40";
                drp_den_s <= '1';
                r_in.state <= s4;

            when s4 =>
                -- Cannot issue the next command before drdy is deasserted
                if drp_drdy_s = '1' then
                    r_in.drp_do <= drp_do_s;
                    r_in.state <= s5;
                end if;

            when s5 =>
                drp_daddr_s <= 7x"40";
                drp_dwe_s <= '1';
                drp_den_s <= '1';

                v_xadc_control0 := r.drp_do;
                v_xadc_control0(13 downto 12) := average;
                drp_di_s <= v_xadc_control0;

                r_in.state <= s6;

            when s6 =>
                if drp_drdy_s = '1' then
                    r_in.state <= idle;
                end if;

        end case;
    end process;

    reg_process : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r <= R_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
