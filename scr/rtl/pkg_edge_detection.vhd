----------------------------------------------------------------------------------
-- @file pkg_edge_detection.vhd
-- 
-- @brief this contains constants use across the project
-- 
-- @author Trevin Vaughan
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pkg_edge_detection is
    -- constants 
    constant COMPONENT_WIDTH_C : integer := 8; -- width of component in a pixel

    -- windwo constants
    constant WINDOW_SIZE_C : integer := 3; -- size of sliding window

    -- types
    type row            is array (WINDOW_SIZE_C - 1 to 0) of unsigned(COMPONENT_WIDTH_C - 1 downto 0); -- row of sliding window
    type sliding_window is array (WINDOW_SIZE_C - 1 to 0) of row; -- a 3x3 sliding window 

    constant WINDOW_DEFAULT_C : sliding_window := (others => (others => (others => '0'))); -- safe default for sliding window

end package pkg_edge_detection;
