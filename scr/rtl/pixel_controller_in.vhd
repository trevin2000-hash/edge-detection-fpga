----------------------------------------------------------------------------------
-- @file pixel_controller_in.vhd
--
-- @brief Receives an AXI4-Stream video input and converts it into per-pixel
-- signals for the edge detection pipeline: RGB components, pixel valid, x and y
-- position, start of frame and end of line.
--
-- @details
-- A beat is accepted when s_axis_valid_i and ready_i are both high and
-- aclken_i is high. Each accepted beat is split into r_o, g_o and b_o and
-- presented one clock later with pixel_valid_o high. Clocks without an
-- accepted beat output pixel_valid_o low.
--
-- The block uses a two-state machine to lock onto the start of a frame:
--
--   S_INIT   : Entered after reset. Waits for the first beat with s_axis_sof_i
--              high, which marks pixel (0, 0) of a frame. Beats before it are
--              accepted and discarded, so the pipeline never starts mid-frame.
--              The SOF beat is output at x = 0, y = 0 and the block moves to
--              S_ACTIVE.
--
--   S_ACTIVE : Outputs every accepted beat. x counts up by one per pixel and
--              returns to 0 after a beat with s_axis_eol_i high. y counts up by
--              one after each end of line and returns to 0 on start of frame.
--              sof_o and eol_o pass the input flags through, aligned with
--              their pixel.
--
-- x_o and y_o are the position of the pixel currently on r_o, g_o and b_o.
--
-- @author Trevin Vaughan
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

        -- downstream outputs
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
            -- update the pixel position
            x_o <= x_cnt;
            y_o <= y_cnt;

            if (arstn_i = '0') then
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
                        else
                            pixel_valid_o <= '0';
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
                            if s_axis_eol_i = '1' then
                                x_cnt <= (others => '0');
                            else
                                x_cnt <= x_cnt + 1;
                            end if;

                            -- increment y pixel position for each line of pixels
                            -- reset to 0 at the Start of the frame
                            if s_axis_sof_i = '1' then
                                y_cnt <= (others => '0');
                                y_o   <= (others => '0');
                            elsif s_axis_eol_i = '1' then
                                y_cnt <= y_cnt + 1;
                            end if;
                        else
                            pixel_valid_o <= '0';
                        end if;

                    when others =>
                        state <= S_INIT;
                end case;
            end if;
        end if;
    end process;
end architecture;
