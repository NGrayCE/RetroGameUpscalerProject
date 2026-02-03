module color_decoder (
    input logic clk,             // 37 MHz or 74 MHz
    input logic rst,
    input logic [11:0] adc_raw,  // Raw composite input
    input logic burst_active,      // From sync separator
    
    output logic [23:0] rgb_out	 //output pixel for hdmi
);
     // 1. Digital PLL to lock 3.58MHz Sine/Cos to burst
	// Pre-calculated tuning word to match ntsc color burst frequency
	// (3.579545 / 74.25) * 2^32
    localparam int NOMINAL_INCREMENT = 32'd207078536;
	
	// Offset from pi controller
	logic signed [15:0] loop_filter_offset; 
    
    logic [31:0] current_phase_increment;
	
	always_comb begin
        current_phase_increment = NOMINAL_INCREMENT + loop_filter_offset;
    end

    logic signed [11:0] sin_val, cos_val;
	
	nco_sine_generator nco_inst (
        .clk(clk),
        .rst(rst),
        .phase_inc(current_phase_increment),
        .sin_val(sin_val),
        .cos_val(cos_val)
    );
	
	
    // 2. Separate Y (Luma) and C (Chroma)
    logic signed [11:0] y_luma, c_chroma;
	yc_separator separator(
			.clk(clk),
			.rst(rst),
			.data_in(adc_raw),
			.luma_out(y_luma),
			.chroma_out(c_chroma)
	);
	
	logic signed [11:0] luma_delayed;
	// Need to delay luma signal to align with the chroma pipeline
	delay_line luma_delay(
			.clk(clk),
			.rst(rst),
			.data_in(y_luma),
			.data_out(luma_delayed)	//luma ready for output
	);
	
	
    // 3. Demodulate C into U/V
    logic signed [11:0] u_val, v_val;
	// u and v before filtering
	logic signed [11:0] u_pre, v_pre;
    
	assign v_pre = c_chroma * cos_val;
	assign u_pre = c_chroma * sin_val;
 
	//average filter latency is 8 cycles
	simple_average_filter v_filter(
			.clk(clk),
			.rst(rst),
			.data_in(v_pre),
			.data_out(v_val)	//demodulated v
	);
	
	simple_average_filter u_filter(
			.clk(clk),
			.rst(rst),
			.data_in(u_pre),
			.data_out(u_val)	//demodulated u
	);
	
	// raw color burst is alinged to the "blue" phase so demodulate the red to find the error
	logic signed [23:0] v_mult;
	assign v_mult = c_chroma * cos_val;
	
	// 12 bit error value
	logic signed [11:0] v_error;
	assign v_error = v_mult[22:11];
	
    // Instantiate Loop Filter
    loop_filter pll_loop (
        .clk(clk),
        .rst(rst),
        .burst_active(burst_active),    // From sync_separator
        .error_in(v_error),         // The "Red" seen during burst
        .offset_out(loop_filter_offset) // The correction value
    );

    // Convert back to Unsigned for RGB conversion
    // We treat this as a 13-bit signed number to prevent overflow during the math inside yuv_to_rgb
    logic signed [12:0] luma_for_rgb;
    
    // Invert MSB again: -2048 becomes 0, +2047 becomes 4095
    assign luma_for_rgb = {1'b0, ~luma_delayed[11], luma_delayed[10:0]};

    // 4. CSC Matrix to RGB
    yuv_to_rgb color_converter(
			.clk(clk),
			.rst(rst),
			.y_in(luma_for_rgb),
			.u_in(u_val),
			.v_in(v_val),
			.rgb_out(rgb_out)
	);
	
endmodule