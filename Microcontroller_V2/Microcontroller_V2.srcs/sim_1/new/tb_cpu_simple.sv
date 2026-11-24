`timescale 1ns / 1ps

module tb_cpu_simple;

    logic clk;
    logic rst_n;

    // Interfata pentru instructiuni.
    logic instr_req;
    logic [16:0] instr_addr;
    logic [25:0] instr_rdata;
    logic instr_ready;

    // Interfata pentru date.
    logic data_req;
    logic data_write;
    logic [16:0] data_addr;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;
    logic data_ready;

    // Memorie simplificata pentru testul STORE / LOAD.
    logic [31:0] memory_value;

    localparam OP_ADD   = 4'h0;
    localparam OP_SUB   = 4'h1;
    localparam OP_AND   = 4'h2;
    localparam OP_OR    = 4'h3;
    localparam OP_XOR   = 4'h4;
    localparam OP_MUL   = 4'h5;
    localparam OP_LOADC = 4'h6;
    localparam OP_LOAD  = 4'h7;
    localparam OP_STORE = 4'h8;
    localparam OP_JUMP  = 4'h9;
    localparam OP_JZ    = 4'hA;
    localparam OP_NOP   = 4'hF;

    cpu_core uut(
        .clk(clk),
        .rst_n(rst_n),

        .instr_req(instr_req),
        .instr_addr(instr_addr),
        .instr_rdata(instr_rdata),
        .instr_ready(instr_ready),

        .data_req(data_req),
        .data_write(data_write),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_rdata(data_rdata),
        .data_ready(data_ready)
    );

    // Clock de aproximativ 25.2 MHz.
    always #19.841 clk = ~clk;

    // In acest test, memoria de instructiuni raspunde imediat.
    assign instr_ready = rst_n && instr_req;

    // Programul de test.
    always_comb
    begin
        case (instr_addr)

            // R1 = 10; R2 = 5.
            17'd0:
                instr_rdata = {OP_LOADC, 5'd1, 17'd10};

            17'd1:
                instr_rdata = {OP_LOADC, 5'd2, 17'd5};

            // R3 = 10 + 5 = 15.
            17'd2:
                instr_rdata = {OP_ADD, 5'd3, 5'd1, 5'd2, 7'd0};

            // R4 = 10 - 5 = 5.
            17'd3:
                instr_rdata = {OP_SUB, 5'd4, 5'd1, 5'd2, 7'd0};

            // R5 = 10 & 5 = 0.
            17'd4:
                instr_rdata = {OP_AND, 5'd5, 5'd1, 5'd2, 7'd0};

            // R6 = 10 | 5 = 15.
            17'd5:
                instr_rdata = {OP_OR, 5'd6, 5'd1, 5'd2, 7'd0};

            // R7 = 10 ^ 5 = 15.
            17'd6:
                instr_rdata = {OP_XOR, 5'd7, 5'd1, 5'd2, 7'd0};

            // R8 = 10 * 5 = 50.
            17'd7:
                instr_rdata = {OP_MUL, 5'd8, 5'd1, 5'd2, 7'd0};

            // R9 = 10 - 10 = 0.
            17'd8:
                instr_rdata = {OP_SUB, 5'd9, 5'd1, 5'd1, 7'd0};

            // Adresa pentru testul de memorie.
            17'd9:
                instr_rdata = {OP_LOADC, 5'd0, 17'd100};

            // MEM[R0] = R8.
            17'd10:
                instr_rdata = {OP_STORE, 5'd8, 5'd0, 12'd0};

            // R10 = MEM[R0].
            17'd11:
                instr_rdata = {OP_LOAD, 5'd10, 5'd0, 12'd0};

            // R9 este zero: trebuie sa sara la 15.
            17'd12:
                instr_rdata = {OP_JZ, 5'd9, 17'd15};

            // R1 nu este zero: trebuie sa continue la 16.
            17'd15:
                instr_rdata = {OP_JZ, 5'd1, 17'd19};

            17'd16:
                instr_rdata = {OP_LOADC, 5'd11, 17'd123};

            // Salt neconditionat la 20.
            17'd17:
                instr_rdata = {OP_JUMP, 5'd0, 17'd20};

            17'd20:
                instr_rdata = {OP_NOP, 5'd0, 17'd0};

            // Opcode neimplementat: CPU intra in STOPPED.
            default:
                instr_rdata = {4'hB, 22'd0};

        endcase
    end

    initial
    begin
        clk = 1'b0;
        rst_n = 1'b0;

        data_rdata = 32'd0;
        data_ready = 1'b0;
        memory_value = 32'd0;

        $display("--- Start test CPU ---");

        // Resetul ramane activ pentru mai multe fronturi de clock.
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // La PC=9, toate operatiile ALU de mai sus s-au terminat.
        wait (instr_addr == 17'd9);
        @(negedge clk);

        if (uut.regs[1] !== 32'd10 ||
            uut.regs[2] !== 32'd5)
            $fatal(1, "[ERR] LOADC incorect");

        $display("[OK] LOADC: R1=10, R2=5");

        if (uut.regs[3] !== 32'd15)
            $fatal(1, "[ERR] ADD: R3=%0d", uut.regs[3]);

        $display("[OK] ADD: R3=15");

        if (uut.regs[4] !== 32'd5)
            $fatal(1, "[ERR] SUB: R4=%0d", uut.regs[4]);

        $display("[OK] SUB: R4=5");

        if (uut.regs[5] !== 32'd0)
            $fatal(1, "[ERR] AND: R5=%0d", uut.regs[5]);

        $display("[OK] AND: R5=0");

        if (uut.regs[6] !== 32'd15)
            $fatal(1, "[ERR] OR: R6=%0d", uut.regs[6]);

        $display("[OK] OR: R6=15");

        if (uut.regs[7] !== 32'd15)
            $fatal(1, "[ERR] XOR: R7=%0d", uut.regs[7]);

        $display("[OK] XOR: R7=15");

        if (uut.regs[8] !== 32'd50)
            $fatal(1, "[ERR] MUL: R8=%0d", uut.regs[8]);

        $display("[OK] MUL: R8=50");

        if (uut.regs[9] !== 32'd0)
            $fatal(1, "[ERR] SUB cu rezultat zero");

        // TEST STORE.
        wait (data_req == 1'b1);

        // Memoria intarzie raspunsul cu trei cicluri.
        repeat (3)
        begin
            @(negedge clk);

            if (data_req !== 1'b1 ||
                data_write !== 1'b1 ||
                data_addr !== 17'd100 ||
                data_wdata !== 32'd50)
                $fatal(1, "[ERR] Semnale STORE incorecte");

            if (instr_addr !== 17'd10)
                $fatal(1, "[ERR] CPU a avansat inainte de confirmarea STORE");
        end

        // Simulam scrierea in memorie.
        memory_value = data_wdata;
        data_ready = 1'b1;

        @(negedge clk);
        data_ready = 1'b0;

        $display("[OK] STORE: MEM[100]=%0d", memory_value);

        // TEST LOAD.
        wait (data_req == 1'b1);

        repeat (3)
        begin
            @(negedge clk);

            if (data_req !== 1'b1 ||
                data_write !== 1'b0 ||
                data_addr !== 17'd100)
                $fatal(1, "[ERR] Semnale LOAD incorecte");

            if (instr_addr !== 17'd11)
                $fatal(1, "[ERR] CPU a avansat inainte de confirmarea LOAD");
        end

        // Simulam raspunsul memoriei.
        data_rdata = memory_value;
        data_ready = 1'b1;

        @(negedge clk);
        data_ready = 1'b0;

        wait (instr_addr != 17'd11);
        @(negedge clk);
        if (uut.regs[10] !== 32'd50)
            $fatal(1, "[ERR] LOAD: R10=%0d", uut.regs[10]);

        $display("[OK] LOAD: R10=50");

        // TEST JZ: registru zero.
        wait (instr_addr == 17'd12);
        wait (instr_addr != 17'd12);
        @(negedge clk);

        if (instr_addr !== 17'd15)
            $fatal(1, "[ERR] JZ trebuia sa sara la 15");

        $display("[OK] JZ executa saltul pentru R9=0");

        // TEST JZ: registru diferit de zero.
        wait (instr_addr != 17'd15);
        @(negedge clk);

        if (instr_addr !== 17'd16)
            $fatal(1, "[ERR] JZ trebuia sa continue la 16");

        $display("[OK] JZ nu executa saltul pentru R1=10");

        // TEST JUMP.
        wait (instr_addr == 17'd17);
        wait (instr_addr != 17'd17);
        @(negedge clk);

        if (instr_addr !== 17'd20 ||
            uut.regs[11] !== 32'd123)
            $fatal(1, "[ERR] JUMP sau instructiunea precedenta incorecta");

        $display("[OK] JUMP: PC=20");

        // TEST NOP si oprire la opcode invalid.
        wait (instr_addr == 17'd21);
        repeat (4) @(negedge clk);

        if (instr_addr !== 17'd21 ||
            instr_req !== 1'b0 ||
            data_req !== 1'b0)
            $fatal(1, "[ERR] NOP sau STOPPED incorect");

        $display("[OK] NOP si oprire la opcode invalid");
        $display("PASS tb_cpu_simple");

        $finish;
    end

    // Oprim simularea daca procesorul ramane blocat.
    initial
    begin
        #100000;
        $fatal(1, "[ERR] Timeout: testul nu s-a terminat");
    end

endmodule