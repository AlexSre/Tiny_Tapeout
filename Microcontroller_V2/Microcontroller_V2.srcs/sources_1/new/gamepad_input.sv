// Gamepad Pmod protocol: ui[4]=latch, ui[5]=clock, ui[6]=data.
// Bits are ACTIVE HIGH, MSB first: B,Y,Select,Start,Up,Down,Left,Right,A,X,L,R.
// Rising serial clock shifts data; rising latch publishes the completed frame.
// Reference: github.com/urish/tt10-gamepad-pmod-demo/src/gamepad_pmod.v
module gamepad_input #(
    parameter integer TIMEOUT_CYCLES = 12500000
)(
    input logic clk, rst_n,
    input logic pmod_latch, pmod_clk, pmod_data,
    output logic [7:0] buttons
);
    (* ASYNC_REG = "TRUE" *) logic [2:0] sync1, sync2;
    logic old_clk, old_latch;
    logic [11:0] shift_data;
    logic [3:0] count;
    logic [23:0] age;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sync1 <= 0;
            sync2 <= 0;
            old_clk <= 0;
            old_latch <= 0;
            shift_data <= 12'hfff;
            count <= 0;
            age <= 0;
            buttons <= 0;
        end else begin
            sync1 <= {pmod_latch,pmod_clk,pmod_data};
            sync2 <= sync1;
            old_clk <= sync2[1];
            old_latch <= sync2[2];
            if (age < TIMEOUT_CYCLES) age <= age + 1'b1;
            else buttons <= 0;
            if (sync2[1] && !old_clk) begin
                shift_data <= {shift_data[10:0],sync2[0]};
                if (count < 12) count <= count + 1'b1;
            end
            if (sync2[2] && !old_latch) begin
                count <= 0;
                if (count == 12) begin
                    age <= 0;
                    if (shift_data == 12'hfff) buttons <= 0;
                    else buttons <= {1'b1,shift_data[9],shift_data[8],
                        (shift_data[11] | shift_data[3]),shift_data[6],
                        shift_data[7],shift_data[4],shift_data[5]};
                end
            end
        end
    end
endmodule
