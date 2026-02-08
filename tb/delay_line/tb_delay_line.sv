`timescale 1ns/1ps

module tb_delay_line();
    logic clk = 0;
    logic rst = 0;
    logic signed [11:0] data_in = 0;
    logic signed [11:0] data_out;

    // Generate Clock (74.25 MHz is approx 13.4ns period)
    always #6.7 clk = ~clk; 

    // Instantiate your module
    delay_line #(.DELAY_CYCLES(8)) dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .data_out(data_out)
    );

    initial begin
        // Setup Waveform dumping for GTKWave
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_delay_line);

        // Test Sequence
        rst = 1; #20; 
        rst = 0; #20;

        // Feed data 10, 20, 30...
        for (int i=0; i<20; i++) begin
            @(posedge clk);
            data_in <= i * 10;
        end
        
        #100;
        $finish;
    end
endmodule