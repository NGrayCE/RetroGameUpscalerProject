module yc_separator #(
    parameter int DATA_WIDTH = 12,
    parameter int WINDOW_SIZE = 32
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [DATA_WIDTH-1:0] data_in, //only accepts values -2048 to 2047
    output logic signed [DATA_WIDTH-1:0] luma_out,//is this enough or do we need an extra bit?
    output logic signed [DATA_WIDTH-1:0] chroma_out
);
    localparam SHIFT_AMOUNT = $clog2(WINDOW_SIZE);
    logic signed [DATA_WIDTH-1:0] shift_reg [WINDOW_SIZE-1:0];
    logic signed [DATA_WIDTH + $clog2(WINDOW_SIZE) : 0] accumulator;
    logic signed [DATA_WIDTH-1:0] center_pixel;
    integer i;

    // BLOCK 1: Shift Register (NO RESET)
    always_ff @(posedge clk) begin
        shift_reg[0] <= data_in;
        for (i = 1; i < WINDOW_SIZE; i++) shift_reg[i] <= shift_reg[i-1];
    end

    // BLOCK 2: Math (WITH RESET)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
            luma_out    <= 0;
            chroma_out  <= 0;
        end else begin
            accumulator <= accumulator + data_in - shift_reg[WINDOW_SIZE-1];
            
            // Luma
            luma_out <= accumulator >>> SHIFT_AMOUNT;
            
            // Chroma
            // We read the center pixel from the 'dirty' shift reg, which is fine.
            center_pixel = shift_reg[WINDOW_SIZE/2 - 1];
            chroma_out <= center_pixel - (accumulator >>> SHIFT_AMOUNT);
        end
    end
endmodule