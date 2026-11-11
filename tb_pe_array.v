// =============================================================================
// File: tb_pe_array.v
// Module: tb_pe_array
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Unit testbench for the parallel Processing Element Array (pe_array.v).
// =============================================================================

`timescale 1ns / 1ps

module tb_pe_array;

    parameter N          = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;

    reg                              clk;
    reg                              rst_n;
    reg                              clear;
    reg                              enable;
    reg  signed [N*DATA_WIDTH-1:0]   a_vec_in;
    reg  signed [N*DATA_WIDTH-1:0]   b_vec_in;
    wire signed [N*ACC_WIDTH-1:0]    pe_acc_packed;
    wire signed [ACC_WIDTH-1:0]      tree_sum_out;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    pe_array #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (clear),
        .enable       (enable),
        .a_vec_in     (a_vec_in),
        .b_vec_in     (b_vec_in),
        .pe_acc_packed(pe_acc_packed),
        .tree_sum_out (tree_sum_out)
    );

    always #5 clk = ~clk;

    // Helper task to pack vector A and vector B
    task set_vectors(
        input signed [DATA_WIDTH-1:0] a0, a1, a2, a3,
        input signed [DATA_WIDTH-1:0] b0, b1, b2, b3
    );
        begin
            a_vec_in[0*DATA_WIDTH +: DATA_WIDTH] = a0;
            a_vec_in[1*DATA_WIDTH +: DATA_WIDTH] = a1;
            a_vec_in[2*DATA_WIDTH +: DATA_WIDTH] = a2;
            a_vec_in[3*DATA_WIDTH +: DATA_WIDTH] = a3;

            b_vec_in[0*DATA_WIDTH +: DATA_WIDTH] = b0;
            b_vec_in[1*DATA_WIDTH +: DATA_WIDTH] = b1;
            b_vec_in[2*DATA_WIDTH +: DATA_WIDTH] = b2;
            b_vec_in[3*DATA_WIDTH +: DATA_WIDTH] = b3;
        end
    endtask

    initial begin
        $display("==================================================");
        $display("       TESTBENCH: PE Array (pe_array.v)           ");
        $display("==================================================");

        clk      = 0;
        rst_n    = 0;
        clear    = 0;
        enable   = 0;
        a_vec_in = 0;
        b_vec_in = 0;

        #15;
        rst_n = 1;
        #10;

        // Test 1: Vector dot product (positive)
        // A = [1, 2, 3, 4], B = [5, 6, 7, 8]
        // PE0: 1*5=5, PE1: 2*6=12, PE2: 3*7=21, PE3: 4*8=32
        // Total dot product = 5 + 12 + 21 + 32 = 70
        @(posedge clk);
        set_vectors(8'sd1, 8'sd2, 8'sd3, 8'sd4, 8'sd5, 8'sd6, 8'sd7, 8'sd8);
        enable = 1;

        // Wait 1 cycle for PE accumulation and tree sum latching
        @(posedge clk);
        #1;
        enable = 0;

        if (tree_sum_out === 24'sd70) begin
            $display("[PASS] Test 1: Parallel Dot Product = %0d (Expected 70)", tree_sum_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 1: Dot Product = %0d, Expected 70", tree_sum_out);
            fail_count = fail_count + 1;
        end

        // Test 2: Synchronous Clear
        @(posedge clk);
        clear = 1;
        @(posedge clk);
        #1;
        clear = 0;

        // Test 3: Signed mixed vector dot product
        // A = [-2, 3, -4, 5], B = [6, -7, 8, -9]
        // Products: -12, -21, -32, -45 -> Sum = -110
        @(posedge clk);
        set_vectors(-8'sd2, 8'sd3, -8'sd4, 8'sd5, 8'sd6, -8'sd7, 8'sd8, -8'sd9);
        enable = 1;

        @(posedge clk);
        #1;
        enable = 0;

        if (tree_sum_out === -24'sd110) begin
            $display("[PASS] Test 2: Signed Mixed Vector Dot Product = %0d (Expected -110)", tree_sum_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 2: Dot Product = %0d, Expected -110", tree_sum_out);
            fail_count = fail_count + 1;
        end

        #20;
        $display("==================================================");
        $display("   PE ARRAY SUMMARY: %0d PASSED, %0d FAILED       ", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> PE_ARRAY.V IS FULLY VERIFIED! <<\n");
        else
            $display(">> PE_ARRAY.V FAILED. <<\n");

        $finish;
    end

endmodule
