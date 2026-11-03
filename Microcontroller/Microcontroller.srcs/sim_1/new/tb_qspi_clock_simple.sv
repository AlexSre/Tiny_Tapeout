`timescale 1ns / 1ps

module tb_qspi_clock_simple;

    logic clk;
    logic rst_n;
    logic enable;

    logic sck;
    logic rise_en;
    logic fall_en;

    qspi_clock uut(
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),

        .sck(sck),
        .rise_en(rise_en),
        .fall_en(fall_en)
    );

    // Aproximativ 25.2 MHz.
    always #19.841 clk = ~clk;

    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;
        enable = 1'b0;

        $display("--- Start test qspi_clock ---");

        // TEST 1: Reset.
        repeat (3) @(negedge clk);

        if (sck !== 1'b0 ||
            rise_en !== 1'b0 ||
            fall_en !== 1'b0)
            $fatal(1, "[ERR] Reset incorect");

        $display("[OK] Reset");

        // TEST 2: Clock oprit prin enable=0.
        rst_n = 1'b1;

        repeat (3)
        begin
            @(negedge clk);

            if (sck !== 1'b0 ||
                rise_en !== 1'b0 ||
                fall_en !== 1'b0)
                $fatal(1, "[ERR] Clock activ desi enable=0");
        end

        $display("[OK] enable=0 mentine clock-ul oprit");

        // TEST 3: Pornire.
        enable = 1'b1;

        // Lasam atribuirile combinationalе sa se actualizeze.
        #1;

        if (sck !== 1'b0 ||
            rise_en !== 1'b1 ||
            fall_en !== 1'b0)
            $fatal(1, "[ERR] Prima tranzitie nu este pregatita corect");

        // Verificam zece perioade complete ale lui SCK.
        repeat (10)
        begin
            // Inainte de acest front, rise_en era 1.
            @(posedge clk);
            #1;

            if (sck !== 1'b1 ||
                rise_en !== 1'b0 ||
                fall_en !== 1'b1)
                $fatal(1, "[ERR] Tranzitie SCK 0 -> 1 incorecta");

            // La urmatorul front, fall_en provoaca tranzitia 1 -> 0.
            @(posedge clk);
            #1;

            if (sck !== 1'b0 ||
                rise_en !== 1'b1 ||
                fall_en !== 1'b0)
                $fatal(1, "[ERR] Tranzitie SCK 1 -> 0 incorecta");
        end

        $display("[OK] SCK are frecventa clk/2");
        $display("[OK] rise_en si fall_en alterneaza corect");

        // TEST 4: Oprire cand SCK este 1.
        @(posedge clk);
        #1;

        if (sck !== 1'b1)
            $fatal(1, "[ERR] SCK trebuia sa fie 1 inainte de oprire");

        @(negedge clk);
        enable = 1'b0;
        #1;

        // Semnalele de faza se dezactiveaza combinational.
        if (rise_en !== 1'b0 || fall_en !== 1'b0)
            $fatal(1, "[ERR] Semnalele de faza nu s-au dezactivat");

        // SCK revine la 0 la urmatorul front pozitiv al lui clk.
        @(posedge clk);
        #1;

        if (sck !== 1'b0)
            $fatal(1, "[ERR] SCK nu s-a oprit la 0");

        repeat (3)
        begin
            @(negedge clk);

            if (sck !== 1'b0 ||
                rise_en !== 1'b0 ||
                fall_en !== 1'b0)
                $fatal(1, "[ERR] Clock-ul nu ramane oprit");
        end

        $display("[OK] Oprire prin enable");

        // TEST 5: Repornire.
        enable = 1'b1;
        #1;

        if (rise_en !== 1'b1 || fall_en !== 1'b0)
            $fatal(1, "[ERR] Faza de repornire incorecta");

        @(posedge clk);
        #1;

        if (sck !== 1'b1 ||
            rise_en !== 1'b0 ||
            fall_en !== 1'b1)
            $fatal(1, "[ERR] Repornire incorecta");

        $display("[OK] Repornire");

        // TEST 6: Reset cu enable ramas activ.
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        #1;

        if (sck !== 1'b0 ||
            rise_en !== 1'b0 ||
            fall_en !== 1'b0)
            $fatal(1, "[ERR] Resetul nu are prioritate fata de enable");

        $display("[OK] Resetul are prioritate fata de enable");
        $display("PASS tb_qspi_clock_simple");

        $finish;
    end

    initial
    begin
        #100000;
        $fatal(1, "[ERR] Timeout: testul qspi_clock nu s-a terminat");
    end

endmodule