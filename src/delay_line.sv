module delay_line #(
    parameter int DATA_WIDTH = 12, 
    parameter int DELAY_CYCLES = 8
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [DATA_WIDTH-1:0] data_in,
    output logic signed [DATA_WIDTH-1:0] data_out
);

    logic signed [DATA_WIDTH-1:0] shift_reg [DELAY_CYCLES-1:0];
    integer i;

    // Separate the array logic (No Reset) from the output logic (Reset)
    always_ff @(posedge clk) begin
        // Only Clock, no Reset for the array
        shift_reg[0] <= data_in;
        for (i = 1; i < DELAY_CYCLES; i++) begin
            shift_reg[i] <= shift_reg[i-1];
        end
    end

    // Output can still be reset safely
    always_ff @(posedge clk or posedge rst) begin
        if (rst) 
            data_out <= 0;
        else 
            data_out <= shift_reg[DELAY_CYCLES-1];
    end

endmodule