module top(

    input  logic [7:0] ui_in,
    output logic [7:0] uo_out,

    input  logic [7:0] uio_in,
    output logic [7:0] uio_out,
    output logic [7:0] uio_oe,

    input logic ena,
    input logic clk,
    input logic rst_n

);

    logic system_rst_n;
    assign system_rst_n = rst_n && ena;

    logic instr_req;
    logic [16:0] instr_addr;
    logic [25:0] instr_rdata;
    logic instr_ready;

    logic data_req;
    logic data_write;
    logic [16:0] data_addr;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;
    logic data_ready;

    logic flash_req;
    logic [23:0] flash_addr;
    logic [31:0] flash_rdata;
    logic flash_ready;

    logic flash_init_done;
    logic flash_init_error;

    logic flash_cs_n;
    logic [3:0] flash_sd_out;
    logic [3:0] flash_sd_oe;

    logic cpu_ram_req;
    logic cpu_ram_write;
    logic cpu_ram_byte;
    logic [22:0] cpu_ram_addr;
    logic [31:0] cpu_ram_wdata;
    logic [31:0] cpu_ram_rdata;
    logic cpu_ram_ready;

    logic video_req;
    logic [22:0] video_addr;
    logic [31:0] video_rdata;
    logic video_ready;

    logic ram_req;
    logic ram_write;
    logic ram_byte;
    logic [22:0] ram_addr;
    logic [31:0] ram_wdata;
    logic [31:0] ram_rdata;
    logic ram_ready;

    logic ram_init_done;

    logic ram_cs_n;
    logic [3:0] ram_sd_out;
    logic [3:0] ram_sd_oe;

    logic qspi_enable;
    logic qspi_sck;
    logic rise_en;
    logic fall_en;

    logic [7:0] buttons;
    logic [31:0] score;

    logic hsync;
    logic vsync;
    logic video_on;
    logic [9:0] x;
    logic [9:0] y;

    logic [7:0] pixel_data;
    logic pixel_valid;

    logic red;
    logic green;
    logic blue;

    logic _unused;

    cpu_core u_cpu(
        .clk(clk),
        .rst_n(system_rst_n),

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

    assign flash_req   = instr_req;
    assign flash_addr  = {5'd0, instr_addr, 2'b00};
    assign instr_rdata = flash_rdata[25:0];
    assign instr_ready = flash_ready;

    qspi_clock u_qspi_clock(
        .clk(clk),
        .rst_n(system_rst_n),
        .enable(qspi_enable),

        .sck(qspi_sck),
        .rise_en(rise_en),
        .fall_en(fall_en)
    );

    qspi_flash_controller u_flash(
        .clk(clk),
        .rst_n(system_rst_n),

        .rise_en(rise_en),
        .fall_en(fall_en),

        .flash_req(flash_req),
        .flash_addr(flash_addr),
        .flash_rdata(flash_rdata),
        .flash_ready(flash_ready),

        .flash_cs_n(flash_cs_n),
        .flash_sd_in(uio_in[3:0]),
        .flash_sd_out(flash_sd_out),
        .flash_sd_oe(flash_sd_oe),

        .init_done(flash_init_done),
        .init_error(flash_init_error)
    );

    input_sync u_input_sync(
        .clk(clk),
        .rst_n(system_rst_n),

        .buttons_in(ui_in),
        .buttons_sync(buttons)
    );

    memory_map u_memory_map(
        .clk(clk),
        .rst_n(system_rst_n),

        .data_req(data_req),
        .data_write(data_write),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_rdata(data_rdata),
        .data_ready(data_ready),

        .buttons(buttons),
        .vsync(vsync),
        .random_value(32'd0),
        .score(score),

        .cpu_req(cpu_ram_req),
        .cpu_write(cpu_ram_write),
        .cpu_byte(cpu_ram_byte),
        .cpu_addr(cpu_ram_addr),
        .cpu_wdata(cpu_ram_wdata),
        .cpu_rdata(cpu_ram_rdata),
        .cpu_ready(cpu_ram_ready)
    );

    ram_arbiter u_ram_arbiter(
        .clk(clk),
        .rst_n(system_rst_n),

        .ram_init_done(ram_init_done),

        .cpu_req(cpu_ram_req),
        .cpu_write(cpu_ram_write),
        .cpu_byte(cpu_ram_byte),
        .cpu_addr(cpu_ram_addr),
        .cpu_wdata(cpu_ram_wdata),
        .cpu_rdata(cpu_ram_rdata),
        .cpu_ready(cpu_ram_ready),

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

    qspi_ram_controller u_ram(
        .clk(clk),
        .rst_n(system_rst_n),

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
        .ram_sd_in(uio_in[7:4]),
        .ram_sd_out(ram_sd_out),
        .ram_sd_oe(ram_sd_oe),

        .init_done(ram_init_done)
    );

    vga_timing u_vga_timing(
        .clk(clk),
        .rst_n(system_rst_n),

        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),
        .x(x),
        .y(y)
    );

    video_line_buffer u_video_line_buffer(
        .clk(clk),
        .rst_n(system_rst_n),

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

    assign red   = video_on && pixel_valid && pixel_data[2];
    assign green = video_on && pixel_valid && pixel_data[1];
    assign blue  = video_on && pixel_valid && pixel_data[0];

    assign uo_out[0] = red;
    assign uo_out[1] = green;
    assign uo_out[2] = blue;
    assign uo_out[3] = vsync;

    assign uo_out[4] = system_rst_n ? qspi_sck : 1'b0;
    assign uo_out[5] = flash_cs_n;
    assign uo_out[6] = ram_cs_n;

    assign uo_out[7] = hsync;

    assign uio_out[3:0] = flash_sd_out;
    assign uio_oe[3:0]  = flash_sd_oe;

    assign uio_out[7:4] = ram_sd_out;
    assign uio_oe[7:4]  = ram_sd_oe;

    assign _unused = &{
        1'b0,
        flash_init_done,
        flash_init_error,
        score
    };

endmodule