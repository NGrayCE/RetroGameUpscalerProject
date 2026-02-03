`timescale 1ns/1ps

module tb_nco_sine_generator();

    // 1. Signals
    logic clk = 0;
    logic rst = 0;
    logic [31:0] phase_inc;
    
    // Outputs (Signed 12-bit)
    logic signed [11:0] sin_val;
    logic signed [11:0] cos_val;

    // 2. Clock Generation (74.25 MHz)
    // Period = 13.468 ns -> Half Period = 6.734 ns
    always #6.734 clk = ~clk;

    // 3. DUT Instantiation
    nco_sine_generator dut (
        .clk(clk),
        .rst(rst),
        .phase_inc(phase_inc),
        .sin_val(sin_val),
        .cos_val(cos_val)
    );

    // 4. Test Sequence
    initial begin
        $dumpfile("nco_wave.vcd");
        $dumpvars(0, tb_nco_sine_generator);
        
        $display("--- Starting NCO Test ---");

        // --- PHASE 1: Initialization ---
        rst = 1;
        phase_inc = 0;
        #20;
        rst = 0;
        
        // Wait a few cycles
        repeat(5) @(posedge clk);

        // --- PHASE 2: Standard NTSC Burst (3.58 MHz) ---
        // Formula: Increment = (TargetFreq / ClockFreq) * 2^32
        // (3.579545 / 74.25) * 4294967296 = ~207,078,536
        $display("Test 2: NTSC 3.58 MHz Generation");
        phase_inc = 32'd207078536;

        // Run for enough cycles to see a full sine wave
        // 74.25MHz / 3.58MHz = ~20.7 clock cycles per wave period
        // We run for 5 periods (approx 100 clocks)
        repeat(100) @(posedge clk);

        // --- PHASE 3: Double Frequency (7.16 MHz) ---
        // We double the increment. The wave period should shrink by half.
        $display("Test 3: Double Frequency (7.16 MHz)");
        phase_inc = 32'd207078536 * 2;
        
        repeat(50) @(posedge clk);

        // --- PHASE 4: Zero Frequency (DC) ---
        // The output should "freeze" at whatever value it currently holds.
        $display("Test 4: Frequency 0 (Hold)");
        phase_inc = 0;
        
        repeat(10) @(posedge clk);
        $display("Output Held at: Sin=%d Cos=%d", sin_val, cos_val);

        // --- PHASE 5: Quadrature Check (Visual only) ---
        // Cosine should lead Sine by 90 degrees. 
        // When Sin is near 0 (rising), Cos should be near Max Positive.
        $display("Test 5: Check Quadrature (View in Waveform)");
        phase_inc = 32'd207078536; // Back to 3.58 MHz
        repeat(50) @(posedge clk);

        $finish;
    end

endmodule