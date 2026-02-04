//Top module for composite to hdmi upscaler
//by Nolan Gray

module top (
    input  logic        sys_clk,                //50MHz crystal
    input  logic        rst_n,                  //active low button
    output logic        sys_rst,                //active high reset signal
    
    // HDMI Output
    output logic        tmds_clk_p, tmds_clk_n, //differential wire pairs for HDMI Serial transmission
    output logic [2:0]  tmds_d_p,   tmds_d_n,

    // I2S Audio Interface (PCM1808)
    output logic        i2s_mclk,               // Master Clock (12.288 MHz)
    output logic        i2s_bck,                // Bit Clock (3.07 MHz)
    output logic        i2s_lrck,               // Word Select (L/R channel select) (48 kHz)
    input  logic        i2s_din,                // Serial data in over i2s

    // ADC interface (AD9226)
    output logic        adc_clk,                // Sampling clk sent to the adc
    input  logic        adc_otr,                 // out of range bit
    input logic [11:0]  adc_in                  // 12 bit digital data in
);

/**********HDMI CLOCK GENERATION*************/
    logic clk_pixel;                // This is the main clock for this system
    logic clk_serial;               // For SERDES output
    logic pll_locked;               // System held in reset until pll has locked


    Gowin_PLL hdmi_clocks(
            //INPUTS
            .clkin(sys_clk),        //50MHz
            .init_clk(sys_clk),
            //OUTPUTS
            .clkout0(clk_pixel),    // 74.25 MHz @ 720p
            .clkout1(clk_serial),   // 5x pixel clock ~371.25 MHz
            .lock(pll_locked)
    );
    
