`timescale 1ns/1ps

module tb_simple_average_filter();

    parameter int DATA_WIDTH = 12;
    parameter int WINDOW_SIZE = 16;

    logic clk = 0;
    logic rst = 0;
    logic signed [DATA_WIDTH-1:0] data_in = 0;
    logic signed [DATA_WIDTH-1:0] data_out;

    // Clock Generation (74.25 MHz approx = 13.4ns)
    always #6.7 clk = ~clk;

    simple_average_filter #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .data_out(data_out)
    );

    initial begin
        // Setup Waveform dumping for GTKWave
        $dumpfile("filter_wave.vcd");
        $dumpvars(0, tb_simple_average_filter);
        
        // --- Initialization ---
        $display("--- Starting Simulation ---");
        rst = 1;
        data_in = 0;
        #50;
		
        $display("Flushing 'x' values while holding reset...");
		repeat(WINDOW_SIZE + 5) @(negedge clk);
		
        // Release Reset
        @(negedge clk) rst = 0;
        $display("Reset Released. Output should be 0. Actual: %d", data_out);

 
        // --- Step Response Test ---
        // If we input a constant 1000, the average should slowly rise 
        // and settle exactly at 1000 after WINDOW_SIZE cycles.
        $display("--- Starting Step Response (Input = 1000) ---");
        
        for (int i = 0; i < WINDOW_SIZE * 2; i++) begin
            @(negedge clk);
            data_in = 12'd1000;
            
            // Optional: Print status every few cycles
            if (i % 4 == 0) 
                $display("Time: %t | Input: %d | Output (Avg): %d", $time, data_in, data_out);
        end

        if (data_out == 1000)
            $display("SUCCESS: Filter settled at 1000.");
        else
            $display("ERROR: Filter did not settle! Got: %d", data_out);

        // --- Impulse Test ---
        // Send a single spike of 1600. 
        // The average should jump to 100 (1600/16) and stay there 
        // for exactly WINDOW_SIZE cycles, then drop to 0.
        $display("--- Starting Impulse Test (Input spike 1600) ---");
        
        // Clear input first
        @(negedge clk) data_in = 0;
        repeat(WINDOW_SIZE) @(posedge clk); // Wait for settle

        // Pulse
        @(negedge clk) data_in = 1600;
        @(negedge clk) data_in = 0;

        // Monitor the "Traveling Pulse"
        repeat(WINDOW_SIZE + 1) begin
            @(negedge clk);
            $display("Time: %t | Impulse Output: %d (Expected: 100)", $time, data_out);
        end

        $finish;
    end

endmodule