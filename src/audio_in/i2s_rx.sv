//I2S protocol implementation for communicating with pcm1808 audio adc
//by Nolan Gray

module i2s_rx (
    input  logic sck,    // Serial Clock (BCK)
    input  logic ws,     // Word Select (LRCK)
    input  logic sd,     // Serial Data (DIN)
    output logic [15:0] data_l,
    output logic [15:0] data_r
);
    logic ws_d;
    logic [5:0] bit_cnt;
    logic [15:0] shift_reg;

    always_ff @(posedge sck) begin
        ws_d <= ws;

        //Detect edge
        if (ws != ws_d) begin
            bit_cnt <= 0;
            if (ws_d == 0) data_l <= shift_reg;
            else           data_r <= shift_reg;
        end 
        else begin
            //Standard I2S: Skip Bit 0, Capture 1..16
            bit_cnt <= bit_cnt + 1;
            
            if (bit_cnt >= 1 && bit_cnt <= 16) begin
                shift_reg <= {shift_reg[14:0], sd};
            end
        end
    end
endmodule