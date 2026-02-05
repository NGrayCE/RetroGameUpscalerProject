module color_decoder (
    input logic clk,             // 37 MHz or 74 MHz
    input logic rst,
    input logic signed [12:0] adc_raw,  // Raw composite input
    input logic burst_active,      // From sync separator
    
    output logic [23:0] rgb_out	 //output pixel for hdmi
);
     // 1. Digital PLL to lock 3.58MHz Sine/Cos to burst
	// Pre-calculated tuning word to match ntsc color burst frequency
	// (3.579545 / 74.25) * 2^32
    localparam int NOMINAL_INCREMENT = 32'd205007859;//32'd207078536;
	
	// Offset from pi controller
	logic signed [31:0] loop_filter_offset; 
    
    logic signed [31:0] current_phase_increment;
	
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

    // --- NEW: Filter Luma to remove 3.58MHz noise ---
    logic signed [11:0] y_luma_filtered;
    
    luma_notch_filter luma_filter(
        .clk(clk),
        .rst(rst),
        .data_in(y_luma),
        .data_out(y_luma_filtered) // Latency is likely ~8 cycles
    );

	
    // 3. Demodulate C into U/V
    logic signed [11:0] u_val, v_val;
	logic signed [11:0] u_pre, v_pre;
	logic signed [23:0] u_mult, v_mult;
    
	assign v_mult = c_chroma * cos_val;
	assign u_mult = c_chroma * sin_val;
	
    assign v_pre = (v_mult >>> 11); 
    assign u_pre = (u_mult >>> 11);
 


    logic signed [11:0] v_filter_out, u_filter_out;
	//average filter latency is 8 cycles
	simple_average_filter v_filter(
			.clk(clk),
			.rst(rst),
			.data_in(v_pre),
			.data_out(v_filter_out)	//demodulated v
	);
	
	simple_average_filter u_filter(
			.clk(clk),
			.rst(rst),
			.data_in(u_pre),
			.data_out(u_filter_out)	//demodulated u
	);
// TINT CORRECTION LOGIC
    // Try these combinations if colors are wrong:
    // 1. Normal:       v_val = v_filter_out; u_val = u_filter_out;
    // 2. Invert V:     v_val = -v_filter_out; u_val = u_filter_out;  (Fixes Cyan Faces)
    // 3. Swap:         v_val = u_filter_out; u_val = v_filter_out;   (Fixes 90 deg rotation)
    // 4. Swap+Invert:  v_val = -u_filter_out; u_val = v_filter_out;
    assign v_val = v_filter_out; 
    assign u_val = u_filter_out;	
	
    // create a delayed version of the burst flag
    logic burst_active_delayed;

    // Simple shift register to delay by ~12 clocks (Match your pipeline depth)
    // You can use the 'delay_line' module you already have
    delay_line #(.DATA_WIDTH(1), .DELAY_CYCLES(12)) burst_delayer (
        .clk(clk),
        .rst(rst),
        .data_in(burst_active),
        .data_out(burst_active_delayed)
    );
    // Instantiate Loop Filter
    loop_filter pll_loop (
        .clk(clk),
        .rst(rst),
        .burst_active(burst_active_delayed),    // From sync_separator
        .error_in(-v_pre),         // The "Red" seen during burst
        .offset_out(loop_filter_offset) // The correction value
    );

    // Convert back to Unsigned for RGB conversion
    // We treat this as a 13-bit signed number to prevent overflow during the math inside yuv_to_rgb
    logic signed [12:0] luma_for_rgb;
    
    // Invert MSB again: -2048 becomes 0, +2047 becomes 4095
    assign luma_for_rgb = {1'b0, ~y_luma_filtered[11], y_luma_filtered[10:0]};

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

module luma_notch_filter (
    input  logic        clk,
    input  logic        rst,
    input  logic signed [11:0] data_in,
    output logic signed [11:0] data_out
);
    // THE MAGIC NUMBER: 21 Taps @ 75MHz = 3.58MHz Notch
    localparam int WINDOW_SIZE = 21;
    
    // RECIPROCAL MATH: 
    // We want to divide by 21. 
    // (1 / 21) * 65536 = 3120.76... round to 3121.
    // So, (x * 3121) >> 16 is approx x / 21.
    localparam int RECIPROCAL = 3121; 

    logic signed [11:0] shift_reg [WINDOW_SIZE-1:0];
    logic signed [17:0] accumulator; // Needs to hold 21 * 12-bit max
    integer i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
            data_out    <= 0;
            for (i = 0; i < WINDOW_SIZE; i++) shift_reg[i] <= 0;
        end else begin
            // 1. Manage Shift Register
            shift_reg[0] <= data_in;
            for (i = 1; i < WINDOW_SIZE; i++) begin
                shift_reg[i] <= shift_reg[i-1];
            end

            // 2. Update Accumulator (Add New, Subtract Old)
            accumulator <= accumulator + data_in - shift_reg[WINDOW_SIZE-1];

            // 3. Apply Division (Multiply by reciprocal and shift)
            // We use a temporary 32-bit calc to prevent overflow during multiply
            data_out <= (accumulator * RECIPROCAL) >>> 16;
        end
    end

endmodule