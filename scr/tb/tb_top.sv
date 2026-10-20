//-----------------------------------------------------------------------------
// @file: tb_top.sv
//
// @brief: System-level testbench for top, the full edge detection pipeline.
//
// @details: Loads top_level_in_test_vector.txt and top_level_out_test_vector.txt,
// both from matlab_prototypes/top_level_test_vectors.m, then streams the input
// frame through the DUT in each of these scenarios:
//
//   clean                 : no stalls, one frame
//   output back-pressure  : the sink drops tready at random
//   input gaps            : the source drops tvalid at random between beats
//   both                  : random input gaps and random back-pressure together
//   back to back          : two frames with no gap between them
//   back to back with gap : two frames with idle clocks between them
//   mid-frame start       : after reset, the end of a frame without tuser, then
//                           a full frame; the DUT must drop the partial frame
//   reset mid-frame       : half a frame, a reset, then a full frame
//
// The check is pixel for pixel, not clock for clock. The monitor counts x on
// every output beat and advances y on tlast, then compares the pixel, its
// counted position, tuser and tlast with the expected pixel for that beat.
// Latency and stalls do not change the result, only the order of the beats.
// A reset restarts the expected frame, because the DUT drops everything in
// flight.
//
// An assertion checks the AXI4-Stream rule on the output in every scenario: a
// beat offered without tready stays valid and unchanged until it is taken.
//
// The testbench drives its signals DRIVE_DELAY after the rising edge and
// samples on the falling edge, so nothing it does races the rising edge the
// DUT uses. A beat transfers at a rising edge when valid and ready are both
// high, so both are sampled on the falling edge before it.
//
// The frame size comes from the vectors, so a smaller frame from the MATLAB
// script runs without changes here and finishes much faster.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_top;
    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    localparam real CLK_PERIOD      = 4.0;                 // 250 MHz
    localparam real DRIVE_DELAY     = 1.0;                 // drive this long after the rising edge
    localparam int  COMPONENT_WIDTH = 8;                   // must match COMPONENT_WIDTH_C in pkg_edge_detection
    localparam int  DATA_WIDTH      = COMPONENT_WIDTH * 3; // must match AXIS_DATA_WIDTH_C in pkg_edge_detection
    localparam int  HEAVY_PCT       = 50;                  // percent of clocks valid or ready is high, heavy stalls
    localparam int  LIGHT_PCT       = 75;                  // percent of clocks valid or ready is high, light stalls
    localparam int  FRAME_GAP       = 100;                 // idle clocks between frames in the gap scenario
    localparam int  MAX_FAILS       = 20;                  // stop early on a systematic failure
    localparam int  STALL_TIMEOUT   = 10000;               // clocks without an output beat while waiting

    // Vivado would not allow a relative path, so change these for your installation
    string in_vector_path  = "/home/petalinux/Documents/edge-detection-fpga/matlab_prototypes/top_level_in_test_vector.txt";
    string out_vector_path = "/home/petalinux/Documents/edge-detection-fpga/matlab_prototypes/top_level_out_test_vector.txt";

    //-------------------------------------------------------------------------
    // Signals
    //-------------------------------------------------------------------------
    logic aclk  = 1'b0;
    logic arstn = 1'b0;

    // AXI4-Stream into the DUT, driven by the source
    logic [DATA_WIDTH-1:0] s_axis_tdata  = '0;
    logic                  s_axis_tvalid = 1'b0;
    logic                  s_axis_tready;
    logic                  s_axis_tuser  = 1'b0;
    logic                  s_axis_tlast  = 1'b0;

    // AXI4-Stream out of the DUT, tready driven by the sink
    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic                  m_axis_tvalid;
    logic                  m_axis_tready = 1'b1;
    logic                  m_axis_tuser;
    logic                  m_axis_tlast;

    // test vectors, loaded once at the start
    logic [DATA_WIDTH-1:0] in_pixel[$];  // packed RGB input, raster order
    int                    in_x[$];
    int                    in_y[$];
    int                    exp_pixel[$]; // expected output, raster order
    int                    exp_x[$];
    int                    exp_y[$];
    int                    frame_pixels; // pixels per frame
    int                    frame_width;  // pixels per line

    // stall settings, changed by each scenario
    int in_valid_pct  = 100; // percent of clocks the source offers a beat
    int out_ready_pct = 100; // percent of clocks the sink is ready

    // results, shared by the scenarios, the monitor and the summary
    int beats_sent        = 0;
    int beats_checked     = 0;
    int beats_failed      = 0;
    int frames_checked    = 0;
    int protocol_failures = 0;
    int exp_index         = 0; // expected pixel for the next output beat

    //-------------------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------------------
    top dut (
        .aclk          (aclk),
        .aresetn       (arstn),

        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tuser  (s_axis_tuser),
        .s_axis_tlast  (s_axis_tlast),

        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tuser  (m_axis_tuser),
        .m_axis_tlast  (m_axis_tlast)
    );

    //-------------------------------------------------------------------------
    // Clock
    //-------------------------------------------------------------------------
    always #(CLK_PERIOD / 2) aclk = ~aclk;

    //-------------------------------------------------------------------------
    // Protocol check
    //-------------------------------------------------------------------------
    // a beat offered without tready must stay valid and unchanged until it is taken
    output_beat_held : assert property (
        @(posedge aclk) disable iff (arstn !== 1'b1)
        (m_axis_tvalid && !m_axis_tready) |=>
            (m_axis_tvalid && $stable({m_axis_tdata, m_axis_tuser, m_axis_tlast}))
    ) else begin
        protocol_failures++;
        $error("output beat dropped or changed while waiting on tready");
    end

    //-------------------------------------------------------------------------
    // Helper tasks
    //-------------------------------------------------------------------------

    // Read both vector files and work out the frame size
    task automatic load_vectors();
        int                    fd;
        string                 header;
        logic [DATA_WIDTH-1:0] pixel;
        int                    value;
        int                    x;
        int                    y;

        fd = $fopen(in_vector_path, "r");
        if (fd == 0) $fatal(1, "cannot open %s", in_vector_path);
        void'($fgets(header, fd)); // skip the header line
        while ($fscanf(fd, "%h %d %d", pixel, x, y) == 3) begin
            in_pixel.push_back(pixel);
            in_x.push_back(x);
            in_y.push_back(y);
        end
        $fclose(fd);

        fd = $fopen(out_vector_path, "r");
        if (fd == 0) $fatal(1, "cannot open %s", out_vector_path);
        void'($fgets(header, fd)); // skip the header line
        while ($fscanf(fd, "%d %d %d", value, x, y) == 3) begin
            exp_pixel.push_back(value);
            exp_x.push_back(x);
            exp_y.push_back(y);
        end
        $fclose(fd);

        // both files describe the same frame, pixel for pixel
        if (in_pixel.size() == 0 || in_pixel.size() != exp_pixel.size()) begin
            $fatal(1, "vector files differ: %0d input pixels, %0d expected pixels",
                   in_pixel.size(), exp_pixel.size());
        end

        frame_pixels = in_pixel.size();
        frame_width  = 0;
        foreach (in_x[i]) begin
            if (in_x[i] + 1 > frame_width) frame_width = in_x[i] + 1;
        end

        $display("tb_top: loaded a %0d x %0d frame", frame_width, frame_pixels / frame_width);
    endtask

    // Hold reset for a few clocks, release it just after a rising edge
    task automatic reset_dut();
        s_axis_tvalid = 1'b0;
        arstn         = 1'b0;
        repeat (4) @(posedge aclk);
        #(DRIVE_DELAY);
        arstn = 1'b1;
    endtask

    // Send frame pixels first to first + count - 1, holding each beat until it
    // is accepted. The source pauses at random between beats.
    task automatic send_pixels(input int first, input int count);
        bit beat_accepted;

        for (int i = first; i < first + count; i++) begin
            // random gap before this beat
            while ($urandom_range(1, 100) > in_valid_pct) begin
                s_axis_tvalid = 1'b0;
                @(posedge aclk);
                #(DRIVE_DELAY);
            end

            s_axis_tdata  = in_pixel[i];
            s_axis_tuser  = (in_x[i] == 0 && in_y[i] == 0); // start of frame
            s_axis_tlast  = (in_x[i] == frame_width - 1);   // end of line
            s_axis_tvalid = 1'b1;

            // hold the beat until a rising edge where tready is high
            do begin
                @(negedge aclk);
                beat_accepted = s_axis_tready;
                @(posedge aclk);
                #(DRIVE_DELAY);
            end while (!beat_accepted);

            beats_sent++;
        end

        s_axis_tvalid = 1'b0;
        s_axis_tuser  = 1'b0;
        s_axis_tlast  = 1'b0;
    endtask

    // Wait until the monitor has checked target_frames complete frames
    task automatic wait_for_frames(input int target_frames);
        int idle_clocks;
        int last_checked;

        idle_clocks  = 0;
        last_checked = beats_checked;

        while (frames_checked < target_frames) begin
            @(posedge aclk);

            if (beats_checked != last_checked) begin
                idle_clocks  = 0;
                last_checked = beats_checked;
            end else begin
                idle_clocks++;
                if (idle_clocks > STALL_TIMEOUT) begin
                    report();
                    $fatal(1, "no output beat for %0d clocks while waiting for frame %0d",
                           STALL_TIMEOUT, target_frames);
                end
            end
        end

        #(DRIVE_DELAY);
    endtask

    // Print the totals and the overall result
    function automatic void report();
        bit pass;

        pass = (frames_checked > 0) && (beats_failed == 0) && (protocol_failures == 0)
            && (exp_index == 0);

        $display("tb_top: %0d beats sent, %0d frames and %0d beats checked, %0d failed beats, %0d protocol failures",
                 beats_sent, frames_checked, beats_checked, beats_failed, protocol_failures);

        // the output stopped part way through a frame, or sent extra beats
        if (exp_index != 0) begin
            $display("tb_top: output ended part way through a frame, at pixel %0d", exp_index);
        end

        $display(pass ? "tb_top: PASS" : "tb_top: FAIL");
    endfunction

    //-------------------------------------------------------------------------
    // Scenarios
    //-------------------------------------------------------------------------

    // Send whole frames with the given stall settings and wait for them all
    task automatic run_frames(input string name, input int valid_pct, input int ready_pct,
                              input int num_frames, input int gap_clocks);
        int target_frames;

        in_valid_pct  = valid_pct;
        out_ready_pct = ready_pct;
        target_frames = frames_checked + num_frames;

        for (int f = 0; f < num_frames; f++) begin
            send_pixels(0, frame_pixels);

            // idle clocks between frames, none after the last one
            if (f < num_frames - 1) begin
                repeat (gap_clocks) begin
                    @(posedge aclk);
                    #(DRIVE_DELAY);
                end
            end
        end

        wait_for_frames(target_frames);
        $display("tb_top: %s done, %0d failed beats so far", name, beats_failed);
    endtask

    // After reset, send the end of a frame without its start, then a full frame
    task automatic run_mid_frame_start(input string name, input int pct);
        int partial_pixels;
        int target_frames;

        in_valid_pct  = pct;
        out_ready_pct = pct;

        // only right after reset does pixel_controller_in wait for a start of frame
        reset_dut();
        target_frames = frames_checked + 1;

        // the last lines of a frame, starting part way along a line, so no tuser
        partial_pixels = 2 * frame_width + frame_width / 2;
        send_pixels(frame_pixels - partial_pixels, partial_pixels);

        // the DUT must drop the partial frame and output only this one
        send_pixels(0, frame_pixels);

        wait_for_frames(target_frames);
        $display("tb_top: %s done, %0d failed beats so far", name, beats_failed);
    endtask

    // Send half a frame, reset with beats still in the pipeline, then a full frame
    task automatic run_reset_mid_frame(input string name, input int pct);
        int target_frames;

        in_valid_pct  = pct;
        out_ready_pct = pct;

        send_pixels(0, frame_pixels / 2);
        reset_dut();

        // the monitor restarts its expected frame on reset, so only this frame counts
        target_frames = frames_checked + 1;
        send_pixels(0, frame_pixels);

        wait_for_frames(target_frames);
        $display("tb_top: %s done, %0d failed beats so far", name, beats_failed);
    endtask

    //-------------------------------------------------------------------------
    // Main
    //-------------------------------------------------------------------------
    initial begin
        load_vectors();
        reset_dut();

        run_frames("clean",                 100,       100,       1, 0);
        run_frames("output back-pressure",  100,       HEAVY_PCT, 1, 0);
        run_frames("input gaps",            HEAVY_PCT, 100,       1, 0);
        run_frames("both",                  HEAVY_PCT, HEAVY_PCT, 1, 0);
        run_frames("back to back",          100,       100,       2, 0);
        run_frames("back to back with gap", 100,       100,       2, FRAME_GAP);
        run_mid_frame_start("mid-frame start", LIGHT_PCT);
        run_reset_mid_frame("reset mid-frame", LIGHT_PCT);

        // a few more clocks so the monitor catches any extra beats
        repeat (20) @(posedge aclk);

        report();
        $finish;
    end

    //-------------------------------------------------------------------------
    // Sink: tready high on a random share of clocks
    //-------------------------------------------------------------------------
    initial begin
        forever begin
            @(posedge aclk);
            #(DRIVE_DELAY);
            m_axis_tready = ($urandom_range(1, 100) <= out_ready_pct);
        end
    end

    //-------------------------------------------------------------------------
    // Monitor: check every output beat against the expected frame
    //-------------------------------------------------------------------------
    initial begin
        int                         x_out;
        int                         y_out;
        bit                         tuser_exp;
        bit                         tlast_exp;
        logic [COMPONENT_WIDTH-1:0] pixel_out;
        bit                         beat_ok;

        x_out = 0;
        y_out = 0;

        forever begin
            @(negedge aclk);

            // reset drops everything in flight, so expect a fresh frame afterwards
            if (arstn !== 1'b1) begin
                exp_index = 0;
                x_out     = 0;
                y_out     = 0;
                continue;
            end

            // no transfer at the coming rising edge
            if (!(m_axis_tvalid === 1'b1 && m_axis_tready === 1'b1)) continue;

            // compare this beat with the expected pixel at the same position
            tuser_exp = (exp_x[exp_index] == 0 && exp_y[exp_index] == 0);
            tlast_exp = (exp_x[exp_index] == frame_width - 1);
            pixel_out = m_axis_tdata[COMPONENT_WIDTH-1:0];

            beat_ok = (x_out == exp_x[exp_index]) && (y_out == exp_y[exp_index])
                   && (pixel_out === COMPONENT_WIDTH'(exp_pixel[exp_index]))
                   && (m_axis_tdata[DATA_WIDTH-1:COMPONENT_WIDTH] === '0)
                   && (m_axis_tuser === tuser_exp)
                   && (m_axis_tlast === tlast_exp);

            beats_checked++;
            if (!beat_ok) begin
                beats_failed++;
                $error("beat %0d: expected pixel %0d at (%0d, %0d) tuser %0b tlast %0b, got pixel %0d at counted (%0d, %0d) tuser %0b tlast %0b, tdata 0x%0h",
                       beats_checked, exp_pixel[exp_index], exp_x[exp_index], exp_y[exp_index],
                       tuser_exp, tlast_exp, pixel_out, x_out, y_out,
                       m_axis_tuser, m_axis_tlast, m_axis_tdata);

                if (beats_failed >= MAX_FAILS) begin
                    report();
                    $fatal(1, "stopping after %0d failed beats", MAX_FAILS);
                end
            end

            // position of the next beat: x counts every beat, tlast starts a new line
            if (m_axis_tlast === 1'b1) begin
                x_out = 0;
                y_out++;
            end else begin
                x_out++;
            end

            // after the last pixel, the next beat starts a new frame
            exp_index++;
            if (exp_index == frame_pixels) begin
                exp_index = 0;
                x_out     = 0;
                y_out     = 0;
                frames_checked++;
            end
        end
    end

endmodule
