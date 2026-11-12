// Accumulator tree: adds the N PE results together (N = 4 here).
// Result is stored in a register, updated when enable=1.
`timescale 1ns / 1ps

module accumulator_tree #(
    parameter N         = 4,
    parameter ACC_WIDTH = 24
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          enable,
    input  wire                          clear,
    input  wire signed [N*ACC_WIDTH-1:0] pe_results,   // N values packed side by side
    output reg  signed [ACC_WIDTH-1:0]   sum_out
);

    // pull out each value from the packed bus
    wire signed [ACC_WIDTH-1:0] v0 = pe_results[0*ACC_WIDTH +: ACC_WIDTH];
    wire signed [ACC_WIDTH-1:0] v1 = pe_results[1*ACC_WIDTH +: ACC_WIDTH];
    wire signed [ACC_WIDTH-1:0] v2 = pe_results[2*ACC_WIDTH +: ACC_WIDTH];
    wire signed [ACC_WIDTH-1:0] v3 = pe_results[3*ACC_WIDTH +: ACC_WIDTH];

    // add them in a tree shape: (v0+v1) and (v2+v3) first, then together
    wire signed [ACC_WIDTH-1:0] s01 = v0 + v1;
    wire signed [ACC_WIDTH-1:0] s23 = v2 + v3;
    wire signed [ACC_WIDTH-1:0] total = s01 + s23;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sum_out <= 0;
        else if (clear)
            sum_out <= 0;
        else if (enable)
            sum_out <= total;
        // else: hold
    end

endmodule
