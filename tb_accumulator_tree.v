// =============================================================================
// File: tb_accumulator_tree.v
// Module: tb_accumulator_tree
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Unit testbench for the Accumulator Tree (accumulator_tree.v).
// =============================================================================

`timescale 1ns / 1ps

module tb_accumulator_tree;

    parameter N         = 4;
    parameter ACC_WIDTH = 24;

    reg                          clk;
    reg                          rst_n;
    reg                          enable;
    reg                          clear;
    reg  signed [N*ACC_WIDTH-1:0] pe_results;
    wire signed [ACC_WIDTH-1:0]   sum_out;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    accumulator_tree #(
        .N        (N),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .clear     (clear),
        .pe_results(pe_results),
        .sum_out   (sum_out)
    );

    always #5 clk = ~clk;

    // Helper task to assign inputs
    task pack_inputs(
        input signed [ACC_WIDTH-1:0] v0,
        input signed [ACC_WIDTH-1:0] v1,
        input signed [ACC_WIDTH-1:0] v2,
        input signed [ACC_WIDTH-1:0] v3
    );
        begin
            pe_results[0*ACC_WIDTH +: ACC_WIDTH] = v0;
            pe_results[1*ACC_WIDTH +: ACC_WIDTH] = v1;
            pe_results[2*ACC_WIDTH +: ACC_WIDTH] = v2;
            pe_results[3*ACC_WIDTH +: ACC_WIDTH] = v3;
        end
    endtask

    task check_sum(input signed [ACC_WIDTH-1:0] expected, input [127:0] test_name);
        begin
            @(posedge clk);
            #1;
            if (sum_out === expected) begin
                $display("[PASS] %0s | sum_out = %0d (Expected %0d)", test_name, sum_out, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | sum_out = %0d, Expected %0d", test_name, sum_out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("==================================================");
        $display("   TESTBENCH: Accumulator Tree (accumulator_tree) ");
        $display("==================================================");

        clk        = 0;
        rst_n      = 0;
        enable     = 0;
        clear      = 0;
        pe_results = 0;

        // Reset check
        #15;
        if (sum_out === 0) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        #10;
        rst_n = 1;
        #10;

        // Test 1: Positive addition (10 + 20 + 30 + 40 = 100)
        pack_inputs(24'sd10, 24'sd20, 24'sd30, 24'sd40);
        enable = 1;
        check_sum(24'sd100, "Test 1: 10 + 20 + 30 + 40 = 100");
        enable = 0;

        // Test 2: Mixed signs (100 + (-25) + (-75) + 50 = 50)
        pack_inputs(24'sd100, -24'sd25, -24'sd75, 24'sd50);
        enable = 1;
        check_sum(24'sd50, "Test 2: 100 - 25 - 75 + 50 = 50");
        enable = 0;

        // Test 3: Hold state (enable=0)
        pack_inputs(24'sd999, 24'sd888, 24'sd777, 24'sd666);
        enable = 0;
        check_sum(24'sd50, "Test 3: Hold when enable=0");

        // Test 4: Synchronous Clear
        @(posedge clk);
        clear = 1;
        @(posedge clk);
        #1;
        clear = 0;
        if (sum_out === 0) begin
            $display("[PASS] Test 4: Clear resets sum_out to 0");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 4: Clear failed, got %0d", sum_out);
            fail_count = fail_count + 1;
        end

        // Test 5: All negative sum (-500 + -300 + -200 + -100 = -1100)
        pack_inputs(-24'sd500, -24'sd300, -24'sd200, -24'sd100);
        enable = 1;
        check_sum(-24'sd1100, "Test 5: All negative inputs");
        enable = 0;

        #20;
        $display("==================================================");
        $display("   TREE SUMMARY: %0d PASSED, %0d FAILED          ", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> ACCUMULATOR_TREE.V IS FULLY VERIFIED! <<\n");
        else
            $display(">> ACCUMULATOR_TREE.V FAILED. <<\n");

        $finish;
    end

endmodule
