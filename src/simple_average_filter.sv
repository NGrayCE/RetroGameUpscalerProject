module simple_average_filter #(
    parameter int DATA_WIDTH = 12,
    parameter int WINDOW_SIZE = 16 
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [DATA_WIDTH-1:0] data_in,
    output logic signed [DATA_WIDTH-1:0] data_out
);

    // 1. Calculate the Shift Amount automatically
    // log2(32) = 5, log2(16) = 4
    localparam int SHIFT_BITS = $clog2(WINDOW_SIZE);

    logic signed [DATA_WIDTH-1:0] shift_reg [WINDOW_SIZE-1:0];
    logic signed [19:0] accumulator;
    integer i;

    // BLOCK 1: Shift Register (NO RESET)
    always_ff @(posedge clk) begin
        shift_reg[0] <= data_in;
        for (i = 1; i < WINDOW_SIZE; i++) shift_reg[i] <= shift_reg[i-1];
    end

    // BLOCK 2: Accumulator & Output (WITH RESET)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
            data_out    <= 0;
        end else begin
            accumulator <= accumulator + data_in - shift_reg[WINDOW_SIZE-1];
            data_out    <= accumulator >>> SHIFT_BITS;
        end
    end
endmodule