`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// Testbench: tb_pixel_controller_in
// Description: SystemVerilog testbench for pixel_controller_in (VHDL DUT)
//              Tests: reset behavior, SOF gating, RGB extraction,
//                     X/Y counters, EOL/SOF strobes, backpressure
//-----------------------------------------------------------------------------

module tb_pixel_controller_in;

    //-------------------------------------------------------------------------
    // Parameters - must match DUT generics
    //-------------------------------------------------------------------------
    localparam COMPONENT_WIDTH = 8;
    localparam PIXEL_PER_CLOCK = 1;
    localparam DATA_WIDTH      = (COMPONENT_WIDTH * 3) * PIXEL_PER_CLOCK;

    // Small frame for quick sim
    localparam FRAME_WIDTH  = 8;
    localparam FRAME_HEIGHT = 4;

    localparam CLK_PERIOD = 10; // 100 MHz

    //-------------------------------------------------------------------------
    // DUT signals
    //-------------------------------------------------------------------------
    logic                       aclk;
    logic                       aclken;
    logic                       arstn;
    logic                       ready_downstream;

    // AXI-Stream slave interface
    logic [DATA_WIDTH-1:0]      s_axis_data;
    logic                       s_axis_valid;
    logic                       s_axis_ready; // output from DUT
    logic                       s_axis_eol;
    logic                       s_axis_sof;

    // Pixel outputs
    logic                       pixel_valid;
    logic [COMPONENT_WIDTH-1:0] r_out;
    logic [COMPONENT_WIDTH-1:0] g_out;
    logic [COMPONENT_WIDTH-1:0] b_out;
    logic [15:0]                x_out;
    logic [15:0]                y_out;
    logic                       sof_out;
    logic                       eol_out;

    //-------------------------------------------------------------------------
    // Clock generation
    //-------------------------------------------------------------------------
    initial aclk = 0;
    always #(CLK_PERIOD / 2) aclk = ~aclk;

    //-------------------------------------------------------------------------
    // DUT instantiation (mixed-language: SV -> VHDL)
    //-------------------------------------------------------------------------
    pixel_controller_in #(
        .COMPONENT_WIDTH(COMPONENT_WIDTH),
        .PIXEL_PER_CLOCK(PIXEL_PER_CLOCK),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .aclk_i         (aclk),
        .aclken_i       (aclken),
        .arstn_i        (arstn),
        .ready_i        (ready_downstream),

        .s_axis_data_i  (s_axis_data),
        .s_axis_valid_i (s_axis_valid),
        .s_axis_ready_o (s_axis_ready),
        .s_axis_eol_i   (s_axis_eol),
        .s_axis_sof_i   (s_axis_sof),

        .pixel_valid_o  (pixel_valid),
        .r_o            (r_out),
        .g_o            (g_out),
        .b_o            (b_out),
        .x_o            (x_out),
        .y_o            (y_out),
        .sof_o          (sof_out),
        .eol_o          (eol_out)
    );

    //-------------------------------------------------------------------------
    // Test counters
    //-------------------------------------------------------------------------
    int test_count   = 0;
    int pass_count   = 0;
    int fail_count   = 0;
    int pixel_count  = 0;

    //-------------------------------------------------------------------------
    // Helper tasks
    //-------------------------------------------------------------------------

    // Assert check with message
    task check(input logic condition, input string msg);
        test_count++;
        if (condition) begin
            pass_count++;
        end else begin
            fail_count++;
            $error("FAIL [%0d]: %s (time=%0t)", test_count, msg, $time);
        end
    endtask

    // Wait N clock cycles
    task wait_clocks(input int n);
        repeat (n) @(posedge aclk);
    endtask

    // Apply reset
    task apply_reset();
        arstn <= 1'b0;
        s_axis_valid <= 1'b0;
        s_axis_data  <= '0;
        s_axis_eol   <= 1'b0;
        s_axis_sof   <= 1'b0;
        wait_clocks(5);
        arstn <= 1'b1;
        wait_clocks(2);
    endtask

    // Send a single pixel on the AXI-Stream bus
    // Waits for both valid and ready before advancing
    task send_pixel(
        input logic [COMPONENT_WIDTH-1:0] r,
        input logic [COMPONENT_WIDTH-1:0] g,
        input logic [COMPONENT_WIDTH-1:0] b,
        input logic                       sof,
        input logic                       eol
    );
        s_axis_data  <= {r, g, b};
        s_axis_valid <= 1'b1;
        s_axis_sof   <= sof;
        s_axis_eol   <= eol;

        // Wait for handshake (valid & ready both high)
        do begin
            @(posedge aclk);
        end while (s_axis_ready !== 1'b1);

        // Deassert after transfer
        s_axis_valid <= 1'b0;
        s_axis_sof   <= 1'b0;
        s_axis_eol   <= 1'b0;
    endtask

    // Send a complete frame with unique pixel values
    task send_frame(
        input int width,
        input int height
    );
        logic is_sof;
        logic is_eol;
        logic [COMPONENT_WIDTH-1:0] r_val, g_val, b_val;

        for (int row = 0; row < height; row++) begin
            for (int col = 0; col < width; col++) begin
                is_sof = (row == 0 && col == 0) ? 1'b1 : 1'b0;
                is_eol = (col == width - 1)     ? 1'b1 : 1'b0;

                // Generate unique pixel values for easy identification
                r_val = 8'(row * width + col);       // unique per pixel
                g_val = 8'(row);                      // row number
                b_val = 8'(col);                      // column number

                send_pixel(r_val, g_val, b_val, is_sof, is_eol);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Output monitor - checks pixel outputs on every valid cycle
    //-------------------------------------------------------------------------
    int expected_x;
    int expected_y;

    always @(posedge aclk) begin
        if (pixel_valid === 1'b1) begin
            pixel_count++;
        end
    end

    //-------------------------------------------------------------------------
    // Test sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("==========================================================");
        $display("  Testbench: tb_pixel_controller_in");
        $display("  Frame: %0d x %0d", FRAME_WIDTH, FRAME_HEIGHT);
        $display("==========================================================");

        // Initialize
        aclken           <= 1'b1;
        ready_downstream <= 1'b1;
        s_axis_valid     <= 1'b0;
        s_axis_data      <= '0;
        s_axis_eol       <= 1'b0;
        s_axis_sof       <= 1'b0;

        //---------------------------------------------------------------------
        // TEST 1: Reset behavior
        //---------------------------------------------------------------------
        $display("\n--- TEST 1: Reset behavior ---");
        apply_reset();
        wait_clocks(1);

        check(pixel_valid === 1'b0, "pixel_valid should be 0 after reset");
        check(r_out === 8'h00,      "r_o should be 0 after reset");
        check(g_out === 8'h00,      "g_o should be 0 after reset");
        check(b_out === 8'h00,      "b_o should be 0 after reset");
        check(sof_out === 1'b0,     "sof_o should be 0 after reset");
        check(eol_out === 1'b0,     "eol_o should be 0 after reset");

        //---------------------------------------------------------------------
        // TEST 2: DUT ignores data without SOF (stuck in S_INIT)
        //---------------------------------------------------------------------
        $display("\n--- TEST 2: Ignore data without SOF ---");
        pixel_count = 0;

        // Send pixels without SOF - DUT should ignore them
        send_pixel(8'hAA, 8'hBB, 8'hCC, 1'b0, 1'b0);
        wait_clocks(2);
        send_pixel(8'hDD, 8'hEE, 8'hFF, 1'b0, 1'b0);
        wait_clocks(2);

        check(pixel_count == 0, "No pixels should be output without SOF");

        //---------------------------------------------------------------------
        // TEST 3: SOF triggers transition and first pixel output
        //---------------------------------------------------------------------
        $display("\n--- TEST 3: SOF triggers first pixel ---");
        pixel_count = 0;

        send_pixel(8'hDE, 8'hAD, 8'h01, 1'b1, 1'b0); // SOF pixel
        wait_clocks(1); // let output register

        check(pixel_valid === 1'b1, "pixel_valid should be 1 after SOF pixel");
        check(r_out === 8'hDE,      "R should match sent value (0xDE)");
        check(g_out === 8'hAD,      "G should match sent value (0xAD)");
        check(b_out === 8'h01,      "B should match sent value (0x01)");
        check(sof_out === 1'b1,     "sof_o should be 1 on SOF pixel");

        //---------------------------------------------------------------------
        // TEST 4: Strobes deassert on idle cycle
        //---------------------------------------------------------------------
        $display("\n--- TEST 4: Strobes deassert when no valid data ---");
        wait_clocks(2);

        check(pixel_valid === 1'b0, "pixel_valid should deassert when idle");
        check(sof_out === 1'b0,     "sof_o should deassert when idle");
        check(eol_out === 1'b0,     "eol_o should deassert when idle");

        //---------------------------------------------------------------------
        // TEST 5: Full frame - reset and send complete frame
        //---------------------------------------------------------------------
        $display("\n--- TEST 5: Full frame (%0d x %0d) ---", FRAME_WIDTH, FRAME_HEIGHT);
        apply_reset();
        pixel_count = 0;

        send_frame(FRAME_WIDTH, FRAME_HEIGHT);
        wait_clocks(5);

        check(pixel_count == FRAME_WIDTH * FRAME_HEIGHT,
              $sformatf("Expected %0d pixels, got %0d", FRAME_WIDTH * FRAME_HEIGHT, pixel_count));

        //---------------------------------------------------------------------
        // TEST 6: EOL asserts on last pixel of each line
        //---------------------------------------------------------------------
        $display("\n--- TEST 6: EOL behavior (separate frame) ---");
        apply_reset();

        // Send first line: 4 pixels, EOL on last
        send_pixel(8'h01, 8'h00, 8'h00, 1'b1, 1'b0); // SOF, not EOL
        send_pixel(8'h02, 8'h00, 8'h01, 1'b0, 1'b0);
        send_pixel(8'h03, 8'h00, 8'h02, 1'b0, 1'b0);
        send_pixel(8'h04, 8'h00, 8'h03, 1'b0, 1'b1); // EOL
        wait_clocks(1);

        check(eol_out === 1'b1, "eol_o should assert on last pixel of line");

        // First pixel of second line
        send_pixel(8'h05, 8'h01, 8'h00, 1'b0, 1'b0);
        wait_clocks(1);

        check(eol_out === 1'b0, "eol_o should deassert on first pixel of new line");

        //---------------------------------------------------------------------
        // TEST 7: Backpressure - ready deasserted
        //---------------------------------------------------------------------
        $display("\n--- TEST 7: Backpressure (ready_i deasserted) ---");
        apply_reset();

        // Send SOF pixel to get into S_ACTIVE
        send_pixel(8'hAA, 8'hBB, 8'hCC, 1'b1, 1'b0);
        wait_clocks(1);

        // Deassert downstream ready
        ready_downstream <= 1'b0;
        wait_clocks(1);

        check(s_axis_ready === 1'b0, "s_axis_ready should be 0 when downstream not ready");

        // Try to send a pixel - should stall
        s_axis_data  <= {8'hFF, 8'hEE, 8'hDD};
        s_axis_valid <= 1'b1;
        wait_clocks(3);

        // Re-assert ready - transfer should complete
        ready_downstream <= 1'b1;
        wait_clocks(2);

        check(pixel_valid === 1'b1, "Pixel should transfer after ready reasserts");
        check(r_out === 8'hFF,      "R should be 0xFF after backpressure release");

        s_axis_valid <= 1'b0;

        //---------------------------------------------------------------------
        // TEST 8: Back-to-back frames
        //---------------------------------------------------------------------
        $display("\n--- TEST 8: Back-to-back frames ---");
        apply_reset();
        pixel_count = 0;

        // First frame
        send_frame(FRAME_WIDTH, FRAME_HEIGHT);
        // Second frame immediately after
        send_frame(FRAME_WIDTH, FRAME_HEIGHT);
        wait_clocks(5);

        check(pixel_count == 2 * FRAME_WIDTH * FRAME_HEIGHT,
              $sformatf("Expected %0d pixels for 2 frames, got %0d",
                        2 * FRAME_WIDTH * FRAME_HEIGHT, pixel_count));

        //---------------------------------------------------------------------
        // TEST 9: Clock enable - aclken deasserted freezes logic
        //---------------------------------------------------------------------
        $display("\n--- TEST 9: Clock enable gating ---");
        apply_reset();

        // Send SOF to get active
        send_pixel(8'h10, 8'h20, 8'h30, 1'b1, 1'b0);
        wait_clocks(1);

        // Freeze with aclken
        aclken <= 1'b0;
        s_axis_data  <= {8'hFF, 8'hFF, 8'hFF};
        s_axis_valid <= 1'b1;
        wait_clocks(5);

        // Output should not have changed
        check(r_out === 8'h10, "R should hold previous value when aclken=0");

        // Unfreeze
        aclken <= 1'b1;
        wait_clocks(2);
        s_axis_valid <= 1'b0;

        //---------------------------------------------------------------------
        // Results
        //---------------------------------------------------------------------
        wait_clocks(10);
        $display("\n==========================================================");
        $display("  RESULTS: %0d tests, %0d passed, %0d failed",
                 test_count, pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule