module memory_map(

    input logic clk,
    input logic rst_n,

    input logic data_req,
    input logic data_write,
    input logic [16:0] data_addr,
    input logic [31:0] data_wdata,

    output logic [31:0] data_rdata,
    output logic data_ready,

    input logic [7:0] buttons,
    input logic vsync,
    input logic [31:0] random_value,

    output logic [31:0] score,

    output logic cpu_req,
    output logic cpu_write,
    output logic cpu_byte,
    output logic [22:0] cpu_addr,
    output logic [31:0] cpu_wdata,

    input logic [31:0] cpu_rdata,
    input logic cpu_ready

);

    localparam IDLE       = 2'd0;
    localparam RAM_ACCESS = 2'd1;
    localparam RESPONSE   = 2'd2;

    localparam FRAMEBUFFER_SIZE = 17'd19200;

    localparam RANDOM_ADDR  = 17'h1FFFC;
    localparam SCORE_ADDR   = 17'h1FFFD;
    localparam VSYNC_ADDR   = 17'h1FFFE;
    localparam BUTTONS_ADDR = 17'h1FFFF;

    logic [1:0] state;

    logic write_saved;
    logic pixel_saved;

    assign cpu_req =
        rst_n && (state == RAM_ACCESS);

    assign data_ready =
        rst_n && (state == RESPONSE) && data_req;

    always_ff @(posedge clk)
    begin
        if (!rst_n)
        begin
            state <= IDLE;

            data_rdata <= 32'd0;
            score <= 32'd0;

            cpu_write <= 1'b0;
            cpu_byte  <= 1'b0;
            cpu_addr  <= 23'd0;
            cpu_wdata <= 32'd0;

            write_saved <= 1'b0;
            pixel_saved <= 1'b0;
        end
        else
        begin
            case (state)

                IDLE:
                begin
                    if (data_req)
                    begin
                        data_rdata <= 32'd0;

                        case (data_addr)

                            RANDOM_ADDR:
                            begin
                                if (!data_write)
                                    data_rdata <= random_value;

                                state <= RESPONSE;
                            end

                            SCORE_ADDR:
                            begin
                                if (data_write)
                                    score <= data_wdata;
                                else
                                    data_rdata <= score;

                                state <= RESPONSE;
                            end

                            VSYNC_ADDR:
                            begin
                                if (!data_write)
                                    data_rdata <= {31'd0, vsync};

                                state <= RESPONSE;
                            end

                            BUTTONS_ADDR:
                            begin
                                if (!data_write)
                                    data_rdata <= {24'd0, buttons};

                                state <= RESPONSE;
                            end

                            default:
                            begin
                                cpu_write <= data_write;
                                write_saved <= data_write;

                                if (data_addr < FRAMEBUFFER_SIZE)
                                begin
                                    cpu_byte <= 1'b1;
                                    pixel_saved <= 1'b1;

                                    cpu_addr <= {
                                        6'd0, data_addr
                                    };

                                    cpu_wdata <= {
                                        29'd0, data_wdata[2:0]
                                    };
                                end
                                else
                                begin
                                    cpu_byte <= 1'b0;
                                    pixel_saved <= 1'b0;

                                    cpu_addr <= {
                                        4'd0, data_addr, 2'b00
                                    };

                                    cpu_wdata <= data_wdata;
                                end

                                state <= RAM_ACCESS;
                            end

                        endcase
                    end
                end

                RAM_ACCESS:
                begin
                    if (cpu_ready)
                    begin
                        if (!write_saved)
                        begin
                            if (pixel_saved)
                            begin
                                data_rdata <= {
                                    29'd0, cpu_rdata[2:0]
                                };
                            end
                            else
                            begin
                                data_rdata <= cpu_rdata;
                            end
                        end

                        state <= RESPONSE;
                    end
                end

                RESPONSE:
                begin
                    if (!data_req)
                        state <= IDLE;
                end

                default:
                begin
                    state <= IDLE;

                    data_rdata <= 32'd0;

                    cpu_write <= 1'b0;
                    cpu_byte  <= 1'b0;
                    cpu_addr  <= 23'd0;
                    cpu_wdata <= 32'd0;
                end

            endcase
        end
    end

endmodule