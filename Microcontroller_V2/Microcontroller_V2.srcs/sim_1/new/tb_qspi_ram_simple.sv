`timescale 1ns / 1ps

// Model comun pentru cele doua testbench-uri.
// Memoria este initializata cu zero numai in simulare.
module ram_model_simple #(parameter MEMORY_BYTES = 131072)(
    input  logic       sck,
    input  logic       cs_n,
    input  logic [3:0] sd_out,
    input  logic [3:0] sd_oe,

    output logic [3:0] sd_in,
    output logic       initialized
);

    logic [7:0] memory [0:MEMORY_BYTES-1];

    logic [7:0] command;
    logic [23:0] address;
    logic [7:0] byte_value;

    integer index;
    integer init_step;
    integer nibble_count;
    integer transaction_count;

    initial begin
        sd_in = 4'd0;
        initialized = 1'b0;

        command = 8'd0;
        address = 24'd0;
        byte_value = 8'd0;

        init_step = 0;
        nibble_count = 0;
        transaction_count = 0;

        index = 0;

        repeat (MEMORY_BYTES) begin
            memory[index] = 8'd0;
            index = index + 1;
        end

        forever begin
            @(negedge cs_n);

            command = 8'd0;

            // Comanda este transmisa serial pe IO0.
            repeat (8) begin
                @(posedge sck);
                #1;

                if (cs_n !== 1'b0 ||
                    sd_oe !== 4'b0001)
                    $fatal(1, "RAM: directie incorecta la comanda");

                command = {command[6:0], sd_out[0]};
            end

            if (init_step < 2) begin
                if (init_step == 0 && command !== 8'h66)
                    $fatal(1, "RAM: asteptam comanda 66");

                if (init_step == 1 && command !== 8'h99)
                    $fatal(1, "RAM: asteptam comanda 99");

                // Urmatorul front descrescator incheie comanda.
                @(negedge sck);
                #1;

                if (cs_n !== 1'b1 ||
                    sd_oe !== 4'b0000)
                    $fatal(1, "RAM: final incorect al resetului");

                init_step = init_step + 1;

                if (init_step == 2)
                    initialized = 1'b1;
            end
            else begin
                if (command !== 8'h38 &&
                    command !== 8'hEB)
                    $fatal(1, "RAM: comanda necunoscuta %h",
                           command);

                // Adresa: 24 biti, cate patru biti pe ciclu.
                address = 24'd0;

                repeat (6) begin
                    @(posedge sck);
                    #1;

                    if (cs_n !== 1'b0 ||
                        sd_oe !== 4'b1111)
                        $fatal(1, "RAM: directie incorecta la adresa");

                    address = {address[19:0], sd_out};
                end

                if (address >= MEMORY_BYTES)
                    $fatal(1, "RAM: adresa depaseste modelul: %h",
                           address);

                nibble_count = 0;

                if (command == 8'h38) begin
                    // Scriere fara cicluri dummy.
                    // CS stabileste daca transferul are 1 sau 4 octeti.
                    while (cs_n == 1'b0) begin
                        @(posedge sck or posedge cs_n);
                        #1;

                        if (cs_n == 1'b0) begin
                            if (sd_oe !== 4'b1111)
                                $fatal(1, "RAM: liniile nu sunt iesiri");

                            byte_value = {
                                byte_value[3:0], sd_out
                            };

                            nibble_count = nibble_count + 1;

                            if ((nibble_count % 2) == 0) begin
                                if (address >= MEMORY_BYTES)
                                    $fatal(1, "RAM: scriere in afara modelului");

                                memory[address] = byte_value;
                                address = address + 24'd1;
                            end
                        end
                    end

                    if (nibble_count != 2 &&
                        nibble_count != 8)
                        $fatal(1, "RAM: lungime incorecta la scriere");
                end
                else begin
                    // Citirea EB are sase cicluri dummy.
                    repeat (6) begin
                        @(posedge sck);
                        #1;

                        if (cs_n !== 1'b0 ||
                            sd_oe !== 4'b0000)
                            $fatal(1, "RAM: cicluri dummy incorecte");
                    end

                    while (cs_n == 1'b0) begin
                        @(negedge sck);
                        #1;

                        if (cs_n == 1'b0) begin
                            if (sd_oe !== 4'b0000)
                                $fatal(1, "RAM: liniile nu sunt intrari");

                            if (address >= MEMORY_BYTES)
                                $fatal(1, "RAM: citire in afara modelului");

                            if ((nibble_count % 2) == 0)
                                sd_in = memory[address][7:4];
                            else
                                sd_in = memory[address][3:0];

                            @(posedge sck);
                            #1;

                            if (cs_n !== 1'b0)
                                $fatal(1, "RAM: citire intrerupta");

                            nibble_count = nibble_count + 1;

                            if ((nibble_count % 2) == 0)
                                address = address + 24'd1;
                        end
                    end

                    if (nibble_count != 2 &&
                        nibble_count != 8)
                        $fatal(1, "RAM: lungime incorecta la citire");

                    sd_in = 4'd0;
                end

                if (sd_oe !== 4'b0000)
                    $fatal(1, "RAM: liniile nu sunt eliberate");

                transaction_count = transaction_count + 1;
            end
        end
    end

endmodule


module tb_qspi_ram_simple;

    logic clk;
    logic rst_n;

    logic sck;
    logic rise_en;
    logic fall_en;
    logic qspi_enable;

    logic ram_req;
    logic ram_write;
    logic ram_byte;
    logic [22:0] ram_addr;
    logic [31:0] ram_wdata;

    logic [31:0] ram_rdata;
    logic ram_ready;

    logic ram_cs_n;
    logic [3:0] ram_sd_in;
    logic [3:0] ram_sd_out;
    logic [3:0] ram_sd_oe;

    logic init_done;
    logic model_initialized;

    qspi_clock clock_generator(
        .clk(clk),
        .rst_n(rst_n),
        .enable(qspi_enable),
        .sck(sck),
        .rise_en(rise_en),
        .fall_en(fall_en)
    );

    qspi_ram_controller dut(
        .clk(clk),
        .rst_n(rst_n),

        .rise_en(rise_en),
        .fall_en(fall_en),
        .qspi_enable(qspi_enable),

        .ram_req(ram_req),
        .ram_write(ram_write),
        .ram_byte(ram_byte),
        .ram_addr(ram_addr),
        .ram_wdata(ram_wdata),

        .ram_rdata(ram_rdata),
        .ram_ready(ram_ready),

        .ram_cs_n(ram_cs_n),
        .ram_sd_in(ram_sd_in),
        .ram_sd_out(ram_sd_out),
        .ram_sd_oe(ram_sd_oe),

        .init_done(init_done)
    );

    ram_model_simple memory_model(
        .sck(sck),
        .cs_n(ram_cs_n),
        .sd_out(ram_sd_out),
        .sd_oe(ram_sd_oe),
        .sd_in(ram_sd_in),
        .initialized(model_initialized)
    );

    always #19.841 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;

        ram_req = 1'b0;
        ram_write = 1'b0;
        ram_byte = 1'b0;
        ram_addr = 23'd0;
        ram_wdata = 32'd0;

        repeat (3) @(negedge clk);

        if (sck !== 1'b0 ||
            ram_cs_n !== 1'b1 ||
            ram_sd_oe !== 4'b0000 ||
            ram_ready !== 1'b0 ||
            init_done !== 1'b0)
            $fatal(1, "Reset incorect");

        $display("[OK] Reset");

        rst_n = 1'b1;

        // Aproximativ 198 us: SCK trebuie sa ramana oprit.
        repeat (5000) begin
            @(negedge clk);

            if (sck !== 1'b0 ||
                qspi_enable !== 1'b0 ||
                ram_cs_n !== 1'b1 ||
                ram_sd_out !== 4'b0000 ||
                ram_sd_oe !== 4'b1111 ||
                init_done !== 1'b0)
                $fatal(1, "Conditii incorecte la pornirea RAM");
        end

        $display("[OK] Asteptare initiala cu SCK si date la zero");

        wait (init_done == 1'b1);
        @(negedge clk);

        if (model_initialized !== 1'b1)
            $fatal(1, "Secventa 66, 99 nu s-a terminat");

        $display("[OK] Initializare RAM: 66, 99");

        // Scriere octet. Numai A5 trebuie transmis.
        ram_addr = 23'h000123;
        ram_wdata = 32'hDEADBEA5;
        ram_byte = 1'b1;
        ram_write = 1'b1;
        ram_req = 1'b1;

        wait (ram_ready == 1'b1);

        repeat (3) begin
            @(negedge clk);

            if (ram_ready !== 1'b1 ||
                ram_cs_n !== 1'b1 ||
                ram_sd_oe !== 4'b0000)
                $fatal(1, "Raspunsul de scriere nu este pastrat");
        end

        if (memory_model.memory[16'h0123] !== 8'hA5 ||
            memory_model.memory[16'h0124] !== 8'h00)
            $fatal(1, "Scrierea unui octet este incorecta");

        ram_req = 1'b0;
        repeat (3) @(negedge clk);

        if (ram_ready !== 1'b0)
            $fatal(1, "Ready nu s-a eliberat");

        $display("[OK] Scriere octet");

        // Citire octet, cu extensie cu zero.
        ram_write = 1'b0;
        ram_req = 1'b1;

        wait (ram_ready == 1'b1);

        repeat (3) begin
            @(negedge clk);

            if (ram_ready !== 1'b1 ||
                ram_rdata !== 32'h000000A5)
                $fatal(1, "Citire octet incorecta: %h", ram_rdata);
        end

        ram_req = 1'b0;
        repeat (3) @(negedge clk);

        $display("[OK] Citire octet si extensie cu zero");

        // Scriere cuvant.
        ram_addr = 23'h012C00;
        ram_wdata = 32'h12345678;
        ram_byte = 1'b0;
        ram_write = 1'b1;
        ram_req = 1'b1;

        wait (ram_ready == 1'b1);
        @(negedge clk);

        if (memory_model.memory[17'h12C00] !== 8'h78 ||
            memory_model.memory[17'h12C01] !== 8'h56 ||
            memory_model.memory[17'h12C02] !== 8'h34 ||
            memory_model.memory[17'h12C03] !== 8'h12 ||
            memory_model.memory[17'h12C04] !== 8'h00)
            $fatal(1, "Ordine incorecta a octetilor scrisi");

        ram_req = 1'b0;
        repeat (3) @(negedge clk);

        $display("[OK] Scriere cuvant little-endian");

        // Citire cuvant.
        ram_write = 1'b0;
        ram_req = 1'b1;

        wait (ram_ready == 1'b1);

        repeat (3) begin
            @(negedge clk);

            if (ram_ready !== 1'b1 ||
                ram_rdata !== 32'h12345678 ||
                ram_cs_n !== 1'b1 ||
                ram_sd_oe !== 4'b0000)
                $fatal(1, "Citire cuvant incorecta: %h", ram_rdata);
        end

        ram_req = 1'b0;
        repeat (3) @(negedge clk);

        if (ram_ready !== 1'b0)
            $fatal(1, "Ready a ramas activ");

        if (memory_model.transaction_count != 4)
            $fatal(1, "Numar incorect de tranzactii RAM");

        $display("[OK] Citire cuvant little-endian");
        $display("[OK] Pastrarea si eliberarea raspunsului");

        rst_n = 1'b0;
        repeat (3) @(negedge clk);

        if (sck !== 1'b0 ||
            ram_cs_n !== 1'b1 ||
            ram_sd_oe !== 4'b0000 ||
            init_done !== 1'b0 ||
            ram_ready !== 1'b0)
            $fatal(1, "Reset final incorect");

        $display("[OK] Reset final");
        $display("PASS tb_qspi_ram_simple");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "TIMEOUT tb_qspi_ram_simple");
    end

endmodule