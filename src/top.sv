//Top module for composite to hdmi upscaler
//by Nolan Gray

module top (
    input  logic        sys_clk,  
    input  logic        rst_n,     
    output logic        sys_rst,
    
    // HDMI Output
    output logic        tmds_clk_p, tmds_clk_n,
    output logic [2:0]  tmds_d_p,   tmds_d_n,

    // I2S Audio Interface (PCM1808)
    output logic        i2s_mclk, // Master Clock (12.288 MHz)
    output logic        i2s_bck,  // Bit Clock (3.07 MHz)
    output logic        i2s_lrck, // Word Select (L/R channel select) (48 kHz)
    input  logic        i2s_din,   //serial data in over i2s

    // ADC interface (AD9226)
    output logic        adc_clk,  //sampling clk sent to the adc
    input logic [11:0]  adc_in   //12 bit digital data in
);
    //Clock Generation
    logic clk_pixel;  
    logic clk_serial;
    logic pll_locked;


    Gowin_PLL hdmi_clocks(
            .clkin(sys_clk), //input 50MHz
            .init_clk(sys_clk), //input  50MHz
            .clkout0(clk_pixel), //output  73.8MHz @ 720p
            .clkout1(clk_serial), //output  5x pixel clock
            .lock(pll_locked) //output  lock
    );
    
    // Power-On Delay & Debounce
    // Holds reset active for ~300ms after power-up or PLL lock to ensure stability
    logic [23:0] reset_counter;
    logic        sys_rst_delayed;

    always_ff @(posedge sys_clk) begin
        // If PLL unlocks or Button is pressed (Active Low), reset immediately
        if (!pll_locked || !rst_n) begin
            reset_counter   <= 0;
            sys_rst_delayed <= 1'b1;
        end else begin
            // Count until the counter fills up
            if (reset_counter != 24'hFFFFFF) begin
                reset_counter   <= reset_counter + 1;
                sys_rst_delayed <= 1'b1; // Keep holding reset
            end else begin
                sys_rst_delayed <= 1'b0; // Release (Boot sequence complete)
            end
        end
    end

    // Reset Synchronizer for HDMI Domain
    // Moves the reset signal safely into the 74MHz clock domain
    logic hdmi_rst_sync_1, hdmi_rst_sync_2;
    logic hdmi_rst_clean;

    always_ff @(negedge clk_pixel) begin
        if (sys_rst_delayed) begin
            hdmi_rst_sync_1 <= 1'b1;
            hdmi_rst_sync_2 <= 1'b1;
            hdmi_rst_clean  <= 1'b1;
        end else begin
            hdmi_rst_sync_1 <= 1'b0;
            hdmi_rst_sync_2 <= hdmi_rst_sync_1; // Double flop for safety
            hdmi_rst_clean  <= hdmi_rst_sync_2;
        end
    end
    
    // Assign the main system reset
    assign sys_rst = sys_rst_delayed;

    // Audio Clock Generation
    // =========================================================================
    // --720p--
    // Pixel Clock = 73.8 MHz
    // MCLK Target = 12.288 MHz (~256 * 48kHz)
    // 73.8 / 6 = 12.3 MHz. (Fs = 48.046 kHz) 
    
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

    //Assign to Outputs
    assign i2s_mclk = mclk_internal;
    assign i2s_bck  = bck_internal;
    assign i2s_lrck = lrck_internal;


    //I2S Receiver
    logic [15:0] sample_l, sample_r;
    
    i2s_rx i2s_rx_inst (
        .sck(bck_internal),
        .ws(lrck_internal),
        .sd(i2s_din),
        .data_l(sample_l),
        .data_r(sample_r)
    );

    //Format for HDMI Audio (2 Channels)
    logic [15:0] audio_sample_word [1:0];

    assign audio_sample_word[1] = sample_l; // Left
    assign audio_sample_word[0] = sample_r; // Right

/*************************************************************************************
    //Color Bar pattern for testing
    logic [10:0] cx, cy, frame_width, frame_height, screen_width, screen_height;
    logic [23:0] rgb;

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
****************************************************************************************/
    logic [10:0] cx, cy, frame_width, frame_height, screen_width, screen_height;

    //sample strobe to send to adc
    // pixel clock / 2 = 36.9 MHz
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

    sync_separator sync_inst (
        .clk(clk_pixel),
        .rst(sys_rst),
        .sample_valid(adc_enable_strobe), // Only process when new data arrives
        .adc_data(adc_data_captured),
        .h_sync_pulse(sync_h_pulse),
        .v_sync_pulse(sync_v_pulse),
        .active_video(sync_active_video)  // High during valid capture window
    );

    //Internal signals for dual port block ram
    logic [11:0] ram_wr_data, ram_rd_data, pp_pixel_out;
    logic [11:0] ram_wr_addr, ram_rd_addr;
    logic        ram_wr_en;
    
    //Only want to write to RAM if we are in active video AND it's a valid sample cycle
    logic write_qualifier;
    assign write_qualifier = sync_active_video && adc_enable_strobe;

    //Detect start of HDMI line to reset read pointer
    logic hdmi_line_start; 
    logic video_data_period;
    assign hdmi_line_start = (cx == 0); 

    //Ping pong controller to handle read and write of video buffer
    ping_pong_controller pp_ctrl (
        .sample_enable(adc_enable_strobe), 
        .clk(clk_pixel),
        .rst(sys_rst),
        
        // Write Side
        .h_sync_in(sync_h_pulse),
        .active_video_in(write_qualifier),
        .pixel_data_in(adc_data_captured),
        
        // Read Side
        .line_reset(hdmi_line_start),      
        .hdmi_request(video_data_period),
        .pixel_data_out(pp_pixel_out),
        
        // RAM wiring
        .ram_wr_en(ram_wr_en),
        .ram_wr_addr(ram_wr_addr),
        .ram_wr_data(ram_wr_data),
        .ram_rd_addr(ram_rd_addr),
        .ram_rd_data(ram_rd_data)
    );

    Gowin_SDPB video_dpram(
            .dout(ram_rd_data), //output [11:0] dout for hdmi
            .clka(clk_pixel), //input clka
            .cea(ram_wr_en), //input cea  
            .clkb(clk_pixel), //input clkb
            .ceb(1'b1), //input ceb
            .oce(1'b1), //input oce
            .reset(sys_rst), //input reset
            .ada(ram_wr_addr), //input [11:0] ada from controller
            .din(ram_wr_data), //input [11:0] din from adc
            .adb(ram_rd_addr) //input [11:0] adb from controller
        );

    //TODO: Add Chroma filtering for color output
    // For now convert 12-bit monochrome to 24-bit RGB (Grayscale)
    logic [7:0] gray_val;
    assign gray_val = pp_pixel_out[11:4];
    
    logic [23:0] rgb_data;

    always_comb begin
        rgb_data = {gray_val, gray_val, gray_val}; 
    end

    //HDMI Module instantiation 

    logic [2:0] tmds;
    logic tmds_clock; 

    //Video Code 4 == 720p
    hdmi #(.VIDEO_ID_CODE(4),.DVI_OUTPUT(0), .VIDEO_REFRESH_RATE(60.0), .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16)) hdmi_inst (
      .clk_pixel_x5(clk_serial),
      .clk_pixel(clk_pixel),
      .clk_audio(~lrck_internal),
      .reset(hdmi_rst_clean),
      .rgb(rgb_data),
      .audio_sample_word(audio_sample_word),
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

    //Using gowin IP
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),   
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );


endmodule