// =============================================================================
// File: pe_array.v
// Module: pe_array
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Array of N Processing Elements (PEs) operating in parallel.
//   Receives packed vectors of operands A and B directly from Near-Memory SRAMs.
//   Provides:
//     1. Individual accumulated outputs from each PE
//     2. Integrated Accumulator Tree sum output for single-cycle vector dot products
// =============================================================================

`timescale 1ns / 1ps

module pe_array #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              clear,           // Synchronously clear PE accumulators
    input  wire                              enable,          // Enable MAC computation in PEs
    input  wire signed [N*DATA_WIDTH-1:0]    a_vec_in,        // Row vector A: A[i, 0..N-1]
    input  wire signed [N*DATA_WIDTH-1:0]    b_vec_in,        // Column vector B: B[0..N-1, j]
    output wire signed [N*ACC_WIDTH-1:0]     pe_acc_packed,   // Packed individual PE accumulator values
    output wire signed [ACC_WIDTH-1:0]       tree_sum_out     // Combined sum from the accumulator tree
);

    // Generate N Processing Elements
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : gen_pe_units
            wire signed [DATA_WIDTH-1:0] a_elem = a_vec_in[g*DATA_WIDTH +: DATA_WIDTH];
            wire signed [DATA_WIDTH-1:0] b_elem = b_vec_in[g*DATA_WIDTH +: DATA_WIDTH];
            wire signed [ACC_WIDTH-1:0]  pe_res;

            pe #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH (ACC_WIDTH)
            ) u_pe (
                .clk      (clk),
                .rst_n    (rst_n),
                .clear    (clear),
                .enable   (enable),
                .a_in     (a_elem),
                .b_in     (b_elem),
                .reg_a_out(),
                .reg_b_out(),
                .acc_out  (pe_res)
            );

            assign pe_acc_packed[g*ACC_WIDTH +: ACC_WIDTH] = pe_res;
        end
    endgenerate

    // Integrated Accumulator Tree to merge results
    accumulator_tree #(
        .N        (N),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_acc_tree (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .clear     (clear),
        .pe_results(pe_acc_packed),
        .sum_out   (tree_sum_out)
    );

endmodule
