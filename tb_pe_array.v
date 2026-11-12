// Testbench for pe_array: 4-element dot product.
// Timing: clock 1 = PEs multiply-accumulate, clock 2 = tree adds the PE results.
`timescale 1ns / 1ps

module tb_pe_array;

    reg                clk = 0;
    reg                rst_n, clear, enable;
    reg  signed [31:0] a_vec_in, b_vec_in;      // 4 x 8 bits
    wire signed [95:0] pe_acc_packed;           // 4 x 24 bits
    wire signed [23:0] tree_sum_out;

    integer errors = 0;

    pe_array #(.N(4), .DATA_WIDTH(8), .ACC_WIDTH(24)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .enable(enable),
        .a_vec_in(a_vec_in), .b_vec_in(b_vec_in),
        .pe_acc_packed(pe_acc_packed), .tree_sum_out(tree_sum_out)
    );

    always #5 clk = ~clk;

    // run one dot product: load vectors, enable for 1 clock, wait 1 more clock for the tree
    task dot(input signed [7:0] a0, a1, a2, a3, b0, b1, b2, b3,
             input signed [23:0] expected, input [255:0] name);
        begin
            a_vec_in = {a3, a2, a1, a0};
            b_vec_in = {b3, b2, b1, b0};
            enable = 1; @(negedge clk);   // PEs accumulate
            enable = 0; @(negedge clk);   // tree adds
            if (tree_sum_out !== expected) begin
                $display("FAIL %0s: got %0d expected %0d", name, tree_sum_out, expected);
                errors = errors + 1;
            end else
                $display("pass %0s: dot product = %0d", name, tree_sum_out);
        end
    endtask

    initial begin
        rst_n = 0; clear = 0; enable = 0; a_vec_in = 0; b_vec_in = 0;
        #12 rst_n = 1;
        @(negedge clk);

        // Test 1: [1 2 3 4] . [5 6 7 8] = 5+12+21+32 = 70
        dot(1, 2, 3, 4,  5, 6, 7, 8,  70, "positive");

        // Test 2: clear everything
        clear = 1; @(negedge clk); clear = 0;
        if (tree_sum_out !== 0) begin
            $display("FAIL clear: got %0d", tree_sum_out);
            errors = errors + 1;
        end else
            $display("pass clear");

        // Test 3: [-2 3 -4 5] . [6 -7 8 -9] = -12-21-32-45 = -110
        dot(-2, 3, -4, 5,  6, -7, 8, -9,  -110, "signed");

        if (errors == 0) $display("PE_ARRAY: ALL TESTS PASSED");
        else             $display("PE_ARRAY: %0d ERRORS", errors);
        $finish;
    end

endmodule
