module ram_arbiter(

    input logic clk,
    input logic rst_n,
    
    input logic ram_init_done,
    
    input logic cpu_req,
    input logic cpu_write,
    input logic cpu_byte,
    input logic[22:0] cpu_addr,
    input logic[31:0] cpu_wdata,
    
    output logic[31:0] cpu_rdata,
    output logic cpu_ready,
    
    input logic video_req,
    input logic[22:0] video_addr,
    
    output logic[31:0] video_rdata,
    output logic video_ready,
    
    output logic ram_req,
    output logic ram_write,
    output logic ram_byte,
    output logic[22:0] ram_addr,
    output logic[31:0] ram_wdata,
    
    input logic[31:0] ram_rdata,
    input logic ram_ready

    );
    
    localparam IDLE = 3'd0;
    localparam CPU_ACCESS = 3'd1;
    localparam VIDEO_ACCESS = 3'd2;
    localparam CPU_RESPONSE = 3'd3;
    localparam VIDEO_RESPONSE = 3'd4;
    
    logic[2:0] state;
    
    assign ram_req = rst_n && ((state == CPU_ACCESS) || (state == VIDEO_ACCESS));
    
    assign cpu_ready = rst_n && (state == CPU_RESPONSE) && cpu_req;
    
    assign video_ready = rst_n && (state == VIDEO_RESPONSE) && video_req;
    
    always_ff @(posedge clk)
    begin
        
        if(!rst_n)
        begin
            
            state <= IDLE;
            
            ram_write <= 1'b0;
            ram_byte <= 1'b0;
            ram_addr <= 23'd0;
            ram_wdata <= 32'd0;
            
            cpu_rdata <= 32'd0;
            video_rdata <= 32'd0;
            
        end
        else
        begin
            
            case(state)
                
                IDLE:
                begin
                    
                    if(ram_init_done)
                    begin
                        
                        if(video_req)
                        begin
                            
                            ram_write <= 1'b0;
                            ram_byte <= 1'b0;
                            ram_addr <= video_addr;
                            ram_wdata <= 32'd0;
                            
                            state <= VIDEO_ACCESS;
                            
                        end
                        else if(cpu_req)
                        begin
                            
                            ram_write <= cpu_write;
                            ram_byte <= cpu_byte;
                            ram_addr <= cpu_addr;
                            ram_wdata <= cpu_wdata;
                            
                            state <= CPU_ACCESS;
                            
                        end
                        
                    end
                    
                end
                
                CPU_ACCESS:
                begin
                    
                    if(ram_ready)
                    begin
                        
                        cpu_rdata <= ram_rdata;
                        state <= CPU_RESPONSE;
                        
                    end
                        
                end
                
                VIDEO_ACCESS:
                begin
                    
                    if(ram_ready)
                    begin
                        
                        video_rdata <= ram_rdata;
                        state <= VIDEO_RESPONSE;
                        
                    end
                    
                end
                
                CPU_RESPONSE:
                begin
                    
                    if(!cpu_req)
                        state <= IDLE;
                    
                end
                
                VIDEO_RESPONSE:
                begin
                    
                    if(!video_req)
                    begin
                        
                        state <= IDLE;
                        
                    end
                    
                end
                
                default:
                begin
                    
                    state<= IDLE;
                    
                    ram_write <= 1'b0;
                    ram_byte  <= 1'b0;
                    ram_addr  <= 23'd0;
                    ram_wdata <= 32'd0;
                    
                end
                
            endcase
            
        end
        
    end
    
endmodule
