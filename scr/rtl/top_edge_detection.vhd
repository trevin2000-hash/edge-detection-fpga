----------------------------------------------------------------------------------
-- @file top_edge_detection.vhd
--
-- @brief top level for the sobel edge detection pipeline.
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
use work.pkg_edge_detection.all;

----------------------------------------------------------------------------------
-- entity 
----------------------------------------------------------------------------------
entity top is
    generic (
        FRAME_WIDTH_G     : integer := 1920; -- 1080 by 1920 resolution
        AXIS_DATA_WIDTH_G : integer := 24    -- must equal AXIS_DATA_WIDTH_C, the block design cannot read the package
    );

    port (
        -- clocks 
        aclk    : in std_logic; -- axi stream clock
        aresetn : in std_logic; -- axi stream reset, active low

        -- AXIS Slave Signals
        s_axis_tdata  : in std_logic_vector(AXIS_DATA_WIDTH_G - 1 downto 0); -- RGB pixel data
        s_axis_tvalid : in std_logic;                                   -- pixel data valid 
        s_axis_tready : out std_logic;                                  -- ready for data signal
        s_axis_tuser  : in std_logic;                                   -- Start of the frame
        s_axis_tlast  : in std_logic;                                   -- End of the pixel line

        -- AXIS Master Signals
        m_axis_tdata  : out std_logic_vector(AXIS_DATA_WIDTH_G - 1 downto 0); -- Mono pixel data (Gradient Magnitude)
        m_axis_tvalid : out std_logic;                                   -- pixel data valid 
        m_axis_tready : in std_logic;                                    -- ready for data signal
        m_axis_tuser  : out std_logic;                                   -- Start of the frame
        m_axis_tlast  : out std_logic                                    -- End of the pixel line
    );
end entity;

----------------------------------------------------------------------------------
-- architecture
----------------------------------------------------------------------------------
architecture Behavioral of top is
    ----------------------------------------------------------------------------------
    --  Constants
    ----------------------------------------------------------------------------------

    ----------------------------------------------------------------------------------
    --  pixel control out signals 
    ----------------------------------------------------------------------------------
    signal ready_s : std_logic;

    ----------------------------------------------------------------------------------
    -- pixel control in signals 
    ----------------------------------------------------------------------------------
    signal rgb_valid_s      : std_logic;
    signal r_s              : std_logic_vector(COMPONENT_WIDTH_C - 1 downto 0);
    signal g_s              : std_logic_vector(COMPONENT_WIDTH_C - 1 downto 0);
    signal b_s              : std_logic_vector(COMPONENT_WIDTH_C - 1 downto 0);
    signal x_rgb_position_s : unsigned(15 downto 0);
    signal y_rbg_position_s : unsigned(15 downto 0);
    signal sof_rgb_s        : std_logic;
    signal eol_rgb_s        : std_logic;

    ----------------------------------------------------------------------------------
    -- RGB to greyscale signals 
    ----------------------------------------------------------------------------------    
    signal greyscale_s            : unsigned(COMPONENT_WIDTH_C - 1 downto 0);
    signal greyscale_valid_s      : std_logic;
    signal x_greyscale_position_s : unsigned(15 downto 0);
    signal y_greyscale_position_s : unsigned(15 downto 0);
    signal sof_greyscale_s        : std_logic;
    signal eol_greyscale_s        : std_logic;
    signal window_s               : sliding_window;
    signal window_valid_s         : std_logic;
    signal window_full_s          : std_logic;
    signal sof_window_s           : std_logic;
    signal eol_window_s           : std_logic;
    signal mag_valid_s            : std_logic;
    signal mag_s                  : unsigned(COMPONENT_WIDTH_C - 1 downto 0);
    signal sof_mag_s              : std_logic;
    signal eol_mag_s              : std_logic;

    ----------------------------------------------------------------------------------
    -- sobel filter signals
    ----------------------------------------------------------------------------------

