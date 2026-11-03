`timescale 1ns / 1ps

module tb_video_line_buffer_simple;

    logic clk;
    logic rst_n;
    logic ram_init_done;

    // Semnale VGA.
    logic [9:0] x;
    logic [9:0] y;
    logic hsync;
    logic vsync;
    logic video_on;

    // Interfata bufferului catre memorie.
    logic video_req;
    logic [22:0] video_addr;
    logic [31:0] video_rdata;
    logic video_ready;

    // Pixelul furnizat de buffer.
    logic [7:0] pixel_data;
    logic pixel_valid;

    // Memorie simulata.
    logic memory_busy;
    logic [22:0] saved_addr;

    integer delay_count;
    integer expected_addr;
    integer request_count;

    logic [7:0] memory_pixel0;
    logic [7:0] memory_pixel1;
    logic [7:0] memory_pixel2;
    logic [7:0] memory_pixel3;

    // Verificarea imaginii.
    integer expected_x;
    integer expected_y;
    integer checked_pixels;

    logic [7:0] expected_pixel;

    vga_timing timing(
        .clk(clk),
        .rst_n(rst_n),

        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),

        .x(x),
        .y(y)
    );

    video_line_buffer uut(
        .clk(clk),
        .rst_n(rst_n),

        .x(x),
        .y(y),
        .video_on(video_on),

        .ram_init_done(ram_init_done),

        .video_req(video_req),
        .video_addr(video_addr),
        .video_rdata(video_rdata),
        .video_ready(video_ready),

        .pixel_data(pixel_data),
        .pixel_valid(pixel_valid)
    );

    always #19.841 clk = ~clk;

    // Construim cei patru pixeli ceruti din memoria simulata.
    // Adresele sunt aliniate la patru octeti.
    always_comb
    begin
        memory_pixel0 =
            ((saved_addr % 160) + (saved_addr / 160)) % 8;

        memory_pixel1 =
            ((saved_addr % 160) + 1 + (saved_addr / 160)) % 8;

        memory_pixel2 =
            ((saved_addr % 160) + 2 + (saved_addr / 160)) % 8;

        memory_pixel3 =
            ((saved_addr % 160) + 3 + (saved_addr / 160)) % 8;
    end

    // Model simplu pentru raspunsul memoriei.
    // Nu simuleaza protocolul QSPI.
    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            video_rdata <= 32'd0;
            video_ready <= 1'b0;

            memory_busy <= 1'b0;
            saved_addr <= 23'd0;
            delay_count <= 0;

            expected_addr <= 0;
            request_count <= 0;
        end
        else
        begin
            if (!video_req)
            begin
                video_ready <= 1'b0;
                memory_busy <= 1'b0;
            end
            else if (!memory_busy)
            begin
                // Verificam limitele si ordinea adreselor.
                if (video_addr > 23'd19196 ||
                    video_addr[1:0] !== 2'b00)
                    $fatal(1, "[ERR] Adresa video invalida: %0d",
                           video_addr);

                if (video_addr !== expected_addr[22:0])
                    $fatal(
                        1,
                        "[ERR] Adresa asteptata=%0d, primita=%0d",
                        expected_addr, video_addr
                    );

                if (expected_addr == 19196)
                    expected_addr <= 0;
                else
                    expected_addr <= expected_addr + 4;

                request_count <= request_count + 1;

                saved_addr <= video_addr;
                delay_count <= 58;
                memory_busy <= 1'b1;
            end
            else
            begin
                // Adresa trebuie pastrata pana la confirmare.
                if (video_addr !== saved_addr)
                    $fatal(1, "[ERR] Adresa s-a schimbat in timpul cererii");

                if (!video_ready)
                begin
                    if (delay_count == 0)
                    begin
                        // Primul pixel ocupa octetul inferior.
                        video_rdata <= {
                            memory_pixel3,
                            memory_pixel2,
                            memory_pixel1,
                            memory_pixel0
                        };

                        video_ready <= 1'b1;
                    end
                    else
                    begin
                        delay_count <= delay_count - 1;
                    end
                end
            end
        end
    end

    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;
        ram_init_done = 1'b0;

        expected_x = 0;
        expected_y = 0;
        checked_pixels = 0;
        expected_pixel = 8'd0;

        $display("--- Start test video_line_buffer ---");

        // TEST 1: Reset.
        repeat (3) @(negedge clk);

        if (video_req !== 1'b0 ||
            pixel_valid !== 1'b0 ||
            pixel_data !== 8'd0)
            $fatal(1, "[ERR] Reset buffer incorect");

        rst_n = 1'b1;

        $display("[OK] Reset");

        // TEST 2: Nu cerem date inainte de initializarea RAM.
        repeat (100)
        begin
            @(negedge clk);

            if (video_req !== 1'b0 ||
                pixel_valid !== 1'b0 ||
                pixel_data !== 8'd0)
                $fatal(1, "[ERR] Buffer activ inainte de initializarea RAM");
        end

        ram_init_done = 1'b1;

        $display("[OK] Bufferul asteapta initializarea RAM");

        // Asteptam prima pauza verticala si incarcarea liniei zero.
        // Verificarea imaginii incepe cu cadrul urmator.
        wait (x == 10'd799 && y == 10'd524);

        @(posedge clk);
        #1;

        if (x !== 10'd0 || y !== 10'd0)
            $fatal(1, "[ERR] Nu suntem la inceputul cadrului");

        if (pixel_valid !== 1'b1 || pixel_data !== 8'd0)
            $fatal(1, "[ERR] Prima linie nu a fost pregatita");

        $display("[OK] Prima linie este pregatita inainte de afisare");

        // TEST 3: Verificam fiecare pozitie dintr-un cadru.
        repeat (420000)
        begin
            if (x !== expected_x[9:0] ||
                y !== expected_y[9:0])
                $fatal(1, "[ERR] Coordonate VGA neasteptate");

            if (expected_x < 640 && expected_y < 480)
            begin
                // Coordonatele logice se obtin prin impartire la patru.
                expected_pixel =
                    ((expected_x / 4) + (expected_y / 4)) % 8;

                if (pixel_valid !== 1'b1)
                    $fatal(
                        1,
                        "[ERR] Pixel indisponibil la (%0d,%0d)",
                        expected_x, expected_y
                    );

                if (pixel_data !== expected_pixel)
                    $fatal(
                        1,
                        "[ERR] Pixel (%0d,%0d): asteptat=%0d, primit=%0d",
                        expected_x, expected_y,
                        expected_pixel, pixel_data
                    );

                checked_pixels = checked_pixels + 1;
            end
            else
            begin
                if (pixel_valid !== 1'b0 || pixel_data !== 8'd0)
                    $fatal(1, "[ERR] Iesire nenula in blanking");
            end

            // Pozitia asteptata pentru urmatorul ciclu.
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

        if (checked_pixels != 307200)
            $fatal(1, "[ERR] Nu au fost verificati toti pixelii");

        if (request_count < 4800)
            $fatal(1, "[ERR] Prea putine citiri pentru un framebuffer");

        $display("[OK] 307200 pixeli verificati");
        $display("[OK] Ordinea pixelilor si scalarea 4x4");
        $display("[OK] Alternarea bufferelor pe toate cele 120 de linii");
        $display("[OK] Adrese consecutive, cate patru octeti");
        $display("[OK] Iesire neagra in blanking");

        // TEST 4: Reset dupa afisare.
        @(negedge clk);
        rst_n = 1'b0;
        ram_init_done = 1'b0;

        repeat (2) @(negedge clk);

        if (video_req !== 1'b0 ||
            pixel_valid !== 1'b0 ||
            pixel_data !== 8'd0)
            $fatal(1, "[ERR] Reset final incorect");

        $display("[OK] Reset final");
        $display("PASS tb_video_line_buffer_simple");

        $finish;
    end

    initial
    begin
        // Doua cadre dureaza aproximativ 33.33 ms.
        #40000000;
        $fatal(1, "[ERR] Timeout: testul bufferului nu s-a terminat");
    end

endmodule