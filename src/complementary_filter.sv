module yc_separator #(
    parameter int DATA_WIDTH = 12,
    //This might need to be smaller to capture higher res of luma
    parameter int WINDOW_SIZE = 32 // Power of 2 (32 taps @ 74MHz ~= 2.3MHz cutoff)
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic   signed   [DATA_WIDTH-1:0] data_in,
	
	output logic signed [DATA_WIDTH-1:0] luma_out,
    output logic signed [DATA_WIDTH-1:0] chroma_out
);

    // shift Register (History)
    // We need to keep the last 'WINDOW_SIZE' pixels to calculate the average.
    logic signed [DATA_WIDTH-1:0] shift_reg [WINDOW_SIZE-1:0];
    
    // Accumulator (Running Sum)
    // Must be wide enough to hold WINDOW_SIZE * MaxValue.
    // 12 bits + 5 bits (for 32) = 17 bits needed. 24 is safe
    logic signed [23:0] accumulator;
    
    logic signed [DATA_WIDTH-1:0] center_pixel;

    // Pipelining
    integer i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
            luma_out    <= 0;
            chroma_out  <= 0;
            for (i = 0; i < WINDOW_SIZE; i++) begin
                shift_reg[i] <= 0;
            end
        end else begin
            // Moving window average to avoid 32 additions per cycle
            // New Sum = Old Sum + New Pixel - Oldest Pixel in buffer
            accumulator <= accumulator + data_in - shift_reg[WINDOW_SIZE-1];

            // Shift the history buffer
            shift_reg[0] <= data_in;
            for (i = 1; i < WINDOW_SIZE; i++) begin
                shift_reg[i] <= shift_reg[i-1];
            end

            // Calculate Low Pass (Luma)
            // Since WINDOW_SIZE is 32, we divide by shifting right 5 bits.
            luma_out = accumulator >>> 5; // Divide by 32

            // Calculate High Pass (Chroma)
            // HighPass = CenterPixel - Average
            // IMPORTANT: We must subtract the average from the CENTER of the window
            // to match the phase delay. The center of 32 is index 15 or 16.
			// the average calculated from the luma if effectivly 16 cycles delayed
			// i.e it describes the pixel 16 cycles ago
            center_pixel = shift_reg[WINDOW_SIZE/2 - 1];

            chroma_out <= center_pixel - luma_out;
        end
    end

endmodule