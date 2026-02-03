`timescale 1ns/1ps

module tb_yc_separator();


    parameter int DATA_WIDTH = 12;
    parameter int WINDOW_SIZE = 32;


    logic clk = 0;
    logic rst = 0;
    logic signed [DATA_WIDTH-1:0] data_in = 0;
    logic signed [DATA_WIDTH-1:0] luma_out;
    logic signed [DATA_WIDTH-1:0] chroma_out;

    // 3. Clock Generation (74.25 MHz)
    always #6.734 clk = ~clk;

    yc_separator #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .luma_out(luma_out),
        .chroma_out(chroma_out)
    );

    initial begin
        $dumpfile("yc_sep_wave.vcd");
        $dumpvars(0, tb_yc_separator);
		for (int i = 0; i < WINDOW_SIZE; i++) begin
            // Syntax: $dumpvars(level, variable_path);
            $dumpvars(0, dut.shift_reg[i]);
        end
        $display("--- Starting YC Separator Test ---");

        rst = 1;
        data_in = 0;
        
        // Clock the module while in reset to push 0s into the shift register
        repeat(WINDOW_SIZE + 5) @(negedge clk);
        
        rst = 0;
        $display("Pipeline Flushed. Outputs should be 0. L: %d C: %d", luma_out, chroma_out);

        // --- DC Test (Pure Brightness) ---
        // If we send a constant value (e.g., 2000), Luma should eventually equal 2000,
        // and Chroma should be 0 (because there is no variation).
        $display("\n--- Test 1: DC Input (Pure Luma = 2000) ---");
        
        for (int i = 0; i < WINDOW_SIZE * 2; i++) begin
            @(negedge clk) data_in = 2000;
        end
        
        $display("Result -> Luma: %d (Exp: 2000) | Chroma: %d (Exp: 0)", luma_out, chroma_out);

        // --- High Frequency Test (Pure Color) ---
        // We will generate a "Zig-Zag" pattern: 1000, 1100, 1000, 1100...
        // This represents a color wave sitting on top of brightness.
        // Expected Luma: 2050 (The Average)
        // Expected Chroma: +/- 50 (The Variation)
        $display("\n--- Test 2: High Freq Input (Color Carrier) ---");
        
        for (int i = 0; i < WINDOW_SIZE * 2; i++) begin
            @(negedge clk);
            if (i % 2 == 0) data_in = 1100;
            else            data_in = 1000;
        end

        // Check the result
        // Note: The Chroma output phase depends on whether the "Center Tap" 
        // lands on a 2100 or a 2000 at this specific cycle.
        $display("Result -> Luma: %d (Exp: 1050)", luma_out);
        $display("Result -> Chroma: %d (Exp: +/- 50)", chroma_out);

        // --- Impulse/Edge Test ---
        // sudden drop to 0 to see how fast it reacts
        $display("\n--- Test 3: Sudden Drop to 0 ---");
        @(negedge clk) data_in = 0;
        
        repeat(WINDOW_SIZE+1) @(negedge clk);
        
        if (luma_out == 0 && chroma_out == 0)
            $display("SUCCESS: Filter settled back to 0.");
        else
            $display("WARNING: Filter did not settle yet. L: %d C: %d", luma_out, chroma_out);

        $finish;
    end

endmodule