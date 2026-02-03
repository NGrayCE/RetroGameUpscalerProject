module delay_line #(
    parameter int DATA_WIDTH = 12, 
    parameter int DELAY_CYCLES = 8 // Chroma Filter latency
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [DATA_WIDTH-1:0] data_in,
    output logic signed [DATA_WIDTH-1:0] data_out
);

    // Array to hold the history of pixels
    logic signed [DATA_WIDTH-1:0] shift_reg [DELAY_CYCLES-1:0];
    
    integer i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 0;
            for (i = 0; i < DELAY_CYCLES; i++) begin
                shift_reg[i] <= 0;
            end
        end else begin
            // Feed the new pixel into the first bucket
            shift_reg[0] <= data_in;

            // Shift everything down the line
            for (i = 1; i < DELAY_CYCLES; i++) begin
                shift_reg[i] <= shift_reg[i-1];
            end

            // Output the pixel falling out of the last bucket
            data_out <= shift_reg[DELAY_CYCLES-1];
        end
    end

endmodule