`timescale 1ns / 1ps

module tb_input_sync_simple;

    logic clk;
    logic rst_n;

    logic [7:0] buttons_in;
    logic [7:0] buttons_sync;

    input_sync uut(
        .clk(clk),
        .rst_n(rst_n),

        .buttons_in(buttons_in),
        .buttons_sync(buttons_sync)
    );

    always #19.841 clk = ~clk;

    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;
        buttons_in = 8'd0;

        $display("--- Start test input_sync ---");

        // TEST 1: Reset.
        repeat (3) @(negedge clk);

        if (buttons_sync !== 8'd0)
            $fatal(1, "[ERR] Iesirea nu este zero dupa reset");

        rst_n = 1'b1;

        $display("[OK] Reset");

        // TEST 2: Intrarea devine A5 intre fronturile de clock.
        @(negedge clk);
        #3;
        buttons_in = 8'hA5;

        #1;

        if (buttons_sync !== 8'd0)
            $fatal(1, "[ERR] Iesirea s-a modificat fara clock");

        // Primul etaj preia A5; al doilea pastreaza zero.
        @(posedge clk);
        #1;

        if (buttons_sync !== 8'd0)
            $fatal(1, "[ERR] A5 a ajuns prea devreme la iesire");

        // Al doilea etaj preia A5.
        @(posedge clk);
        #1;

        if (buttons_sync !== 8'hA5)
            $fatal(1, "[ERR] A5 nu a ajuns la iesire dupa doua fronturi");

        $display("[OK] A5 apare dupa doua fronturi pozitive");

        // TEST 3: O noua valoare trebuie sa respecte aceeasi intarziere.
        @(negedge clk);
        #3;
        buttons_in = 8'h3C;

        @(posedge clk);
        #1;

        if (buttons_sync !== 8'hA5)
            $fatal(1, "[ERR] Valoarea anterioara nu a fost pastrata");

        @(posedge clk);
        #1;

        if (buttons_sync !== 8'h3C)
            $fatal(1, "[ERR] 3C nu a ajuns corect la iesire");

        $display("[OK] Tranzitie A5 -> 3C");

        // TEST 4: Intrarea constanta produce o iesire constanta.
        repeat (4)
        begin
            @(posedge clk);
            #1;

            if (buttons_sync !== 8'h3C)
                $fatal(1, "[ERR] Iesirea nu ramane stabila");
        end

        $display("[OK] Iesire stabila pentru intrare constanta");

        // TEST 5: Eliberarea tuturor butoanelor.
        @(negedge clk);
        buttons_in = 8'd0;

        @(posedge clk);
        #1;

        if (buttons_sync !== 8'h3C)
            $fatal(1, "[ERR] Zero a ajuns prea devreme la iesire");

        @(posedge clk);
        #1;

        if (buttons_sync !== 8'd0)
            $fatal(1, "[ERR] Iesirea nu a revenit la zero");

        $display("[OK] Revenire la zero dupa doua fronturi");

        // TEST 6: Reset in timp ce intrarea este FF.
        @(negedge clk);
        buttons_in = 8'hFF;

        repeat (2) @(posedge clk);
        #1;

        if (buttons_sync !== 8'hFF)
            $fatal(1, "[ERR] Pregatirea testului de reset a esuat");

        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        #1;

        if (buttons_sync !== 8'd0)
            $fatal(1, "[ERR] Resetul nu a adus iesirea la zero");

        $display("[OK] Reset cu intrare nenula");

        // TEST 7: Dupa reset sunt necesare din nou doua fronturi.
        @(negedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        #1;

        if (buttons_sync !== 8'd0)
            $fatal(1, "[ERR] Primul etaj nu a fost resetat corect");

        @(posedge clk);
        #1;

        if (buttons_sync !== 8'hFF)
            $fatal(1, "[ERR] Reluare incorecta dupa reset");

        $display("[OK] Reluare corecta dupa reset");
        $display("PASS tb_input_sync_simple");

        $finish;
    end

    initial
    begin
        #100000;
        $fatal(1, "[ERR] Timeout: testul input_sync nu s-a terminat");
    end

endmodule