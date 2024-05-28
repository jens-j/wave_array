library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;

library xil_defaultlib;
library sdram;

-- Priority memory arbiter. Lowest index goes first.
-- Clients can assert their read- or write-enable lines and wait for the valid line.
entity ddr_arbiter is
    generic (
        N_CLIENTS               : integer;
        NO_MIG                  : boolean := false
    );
    port (
        mig_ctrl_clk            : in    std_logic;
        mig_ref_clk             : in    std_logic;
        mig_ui_clk              : out   std_logic; 
        mig_reset               : in    std_logic;
        mig_ui_reset            : out   std_logic;
        pll_locked              : in    std_logic; -- SDRAM clock needs to be running before becoming active.

        -- Client interfaces.
        sdram_inputs            : in    t_sdram_input_array(0 to N_CLIENTS - 1);
        sdram_outputs           : out   t_sdram_output_array(0 to N_CLIENTS - 1);

        -- SDRAM interface.
        DDR3_DQ                 : inout std_logic_vector(15 downto 0);
        DDR3_DQS_P              : inout std_logic_vector(1 downto 0);
        DDR3_DQS_N              : inout std_logic_vector(1 downto 0);
        DDR3_ADDR               : out   std_logic_vector(14 downto 0);
        DDR3_BA                 : out   std_logic_vector(2 downto 0);
        DDR3_RAS_N              : out   std_logic;
        DDR3_CAS_N              : out   std_logic;
        DDR3_WE_N               : out   std_logic;
        DDR3_RESET_N            : out   std_logic;
        DDR3_CK_P               : out   std_logic;
        DDR3_CK_N               : out   std_logic;
        DDR3_CKE                : out   std_logic;
        DDR3_DM                 : out   std_logic_vector(1 downto 0);
        DDR3_ODT                : out   std_logic
    );
end entity;

architecture arch of ddr_arbiter is

    type t_state is (init, idle, read_0, read_1, read_2, write_0, write_1, write_2);

    type t_arbiter_reg is record
        state                   : t_state;
        index                   : integer range 0 to N_CLIENTS - 1;
        sdram_outputs           : t_sdram_output_array(0 to N_CLIENTS - 1);
        burst_count             : integer range 0 to 2**29 - 1;
        word_count              : integer range 0 to 7;
        prefetch_count          : unsigned(31 downto 0);
        app_wdf_data            : std_logic_vector(127 downto 0);
        app_rd_data             : std_logic_vector(127 downto 0);
        address                 : unsigned(27 downto 0);
        fifo_wr_en              : std_logic;
    end record;

    constant REG_INIT : t_arbiter_reg := (
        state                   => init,
        index                   => 0,
        sdram_outputs           => (others => SDRAM_OUTPUT_INIT),
        burst_count             => 0,
        word_count              => 0,
        prefetch_count          => (others => '0'),
        app_wdf_data            => (others => '0'),
        app_rd_data             => (others => '0'),
        address                 => (others => '0'),
        fifo_wr_en              => '0'
    );

    signal r, r_in              : t_arbiter_reg;

    signal s_fifo_din           : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    signal s_fifo_rd_en         : std_logic;
    signal s_fifo_dout          : std_logic_vector(SDRAM_WIDTH - 1 downto 0);
    signal s_fifo_full          : std_logic;
    signal s_fifo_empty         : std_logic;
    signal s_fifo_data_count    : std_logic_vector(4 downto 0);

    signal s_app_rd_data        : std_logic_vector(127 downto 0);
    signal s_app_rd_data_end    : std_logic;
    signal s_app_rd_data_valid  : std_logic;
    signal s_app_rdy            : std_logic;
    signal s_app_wdf_rdy        : std_logic;

    signal s_app_addr           : std_logic_vector(28 downto 0);
    signal s_app_cmd            : std_logic_vector(2 downto 0);
    signal s_app_en             : std_logic;
    signal s_app_wdf_end        : std_logic;
    signal s_app_wdf_wren       : std_logic;

    signal s_mig_ui_clk         : std_logic;
    signal s_ui_sync_rst        : std_logic;
    signal s_init_calib_complete: std_logic;
    signal s_mig_ui_reset       : std_logic;

    component mig_gen
    port (
        ddr3_dq                 : inout std_logic_vector(15 downto 0);
        ddr3_dqs_p              : inout std_logic_vector(1 downto 0);
        ddr3_dqs_n              : inout std_logic_vector(1 downto 0);
        ddr3_addr               : out   std_logic_vector(14 downto 0);
        ddr3_ba                 : out   std_logic_vector(2 downto 0);
        ddr3_ras_n              : out   std_logic;
        ddr3_cas_n              : out   std_logic;
        ddr3_we_n               : out   std_logic;
        ddr3_reset_n            : out   std_logic;
        ddr3_ck_p               : out   std_logic_vector(0 downto 0);
        ddr3_ck_n               : out   std_logic_vector(0 downto 0);
        ddr3_cke                : out   std_logic_vector(0 downto 0);
        ddr3_dm                 : out   std_logic_vector(1 downto 0);
        ddr3_odt                : out   std_logic_vector(0 downto 0);
        app_addr                : in    std_logic_vector(28 downto 0);
        app_cmd                 : in    std_logic_vector(2 downto 0);
        app_en                  : in    std_logic;
        app_wdf_data            : in    std_logic_vector(127 downto 0);
        app_wdf_end             : in    std_logic;
        app_wdf_mask            : in    std_logic_vector(15 downto 0);
        app_wdf_wren            : in    std_logic;
        app_rd_data             : out   std_logic_vector(127 downto 0);
        app_rd_data_end         : out   std_logic;
        app_rd_data_valid       : out   std_logic;
        app_rdy                 : out   std_logic;
        app_wdf_rdy             : out   std_logic;
        app_sr_req              : in    std_logic;
        app_ref_req             : in    std_logic;
        app_zq_req              : in    std_logic;
        app_sr_active           : out   std_logic;
        app_ref_ack             : out   std_logic;
        app_zq_ack              : out   std_logic;
        ui_clk                  : out   std_logic;
        ui_clk_sync_rst         : out   std_logic;
        init_calib_complete     : out   std_logic;
        sys_clk_i               : in    std_logic;
        clk_ref_i               : in    std_logic;
        device_temp             : out   std_logic_vector(11 downto 0);
        sys_rst                 : in    std_logic
    );
    end component;

