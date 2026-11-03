`timescale 1ns / 1ps

module tb_qspi_flash_simple;

    logic clk;
    logic rst_n;

    logic sck;
    logic rise_en;
    logic fall_en;

    logic flash_req;
    logic [23:0] flash_addr;
    logic [31:0] flash_rdata;
    logic flash_ready;

    logic flash_cs_n;
    logic [3:0] flash_sd_in;
    logic [3:0] flash_sd_out;
    logic [3:0] flash_sd_oe;

    logic init_done;
    logic init_error;

    // Variabile pentru memoria simulata.
    logic [7:0] received_command;
    logic [7:0] expected_command;
    logic [7:0] received_status;

    logic [7:0] model_status;
    logic [7:0] status_shift;

    logic [23:0] received_address;
    logic [31:0] transmit_shift;

    integer init_step;
    integer reply_index;
    integer read_index;
    integer selected_clocks;

    logic model_finished;
    logic [31:0] expected_data;

    qspi_clock clock_generator(
        .clk(clk),
        .rst_n(rst_n),
        .enable(1'b1),

        .sck(sck),
        .rise_en(rise_en),
        .fall_en(fall_en)
    );

    qspi_flash_controller uut(
        .clk(clk),
        .rst_n(rst_n),

        .rise_en(rise_en),
        .fall_en(fall_en),

        .flash_req(flash_req),
        .flash_addr(flash_addr),
        .flash_rdata(flash_rdata),
        .flash_ready(flash_ready),

        .flash_cs_n(flash_cs_n),
        .flash_sd_in(flash_sd_in),
        .flash_sd_out(flash_sd_out),
        .flash_sd_oe(flash_sd_oe),

        .init_done(init_done),
        .init_error(init_error)
    );

    always #19.841 clk = ~clk;

    // Numaram fronturile SCK din fiecare tranzactie.
    always @(negedge flash_cs_n)
        selected_clocks = 0;

    always @(posedge sck)
    begin
        if (!flash_cs_n)
            selected_clocks = selected_clocks + 1;
    end

    // MEMORIA FLASH SIMULATA.
    initial
    begin
        flash_sd_in = 4'd0;

        // QE este initial zero.
        // Bitul 6 este unu pentru a verifica pastrarea lui.
        model_status = 8'h40;

        received_command = 8'd0;
        expected_command = 8'd0;
        received_status = 8'd0;
        received_address = 24'd0;
        status_shift = 8'd0;
        transmit_shift = 32'd0;

        init_step = 0;
        reply_index = 0;
        model_finished = 1'b0;

        // Secventa asteptata:
        // AB, 66, 99, 35, 50, 31, 35.
        repeat (7)
        begin
            @(negedge flash_cs_n);

            received_command = 8'd0;

            // Comanda este transmisa serial pe IO0.
            repeat (8)
            begin
                @(posedge sck);
                #1;

                if (flash_cs_n !== 1'b0 ||
                    flash_sd_oe !== 4'b1101)
                    $fatal(1, "[ERR] Semnale SPI incorecte la comanda");

                received_command = {
                    received_command[6:0],
                    flash_sd_out[0]
                };
            end

            case (init_step)
                0: expected_command = 8'hAB;
                1: expected_command = 8'h66;
                2: expected_command = 8'h99;
                3: expected_command = 8'h35;
                4: expected_command = 8'h50;
                5: expected_command = 8'h31;
                6: expected_command = 8'h35;
            endcase

            if (received_command !== expected_command)
                $fatal(
                    1,
                    "[ERR] Comanda init: asteptat=%h, primit=%h",
                    expected_command, received_command
                );

            // Raspuns la citirea registrului Status 2.
            if (received_command == 8'h35)
            begin
                status_shift = model_status;

                repeat (8)
                begin
                    // Memoria prezinta bitul dupa frontul descendent.
                    @(negedge sck);
                    #1;

                    if (flash_cs_n !== 1'b0 ||
                        flash_sd_oe[1] !== 1'b0)
                        $fatal(1, "[ERR] IO1 nu este disponibil pentru citire");

                    flash_sd_in = {
                        2'b00, status_shift[7], 1'b0
                    };

                    // Controllerul il citeste la urmatorul front.
                    @(posedge sck);
                    #1;

                    status_shift = {status_shift[6:0], 1'b0};
                end
            end

            // Primim noua valoare pentru Status 2.
            if (received_command == 8'h31)
            begin
                received_status = 8'd0;

                repeat (8)
                begin
                    @(posedge sck);
                    #1;

                    if (flash_cs_n !== 1'b0 ||
                        flash_sd_oe !== 4'b1101)
                        $fatal(1, "[ERR] Scriere Status 2 incorecta");

                    received_status = {
                        received_status[6:0],
                        flash_sd_out[0]
                    };
                end

                // 40 | 02 = 42: QE activ, bitul 6 pastrat.
                if (received_status !== 8'h42)
                    $fatal(
                        1,
                        "[ERR] Status 2 asteptat=42, primit=%h",
                        received_status
                    );
            end

            @(posedge flash_cs_n);
            #1;

            if (received_command == 8'h35 ||
                received_command == 8'h31)
            begin
                if (selected_clocks != 16)
                    $fatal(1, "[ERR] Numar incorect de cicluri pentru status");
            end
            else
            begin
                if (selected_clocks != 8)
                    $fatal(1, "[ERR] Numar incorect de cicluri pentru comanda");
            end

            if (received_command == 8'h31)
                model_status = received_status;

            flash_sd_in = 4'd0;
            init_step = init_step + 1;
        end

        $display("[OK] Secventa de initializare si activarea QE");

        // Raspundem la doua citiri.
        repeat (2)
        begin
            @(negedge flash_cs_n);

            received_command = 8'd0;
            received_address = 24'd0;

            // Primim comanda 6B.
            repeat (8)
            begin
                @(posedge sck);
                #1;

                if (flash_cs_n !== 1'b0 ||
                    flash_sd_oe !== 4'b1101)
                    $fatal(1, "[ERR] Comanda de citire transmisa incorect");

                received_command = {
                    received_command[6:0],
                    flash_sd_out[0]
                };
            end

            if (received_command !== 8'h6B)
                $fatal(1, "[ERR] Comanda asteptata este 6B");

            // Primim adresa de 24 de biti, tot serial.
            repeat (24)
            begin
                @(posedge sck);
                #1;

                if (flash_cs_n !== 1'b0 ||
                    flash_sd_oe !== 4'b1101)
                    $fatal(1, "[ERR] Transmiterea adresei este incorecta");

                received_address = {
                    received_address[22:0],
                    flash_sd_out[0]
                };
            end

            if (reply_index == 0)
            begin
                if (received_address !== 24'h000000)
                    $fatal(1, "[ERR] Prima adresa este incorecta");

                // Ordinea octetilor pe magistrala: 12, 34, 56, 78.
                transmit_shift = 32'h12345678;
            end
            else
            begin
                if (received_address !== 24'h123456)
                    $fatal(1, "[ERR] A doua adresa este incorecta");

                // Ordinea octetilor pe magistrala: A1, B2, C3, D4.
                transmit_shift = 32'hA1B2C3D4;
            end

            // Opt cicluri dummy, fara date utile.
            repeat (8)
            begin
                @(posedge sck);
                #1;

                if (flash_cs_n !== 1'b0 ||
                    flash_sd_oe !== 4'b0000)
                    $fatal(1, "[ERR] Liniile nu sunt eliberate in dummy");
            end

            // Trimitem 32 de biti in opt grupuri de cate patru.
            repeat (8)
            begin
                @(negedge sck);
                #1;

                if (flash_cs_n !== 1'b0 ||
                    flash_sd_oe !== 4'b0000)
                    $fatal(1, "[ERR] Controllerul conduce liniile la citire");

                flash_sd_in = transmit_shift[31:28];

                @(posedge sck);
                #1;

                transmit_shift = {
                    transmit_shift[27:0], 4'd0
                };
            end

            @(posedge flash_cs_n);
            #1;

            // 8 comanda + 24 adresa + 8 dummy + 8 date.
            if (selected_clocks != 48)
                $fatal(
                    1,
                    "[ERR] Citirea a avut %0d cicluri, nu 48",
                    selected_clocks
                );

            flash_sd_in = 4'd0;
            reply_index = reply_index + 1;
        end

        model_finished = 1'b1;
    end

    // CERERILE CATRE CONTROLLER SI VERIFICAREA REZULTATELOR.
    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;

        flash_req = 1'b0;
        flash_addr = 24'd0;

        read_index = 0;
        expected_data = 32'd0;

        $display("--- Start test qspi_flash ---");

        repeat (3) @(negedge clk);

        if (flash_cs_n !== 1'b1 ||
            flash_sd_oe !== 4'd0 ||
            flash_ready !== 1'b0 ||
            init_done !== 1'b0 ||
            init_error !== 1'b0)
            $fatal(1, "[ERR] Reset Flash incorect");

        rst_n = 1'b1;

        $display("[OK] Reset");

        wait (init_done == 1'b1 || init_error == 1'b1);
        @(negedge clk);

        if (init_done !== 1'b1 ||
            init_error !== 1'b0 ||
            model_status !== 8'h42)
            $fatal(1, "[ERR] Initializarea Flash a esuat");

        $display("[OK] init_done=1, init_error=0");

        repeat (2)
        begin
            @(negedge clk);

            if (read_index == 0)
            begin
                flash_addr = 24'h000000;
                expected_data = 32'h78563412;
            end
            else
            begin
                flash_addr = 24'h123456;
                expected_data = 32'hD4C3B2A1;
            end

            flash_req = 1'b1;

            wait (flash_ready == 1'b1);

            // Raspunsul trebuie pastrat pana retragem cererea.
            repeat (3)
            begin
                @(negedge clk);

                if (flash_ready !== 1'b1 ||
                    flash_rdata !== expected_data ||
                    flash_cs_n !== 1'b1 ||
                    flash_sd_oe !== 4'd0)
                    $fatal(
                        1,
                        "[ERR] Citire: asteptat=%h, primit=%h",
                        expected_data, flash_rdata
                    );
            end

            $display(
                "[OK] Citire adresa %h: %h, ordine little-endian",
                flash_addr, flash_rdata
            );

            flash_req = 1'b0;
            repeat (2) @(negedge clk);

            if (flash_ready !== 1'b0)
                $fatal(1, "[ERR] flash_ready nu s-a dezactivat");

            read_index = read_index + 1;
        end

        wait (model_finished == 1'b1);

        $display("[OK] Adrese, cicluri dummy si directia liniilor");
        $display("[OK] Pastrarea si eliberarea raspunsului");
        $display("PASS tb_qspi_flash_simple");

        $finish;
    end

    initial
    begin
        // Initializarea controllerului include o asteptare de circa 6 ms.
        #10000000;
        $fatal(1, "[ERR] Timeout: testul Flash nu s-a terminat");
    end

endmodule