module video_line_buffer(

    input logic clk,
    input logic rst_n,

    input logic [9:0] x,
    input logic [9:0] y,
    input logic video_on,

    input logic ram_init_done,

    output logic video_req,
    output logic [22:0] video_addr,

    input logic [31:0] video_rdata,
    input logic video_ready,

    output logic [7:0] pixel_data,
    output logic pixel_valid

);

    localparam WAIT_FRAME = 2'd0;
    localparam READ_LINE  = 2'd1;
    localparam RELEASE   = 2'd2;
    localparam WAIT_LINE = 2'd3;

    logic [1:0] state;

    logic [11:0] buffer0 [0:39];
    logic [11:0] buffer1 [0:39];

    logic buffer0_valid;
    logic buffer1_valid;

    logic [6:0] buffer0_line;
    logic [6:0] buffer1_line;

    logic [6:0] load_line;
    logic [5:0] word_index;

    logic start_line;
    logic [6:0] next_line;

    logic display_valid;
    logic [11:0] pixel_group;

    assign video_req = rst_n && (state == READ_LINE);

    assign start_line = (x == 10'd799) && ( ((y < 10'd479) && (y[1:0] == 2'b11)) || (y == 10'd524) );

    assign next_line = (y == 10'd524) ? 7'd0 : (y[8:2] + 7'd1);

    always_comb
    begin
    
        pixel_group = 12'd0;
        pixel_data  = 8'd0;
        pixel_valid = 1'b0;

        if (rst_n && video_on && display_valid && (x < 10'd640) && (y < 10'd480))
        begin
        
            if (y[2])
            
                pixel_group = buffer1[x[9:4]];
                
            else
            
                pixel_group = buffer0[x[9:4]];

            case (x[3:2])

                2'd0:
                    pixel_data = {5'd0, pixel_group[2:0]};

                2'd1:
                    pixel_data = {5'd0, pixel_group[5:3]};

                2'd2:
                    pixel_data = {5'd0, pixel_group[8:6]};

                2'd3:
                    pixel_data = {5'd0, pixel_group[11:9]};

            endcase

            pixel_valid = 1'b1;
            
        end
        
    end

    always_ff @(posedge clk)
    begin
    
        if (!rst_n)
        begin
        
            state <= WAIT_FRAME;

            video_addr <= 23'd0;

            load_line  <= 7'd0;
            word_index <= 6'd0;

            buffer0_valid <= 1'b0;
            buffer1_valid <= 1'b0;

            buffer0_line <= 7'd0;
            buffer1_line <= 7'd0;

            display_valid <= 1'b0;
        
        end
        else
        begin
        
            if (start_line)
            begin
        
                if (next_line[0])
                begin
        
                    display_valid <= buffer1_valid && (buffer1_line == next_line);
        
                end
                else
                begin
        
                    display_valid <= buffer0_valid && (buffer0_line == next_line);
                
                end
            end
            else if ((x == 10'd799) && (y == 10'd479))
            begin
            
                display_valid <= 1'b0;
            
            end

            case (state)

                WAIT_FRAME:
                begin
                    if (ram_init_done && (y >= 10'd480))
                    begin
                        video_addr <= 23'd0;

                        load_line  <= 7'd0;
                        word_index <= 6'd0;

                        buffer0_valid <= 1'b0;
                        buffer1_valid <= 1'b0;

                        state <= READ_LINE;
                    end
                end

                READ_LINE:
                begin
                    if (video_ready)
                    begin
                        if (load_line[0])
                        begin
                            buffer1[word_index] <= {
                                video_rdata[26:24],
                                video_rdata[18:16],
                                video_rdata[10:8],
                                video_rdata[2:0]
                            };

                            if (word_index == 6'd39)
                            begin
                                buffer1_line  <= load_line;
                                buffer1_valid <= 1'b1;
                            end
                        end
                        else
                        begin
                            buffer0[word_index] <= {
                                video_rdata[26:24],
                                video_rdata[18:16],
                                video_rdata[10:8],
                                video_rdata[2:0]
                            };

                            if (word_index == 6'd39)
                            begin
                                buffer0_line  <= load_line;
                                buffer0_valid <= 1'b1;
                            end
                        end

                        state <= RELEASE;
                    end
                end

                RELEASE:
                begin
                    if (!video_ready)
                    begin
                        if (word_index == 6'd39)
                        begin
                            state <= WAIT_LINE;
                        end
                        else
                        begin
                            word_index <= word_index + 6'd1;
                            video_addr <= video_addr + 23'd4;

                            state <= READ_LINE;
                        end
                    end
                end

                WAIT_LINE:
                begin
                    if (start_line && (next_line == load_line))
                    begin
                        if (load_line == 7'd119)
                        begin
                            state <= WAIT_FRAME;
                        end
                        else
                        begin
                            if (load_line[0])
                                buffer0_valid <= 1'b0;
                            else
                                buffer1_valid <= 1'b0;

                            load_line <= load_line + 7'd1;
                            word_index <= 6'd0;

                            video_addr <= video_addr + 23'd4;

                            state <= READ_LINE;
                        end
                    end
                    else if (
                        ((y < 10'd480) && (y[8:2] >= load_line)) ||
                        ((y >= 10'd480) && (load_line != 7'd0))
                    )
                    begin
                        state <= WAIT_FRAME;
                    end
                end

                default:
                begin
                    state <= WAIT_FRAME;

                    buffer0_valid <= 1'b0;
                    buffer1_valid <= 1'b0;
                    display_valid <= 1'b0;
                end

            endcase

            if ((x == 10'd799) && (y == 10'd479))
            begin
                buffer0_valid <= 1'b0;
                buffer1_valid <= 1'b0;
            end
        end
    end

endmodule