/******************POWER UP**********************/

    // Holds reset active for ~300ms after power-up or PLL lock to ensure stability
    logic [23:0] reset_counter;
    logic        sys_rst_delayed;

    always_ff @(posedge sys_clk) begin
        // If PLL unlocks or button is pressed (active low), reset immediately
        if (!pll_locked || !rst_n) begin
            reset_counter   <= 0;
            sys_rst_delayed <= 1'b1;
        end else begin
            // wait ~300 ms
            if (reset_counter != 24'hFFFFFF) begin
                reset_counter   <= reset_counter + 1;
                sys_rst_delayed <= 1'b1; // Keep holding reset
            end else begin
                sys_rst_delayed <= 1'b0; // Release (Boot sequence complete)
            end
        end
    end

    // Move the reset signal safely into the 74MHz clock domain with double flop
    logic hdmi_rst_sync_1, hdmi_rst_sync_2;
    logic hdmi_rst_clean;

    always_ff @(negedge clk_pixel) begin
        if (sys_rst_delayed) begin
            hdmi_rst_sync_1 <= 1'b1;
            hdmi_rst_sync_2 <= 1'b1;
            hdmi_rst_clean  <= 1'b1;
        end else begin
            hdmi_rst_sync_1 <= 1'b0;
            hdmi_rst_sync_2 <= hdmi_rst_sync_1;
            hdmi_rst_clean  <= hdmi_rst_sync_2;
        end
    end
    
    // Assign the main system reset
    assign sys_rst = sys_rst_delayed;

/*********************Audio Clock Generation*********************/
    // --720p--
    // Pixel Clock = 74.25 MHz
    // MCLK Target = 12.288 MHz (~256 * 48kHz)
    // 74.25 / 6 = 12.375 MHz. (Fs = 48.046 kHz) 
    
    logic [2:0] mclk_counter;
    logic       mclk_internal = 0;
    
    always_ff @(posedge clk_pixel) begin
        if (mclk_counter >= 2) begin // Toggle every 3 cycles (Divide by 6)
            mclk_counter <= 0;
            mclk_internal <= ~mclk_internal;
        end else begin
            mclk_counter <= mclk_counter + 1;
        end
    end

    //Generate BCK (MCLK / 4) and LRCK (BCK / 64)
    logic       bck_div;
    logic       bck_internal = 0;
    logic [5:0] lrck_div;
    logic       lrck_internal = 0;

    always_ff @(posedge mclk_internal) begin
        //BCK Generation
        if (bck_div == 0) begin
            bck_internal <= ~bck_internal;
            //LRCK Generation
            if (bck_internal) begin // Falling edge of BCK
                if (lrck_div == 31) begin
                    lrck_div <= 0;
                    lrck_internal <= ~lrck_internal;
                end else begin
                    lrck_div <= lrck_div + 1;
                end
            end
        end
        bck_div <= bck_div + 1;
    end

    //Assign to physical pins
    assign i2s_mclk = mclk_internal;
    assign i2s_bck  = bck_internal;
    assign i2s_lrck = lrck_internal;


    //I2S Receiver
    logic [15:0] sample_l, sample_r;
    
    i2s_rx i2s_rx_inst (
        //INPUTS
        .sck(bck_internal),
        .ws(lrck_internal),
        .sd(i2s_din),

        //OUTPUTS
        .data_l(sample_l),
        .data_r(sample_r)
    );

    //Format for HDMI Audio (2 Channels)
    logic [15:0] audio_sample_word [1:0];

    assign audio_sample_word[1] = sample_l; // Left
    assign audio_sample_word[0] = sample_r; // Right

/*****************VIDEO MODULES******************/

    logic [10:0] cx, cy, frame_width, frame_height, screen_width, screen_height;
    logic [23:0] rgb_data;

    // Sample strobe to send to adc
    // pixel clock / 2 = 37 MHz
    logic adc_enable_strobe;
    always_ff @(posedge clk_pixel or posedge sys_rst) begin
        if (sys_rst) adc_enable_strobe <= 0;
        else         adc_enable_strobe <= ~adc_enable_strobe;
    end

    //Output to physical pin
    assign adc_clk = adc_enable_strobe; 

    //Capture ADC data
    logic [11:0] adc_data_captured;
    always_ff @(posedge clk_pixel) begin
        if (adc_enable_strobe) begin
            adc_data_captured <= adc_in;
        end
    end

    //Signals from sync module
    logic sync_active_video;
    logic sync_h_pulse, sync_v_pulse;
    logic burst_active;

    sync_separator sync_inst (
        //INPUTS
        .clk(clk_pixel),
        .rst(sys_rst),
        .sample_valid(adc_enable_strobe), // Only process when new data arrives
        .adc_data(adc_data_captured),

        //OUTPUTS
        .h_sync_pulse(sync_h_pulse),        // Pulse when line if finished
        .v_sync_pulse(sync_v_pulse),        // Pulse when frame is finished
        .active_video(sync_active_video),    // High during valid capture window
        .burst_active(burst_active)
    );

    //Internal signals for dual port block ram
    logic [23:0] ram_wr_data, ram_rd_data, pp_pixel_out;
    logic [11:0] ram_wr_addr, ram_rd_addr;
    logic        ram_wr_en;

    logic write_qualifier;
    logic hdmi_line_start; 
    logic video_data_period;


    //Only want to write to RAM if we are in active video AND it's a valid sample cycle
    assign write_qualifier = sync_active_video && adc_enable_strobe;

    // Detect start of HDMI line to reset read pointer
    // Reset read pointer on sync detected
    // TODO:is the cy condition still needed?
    assign hdmi_line_start = (cx == 0) || (cy == 0); 

    //Ping pong controller to handle read and write of video buffer
    ping_pong_controller pp_ctrl (
        //INPUTS
        .sample_enable(adc_enable_strobe), 
        .clk(clk_pixel),
        .rst(sys_rst),
        
        // Write Side
        .h_sync_in(sync_h_pulse),
        .v_sync_in(sync_v_pulse),
        .active_video_in(write_qualifier),
        .pixel_data_in(rgb_data),
        
        // Read Side
        .line_reset(hdmi_line_start),      
        .hdmi_request(video_data_period),
        
        //OUTPUTS
        .pixel_data_out(pp_pixel_out),

        // RAM wiring
        .ram_wr_en(ram_wr_en),
        .ram_wr_addr(ram_wr_addr),
        .ram_wr_data(ram_wr_data),
        .ram_rd_addr(ram_rd_addr),
        .ram_rd_data(ram_rd_data)
    );

    Gowin_SDPB video_dpram(
            //INPUTS
            .reset(sys_rst),

            //Write side
            .clka(clk_pixel),   // Run on same clock, ram controller will handle timing
            .cea(ram_wr_en),
            .ada(ram_wr_addr),  // 12 bit address, MSB for buffer select
            .din(ram_wr_data),  // 24 bit data from ADC

            //Read side
            .clkb(clk_pixel),
            .adb(ram_rd_addr),   // 12 bit address, MSB for buffer select
            .ceb(1'b1),         // Leave high, controller handles everything
            .oce(1'b1),

            //OUTPUTS
            .dout(ram_rd_data) // 24 bit output for controller

        );

`ifdef COLOR_BAR
    //Color Bar pattern for testing
    // 720p is 1280 x 720
    always @(posedge clk_pixel) begin
        if (cx < 1280 && cy < 720) begin
            // Simple Color Bar Logic for 720p (Width 1280 / 8 = 160 per bar)
            if      (cx < 160)  rgb <= 24'hFFFFFF; // White
            else if (cx < 320)  rgb <= 24'hFFFF00; // Yellow
            else if (cx < 480)  rgb <= 24'h00FFFF; // Cyan
            else if (cx < 640)  rgb <= 24'h00FF00; // Green
            else if (cx < 800)  rgb <= 24'hFF00FF; // Magenta
            else if (cx < 960)  rgb <= 24'hFF0000; // Red
            else if (cx < 1120) rgb <= 24'h0000FF; // Blue
            else                rgb <= 24'h000000; // Black
        end else begin
            rgb <= 24'h000000;
        end
    end
`else
    // Create a signed version of the input
    logic signed [11:0] adc_signed;
    assign adc_signed = {~adc_data_captured[11], adc_data_captured[10:0]}; // Invert MSB to center at 0

    color_decoder decoder_inst(
        .clk(clk_pixel),
        .rst(sys_rst),
        .adc_raw(adc_signed),
        .burst_active(burst_active),
        .rgb_out(rgb_data)
    );
`endif

    //HDMI Module instantiation 
    logic [2:0] tmds;
    logic tmds_clock; 

    //Video Code 4 == 720p
    hdmi #(.VIDEO_ID_CODE(4),.DVI_OUTPUT(0), 
            .VIDEO_REFRESH_RATE(60.0), .AUDIO_RATE(48000), 
                .AUDIO_BIT_WIDTH(16)) hdmi_inst (
      //INPUTS
      .clk_pixel_x5(clk_serial),
      .clk_pixel(clk_pixel),
      .clk_audio(~lrck_internal),           // Pass inverted clock to prevent race condition with i2S module
      .reset(hdmi_rst_clean),               // Safe reset signal
      .rgb(pp_pixel_out),
      .audio_sample_word(audio_sample_word),    
      .analog_frame_finished(sync_v_pulse), // To synchronize frames
      //OUTPUTS
      .tmds(tmds),
      .tmds_clock(tmds_clock), 
      .cx(cx),
      .cy(cy),
      .frame_width(frame_width),
      .frame_height(frame_height),
      .screen_width(screen_width),
      .screen_height(screen_height),
      .video_data_period(video_data_period)
    );

    //Send HDMI Packet
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),   
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );


endmodule