module filter_21tap #(parameter DATA_WIDTH=12)(
    input  logic        clk,
    input  logic        rst,
    input  logic signed [DATA_WIDTH-1:0] data_in,
    output logic signed [DATA_WIDTH-1:0] data_out
);
    // THE MAGIC NUMBER: 21 Taps @ 75MHz = 3.58MHz Notch
    localparam int WINDOW_SIZE = 21;
    
    // RECIPROCAL MATH: 
    // We want to divide by 21. 
    // (1 / 21) * 65536 = 3120.76... round to 3121.
    // So, (x * 3121) >> 16 is approx x / 21.
    localparam int RECIPROCAL = 3121; 

    logic signed [DATA_WIDTH-1:0] shift_reg [WINDOW_SIZE-1:0];
    logic signed [31:0] accumulator; // Needs to hold 21 * 12-bit max
    integer i;

    // BLOCK 1: Shift Register (NO RESET)
    always_ff @(posedge clk) begin
        shift_reg[0] <= data_in;
        for (i = 1; i < WINDOW_SIZE; i++) shift_reg[i] <= shift_reg[i-1];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
            data_out    <= 0;
        end else begin
            // 2. Update Accumulator (Add New, Subtract Old)
            accumulator <= accumulator + data_in - shift_reg[WINDOW_SIZE-1];

            // 3. Apply Division (Multiply by reciprocal and shift)
            // We use a temporary 32-bit calc to prevent overflow during multiply
            data_out <= (accumulator * RECIPROCAL) >>> 16;
        end
    end

endmodule