----------------------------------------------------------------------------------
-- @file sobel_filter.vhd
--
-- @brief Takes a 3x3 sliding window and outputs the magnitude of the edge
-- gradient at the window's center pixel.
--
-- For invalid (not active) windows, mag_o is forced to zero, so edge of the image
-- has a small black border, WINDOW_SIZE_C - 1 pixels wide.
--
-- @details
-- The filter is a two stage pipeline:
--
--   stage 1 : Convolves the window with the horizontal and vertical Sobel
--             kernels (KERNEL_HORZ_C and KERNEL_VERT_C) to get the gradients
--             gx and gy. Only updated when window_valid_i is high.
--
--   stage 2 : Computes the magnitude as |gx| + |gy|, the Manhattan distance,
--             which avoids a square root. Forced to zero when stage 1 does not
--             hold a valid window.
--
-- mag_r is scaled to fit into mag_o by keeping its upper COMPONENT_WIDTH_C bits.
--
-- Latency is two clocks from window_i to mag_o. sof and eol pass through the
-- same two registers so they stay aligned with the magnitude.
--
-- ready_i is the pipeline clock enable. When it is low, every register holds
-- its value and the stage stalls. Reset does not depend on it.
--
-- @author Trevin Vaughan
-- 
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
-- libraries 
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_edge_detection.all;

----------------------------------------------------------------------------------
-- entity
----------------------------------------------------------------------------------

entity sobel_filter is
    generic (
        FRAME_WIDTH_G : integer := 1920 -- width of a video frame 
    );
    port (
        --clock and reset
        clk_i  : in std_logic; -- axi stream clock
        rstn_i : in std_logic; -- axi stream reset

        -- sliding window and pixel control
        window_i       : in sliding_window;
        window_valid_i : in std_logic;
        pixel_valid_i  : in std_logic;
        sof_i          : in std_logic; -- start of frame
        eol_i          : in std_logic; -- end of line

        -- final output - magnitude of the gradient
        mag_valid_o : out std_logic;
        mag_o       : out unsigned(COMPONENT_WIDTH_C - 1 downto 0);
        sof_o       : out std_logic; -- start of frame, aligned with mag_o
        eol_o       : out std_logic; -- end of line, aligned with mag_o

        -- downstream input
        ready_i : in std_logic -- downstream axi stream ready, pipeline clock enable
    );
end entity sobel_filter;
architecture behavioral of sobel_filter is
    ----------------------------------------------------------------------------------
    -- constants
    ----------------------------------------------------------------------------------
    constant SIGNED_PIXEL_WIDTH : integer := COMPONENT_WIDTH_C + 1;              -- signed grey scale pixel width
    constant ACC_WIDTH_C        : integer := SIGNED_PIXEL_WIDTH + WINDOW_SIZE_C; -- accumulation width for convolution

    ----------------------------------------------------------------------------------
    -- functions
    ----------------------------------------------------------------------------------
    function conv(window : sliding_window; kernel : kernel_t) return signed is
        variable pixel_v : signed(SIGNED_PIXEL_WIDTH - 1 downto 0); -- signed pixel
        variable prod_v  : signed(ACC_WIDTH_C - 1 downto 0);        -- product
        variable acc_v   : signed(ACC_WIDTH_C - 1 downto 0);        -- accumulation
    begin
        acc_v := (others => '0');

        -- element wise multiplication the slide window with kernel
        for r in 0 to WINDOW_SIZE_C - 1 loop
            for c in 0 to WINDOW_SIZE_C - 1 loop
                pixel_v := signed('0' & window(r)(c));
                prod_v  := pixel_v * to_signed(kernel(r)(c), WINDOW_SIZE_C);
                acc_v   := acc_v + prod_v; -- accumulated the result 
            end loop;
        end loop;
        return acc_v;
    end function conv;

    ----------------------------------------------------------------------------------
    -- signals
    ----------------------------------------------------------------------------------
    signal gx_r                 : signed(ACC_WIDTH_C - 1 downto 0);   -- horizontal gradient 
    signal gy_r                 : signed(ACC_WIDTH_C - 1 downto 0);   -- vertical gradient
    signal stage1_valid_r       : std_logic;                          -- gx_r and gy_r valid
    signal stage2_valid_r       : std_logic;                          -- magnitude valid  
    signal mag_r                : unsigned(ACC_WIDTH_C - 1 downto 0); -- magnitude of gradient
    signal stage1_sof_r         : std_logic;                          -- start of frame, stage 1
    signal stage1_eol_r         : std_logic;                          -- end of line, stage 1
    signal stage1_pixel_valid_r : std_logic;                          -- pixel valid, stage 1
    signal stage2_sof_r         : std_logic;                          -- start of frame, stage 2
    signal stage2_eol_r         : std_logic;                          -- end of line, stage 2
    signal stage2_pixel_valid_r : std_logic;                          -- pixel valid, stage 2

    ----------------------------------------------------------------------------------
    -- aliases 
    ----------------------------------------------------------------------------------
    -- scale mag_r to fit into mag_o by keeping its upper COMPONENT_WIDTH_C bits
    alias mag_scaled : unsigned(COMPONENT_WIDTH_C - 1 downto 0) is mag_r(ACC_WIDTH_C - 1 downto ACC_WIDTH_C - COMPONENT_WIDTH_C);

begin
    ----------------------------------------------------------------------------------
    -- sobel filter process
    ----------------------------------------------------------------------------------
    sobel_filter_proc : process (clk_i) is
    begin
        if rising_edge(clk_i) then
            if rstn_i = '0' then
                gx_r           <= (others => '0');
                gy_r           <= (others => '0');
                mag_r          <= (others => '0');
                stage1_valid_r <= '0';
                stage2_valid_r <= '0';
                stage1_sof_r   <= '0';
                stage1_eol_r   <= '0';
                stage2_sof_r   <= '0';
                stage2_eol_r   <= '0';

            elsif ready_i = '1' then
                -- ready_i is the pipeline clock enable: when low, every
                -- register holds its value and the stage stalls

                -- pixel control signals pipelining
                stage1_sof_r         <= sof_i;
                stage1_eol_r         <= eol_i;
                stage1_pixel_valid_r <= pixel_valid_i;

                stage2_sof_r         <= stage1_sof_r;
                stage2_eol_r         <= stage1_eol_r;
                stage2_pixel_valid_r <= stage1_pixel_valid_r;

                -- stage 1 convolve for the horizontal and vertical gradient
                if window_valid_i = '1' then
                    gx_r           <= conv(window_i, KERNEL_HORZ_C);
                    gy_r           <= conv(window_i, KERNEL_VERT_C);
                    stage1_valid_r <= '1';
                else
                    stage1_valid_r <= '0';
                end if;

                if stage1_valid_r = '1' then
                    -- calculate the magnitude using Manhattan distance
                    mag_r          <= unsigned(abs(gx_r)) + unsigned(abs(gy_r));
                    stage2_valid_r <= '1';
                else
                    stage2_valid_r <= '0';
                end if;

            end if;
        end if;
    end process sobel_filter_proc;

    ----------------------------------------------------------------------------------
    -- final output
    ----------------------------------------------------------------------------------
    -- border pixels have no full window, so output black instead of being
    -- dropped: every input pixel still produces an output, which keeps the AXI
    -- video frame timing intact
    mag_o <= mag_scaled when stage2_valid_r = '1' else
        (others => '0');
    mag_valid_o <= stage2_pixel_valid_r;
    sof_o       <= stage2_sof_r;
    eol_o       <= stage2_eol_r;
end architecture behavioral;
