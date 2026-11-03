module input_sync(

    input logic clk,
    input logic rst_n,

    input logic [7:0] buttons_in,
    output logic [7:0] buttons_sync

);

    (* ASYNC_REG = "TRUE" *) logic [7:0] sync_stage1;
    (* ASYNC_REG = "TRUE" *) logic [7:0] sync_stage2;

    assign buttons_sync = sync_stage2;

    always_ff @(posedge clk)
    begin
        if (!rst_n)
        begin
            sync_stage1 <= 8'd0;
            sync_stage2 <= 8'd0;
        end
        else
        begin
            sync_stage1 <= buttons_in;
            sync_stage2 <= sync_stage1;
        end
    end

endmodule