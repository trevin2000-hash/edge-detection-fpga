----------------------------------------------------------------------------------
-- @file pixel_line_buff_wrap.vhd
--
-- @brief Verification-only wrapper around pixel_line_buff that flattens the
-- sliding window port so a SystemVerilog testbench can bind to it.
--
-- @details pixel_line_buff exposes window_o as the VHDL composite type
-- sliding_window (array of array of unsigned). User-defined composite types
-- cannot cross a mixed-language port boundary, so this wrapper presents the
-- window as a single std_logic_vector and leaves the DUT untouched.
--
-- Window bit layout (matches unpack_window() in pkg_edge_detection_sv.sv):
--
--   index          = (row * WINDOW_SIZE_C) + col
--   window_o slice = ((index + 1) * COMPONENT_WIDTH_G) - 1
--                    downto (index * COMPONENT_WIDTH_G)
--
-- so window(0)(0) occupies the LOW bits and window(2)(2) the HIGH bits:
--
--   bits  7:0   -> window(0)(0)    bits 39:32 -> window(1)(1)
--   bits 15:8   -> window(0)(1)    bits 47:40 -> window(1)(2)
--   bits 23:16  -> window(0)(2)    bits 55:48 -> window(2)(0)
--   bits 31:24  -> window(1)(0)    bits 63:56 -> window(2)(1)
--                                  bits 71:64 -> window(2)(2)
--
-- @warning Simulation only. Do not instantiate in synthesizable hierarchy.
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
entity pixel_line_buff_wrap is
    generic (
        COMPONENT_WIDTH_G : integer := COMPONENT_WIDTH_C; -- bits per component in a pixel
        FRAME_WIDTH_G     : integer := 3840               -- width of a video frame
    );
    port (
        -- clock and reset
        clk_i  : in std_logic; -- axi stream clock
        rstn_i : in std_logic; -- axi stream reset

        -- upstream pixel data
        greyscale_pixel_i : in std_logic_vector(COMPONENT_WIDTH_G - 1 downto 0); -- greyscale pixel
        pixel_valid_i     : in std_logic;                                        -- current pixel is valid
        x_i               : in std_logic_vector(15 downto 0);                    -- current x position of the pixel
        y_i               : in std_logic_vector(15 downto 0);                    -- current y position of the pixel

        -- flattened sliding window, see layout in file header
        window_o       : out std_logic_vector((WINDOW_SIZE_C * WINDOW_SIZE_C * COMPONENT_WIDTH_G) - 1 downto 0);
        window_valid_o : out std_logic
    );
end entity pixel_line_buff_wrap;

----------------------------------------------------------------------------------
-- architecture
----------------------------------------------------------------------------------
architecture Behavioral of pixel_line_buff_wrap is
    ----------------------------------------------------------------------------------
    -- signals
    ----------------------------------------------------------------------------------
    signal window_s : sliding_window; -- typed window straight from the DUT

begin

    ----------------------------------------------------------------------------------
    -- device under test
    ----------------------------------------------------------------------------------
    dut : entity work.pixel_line_buff
        generic map (
            COMPONENT_WIDTH_G => COMPONENT_WIDTH_G,
            FRAME_WIDTH_G     => FRAME_WIDTH_G
        )
        port map (
            clk_i  => clk_i,
            rstn_i => rstn_i,

            greyscale_pixel_i => unsigned(greyscale_pixel_i),
            pixel_valid_i     => pixel_valid_i,
            x_i               => unsigned(x_i),
            y_i               => unsigned(y_i),

            window_o       => window_s,
            window_valid_o => window_valid_o
        );

    ----------------------------------------------------------------------------------
    -- flatten the sliding window for the cross-language boundary
    ----------------------------------------------------------------------------------
    flatten_rows : for r in 0 to WINDOW_SIZE_C - 1 generate
        flatten_cols : for c in 0 to WINDOW_SIZE_C - 1 generate
            window_o((((r * WINDOW_SIZE_C) + c + 1) * COMPONENT_WIDTH_G) - 1
                     downto ((r * WINDOW_SIZE_C) + c) * COMPONENT_WIDTH_G)
                <= std_logic_vector(window_s(r)(c));
        end generate flatten_cols;
    end generate flatten_rows;

end architecture Behavioral;