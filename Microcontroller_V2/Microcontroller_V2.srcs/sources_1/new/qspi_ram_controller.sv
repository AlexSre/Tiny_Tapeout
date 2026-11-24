module qspi_ram_controller(

    input logic clk,
    input logic rst_n,
    
    input logic rise_en,
    input logic fall_en,
    
    output logic qspi_enable,
    
    input logic ram_req,
    input logic ram_write,
    
    input logic ram_byte,
    
    input logic[22:0] ram_addr,
    input logic[31:0] ram_wdata,
    
    output logic[31:0] ram_rdata,
    output logic ram_ready,
    
    output logic ram_cs_n,
    input logic[3:0] ram_sd_in,
    output logic[3:0] ram_sd_out,
    output logic[3:0] ram_sd_oe,
    
    output logic init_done

    );
    
    localparam POWER_WAIT = 4'd0;
    localparam WAIT_DELAY = 4'd1;
    localparam PREPARE = 4'd2;
    localparam START= 4'd3;
    localparam COMMAND = 4'd4;
    localparam ADDRESS = 4'd5;
    localparam DUMMY = 4'd6;
    localparam READ_DATA = 4'd7;
    localparam WRITE_DATA = 4'd8;
    localparam FINISH = 4'd9;
    localparam IDLE = 4'd10;
    localparam RESPONSE = 4'd11;
  
    localparam P_RESET_ENABLE =2'd0;
    localparam P_RESET = 2'd1;
    localparam P_NORMAL = 2'd2;
    
    localparam POWER_COUNT = 13'd5039;
    localparam RESET_COUNT = 13'd2519;
    
    logic[3:0] state;
    logic[1:0] phase;
    
    logic[12:0] wait_count;
    
    logic[7:0] command_shift;
    logic[23:0] address_shift;
    logic[31:0] write_shift;
    logic[31:0] read_shift;
    
    logic[3:0] command_left;
    logic[3:0] address_left;
    logic[3:0] dummy_left;
    logic[3:0] data_left;

    logic write_saved;
    logic byte_saved;
    
    logic cs_active;
    
    logic[3:0] sd_out_reg;
    logic[3:0] sd_oe_reg;
    
    assign ram_cs_n = !(rst_n && cs_active);
    
    assign ram_sd_out = sd_out_reg;
    assign ram_sd_oe = rst_n ? sd_oe_reg : 4'b0000;
    
    assign ram_ready = rst_n && (state == RESPONSE) && ram_req;
    
    always_ff @(posedge clk)
    begin
        
        if(!rst_n)
        begin
            
            state <= POWER_WAIT;
            phase <= P_RESET_ENABLE;
            
            wait_count <= POWER_COUNT;
            
            command_shift <= 8'd0;
            address_shift <= 24'd0;
            write_shift <= 32'd0;
            read_shift <= 32'd0;
            
            command_left <= 4'd0;
            address_left <= 4'd0;
            dummy_left <= 4'd0;
            data_left <= 4'd0;
            
            write_saved <= 1'b0;
            byte_saved <= 1'b0;
            
            cs_active <= 1'b0;
            
            sd_out_reg <= 4'b0000;
            sd_oe_reg <= 4'b0000;
            
            qspi_enable <= 1'b0;
            init_done <= 1'b0;
            ram_rdata <= 32'd0;
            
        end
        else
        begin
            case (state)

                POWER_WAIT:
                begin
                    qspi_enable <= 1'b0;
                    cs_active   <= 1'b0;
                    sd_out_reg  <= 4'b0000;
                    sd_oe_reg   <= 4'b1111;

                    if (wait_count == 13'd0)
                    begin
                        sd_oe_reg   <= 4'b0000;
                        qspi_enable <= 1'b1;

                        wait_count <= 13'd3;
                        state <= WAIT_DELAY;
                    end
                    else
                    begin
                        wait_count <= wait_count - 13'd1;
                    end
                end

                WAIT_DELAY:
                begin
                    if (wait_count == 13'd0)
                    begin
                        if (phase == P_NORMAL)
                        begin
                            init_done <= 1'b1;
                            state <= IDLE;
                        end
                        else
                        begin
                            state <= PREPARE;
                        end
                    end
                    else
                    begin
                        wait_count <= wait_count - 13'd1;
                    end
                end

                PREPARE:
                begin
                    command_left <= 4'd8;

                    if (phase == P_RESET_ENABLE)
                        command_shift <= 8'h66;
                    else
                        command_shift <= 8'h99;

                    state <= START;
                end

                START:
                begin
                    if (fall_en)
                    begin
                        cs_active <= 1'b1;

                        sd_oe_reg <= 4'b0001;
                        sd_out_reg <= {
                            3'b000, command_shift[7]
                        };

                        state <= COMMAND;
                    end
                end

                COMMAND:
                begin
                    if (rise_en)
                    begin
                        command_shift <= {
                            command_shift[6:0], 1'b0
                        };

                        if (command_left == 4'd1)
                        begin
                            if (phase == P_NORMAL)
                            begin
                                address_left <= 4'd6;
                                state <= ADDRESS;
                            end
                            else
                            begin
                                state <= FINISH;
                            end
                        end
                        else
                        begin
                            command_left <= command_left - 4'd1;
                        end
                    end

                    if (fall_en)
                    begin
                        sd_out_reg <= {
                            3'b000, command_shift[7]
                        };
                    end
                end

                ADDRESS:
                begin
                    if (fall_en)
                    begin
                        sd_oe_reg  <= 4'b1111;
                        sd_out_reg <= address_shift[23:20];
                    end

                    if (rise_en)
                    begin
                        address_shift <= {
                            address_shift[19:0], 4'b0000
                        };

                        if (address_left == 4'd1)
                        begin
                            if (write_saved)
                            begin
                                state <= WRITE_DATA;
                            end
                            else
                            begin
                                dummy_left <= 4'd6;
                                state <= DUMMY;
                            end
                        end
                        else
                        begin
                            address_left <= address_left - 4'd1;
                        end
                    end
                end

                DUMMY:
                begin
                    if (fall_en)
                    begin
                        sd_oe_reg <= 4'b0000;
                    end

                    if (rise_en)
                    begin
                        if (dummy_left == 4'd1)
                        begin
                            state <= READ_DATA;
                        end
                        else
                        begin
                            dummy_left <= dummy_left - 4'd1;
                        end
                    end
                end

                READ_DATA:
                begin
                    if (rise_en)
                    begin
                        read_shift <= {
                            read_shift[27:0], ram_sd_in
                        };

                        if (data_left == 4'd1)
                        begin
                            state <= FINISH;
                        end
                        else
                        begin
                            data_left <= data_left - 4'd1;
                        end
                    end
                end

                WRITE_DATA:
                begin
                    if (fall_en)
                    begin
                        sd_oe_reg  <= 4'b1111;
                        sd_out_reg <= write_shift[31:28];
                    end

                    if (rise_en)
                    begin
                        write_shift <= {
                            write_shift[27:0], 4'b0000
                        };

                        if (data_left == 4'd1)
                        begin
                            state <= FINISH;
                        end
                        else
                        begin
                            data_left <= data_left - 4'd1;
                        end
                    end
                end

                FINISH:
                begin
                    if (fall_en)
                    begin
                        cs_active <= 1'b0;
                        sd_oe_reg <= 4'b0000;

                        if (phase == P_NORMAL)
                        begin
                            if (!write_saved)
                            begin
                                if (byte_saved)
                                begin
                                    ram_rdata <= {
                                        24'd0, read_shift[7:0]
                                    };
                                end
                                else
                                begin
                                    ram_rdata <= {
                                        read_shift[7:0],
                                        read_shift[15:8],
                                        read_shift[23:16],
                                        read_shift[31:24]
                                    };
                                end
                            end

                            state <= RESPONSE;
                        end
                        else
                        begin
                            if (phase == P_RESET_ENABLE)
                                phase <= P_RESET;
                            else
                                phase <= P_NORMAL;

                            wait_count <= RESET_COUNT;
                            state <= WAIT_DELAY;
                        end
                    end
                end

                IDLE:
                begin
                    if (ram_req)
                    begin
                        write_saved <= ram_write;
                        byte_saved  <= ram_byte;

                        address_shift <= {1'b0, ram_addr};

                        if (ram_write)
                            command_shift <= 8'h38;
                        else
                            command_shift <= 8'hEB;

                        command_left <= 4'd8;

                        if (ram_byte)
                        begin
                            data_left <= 4'd2;

                            write_shift <= {
                                ram_wdata[7:0], 24'd0
                            };
                        end
                        else
                        begin
                            data_left <= 4'd8;

                            write_shift <= {
                                ram_wdata[7:0],
                                ram_wdata[15:8],
                                ram_wdata[23:16],
                                ram_wdata[31:24]
                            };
                        end

                        read_shift <= 32'd0;
                        ram_rdata  <= 32'd0;

                        state <= START;
                    end
                end

                RESPONSE:
                begin
                    if (!ram_req)
                        state <= IDLE;
                end

                default:
                begin
                    cs_active <= 1'b0;
                    sd_oe_reg <= 4'b0000;

                    qspi_enable <= 1'b0;
                    init_done <= 1'b0;

                    phase <= P_RESET_ENABLE;
                    wait_count <= POWER_COUNT;
                    state <= POWER_WAIT;
                end

            endcase
        end
        
    end
    
endmodule
