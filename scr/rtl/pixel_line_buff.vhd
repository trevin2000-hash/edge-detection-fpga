----------------------------------------------------------------------------------
-- @file pixel_line_buff.vhd
-- 
-- @brief This takes greyscale pixel has a input and outputs a valid 3x3 sliding window
-- for convolution
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

library work;
use work.pkg_edge_detection.all;

----------------------------------------------------------------------------------
-- entity
----------------------------------------------------------------------------------

entity pixel_line_buff is
    generic(
        COMPONENT_WIDTH_G : integer := COMPONENT_WIDTH_C; -- bits per component in a pixel 
        FRAME_WIDTH_G     : integer := 1920 -- width of a video frame 
    );
    port(
        --clock and reset
        clk_i             : in  std_logic; -- axi stream clock
        rstn_i            : in  std_logic; -- axi stream reset

        -- upstream pixel data
        greyscale_pixel_i : in  unsigned(COMPONENT_WIDTH_G - 1 downto 0); -- greyscale pixel
        pixel_valid_i     : in  std_logic; -- current pixel is valid 
        x_i               : in  unsigned(15 downto 0); -- current x position the pixel 
        y_i               : in  unsigned(15 downto 0); -- current y position the pixel 

        -- sliding window
        window_o          : out sliding_window;
        window_valid_o    : out std_logic
    );
end entity pixel_line_buff;

----------------------------------------------------------------------------------
-- architecture
----------------------------------------------------------------------------------
architecture Behavioral of pixel_line_buff is
    ----------------------------------------------------------------------------------
    -- types
    ----------------------------------------------------------------------------------
    type line_buff_t is array (FRAME_WIDTH_G - 1 downto 0) of unsigned(COMPONENT_WIDTH_G - 1 downto 0);

    ----------------------------------------------------------------------------------
    -- signals and registers
    ----------------------------------------------------------------------------------

    -- line buffer for keep the last 2 line of pixels
    signal line_buffer0_r : line_buff_t;
    signal line_buffer1_r : line_buff_t;

    -- taps for each line of buffer
    signal tap0_r : unsigned(COMPONENT_WIDTH_G - 1 downto 0);
    signal tap1_r : unsigned(COMPONENT_WIDTH_G - 1 downto 0);

    -- sliding window register 
    signal window_r : sliding_window;

begin

    ----------------------------------------------------------------------------------
    -- combination logic 
    ----------------------------------------------------------------------------------
    window_o <= window_r;

    ----------------------------------------------------------------------------------
    -- line buffer and sliding window
    ----------------------------------------------------------------------------------
    line_buffer : process(clk_i) is
    begin
        if rising_edge(clk_i) then
            if (rstn_i = '0') then
                window_valid_o <= '0';
                window_r       <= WINDOW_DEFAULT_C;

            else
                if (pixel_valid_i = '1') then
                    -- read then write for BRAM access pattern
                    tap0_r                          <= line_buffer0_r(to_integer(x_i));
                    line_buffer0_r(to_integer(x_i)) <= greyscale_pixel_i;

                    tap1_r                          <= line_buffer1_r(to_integer(x_i));
                    line_buffer1_r(to_integer(x_i)) <= tap0_r;

                    -- sliding window is a shift register fill by the line buffers
                    window_r(1)(3) <= tap1_r;
                    window_r(1)(2) <= window_r(1)(3);
                    window_r(1)(1) <= window_r(1)(2);

                    window_r(2)(3) <= tap0_r;
                    window_r(2)(2) <= window_r(2)(3);
                    window_r(2)(1) <= window_r(2)(2);

                    window_r(3)(3) <= greyscale_pixel_i;
                    window_r(3)(2) <= window_r(3)(3);
                    window_r(3)(1) <= window_r(3)(1);

                    if ((x_i >= WINDOW_SIZE_C) and (y_i >= WINDOW_SIZE_C)) then
                        -- window valid when window_r is filled 
                        window_valid_o <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process line_buffer;

end architecture Behavioral;
