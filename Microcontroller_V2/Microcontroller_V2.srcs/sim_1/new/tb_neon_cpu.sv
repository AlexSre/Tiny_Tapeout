`timescale 1ns/1ps
`include "software/neon_breaker/test_constants.vh"
// Cold boot of the actual cpu_core using the game binary. This isolates ISA
// correctness from QSPI, tested separately by tb_neon_qspi.
module tb_neon_cpu;
    logic clk=0,rst_n=0;
    wire instr_req,data_req,data_write;
    wire [16:0] instr_addr,data_addr;
    wire [31:0] data_wdata;
    logic [31:0] rom[0:`NEON_WORDS-1];
    logic [31:0] ram[0:131071],expected[0:131071];
    wire [31:0] data_rdata = data_addr==17'h1ffff ? 32'd128 :
                             data_addr==17'h1fffe ? 32'd1 : ram[data_addr];
    cpu_core dut(.clk(clk),.rst_n(rst_n),.instr_req(instr_req),.instr_addr(instr_addr),
        .instr_rdata(rom[instr_addr][25:0]),.instr_ready(instr_req),
        .data_req(data_req),.data_write(data_write),.data_addr(data_addr),
        .data_wdata(data_wdata),.data_rdata(data_rdata),.data_ready(data_req));
    always #5 clk=~clk;
    integer retired=0;
    always @(posedge clk) if(rst_n)begin
        if(instr_req)begin
            if(instr_addr>=`NEON_WORDS)$fatal(1,"PC out of image");
            retired=retired+1;
        end
        if(data_req && data_write)begin
            if(data_addr<19200)ram[data_addr]<={29'd0,data_wdata[2:0]};
            else ram[data_addr]<=data_wdata;
        end
        if(dut.state==3)$fatal(1,"Invalid instruction/register stopped CPU");
    end
    initial begin
        $readmemh("software/neon_breaker/neon_breaker.hex",rom);
        $readmemh("software/neon_breaker/init_expected.hex",expected);
        #50;rst_n=1;
        wait(instr_req && instr_addr==`NEON_WAIT_PC);
        @(negedge clk);
        for(integer i=0;i<131072;i=i+1)
            if(expected[i]!=32'hdeadbeef && ram[i]!==expected[i])
                $fatal(1,"RAM mismatch %h actual %h expected %h",i,ram[i],expected[i]);
        $display("PASS tb_neon_cpu: cold boot %0d instructions; framebuffer, backing image, game state match",retired);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Boot timeout");end
endmodule
