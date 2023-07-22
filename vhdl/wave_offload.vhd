library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library uart;
use uart.uart_pkg.all;

library xil_defaultlib;


entity wave_offload is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        config                  : in  t_config;
        next_sample             : in  std_logic;
        new_period              : in  std_logic_vector(N_VOICES - 1 downto 0);
        sample_in               : in  t_mono_sample;
        lowest_voice            : in  integer range 0 to N_VOICES - 1; -- Voice index of the lowest playing note.

        -- Auto offload fifo interface.
        wave_write_enable       : out std_logic;
        wave_data               : out std_logic_vector(CTRL_SIZE - 1 downto 0);
        wave_full               : in  std_logic;

        debug_state_offload     : out integer;
        debug_state_sample      : out integer;
        debug_fifo_count        : out integer range 0 to 2047;
        debug_timer             : out std_logic_vector(15 downto 0); 
        debug_flags             : out std_logic_vector(5 downto 0) -- wave_req & wave_ready
    );
end entity;

architecture arch of wave_offload is 

    type t_state_offload is (offload_idle, offload_wave_0, offload_wave_1, offload_wave_2);
    type t_state_sample is (sample_idle, sample_running);

    type t_packet_engine_reg is record
        state_offload           : t_state_offload;
        state_sample            : t_state_sample;
        wave_write_enable       : std_logic;
        wave_data               : std_logic_vector(CTRL_SIZE - 1 downto 0);
        wave_timer              : integer; -- Counts cycles. Compared to config.wave_period of which the value counts increments of 1024 cycles..
        wave_req                : std_logic; -- Wave timer overflow flag.
        wave_ready              : std_logic; -- Wave buffer filled flag.
        wave_length             : integer range 0 to WAVE_MAX_WORDS - 1;
        sample_count            : integer range 0 to WAVE_MAX_WORDS - 1;
        offload_count           : integer range 0 to WAVE_MAX_WORDS - 1;
        lowest_voice            : integer range 0 to N_VOICES - 1;
        next_sample             : std_logic; -- Delay one cycle to sample after values update.
        fifo_overflow           : std_logic;
        fifo_underflow          : std_logic;
    end record;

    constant REG_INIT : t_packet_engine_reg := (
        state_offload           => offload_idle,
        state_sample            => sample_idle,
        wave_write_enable       => '0',
        wave_data               => (others => '0'),
        wave_timer              => 0,
        wave_req                => '0',
        wave_ready              => '0',
        wave_length             => 0,
        sample_count            => 0,
        offload_count           => 0,
        lowest_voice            => 0,
        next_sample             => '0',
        fifo_overflow           => '0',
        fifo_underflow          => '0'
    );

    signal r, r_in              : t_packet_engine_reg;

    signal s_fifo_write_enable  : std_logic;
    signal s_fifo_read_enable   : std_logic;
    signal s_fifo_full          : std_logic;
    signal s_fifo_empty         : std_logic;
    signal s_fifo_count         : std_logic_vector(11 downto 0);
    signal s_fifo_read_data     : std_logic_vector(15 downto 0);

begin

    wave_fifo : entity xil_defaultlib.wave_offload_fifo_gen
    port map (
        clk                     => clk,
        srst                    => reset,
        din                     => std_logic_vector(sample_in),
        wr_en                   => s_fifo_write_enable,
        rd_en                   => s_fifo_read_enable,
        dout                    => s_fifo_read_data,
        full                    => s_fifo_full,
        empty                   => s_fifo_empty,
        data_count              => s_fifo_count
    );

    comb_process : process (r, config, next_sample, wave_full, new_period, sample_in, lowest_voice, 
            s_fifo_empty, s_fifo_full, s_fifo_read_data, s_fifo_count)
        variable v_debug_timer : std_logic_vector(CTRL_SIZE + 9 downto 0);
        variable v_length : std_logic_vector(15 downto 0);
    begin

        r_in <= r;
        r_in.wave_write_enable <= '0';
        r_in.wave_data <= (others => '0');
        r_in.next_sample <= next_sample;

        s_fifo_write_enable <= '0';
        s_fifo_read_enable <= '0';

        -- Connect output registers.
        wave_write_enable <= r.wave_write_enable;
        wave_data <= r.wave_data;      

        debug_state_offload <= t_state_offload'pos(r.state_offload);
        debug_state_sample <= t_state_sample'pos(r.state_sample);
        debug_fifo_count <= to_integer(unsigned(s_fifo_count));
        debug_flags <= r.fifo_overflow & r.fifo_underflow & r.wave_req & r.wave_ready & s_fifo_empty & s_fifo_full;

        v_debug_timer := std_logic_vector(to_unsigned(r.wave_timer, CTRL_SIZE + 10));
        debug_timer <= v_debug_timer(CTRL_SIZE - 1 downto 0);

        -- Fill fifo with samples of one period of the lowest note.
        case r.state_sample is 
        when sample_idle => 

            if r.next_sample = '1' and new_period(lowest_voice) = '1' and r.wave_ready = '0' then 
                s_fifo_write_enable <= '1';
                r_in.lowest_voice <= lowest_voice;
                r_in.sample_count <= 1;
                r_in.state_sample <= sample_running; 
            end if; 

        when sample_running => 

            if r.next_sample = '1' then 
                if new_period(r.lowest_voice) = '1' then
                    r_in.wave_ready <= '1';
                    r_in.wave_length <= r.sample_count;
                    r_in.state_sample <= sample_idle;
                else 
                    if s_fifo_full = '1' then 
                        r_in.fifo_overflow <= '1';
                    end if;

                    s_fifo_write_enable <= '1';
                    r_in.sample_count <= r.sample_count + 1;
                end if;
            end if;
        end case;

        -- Write wave packet to uart packet engine if samples are ready in the fifo and the timer overflowed.
        case r.state_offload is 
        when offload_idle => 
            
            if config.wave_enable = '1' and r.wave_req = '1' and r.wave_ready = '1' then 
                r_in.wave_req <= '0';
                r_in.offload_count <= r.wave_length;
                r_in.state_offload <= offload_wave_0;
            end if;

        -- Write auto offload opcode and wave channel. 
        when offload_wave_0 =>

            r_in.wave_write_enable <= '1';
            r_in.wave_data <= UART_AUTO_OFFLOAD & UART_AO_WAVE;
            r_in.state_offload <= offload_wave_1;
        
        -- write data length in 16 bit words.
        when offload_wave_1 =>

            r_in.wave_write_enable <= '1';
            v_length := std_logic_vector(to_unsigned(r.offload_count, CTRL_SIZE));
            r_in.wave_data <= v_length(7 downto 0) & v_length(15 downto 8); -- Switch bytes for little endian transfer.
            r_in.state_offload <= offload_wave_2;

        -- Write packet data to auto offload fifo.
        when offload_wave_2 =>

            if s_fifo_empty = '1' then 
                r_in.fifo_underflow <= '1';
            end if;

            r_in.wave_write_enable <= '1';
            s_fifo_read_enable <= '1';
            r_in.wave_data <= s_fifo_read_data(7 downto 0) & s_fifo_read_data(15 downto 8); -- Switch bytes for little endian transfer.
            
            if r.offload_count > 1 then 
                r_in.offload_count <= r.offload_count - 1;
            else 
                r_in.wave_ready <= '0';
                r_in.state_offload <= offload_idle;
            end if;
        end case;

        -- Increment wave timer.
        if r.wave_timer >= to_integer(config.wave_period) * 2**10 then 
            r_in.wave_timer <= 0;
            r_in.wave_req <= '1';
        else 
            r_in.wave_timer <= r.wave_timer + 1;
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