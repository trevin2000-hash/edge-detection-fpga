//-----------------------------------------------------------------------------
// @file: pkg_edge_detection.sv
//
// @brief: SystemVerilog mirror of scr/rtl/pkg_edge_detection.vhd.
//
// @details SystemVerilog cannot import VHDL package constants, so the values
// below are duplicated by hand. If pkg_edge_detection.vhd changes, this file
// must change with it. Nothing enforces that at compile time, so testbenches
// should sanity-check the DUT against these constants at runtime (e.g. verify
// window_valid_o asserts at the pixel count WINDOW_SIZE_C predicts).
//
// @author Trevin Vaughan
//-----------------------------------------------------------------------------
`ifndef pkg_edge_detection
`define pkg_edge_detection

package pkg_edge_detection;

    //-------------------------------------------------------------------------
    // Constants - must match pkg_edge_detection.vhd
    //-------------------------------------------------------------------------
    parameter int COMPONENT_WIDTH_C = 8; // width of component in a pixel
    parameter int WINDOW_SIZE_C     = 3; // size of sliding window

    // Not in the VHDL package, this is the pixel_line_buff FRAME_WIDTH_G default
    parameter int FRAME_WIDTH_C = 1920;

    // Total width of the flattened window port on pixel_line_buff_wrap
    parameter int WINDOW_BITS_C = WINDOW_SIZE_C * WINDOW_SIZE_C * COMPONENT_WIDTH_C;

    //-------------------------------------------------------------------------
    // Types
    //-------------------------------------------------------------------------
    typedef logic [COMPONENT_WIDTH_C-1:0] pixel_t;
    typedef logic [WINDOW_BITS_C-1:0]     window_flat_t;

    // window_t[row][col], mirrors the VHDL sliding_window type
    typedef pixel_t window_t [WINDOW_SIZE_C][WINDOW_SIZE_C];

    //-------------------------------------------------------------------------
    // Window packing helpers
    //
    // Bit layout must stay in sync with the flatten_rows/flatten_cols generate
    // in scr/tb/wrapper/pixel_line_buff_wrap.vhd:
    //
    //   index = (row * WINDOW_SIZE_C) + col
    //   slice = flat[index*COMPONENT_WIDTH_C +: COMPONENT_WIDTH_C]
    //
    // window[0][0] is the LOW bits, window[2][2] the HIGH bits.
    //-------------------------------------------------------------------------

    // Flat DUT port -> 2D window
    function automatic window_t unflatten_window(input window_flat_t flat);
        window_t w;
        for (int r = 0; r < WINDOW_SIZE_C; r++) begin
            for (int c = 0; c < WINDOW_SIZE_C; c++) begin
                w[r][c] = flat[((r * WINDOW_SIZE_C) + c) * COMPONENT_WIDTH_C +: COMPONENT_WIDTH_C];
            end
        end
        return w;
    endfunction

    // 2D window -> flat vector, for building expected values
    function automatic window_flat_t flatten_window(input window_t w);
        window_flat_t flat = '0;
        for (int r = 0; r < WINDOW_SIZE_C; r++) begin
            for (int c = 0; c < WINDOW_SIZE_C; c++) begin
                flat[((r * WINDOW_SIZE_C) + c) * COMPONENT_WIDTH_C +: COMPONENT_WIDTH_C] = w[r][c];
            end
        end
        return flat;
    endfunction

    //-------------------------------------------------------------------------
    // Compare and report
    //-------------------------------------------------------------------------

    // 4-state compare of every element. Returns 1 when the windows match.
    function automatic bit window_eq(input window_t actual, input window_t expected);
        for (int r = 0; r < WINDOW_SIZE_C; r++) begin
            for (int c = 0; c < WINDOW_SIZE_C; c++) begin
                if (actual[r][c] !== expected[r][c]) begin
                    return 1'b0;
                end
            end
        end
        return 1'b1;
    endfunction

    // Number of mismatching elements, useful for summary reporting
    function automatic int window_diff_count(input window_t actual, input window_t expected);
        int n = 0;
        for (int r = 0; r < WINDOW_SIZE_C; r++) begin
            for (int c = 0; c < WINDOW_SIZE_C; c++) begin
                if (actual[r][c] !== expected[r][c]) begin
                    n++;
                end
            end
        end
        return n;
    endfunction

    // Pretty-print a window for $display on mismatch
    function automatic string window2str(input window_t w);
        string s = "";
        for (int r = 0; r < WINDOW_SIZE_C; r++) begin
            s = {s, "  ["};
            for (int c = 0; c < WINDOW_SIZE_C; c++) begin
                s = {s, $sformatf(" %3d", w[r][c])};
            end
            s = {s, " ]\n"};
        end
        return s;
    endfunction

    // Side-by-side actual vs expected, mismatching elements marked with '*'
    function automatic string window_diff_str(input window_t actual, input window_t expected);
        string s;
        s = "        actual              expected\n";
        for (int r = 0; r < WINDOW_SIZE_C; r++) begin
            s = {s, "  ["};
            for (int c = 0; c < WINDOW_SIZE_C; c++) begin
                s = {s, $sformatf(" %3d%s", actual[r][c],
                    (actual[r][c] !== expected[r][c]) ? "*" : " ")};
            end
            s = {s, "]   ["};
            for (int c = 0; c < WINDOW_SIZE_C; c++) begin
                s = {s, $sformatf(" %3d ", expected[r][c])};
            end
            s = {s, "]\n"};
        end
        return s;
    endfunction

endpackage : pkg_edge_detection

//-----------------------------------------------------------------------------
// Check macros
//
// Defined outside the package because `define is not scoped. The package is
// referenced explicitly so these work whether or not the testbench imports it.
//
// Usage:
//   `CHECK_WINDOW_EQ(unpack_window(window_flat), exp_window, "pixel 42")
//   `CHECK_WINDOW_EQ_CNT(act, exp, "pixel 42", test_count, pass_count, fail_count)
//-----------------------------------------------------------------------------

// Compare two window_t values, report a labelled diff on mismatch.
`define CHECK_WINDOW_EQ(actual, expected, msg)                                       \
    if (!pkg_edge_detection::window_eq(actual, expected)) begin                    \
        $error("window mismatch: %s (%0d/%0d elements differ, time=%0t)\n%s",         \
               msg,                                                                   \
               pkg_edge_detection::window_diff_count(actual, expected),            \
               pkg_edge_detection::WINDOW_SIZE_C *                                 \
               pkg_edge_detection::WINDOW_SIZE_C,                                  \
               $time,                                                                 \
               pkg_edge_detection::window_diff_str(actual, expected));             \
    end

// Same, but also maintains the tb test/pass/fail counters.
`define CHECK_WINDOW_EQ_CNT(actual, expected, msg, tests, passes, fails)             \
    begin                                                                            \
        tests++;                                                                     \
        if (pkg_edge_detection::window_eq(actual, expected)) begin                 \
            passes++;                                                                \
        end else begin                                                               \
            fails++;                                                                 \
            $error("FAIL [%0d] window mismatch: %s (%0d/%0d differ, time=%0t)\n%s",  \
                   tests, msg,                                                       \
                   pkg_edge_detection::window_diff_count(actual, expected),       \
                   pkg_edge_detection::WINDOW_SIZE_C *                            \
                   pkg_edge_detection::WINDOW_SIZE_C,                             \
                   $time,                                                            \
                   pkg_edge_detection::window_diff_str(actual, expected));        \
        end                                                                          \
    end

`endif // pkg_edge_detection
