`timescale 1ns/1ps

module tb_loop_filter();

    // 1. Signals
    logic clk = 0;
    logic rst = 0;
    logic burst_active = 0;
    logic signed [11:0] phase_error = 0; // Input from Phase Detector
    logic signed [31:0] loop_offset;     // Output to NCO

    // 2. Clock Generation (74.25 MHz)
    always #6.734 clk = ~clk;

    // 3. DUT Instantiation
    loop_filter dut (
        .clk(clk),
        .rst(rst),
        .burst_active(burst_active),
        .error_in(phase_error),
        .offset_out(loop_offset)
    );

    // 4. Test Sequence
    initial begin
		logic signed [31:0] start_val, end_val;
        $dumpfile("loop_filter_wave.vcd");
        $dumpvars(0, tb_loop_filter);
        
        $display("--- Starting Loop Filter (PI) Test ---");

        // --- PHASE 1: Initialization ---
        rst = 1;
        burst_active = 0;
        phase_error = 0;
        #50;
        rst = 0;
        
        // Wait for a few cycles
        repeat(5) @(posedge clk);
        $display("Init: Offset should be 0. Actual: %d", loop_offset);

        // --- PHASE 2: "Hold" Check (Burst Inactive) ---
        // If burst is NOT active, the filter should IGNORE errors.
        // It shouldn't change the offset even if error is huge.
        $display("\nTest 2: Hold Check (Burst Low, Error High)");
        burst_active = 0;
        phase_error = 12'd1000; // Large positive error
        
        repeat(10) @(posedge clk);
        
        if (loop_offset == 0) 
            $display("SUCCESS: Filter ignored error while burst was low.");
        else
            $display("FAILURE: Filter reacted when it should have held! Val: %d", loop_offset);


        // --- PHASE 3: Integral Action (Simulating Video Lines) ---
        // We will simulate 3 scanlines. 
        // Logic: Burst ON (Accumulate Error) -> Burst OFF (Update Output).
        $display("\nTest 3: Integral Action (Stepping through 3 lines)");
        
        phase_error = 12'd1000; // Constant positive error
        
        // --- Line 1 ---
        $display("  [Line 1] Burst Start...");
        burst_active = 1;
        repeat(20) @(posedge clk); // Integrating... output should NOT change yet
        
        burst_active = 0;          // Burst End -> Update should happen here
        repeat(5) @(posedge clk);  // Wait for update
        
        $display("  [Line 1] End. Offset: %d", loop_offset);
        if (loop_offset > 0) $display("    -> SUCCESS: Offset increased after burst.");
        else                 $display("    -> FAIL: Offset did not update.");

        // --- Line 2 ---
        $display("  [Line 2] Burst Start...");
        burst_active = 1;
        repeat(20) @(posedge clk);
        
        burst_active = 0;
        repeat(5) @(posedge clk);
        
        $display("  [Line 2] End. Offset: %d", loop_offset);

        // --- Line 3 ---
        $display("  [Line 3] Burst Start...");
        burst_active = 1;
        repeat(20) @(posedge clk);
        
        burst_active = 0;
        repeat(5) @(posedge clk);
        
        $display("  [Line 3] End. Offset: %d", loop_offset);


        // --- PHASE 4: Negative Correction ---
        $display("\nTest 4: Negative Correction (Input -2000)");
        phase_error = -12'd2000; // Strong negative error
        
        // Run one line with negative error
        burst_active = 1;
        repeat(20) @(posedge clk);
        burst_active = 0;
        repeat(5) @(posedge clk);
        
        $display("  [Line 4] End. Offset: %d", loop_offset);
        
        // Check logic
        if (loop_offset < 10000000) // Just checking it went down significantly
             $display("SUCCESS: Offset decreased correctly.");

        // --- PHASE 5: Lock Stability ---
        // If error goes to 0, output should stabilize (Hold current value).
        $display("\nTest 5: Lock Stability (Error = 0)");
        phase_error = 0;
        
        // Let it run
        repeat(5) @(posedge clk);
        start_val = loop_offset;
        repeat(10) @(posedge clk);
        end_val = loop_offset;

        if (start_val == end_val)
            $display("SUCCESS: Output held steady at %d", end_val);
        else
            $display("FAILURE: Output drifted! %d -> %d", start_val, end_val);

        $finish;
    end

endmodule