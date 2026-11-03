module cpu_core(

    input logic clk,
    input logic rst_n,
    
    output logic instr_req,
    output logic[16:0] instr_addr,
    input logic[25:0] instr_rdata,
    input logic instr_ready,
    
    output logic data_req,
    output logic data_write,
    output logic[16:0] data_addr,
    output logic[31:0] data_wdata,
    input logic[31:0] data_rdata,
    input logic data_ready 

    );
    
    
    localparam FETCH = 2'b00;
    localparam EXECUTE = 2'b01;
    localparam MEMORY = 2'b10;
    localparam STOPPED = 2'b11;
    
    localparam OP_ADD = 4'b0000;
    localparam OP_SUB = 4'b0001;
    localparam OP_AND = 4'b0010;
    localparam OP_OR = 4'b0011;
    localparam OP_XOR = 4'b0100;
    localparam OP_MUL = 4'b0101;
    localparam OP_LOADC = 4'b0110;
    localparam OP_LOAD = 4'b0111;
    localparam OP_STORE = 4'b1000; 
    localparam OP_JUMP = 4'b1001;
    localparam OP_JZ = 4'b1010;
    localparam OP_NOP = 4'b1111;
    
    logic[1:0] state;
    logic[16:0] pc;
    logic[25:0] instruction;
    logic[31:0] regs[0:31];
    logic[3:0] opcode;
    logic[4:0] rdest;
    logic[4:0] rleft;
    logic[4:0] rright;
    logic[16:0] immediate;
    
    assign instr_req = rst_n && (state == FETCH);
    assign instr_addr = pc;
    
    assign opcode = instruction[25:22];
    assign rdest = instruction[21:17];
    assign rleft = instruction[16:12];
    assign rright = instruction[11:7];
    assign immediate = instruction[16:0];
    
    assign data_req = rst_n && (state == MEMORY);
    
    
    always_ff @(posedge clk)
    begin
        
        if(!rst_n)
        begin
        
            state <= FETCH;
            pc <= 17'd0;
           instruction <= 26'd0;
           data_write <= 1'b0;
           data_addr <= 17'd0;
           data_wdata <= 32'd0;
        
        end
        
        else
        begin
        
            case(state)
            
                FETCH:
                begin
                
                    if(instr_ready)
                    begin
                    
                        instruction <= instr_rdata;
                        state <= EXECUTE;
                    
                    end
                
                end    
                
                EXECUTE:
                begin
                    
                    case(opcode)
                        
                        OP_ADD:
                        begin
                            
                            regs[rdest] <= regs[rleft] + regs[rright];
                            pc <= pc + 17'd1;
                            state <= FETCH;
                            
                        end
                        
                        OP_SUB:
                        begin
                        
                            regs[rdest] <= regs[rleft] - regs[rright];
                            pc <= pc + 17'd1;
                            state <= FETCH;
                        
                        end
                        
                        OP_AND:
                        begin
                            
                            regs[rdest] <= regs[rleft] & regs[rright];
                            pc <= pc + 17'd1;
                            state <= FETCH;
                            
                        end
                        
                        OP_OR:
                        begin
                            
                            regs[rdest] <= regs[rleft] | regs[rright];
                            pc <= pc + 17'd1;
                            state <= FETCH;
                            
                        end
                        
                        OP_XOR:
                        begin
                            
                            regs[rdest] <= regs[rleft] ^ regs[rright];
                            pc <= pc + 17'd1;
                            state <= FETCH;
                            
                        end
                        
                        OP_MUL:
                        begin
                        
                            regs[rdest] <= regs[rleft] * regs[rright];
                            pc <= pc + 17'd1;
                            state <= FETCH;
                            
                        end
                        
                        OP_LOADC:
                        begin
                            
                            regs[rdest] <= {15'b0, immediate};
                            pc <= pc + 17'd1;
                            state <= FETCH;
                            
                        end
                        
                        OP_LOAD:
                        begin
                            
                            data_addr <= regs[rleft][16:0];
                            data_write <= 1'b0;
                            data_wdata <= 32'd0;
                            state <= MEMORY;
                            
                        end
                        
                        OP_STORE:
                        begin
                            
                            data_addr <= regs[rleft][16:0];
                            data_write <= 1'b1;
                            data_wdata <= regs[rdest];
                            state <= MEMORY;
                            
                        end
                        
                        OP_JUMP:
                        begin
                            
                            pc <= immediate;
                            state <= FETCH;
                            
                        end
                        
                        OP_JZ:
                        begin
                            
                            if(regs[rdest] == 32'd0)
                            begin
                                
                                pc <= immediate;
                                
                            end
                            else
                            begin
                                
                                pc <= pc + 17'd1;
                                
                            end
                            
                            state <= FETCH;
                            
                        end
                        
                        OP_NOP:
                        begin
                            
                            pc <= pc + 17'd1;
                            state <= FETCH;
                            
                        end
                        
                        default:
                        begin
                            
                            state <= STOPPED;
                            
                        end
                   
                    endcase
                    
                end
                
                MEMORY:
                begin
                    
                    if(data_ready)
                    begin
                        
                        if(opcode == OP_LOAD)
                        begin
                            
                            regs[rdest] <= data_rdata; 
                            
                        end
                        
                        pc <= pc + 17'd1;
                        state <= FETCH;
                        data_write <= 1'b0;
                        
                    end
                    
                end
                
                STOPPED:
                begin
                                        
                end
                
                default:
                begin
                    
                    state <= STOPPED;
                    
                end
            
            endcase
        
        end
        
    end
    
    
endmodule
