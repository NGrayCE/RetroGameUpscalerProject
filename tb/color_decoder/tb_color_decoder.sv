`timescale 1ns/1ps

module tb_color_decoder();

    // --- 1. DUT Signals ---
    logic clk = 0;
    logic rst = 0;
    logic [11:0] adc_raw;
    logic burst_active = 0;
    logic [23:0] rgb_out;

    // Helper for Waveform Viewing
    logic [7:0] r_out, g_out, b_out;
    assign r_out = rgb_out[23:16];
    assign g_out = rgb_out[15:8];
    assign b_out = rgb_out[7:0];

    // --- 2. Signal Generator Variables (The "Retro Console") ---
    real t = 0; // Time accumulator
    real freq_carrier = 3.579545; // MHz
    real freq_sample  = 74.25;    // MHz
    real phase_tx     = 0;        // Transmitter Phase (0 to 2*PI)
    
    // Video Component Settings
    real luma_level   = 0;        // 0.0 to 1.0
    real chroma_amp   = 0;        // 0.0 to 1.0 (Amplitude)
    real chroma_phase = 0;        // Phase shift in Degrees
    
    // Constant: PI
    const real PI = 3.14159265359;

    // --- 3. Clock Generation ---
    always #6.734 clk = ~clk; // 74.25 MHz

    // --- 4. DUT Instantiation ---
    color_decoder dut (
        .clk(clk),
        .rst(rst),
        .adc_raw(adc_raw),
        .burst_active(burst_active),
        .rgb_out(rgb_out)
    );

    // --- 5. The "Transmitter" Logic (ADC Generator) ---
    // This block runs every clock cycle to generate the next analog sample
    always @(posedge clk) begin
        if (rst) begin
            adc_raw <= 0;
            phase_tx <= 0;
        end else begin
            // 1. Update Phase of the 3.58MHz Carrier
            // Phase Step = 2*PI * (F_carrier / F_sample)
            phase_tx = phase_tx + (2.0 * PI * (freq_carrier / freq_sample));
            
            // Keep phase within 0..2PI to prevent overflow issues
            if (phase_tx > 2.0 * PI) phase_tx = phase_tx - (2.0 * PI);

            // 2. Calculate the Chroma Wave (Sine Wave)
            // Signal = Luma + Amplitude * Sin(CarrierPhase + ColorPhase)
            // Note: We convert Degrees to Radians for the ColorPhase
            real signal_val;
            real rad_shift;
            
            rad_shift = chroma_phase * (PI / 180.0);
            
            // Base Signal
            signal_val = luma_level + (chroma_amp * $sin(phase_tx + rad_shift));

            // 3. Convert to 12-bit ADC Format (Unsigned)
            // 0.0 -> 0, 1.0 -> 4095.
            // But usually video is 0.3V (Black) to 1.0V (White).
            // Let's assume full range for simplicity: 2048 is center.
            // Scale: -1.0 to 1.0 input range maps to 0..4095
            
            // Map: 0.0 (Center) -> 2048
            // Range: +/- 2047
            int adc_int;
            adc_int = 2048 + int'(signal_val * 2000.0);

            // Clamp
            if (adc_int > 4095) adc_int = 4095;
            if (adc_int < 0)    adc_int = 0;

            adc_raw <= 12'(adc_int);
        end
    end

    // --- 6. Test Procedure ---
    initial begin
        $dumpfile("decoder_full_wave.vcd");
        $dumpvars(0, tb_color_decoder);

        $display("--- Starting Color Decoder System Test ---");

        // Initialize
        rst = 1;
        luma_level = 0.0; // Black
        chroma_amp = 0.0; // No Color
        #50;
        rst = 0;
        
        // Wait for pipeline
        repeat(10) @(posedge clk);

        // ============================================================
        // PHASE 1: PLL LOCKING (The "Color Burst")
        // ============================================================
        // To verify the decoder, we first need to lock the NCO to the input.
        // We simulate a "Burst" by sending a standard sine wave (Phase 0)
        // and asserting the burst_active flag.
        $display("Phase 1: Attempting PLL Lock (Sending Burst)...");

        burst_active = 1;
        luma_level   = -0.2; // Sync tip area / Back porch (dark)
        chroma_amp   = 0.3;  // Standard Burst Amplitude
        chroma_phase = 180;  // Burst is reference 180 degrees (usually)
                             // NOTE: NTSC definition says Burst is 180 deg relative to Reduced-Carrier.
                             // For simplicity, we define our generator's 0 as "Burst Phase".
        chroma_phase = 0;    
        
        // We need to hold this for a LONG time for the Loop Filter to settle.
        // The loop filter is slow (overdamped).
        repeat(2000) @(posedge clk); 

        $display("PLL should be locked now. Checking Loop Filter Offset...");
        // You can check 'dut.loop_filter_offset' in GTKWave to see if it stabilized.

        burst_active = 0; // End Burst

        // ============================================================
        // PHASE 2: RED TEST
        // ============================================================
        // Red is usually around 100 degrees phase shift from burst.
        $display("Phase 2: Sending RED Signal");
        
        luma_level   = 0.3; // Mid-Gray Background
        chroma_amp   = 0.4; // Strong Color
        chroma_phase = 90;  // 90 Deg shift (Approximating Red/V-Axis)

        repeat(100) @(posedge clk);
        // Look at rgb_out. Red (R) should be high, G and B low.

        // ============================================================
        // PHASE 3: BLUE TEST
        // ============================================================
        // Blue is around 0 or 180 degrees (U-Axis).
        $display("Phase 3: Sending BLUE Signal");
        chroma_phase = 0;   // 0 Deg shift (Approximating Blue/U-Axis)
        
        repeat(100) @(posedge clk);

        // ============================================================
        // PHASE 4: BLACK & WHITE TEST
        // ============================================================
        $display("Phase 4: Sending B&W Signal (No Chroma)");
        chroma_amp = 0.0;
        luma_level = 0.5; // Bright Gray
        
        repeat(100) @(posedge clk);
        // All RGB should be roughly equal (~128)

        $finish;
    end

endmodule