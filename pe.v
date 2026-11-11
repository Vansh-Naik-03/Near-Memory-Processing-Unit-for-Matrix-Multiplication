// =============================================================================
// File: pe.v
// Module: pe
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Single Processing Element (PE) containing:
//     - Input registers Reg A and Reg B
//     - Signed multiplier (DATA_WIDTH x DATA_WIDTH -> 2*DATA_WIDTH)
//     - Adder with sign-extended product
//     - Local Accumulator / Sum Register with feedback loop
//
// Conforms to ASIC standard cell library conventions (active-low rst_n).
// =============================================================================

`timescale 1ns / 1ps

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24
)(
    input  wire                          clk,
    input  wire                          rst_n,      // Active-low asynchronous reset
    input  wire                          clear,      // Synchronous clear for accumulator
    input  wire                          enable,     // Enable MAC operation
    input  wire signed [DATA_WIDTH-1:0]  a_in,       // Operand A input
    input  wire signed [DATA_WIDTH-1:0]  b_in,       // Operand B input
    output reg  signed [DATA_WIDTH-1:0]  reg_a_out,  // Registered A operand (inspectable)
    output reg  signed [DATA_WIDTH-1:0]  reg_b_out,  // Registered B operand (inspectable)
    output reg  signed [ACC_WIDTH-1:0]   acc_out     // Accumulated running sum
);

    // Multiplier product (full precision signed)
    wire signed [2*DATA_WIDTH-1:0] product;
    assign product = a_in * b_in;

    // Sign-extended product to match accumulator bit-width
    wire signed [ACC_WIDTH-1:0] product_ext;
    assign product_ext = {{(ACC_WIDTH - 2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};

    // Sequential Accumulator Logic with input registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_a_out <= {DATA_WIDTH{1'b0}};
            reg_b_out <= {DATA_WIDTH{1'b0}};
            acc_out   <= {ACC_WIDTH{1'b0}};
        end else begin
            if (clear) begin
                acc_out   <= {ACC_WIDTH{1'b0}};
                reg_a_out <= {DATA_WIDTH{1'b0}};
                reg_b_out <= {DATA_WIDTH{1'b0}};
            end else if (enable) begin
                reg_a_out <= a_in;
                reg_b_out <= b_in;
                acc_out   <= acc_out + product_ext;
            end
            // else: hold current values with no latch synthesis
        end
    end

endmodule
