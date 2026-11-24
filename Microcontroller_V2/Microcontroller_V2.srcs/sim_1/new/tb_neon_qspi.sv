`timescale 1ns / 1ps
`include "software/neon_breaker/test_constants.vh"

module tb_neon_qspi;
    logic [31:0] rom [0:131071];
    logic [31:0] checkpoint_regs [0:15];

    logic clk;
    logic rst_n;
    logic ena;

    logic [7:0] ui_in;
    logic [7:0] uo_out;
    logic [7:0] uio_in;
    logic [7:0] uio_out;
    logic [7:0] uio_oe;

    logic [3:0] flash_input;
    logic [3:0] ram_input;
    logic ram_model_initialized;

    logic [7:0] flash_command;
    logic [23:0] flash_address;
    logic [7:0] status_shift;
    logic [31:0] program_word;
    logic [31:0] transmit_shift;

    integer flash_init_step;
    integer flash_reads;

    integer expected_x;
    integer expected_y;
    integer visible_pixels;
    integer colored_pixels;

    logic expected_hsync;
    logic expected_vsync;
    logic [5:0] expected_rgb;
    wire sck = uo_out[4];
    wire flash_cs = uo_out[5];
    wire ram_cs = uo_out[6];
    wire [3:0] sd_out = uio_out[3:0];
    wire [3:0] sd_oe = uio_oe[3:0];
    wire [2:0] rgb = uo_out[2:0];
    integer concurrent_cycles=0, visible_cycles=0, nonblack_cycles=0;
    always @(negedge clk) if (rst_n && ena) begin
        if(!flash_cs && !ram_cs) concurrent_cycles=concurrent_cycles+1;
        if(dut.video_on && dut.pixel_valid) begin
            visible_cycles=visible_cycles+1;
            if(rgb!=0) nonblack_cycles=nonblack_cycles+1;
            if(rgb !== {dut.pixel_data[0],dut.pixel_data[1],dut.pixel_data[2]})
                $fatal(1,"RGB111 pin mapping mismatch");
        end
        if(!dut.video_on && rgb!==0) $fatal(1,"Nonblack blanking");
    end
    assign uio_in = {ram_input,flash_input};

    top #(.GAMEPAD_PMOD(1)) dut(
        .ui_in(ui_in),
        .uo_out(uo_out),

        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),

        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    ram_model_simple #(.MEMORY_BYTES(262144)) memory_model(
        .sck(sck),
        .cs_n(ram_cs),
        .sd_out(uio_out[7:4]),
        .sd_oe(uio_oe[7:4]),
        .sd_in(ram_input),
        .initialized(ram_model_initialized)
    );

    always #19.841 clk = ~clk;

    // Model Flash simplificat.
    // QE este deja activ: controllerul trebuie sa detecteze asta.
    initial begin
        flash_input = 4'd0;
        flash_command = 8'd0;
        flash_address = 24'd0;
        status_shift = 8'd0;
        program_word = 32'd0;
        transmit_shift = 32'd0;

        flash_init_step = 0;
        flash_reads = 0;

        forever begin
            @(negedge flash_cs);

            flash_command = 8'd0;

            repeat (8) begin
                @(posedge sck);
                #1;

                if (flash_cs !== 1'b0 ||
                    sd_oe !== 4'b1101)
                    $fatal(1, "Flash: directie incorecta la comanda");

                flash_command = {
                    flash_command[6:0], sd_out[0]
                };
            end

            if (flash_init_step < 4) begin
                case (flash_init_step)
                    0:
                        if (flash_command !== 8'hAB)
                            $fatal(1, "Flash: asteptam AB");

                    1:
                        if (flash_command !== 8'h66)
                            $fatal(1, "Flash: asteptam 66");

                    2:
                        if (flash_command !== 8'h99)
                            $fatal(1, "Flash: asteptam 99");

                    3:
                        if (flash_command !== 8'h35)
                            $fatal(1, "Flash: asteptam 35");
                endcase

                if (flash_command == 8'h35) begin
                    // Status Register 2: QE = 1.
                    status_shift = 8'h02;

                    repeat (8) begin
                        @(negedge sck);
                        #1;

                        if (flash_cs !== 1'b0 ||
                            sd_oe[1] !== 1'b0)
                            $fatal(1, "Flash: IO1 nu este intrare");

                        flash_input = {
                            2'b00, status_shift[7], 1'b0
                        };

                        @(posedge sck);
                        #1;

                        status_shift = {
                            status_shift[6:0], 1'b0
                        };
                    end
                end

                @(negedge sck);
                #1;

                if (flash_cs !== 1'b1 ||
                    sd_oe !== 4'b0000)
                    $fatal(1, "Flash: final incorect de comanda");

                flash_input = 4'd0;
                flash_init_step = flash_init_step + 1;
            end
            else begin
                if (flash_command !== 8'h6B)
                    $fatal(1, "Flash: asteptam citire 6B");

                flash_address = 24'd0;

                repeat (24) begin
                    @(posedge sck);
                    #1;

                    if (flash_cs !== 1'b0 ||
                        sd_oe !== 4'b1101)
                        $fatal(1, "Flash: adresa seriala incorecta");

                    flash_address = {
                        flash_address[22:0], sd_out[0]
                    };
                end

                // Fiecare instructiune ocupa patru octeti.
                // Format:
                // opcode[3:0], rdest[4:0], immediate[16:0]
                // sau opcode, rdest, rleft, rright, 7 biti zero.
                if (flash_address[23:2] >= `NEON_WORDS) $fatal(1,"PC outside game");
                program_word = rom[flash_address[23:2]];

                // Primul octet transmis este cel mai putin
                // semnificativ din instructiune.
                transmit_shift = {
                    program_word[7:0],
                    program_word[15:8],
                    program_word[23:16],
                    program_word[31:24]
                };

                repeat (8) begin
                    @(posedge sck);
                    #1;

                    if (flash_cs !== 1'b0 ||
                        sd_oe !== 4'b0000)
                        $fatal(1, "Flash: cicluri dummy incorecte");
                end

                repeat (8) begin
                    @(negedge sck);
                    #1;

                    if (flash_cs !== 1'b0 ||
                        sd_oe !== 4'b0000)
                        $fatal(1, "Flash: directie incorecta la citire");

                    flash_input = transmit_shift[31:28];

                    @(posedge sck);
                    #1;

                    transmit_shift = {
                        transmit_shift[27:0], 4'd0
                    };
                end

                @(negedge sck);
                #1;

                if (flash_cs !== 1'b1 ||
                    sd_oe !== 4'b0000)
                    $fatal(1, "Flash: final incorect de citire");

                flash_input = 4'd0;
                flash_reads = flash_reads + 1;
            end
        end
    end


    function [31:0] word_at(input integer a);
        word_at={memory_model.memory[a*4+3],memory_model.memory[a*4+2],memory_model.memory[a*4+1],memory_model.memory[a*4]};
    endfunction
    logic [11:0] pad=0;
    initial begin
        #10000;
        forever begin
            for(integer bitnum=11;bitnum>=0;bitnum=bitnum-1) begin
                ui_in[6]=pad[bitnum]; #2000; ui_in[5]=1; #2000; ui_in[5]=0;
            end
            #2000;ui_in[4]=1;#2000;ui_in[4]=0;
            #1000000;
        end
    end
    integer frames=0;
    realtime previous_time=0;
    realtime dt;
    always @(posedge clk) if (rst_n && dut.instr_ready && dut.instr_addr==`NEON_FRAME_PC) begin
        if(previous_time!=0)begin
            dt=($realtime-previous_time)/1000000.0;
            $display("UPDATE %0d duration_ms=%0.3f x=%0d y=%0d score=%0d",frames,dt,word_at(`NEON_X),word_at(`NEON_Y),dut.score);
        end
        $fflush();
        previous_time=$realtime;
        frames=frames+1;
    end
    initial begin
        clk=0;rst_n=0;ena=1;ui_in=0;
        $readmemh("software/neon_breaker/neon_breaker.hex",rom,0,`NEON_WORDS-1);
        $readmemh("software/neon_breaker/checkpoint_regs.hex",checkpoint_regs);
        #200;rst_n=1;
        // Checkpoint skips only already-tested initialization; all subsequent
        // CPU, QSPI Flash, PSRAM, arbitration, video and controller paths are real RTL.
        force dut.u_cpu.state=3;
        wait(dut.ram_init_done && dut.flash_init_done);
        @(negedge clk);
        $readmemh("software/neon_breaker/checkpoint_ram.hex",memory_model.memory);
        for(integer i=0;i<16;i=i+1)dut.u_cpu.regs[i]=checkpoint_regs[i];
        dut.u_cpu.pc=`NEON_WAIT_PC;
        release dut.u_cpu.state;
        dut.u_cpu.state=0;
        wait(frames==3);pad=12'h020;
        wait(frames==6);pad=0;
        wait(frames==8);
        if(dut.score==0)$fatal(1,"No brick collision / score");
        if(word_at(`NEON_PX)>=68)$fatal(1,"Serial controller did not move paddle");
        if(dut.u_cpu.state==3)$fatal(1,"CPU stopped");
        if(concurrent_cycles==0 || visible_cycles==0 || nonblack_cycles==0) $fatal(1,"No QSPI concurrency or visible graphics");
        $display("CONCURRENT QSPI clocks=%0d visible=%0d nonblack=%0d", concurrent_cycles,visible_cycles,nonblack_cycles);
        $display("PASS tb_neon_qspi: real game, Flash/PSRAM separate buses RGB111, collision, score, serial controller, VGA active");
        $finish;
    end
    initial begin #1000000000; $fatal(1,"Game integration timeout"); end
endmodule
