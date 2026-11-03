`timescale 1ns / 1ps

module tb_vga_timing_simple;

    logic clk;
    logic rst_n;

    logic hsync;
    logic vsync;
    logic video_on;

    logic [9:0] x;
    logic [9:0] y;

    // Coordonatele asteptate, calculate de testbench.
    integer expected_x;
    integer expected_y;

    integer visible_pixels;
    integer hsync_cycles;
    integer vsync_cycles;

    vga_timing uut(
        .clk(clk),
        .rst_n(rst_n),

        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),

        .x(x),
        .y(y)
    );

    always #19.841 clk = ~clk;

    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;

        expected_x = 0;
        expected_y = 0;

        visible_pixels = 0;
        hsync_cycles = 0;
        vsync_cycles = 0;

        $display("--- Start test vga_timing ---");

        // TEST 1: Reset.
        repeat (3) @(negedge clk);

        if (x !== 10'd0 ||
            y !== 10'd0 ||
            video_on !== 1'b0 ||
            hsync !== 1'b1 ||
            vsync !== 1'b1)
            $fatal(1, "[ERR] Reset VGA incorect");

        $display("[OK] Reset");

        rst_n = 1'b1;
        #1;

        // TEST 2: Toate pozitiile unui cadru.
        // 800 * 525 = 420000 cicluri de pixel.
        repeat (420000)
        begin
            // Verificam ordinea coordonatelor.
            if (x !== expected_x[9:0] ||
                y !== expected_y[9:0])
                $fatal(
                    1,
                    "[ERR] Coordonate: asteptat (%0d,%0d), primit (%0d,%0d)",
                    expected_x, expected_y, x, y
                );

            // Verificam zona vizibila.
            if (expected_x < 640 && expected_y < 480)
            begin
                if (video_on !== 1'b1)
                    $fatal(
                        1,
                        "[ERR] video_on=0 in zona vizibila la (%0d,%0d)",
                        expected_x, expected_y
                    );
            end
            else
            begin
                if (video_on !== 1'b0)
                    $fatal(
                        1,
                        "[ERR] video_on activ in blanking la (%0d,%0d)",
                        expected_x, expected_y
                    );
            end

            // Verificam impulsul HSYNC.
            if (expected_x >= 656 && expected_x < 752)
            begin
                if (hsync !== 1'b0)
                    $fatal(1, "[ERR] HSYNC trebuia sa fie 0");
            end
            else
            begin
                if (hsync !== 1'b1)
                    $fatal(1, "[ERR] HSYNC trebuia sa fie 1");
            end

            // Verificam impulsul VSYNC.
            if (expected_y >= 490 && expected_y < 492)
            begin
                if (vsync !== 1'b0)
                    $fatal(1, "[ERR] VSYNC trebuia sa fie 0");
            end
            else
            begin
                if (vsync !== 1'b1)
                    $fatal(1, "[ERR] VSYNC trebuia sa fie 1");
            end

            // Numaram ciclurile observate.
            if (video_on)
                visible_pixels = visible_pixels + 1;

            if (!hsync)
                hsync_cycles = hsync_cycles + 1;

            if (!vsync)
                vsync_cycles = vsync_cycles + 1;

            // Calculam pozitia asteptata la urmatorul clock.
            if (expected_x == 799)
            begin
                expected_x = 0;

                if (expected_y == 524)
                    expected_y = 0;
                else
                    expected_y = expected_y + 1;
            end
            else
            begin
                expected_x = expected_x + 1;
            end

            @(posedge clk);
            #1;
        end

        $display("[OK] Coordonate corecte pe un cadru complet");
        $display("[OK] Zona vizibila si intervale HSYNC/VSYNC corecte");

        // TEST 3: Totalurile unui cadru.

        // 640 * 480 = 307200 pixeli vizibili.
        if (visible_pixels != 307200)
            $fatal(
                1,
                "[ERR] Numar pixeli vizibili: %0d",
                visible_pixels
            );

        $display("[OK] 307200 pixeli vizibili");

        // HSYNC: 96 cicluri pe fiecare dintre cele 525 de linii.
        if (hsync_cycles != 50400)
            $fatal(
                1,
                "[ERR] Numar cicluri HSYNC activ: %0d",
                hsync_cycles
            );

        $display("[OK] HSYNC activ 96 cicluri pe linie");

        // VSYNC: 2 linii complete, fiecare cu 800 de cicluri.
        if (vsync_cycles != 1600)
            $fatal(
                1,
                "[ERR] Numar cicluri VSYNC activ: %0d",
                vsync_cycles
            );

        $display("[OK] VSYNC activ doua linii");

        // Dupa un cadru trebuie sa revenim la origine.
        if (x !== 10'd0 || y !== 10'd0)
            $fatal(1, "[ERR] Cadrul nu a revenit la (0,0)");

        $display("[OK] Revenire la inceputul cadrului");

        // TEST 4: Reset dupa ce numaratoarea a avansat.
        repeat (10) @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        #1;

        if (x !== 10'd0 ||
            y !== 10'd0 ||
            video_on !== 1'b0 ||
            hsync !== 1'b1 ||
            vsync !== 1'b1)
            $fatal(1, "[ERR] Reset final incorect");

        $display("[OK] Reset final");
        $display("PASS tb_vga_timing_simple");

        $finish;
    end

    initial
    begin
        // Timeout de 20 ms.
        #20000000;
        $fatal(1, "[ERR] Timeout: testul VGA nu s-a terminat");
    end

endmodule