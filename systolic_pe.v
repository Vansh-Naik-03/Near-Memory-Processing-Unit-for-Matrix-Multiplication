// =============================================================================
// File: systolic_pe.v
// Module: systolic_pe
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Output-Stationary 2D Systolic Array Processing Element (PE).
//   - Signed DATA_WIDTH-bit inputs (default 8-bit) with valid handshakes.
//   - Signed multiplication with full sign extension to ACC_WIDTH (default 24-bit).
//   - Accumulates (a_in * b_in) locally when (a_valid_in && b_valid_in).
//   - Forwards a_in / a_valid_in horizontally (left -> right) by 1 cycle.
//   - Forwards b_in / b_valid_in vertically (top -> bottom) by 1 cycle.
//   - Active-low asynchronous reset (rst_n) and synchronous clear (clear).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module systolic_pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24
)(
    input  wire                         clk,
    input  wire                         rst_n,        // active-low async reset
    input  wire                         clear,        // synchronous clear (acc & pipeline regs)
    input  wire signed [DATA_WIDTH-1:0] a_in,         // operand A from left neighbor
    input  wire signed [DATA_WIDTH-1:0] b_in,         // operand B from top neighbor
    input  wire                         a_valid_in,   // A operand valid
    input  wire                         b_valid_in,   // B operand valid
    output reg  signed [DATA_WIDTH-1:0] a_out,        // forwarded A to right neighbor
    output reg  signed [DATA_WIDTH-1:0] b_out,        // forwarded B to bottom neighbor
    output reg                          a_valid_out,  // forwarded A valid
    output reg                          b_valid_out,  // forwarded B valid
    output reg  signed [ACC_WIDTH-1:0]  acc_out       // local stationary partial sum
);

    // Signed 2*DATA_WIDTH product (16 bits for 8x8), sign-extended to ACC_WIDTH
    wire signed [2*DATA_WIDTH-1:0] product;
    wire signed [ACC_WIDTH-1:0]    product_ext;

    assign product = a_in * b_in;

    generate
        if (ACC_WIDTH > 2*DATA_WIDTH) begin : gen_sext
            assign product_ext = {{(ACC_WIDTH - 2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
        end else begin : gen_no_sext
            assign product_ext = product[ACC_WIDTH-1:0];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out       <= {DATA_WIDTH{1'b0}};
            b_out       <= {DATA_WIDTH{1'b0}};
            a_valid_out <= 1'b0;
            b_valid_out <= 1'b0;
            acc_out     <= {ACC_WIDTH{1'b0}};
        end else if (clear) begin
            a_out       <= {DATA_WIDTH{1'b0}};
            b_out       <= {DATA_WIDTH{1'b0}};
            a_valid_out <= 1'b0;
            b_valid_out <= 1'b0;
            acc_out     <= {ACC_WIDTH{1'b0}};
        end else begin
            // Systolic neighbour-to-neighbour forwarding (1-cycle pipeline register)
            a_out       <= a_in;
            b_out       <= b_in;
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;

            // Output-stationary MAC: accumulate only when both operands are valid
            if (a_valid_in && b_valid_in) begin
                acc_out <= acc_out + product_ext;
            end
        end
    end

endmodule

`default_nettype wire

