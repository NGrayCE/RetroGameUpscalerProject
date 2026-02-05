module loop_filter(
	input	logic	clk,
	input 	logic	rst,
	input	logic	 burst_active,
	input	logic	 signed [11:0] error_in, //the red component of the color burst
	output	logic	signed [31:0] offset_out
);

	// Accumulate Error over the Burst
    // The burst is noisy. Averaging it over the ~20-90 tick duration gives a cleaner error.
    logic signed [31:0] burst_accumulator;
    logic [6:0]         sample_count;
    logic               update_pulse;
    logic signed [31:0] captured_error;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            burst_accumulator <= 0;
            sample_count      <= 0;
            update_pulse      <= 0;
            captured_error    <= 0;
        end else begin
            update_pulse <= 0; // Default low

            if (burst_active) begin
                // While in the burst, sum up the "Red" values (which should be 0)
                burst_accumulator <= burst_accumulator + error_in;
                sample_count      <= sample_count + 1;
            end else if (sample_count > 0) begin
                // Burst just ended. Save the total error and reset.
                // We typically just use the sum directly (effectively gain), 
                // or divide by sample_count if you want the true average.
                // Here we keep the sum for higher sensitivity.
                captured_error    <= burst_accumulator;
                update_pulse      <= 1; // Signal the loop to update ONCE per line
                burst_accumulator <= 0;
                sample_count      <= 0;
            end
        end
    end

	// PI Controller
    // Powers of 2 allow bit-shifts
    localparam int KP_SHIFT = 4;  // Proportional Gain (Divide by 2^6 = 64)
    localparam int KI_SHIFT = 8; // Integral Gain (Divide by 2^10 = 1024)

    logic signed [31:0] integrator; // Large register to hold long-term drift
    logic signed [31:0] p_term, i_term;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            integrator <= 0;
            offset_out <= 0;
        end else if (update_pulse) begin
            // INTEGRAL: Permanently adjust frequency based on history
            integrator <= integrator + captured_error;
            
            // PROPORTIONAL: Temporarily adjust based on this line's error
            // (Arithmetic Shift Right >>> preserves sign)
            p_term = captured_error >>> KP_SHIFT;
            i_term = integrator     >>> KI_SHIFT;
            
            // Output the sum
            offset_out <= p_term + i_term;
        end
    end
endmodule
