`timescale 1ns / 1ps

module tb_ram_arbiter_simple;

    logic clk;
    logic rst_n;
    logic ram_init_done;

    // Cereri CPU.
    logic cpu_req;
    logic cpu_write;
    logic cpu_byte;
    logic [22:0] cpu_addr;
    logic [31:0] cpu_wdata;

    logic [31:0] cpu_rdata;
    logic cpu_ready;

    // Cereri video.
    logic video_req;
    logic [22:0] video_addr;

    logic [31:0] video_rdata;
    logic video_ready;

    // Interfata catre controllerul RAM.
    logic ram_req;
    logic ram_write;
    logic ram_byte;
    logic [22:0] ram_addr;
    logic [31:0] ram_wdata;

    logic [31:0] ram_rdata;
    logic ram_ready;

    ram_arbiter uut(
        .clk(clk),
        .rst_n(rst_n),

        .ram_init_done(ram_init_done),

        .cpu_req(cpu_req),
        .cpu_write(cpu_write),
        .cpu_byte(cpu_byte),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),

        .video_req(video_req),
        .video_addr(video_addr),
        .video_rdata(video_rdata),
        .video_ready(video_ready),

        .ram_req(ram_req),
        .ram_write(ram_write),
        .ram_byte(ram_byte),
        .ram_addr(ram_addr),
        .ram_wdata(ram_wdata),
        .ram_rdata(ram_rdata),
        .ram_ready(ram_ready)
    );

    always #19.841 clk = ~clk;

    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;
        ram_init_done = 1'b0;

        cpu_req = 1'b0;
        cpu_write = 1'b0;
        cpu_byte = 1'b0;
        cpu_addr = 23'd0;
        cpu_wdata = 32'd0;

        video_req = 1'b0;
        video_addr = 23'd0;

        ram_rdata = 32'd0;
        ram_ready = 1'b0;

        $display("--- Start test ram_arbiter ---");

        repeat (3) @(negedge clk);

        if (ram_req !== 1'b0 ||
            cpu_ready !== 1'b0 ||
            video_ready !== 1'b0)
            $fatal(1, "[ERR] Reset incorect");

        rst_n = 1'b1;

        $display("[OK] Reset");

        // TEST 1: Cererile asteapta initializarea RAM.
        // CPU cere o scriere de un octet.
        // Video cere o citire de patru octeti.
        @(negedge clk);

        cpu_req = 1'b1;
        cpu_write = 1'b1;
        cpu_byte = 1'b1;
        cpu_addr = 23'd100;
        cpu_wdata = 32'd5;

        video_req = 1'b1;
        video_addr = 23'd200;

        repeat (3)
        begin
            @(negedge clk);

            if (ram_req !== 1'b0 ||
                cpu_ready !== 1'b0 ||
                video_ready !== 1'b0)
                $fatal(1, "[ERR] Acces inainte de initializarea RAM");
        end

        $display("[OK] Cererile asteapta initializarea RAM");

        // TEST 2: La cereri simultane, video are prioritate.
        ram_init_done = 1'b1;

        wait (ram_req == 1'b1);
        @(negedge clk);

        if (ram_addr !== 23'd200 ||
            ram_write !== 1'b0 ||
            ram_byte !== 1'b0 ||
            ram_wdata !== 32'd0)
            $fatal(1, "[ERR] Video nu a primit prioritate");

        // Intarziem raspunsul RAM.
        repeat (3)
        begin
            @(negedge clk);

            if (ram_req !== 1'b1 ||
                ram_addr !== 23'd200 ||
                cpu_ready !== 1'b0 ||
                video_ready !== 1'b0)
                $fatal(1, "[ERR] Tranzactie video instabila");
        end

        ram_rdata = 32'h12345678;
        ram_ready = 1'b1;

        @(negedge clk);
        ram_ready = 1'b0;

        if (video_ready !== 1'b1 ||
            video_rdata !== 32'h12345678 ||
            cpu_ready !== 1'b0 ||
            ram_req !== 1'b0)
            $fatal(1, "[ERR] Raspuns video incorect");

        // Raspunsul trebuie pastrat cat timp video_req este 1.
        repeat (2)
        begin
            @(negedge clk);

            if (video_ready !== 1'b1 ||
                video_rdata !== 32'h12345678 ||
                cpu_ready !== 1'b0 ||
                ram_req !== 1'b0)
                $fatal(1, "[ERR] Raspunsul video nu este pastrat");
        end

        $display("[OK] Prioritate video si pastrarea raspunsului");

        // TEST 3: Dupa video, este servita cererea CPU in asteptare.
        video_req = 1'b0;

        wait (ram_req == 1'b1);
        @(negedge clk);

        if (ram_addr !== 23'd100 ||
            ram_write !== 1'b1 ||
            ram_byte !== 1'b1 ||
            ram_wdata !== 32'd5)
            $fatal(1, "[ERR] Cererea CPU nu a fost preluata corect");

        $display("[OK] Cererea CPU aflata in asteptare este preluata");

        // TEST 4: O cerere video noua nu intrerupe accesul CPU.
        video_req = 1'b1;
        video_addr = 23'd400;

        repeat (3)
        begin
            @(negedge clk);

            if (ram_req !== 1'b1 ||
                ram_addr !== 23'd100 ||
                ram_write !== 1'b1 ||
                ram_byte !== 1'b1 ||
                ram_wdata !== 32'd5 ||
                cpu_ready !== 1'b0 ||
                video_ready !== 1'b0)
                $fatal(1, "[ERR] Tranzactia CPU a fost intrerupta");
        end

        // Confirmam scrierea CPU.
        ram_rdata = 32'd0;
        ram_ready = 1'b1;

        @(negedge clk);
        ram_ready = 1'b0;

        if (cpu_ready !== 1'b1 ||
            video_ready !== 1'b0 ||
            ram_req !== 1'b0)
            $fatal(1, "[ERR] Confirmare CPU incorecta");

        repeat (2)
        begin
            @(negedge clk);

            if (cpu_ready !== 1'b1 ||
                video_ready !== 1'b0 ||
                ram_req !== 1'b0)
                $fatal(1, "[ERR] Confirmarea CPU nu este pastrata");
        end

        $display("[OK] Accesul CPU nu este intrerupt de video");

        // TEST 5: Cererea video noua este servita dupa CPU.
        cpu_req = 1'b0;

        wait (ram_req == 1'b1);
        @(negedge clk);

        if (ram_addr !== 23'd400 ||
            ram_write !== 1'b0 ||
            ram_byte !== 1'b0)
            $fatal(1, "[ERR] Cererea video in asteptare nu este servita");

        ram_rdata = 32'hAABBCCDD;
        ram_ready = 1'b1;

        @(negedge clk);
        ram_ready = 1'b0;

        if (video_ready !== 1'b1 ||
            video_rdata !== 32'hAABBCCDD ||
            cpu_ready !== 1'b0)
            $fatal(1, "[ERR] Al doilea raspuns video este incorect");

        video_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] Cererea video in asteptare este servita");

        // TEST 6: Citire CPU de patru octeti.
        cpu_req = 1'b1;
        cpu_write = 1'b0;
        cpu_byte = 1'b0;
        cpu_addr = 23'h012C00;
        cpu_wdata = 32'd0;

        wait (ram_req == 1'b1);
        @(negedge clk);

        if (ram_addr !== 23'h012C00 ||
            ram_write !== 1'b0 ||
            ram_byte !== 1'b0)
            $fatal(1, "[ERR] Cererea LOAD a CPU este incorecta");

        ram_rdata = 32'h89ABCDEF;
        ram_ready = 1'b1;

        @(negedge clk);
        ram_ready = 1'b0;

        if (cpu_ready !== 1'b1 ||
            cpu_rdata !== 32'h89ABCDEF ||
            video_ready !== 1'b0)
            $fatal(1, "[ERR] Datele citite nu au ajuns corect la CPU");

        cpu_req = 1'b0;
        repeat (2) @(negedge clk);

        if (ram_req !== 1'b0 ||
            cpu_ready !== 1'b0 ||
            video_ready !== 1'b0)
            $fatal(1, "[ERR] Arbitrul nu a revenit in repaus");

        $display("[OK] Citire CPU si revenire in repaus");

        // TEST 7: Reset in timpul unei cereri neconfirmate.
        video_req = 1'b1;
        video_addr = 23'd800;

        wait (ram_req == 1'b1);
        @(negedge clk);

        rst_n = 1'b0;
        video_req = 1'b0;
        ram_init_done = 1'b0;

        repeat (2) @(negedge clk);

        if (ram_req !== 1'b0 ||
            cpu_ready !== 1'b0 ||
            video_ready !== 1'b0)
            $fatal(1, "[ERR] Resetul nu a anulat cererea");

        $display("[OK] Reset in timpul unei cereri");
        $display("PASS tb_ram_arbiter_simple");

        $finish;
    end

    initial
    begin
        #100000;
        $fatal(1, "[ERR] Timeout: testul arbitrului nu s-a terminat");
    end

endmodule