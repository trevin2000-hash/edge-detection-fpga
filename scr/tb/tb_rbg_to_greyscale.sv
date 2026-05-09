`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// Testbench: tb_rbg_to_greyscale
// Description: SystemVerilog testbench for rbg_to_greyscale (VHDL DUT)
//              Tests: reset, grayscale math, strobe deassertion,
//                     control signal passthrough, valid gating
//-----------------------------------------------------------------------------

module tb_rbg_to_greyscale;

  //-------------------------------------------------------------------------
  // Parameters - must match DUT generics
  //-------------------------------------------------------------------------
  localparam COMPONENT_WIDTH = 8;
  localparam PIXEL_PER_CLOCK = 1;
  localparam real RED_GAIN   = 0.2989;
  localparam real GREEN_GAIN = 0.5870;
  localparam real BLUE_GAIN  = 0.1140;

  // Fixed-point gain constants (must match DUT elaboration)
  localparam int RED_FIX   = int'(RED_GAIN   * (2.0 ** COMPONENT_WIDTH));  // 76
  localparam int GREEN_FIX = int'(GREEN_GAIN * (2.0 ** COMPONENT_WIDTH));  // 150
  localparam int BLUE_FIX  = int'(BLUE_GAIN  * (2.0 ** COMPONENT_WIDTH));  // 29

  localparam CLK_PERIOD = 10;

  //-------------------------------------------------------------------------
  // DUT signals
  //-------------------------------------------------------------------------
  logic                       clk;
  logic                       rstn;

  logic [COMPONENT_WIDTH-1:0] r_in;
  logic [COMPONENT_WIDTH-1:0] g_in;
  logic [COMPONENT_WIDTH-1:0] b_in;

  logic                       pixel_valid_in;
  logic [15:0]                x_in;
  logic [15:0]                y_in;
  logic                       sof_in;
  logic                       eol_in;

  logic [COMPONENT_WIDTH-1:0] greyscale_out;
  logic                       pixel_valid_out;
  logic [15:0]                x_out;
  logic [15:0]                y_out;
  logic                       sof_out;
  logic                       eol_out;

  //-------------------------------------------------------------------------
  // Clock generation
  //-------------------------------------------------------------------------
  initial
    clk = 0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  //-------------------------------------------------------------------------
  // DUT instantiation (mixed-language: SV -> VHDL)
  //-------------------------------------------------------------------------
  rbg_to_greyscale #(
                     .COMPONENT_WIDTH(COMPONENT_WIDTH),
                     .PIXEL_PER_CLOCK(PIXEL_PER_CLOCK),
                     .RED_GAIN_FRAC(RED_GAIN),
                     .GREEN_GAIN_FRAC(GREEN_GAIN),
                     .BLUE_GAIN_FRAC(BLUE_GAIN)
                   ) dut (
                     .clk_i  (clk),
                     .rstn_i (rstn),

                     .r_i (r_in),
                     .g_i (g_in),
                     .b_i (b_in),

                     .pixel_valid_i (pixel_valid_in),
                     .x_i           (x_in),
                     .y_i           (y_in),
                     .sof_i         (sof_in),
                     .eol_i         (eol_in),

                     .greyscale_pixel_o (greyscale_out),
                     .pixel_valid_o     (pixel_valid_out),
                     .x_o               (x_out),
                     .y_o               (y_out),
                     .sof_o             (sof_out),
                     .eol_o             (eol_out)
                   );

  //-------------------------------------------------------------------------
  // Test counters
  //-------------------------------------------------------------------------
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  //-------------------------------------------------------------------------
  // Helper tasks
  //-------------------------------------------------------------------------

  task check(input logic condition, input string msg);
    test_count++;
    if (condition)
    begin
      pass_count++;
    end
    else
    begin
      fail_count++;
      $error("FAIL [%0d]: %s (time=%0t)", test_count, msg, $time);
    end
  endtask

  task wait_clocks(input int n);
    repeat (n) @(posedge clk);
  endtask

  task apply_reset();
    rstn <= 1'b0;
    pixel_valid_in <= 1'b0;
    r_in  <= '0;
    g_in  <= '0;
    b_in  <= '0;
    x_in  <= '0;
    y_in  <= '0;
    sof_in <= 1'b0;
    eol_in <= 1'b0;
    wait_clocks(5);
    rstn <= 1'b1;
    wait_clocks(2);
  endtask

  // Calculate expected greyscale value matching DUT fixed-point math
  function automatic logic [COMPONENT_WIDTH-1:0] expected_grey(
      input logic [COMPONENT_WIDTH-1:0] r,
      input logic [COMPONENT_WIDTH-1:0] g,
      input logic [COMPONENT_WIDTH-1:0] b
    );
    int sum;
    sum = (int'(r) * RED_FIX) + (int'(g) * GREEN_FIX) + (int'(b) * BLUE_FIX);
    return (sum >> COMPONENT_WIDTH) & {COMPONENT_WIDTH{1'b1}};
  endfunction

  // Send a pixel and check the output one clock later
  task send_and_check(
      input logic [COMPONENT_WIDTH-1:0] r,
      input logic [COMPONENT_WIDTH-1:0] g,
      input logic [COMPONENT_WIDTH-1:0] b,
      input logic [15:0]                x,
      input logic [15:0]                y,
      input logic                       sof,
      input logic                       eol,
      input string                      label
    );
    logic [COMPONENT_WIDTH-1:0] exp;
    exp = expected_grey(r, g, b);

    // Drive inputs
    r_in  <= r;
    g_in  <= g;
    b_in  <= b;
    x_in  <= x;
    y_in  <= y;
    sof_in <= sof;
    eol_in <= eol;
    pixel_valid_in <= 1'b1;
    @(posedge clk);

    // Deassert valid
    pixel_valid_in <= 1'b0;
    @(posedge clk);

    // Check outputs (one clock latency)
    check(pixel_valid_out === 1'b1,
          $sformatf("%s: pixel_valid_o should be 1", label));
    check(greyscale_out === exp,
          $sformatf("%s: grey expected %0d, got %0d (R=%0d G=%0d B=%0d)",
                    label, exp, greyscale_out, r, g, b));
    check(x_out === x,
          $sformatf("%s: x expected %0d, got %0d", label, x, x_out));
    check(y_out === y,
          $sformatf("%s: y expected %0d, got %0d", label, y, y_out));
    check(sof_out === sof,
          $sformatf("%s: sof expected %b, got %b", label, sof, sof_out));
    check(eol_out === eol,
          $sformatf("%s: eol expected %b, got %b", label, eol, eol_out));
  endtask

  //-------------------------------------------------------------------------
  // Test sequence
  //-------------------------------------------------------------------------
  initial
  begin
    logic [COMPONENT_WIDTH-1:0] grey_red, grey_green;

    $display("==========================================================");
    $display("  Testbench: tb_rbg_to_greyscale");
    $display("  Fixed-point gains: R=%0d  G=%0d  B=%0d",
             RED_FIX, GREEN_FIX, BLUE_FIX);
    $display("==========================================================");

    //---------------------------------------------------------------------
    // TEST 1: Reset behavior
    //---------------------------------------------------------------------
    $display("\n--- TEST 1: Reset behavior ---");
    apply_reset();

    check(greyscale_out === '0,  "greyscale should be 0 after reset");
    check(pixel_valid_out === 1'b0, "pixel_valid should be 0 after reset");
    check(x_out === '0,          "x should be 0 after reset");
    check(y_out === '0,          "y should be 0 after reset");
    check(sof_out === 1'b0,      "sof should be 0 after reset");
    check(eol_out === 1'b0,      "eol should be 0 after reset");

    //---------------------------------------------------------------------
    // TEST 2: White pixel (255, 255, 255) → ~254
    //---------------------------------------------------------------------
    $display("\n--- TEST 2: White pixel ---");
    send_and_check(
        .r(8'd255), .g(8'd255), .b(8'd255),
        .x(16'd0), .y(16'd0),
        .sof(1'b1), .eol(1'b0),
        .label("White")
      );

    //---------------------------------------------------------------------
    // TEST 3: Black pixel (0, 0, 0) → 0
    //---------------------------------------------------------------------
    $display("\n--- TEST 3: Black pixel ---");
    send_and_check(
        .r(8'd0), .g(8'd0), .b(8'd0),
        .x(16'd1), .y(16'd0),
        .sof(1'b0), .eol(1'b0),
        .label("Black")
      );

    //---------------------------------------------------------------------
    // TEST 4: Pure red (255, 0, 0) → 76*255 >> 8 = 75
    //---------------------------------------------------------------------
    $display("\n--- TEST 4: Pure red ---");
    send_and_check(
        .r(8'd255), .g(8'd0), .b(8'd0),
        .x(16'd2), .y(16'd0),
        .sof(1'b0), .eol(1'b0),
        .label("Red")
      );

    //---------------------------------------------------------------------
    // TEST 5: Pure green (0, 255, 0) → 150*255 >> 8 = 149
    //---------------------------------------------------------------------
    $display("\n--- TEST 5: Pure green ---");
    send_and_check(
        .r(8'd0), .g(8'd255), .b(8'd0),
        .x(16'd3), .y(16'd0),
        .sof(1'b0), .eol(1'b0),
        .label("Green")
      );

    //---------------------------------------------------------------------
    // TEST 6: Pure blue (0, 0, 255) → 29*255 >> 8 = 28
    //---------------------------------------------------------------------
    $display("\n--- TEST 6: Pure blue ---");
    send_and_check(
        .r(8'd0), .g(8'd0), .b(8'd255),
        .x(16'd4), .y(16'd0),
        .sof(1'b0), .eol(1'b0),
        .label("Blue")
      );

    //---------------------------------------------------------------------
    // TEST 7: Known value (100, 150, 50)
    //   100*76 + 150*150 + 50*29 = 7600 + 22500 + 1450 = 31550
    //   31550 >> 8 = 123
    //---------------------------------------------------------------------
    $display("\n--- TEST 7: Known value (100, 150, 50) ---");
    send_and_check(
        .r(8'd100), .g(8'd150), .b(8'd50),
        .x(16'd5), .y(16'd0),
        .sof(1'b0), .eol(1'b1),
        .label("Known")
      );

    //---------------------------------------------------------------------
    // TEST 8: Strobes deassert after idle
    //---------------------------------------------------------------------
    $display("\n--- TEST 8: Strobe deassertion ---");
    // After test 7, valid was deasserted. Wait another cycle.
    wait_clocks(2);

    check(pixel_valid_out === 1'b0, "pixel_valid should deassert when idle");
    check(sof_out === 1'b0,         "sof should deassert when idle");
    check(eol_out === 1'b0,         "eol should deassert when idle");

    //---------------------------------------------------------------------
    // TEST 9: Valid gating - data ignored when valid is low
    //---------------------------------------------------------------------
    $display("\n--- TEST 9: Valid gating ---");

    // Drive garbage data with valid low
    r_in  <= 8'hFF;
    g_in  <= 8'hFF;
    b_in  <= 8'hFF;
    pixel_valid_in <= 1'b0;
    wait_clocks(3);

    // Greyscale output should not have updated to white
    check(pixel_valid_out === 1'b0,
          "pixel_valid should remain 0 when input valid is low");

    //---------------------------------------------------------------------
    // TEST 10: Consecutive pixels (pipeline check)
    //---------------------------------------------------------------------
    $display("\n--- TEST 10: Consecutive pixels ---");

    // Pixel 1
    r_in <= 8'd50;
    g_in <= 8'd100;
    b_in <= 8'd200;
    x_in <= 16'd0;
    y_in <= 16'd1;
    sof_in <= 1'b0;
    eol_in <= 1'b0;
    pixel_valid_in <= 1'b1;
    @(posedge clk);

    // Pixel 2 — check pixel 1 output
    r_in <= 8'd10;
    g_in <= 8'd20;
    b_in <= 8'd30;
    x_in <= 16'd1;
    @(posedge clk);
    check(pixel_valid_out === 1'b1, "Consecutive: pixel 1 valid");
    check(greyscale_out === expected_grey(8'd50, 8'd100, 8'd200),
          $sformatf("Consecutive pixel 1: expected %0d, got %0d",
                    expected_grey(8'd50, 8'd100, 8'd200), greyscale_out));

    // Pixel 3 — check pixel 2 output
    r_in <= 8'd200;
    g_in <= 8'd200;
    b_in <= 8'd200;
    x_in <= 16'd2;
    @(posedge clk);
    check(greyscale_out === expected_grey(8'd10, 8'd20, 8'd30),
          $sformatf("Consecutive pixel 2: expected %0d, got %0d",
                    expected_grey(8'd10, 8'd20, 8'd30), greyscale_out));

    // Pixel 4 — check pixel 3 output
    r_in <= 8'd128;
    g_in <= 8'd64;
    b_in <= 8'd32;
    x_in <= 16'd3;
    eol_in <= 1'b1;
    @(posedge clk);
    check(greyscale_out === expected_grey(8'd200, 8'd200, 8'd200),
          $sformatf("Consecutive pixel 3: expected %0d, got %0d",
                    expected_grey(8'd200, 8'd200, 8'd200), greyscale_out));

    // Done sending — check pixel 4 output
    pixel_valid_in <= 1'b0;
    eol_in <= 1'b0;
    @(posedge clk);
    check(greyscale_out === expected_grey(8'd128, 8'd64, 8'd32),
          $sformatf("Consecutive pixel 4: expected %0d, got %0d",
                    expected_grey(8'd128, 8'd64, 8'd32), greyscale_out));
    check(eol_out === 1'b1, "Consecutive: eol on last pixel");

    //---------------------------------------------------------------------
    // TEST 11: Green dominance (G should contribute most)
    //---------------------------------------------------------------------
    $display("\n--- TEST 11: Green dominance ---");
    // Same total (100+100+100=300) but distributed differently
    // All green should produce higher grey than all red

    r_in <= 8'd255;
    g_in <= 8'd0;
    b_in <= 8'd0;
    pixel_valid_in <= 1'b1;
    sof_in <= 1'b0;
    eol_in <= 1'b0;
    x_in <= '0;
    y_in <= '0;
    @(posedge clk);
    pixel_valid_in <= 1'b0;
    @(posedge clk);
    grey_red = greyscale_out;

    r_in <= 8'd0;
    g_in <= 8'd255;
    b_in <= 8'd0;
    pixel_valid_in <= 1'b1;
    @(posedge clk);
    pixel_valid_in <= 1'b0;
    @(posedge clk);
    grey_green = greyscale_out;

    check(grey_green > grey_red,
          $sformatf("Green (%0d) should be brighter than red (%0d)",
                    grey_green, grey_red));

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
