// =============================================================================
// File: accumulator_tree.v
// Module: accumulator_tree
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Accumulator / Adder Tree that merges partial results from the PE array.
//   Hierarchical balanced binary tree for minimal propagation delay.
//   Includes synchronous enable/clear and registered output stage for timing closure.
// =============================================================================

`timescale 1ns / 1ps

module accumulator_tree #(
    parameter N         = 4,
    parameter ACC_WIDTH = 24
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              enable,      // Latch/update tree sum
    input  wire                              clear,       // Clear registered sum
    input  wire signed [N*ACC_WIDTH-1:0]     pe_results,  // Packed results from N PEs
    output reg  signed [ACC_WIDTH-1:0]       sum_out      // Merged tree sum
);

    // Unpack inputs into array for clean indexing
    wire signed [ACC_WIDTH-1:0] in_val [0:N-1];
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : gen_unpack
            assign in_val[g] = pe_results[g*ACC_WIDTH +: ACC_WIDTH];
        end
    endgenerate

    // Combinational Adder Tree calculation (parameterized for N=4, easily expandable)
    reg signed [ACC_WIDTH-1:0] comb_sum;

    generate
        if (N == 4) begin : gen_tree_4
            wire signed [ACC_WIDTH-1:0] sum_level1_0 = in_val[0] + in_val[1];
            wire signed [ACC_WIDTH-1:0] sum_level1_1 = in_val[2] + in_val[3];
            always @(*) begin
                comb_sum = sum_level1_0 + sum_level1_1;
            end
        end else if (N == 2) begin : gen_tree_2
            always @(*) begin
                comb_sum = in_val[0] + in_val[1];
            end
        end else if (N == 1) begin : gen_tree_1
            always @(*) begin
                comb_sum = in_val[0];
            end
        end else begin : gen_tree_gen
            // Generic iterative fallback for arbitrary N
            integer k;
            always @(*) begin
                comb_sum = 0;
                for (k = 0; k < N; k = k + 1) begin
                    comb_sum = comb_sum + in_val[k];
                end
            end
        end
    endgenerate

    // Registered output for clean timing and glitch suppression
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_out <= {ACC_WIDTH{1'b0}};
        end else begin
            if (clear) begin
                sum_out <= {ACC_WIDTH{1'b0}};
            end else if (enable) begin
                sum_out <= comb_sum;
            end
        end
    end

endmodule
