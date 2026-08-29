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
    ----------------------------------------------------------------------------------
    -- constants for project
    ----------------------------------------------------------------------------------
    constant COMPONENT_WIDTH_C : integer := 8; -- width of component in a pixel

    ----------------------------------------------------------------------------------
    -- sliding window
    ----------------------------------------------------------------------------------
    constant WINDOW_SIZE_C : integer := 3; -- size of sliding window

    type row is array (0 to WINDOW_SIZE_C - 1) of unsigned(COMPONENT_WIDTH_C - 1 downto 0); -- row of sliding window
    type sliding_window is array (0 to WINDOW_SIZE_C - 1) of row;                           -- a 3x3 sliding window 

    constant WINDOW_DEFAULT_C : sliding_window := (others => (others => (others => '0'))); -- safe default for sliding window

    ----------------------------------------------------------------------------------
    -- kernel  
    ---------------------------------------------------------------------------------- 
    subtype kernel_coeff_t is integer range -2 to 2;                      -- kernel coefficient
    type kernel_row_t is array(0 to WINDOW_SIZE_C - 1) of kernel_coeff_t; -- kernel row 
    type kernel_t is array(0 to WINDOW_SIZE_C - 1) of kernel_row_t;       -- kernel  

    constant KERNEL_VERT_C : kernel_t := ((1, 2, 1), -- row y-2
    (0, 0, 0),                                       -- row y-1
    (-1, -2, -1));                                   -- row y
    constant KERNEL_HORZ_C : kernel_t := ((1, 0, -1),
    (2, 0, -2),
    (1, 0, -1));
end package pkg_edge_detection;
