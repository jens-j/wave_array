library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity oscillator is
    generic (
        N_OSCILLATORS           : positive := 4;
        INIT_FILE               : string := "saw_mipmap.data"
    );
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        mipmap_enable           : in  std_logic;
        interpolate_enable      : in  std_logic;
        next_sample             : in  std_logic;
        velocities              : in  t_table_phase_array(N_OSCILLATORS - 1 downto  0);
        mipmap_level            : out integer range 0 to MIPMAP_LEVELS - 1;
        samples                 : out t_mono_sample_array(N_OSCILLATORS - 1 downto  0)
    );
end entity;

architecture arch of oscillator is

    constant PIPELINE_STAGES : integer := 8;
    constant PIPELINE_LENGTH : integer := PIPELINE_STAGES * N_OSCILLATORS * 2 + PIPELINE_STAGES;


    function get_mipmap_level (velocity : t_table_phase) return integer is
    begin
        for level in 0 to MIPMAP_LEVELS - 2 loop
            if velocity < MIPMAP_THRESHOLDS(level) then
                return level;
            end if;
        end loop;
        return MIPMAP_LEVELS - 1;
    end function get_mipmap_level;

    -- coeffient is unsigned 1.8 fixed point. Range: [0 - 1] or [0x0 - 0x100].
    subtype t_mul_coeff is std_logic_vector(WAVE_ADDR_FRAC + 1 downto 0); -- Input has one extra bit to allow unsigned.
    subtype t_mul_sample is std_logic_vector(SAMPLE_SIZE - 1 downto 0); -- Input is signed.
    subtype t_mul_acc is std_logic_vector(t_mul_sample'length + t_mul_coeff'length - 1 downto 0);
    subtype t_mul_result is std_logic_vector(t_mul_sample'length + t_mul_coeff'length downto 0);

    type t_state is (idle, gen_samples, update_phases);
    type t_oscillator_reg is record
        state                   : t_state;
        samples                 : t_mono_sample_array(0 to N_OSCILLATORS - 1); -- Output sample buffer.
        sample_buffer           : t_mono_sample_array(0 to N_OSCILLATORS - 1); -- Next sample buffer.
        phases                  : t_table_phase_array(0 to N_OSCILLATORS - 1); -- Phase of all oscillators.
        count                   : integer range 0 to PIPELINE_LENGTH - 1;
        mipmap_level            : integer range 0 to MIPMAP_LEVELS - 1; -- Mipmap table to use for next sample.
        wave_address            : unsigned(WAVE_SIZE_LOG2 - 1 downto 0); -- Address in (L0) wave table.
        mipmap_address_a        : std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0); -- Address in mipmap table for interpolation sample A.
        mipmap_address_a_d      : std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0); -- Address in mipmap table for interpolation sample A, delayed one cycle while address B is calculated.
        mipmap_address_b        : std_logic_vector(MIPMAP_ADDR_SIZE - 1 downto 0); -- Address in mipmap table for interpolation sample B.
        mul_sample              : t_mul_sample; -- Multiplier A port input buffer.
        mul_coeff               : t_mul_coeff; -- Multiplier B port input buffer.
        mul_acc                 : t_mul_acc; -- Multiplier C port input buffer.
        mul_res                 : t_mul_result; -- Multiplier P port output buffer.
    end record;

    constant R_INIT : t_oscillator_reg := (
        state                   => idle,
        samples                 => (others => (others => '0')),
        sample_buffer           => (others => (others => '0')),
        phases                  => (others => (others => '0')),
        count                   => 0,
        mipmap_level            => 0,
        wave_address            => (others => '0'),
        mipmap_address_a        => (others => '0'),
        mipmap_address_a_d      => (others => '0'),
        mipmap_address_b        => (others => '0'),
        mul_sample              => (others => '0'),
        mul_coeff               => (others => '0'),
        mul_acc                 => (others => '0'),
        mul_res                 => (others => '0')
    );

    signal r, r_in : t_oscillator_reg := R_INIT;

    -- Blockram signals.
    signal ram_ren_s            : std_logic;
    signal ram_raddr_s          : std_logic_vector(MIPMAP_ADDR_SIZE-1 downto 0);
    signal ram_rdata_s          : std_logic_vector(SAMPLE_SIZE-1 downto 0);
    signal ram_wen_s            : std_logic;
    signal ram_waddr_s          : std_logic_vector(MIPMAP_ADDR_SIZE-1 downto 0);
    signal ram_wdata_s          : std_logic_vector(SAMPLE_SIZE-1 downto 0);

    signal mul_a_s              : t_mul_sample;
    signal mul_b_s              : t_mul_coeff;
    signal mul_c_s              : t_mul_acc;
    signal mul_p_s              : t_mul_result;

    component osc_mul_gen is
    port (
        clk                     : in std_logic;
        a                       : in t_mul_sample;
        b                       : in t_mul_coeff;
        c                       : in t_mul_acc;
        p                       : out t_mul_result
    );
    end component;

