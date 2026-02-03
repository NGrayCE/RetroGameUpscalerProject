module simple_average_filter #(
    parameter int DATA_WIDTH = 12,
    parameter int WINDOW_SIZE = 16 // Must be Power of 2 (e.g., 16)
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [DATA_WIDTH-1:0] data_in,
    
    output logic signed [DATA_WIDTH-1:0] data_out
);

    //History Buffer
    logic signed [DATA_WIDTH-1:0] shift_reg [WINDOW_SIZE-1:0];
    
    // Accumulator (Need extra bits for sum: 12 + 4 = 16 bits minimum)
    logic signed [19:0] accumulator;
    
    integer i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
            data_out    <= 0;
            for (i = 0; i < WINDOW_SIZE; i++) shift_reg[i] <= 0;
        end else begin
            // Add new, subtract old
            accumulator <= accumulator + data_in - shift_reg[WINDOW_SIZE-1];

            // Shift history
            shift_reg[0] <= data_in;
            for (i = 1; i < WINDOW_SIZE; i++) shift_reg[i] <= shift_reg[i-1];

            // Output Average (Divide by 16 = Shift Right 4)
            data_out <= accumulator >>> 4; 
        end
    end

endmodule