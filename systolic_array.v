// =============================================================================
// File: systolic_array.v
// Module: systolic_array
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Parameterizable 2D Output-Stationary Systolic Array (default 4x4 = 16 PEs).
//   - Instantiates N x N systolic_pe units in a 2D grid via generate loops.
//   - Horizontal dataflow: Matrix A operands & valids forward left -> right.
//   - Vertical dataflow:   Matrix B operands & valids forward top -> bottom.
//   - Each PE(r, c) locally accumulates C[r][c] = sum_k A[r][k] * B[k][c].
//   - Exposes all N*N accumulated outputs in row-major packed vector c_out.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module systolic_array #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24
)(
    input  wire                        clk,
    input  wire                        rst_n,       // active-low async reset
    input  wire                        clear,       // synchronous clear for all PEs
    input  wire [N*DATA_WIDTH-1:0]     a_in,        // N packed signed A inputs (left edge)
    input  wire [N*DATA_WIDTH-1:0]     b_in,        // N packed signed B inputs (top edge)
    input  wire [N-1:0]                a_valid_in,  // row valid bits
    input  wire [N-1:0]                b_valid_in,  // column valid bits
    output wire [N*N*ACC_WIDTH-1:0]    c_out        // N*N packed signed C outputs (row-major)
);

    // Inter-PE horizontal wires: N rows, N+1 horizontal tap points (0=left input, N=right sink)
    wire signed [DATA_WIDTH-1:0] a_bus       [0:N-1][0:N];
    wire                         a_valid_bus [0:N-1][0:N];

    // Inter-PE vertical wires: N+1 vertical tap points (0=top input, N=bottom sink), N cols
    wire signed [DATA_WIDTH-1:0] b_bus       [0:N][0:N-1];
    wire                         b_valid_bus [0:N][0:N-1];

    genvar r, c;
    generate
        // Connect left boundary inputs for Matrix A (one per row)
        for (r = 0; r < N; r = r + 1) begin : gen_left_boundary
            assign a_bus[r][0]       = $signed(a_in[r*DATA_WIDTH +: DATA_WIDTH]);
            assign a_valid_bus[r][0] = a_valid_in[r];
        end

        // Connect top boundary inputs for Matrix B (one per column)
        for (c = 0; c < N; c = c + 1) begin : gen_top_boundary
            assign b_bus[0][c]       = $signed(b_in[c*DATA_WIDTH +: DATA_WIDTH]);
            assign b_valid_bus[0][c] = b_valid_in[c];
        end

        // Instantiate 2D grid of N x N processing elements
        for (r = 0; r < N; r = r + 1) begin : gen_row
            for (c = 0; c < N; c = c + 1) begin : gen_col
                systolic_pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) u_pe (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .clear      (clear),
                    .a_in       (a_bus[r][c]),
                    .b_in       (b_bus[r][c]),
                    .a_valid_in (a_valid_bus[r][c]),
                    .b_valid_in (b_valid_bus[r][c]),
                    .a_out      (a_bus[r][c+1]),
                    .b_out      (b_bus[r+1][c]),
                    .a_valid_out(a_valid_bus[r][c+1]),
                    .b_valid_out(b_valid_bus[r+1][c]),
                    .acc_out    (c_out[(r*N + c)*ACC_WIDTH +: ACC_WIDTH])
                );
            end
        end
    endgenerate

endmodule

`default_nettype wire

