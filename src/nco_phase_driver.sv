module nco_sine_generator (
    input  logic        clk,
    input  logic        rst,
    
    input  logic [31:0] phase_inc, 
    
    // Outputs
    output logic signed [11:0] sin_val,
    output logic signed [11:0] cos_val
);
	
	
    //Phase Accumulator
    logic [31:0] phase_acc;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            phase_acc <= 0;
        end else begin
            phase_acc <= phase_acc + phase_inc;
        end
    end

    // using top 20 bits for the cordic module
	// target angle is signed to take advantage 
	// of 2s compliment wrapping to map 360 degrees
	
    logic [19:0] cordic_angle;
    assign cordic_angle = phase_acc[31:12];

    // Instantiate CORDIC
    cordic_rotator #(
        .DATA_WIDTH(12),
        .STAGES(12)      // 12 stages for 12-bit precision
    ) cordic_inst (
        .clk(clk),
        .rst(rst),
        .target_angle(cordic_angle),
        .sin_out(sin_val),
        .cos_out(cos_val)
    );

endmodule