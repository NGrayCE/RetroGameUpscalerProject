module yuv_to_rgb (
    input  logic        clk,
    input  logic        rst,
    
    // Inputs from your Decoder (12-bit Signed/Unsigned)
    input  logic signed [12:0] y_in, // 0 to 4095 (treated as signed for math)
    input  logic signed [11:0] u_in, // -2048 to +2047
    input  logic signed [11:0] v_in, // -2048 to +2047

    // Output to HDMI (Standard 24-bit RGB)
    output logic [23:0] rgb_out
);

    // Coefficients (Scaled by 1024)
    localparam int C_RV = 1167; // 1.140
    localparam int C_GU = 404;  // 0.395
    localparam int C_GV = 595;  // 0.581
    localparam int C_BU = 2081; // 2.032

    // Intermediate Products (Wide enough to hold 12bit * 11bit = 23bit)
    logic signed [23:0] y_scaled;
    logic signed [23:0] r_v, g_u, g_v, b_u;
    
    // Sums (The raw 12-bit scale result)
    logic signed [23:0] r_sum, g_sum, b_sum;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rgb_out <= 0;
            y_scaled <= 0; r_v <= 0; g_u <= 0; g_v <= 0; b_u <= 0;
            r_sum <= 0; g_sum <= 0; b_sum <= 0;
        end else begin
            // STAGE A: Multiplications
            // We multiply Y by 1024 so it matches the scale of the U/V terms
            y_scaled <= y_in * 1024;
            
            r_v <= v_in * C_RV;
            g_u <= u_in * C_GU;
            g_v <= v_in * C_GV;
            b_u <= u_in * C_BU;

            // STAGE B: Summation (Matrix)
            r_sum <= y_scaled + r_v;
            g_sum <= y_scaled - g_u - g_v;
            b_sum <= y_scaled + b_u;

            // STAGE C: Clamping & Downscaling
            // 1. Divide by 1024 (Shift Right 10) to get back to 12-bit scale
            // 2. Divide by 16   (Shift Right 4)  to get to 8-bit scale
            // Total Shift: 14 bits
            
            rgb_out[23:16] <= clamp_and_cast(r_sum); // Red
            rgb_out[15:8]  <= clamp_and_cast(g_sum); // Green
            rgb_out[7:0]   <= clamp_and_cast(b_sum); // Blue
        end
    end

    // Function to Clamp and Convert to 8-bit
    function automatic logic [7:0] clamp_and_cast(input logic signed [23:0] val);
        logic signed [23:0] descaled;
        descaled = val >>> 14; // Divide by 1024 (Math Scale) and 16 (12->8 bit)

        if (descaled < 0) 
            return 8'd0;             // Underflow (Blacker than black)
        else if (descaled > 255) 
            return 8'd255;           // Overflow (Whiter than white)
        else 
            return descaled[7:0];    // Perfect range
    endfunction

endmodule