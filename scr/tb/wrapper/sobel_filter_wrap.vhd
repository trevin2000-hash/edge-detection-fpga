----------------------------------------------------------------------------------
-- @file sobel_filter_wrap.vhd
--
-- @brief Verification-only wrapper around sobel_filter that flattens the
-- sliding window port so a SystemVerilog testbench can drive it.
--
-- @details sobel_filter takes window_i as the VHDL composite type
-- sliding_window (array of array of unsigned). User-defined composite types
-- cannot cross a mixed-language port boundary, so this wrapper accepts the
-- window as a single std_logic_vector and leaves the DUT untouched. The
-- magnitude output is likewise converted from unsigned to std_logic_vector.
--
-- Window bit layout (matches flatten_window() in pkg_edge_detection.sv and
-- the flattening done by pixel_line_buff_wrap.vhd):
--
--   index          = (row * WINDOW_SIZE_C) + col
--   window_i slice = ((index + 1) * COMPONENT_WIDTH_C) - 1
--                    downto (index * COMPONENT_WIDTH_C)
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
entity sobel_filter_wrap is
    generic (
        FRAME_WIDTH_G : integer := 1920 -- width of a video frame
    );
    port (
        -- clock and reset
        clk_i  : in std_logic; -- axi stream clock
        rstn_i : in std_logic; -- axi stream reset

        -- flattened sliding window, see layout in file header
        window_i       : in std_logic_vector((WINDOW_SIZE_C * WINDOW_SIZE_C * COMPONENT_WIDTH_C) - 1 downto 0);
        window_valid_i : in std_logic;

        -- final output - magnitude of the gradient
        mag_valid_o : out std_logic;
        mag_o       : out unsigned(COMPONENT_WIDTH_C - 1 downto 0)
    );
end entity sobel_filter_wrap;

----------------------------------------------------------------------------------
-- architecture
----------------------------------------------------------------------------------
architecture Behavioral of sobel_filter_wrap is
    ----------------------------------------------------------------------------------
    -- signals
    ----------------------------------------------------------------------------------
    signal window_s : sliding_window;                           -- typed window fed to the DUT
    signal mag_s    : unsigned(COMPONENT_WIDTH_C - 1 downto 0); -- typed magnitude from the DUT

begin

    ----------------------------------------------------------------------------------
    -- unflatten the sliding window from the cross-language boundary
    ----------------------------------------------------------------------------------
    unflatten_rows : for r in 0 to WINDOW_SIZE_C - 1 generate
        unflatten_cols : for c in 0 to WINDOW_SIZE_C - 1 generate
            window_s(r)(c) <= unsigned(window_i((((r * WINDOW_SIZE_C) + c + 1) * COMPONENT_WIDTH_C) - 1
            downto ((r * WINDOW_SIZE_C) + c) * COMPONENT_WIDTH_C));
        end generate unflatten_cols;
    end generate unflatten_rows;

    ----------------------------------------------------------------------------------
    -- device under test
    ----------------------------------------------------------------------------------
    dut : entity work.sobel_filter
        generic map(
            FRAME_WIDTH_G => FRAME_WIDTH_G
        )
        port map
        (
            clk_i  => clk_i,
            rstn_i => rstn_i,

            window_i       => window_s,
            window_valid_i => window_valid_i,

            mag_valid_o => mag_valid_o,
            mag_o       => mag_o
        );

end architecture Behavioral;
