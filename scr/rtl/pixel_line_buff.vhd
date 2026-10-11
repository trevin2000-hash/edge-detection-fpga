----------------------------------------------------------------------------------
-- @file pixel_line_buff.vhd
-- 
-- @brief Takes a raster stream of greyscale pixels and outputs a 3x3 sliding
-- window of the most recent pixels for convolution.
--
-- @details
-- Two line buffers hold the previous two lines of the frame. Line buffer 0
-- holds line y-1 and line buffer 1 holds line y-2. For each input pixel at x,
-- both buffers are read at x, and the pixel moves down one line: the new pixel
-- is written into line buffer 0 and the old line buffer 0 value into line
-- buffer 1. Both buffers are block RAM with registered read data, and their
-- contents start at zero after configuration.
--
-- The window is a shift register. Each new pixel shifts in a column of
-- line y-2, line y-1 and the current pixel, so window_o(row)(col) holds:
--
--   row 0 : line y-2       col 0 : x-2
--   row 1 : line y-1       col 1 : x-1
--   row 2 : line y         col 2 : x
--
-- pixel_valid_o marks every input pixel, including pixels near the top and
-- left edges of the frame where the window is not full yet. window_valid_o
-- is high only when the window also holds a full neighborhood, which is when
-- the newest pixel has x >= 2 and y >= 2. sof_o and eol_o are the frame
-- markers of that newest pixel.
--
-- Downstream logic must still produce an output pixel for every
-- pixel_valid_o, even when window_valid_o is low, for example by outputting
-- zero. Dropping those pixels would leave frames short and move sof and eol
-- off the right pixels, which breaks the AXI video stream timing.
--
-- Latency is two clocks from an input pixel to its window: one for the RAM
-- read and one for the window register. The outputs only change when a pixel
-- shifts in.
--
-- ready_i is the pipeline clock enable. When it is low, the line buffers and
-- every register hold their value and the stage stalls. Reset does not
-- depend on it.
--
-- @author Trevin Vaughan
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
    generic (
        COMPONENT_WIDTH_G : integer := COMPONENT_WIDTH_C; -- bits per component in a pixel 
        FRAME_WIDTH_G     : integer := 1920               -- width of a video frame 
    );
    port (
        --clock and reset
        clk_i  : in std_logic; -- axi stream clock
        rstn_i : in std_logic; -- axi stream reset

        -- upstream pixel data
        greyscale_pixel_i : in unsigned(COMPONENT_WIDTH_G - 1 downto 0); -- greyscale pixel
        pixel_valid_i     : in std_logic;                                -- current pixel is valid 
        x_i               : in unsigned(15 downto 0);                    -- current x position the pixel 
        y_i               : in unsigned(15 downto 0);                    -- current y position the pixel
        sof_i             : in std_logic;                                -- start of frame
        eol_i             : in std_logic;                                -- end of line

        -- downstream - sliding window and pixel control
        window_o       : out sliding_window;
        window_valid_o : out std_logic;
        pixel_valid_o  : out std_logic;
        sof_o          : out std_logic; -- start of frame
        eol_o          : out std_logic; -- end of line

        -- downstream input
        ready_i : in std_logic -- downstream axi stream ready, pipeline clock enable
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

    -- line buffer for keep the last 2 line of pixels (initialized a boot to '0')
    signal line_buffer0_r : line_buff_t := (others => (others => '0'));
    signal line_buffer1_r : line_buff_t := (others => (others => '0'));

    -- taps for each line of buffer
    signal tap0_r : unsigned(COMPONENT_WIDTH_G - 1 downto 0);
    signal tap1_r : unsigned(COMPONENT_WIDTH_G - 1 downto 0);

    -- force line buffers to synthesis as BRAM
    attribute ram_style                   : string;
    attribute ram_style of line_buffer0_r : signal is "block";
    attribute ram_style of line_buffer1_r : signal is "block";

    -- input delayed one clock to line up with the BRAM read data
    signal greyscale_pixel_r : unsigned(COMPONENT_WIDTH_G - 1 downto 0) := (others => '0');
    signal x_r               : unsigned(15 downto 0)                    := (others => '0');
    signal y_r               : unsigned(15 downto 0)                    := (others => '0');
    signal pixel_valid_r     : std_logic                                := '0';
    signal sof_r             : std_logic                                := '0';
    signal eol_r             : std_logic                                := '0';

    -- sliding window register 
    signal window_r : sliding_window;

begin

    ----------------------------------------------------------------------------------
    -- combination logic 
    ----------------------------------------------------------------------------------
    window_o <= window_r;

    ----------------------------------------------------------------------------------
    -- line buffer 0: read-first then write single port BRAM
    ----------------------------------------------------------------------------------
    line_buffer0_proc : process (clk_i) is
    begin
        if rising_edge(clk_i) then
            if (ready_i = '1' and pixel_valid_i = '1') then
                tap0_r                          <= line_buffer0_r(to_integer(x_i));
                line_buffer0_r(to_integer(x_i)) <= greyscale_pixel_i;
            end if;
        end if;
    end process line_buffer0_proc;

    ----------------------------------------------------------------------------------
    -- line buffer 1: simple dual port BRAM
    -- read at the current x, write tap0_r one clock later at the previous x
    ----------------------------------------------------------------------------------
    line_buffer1_proc : process (clk_i) is
    begin
        if rising_edge(clk_i) then
            if (ready_i = '1' and pixel_valid_i = '1') then
                tap1_r <= line_buffer1_r(to_integer(x_i));
            end if;

            if (ready_i = '1' and pixel_valid_r = '1') then
                line_buffer1_r(to_integer(x_r)) <= tap0_r;
            end if;
        end if;
    end process line_buffer1_proc;

    ----------------------------------------------------------------------------------
    -- sliding window
    ----------------------------------------------------------------------------------
    sliding_window_proc : process (clk_i) is
    begin
        if rising_edge(clk_i) then
            if (rstn_i = '0') then
                window_valid_o    <= '0';
                window_r          <= WINDOW_DEFAULT_C;
                pixel_valid_r     <= '0';
                greyscale_pixel_r <= (others => '0');
                sof_o             <= '0';
                eol_o             <= '0';
                pixel_valid_o     <= '0';

            elsif (ready_i = '1') then
                -- ready_i is the pipeline clock enable: when low, every
                -- register holds its value and the stage stalls

                -- delay one clock to match BRAM read latency
                pixel_valid_r     <= pixel_valid_i;
                greyscale_pixel_r <= greyscale_pixel_i;
                x_r               <= x_i;
                y_r               <= y_i;
                sof_r             <= sof_i;
                eol_r             <= eol_i;

                -- assert pixel value for downstream logic
                pixel_valid_o <= pixel_valid_r;

                if (pixel_valid_r = '1') then
                    -- frame markers of the newest pixel in the window
                    sof_o <= sof_r;
                    eol_o <= eol_r;

                    -- sliding window is a shift register fill by the line buffers
                    window_r(0)(2) <= tap1_r;
                    window_r(0)(1) <= window_r(0)(2);
                    window_r(0)(0) <= window_r(0)(1);

                    window_r(1)(2) <= tap0_r;
                    window_r(1)(1) <= window_r(1)(2);
                    window_r(1)(0) <= window_r(1)(1);

                    window_r(2)(2) <= greyscale_pixel_r;
                    window_r(2)(1) <= window_r(2)(2);
                    window_r(2)(0) <= window_r(2)(1);

                    if ((x_r >= WINDOW_SIZE_C - 1) and (y_r >= WINDOW_SIZE_C - 1)) then
                        -- window valid when window_r is filled 
                        window_valid_o <= '1';
                    else
                        window_valid_o <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process sliding_window_proc;

end architecture Behavioral;
