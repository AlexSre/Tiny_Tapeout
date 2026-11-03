module qspi_flash_controller(
    
    input logic clk,
    input logic rst_n,
    
    input logic rise_en,
    input logic fall_en,
    
    input logic flash_req,
    input logic[23:0] flash_addr,
    output logic[31:0] flash_rdata,
    output logic flash_ready,
    
    output logic flash_cs_n,
    input logic[3:0] flash_sd_in,
    output logic[3:0] flash_sd_out,
    output logic[3:0] flash_sd_oe,
    
    output logic init_done,
    output logic init_error    
    
    );

    localparam WAIT_DELAY = 4'd0;
    localparam PREPARE = 4'd1;
    localparam START = 4'd2;
    localparam SEND = 4'd3;
    localparam READ_STATUS = 4'd4;
    localparam DUMMY = 4'd5;
    localparam READ_QUAD = 4'd6;
    localparam FINISH = 4'd7;
    localparam IDLE = 4'd8;
    localparam RESPONSE = 4'd9;
    localparam ERROR = 4'd10;
    
    localparam P_RELEASE = 3'd0;
    localparam P_RESET_ENABLE = 3'd1;
    localparam P_RESET = 3'd2;
    localparam P_READ_STATUS = 3'd3;
    localparam P_WRITE_ENABLE = 3'd4;
    localparam P_WRITE_STATUS = 3'd5;
    localparam P_VERIFY = 3'd6;
    localparam P_NORMAL = 3'd7;
    
    localparam POWER_WAIT = 18'd151199;
    localparam INIT_WAIT  = 18'd2519;
    
    logic [3:0]  state;
    logic [2:0]  phase;

    logic [17:0] wait_count;
    logic [31:0] tx_shift;
    logic [5:0]  tx_left;

    logic [7:0]  status2;
    logic [3:0]  rx_left;
    logic [3:0]  dummy_left;
    logic [31:0] rx_shift;

    logic        cs_active;
    logic [3:0]  sd_out_reg;
    logic [3:0]  sd_oe_reg;

    assign flash_cs_n = !(rst_n && cs_active);

    assign flash_sd_out = sd_out_reg;
    assign flash_sd_oe  = rst_n ? sd_oe_reg : 4'b0000;

    assign flash_ready =
        rst_n && (state == RESPONSE) && flash_req;

    always_ff @(posedge clk)
    begin
        if (!rst_n)
        begin
        
            state        <= WAIT_DELAY;
            phase        <= P_RELEASE;
            wait_count   <= POWER_WAIT;

            tx_shift     <= 32'd0;
            tx_left      <= 6'd0;
            status2      <= 8'd0;
            rx_left      <= 4'd0;
            dummy_left   <= 4'd0;
            rx_shift     <= 32'd0;

            cs_active    <= 1'b0;
            sd_out_reg   <= 4'b1100;
            sd_oe_reg    <= 4'b0000;

            flash_rdata  <= 32'd0;
            init_done    <= 1'b0;
            init_error   <= 1'b0;
        
        end
        else
        begin
        
            case (state)

                WAIT_DELAY:
                begin
        
                    if (wait_count == 18'd0)
                        state <= PREPARE;
        
                    else
        
                        wait_count <= wait_count - 18'd1;
        
                end

                PREPARE:
                begin

                    tx_left <= 6'd8;
                    state   <= START;

                    case (phase)

                        P_RELEASE:
                        begin

                            tx_shift <= {8'hAB, 24'd0};
        
                        end

                        P_RESET_ENABLE:
                        begin
        
                            tx_shift <= {8'h66, 24'd0};
        
                        end

                        P_RESET:
                        begin
        
                            tx_shift <= {8'h99, 24'd0};
        
                        end

                        P_READ_STATUS, P_VERIFY:
                        begin

                            tx_shift <= {8'h35, 24'd0};
        
                        end

                        P_WRITE_ENABLE:
                        begin

                            tx_shift <= {8'h50, 24'd0};
                        end

                        P_WRITE_STATUS:
                        begin

                            tx_shift <= { 8'h31, (status2 | 8'h02), 16'd0 };
                            tx_left <= 6'd16;
                        
                        end

                        default:
                        begin
                        
                            state      <= ERROR;
                            init_error <= 1'b1;
                        
                        end

                    endcase
                end

                START:
                begin

                    if (fall_en)
                    begin
                        
                        cs_active <= 1'b1;

                        sd_oe_reg  <= 4'b1101;
                        sd_out_reg <= {2'b11, 1'b0, tx_shift[31]};

                        state <= SEND;
                    
                    end
                
                end

                SEND:
                begin
                
                    if (rise_en)
                    begin

                        if (tx_left == 6'd1)
                        begin
                
                            if ((phase == P_READ_STATUS) || (phase == P_VERIFY))
                            begin
                                
                                status2 <= 8'd0;
                                rx_left <= 4'd8;
                                state   <= READ_STATUS;
                            
                            end
                            else if (phase == P_NORMAL)
                            begin
                            
                                dummy_left <= 4'd8;
                                state      <= DUMMY;
                            
                            end
                            else
                            begin
                            
                                state <= FINISH;
                            
                            end
                        end
                        else
                        begin
                            
                            tx_left <= tx_left - 6'd1;
                        
                        end
                    end

                    if (fall_en)
                    begin
                        
                        tx_shift <= {tx_shift[30:0], 1'b0};
                        sd_out_reg <= { 2'b11, 1'b0, tx_shift[30] };
                    
                    end
                
                end

                READ_STATUS:
                begin
                
                    if (rise_en)
                    begin
                
                        status2 <= { status2[6:0], flash_sd_in[1] };

                        if (rx_left == 4'd1)
                        
                            state <= FINISH;
                        
                        else
                        
                            rx_left <= rx_left - 4'd1;
                   
                    end
                
                end

                DUMMY:
                begin
                
                    if (fall_en)
                
                        sd_oe_reg <= 4'b0000;

                    if (rise_en)
                    begin
                
                        if (dummy_left == 4'd1)
                        begin
                
                            rx_shift <= 32'd0;
                            rx_left  <= 4'd8;
                            state    <= READ_QUAD;
                
                        end
                        else
                        begin
                
                            dummy_left <= dummy_left - 4'd1;
                
                        end
                
                    end
                
                end

                READ_QUAD:
                begin
                
                    if (rise_en)
                    begin
                
                        rx_shift <= { rx_shift[27:0], flash_sd_in };

                        if (rx_left == 4'd1)
                            
                            state <= FINISH;
                        
                        else
                           
                            rx_left <= rx_left - 4'd1;
                    
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
                
                            flash_rdata <= { rx_shift[7:0], rx_shift[15:8], rx_shift[23:16], rx_shift[31:24] };
                            state <= RESPONSE;
                        
                        end
                        else
                        begin
                        
                            wait_count <= INIT_WAIT;
                            state      <= WAIT_DELAY;

                            case (phase)

                                P_RELEASE:
                                begin
                                
                                    phase <= P_RESET_ENABLE;
                                
                                end
                                
                                P_RESET_ENABLE:
                                begin
                                   
                                    phase <= P_RESET;

                                end

                                P_RESET:
                                begin
                                
                                    phase <= P_READ_STATUS;

                                end

                                P_READ_STATUS:
                                begin
                        
                                    if (status2[1])
                                    begin
                        
                                        phase     <= P_NORMAL;
                                        init_done <= 1'b1;
                                        state     <= IDLE;
                        
                                    end
                                    else
                                    begin
                        
                                        phase <= P_WRITE_ENABLE;
                        
                                    end
                        
                                end

                                P_WRITE_ENABLE:
                                begin
                        
                                    phase <= P_WRITE_STATUS;
                                    
                                end

                                P_WRITE_STATUS:
                                begin
                        
                                    phase <= P_VERIFY;
                                
                                end

                                P_VERIFY:
                                begin
                        
                                    if (status2[1])
                                    begin
                        
                                        phase     <= P_NORMAL;
                                        init_done <= 1'b1;
                                        state     <= IDLE;
                        
                                    end
                                    else
                                    begin
                        
                                        init_error <= 1'b1;
                                        state      <= ERROR;
                        
                                    end
                        
                                end

                                default:
                                begin
                        
                                    init_error <= 1'b1;
                                    state      <= ERROR;
                        
                                end

                            endcase
                        
                        end
                    
                    end
                
                end

                IDLE:
                begin
                
                    if (flash_req)
                    begin
                
                        tx_shift <= {8'h6B, flash_addr};
                        tx_left  <= 6'd32;
                        state    <= START;
                
                    end
                
                end

                RESPONSE:
                begin
                
                    if (!flash_req)
                        state <= IDLE;
                
                end

                ERROR:
                begin
                
                    cs_active <= 1'b0;
                    sd_oe_reg <= 4'b0000;
                
                end

                default:
                begin
                
                    cs_active  <= 1'b0;
                    sd_oe_reg  <= 4'b0000;
                    init_done  <= 1'b0;
                    init_error <= 1'b1;
                    state      <= ERROR;
                
                end

            endcase
       
        end
    
    end

endmodule
