//Composite video signal sync detector
//by Nolan Gray

module sync_separator (
    input  logic        clk,            // System Clock (73.8 MHz @ 720p)
    input  logic        rst,
    input  logic        sample_valid,   // Strobe sent to adc (36.9 MHz)
    input  logic [11:0] adc_data,       // Raw video data
    
    output logic        h_sync_pulse,   // Single cycle strobe at START of line
    output logic        v_sync_pulse,   // Single cycle strobe at START of frame
    output logic        active_video,   // High when valid pixel data is present
    output logic [11:0] x_coord         // Useful for debugging
);

    /****Paremeters****/

    // Voltage Threshold: Below this value = SYNC TIP. Above = VIDEO/BLACK.
    // TODO:Use a logic analyzer to find the actual threshold value for this adc
    parameter int SYNC_VOLTAGE_THRESH = 2850; 

    // Timing Thresholds (in 36.9 MHz ticks)
    parameter int HSYNC_MIN_WIDTH = 20;  // Minimum valid HSync (~2.7us)
    parameter int VSYNC_MIN_WIDTH = 800;  // Minimum valid VSync (~21us)
    
    // Back Porch: Time between HSync rising edge and actual image data
    parameter int BACK_PORCH_DELAY = 175; // ~4.7us

    // Screen Width: How many samples to capture per line
    parameter int ACTIVE_WIDTH     = 1920; // Capture 1920 samples and discard 1/3

    /****Logic****/

    logic is_sync_level;
    int   low_counter;
    
    // Internal state
    logic       prev_sync_level;
    logic [11:0] pixel_counter;
    logic        in_active_region;

    assign x_coord = pixel_counter;
    assign active_video = in_active_region;

    //Threshold Comparator
    assign is_sync_level = (adc_data < SYNC_VOLTAGE_THRESH);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            low_counter      <= 0;
            h_sync_pulse     <= 0;
            v_sync_pulse     <= 0;
            pixel_counter    <= 0;
            in_active_region <= 0;
            prev_sync_level  <= 0;
        end else if (sample_valid) begin
            // Reset strobes every sample
            h_sync_pulse <= 0;
            v_sync_pulse <= 0;
            prev_sync_level <= is_sync_level;

            
            // Pulse Width Measurement
            if (is_sync_level) begin
                // Signal is LOW (in sync tip)
                low_counter <= low_counter + 1;
                in_active_region <= 0; // Cannot be active video during sync
            end else begin
                // Signal is HIGH (Video or Blanking)
                // Did we JUST finish a low pulse? (Rising Edge of Sync)
                if (prev_sync_level == 1'b1) begin
                    
                    //Was it a VSYNC?
                    if (low_counter > VSYNC_MIN_WIDTH) begin
                        v_sync_pulse <= 1'b1;
                        // Reset line timing
                        pixel_counter <= 0;
                    end 
                    //Was it an HSYNC?
                    else if (low_counter > HSYNC_MIN_WIDTH) begin
                        h_sync_pulse <= 1'b1;
                        // Reset line timing triggers
                        pixel_counter <= 0; 
                    end
                end
                
                // Reset counter since we are not low anymore
                low_counter <= 0;
            end

            // Horizontal Timing (Back Porch & Capture)

            // We use pixel_counter to track where we are in the scanline
            // 0 -> BACK_PORCH_DELAY : Blanking (Black)
            // BACK_PORCH_DELAY -> END   : Active Video
            
            if (pixel_counter < 4095)
                pixel_counter <= pixel_counter + 1;

            if (pixel_counter > BACK_PORCH_DELAY && pixel_counter <= (BACK_PORCH_DELAY + ACTIVE_WIDTH)) begin
                in_active_region <= 1'b1;
            end else begin
                in_active_region <= 0;
            end
        end
    end

endmodule