----------------------------------------------------------------------------------
-- @file pixel_line_buff.vhd
-- 
-- @brief This takes 3x3 sliding window and output the magnitude of edge gradient.
-- 
-- 
-- @details 
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

        -- sliding window input from pixel line buffer
        window_i       : in sliding_window;
        window_valid_i : in std_logic;

        -- final output - magnitude of the gradient 
        mag_valid_o : out std_logic;
        mag_o       : out unsigned(COMPONENT_WIDTH_C - 1 downto 0)
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
        variable pixel_v : signed(SIGNED_PIXEL_WIDTH - 1 downto 0); --signed pixel
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
    signal gx_r           : signed(ACC_WIDTH_C - 1 downto 0);   -- horizontal gradient 
    signal gy_r           : signed(ACC_WIDTH_C - 1 downto 0);   -- vertical gradient
    signal stage1_valid_r : std_logic;                          -- 
    signal stage2_valid_r : std_logic;                          -- magnitude valid  
    signal mag_r          : unsigned(ACC_WIDTH_C - 1 downto 0); -- magnitude of gradient  

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
            else
                -- default value: 

                -- stage 1 convolve for the horizontal and vertical gradient
                if window_valid_i then
                    gx_r           <= conv(window_i, KERNEL_HORZ_C);
                    gy_r           <= conv(window_i, KERNEL_VERT_C);
                    stage1_valid_r <= '1';
                else
                    stage1_valid_r <= '0';
                end if;

                if stage1_valid_r then
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
    -- bit shift mag_r to fix inside a 8 bits
    mag_o       <= mag_r(ACC_WIDTH_C - 1 downto ACC_WIDTH_C - COMPONENT_WIDTH_C);
    mag_valid_o <= stage2_valid_r;
end architecture behavioral;
