`timescale 1ns/1ps

module tb_yuv_to_rgb();

    logic clk = 0;
    logic rst = 0;
    
    // Inputs
    logic signed [12:0] y_in; // 0 to 4095
    logic signed [11:0] u_in; // -2048 to +2047
    logic signed [11:0] v_in; // -2048 to +2047

    // Output
    logic [23:0] rgb_out;
    logic [7:0] r_out, g_out, b_out;

    // Helper to read RGB easier in waveform
    assign r_out = rgb_out[23:16];
    assign g_out = rgb_out[15:8];
    assign b_out = rgb_out[7:0];

    // Clock Generation (74.25 MHz)
    always #6.734 clk = ~clk;

    // DUT Instantiation
    yuv_to_rgb dut (
        .clk(clk),
        .rst(rst),
        .y_in(y_in),
        .u_in(u_in),
        .v_in(v_in),
        .rgb_out(rgb_out)
    );

    // Test Sequence
    initial begin
        $dumpfile("csc_wave.vcd");
        $dumpvars(0, tb_yuv_to_rgb);
        
        $display("--- Starting Color Space Converter Test ---");

        // Initialization
        rst = 1;
        y_in = 0; u_in = 0; v_in = 0;
        #20;
        rst = 0;
        
        // Wait for pipeline flush
        repeat(5) @(posedge clk);

        // --- TEST 1: BLACK (Y=0, U=0, V=0) ---
        $display("\nTest 1: Black (Y=0, U=0, V=0)");
        y_in = 0; u_in = 0; v_in = 0;
        
        // Wait 4 cycles for pipeline (Input -> Mult -> Sum -> Output)
        repeat(4) @(posedge clk); 
        $display("RGB Output: %d %d %d (Exp: 0 0 0)", r_out, g_out, b_out);

        // --- TEST 2: WHITE (Y=Max, U=0, V=0) ---
        // Y input is 13-bit (0..4095)
        $display("\nTest 2: White (Y=4095, U=0, V=0)");
        y_in = 13'd4095; u_in = 0; v_in = 0;
        
        repeat(4) @(posedge clk);
        $display("RGB Output: %d %d %d (Exp: 255 255 255)", r_out, g_out, b_out);

        // --- TEST 3: GRAY (Y=Mid, U=0, V=0) ---
        $display("\nTest 3: Gray (Y=2048, U=0, V=0)");
        y_in = 13'd2048; u_in = 0; v_in = 0;
        
        repeat(4) @(posedge clk);
        // 2048 is roughly 50% brightness -> 128
        $display("RGB Output: %d %d %d (Exp: ~128 ~128 ~128)", r_out, g_out, b_out);

        // --- TEST 4: RED-ish Tone (Y=Mid, V=Positive, U=Negative) ---
        // Red is driven by +V (Cr) and -U (Cb)
        $display("\nTest 4: Red Tone (Y=1000, U=-500, V=1000)");
        y_in = 13'd1000; u_in = -12'd500; v_in = 12'd1000;
        
        repeat(4) @(posedge clk);
        $display("RGB Output: %d %d %d (Exp: High Red, Low Green/Blue)", r_out, g_out, b_out);

        // --- TEST 5: BLUE-ish Tone (Y=Mid, U=Positive) ---
        // Blue is driven by +U (Cb)
        $display("\nTest 5: Blue Tone (Y=1000, U=1000, V=0)");
        y_in = 13'd1000; u_in = 12'd1000; v_in = 0;
        
        repeat(4) @(posedge clk);
        $display("RGB Output: %d %d %d (Exp: Low Red, Low Green, High Blue)", r_out, g_out, b_out);

        // --- TEST 6: CLAMPING CHECK (Overflow) ---
        // Input a value that would mathematically produce > 255
        // Y=4095 (White) + V=2000 (More Red) -> Red Channel Overflow
        $display("\nTest 6: Clamping (Y=4095, V=2000)");
        y_in = 13'd4095; u_in = 0; v_in = 12'd2000;
        
        repeat(4) @(posedge clk);
        $display("RGB Output: %d %d %d (Exp: 255 255 255 - clamped)", r_out, g_out, b_out);

        $finish;
    end

endmodule