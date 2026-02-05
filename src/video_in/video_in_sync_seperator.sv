//Composite video signal sync detector
//by Nolan Gray

module sync_separator (
    input  logic        clk,            // HDMI clock
    input  logic        rst,            // active high reset
    input  logic        sample_valid,   // Strobe sent to adc (~37 MHz)
    input  logic [11:0] adc_data,       // Raw video data
    
    output logic        h_sync_pulse,   // signal at start of LINE
    output logic        v_sync_pulse,   // signal at start of FRAME
    output logic        active_video,   // High when valid pixel data is present
    output logic        burst_active,   // high during color burst
    output logic [11:0] sync_threshold,
    output logic [11:0] x_coord         // For debugging
);

    /****PARAMETERS****/

    // Timing Thresholds (in 37 MHz ticks)
    parameter int HSYNC_MIN_WIDTH = 20;  // Minimum valid HSync (~2.7us)
    parameter int VSYNC_MIN_WIDTH = 800;  // Minimum valid VSync (~21us)
    
    // Back Porch: Time between HSync rising edge and actual image data
    parameter int BACK_PORCH_DELAY = 222;//175; // ~4.7us

    // Screen Width: How many samples to capture per line
    parameter int ACTIVE_WIDTH     = 1920; // Capture 1920 samples

    // Fixed "Safety Margin" above the sync tip 
    parameter int SYNC_MARGIN = 250;

    // Burst usually starts ~0.6us after sync and lasts ~2.5us.
    // 0.6us * 37MHz ~= 22 ticks
    // 2.5us * 37MHz ~= 92 ticks
    /****LOGIC****/

    logic is_sync_level;
    int   low_counter;
    
    // Internal state
    logic        prev_sync_level;
    logic [11:0] pixel_counter;
    logic        in_active_region;
    //save when v sync is detected and reset in sync with h sync
    logic v_sync_flag;

    assign burst_active = (pixel_counter > BURST_START && pixel_counter < BURST_END);
    assign x_coord = pixel_counter;
    assign active_video = in_active_region;

    //dynamic threshold comparator
    logic [11:0] sync_tip_val;     // The lowest voltage seen recently
    logic [15:0] leak_counter;     // Timer to slowly "forget" the minimum
    //expose threshold to other modules
    assign sync_threshold = sync_tip_val;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_tip_val <= 12'd4095; // Start high
            leak_counter <= 0;
        end else begin
            //If we see a lower value, grab it immediately
            if (adc_data < sync_tip_val) begin
                sync_tip_val <= adc_data;
            end
            // 2.Slowly raise the floor (Leak) to handle drift
            //~1.7ms response time
            else begin
                leak_counter <= leak_counter + 1;
                if (leak_counter == 16'hFFFF) begin
                    if (sync_tip_val < 12'd4095)
                        sync_tip_val <= sync_tip_val + 1;
                end
            end
        end
    end

    // Dynamic Threshold Calculation
    // Use 13 bits to capture the sum, then clamp it
    wire [12:0] calc_thresh;
    assign calc_thresh = sync_tip_val + SYNC_MARGIN;
    wire [11:0] dynamic_thresh;
    assign dynamic_thresh = (calc_thresh > 13'd4095) ? 12'd4095 : calc_thresh[11:0];
    
    // Use the dynamic threshold to detect sync
    assign is_sync_level = (adc_data < dynamic_thresh);

/********************SYNC DETECTION***********************/

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            low_counter      <= 0;
            h_sync_pulse     <= 0;
            v_sync_pulse     <= 0;
            pixel_counter    <= 0;
            in_active_region <= 0;
            prev_sync_level  <= 0;
            v_sync_flag      <= 0;
        end else if (sample_valid) begin
            // Reset every sample
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
                    
                    // Check for Vertical Sync
                    if (low_counter > VSYNC_MIN_WIDTH) begin
                        // save the flag but don't fire pulse until h sync
                        v_sync_flag <= 1'b1; 
                    end 
                    // Check for Horizontal Sync
                    else if (low_counter > HSYNC_MIN_WIDTH) begin
                        h_sync_pulse <= 1'b1;
                        pixel_counter <= 0; // Reset line timing ONLY on H-Sync

                        // If we have a pending V-Sync, fire it now
                        if (v_sync_flag) begin
                            v_sync_pulse <= 1'b1;
                            v_sync_flag  <= 0; // Clear the flag
                        end
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