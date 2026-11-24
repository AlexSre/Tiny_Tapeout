`timescale 1ns/1ps
module tb_gamepad_input;
    logic clk=0, rst_n=0, latch=0, serial_clk=0, serial_data=0;
    logic [7:0] buttons;
    always #5 clk=~clk;
    gamepad_input #(.TIMEOUT_CYCLES(1000)) dut(
        .clk(clk),.rst_n(rst_n),.pmod_latch(latch),
        .pmod_clk(serial_clk),.pmod_data(serial_data),.buttons(buttons));
    task bit_out(input logic b);
        serial_data=b; #67; serial_clk=1; #73; serial_clk=0; #61;
    endtask
    task frame(input logic [23:0] data, input integer n);
        for(integer i=n-1;i>=0;i=i-1) bit_out(data[i]);
        #31; latch=1; #77; latch=0; #100;
    endtask
    initial begin
        #50; rst_n=1;
        frame(24'h000000,12); if(buttons!==8'h80)$fatal(1,"Idle controller");
        frame(24'h000020,12); if(buttons!==8'h81)$fatal(1,"LEFT mapping");
        frame(24'h000010,12); if(buttons!==8'h82)$fatal(1,"RIGHT mapping");
        frame(24'h000008,12); if(buttons!==8'h90)$fatal(1,"A mapping");
        frame(24'h000800,12); if(buttons!==8'h90)$fatal(1,"B mapping");
        frame(24'h000100,12); if(buttons!==8'ha0)$fatal(1,"START mapping");
        frame(24'h000200,12); if(buttons!==8'hc0)$fatal(1,"SELECT mapping");
        frame(24'h0000c0,12); if(buttons!==8'h8c)$fatal(1,"UP/DOWN mapping");
        frame(24'h020010,24); if(buttons!==8'h82)$fatal(1,"First controller is last 12 bits");
        frame(24'h000fff,12); if(buttons!==8'h00)$fatal(1,"Disconnected controller");
        frame(24'h000020,12);
        frame(24'h000000,5); if(buttons!==8'h81)$fatal(1,"Partial frame published");
        #11000; if(buttons!==8'h00)$fatal(1,"Unplug timeout");
        frame(24'h000008,12); if(buttons!==8'h90)$fatal(1,"Recovery after unplug");
        rst_n=0; #50; if(buttons!==0)$fatal(1,"Reset");
        $display("PASS gamepad_input: serial CDC, 12/24 bits, mapping, partial frame, timeout, reset");
        $finish;
    end
endmodule
