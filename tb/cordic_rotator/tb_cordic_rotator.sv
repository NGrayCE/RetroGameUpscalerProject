`timescale 1ns/1ps

module tb_cordic_rotator();


    parameter int DATA_WIDTH = 12;
    parameter int STAGES     = 12;

    logic clk = 0;
    logic rst = 0;
    logic signed [19:0] target_angle = 0;
    
    // Outputs
    logic signed [DATA_WIDTH-1:0] sin_out;
    logic signed [DATA_WIDTH-1:0] cos_out;

    // Period = 13.468 ns -> Half Period = 6.734 ns
    always #6.734 clk = ~clk;


    cordic_rotator #(
        .DATA_WIDTH(DATA_WIDTH),
        .STAGES(STAGES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .target_angle(target_angle),
        .sin_out(sin_out),
        .cos_out(cos_out)
    );

    // Constants for Angle Mapping
    // 360 degrees = 2^20 = 1,048,576
    // 90  degrees = 262,144
    // 45  degrees = 131,072
    localparam int DEG_90 = 262144;
    localparam int DEG_45 = 131072;

    // Test Sequence
    initial begin
        $dumpfile("cordic_wave.vcd");
        $dumpvars(0, tb_cordic_rotator);
        
        $display("--- Starting CORDIC Rotator Test ---");

        // Initialization
        rst = 1;
        target_angle = 0;
        #20;
        rst = 0;
        
        // Wait for pipeline flush (STAGES cycles)
        repeat(STAGES + 2) @(posedge clk);

        // --- TEST 1: Zero Degrees ---
        $display("Test 1: 0 Degrees");
        target_angle = 0;
        repeat(STAGES + 2) @(posedge clk);
        $display("Angle: 0 | Sin: %d (Exp: 0) | Cos: %d (Exp: ~1024)", sin_out, cos_out);

        // --- TEST 2: +45 Degrees ---
        $display("\nTest 2: +45 Degrees");
        target_angle = DEG_45;
        repeat(STAGES + 2) @(posedge clk);
        $display("Angle: 45 | Sin: %d | Cos: %d (Should be equal)", sin_out, cos_out);

        // --- TEST 3: +90 Degrees (Edge of Convergence) ---
        $display("\nTest 3: +90 Degrees");
        target_angle = DEG_90;
        repeat(STAGES + 2) @(posedge clk);
        $display("Angle: 90 | Sin: %d (Exp: Max) | Cos: %d (Exp: 0)", sin_out, cos_out);

        // --- TEST 4: -90 Degrees ---
        $display("\nTest 4: -90 Degrees");
        target_angle = -DEG_90;
        repeat(STAGES + 2) @(posedge clk);
        $display("Angle: -90 | Sin: %d (Exp: -Max) | Cos: %d (Exp: 0)", sin_out, cos_out);

        // --- TEST 5: Full Sweep (Ramp) ---
        // This generates a visual sine wave in the waveform viewer.
        // We will sweep from -180 to +180 to see where it breaks.
        $display("\nTest 5: Full Circle Sweep (-180 to 180)");
        
        // Start at -180 degrees (approx -524288)
        target_angle = -524288; 
        
        // Increment by small steps to draw the wave
        for (int i = 0; i < 2000; i++) begin
            @(posedge clk);
            target_angle = target_angle + 524; // Sweep speed
        end

        $finish;
    end

endmodule