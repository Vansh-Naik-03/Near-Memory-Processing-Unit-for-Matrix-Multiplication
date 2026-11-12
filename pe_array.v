// PE array: N PEs working side by side, plus the accumulator tree to add their results.
`timescale 1ns / 1ps

module pe_array #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           clear,
    input  wire                           enable,
    input  wire signed [N*DATA_WIDTH-1:0] a_vec_in,
    input  wire signed [N*DATA_WIDTH-1:0] b_vec_in,
    output wire signed [N*ACC_WIDTH-1:0]  pe_acc_packed,
    output wire signed [ACC_WIDTH-1:0]    tree_sum_out
);

    // make N copies of the PE
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : gen_pe
            pe #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pe (
                .clk      (clk),
                .rst_n    (rst_n),
                .clear    (clear),
                .enable   (enable),
                .a_in     (a_vec_in[g*DATA_WIDTH +: DATA_WIDTH]),
                .b_in     (b_vec_in[g*DATA_WIDTH +: DATA_WIDTH]),
                .reg_a_out(),
                .reg_b_out(),
                .acc_out  (pe_acc_packed[g*ACC_WIDTH +: ACC_WIDTH])
            );
        end
    endgenerate

    // PEs update on the edge where enable=1, so their sums are ready 1 clock later.
    // Delay enable by 1 clock for the tree.
    reg enable_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) enable_d <= 0;
        else        enable_d <= enable;
    end

    accumulator_tree #(.N(N), .ACC_WIDTH(ACC_WIDTH)) u_tree (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable_d),
        .clear     (clear),
        .pe_results(pe_acc_packed),
        .sum_out   (tree_sum_out)
    );

endmodule