begin

    -- 18 word deep FWFT fifo.
    prefetch : entity xil_defaultlib.arbiter_fifo
    port map (
        clk                     => s_mig_ui_clk,
        srst                    => s_mig_ui_reset,
        din                     => s_fifo_din,
        wr_en                   => r.fifo_wr_en,
        rd_en                   => s_fifo_rd_en,
        dout                    => s_fifo_dout,
        full                    => s_fifo_full,
        empty                   => s_fifo_empty,
        data_count              => s_fifo_data_count
    );

    no_mig_gen : if NO_MIG generate 
        s_mig_ui_clk <= mig_ctrl_clk;
        s_mig_ui_reset <= mig_reset;
    end generate;

    do_mig_gen : if not NO_MIG generate
        sdram_controller : mig_gen
        port map (
            sys_clk_i               => mig_ctrl_clk,
            clk_ref_i               => mig_ref_clk,
            device_temp             => open,
            sys_rst                 => mig_reset,

            app_addr                => s_app_addr,
            app_cmd                 => s_app_cmd,
            app_en                  => s_app_en,
            app_wdf_data            => r.app_wdf_data,
            app_wdf_end             => s_app_wdf_end,
            app_wdf_mask            => (others => '0'),
            app_wdf_wren            => s_app_wdf_wren,
            app_rd_data             => s_app_rd_data,
            app_rd_data_end         => s_app_rd_data_end,
            app_rd_data_valid       => s_app_rd_data_valid,
            app_rdy                 => s_app_rdy,
            app_wdf_rdy             => s_app_wdf_rdy,
            app_sr_req              => '0',
            app_ref_req             => '0',
            app_zq_req              => '0',
            app_sr_active           => open,
            app_ref_ack             => open,
            app_zq_ack              => open,

            ui_clk                  => s_mig_ui_clk,
            ui_clk_sync_rst         => s_mig_ui_reset,
            init_calib_complete     => s_init_calib_complete,

            ddr3_dq                 => DDR3_DQ,
            ddr3_dqs_p              => DDR3_DQS_P,
            ddr3_dqs_n              => DDR3_DQS_N,
            ddr3_addr               => DDR3_ADDR,
            ddr3_ba                 => DDR3_BA,
            ddr3_ras_n              => DDR3_RAS_N,
            ddr3_cas_n              => DDR3_CAS_N,
            ddr3_we_n               => DDR3_WE_N,
            ddr3_reset_n            => DDR3_RESET_N,
            ddr3_ck_p(0)            => DDR3_CK_P,
            ddr3_ck_n(0)            => DDR3_CK_N,
            ddr3_cke(0)             => DDR3_CKE,
            ddr3_dm                 => DDR3_DM,
            ddr3_odt(0)             => DDR3_ODT
        );
    end generate;

    -- Connect output registers.
    sdram_outputs <= r.sdram_outputs;

    comb_process : process (r, sdram_inputs, s_mig_ui_clk, s_mig_ui_reset,
        s_app_rd_data, s_app_rd_data_end, s_app_rd_data_valid, s_app_rdy, s_app_wdf_rdy,
        s_fifo_dout, s_fifo_full, s_fifo_empty, s_fifo_data_count, s_init_calib_complete)

    begin

        r_in <= r;
        r_in.sdram_outputs <= (others => SDRAM_OUTPUT_INIT);

        -- Mux prefetch fifo input.
        s_fifo_din <= sdram_inputs(r.index).write_data;

        s_fifo_rd_en <= '0';
        r_in.fifo_wr_en <= '0';

        s_app_addr <= (others => '0');
        s_app_cmd <= (others => '0');
        s_app_en <= '0';
        s_app_wdf_end <= '0';
        s_app_wdf_wren <= '0';

        -- Output ui clock to be used as system clock.
        mig_ui_clk <= s_mig_ui_clk;
        mig_ui_reset <= s_mig_ui_reset;

        -- Prefetch write words to avoid latency issues with handshaking. Wait for the write_enable is deasserted to start prefetching after the ack is returned. 
        if r.prefetch_count > 0 and to_integer(unsigned(s_fifo_data_count)) < 16 
                and sdram_inputs(r.index).write_enable = '0' then

            r_in.fifo_wr_en <= '1';
            r_in.prefetch_count <= r.prefetch_count - 1;

            if r.prefetch_count = 1 then
                r_in.sdram_outputs(r.index).done <= '1';
            else
                r_in.sdram_outputs(r.index).write_req <= '1';
            end if;
        end if;
        
        -- Wait for controller initialization.
        if r.state = init and s_init_calib_complete = '1' then
            r_in.state <= idle;

        -- Wait for read- or write-enables.
        elsif r.state = idle then 
            for i in 0 to N_CLIENTS - 1 loop
                if sdram_inputs(i).read_enable = '1' or sdram_inputs(i).write_enable = '1' then

                    r_in.word_count <= 0;
                    r_in.index <= i;
                    r_in.burst_count <= sdram_inputs(i).burst_n;
                    r_in.address <= sdram_inputs(i).address;
                    r_in.sdram_outputs(i).ack <= '1';

                    if sdram_inputs(i).read_enable = '1' then 
                        r_in.state <= read_0;
                    else 
                        r_in.prefetch_count <= to_unsigned(8 * sdram_inputs(i).burst_n, 32);
                        r_in.state <= write_0;
                    end if;

                    exit; -- Lower client indices get priority.

                end if;
            end loop;

        -- Issue read command to the MIG. 
        elsif r.state = read_0 then 

            s_app_en <= '1';
            s_app_cmd <= "001";
            s_app_addr <= '0' & std_logic_vector(r.address); -- MIG expects one msb bit.
            
            if s_app_rdy = '1' then 
                r_in.state <= read_1;
            end if;

        -- Register read data burst as a vector.
        elsif r.state = read_1 then 
            if s_app_rd_data_valid = '1' then 
                r_in.app_rd_data <= s_app_rd_data;
                r_in.word_count <= 0;
                r_in.state <= read_2;
            end if;

        -- Return words to the client interface.
        elsif r.state = read_2 then 
            r_in.sdram_outputs(r.index).read_valid <= '1';
            r_in.sdram_outputs(r.index).read_data <= r.app_rd_data((r.word_count + 1) * 16 - 1 downto r.word_count * 16);

            if r.word_count < 7 then 
                r_in.word_count <= r.word_count + 1;
            else 
                if r.burst_count > 1 then 
                    r_in.burst_count <= r.burst_count - 1;
                    r_in.word_count <= 0;
                    r_in.address <= r.address + to_unsigned(8, 28);
                    r_in.state <= read_0;
                else
                    r_in.sdram_outputs(r.index).done <= '1';
                    r_in.state <= idle;
                end if;
            end if;

        -- Collect 8 words from the client.    
        elsif r.state = write_0 and s_fifo_empty = '0' then 

            s_fifo_rd_en <= '1';
            r_in.app_wdf_data((r.word_count + 1) * 16 - 1 downto r.word_count * 16) <= s_fifo_dout;

            if r.word_count < 7 then 
                r_in.word_count <= r.word_count + 1;
            else 
                r_in.state <= write_1;
            end if;

        -- Write burst to MIG input fifo as a vector.
        elsif r.state = write_1 then 

            if s_app_wdf_rdy = '1' then 
                s_app_wdf_wren <= '1';
                s_app_wdf_end <= '1';
                r_in.state <= write_2;
            end if;

        -- Initiate write command on the MIG.
        elsif r.state = write_2 then

            s_app_en <= '1';
            s_app_cmd <= "000";
            s_app_addr <= '0' & std_logic_vector(r.address); -- MIG expects one msb bit.

            if s_app_rdy = '1' then 
                if r.burst_count > 1 then 
                    r_in.burst_count <= r.burst_count - 1;
                    r_in.word_count <= 0;
                    r_in.address <= r.address + to_unsigned(8, 28);
                    r_in.state <= write_0;
                else
                    r_in.state <= idle;
                end if;
            end if;
        end if;

    end process;

    reg_process : process (s_mig_ui_clk)
    begin
        if rising_edge(s_mig_ui_clk) then
            if s_mig_ui_reset = '1' then
                r <= REG_INIT;
            else
                r <= r_in;
            end if;
        end if;
    end process;

end architecture;
