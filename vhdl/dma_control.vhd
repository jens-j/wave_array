library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library wave;
use wave.wave_array_pkg.all;


-- This entity manages the contents of the wavetable memory. It swaps frames in the 4 quadrants of
-- the wavetable memory. The two active frames are identified by frame_0_index and frame_1_index.
-- These two frames are interpolated by the oscillator.
entity dma_control is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic;
        dma_input               : in  t_dma_input;
        dma2ctrl                : in  t_dma2ctrl;
        ctrl2dma                : out t_ctrl2dma;
        buffer_index            : out integer range 0 to 3
    );
end entity;

architecture arch of dma_control is

    type t_state is (idle, dma_start, init_0, init_1, init_2, init_3, init_4, init_5,
        increment_0, increment_1, decrement_0, decrement_1);

    type t_dma_ctrl_reg is record
        state                   : t_state;
        next_state              : t_state;
        ctrl2dma                : t_ctrl2dma;
        buffer_index            : unsigned(1 downto 0); -- Unsigned for easy overflow.
        frame_index             : unsigned(WAVE_MAX_FRAMES_LOG2 downto 0); -- Can also be WAVE_MAX_FRAMES + 1.
        new_table               : std_logic; -- Register this signal because it is a pulse.
        base_address            : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
        n_frames_log2           : integer range 0 to 8;
    end record;

    constant REG_INIT : t_dma_ctrl_reg := (
        state                   => init_0,
        next_state              => idle,
        ctrl2dma                => CTRL2DMA_INIT,
        buffer_index            => "00",
        frame_index             => (others => '0'),
        new_table               => '0',
        base_address            => (others => '0'),
        n_frames_log2           => 0
    );

    signal r, r_in              : t_dma_ctrl_reg;

