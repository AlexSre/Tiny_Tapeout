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
    
    
    localparam FETCH = 3'd0;
    localparam EXECUTE = 3'd1;
    localparam MEMORY = 3'd2;
    localparam STOPPED = 3'd3;
    localparam READ_REGS = 3'd4;
    localparam WRITEBACK = 3'd5;
    localparam MUL_FINISH = 3'd6;
    
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
    
    logic[2:0] state;
    logic[16:0] pc;
    logic[25:0] instruction;
    logic[31:0] regs[0:15];
    logic[3:0] opcode;
    logic[3:0] rdest;
    logic[3:0] rleft;
    logic[3:0] rright;
    logic[16:0] immediate;
    logic invalid_register;
    logic [31:0] operand_left;
    logic [31:0] operand_right;
    logic [31:0] operand_dest;
    logic [31:0] result;
    logic [31:0] mul_low;
    logic [15:0] mul_cross_a;
    logic [15:0] mul_cross_b;
    logic [15:0] mul_cross_sum;

    // Only the low 32 bits of a product are part of the ISA.
    assign mul_cross_sum = mul_cross_a + mul_cross_b;
    
    assign instr_req = rst_n && (state == FETCH);
    assign instr_addr = pc;
    
    assign opcode = instruction[25:22];
    assign rdest  = instruction[20:17];
    assign rleft  = instruction[15:12];
    assign rright = instruction[10:7];
    assign immediate = instruction[16:0];
    
    assign data_req = rst_n && (state == MEMORY);
    
    always_comb
begin
    invalid_register = 1'b0;

    case (opcode)

        OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_MUL:
        begin
            invalid_register =
                instruction[21] |
                instruction[16] |
                instruction[11];
        end

        OP_LOAD, OP_STORE:
        begin
            invalid_register =
                instruction[21] |
                instruction[16];
        end

        OP_LOADC, OP_JZ:
        begin
            invalid_register = instruction[21];
        end

        default:
        begin
            invalid_register = 1'b0;
        end

    endcase
end
    
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
                        state <= READ_REGS;
                    
                    end
                
                end    
                
                READ_REGS:
                begin
                    if (invalid_register)
                        state <= STOPPED;
                    else
                    begin
                        operand_left <= regs[rleft];
                        operand_right <= regs[rright];
                        operand_dest <= regs[rdest];
                        state <= EXECUTE;
                    end
                end

                MUL_FINISH:
                begin
                    result <= mul_low + {mul_cross_sum, 16'd0};
                    state <= WRITEBACK;
                end

                WRITEBACK:
                begin
                    regs[rdest] <= result;
                    pc <= pc + 17'd1;
                    state <= FETCH;
                end

                EXECUTE:
                begin
                    
                    if (invalid_register)
                    begin
                        state <= STOPPED;
                    end
                    else
                    begin
                        case(opcode)
                            
                            OP_ADD:
                            begin
                                result <= operand_left + operand_right;
                                state <= WRITEBACK;
                                
                            end
                            
                            OP_SUB:
                            begin
                                result <= operand_left - operand_right;
                                state <= WRITEBACK;
                            
                            end
                            
                            OP_AND:
                            begin
                                result <= operand_left & operand_right;
                                state <= WRITEBACK;
                                
                            end
                            
                            OP_OR:
                            begin
                                result <= operand_left | operand_right;
                                state <= WRITEBACK;
                                
                            end
                            
                            OP_XOR:
                            begin
                                result <= operand_left ^ operand_right;
                                state <= WRITEBACK;
                                
                            end
                            
                            OP_MUL:
                            begin
                                mul_low <= operand_left[15:0] * operand_right[15:0];
                                mul_cross_a <= operand_left[31:16] * operand_right[15:0];
                                mul_cross_b <= operand_left[15:0] * operand_right[31:16];
                                state <= MUL_FINISH;
                                
                            end
                            
                            OP_LOADC:
                            begin
                                result <= {15'b0, immediate};
                                state <= WRITEBACK;
                                
                            end
                            
                            OP_LOAD:
                            begin
                                
                                data_addr <= operand_left[16:0];
                                data_write <= 1'b0;
                                data_wdata <= 32'd0;
                                state <= MEMORY;
                                
                            end
                            
                            OP_STORE:
                            begin
                                
                                data_addr <= operand_left[16:0];
                                data_write <= 1'b1;
                                data_wdata <= operand_dest;
                                state <= MEMORY;
                                
                            end
                            
                            OP_JUMP:
                            begin
                                
                                pc <= immediate;
                                state <= FETCH;
                                
                            end
                            
                            OP_JZ:
                            begin
                                
                                if(operand_dest == 32'd0)
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
                end
                
                MEMORY:
                begin
                    if (data_ready)
                    begin
                        data_write <= 1'b0;
                        if (opcode == OP_LOAD)
                        begin
                            result <= data_rdata;
                            state <= WRITEBACK;
                        end
                        else
                        begin
                            pc <= pc + 17'd1;
                            state <= FETCH;
                        end
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
