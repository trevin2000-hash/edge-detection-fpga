----------------------------------------------------------------------------------
-- Engineer: Trevin Vaughan
-- 
-- Create Date: 02/21/2026 04:22:08 PM
-- Design Name: 
-- Module Name: pixel_controller_in - Behavioral
-- Project Name: edge_detection
-- Target Devices: Ultra96
-- Tool Versions: 2022.2
-- Description: This controls the pixel input for a video module
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity pixel_controller_in is
    generic (
        COMPONENT_WIDTH : integer := 8;                                      -- how many bits per component in the pixel 
        PIXEL_PER_CLOCK : integer := 1;                                      -- number of pixel per clock cycle  
        DATA_WIDTH      : integer := (COMPONENT_WIDTH * 3) * PIXEL_PER_CLOCK -- width of the axi stream
    );
    port (
        -- clocks 
        aclk_i   : in std_logic; -- axi stream clock
        aclken_i : in std_logic; -- axi stream clock enable
        arstn_i  : in std_logic; -- axi stream reset
        ready_i  : in std_logic; -- downstream axi stream ready

        -- AXI Slave Signals
        s_axis_data_i  : in std_logic_vector(DATA_WIDTH - 1 downto 0); -- pixel data
        s_axis_valid_i : in std_logic;                                 -- pixel data valid 
        s_axis_ready_o : out std_logic;                                -- ready for data signal
        s_axis_eol_i   : in std_logic;                                 -- End of the pixel line
        s_axis_sof_i   : in std_logic;                                 -- Start of the frame

        --outputs
        pixel_valid_o : out std_logic;                                      -- pixel data is valid for downstream 
        r_o           : out std_logic_vector(COMPONENT_WIDTH - 1 downto 0); -- red channel
        g_o           : out std_logic_vector(COMPONENT_WIDTH - 1 downto 0); -- green channel
        b_o           : out std_logic_vector(COMPONENT_WIDTH - 1 downto 0); -- blue channel
        x_o           : out unsigned(15 downto 0);                          -- X pixel position
        y_o           : out unsigned(15 downto 0);                          -- Y pixel position
        sof_o         : out std_logic;                                      -- start of frame
        eol_o         : out std_logic                                       -- end of line
    );
end entity;

architecture Behavioral of pixel_controller_in is
    type T_STATE is (S_INIT, S_ACTIVE);
    signal state : T_STATE;

    signal x_cnt : unsigned(15 downto 0);
    signal y_cnt : unsigned(15 downto 0);
begin

    -- need to update the s_axis_read_o immediately outside the clock process
    s_axis_ready_o <= ready_i when arstn_i = '1' else
        '0';

    -- clock process for pixel control
    process (aclk_i)
    begin
        if (rising_edge(aclk_i)) then
            --we are not ready for data during a reset
            -- update the pixel position
            x_o <= x_cnt;
            y_o <= y_cnt;

            --defaults:
            pixel_valid_o <= '0';
            sof_o         <= '0';
            eol_o         <= '0';

            if (arstn_i = '0') then
                -- reset everything here
                state         <= S_INIT;
                pixel_valid_o <= '0';
                r_o           <= (others => '0');
                g_o           <= (others => '0');
                b_o           <= (others => '0');
                x_cnt         <= (others => '0');
                y_cnt         <= (others => '0');
                sof_o         <= '0';
                eol_o         <= '0';

            elsif (aclken_i = '1') then
                case state is
                    when S_INIT =>

                        if (s_axis_valid_i = '1' and s_axis_sof_i = '1' and ready_i = '1') then
                            --clock in the valid data
                            r_o <= s_axis_data_i(3 * COMPONENT_WIDTH - 1 downto 2 * COMPONENT_WIDTH);
                            g_o <= s_axis_data_i(2 * COMPONENT_WIDTH - 1 downto COMPONENT_WIDTH);
                            b_o <= s_axis_data_i(COMPONENT_WIDTH - 1 downto 0);

                            x_cnt <= x_cnt + 1;
                            --send down stream control signals
                            pixel_valid_o <= '1';
                            sof_o         <= s_axis_sof_i;
                            eol_o         <= s_axis_eol_i;

                            state <= S_ACTIVE;
                        end if;

                    when S_ACTIVE =>

                        if (s_axis_valid_i = '1' and ready_i = '1') then
                            --clock in the valid data
                            r_o <= s_axis_data_i(3 * COMPONENT_WIDTH - 1 downto 2 * COMPONENT_WIDTH);
                            g_o <= s_axis_data_i(2 * COMPONENT_WIDTH - 1 downto COMPONENT_WIDTH);
                            b_o <= s_axis_data_i(COMPONENT_WIDTH - 1 downto 0);

                            --send down stream control signals
                            pixel_valid_o <= '1';
                            sof_o         <= s_axis_sof_i;
                            eol_o         <= s_axis_eol_i;

                            -- increment X pixel position for each pixel
                            -- reset to 0 at the End of the Line
                            x_cnt <= x_cnt + 1 when s_axis_eol_i = '0' else
                                (others => '0');

                            -- increment y pixel position for each line of pixels
                            -- reset to 0 at the Start of the frame
                            if s_axis_sof_i = '1' then
                                y_cnt <= (others => '0');
                            elsif s_axis_eol_i = '1' then
                                y_cnt <= y_cnt + 1;
                            end if;

                        end if;
                    when others =>
                        state <= S_INIT;
                end case;
            end if;
        end if;
    end process;
end architecture;
