----------------------------------------------------------------------------------
-- @file rbg_to_greyscale.vhd
--
-- @brief Converts an RGB pixel into a greyscale pixel using a weighted sum of
-- the red, green and blue components.
--
-- @details
-- greyscale = red * RED_GAIN_FRAC + green * GREEN_GAIN_FRAC + blue * BLUE_GAIN_FRAC
--
-- The gains are converted to fixed point at elaboration with COMPONENT_WIDTH
-- fractional bits, rounded to the nearest step. The products are summed at
-- double the width and the upper COMPONENT_WIDTH bits are kept (integer bits), so the 
-- result is integer with fraction bits truncated. 
--
-- The output is registered, one clock after the input. pixel_valid, x, y,
-- sof and eol pass through alongside the pixel so they stay aligned with it.
--
-- ready_i is the pipeline clock enable. When it is low, every output
-- register holds its value and the stage stalls. Reset does not depend on it.
--
-- @author Trevin Vaughan
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity rbg_to_greyscale is
    generic (
        COMPONENT_WIDTH : integer := 8;      -- bits per component in a pixel
        PIXEL_PER_CLOCK : integer := 1;      -- pixel per clock cycle  
        RED_GAIN_FRAC   : real    := 0.2989; -- fraction red gain 
        GREEN_GAIN_FRAC : real    := 0.5870; -- fraction green gain 
        BLUE_GAIN_FRAC  : real    := 0.1140  -- fraction blue gain 
    );
    port (
        --clock and reset
        clk_i  : in std_logic; -- axi stream clock
        rstn_i : in std_logic; -- axi stream reset

        -- pixel data
        r_i : in unsigned(COMPONENT_WIDTH - 1 downto 0); -- red channel of the pixel
        g_i : in unsigned(COMPONENT_WIDTH - 1 downto 0); -- green channel of the pixel
        b_i : in unsigned(COMPONENT_WIDTH - 1 downto 0); -- blue channel of the pixel

        -- upstream pixel control signals
        pixel_valid_i : in std_logic;             -- current pixel is valid 
        x_i           : in unsigned(15 downto 0); -- current x position the pixel 
        y_i           : in unsigned(15 downto 0); -- current y position the pixel 
        sof_i         : in std_logic;             -- start of frame
        eol_i         : in std_logic;             -- end of line

        -- downstream outputs
        greyscale_pixel_o : out unsigned(COMPONENT_WIDTH - 1 downto 0); -- grey scale pixel
        pixel_valid_o     : out std_logic;                              -- pixel data is valid for downstream 
        x_o               : out unsigned(15 downto 0);                  -- X pixel position
        y_o               : out unsigned(15 downto 0);                  -- Y pixel position
        sof_o             : out std_logic;                              -- start of frame
        eol_o             : out std_logic;                              -- end of line

        -- downstream input 
        ready_i : in std_logic -- downstream axi stream ready

    );
end rbg_to_greyscale;

architecture Behavioral of rbg_to_greyscale is

    function to_fixed(
        gain      : real;    -- floating point coefficient (0.0 to 1.0)
        bits      : integer; -- result bit width   
        frac_bits : integer  -- number of fractional bits
    ) return unsigned is
    begin
        -- Floating to fix point is: 
        -- fixed_point = floating_point * (2^fraction_bits)
        return to_unsigned(integer(gain * real(2 ** frac_bits)), bits);
    end function;

    constant RED_GAIN_FIX   : unsigned(COMPONENT_WIDTH - 1 downto 0) := to_fixed(RED_GAIN_FRAC, COMPONENT_WIDTH, COMPONENT_WIDTH);
    constant GREEN_GAIN_FIX : unsigned(COMPONENT_WIDTH - 1 downto 0) := to_fixed(GREEN_GAIN_FRAC, COMPONENT_WIDTH, COMPONENT_WIDTH);
    constant BLUE_GAIN_FIX  : unsigned(COMPONENT_WIDTH - 1 downto 0) := to_fixed(BLUE_GAIN_FRAC, COMPONENT_WIDTH, COMPONENT_WIDTH);
begin

    process (clk_i)
        -- intermediate sum for greyscale calculation
        variable sum : unsigned((COMPONENT_WIDTH * 2) - 1 downto 0);
    begin
        if rising_edge(clk_i) then
            if (rstn_i = '0') then
                greyscale_pixel_o <= (others => '0');
                pixel_valid_o     <= '0';
                x_o               <= (others => '0');
                y_o               <= (others => '0');
                sof_o             <= '0';
                eol_o             <= '0';

            elsif (ready_i = '1') then
                -- ready_i is the pipeline clock enable: when low, every
                -- output register holds its value and the stage stalls
                if (pixel_valid_i = '1') then
                    --greyscale = red_channel * red_gain + green_channel * green_gain + blue_channel * blue_gain
                    sum := (r_i * RED_GAIN_FIX) + (g_i * GREEN_GAIN_FIX) + (b_i * BLUE_GAIN_FIX);

                    -- drop the COMPONENT_WIDTH fractional bits, keep the integer greyscale value
                    greyscale_pixel_o <= resize(shift_right(sum, COMPONENT_WIDTH), COMPONENT_WIDTH);

                    --update control signals
                    pixel_valid_o <= pixel_valid_i;
                    x_o           <= x_i;
                    y_o           <= y_i;
                    sof_o         <= sof_i;
                    eol_o         <= eol_i;
                else
                    pixel_valid_o <= '0';
                end if;
            end if;
        end if;
    end process;
end Behavioral;
