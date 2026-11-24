module qspi_clock(

    input logic clk,
    input logic rst_n,
    input logic enable,
    
    output logic sck,
    output logic rise_en,
    output logic fall_en    

);

always_ff @(posedge clk)
begin
    
    if(!rst_n)
        sck <= 1'b0;
    else if(!enable)
        sck <= 1'b0;
    else
        sck <= ~sck;
    
end

assign rise_en = rst_n && enable && !sck;
assign fall_en = rst_n && enable && sck;

endmodule
