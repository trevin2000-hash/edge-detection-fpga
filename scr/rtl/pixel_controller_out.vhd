---------------------------------------------------------------------------------
-- @file pixel_controller_out.vhd
--
-- @brief Takes one mono pixel per clock from the pipeline and outputs it as an
-- AXI4-Stream video master.
--
-- @details
-- The pixel is placed in the low COMPONENT_WIDTH bits of m_axis_data_o and the
-- remaining bits are zero, the mono layout of the AXI4-Stream video spec
-- (video format code 12, Y8 in the frame buffer write core). sof_i drives
-- tuser (m_axis_sof_o) and eol_i drives tlast (m_axis_eol_o).
--
-- The output is a single register stage. A beat stays in it unchanged until
-- downstream accepts it, with valid and ready both high, as the AXI4-Stream
-- protocol requires.
--
-- ready_o is the clock enable for the whole pipeline. It is high when the
-- output register is empty or its beat is accepted this clock, so the pipeline
-- only advances when the pixel it pushes out has somewhere to go. It depends
-- combinationally on m_axis_ready_i.
--
-- @author Trevin Vaughan
--
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
-- libraries 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

----------------------------------------------------------------------------------
-- entity
----------------------------------------------------------------------------------
entity pixel_controller_out is
    generic (
        COMPONENT_WIDTH : integer := 8;                                      -- how many bits per component in the pixel 
        PIXEL_PER_CLOCK : integer := 1;                                      -- number of pixel per clock cycle  
        DATA_WIDTH      : integer := (COMPONENT_WIDTH * 3) * PIXEL_PER_CLOCK -- greyscale (only one channel)
    );
    port (
        -- clocks 
        aclk_i  : in std_logic; -- axi stream clock
        arstn_i : in std_logic; -- axi stream reset

        -- upstream outputs
        ready_o : out std_logic;

        -- upstream inputs
        pixel_valid_i : in std_logic;                                      -- pixel data is valid 
        pixel_i       : in std_logic_vector(COMPONENT_WIDTH - 1 downto 0); -- Mono pixel
        sof_i         : in std_logic;                                      -- start of frame
        eol_i         : in std_logic;                                      -- end of line

        -- AXIS Master Signals
        m_axis_data_o  : out std_logic_vector(DATA_WIDTH - 1 downto 0); -- pixel data
        m_axis_valid_o : out std_logic;                                 -- pixel data valid 
        m_axis_ready_i : in std_logic;                                  -- ready for data signal
        m_axis_eol_o   : out std_logic;                                 -- End of the pixel line
        m_axis_sof_o   : out std_logic                                  -- Start of the frame

    );
end entity;

----------------------------------------------------------------------------------
-- architecture
----------------------------------------------------------------------------------
architecture Behavioral of pixel_controller_out is
    ----------------------------------------------------------------------------------
    -- types
    ----------------------------------------------------------------------------------

    ----------------------------------------------------------------------------------
    -- signals and registers
    ----------------------------------------------------------------------------------
    signal pipeline_ce_s   : std_logic; -- pipeline clock enable, also ready to upstream
    signal output_empty_s  : std_logic; -- output register holds no beat
    signal beat_accepted_s : std_logic; -- downstream takes the held beat this clock
    signal pixel_valid_r   : std_logic; -- output register holds a beat

begin
    ----------------------------------------------------------------------------------
    -- clock enable
    ----------------------------------------------------------------------------------
    -- advance when nothing is waiting in the output register or when the
    -- waiting beat is taken this clock
    output_empty_s  <= not pixel_valid_r;
    beat_accepted_s <= pixel_valid_r and m_axis_ready_i;
    pipeline_ce_s <= output_empty_s or beat_accepted_s;
    ready_o       <= pipeline_ce_s;

    m_axis_valid_o <= pixel_valid_r;
    ----------------------------------------------------------------------------------
    -- output register
    ----------------------------------------------------------------------------------
    process (aclk_i)
    begin
        if (rising_edge(aclk_i)) then
            if (arstn_i = '0') then
                -- reset
                pixel_valid_r <= '0';
                m_axis_eol_o  <= '0';
                m_axis_sof_o  <= '0';
                m_axis_data_o <= (others => '0');

            elsif (pipeline_ce_s = '1') then
                -- feed forward control signals 
                pixel_valid_r <= pixel_valid_i;
                m_axis_eol_o  <= eol_i;
                m_axis_sof_o  <= sof_i;

                -- place pixel right aligned 
                m_axis_data_o <= (COMPONENT_WIDTH - 1 downto 0 => pixel_i, others => '0');
            end if;
        end if;
    end process;

end architecture;
