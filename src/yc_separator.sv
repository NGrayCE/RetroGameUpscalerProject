module yc_separator (
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [11:0]      data_in,
    output logic signed [11:0]      luma_out,
    output logic signed [11:0]      chroma_out
);
    // TUNED FOR NTSC @ 74.25 MHz
    // 74.25 / 3.58 = 20.74 -> Round to 21
    localparam int WINDOW_SIZE = 21;
    
    // RECIPROCAL MATH: (1 / 21) * 65536 = 3121
    localparam int RECIPROCAL = 3121;

    logic signed [11:0] shift_reg [WINDOW_SIZE-1:0];
    logic signed [17:0] accumulator; // Expanded to hold sum of 21 * 12-bit
    logic signed [11:0] center_pixel;
    logic signed [12:0] chroma_calc;
    integer i;

    // BLOCK 1: Shift Register
    always_ff @(posedge clk) begin
        shift_reg[0] <= data_in;
        for (i = 1; i < WINDOW_SIZE; i++) 
            shift_reg[i] <= shift_reg[i-1];
    end

    // BLOCK 2: Accumulator & Output
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
            luma_out    <= 0;
            chroma_out  <= 0;
        end else begin
            // 1. Maintain Rolling Sum
            accumulator <= accumulator + data_in - shift_reg[WINDOW_SIZE-1];

            // 2. Calculate Luma (Average)
            // Multiply by 1/21 (approx) and shift down 16 bits
            luma_out <= (accumulator * RECIPROCAL) >>> 16;

            // 3. Calculate Chroma (Delta)
            // Center tap is at index 10 (21 / 2)
            center_pixel = shift_reg[10];
            // Perform subtraction in 13 bits
            chroma_calc = center_pixel - ((accumulator * RECIPROCAL) >>> 16);

            // CLAMP to 12 bits
            if (chroma_calc > 2047)      chroma_out <= 2047;
            else if (chroma_calc < -2048) chroma_out <= -2048;
            else                          chroma_out <= chroma_calc[11:0]; 
            chroma_out   <= center_pixel - ((accumulator * RECIPROCAL) >>> 16);
        end
    end
endmodule