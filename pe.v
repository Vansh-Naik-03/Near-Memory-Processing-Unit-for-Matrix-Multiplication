// Processing Element (PE): one multiply-accumulate unit.
// Every enabled clock:  acc = acc + (a * b)
`timescale 1ns / 1ps

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24
)(
    input  wire                         clk,
    input  wire                         rst_n,      // active-low reset
    input  wire                         clear,      // set accumulator to 0
    input  wire                         enable,     // do one multiply-accumulate
    input  wire signed [DATA_WIDTH-1:0] a_in,
    input  wire signed [DATA_WIDTH-1:0] b_in,
    output reg  signed [DATA_WIDTH-1:0] reg_a_out,  // saved copy of a (for viewing)
    output reg  signed [DATA_WIDTH-1:0] reg_b_out,  // saved copy of b (for viewing)
    output reg  signed [ACC_WIDTH-1:0]  acc_out     // running sum
);

    // multiply (16 bits is enough for 8bit x 8bit)
    wire signed [2*DATA_WIDTH-1:0] product = a_in * b_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_a_out <= 0;
            reg_b_out <= 0;
            acc_out   <= 0;
        end
        else if (clear) begin
            reg_a_out <= 0;
            reg_b_out <= 0;
            acc_out   <= 0;
        end
        else if (enable) begin
            reg_a_out <= a_in;
            reg_b_out <= b_in;
            acc_out   <= acc_out + product;  // signed, so it extends automatically
        end
        // if none of the above: keep old values
    end

endmodule