begin

    ----------------------------------------------------------------------------------
    -- combination logic
    ----------------------------------------------------------------------------------

    -- the stream width is a generic only so the block design can size the ports;
    -- every stage is built from AXIS_DATA_WIDTH_C, so stop on a mismatch
    assert AXIS_DATA_WIDTH_G = AXIS_DATA_WIDTH_C
        report "AXIS_DATA_WIDTH_G does not match AXIS_DATA_WIDTH_C in pkg_edge_detection"
        severity failure;

    ----------------------------------------------------------------------------------
    -- Pixel Control in
    ----------------------------------------------------------------------------------
    pixel_controller_in_inst : entity work.pixel_controller_in
        generic map(
            COMPONENT_WIDTH => COMPONENT_WIDTH_C,
            PIXEL_PER_CLOCK => PIXEL_PER_CLOCK_C,
            DATA_WIDTH      => AXIS_DATA_WIDTH_G
        )
        port map
        (
            aclk_i         => aclk,
            arstn_i        => aresetn,
            ready_i        => ready_s,
            s_axis_data_i  => s_axis_tdata,
            s_axis_valid_i => s_axis_tvalid,
            s_axis_ready_o => s_axis_tready,
            s_axis_sof_i   => s_axis_tuser,
            s_axis_eol_i   => s_axis_tlast,
            pixel_valid_o  => rgb_valid_s,
            r_o            => r_s,
            g_o            => g_s,
            b_o            => b_s,
            x_o            => x_rgb_position_s,
            y_o            => y_rbg_position_s,
            sof_o          => sof_rgb_s,
            eol_o          => eol_rgb_s
        );

    ----------------------------------------------------------------------------------
    -- rgb to greyscale
    ----------------------------------------------------------------------------------
    rgb_to_greyscale_inst : entity work.rgb_to_greyscale
        generic map(
            COMPONENT_WIDTH => COMPONENT_WIDTH_C,
            PIXEL_PER_CLOCK => PIXEL_PER_CLOCK_C
        )
        port map
        (
            clk_i             => aclk,
            rstn_i            => aresetn,
            r_i               => unsigned(r_s),
            g_i               => unsigned(g_s),
            b_i               => unsigned(b_s),
            pixel_valid_i     => rgb_valid_s,
            x_i               => x_rgb_position_s,
            y_i               => y_rbg_position_s,
            sof_i             => sof_rgb_s,
            eol_i             => eol_rgb_s,
            greyscale_pixel_o => greyscale_s,
            pixel_valid_o     => greyscale_valid_s,
            x_o               => x_greyscale_position_s,
            y_o               => y_greyscale_position_s,
            sof_o             => sof_greyscale_s,
            eol_o             => eol_greyscale_s,
            ready_i           => ready_s
        );

    ----------------------------------------------------------------------------------
    -- pixel line buffer
    ----------------------------------------------------------------------------------
    pixel_line_buff_inst : entity work.pixel_line_buff
        generic map(
            COMPONENT_WIDTH_G => COMPONENT_WIDTH_C,
            FRAME_WIDTH_G     => FRAME_WIDTH_G
        )
        port map
        (
            clk_i             => aclk,
            rstn_i            => aresetn,
            greyscale_pixel_i => greyscale_s,
            pixel_valid_i     => greyscale_valid_s,
            x_i               => x_greyscale_position_s,
            y_i               => y_greyscale_position_s,
            sof_i             => sof_greyscale_s,
            eol_i             => eol_greyscale_s,
            window_o          => window_s,
            window_valid_o    => window_valid_s,
            window_full_o     => window_full_s,
            sof_o             => sof_window_s,
            eol_o             => eol_window_s,
            ready_i           => ready_s
        );
    ----------------------------------------------------------------------------------
    -- sobel filter
    ----------------------------------------------------------------------------------
    sobel_filter_inst : entity work.sobel_filter
        generic map(
            FRAME_WIDTH_G => FRAME_WIDTH_G
        )
        port map
        (
            clk_i          => aclk,
            rstn_i         => aresetn,
            window_i       => window_s,
            window_valid_i => window_valid_s,
            window_full_i  => window_full_s,
            sof_i          => sof_window_s,
            eol_i          => eol_window_s,
            mag_valid_o    => mag_valid_s,
            mag_o          => mag_s,
            sof_o          => sof_mag_s,
            eol_o          => eol_mag_s,
            ready_i        => ready_s
        );

    ----------------------------------------------------------------------------------
    -- pixel control out
    ----------------------------------------------------------------------------------
    pixel_controller_out_inst : entity work.pixel_controller_out
        generic map(
            COMPONENT_WIDTH => COMPONENT_WIDTH_C,
            PIXEL_PER_CLOCK => PIXEL_PER_CLOCK_C,
            DATA_WIDTH      => AXIS_DATA_WIDTH_G
        )
        port map
        (
            aclk_i         => aclk,
            arstn_i        => aresetn,
            ready_o        => ready_s,
            pixel_valid_i  => mag_valid_s,
            pixel_i        => std_logic_vector(mag_s),
            sof_i          => sof_mag_s,
            eol_i          => eol_mag_s,
            m_axis_data_o  => m_axis_tdata,
            m_axis_valid_o => m_axis_tvalid,
            m_axis_ready_i => m_axis_tready,
            m_axis_eol_o   => m_axis_tlast,
            m_axis_sof_o   => m_axis_tuser
        );

end architecture;
