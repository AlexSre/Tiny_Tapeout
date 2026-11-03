`timescale 1ns / 1ps

module tb_memory_map_simple;

    logic clk;
    logic rst_n;

    // Interfata catre CPU.
    logic data_req;
    logic data_write;
    logic [16:0] data_addr;
    logic [31:0] data_wdata;

    logic [31:0] data_rdata;
    logic data_ready;

    // Periferice.
    logic [7:0] buttons;
    logic vsync;
    logic [31:0] random_value;
    logic [31:0] score;

    // Interfata catre arbitru.
    logic cpu_req;
    logic cpu_write;
    logic cpu_byte;
    logic [22:0] cpu_addr;
    logic [31:0] cpu_wdata;

    logic [31:0] cpu_rdata;
    logic cpu_ready;

    memory_map uut(
        .clk(clk),
        .rst_n(rst_n),

        .data_req(data_req),
        .data_write(data_write),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_rdata(data_rdata),
        .data_ready(data_ready),

        .buttons(buttons),
        .vsync(vsync),
        .random_value(random_value),
        .score(score),

        .cpu_req(cpu_req),
        .cpu_write(cpu_write),
        .cpu_byte(cpu_byte),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready)
    );

    always #19.841 clk = ~clk;

    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;

        data_req = 1'b0;
        data_write = 1'b0;
        data_addr = 17'd0;
        data_wdata = 32'd0;

        cpu_rdata = 32'd0;
        cpu_ready = 1'b0;

        buttons = 8'hA5;
        vsync = 1'b1;
        random_value = 32'd0;

        $display("--- Start test memory_map ---");

        repeat (3) @(negedge clk);

        if (data_ready !== 1'b0 ||
            cpu_req !== 1'b0 ||
            score !== 32'd0)
            $fatal(1, "[ERR] Reset incorect");

        rst_n = 1'b1;

        $display("[OK] Reset");

        // TEST 1: Scriere pixel la adresa 100.
        // Din valoarea F5 pastram numai RGB111: 101 = 5.
        @(negedge clk);
        data_req = 1'b1;
        data_write = 1'b1;
        data_addr = 17'd100;
        data_wdata = 32'h000000F5;

        wait (cpu_req == 1'b1);

        // Arbitru/memorie ocupata: confirmarea intarzie.
        repeat (3)
        begin
            @(negedge clk);

            if (cpu_req !== 1'b1 ||
                cpu_write !== 1'b1 ||
                cpu_byte !== 1'b1 ||
                cpu_addr !== 23'd100 ||
                cpu_wdata !== 32'd5)
                $fatal(1, "[ERR] Mapare STORE pixel incorecta");

            if (data_ready !== 1'b0)
                $fatal(1, "[ERR] Confirmare prematura catre CPU");
        end

        cpu_ready = 1'b1;

        @(negedge clk);
        cpu_ready = 1'b0;

        if (data_ready !== 1'b1 || cpu_req !== 1'b0)
            $fatal(1, "[ERR] Confirmare STORE pixel incorecta");

        // Raspunsul trebuie pastrat pana la retragerea cererii CPU.
        repeat (2)
        begin
            @(negedge clk);

            if (data_ready !== 1'b1)
                $fatal(1, "[ERR] Raspunsul nu este pastrat");
        end

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        if (data_ready !== 1'b0)
            $fatal(1, "[ERR] Raspunsul nu s-a dezactivat");

        $display("[OK] STORE pixel si handshake");

        // TEST 2: Citirea ultimului pixel.
        // 19199 = 0x04AFF, inca in framebuffer.
        data_req = 1'b1;
        data_write = 1'b0;
        data_addr = 17'h04AFF;
        data_wdata = 32'd0;

        wait (cpu_req == 1'b1);
        @(negedge clk);

        if (cpu_write !== 1'b0 ||
            cpu_byte !== 1'b1 ||
            cpu_addr !== 23'h004AFF)
            $fatal(1, "[ERR] Ultimul pixel este mapat incorect");

        // Din octetul FE trebuie returnati numai cei 3 biti RGB.
        cpu_rdata = 32'h000000FE;
        cpu_ready = 1'b1;

        @(negedge clk);
        cpu_ready = 1'b0;

        if (data_ready !== 1'b1 || data_rdata !== 32'd6)
            $fatal(1, "[ERR] LOAD pixel: rezultat=%h", data_rdata);

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] LOAD ultimul pixel: RGB=6");

        // TEST 3: Prima adresa de RAM generala.
        // Adresa CPU 0x04B00 devine adresa fizica 0x012C00.
        data_req = 1'b1;
        data_write = 1'b1;
        data_addr = 17'h04B00;
        data_wdata = 32'h12345678;

        wait (cpu_req == 1'b1);
        @(negedge clk);

        if (cpu_write !== 1'b1 ||
            cpu_byte !== 1'b0 ||
            cpu_addr !== 23'h012C00 ||
            cpu_wdata !== 32'h12345678)
            $fatal(1, "[ERR] Mapare STORE RAM incorecta");

        cpu_ready = 1'b1;

        @(negedge clk);
        cpu_ready = 1'b0;

        if (data_ready !== 1'b1)
            $fatal(1, "[ERR] Lipseste confirmarea STORE RAM");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] STORE RAM: adresa CPU inmultita cu 4");

        // TEST 4: Citirea unui cuvant complet de 32 de biti.
        data_req = 1'b1;
        data_write = 1'b0;
        data_addr = 17'h04B00;
        data_wdata = 32'd0;

        wait (cpu_req == 1'b1);
        @(negedge clk);

        if (cpu_write !== 1'b0 ||
            cpu_byte !== 1'b0 ||
            cpu_addr !== 23'h012C00)
            $fatal(1, "[ERR] Mapare LOAD RAM incorecta");

        cpu_rdata = 32'h12345678;
        cpu_ready = 1'b1;

        @(negedge clk);
        cpu_ready = 1'b0;

        if (data_ready !== 1'b1 ||
            data_rdata !== 32'h12345678)
            $fatal(1, "[ERR] LOAD RAM: rezultat=%h", data_rdata);

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] LOAD RAM: toti cei 32 de biti sunt pastrati");

        // TEST 5: Citirea butoanelor.
        data_req = 1'b1;
        data_write = 1'b0;
        data_addr = 17'h1FFFF;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (data_rdata !== 32'h000000A5 || cpu_req !== 1'b0)
            $fatal(1, "[ERR] Citire butoane incorecta");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] Butoane: A5, fara acces PSRAM");

        // TEST 6: VSYNC la nivel 1.
        data_req = 1'b1;
        data_addr = 17'h1FFFE;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (data_rdata !== 32'd1 || cpu_req !== 1'b0)
            $fatal(1, "[ERR] Citire VSYNC=1 incorecta");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        // VSYNC la nivel 0.
        vsync = 1'b0;
        data_req = 1'b1;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (data_rdata !== 32'd0 || cpu_req !== 1'b0)
            $fatal(1, "[ERR] Citire VSYNC=0 incorecta");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] Citire VSYNC pentru ambele niveluri");

        // TEST 7: Scriere scor.
        data_req = 1'b1;
        data_write = 1'b1;
        data_addr = 17'h1FFFD;
        data_wdata = 32'd123;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (score !== 32'd123 || cpu_req !== 1'b0)
            $fatal(1, "[ERR] Scriere scor incorecta");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        // Citire scor.
        data_req = 1'b1;
        data_write = 1'b0;
        data_wdata = 32'd0;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (data_rdata !== 32'd123 || cpu_req !== 1'b0)
            $fatal(1, "[ERR] Citire scor incorecta");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] Scriere/citire scor: 123");

        // TEST 8: Adresa RANDOM intoarce zero,
        // conform conexiunii actuale din top.
        data_req = 1'b1;
        data_addr = 17'h1FFFC;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (data_rdata !== 32'd0 || cpu_req !== 1'b0)
            $fatal(1, "[ERR] Citire RANDOM incorecta");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] RANDOM=0");

        // TEST 9: Scrierea la adresa butoanelor este ignorata.
        data_req = 1'b1;
        data_write = 1'b1;
        data_addr = 17'h1FFFF;
        data_wdata = 32'hFFFFFFFF;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (cpu_req !== 1'b0)
            $fatal(1, "[ERR] Scrierea perifericului a ajuns la PSRAM");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        // Citim din nou butoanele.
        data_req = 1'b1;
        data_write = 1'b0;

        wait (data_ready == 1'b1);
        @(negedge clk);

        if (data_rdata !== 32'h000000A5)
            $fatal(1, "[ERR] Citirea butoanelor dupa STORE este incorecta");

        data_req = 1'b0;
        repeat (2) @(negedge clk);

        $display("[OK] STORE la adresa butoanelor este ignorat");

        // Verificam si resetarea scorului dupa utilizare.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);

        if (score !== 32'd0 ||
            cpu_req !== 1'b0 ||
            data_ready !== 1'b0)
            $fatal(1, "[ERR] Resetul final este incorect");

        $display("[OK] Reset final");
        $display("PASS tb_memory_map_simple");

        $finish;
    end

    initial
    begin
        #100000;
        $fatal(1, "[ERR] Timeout: testul memory_map nu s-a terminat");
    end

endmodule