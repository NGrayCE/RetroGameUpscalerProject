module cordic_rotator #(
    parameter int DATA_WIDTH = 12,  // Width of x, y, z (system bit depth)
    parameter int STAGES     = 10   // Number of iterations (precision)
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [19:0]      target_angle, 		// Input Angle (Phase)
    output logic signed [DATA_WIDTH-1:0] sin_out,      	// Sine Output
    output logic signed [DATA_WIDTH-1:0] cos_out      	// Cosine Output
);

    // Start with scaling factor of ~0.60725 to avoid a multiplication
    // 0.60725 * 2^(DATA_WIDTH-1)
    localparam int CORDIC_GAIN = int'(0.60725 * (2**(DATA_WIDTH-1))); 

    // ATAN Table (Pre-calculated angles for each step)
    // Scaled to match the 20-bit target_angle input
	// angle representation = round(arctan(2^-i)/360 * 2^20)
	// supports up to 16 iterations
    logic [19:0] atan_table [0:15];
    initial begin
        atan_table[0]  = 20'd131072; // 45.000 degrees
        atan_table[1]  = 20'd77376;  // 26.565
        atan_table[2]  = 20'd40883;  // 14.036
        atan_table[3]  = 20'd20753;  // 7.125
        atan_table[4]  = 20'd10416;  // 3.576
        atan_table[5]  = 20'd5213;   // 1.790
        atan_table[6]  = 20'd2607;   // 0.895
        atan_table[7]  = 20'd1303;   // 0.448
        atan_table[8]  = 20'd652;    // 0.224
        atan_table[9]  = 20'd326;    // 0.112
        atan_table[10] = 20'd163;
        atan_table[11] = 20'd81;
        atan_table[12] = 20'd41;
        atan_table[13] = 20'd20;
        atan_table[14] = 20'd10;
        atan_table[15] = 20'd5;
    end

    // Pipeline Registers
	// need pipeline to achieve 1 clock cycle calculation
    // x, y = vector coordinates
    // z = remaining angle error
    logic signed [DATA_WIDTH:0] x [STAGES-1:0];
    logic signed [DATA_WIDTH:0] y [STAGES-1:0];
    logic signed [19:0]         z [STAGES-1:0];

	// Constants for 45 and 135 degrees
    localparam int DEG_45  = 20'd131072;
    localparam int DEG_135 = 20'd393216;
    // Iteration Logic
    genvar i;
    generate
        for (i = 0; i < STAGES; i++) begin : loop_stages
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    x[i] <= 0;
                    y[i] <= 0;
                    z[i] <= 0;
                end else begin
                    // --- STAGE 0: Initial Rotation & Quadrant Check ---
					if (i == 0) begin
						// Check the top 2 bits to find the Quadrant
						case (target_angle[19:18])
							// Quadrant 1 (0 to 90): Standard Start (0 deg), Rotate +45
							2'b00: begin
								x[0] <= CORDIC_GAIN - 0;
								y[0] <= 0 + CORDIC_GAIN;
								z[0] <= target_angle - DEG_45;
							end

							// Quadrant 2 (90 to 180): Start Backwards (180 deg), Rotate -45
							// X starts negative, Y starts positive (effective 135 deg start)
							2'b01: begin
								x[0] <= -CORDIC_GAIN + 0;
								y[0] <= 0 + CORDIC_GAIN;
								z[0] <= target_angle - DEG_135;
							end

							// Quadrant 3 (-180 to -90): Start Backwards (-180 deg), Rotate +45
							// X starts negative, Y starts negative (effective -135 deg start)
							2'b10: begin
								x[0] <= -CORDIC_GAIN - 0;
								y[0] <= 0 - CORDIC_GAIN;
								z[0] <= target_angle + DEG_135;
							end

							// Quadrant 4 (-90 to 0): Standard Start (0 deg), Rotate -45
							2'b11: begin
								x[0] <= CORDIC_GAIN + 0;
								y[0] <= 0 - CORDIC_GAIN;
								z[0] <= target_angle + DEG_45;
							end
						endcase
                    end 
                    // Subsequent Stages
                    else begin
                        // If z is negative, we need to rotate positive, and vice versa
                        if (z[i-1][19] == 1'b1) begin
                            x[i] <= x[i-1] + (y[i-1] >>> i); // Arithmetic Shift Right
                            y[i] <= y[i-1] - (x[i-1] >>> i);
                            z[i] <= z[i-1] + atan_table[i];
                        end else begin
                            x[i] <= x[i-1] - (y[i-1] >>> i);
                            y[i] <= y[i-1] + (x[i-1] >>> i);
                            z[i] <= z[i-1] - atan_table[i];
                        end
                    end
                end
            end
        end
    endgenerate
	
	// Internal signals are 13-bit (to handle the growth)
    // We clamp them to 12-bit for the output
    logic signed [DATA_WIDTH:0] x_final, y_final;
    assign x_final = x[STAGES-1];
    assign y_final = y[STAGES-1];

    // Clamp Cosine
    always_comb begin
        if (x_final > 2047)      cos_out = 2047;
        else if (x_final < -2048) cos_out = -2048;
        else                      cos_out = x_final[DATA_WIDTH-1:0];
    end

    // Clamp Sine
    always_comb begin
        if (y_final > 2047)      sin_out = 2047;
        else if (y_final < -2048) sin_out = -2048;
        else                      sin_out = y_final[DATA_WIDTH-1:0];
    end

endmodule