begin

    osc_mul : osc_mul_gen
    port map (
        clk                     => clk,
        a                       => mul_a_s,
        b                       => mul_b_s,
        c                       => mul_c_s,
        p                       => mul_p_s
    );

    -- Wave table ram
    mipmap_ram : entity wave.blockram
    generic map (
        ABITS                   => MIPMAP_ADDR_SIZE,
        DBITS                   => SAMPLE_SIZE,
        INIT_FILE               => INIT_FILE
    )
    port map(
        rclk                    => clk,
        wclk                    => clk,
        ren                     => ram_ren_s,
        raddr                   => ram_raddr_s,
        rdata                   => ram_rdata_s,
        wen                     => ram_wen_s,
        waddr                   => ram_waddr_s,
        wdata                   => ram_wdata_s
    );

    combinatorial : process (r, next_sample, velocities, ram_rdata_s, mul_p_s)
        variable v_odd : boolean;
        variable v_wave_address : unsigned(WAVE_SIZE_LOG2 - 1 downto 0);
        variable v_address_frac : unsigned(WAVE_ADDR_FRAC - 1 downto 0);
    begin

        r_in <= r;
        r_in.mipmap_address_a_d <= r.mipmap_address_a;
        v_odd := r.count mod 2 = 1;

        case (r.state) is
            when idle =>
                if next_sample = '1' then
                    r_in.state <= gen_samples;
                    r_in.count <= 0;
                    r_in.samples <= r.sample_buffer;
                    r_in.sample_buffer <= (others => (others => '0'));
                end if;

            when gen_samples =>

                -- Increase counter
                if r.count < 2 * N_OSCILLATORS + PIPELINE_STAGES - 1 then
                    r_in.count <= r.count + 1;
                else
                    r_in.state <= update_phases;
                    r_in.count <= 0;
                end if;

            when update_phases =>

                r_in.phases(r.count) <= r.phases(r.count) + velocities(r.count);

                if r.count = N_OSCILLATORS - 1 then
                    r_in.state <= idle;
                else
                    r_in.count <= r.count + 1;
                end if;

        end case;

        -- Pipeline stage 0: calculate mipmap level and calculate wave Address.
        if r.count < 2 * N_OSCILLATORS then
            r_in.mipmap_level <= get_mipmap_level(velocities(r.count / 2));

            v_wave_address :=
                r.phases(r.count / 2)(WAVE_ADDR_SIZE - 1 downto WAVE_ADDR_FRAC);

            if v_odd then
                r_in.wave_address <= v_wave_address + 1;
            else
                r_in.wave_address <= v_wave_address;
            end if;
        else
            -- r_in.mipmap_level <= 0;
            -- r_in.wave_address <= (others => '0');
        end if;

        -- Pipeline stage 1: calculate mipmap address A.
        if mipmap_enable = '1' then
            r_in.mipmap_address_a <= std_logic_vector(
                unsigned(MIPMAP_OFFSETS(r.mipmap_level)) +
                resize(r.wave_address(WAVE_SIZE_LOG2 - 1 downto r.mipmap_level),
                       MIPMAP_ADDR_SIZE));
        else
            r_in.mipmap_address_a <= std_logic_vector(resize(r.wave_address, MIPMAP_ADDR_SIZE));
        end if;

        -- Pipeline stage 2: calculate mipmap address B.
        r_in.mipmap_address_b <= std_logic_vector(unsigned(r.mipmap_address_a) + 1);

        -- Pipeline stage 3: issue read from mipmap table.
        ram_ren_s <= '1';
        if v_odd then
            ram_raddr_s <= r.mipmap_address_a_d;
        else
            ram_raddr_s <= r.mipmap_address_b;
        end if;

        -- Pipeline stage 4: register mipmap sample.
        r_in.mul_sample <= ram_rdata_s;

        -- Pipeline stage 4: calculate interpolation coefficients.
        if r.count >= 4 and r.count < 2 * N_OSCILLATORS + 4 then
            v_address_frac := r.phases((r.count - 4) / 2)(WAVE_ADDR_FRAC - 1 downto 0);


            if interpolate_enable = '1' then
                if v_odd then
                    -- Coeff B range [0x0 - 0xFF]. Leading zero to make unsigned.
                    r_in.mul_coeff <= "00" & std_logic_vector(v_address_frac);
                else
                    -- Coeff A is 1 - Coeff A. Range [0x0 - 0x100]. Leading zero to make unsigned.
                    r_in.mul_coeff <= "0" & std_logic_vector(
                        unsigned(unsigned'("1" & (0 to WAVE_ADDR_FRAC - 1 => '0')))
                        - resize(v_address_frac, WAVE_ADDR_FRAC + 1));
                end if;
            else
                if v_odd then
                    r_in.mul_coeff <= (t_mul_coeff'length - 1 downto 0 => '0');
                else
                    r_in.mul_coeff <= "01" & (0 to t_mul_coeff'length - 3 => '0');
                end if;
            end if;
        else
            r_in.mul_coeff <= (others => '0');
        end if;

        -- Pipeline stage 5: multiply sample with coefficient
        mul_a_s <= r.mul_sample;
        mul_b_s <= r.mul_coeff;

        if v_odd then
            r_in.mul_acc <= (others => '0');
        else
            r_in.mul_acc <= mul_p_s(t_mul_acc'length - 1 downto 0);
        end if;

        -- Pipeline stage 6: add multiplication result to accumulator and store result.
        mul_c_s <= r.mul_acc;
        r_in.mul_res <= mul_p_s;

        -- Pipeline stage 7: write sample to buffer.
        if r.count > PIPELINE_STAGES - 1 and not v_odd then
            r_in.sample_buffer((r.count - PIPELINE_STAGES) / 2) <=
                signed(r.mul_res(SAMPLE_SIZE + WAVE_ADDR_FRAC - 1 downto WAVE_ADDR_FRAC));
        end if;

        -- Output ports.
        samples <= r.samples;
        mipmap_level <= r.mipmap_level;

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
