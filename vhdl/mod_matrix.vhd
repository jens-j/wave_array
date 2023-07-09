library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


entity mod_matrix is 
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        next_sample             : in  std_logic;
        mod_sources             : in  t_mods_array;
        mod_destinations        : out t_modd_array
    );
end entity;

architecture arch of mod_matrix is 

    constant PIPE_LEN_MUX_IN    : integer := 1;
    constant PIPE_LEN_MULT      : integer := 1;
    constant PIPE_LEN_ADD       : integer := 1;
    constant PIPE_LEN_CLIP      : integer := 1;
    constant PIPE_LEN_MUX_OUT   : integer := 1;

    constant PIPE_SUM_MULT      : integer := PIPE_LEN_MUX_IN + PIPE_LEN_MULT;
    constant PIPE_SUM_ADD       : integer := PIPE_SUM_MULT + PIPE_LEN_ADD;
    constant PIPE_SUM_CLIP      : integer := PIPE_SUM_ADD + PIPE_LEN_CLIP;
    constant PIPE_SUM_MUX_OUT   : integer := PIPE_SUM_CLIP + PIPE_LEN_MUX_OUT;

    constant ACC_WIDTH          : integer := CTRL_SIZE + MAX_MOD_SOURCES_LOG2 + 1; -- Plus one for base value.

    type t_state is (idle, running);
    type t_accumulator_array is array (0 to N_VOICES - 1) of signed(ACC_WIDTH - 1 downto 0);
    type t_dest_counter_array is array (0 to PIPE_SUM_MUX_OUT - 1) of integer range 0 to MODD_LEN - 1;
    type t_source_counter_array is array (0 to PIPE_SUM_MUX_OUT - 1) of integer range 0 to MAX_MOD_SOURCES;
    
    
    type t_mod_matrix_reg is record
        state                   : t_state;
        mod_dest                : t_modd_array;
        mod_dest_buffer         : t_modd_array;
        dest_counter            : t_dest_counter_array;
        source_counter          : t_source_counter_array;
        source_values           : t_ctrl_value_array(0 to N_VOICES - 1); -- Source operands mux buffer.
        scaled_source_values    : t_ctrl_value_array(0 to N_VOICES - 1); -- Source operands scaled by multiplying with mod amount.
        accumulator             : t_accumulator_array;
        accumulator_clipped     : t_ctrl_value_array(0 to N_VOICES - 1); 
        valid_shift             : std_logic_vector(PIPE_SUM_MUX_OUT - 1 downto 0); -- Pipeline valid shift register.
        amount                  : t_ctrl_value;
    end record;

    constant REG_INIT : t_mod_matrix_reg := (
        state                   => idle,
        mod_dest                => (others => (others => (others => '0'))),
        mod_dest_buffer         => (others => (others => (others => '0'))),
        dest_counter            => (others => 0),
        source_counter          => (others => 0),
        source_values           => (others => (others => '0')),
        scaled_source_values    => (others => (others => '0')),
        accumulator             => (others => (others => '0')),
        accumulator_clipped     => (others => (others => '0')),
        valid_shift             => (others => '0'),
        amount                  => (others => '0')
    );

    signal r, r_in : t_mod_matrix_reg := REG_INIT;

    -- -- This prevents Vivado somehow optimizing away this whole entity. 
    -- attribute keep : string;
    -- attribute keep of r : signal is "true";

