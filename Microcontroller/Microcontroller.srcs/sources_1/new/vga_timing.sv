module vga_timing(

    input logic clk,
    input logic rst_n,
    
    output logic hsync,
    output logic vsync,
    output logic video_on,
    output logic[9:0] x,
    output logic[9:0] y    

    );
    
    localparam H_ACTIVE = 640;
    localparam H_FRONT = 16;
    localparam H_SYNC = 96;
    localparam H_BACK = 48;
    localparam H_TOTAL = H_ACTIVE +H_FRONT + H_SYNC + H_BACK;
    
    localparam V_ACTIVE = 480;
    localparam V_FRONT = 10;
    localparam V_SYNC = 2;
    localparam V_BACK = 33;
    localparam V_TOTAL = V_ACTIVE +V_FRONT + V_SYNC + V_BACK;
    
    logic [9:0] h_count;
    logic [9:0] v_count;
    
    
    always_ff @(posedge clk)
    begin
        if (!rst_n)
        begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end
        else
        begin
            if (h_count == H_TOTAL - 1)
            begin
                h_count <= 10'd0;

                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end
            else
            begin
                h_count <= h_count + 10'd1;
            end
        end
    end
    
    assign x = h_count;
    assign y = v_count;
    
    assign video_on = rst_n && (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    
    assign hsync = !(rst_n && (h_count >= H_ACTIVE + H_FRONT) && (h_count < H_ACTIVE + H_FRONT + H_SYNC ));
    assign vsync = !(rst_n && (v_count >= V_ACTIVE + V_FRONT) && (v_count < V_ACTIVE + V_FRONT + V_SYNC ));
    
endmodule
