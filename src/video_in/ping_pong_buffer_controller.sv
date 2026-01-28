//Ping pong buffer controller for composite video in and hdmi video out
//by Nolan Gray

module ping_pong_controller (
    input  logic        clk,
    input  logic        rst,
    input  logic        sample_enable,
    
    //From Sync Separator
    input  logic        h_sync_in,    // Triggers the buffer swap
    input  logic        active_video_in, //flag for active video data
    input  logic [11:0] pixel_data_in,
    
    //From HDMI Module
    input  logic        line_reset, //for line scaler
    input  logic        hdmi_request, // HDMI module asking for a pixel
    output logic [11:0] pixel_data_out,
    
    // MEMORY INTERFACE
    output logic        ram_wr_en,
    output logic [11:0] ram_wr_addr,
    output logic [11:0] ram_wr_data,
    
    output logic [11:0] ram_rd_addr,
    input  logic [11:0] ram_rd_data
);

    // State variable to track which buffer is being written to
    // 0 = Write to Lower Half, Read from Upper Half
    // 1 = Write to Upper Half, Read from Lower Half
    logic buffer_select; 
    
    //****Write Side****/

    logic [10:0] write_pointer; // 0 to 2047
    logic        prev_h_sync;
    //3:2 scaler needed because we are sampling 1920 pixels but can only output 1280
    logic [1:0]  scale_counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_pointer <= 0;
            buffer_select <= 0;
            prev_h_sync   <= 0;
            ram_wr_en <= 0;
            scale_counter <= 0;
        end else if (sample_enable) begin
            prev_h_sync <= h_sync_in;

            // Detect Rising Edge of HSync -> swap buffer
            if (h_sync_in && !prev_h_sync) begin
                buffer_select <= ~buffer_select; // Toggle A/B
                write_pointer <= 0;              // Reset pointer for new line
                scale_counter <= 0;
            end
            
            // Write data if valid
            if (active_video_in) begin
                //scaling logic
                if (scale_counter == 2) 
                    scale_counter <= 0;
                else 
                    scale_counter <= scale_counter + 1;
                
                if (scale_counter != 2) begin
                    ram_wr_en   <= 1'b1;
                    ram_wr_data <= pixel_data_in;
                    
                    // The address bit [11] determines if we are in Buffer A or B
                    // Bits [10:0] determine the pixel position in that buffer
                    ram_wr_addr <= {buffer_select, write_pointer};

                    if (write_pointer < 2047)
                        write_pointer <= write_pointer + 1;
                end else begin
                    ram_wr_en <= 1'b0; //don't write the third pixel
                end
            end else begin
                ram_wr_en <= 1'b0; //not in active video
            end
        end
    end

    /****Read Side****/

    logic [10:0] read_pointer;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            read_pointer <= 0;
        end else begin
            //TODO:Implement more robust scaling logic
            //for now line doubling will work
            //Reset pointer at start of each line
            if (line_reset) begin
                read_pointer <= 0;
            end 
            else if (hdmi_request) begin
                //Read from the opposite buffer
                ram_rd_addr <= {~buffer_select, read_pointer};
                read_pointer <= read_pointer + 1;
            end
        end
    end
    
    //Pass RAM data to output
    assign pixel_data_out = ram_rd_data;

endmodule