begin


    comb_process : process (r, dma_input, dma2ctrl)
        variable v_address_offset : unsigned(SDRAM_DEPTH_LOG2 - 1 downto 0);
    begin

        r_in <= r;
        r_in.ctrl2dma.start <= '0';
        r_in.ctrl2dma.address <= (others => '0');
        r_in.ctrl2dma.index <= 0;

        -- Register this signal in case the state machine is busy.
        if dma_input.new_table = '1' then
            r_in.new_table <= '1';
            r_in.base_address <= dma_input.base_address;
            r_in.n_frames_log2 <= dma_input.n_frames_log2;
        end if;

        -- Connect output registers.
        ctrl2dma <= r.ctrl2dma;
        buffer_index <= to_integer(r.buffer_index);

        -- Read frame position input.
        if r.state = init_0 then
            r_in.frame_index <= '0' & to_unsigned(dma_input.frame_index, WAVE_MAX_FRAMES_LOG2);
            r_in.state <= init_1;

        -- Write current frame (frame_0).
        elsif r.state = init_1 and dma2ctrl.busy = '0' then

            v_address_offset := r.frame_index
                * to_unsigned(MIPMAP_TABLE_SIZE, SDRAM_DEPTH_LOG2 - WAVE_MAX_FRAMES_LOG2 - 1);

            r_in.ctrl2dma.start <= '1';
            r_in.ctrl2dma.index <= to_integer(r.buffer_index + 2);
            r_in.ctrl2dma.address <=
                r.base_address + v_address_offset(SDRAM_DEPTH_LOG2 - 1 downto 0);

            r_in.state <= dma_start;
            r_in.next_state <= init_2;

        -- Wait for DMA to start.
        elsif r.state = dma_start then
            if dma2ctrl.busy = '1' then
                r_in.state <= r.next_state;
            end if;

        -- Write frame index+1 (frame_1).
        elsif r.state = init_2 and dma2ctrl.busy = '0' then

            v_address_offset := (r.frame_index + 1)
                * to_unsigned(MIPMAP_TABLE_SIZE, SDRAM_DEPTH_LOG2 - WAVE_MAX_FRAMES_LOG2 - 1);

            r_in.ctrl2dma.start <= '1';
            r_in.ctrl2dma.index <= to_integer(r.buffer_index + 3);
            r_in.ctrl2dma.address <=
                r.base_address + v_address_offset(SDRAM_DEPTH_LOG2 - 1 downto 0);

            r_in.state <= dma_start;
            r_in.next_state <= init_3;


        -- Wait from DMA to complete and update table pointer.
        -- Then start writing frame index+2 if required.
        elsif r.state = init_3 and dma2ctrl.busy = '0' then

            r_in.buffer_index <= r.buffer_index + 2;

            if r.frame_index + 2 <= 2**dma_input.n_frames_log2 then 

                v_address_offset := (r.frame_index + 2)
                    * to_unsigned(MIPMAP_TABLE_SIZE, SDRAM_DEPTH_LOG2 - WAVE_MAX_FRAMES_LOG2 - 1);

                r_in.ctrl2dma.start <= '1';
                r_in.ctrl2dma.index <= to_integer(r.buffer_index + 4);
                r_in.ctrl2dma.address <=
                    r.base_address + v_address_offset(SDRAM_DEPTH_LOG2 - 1 downto 0);

                r_in.state <= dma_start;
                r_in.next_state <= init_4;
            else 
                r_in.state <= init_4;
            end if;

        -- Write frame index-1 if required.
        elsif r.state = init_4 and dma2ctrl.busy = '0' then

            if r.frame_index > 0 then 

                v_address_offset := (r.frame_index - 1)
                    * to_unsigned(MIPMAP_TABLE_SIZE, SDRAM_DEPTH_LOG2 - WAVE_MAX_FRAMES_LOG2 - 1);

                r_in.ctrl2dma.start <= '1';
                r_in.ctrl2dma.index <= to_integer(r.buffer_index - 1);
                r_in.ctrl2dma.address <=
                    r.base_address + v_address_offset(SDRAM_DEPTH_LOG2 - 1 downto 0);

                r_in.state <= dma_start;
                r_in.next_state <= idle;
            else 
                r_in.state <= idle;
            end if;

         -- Increment frame and table pointer.
        elsif r.state = increment_0 then
            r_in.buffer_index <= r.buffer_index + 1;
            r_in.frame_index <= r.frame_index + 1;
            r_in.state <= increment_1;

        -- Write higher frame to wavetable memory to index+2.
        elsif r.state = increment_1 and dma2ctrl.busy = '0' then

            if r.frame_index + 2 <= 2**dma_input.n_frames_log2 then 

                v_address_offset := (r.frame_index + 2)
                    * to_unsigned(MIPMAP_TABLE_SIZE, SDRAM_DEPTH_LOG2 - WAVE_MAX_FRAMES_LOG2 - 1);

                r_in.ctrl2dma.start <= '1';
                r_in.ctrl2dma.index <= to_integer(r.buffer_index + 2);
                r_in.ctrl2dma.address <=
                    r.base_address + v_address_offset(SDRAM_DEPTH_LOG2 - 1 downto 0);

                r_in.state <= dma_start;
                r_in.next_state <= idle;    
            else 
                r_in.state <= idle;   
            end if;

         -- Decrement frame and table pointer.
        elsif r.state = decrement_0 then
            if dma2ctrl.busy = '0' then
                r_in.buffer_index <= r.buffer_index - 1;
                r_in.frame_index <= r.frame_index - 1;
                r_in.state <= decrement_1;
            end if;

        -- Write lower frame to index below current index.
        elsif r.state = decrement_1 and dma2ctrl.busy = '0' then

            if r.frame_index > 0 then 

                v_address_offset := (r.frame_index - 1)
                    * to_unsigned(MIPMAP_TABLE_SIZE, SDRAM_DEPTH_LOG2 - WAVE_MAX_FRAMES_LOG2 - 1);

                r_in.ctrl2dma.start <= '1';
                r_in.ctrl2dma.index <= to_integer(r.buffer_index - 1);
                r_in.ctrl2dma.address <=
                    r.base_address + v_address_offset(SDRAM_DEPTH_LOG2 - 1 downto 0);

                r_in.state <= dma_start;
                r_in.next_state <= idle;    
            else 
                r_in.state <= idle;   
            end if;       

        -- Wait for something to happen.
        elsif r.state = idle then

            -- Check for table change.
            if r.new_table = '1' then
                r_in.new_table <= '0';
                r_in.state <= init_0;

            -- Check if control value requires changing to lower frame.
            elsif dma_input.frame_index > to_integer(r.frame_index) then
                r_in.state <= increment_0;

            -- CHeck if control value requires changing to higher frame.
            elsif dma_input.frame_index < to_integer(r.frame_index) then
                r_in.state <= decrement_0;
            end if;
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