begin 

    -- Connect outputs.
    mod_destinations <= r.mod_dest;
    

    combinatorial : process (r, next_sample, config, mod_sources)
        -- variable v_source_index : integer range 0 to MODS_LEN - 1;
        variable v_source_index : integer range 0 to MODS_LEN - 1;
        variable v_mult : signed(2 * CTRL_SIZE - 1 downto 0);
    begin

        r_in <= r;

        r_in.valid_shift(0) <= '0';
        r_in.amount <= (others => '0');
        r_in.accumulator <= (others => (others => '0'));
        r_in.accumulator_clipped <= (others => (others => '0'));
        r_in.source_values <= (others => (others => '0'));
        
        if r.state = idle then 

            if next_sample = '1' then 

                r_in.mod_dest <= r.mod_dest_buffer;
                r_in.mod_dest_buffer <= (others => (others => (others => '0')));

                r_in.source_counter <= (others => 0);
                r_in.dest_counter <= (others => 0);

                r_in.valid_shift(0) <= '1';
                r_in.state <= running;
            end if;

        -- Pipeline stage 0:
        -- This state only inputs data into the pipeline. Later stages are handled outside the state machine.
        -- In the first MAX_MOD_SOURCES cycles, the modulation sources are muxed for the accumulator. 
        -- Finally the base control value is muxed in cycle MAX_MOD_SOURCES.
        elsif r.state = running then 

            r_in.valid_shift(0) <= '1';     

            if r.source_counter(0) = MAX_MOD_SOURCES then 
                r_in.source_values <= (others => config.base_ctrl(r.dest_counter(0)));
                r_in.amount <= x"7FFF";
            else  
                -- Mux mod source amount.
                r_in.amount <= config.mod_mapping(r.dest_counter(0))(r.source_counter(0)).amount;

                -- Look up mod source index in the mapping based on the pipeline counters.
                v_source_index := config.mod_mapping(r.dest_counter(0))(r.source_counter(0)).source;  

                if v_source_index /= MODS_NONE then 
                    r_in.source_values <= mod_sources(v_source_index);
                else 
                    r_in.source_values <= (others => (others => '0'));
                end if;
            end if;

            -- Increment counters.
            if r.source_counter(0) < MAX_MOD_SOURCES then 
                r_in.source_counter(0) <= r.source_counter(0) + 1;
            else 
                r_in.source_counter(0) <= 0;

                if r.dest_counter(0) < MODD_LEN - 1 then 
                    r_in.dest_counter(0) <= r.dest_counter(0) + 1;
                else 
                    r_in.state <= idle;
                end if;
            end if;

        end if;

        -- Pipeline stage 1: multiply mod source with mod amount.
        if r.valid_shift(PIPE_SUM_MULT - 1) = '1' then 
            for i in 0 to N_VOICES - 1 loop
                v_mult := r.source_values(i) * r.amount;
                r_in.scaled_source_values(i) <= v_mult(2 * CTRL_SIZE - 2 downto CTRL_SIZE - 1);

            end loop;
        end if;

        -- Pipeline stage 2: add source control values to accumulators.
        if r.valid_shift(PIPE_SUM_ADD - 1) = '1' then 

            for i in 0 to N_VOICES - 1 loop 
                if r.source_counter(PIPE_SUM_ADD - 1) = 0 then 
                    r_in.accumulator(i) <= resize(r.scaled_source_values(i), ACC_WIDTH);
                else 
                    r_in.accumulator(i) <= r.accumulator(i) + r.scaled_source_values(i);
                end if;

            end loop;
        end if;

        -- Pipeline stage 3: clip accumulator.
        if r.valid_shift(PIPE_SUM_CLIP - 1) = '1' and r.source_counter(PIPE_SUM_CLIP - 1) = MAX_MOD_SOURCES then 

            for i in 0 to N_VOICES - 1 loop 

                if r.accumulator(i) > resize(x"7FFF", ACC_WIDTH) then 
                    r_in.accumulator_clipped(i) <= x"7FFF";
                elsif r.accumulator(i) < resize(x"8001", ACC_WIDTH) then 
                    r_in.accumulator_clipped(i) <= x"8001";
                else 
                    r_in.accumulator_clipped(i) <= r.accumulator(i)(CTRL_SIZE - 1 downto 0);
                end if;

            end loop;           
        end if;

        -- Pipeline stage 4: output mux.
        if r.valid_shift(PIPE_SUM_MUX_OUT - 1) = '1' and r.source_counter(PIPE_SUM_MUX_OUT - 1) = MAX_MOD_SOURCES then 

            r_in.mod_dest_buffer(r.dest_counter(PIPE_SUM_MUX_OUT - 1)) <= r.accumulator_clipped;
        end if;

        -- Update shift registers.
        r_in.valid_shift(PIPE_SUM_MUX_OUT - 1 downto 1) <= r.valid_shift(PIPE_SUM_MUX_OUT - 2 downto 0);
        r_in.dest_counter(1 to PIPE_SUM_MUX_OUT - 1)    <= r.dest_counter(0 to PIPE_SUM_MUX_OUT - 2);
        r_in.source_counter(1 to PIPE_SUM_MUX_OUT - 1)  <= r.source_counter(0 to PIPE_SUM_MUX_OUT - 2);

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