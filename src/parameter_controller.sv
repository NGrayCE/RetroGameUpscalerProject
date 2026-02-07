module parameter_controller (
    input  logic clk,             // 74.25 MHz
    input  logic btn_select,      // Button 1 (Mode Cycle)
    input  logic btn_change,      // Button 2 (Value Change)
    
    output logic signed [13:0] contrast_gain,
    output logic signed [13:0] brightness_offset,
    output logic signed [7:0]  saturation_gain     // Controls U and V magnitude
);

    // --- 1. Settings Registers ---
    // Default Values:
    logic signed [13:0] bright_reg = 3000;    // Start at 0 (Middle)
    logic signed [13:0] cont_reg   = 2;    // Start at 4x Contrast
    logic signed [7:0]  sat_reg    = 64;   // Start at 1.0x (assuming /64 later)
    
    // Modes: 0=Brightness (Hold), 1=Contrast (Click), 2=Saturation (Click)
    logic [1:0] mode = 0; 

    // --- 2. Button History & Timers ---
    logic btn_sel_last = 1;
    logic btn_chg_last = 1;
    
    // Timer for "Holding Down" the button (approx 10Hz repeat rate)
    // 74.25 MHz / 7,425,000 = ~10 updates per second
    logic [23:0] repeat_timer = 0;
    logic trigger_change;

    always_ff @(posedge clk) begin
        
        // --- A. Mode Switching (Strict Edge Detect) ---
        // Only cycle when button is FIRST pressed.
        if (btn_select == 0 && btn_sel_last == 1) begin
            if (mode == 2) mode <= 0;
            else           mode <= mode + 1;
        end
        btn_sel_last <= btn_select;


        // --- B. Value Changing (Hybrid Logic) ---
        
        // 1. Determine "Trigger" condition based on Mode
        if (mode == 0 || mode==2) begin
            // MODE 0 (Brightness): Allow Hold
            // Trigger if: (Edge Detect) OR (Button Held AND Timer Rollover)
            if ((btn_change == 0 && btn_chg_last == 1) || (btn_change == 0 && repeat_timer == 0)) begin
                trigger_change <= 1;
            end else begin
                trigger_change <= 0;
            end
        end
        else begin
            // MODES 1 & 2 (Contrast/Sat): Strict Edge Detect
            // Trigger if: Edge Detect ONLY
            if (btn_change == 0 && btn_chg_last == 1) begin
                trigger_change <= 1;
            end else begin
                trigger_change <= 0;
            end
        end

        // 2. Manage the Repeat Timer
        if (btn_change == 0) begin
            // If button is held, run the timer
            if (repeat_timer == 0) repeat_timer <= 24'd7425000; // Reset for 100ms delay
            else                   repeat_timer <= repeat_timer - 1;
        end else begin
            // If button released, reset timer so next press is instant
            repeat_timer <= 0;
        end

        // 3. Execute the Change
        if (trigger_change) begin
            case (mode)
                // BRIGHTNESS (Large Range, Fast Repeat)
                0: begin
                    // Loop -2000 to +2000
                    if (bright_reg > 6000)      bright_reg <= 2000;
                    else                        bright_reg <= bright_reg + 50; 
                end

                // CONTRAST (Small Range, Single Step)
                1: begin
                    // Loop 1x to 16x
                    if (cont_reg >= 16)         cont_reg <= 1;
                    else                        cont_reg <= cont_reg + 1;
                end

                // SATURATION (U/V Gain)
                2: begin
                    // Loop 0x to 4x (assuming 64 is 1.0x)
                    if (sat_reg >= 250)         sat_reg <= 10;
                    else                        sat_reg <= sat_reg + 10;
                end
            endcase
        end

        btn_chg_last <= btn_change;
    end

    // --- 3. Output Assignment ---
    assign contrast_gain     = cont_reg;
    assign brightness_offset = bright_reg;
    assign saturation_gain   = sat_reg;

endmodule