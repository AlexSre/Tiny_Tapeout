`timescale 1ns / 1ps

module tb_top_simple;

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
    logic [2:0] expected_rgb;

    assign uio_in = {ram_input, flash_input};

    top dut(
        .ui_in(ui_in),
        .uo_out(uo_out),

        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),

        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    ram_model_simple memory_model(
        .sck(uo_out[4]),
        .cs_n(uo_out[6]),
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
            @(negedge uo_out[5]);

            flash_command = 8'd0;

            repeat (8) begin
                @(posedge uo_out[4]);
                #1;

                if (uo_out[5] !== 1'b0 ||
                    uio_oe[3:0] !== 4'b1101)
                    $fatal(1, "Flash: directie incorecta la comanda");

                flash_command = {
                    flash_command[6:0], uio_out[0]
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
                        @(negedge uo_out[4]);
                        #1;

                        if (uo_out[5] !== 1'b0 ||
                            uio_oe[1] !== 1'b0)
                            $fatal(1, "Flash: IO1 nu este intrare");

                        flash_input = {
                            2'b00, status_shift[7], 1'b0
                        };

                        @(posedge uo_out[4]);
                        #1;

                        status_shift = {
                            status_shift[6:0], 1'b0
                        };
                    end
                end

                @(negedge uo_out[4]);
                #1;

                if (uo_out[5] !== 1'b1 ||
                    uio_oe[3:0] !== 4'b0000)
                    $fatal(1, "Flash: final incorect de comanda");

                flash_input = 4'd0;
                flash_init_step = flash_init_step + 1;
            end
            else begin
                if (flash_command !== 8'h6B)
                    $fatal(1, "Flash: asteptam citire 6B");

                flash_address = 24'd0;

                repeat (24) begin
                    @(posedge uo_out[4]);
                    #1;

                    if (uo_out[5] !== 1'b0 ||
                        uio_oe[3:0] !== 4'b1101)
                        $fatal(1, "Flash: adresa seriala incorecta");

                    flash_address = {
                        flash_address[22:0], uio_out[0]
                    };
                end

                // Fiecare instructiune ocupa patru octeti.
                // Format:
                // opcode[3:0], rdest[4:0], immediate[16:0]
                // sau opcode, rdest, rleft, rright, 7 biti zero.
                case (flash_address)
                    // LOADC R1, 0
                    24'd0:
                        program_word = {
                            6'd0, 4'h6, 5'd1, 17'd0
                        };

                    // LOADC R2, 5
                    24'd4:
                        program_word = {
                            6'd0, 4'h6, 5'd2, 17'd5
                        };

                    // STORE R2, [R1] : pixelul 0 = 5
                    24'd8:
                        program_word = {
                            6'd0, 4'h8, 5'd2,
                            5'd1, 5'd0, 7'd0
                        };

                    // LOAD R3, [R1]
                    24'd12:
                        program_word = {
                            6'd0, 4'h7, 5'd3,
                            5'd1, 5'd0, 7'd0
                        };

                    // LOADC R4, 0x4B00 : prima adresa RAM normala
                    24'd16:
                        program_word = {
                            6'd0, 4'h6, 5'd4, 17'h04B00
                        };

                    // STORE R3, [R4]
                    24'd20:
                        program_word = {
                            6'd0, 4'h8, 5'd3,
                            5'd4, 5'd0, 7'd0
                        };

                    // LOAD R5, [R4]
                    24'd24:
                        program_word = {
                            6'd0, 4'h7, 5'd5,
                            5'd4, 5'd0, 7'd0
                        };

                    // LOADC R6, 0x1FFFF : adresa butoanelor
                    24'd28:
                        program_word = {
                            6'd0, 4'h6, 5'd6, 17'h1FFFF
                        };

                    // LOAD R7, [R6]
                    24'd32:
                        program_word = {
                            6'd0, 4'h7, 5'd7,
                            5'd6, 5'd0, 7'd0
                        };

                    // LOADC R8, 0x1FFFD : adresa score
                    24'd36:
                        program_word = {
                            6'd0, 4'h6, 5'd8, 17'h1FFFD
                        };

                    // STORE R7, [R8]
                    24'd40:
                        program_word = {
                            6'd0, 4'h8, 5'd7,
                            5'd8, 5'd0, 7'd0
                        };

                    // JUMP 11 : bucla pe aceasta instructiune
                    24'd44:
                        program_word = {
                            6'd0, 4'h9, 5'd0, 17'd11
                        };

                    default:
                        $fatal(1, "Flash: PC neasteptat, adresa %h",
                               flash_address);
                endcase

                // Primul octet transmis este cel mai putin
                // semnificativ din instructiune.
                transmit_shift = {
                    program_word[7:0],
                    program_word[15:8],
                    program_word[23:16],
                    program_word[31:24]
                };

                repeat (8) begin
                    @(posedge uo_out[4]);
                    #1;

                    if (uo_out[5] !== 1'b0 ||
                        uio_oe[3:0] !== 4'b0000)
                        $fatal(1, "Flash: cicluri dummy incorecte");
                end

                repeat (8) begin
                    @(negedge uo_out[4]);
                    #1;

                    if (uo_out[5] !== 1'b0 ||
                        uio_oe[3:0] !== 4'b0000)
                        $fatal(1, "Flash: directie incorecta la citire");

                    flash_input = transmit_shift[31:28];

                    @(posedge uo_out[4]);
                    #1;

                    transmit_shift = {
                        transmit_shift[27:0], 4'd0
                    };
                end

                @(negedge uo_out[4]);
                #1;

                if (uo_out[5] !== 1'b1 ||
                    uio_oe[3:0] !== 4'b0000)
                    $fatal(1, "Flash: final incorect de citire");

                flash_input = 4'd0;
                flash_reads = flash_reads + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ena = 1'b1;
        ui_in = 8'hA5;

        expected_x = 0;
        expected_y = 0;
        visible_pixels = 0;
        colored_pixels = 0;

        expected_hsync = 1'b1;
        expected_vsync = 1'b1;
        expected_rgb = 3'b000;

        repeat (3) @(negedge clk);

        // HSYNC, VSYNC si ambele CS sunt inactive, adica 1.
        // SCK si RGB sunt 0.
        if (uo_out !== 8'hE8 ||
            uio_oe !== 8'h00)
            $fatal(1, "Top: iesiri incorecte in reset");

        $display("[OK] Reset si pini externi");

        rst_n = 1'b1;

        wait (dut.flash_init_done == 1'b1 &&
              dut.ram_init_done == 1'b1);

        @(negedge clk);

        if (dut.flash_init_error !== 1'b0 ||
            ram_model_initialized !== 1'b1)
            $fatal(1, "Top: initializarea memoriilor a esuat");

        $display("[OK] Initializarea Flash si RAM");

        // Ultima operatie utila a programului scrie score.
        wait (dut.score == 32'h000000A5);
        @(negedge clk);

        if (dut.u_cpu.regs[3] !== 32'd5)
            $fatal(1, "CPU: citirea pixelului este incorecta");

        if (dut.u_cpu.regs[5] !== 32'd5)
            $fatal(1, "CPU: citirea cuvantului RAM este incorecta");

        if (dut.u_cpu.regs[7] !== 32'h000000A5)
            $fatal(1, "CPU: citirea butoanelor este incorecta");

        if (memory_model.memory[0] !== 8'd5 ||
            memory_model.memory[1] !== 8'd0)
            $fatal(1, "Framebuffer: scriere incorecta");

        if (memory_model.memory[17'h12C00] !== 8'd5 ||
            memory_model.memory[17'h12C01] !== 8'd0 ||
            memory_model.memory[17'h12C02] !== 8'd0 ||
            memory_model.memory[17'h12C03] !== 8'd0)
            $fatal(1, "RAM: adresa fizica sau date incorecte");

        $display("[OK] Program executat din Flash prin QSPI");
        $display("[OK] Scriere si citire framebuffer");
        $display("[OK] Scriere si citire RAM normala");
        $display("[OK] Butoane si registrul score");

        // Asteptam blanking-ul si inceputul cadrului urmator,
        // pentru ca prima linie video sa poata fi preincarcata.
        wait (dut.y == 10'd480);
        wait (dut.y == 10'd0 && dut.x == 10'd0);

        expected_x = 0;
        expected_y = 0;

        // Un cadru complet: 800 * 525 cicluri.
        repeat (420000) begin
            // Citim la negedge: iesirile produse la posedge
            // sunt deja stabile.
            @(negedge clk);

            if (dut.x !== expected_x ||
                dut.y !== expected_y)
                $fatal(1, "VGA: coordonate incorecte");

            expected_hsync =
                !(expected_x >= 656 && expected_x < 752);

            expected_vsync =
                !(expected_y >= 490 && expected_y < 492);

            if (uo_out[7] !== expected_hsync ||
                uo_out[3] !== expected_vsync)
                $fatal(1, "VGA: sincronizari incorecte");

            expected_rgb = 3'b000;

            if (expected_x < 640 && expected_y < 480) begin
                visible_pixels = visible_pixels + 1;

                if (dut.pixel_valid !== 1'b1)
                    $fatal(1, "VGA: linie nepregatita la x=%0d y=%0d",
                           expected_x, expected_y);

                // RGB111 = 101, adica magenta.
                // Pentru aceasta culoare, si ordinea pinilor
                // {B,G,R} are valoarea 101.
                if (expected_x < 4 && expected_y < 4) begin
                    expected_rgb = 3'b101;
                    colored_pixels = colored_pixels + 1;
                end
            end

            if (uo_out[2:0] !== expected_rgb)
                $fatal(1,
                    "RGB incorect la x=%0d y=%0d: primit=%b asteptat=%b",
                    expected_x, expected_y,
                    uo_out[2:0], expected_rgb);

            if (expected_x == 799) begin
                expected_x = 0;

                if (expected_y == 524)
                    expected_y = 0;
                else
                    expected_y = expected_y + 1;
            end
            else begin
                expected_x = expected_x + 1;
            end
        end

        if (visible_pixels != 307200 ||
            colored_pixels != 16)
            $fatal(1, "VGA: numar incorect de pixeli");

        if (flash_reads < 12)
            $fatal(1, "Prea putine instructiuni citite");

        $display("[OK] Cadru VGA complet: 307200 pixeli vizibili");
        $display("[OK] Pixel din RAM afisat cu scalare 4x4");
        $display("[OK] Imagine neagra in rest si in blanking");
        $display("[OK] CPU, Flash si video functioneaza impreuna");

        // Dezactivarea ena trebuie sa reseteze designul.
        // Modelele sunt oprite deoarece testul se termina aici.
        ena = 1'b0;

        repeat (3) @(negedge clk);

        if (uo_out !== 8'hE8 ||
            uio_oe !== 8'h00 ||
            dut.score !== 32'd0)
            $fatal(1, "Top: dezactivarea ena nu reseteaza designul");

        $display("[OK] Dezactivare prin ena");
        $display("PASS tb_top_simple");
        $finish;
    end

    initial begin
        #40000000;
        $fatal(1, "TIMEOUT tb_top_simple");
    end

endmodule