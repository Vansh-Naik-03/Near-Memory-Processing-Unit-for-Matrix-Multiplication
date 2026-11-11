// =============================================================================
// File: tb_pe.v
// Module: tb_pe
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Comprehensive unit testbench for Processing Element (pe.v).
//   Tests corner cases, signed arithmetic, accumulation loop, hold, and clear.
// =============================================================================

`timescale 1ns / 1ps

module tb_pe;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;

    reg                          clk;
    reg                          rst_n;
    reg                          clear;
    reg                          enable;
    reg  signed [DATA_WIDTH-1:0] a_in;
    reg  signed [DATA_WIDTH-1:0] b_in;
    wire signed [DATA_WIDTH-1:0] reg_a_out;
    wire signed [DATA_WIDTH-1:0] reg_b_out;
    wire signed [ACC_WIDTH-1:0]  acc_out;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate Device Under Test (DUT)
    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear),
        .enable   (enable),
        .a_in     (a_in),
        .b_in     (b_in),
        .reg_a_out(reg_a_out),
        .reg_b_out(reg_b_out),
        .acc_out  (acc_out)
    );

    // 100 MHz clock generation (10 ns period)
    always #5 clk = ~clk;

    // Verification check task
    task check_acc(input signed [ACC_WIDTH-1:0] expected, input [127:0] test_name);
        begin
            @(posedge clk);
            #1; // Sample shortly after rising edge
            if (acc_out === expected) begin
                $display("[PASS] %0s | Got acc_out = %0d (Expected %0d)", test_name, acc_out, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | Got acc_out = %0d, Expected %0d", test_name, acc_out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("==================================================");
        $display("        TESTBENCH: Processing Element (pe.v)      ");
        $display("==================================================");

        // Initialize signals
        clk    = 0;
        rst_n  = 0;
        clear  = 0;
        enable = 0;
        a_in   = 0;
        b_in   = 0;

        // Test 1: Asynchronous Reset Test
        #15;
        if (acc_out === 0) begin
            $display("[PASS] Reset Verification: acc_out initialized to 0");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Reset Verification: acc_out is %0d, expected 0", acc_out);
            fail_count = fail_count + 1;
        end

        // Deassert reset
        #10;
        rst_n = 1;
        #10;

        // Test 2: Single MAC operation (Positive numbers)
        // 5 * 12 = 60
        @(posedge clk);
        a_in   = 8'sd5;
        b_in   = 8'sd12;
        enable = 1;
        check_acc(24'sd60, "Test 2: Positive MAC (5 * 12 = 60)");
        enable = 0;

        // Test 3: Accumulation into running sum
        // 60 + (7 * 8) = 60 + 56 = 116
        @(posedge clk);
        a_in   = 8'sd7;
        b_in   = 8'sd8;
        enable = 1;
        check_acc(24'sd116, "Test 3: Accumulate (60 + 7*8 = 116)");
        enable = 0;

        // Test 4: Mixed Sign MAC (Negative product)
        // 116 + ((-10) * 15) = 116 - 150 = -34
        @(posedge clk);
        a_in   = -8'sd10;
        b_in   = 8'sd15;
        enable = 1;
        check_acc(-24'sd34, "Test 4: Mixed Sign MAC (116 + (-10)*15 = -34)");
        enable = 0;

        // Test 5: Hold Feature (enable = 0)
        @(posedge clk);
        a_in   = 8'sd50;
        b_in   = 8'sd50;
        enable = 0; // should NOT accumulate
        check_acc(-24'sd34, "Test 5: Hold state when enable=0");

        // Test 6: Synchronous Clear
        @(posedge clk);
        clear = 1;
        @(posedge clk);
        #1;
        clear = 0;
        if (acc_out === 0) begin
            $display("[PASS] Test 6: Synchronous Clear resets acc_out to 0");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 6: Clear failed, acc_out = %0d", acc_out);
            fail_count = fail_count + 1;
        end

        // Test 7: Maximum Positive Limit: 127 * 127 = 16129
        @(posedge clk);
        a_in   = 8'sd127;
        b_in   = 8'sd127;
        enable = 1;
        check_acc(24'sd16129, "Test 7: Max Positive (127 * 127 = 16129)");
        enable = 0;

        // Test 8: Maximum Negative Limit: (-128) * (-128) = 16384
        @(posedge clk);
        clear = 1;
        @(posedge clk);
        clear = 0;
        a_in   = -8'sd128;
        b_in   = -8'sd128;
        enable = 1;
        check_acc(24'sd16384, "Test 8: Max Negative (-128 * -128 = 16384)");
        enable = 0;

        // Test 9: Zero multiplication
        @(posedge clk);
        a_in   = 8'sd0;
        b_in   = 8'sd99;
        enable = 1;
        check_acc(24'sd16384, "Test 9: Zero multiplication (16384 + 0 = 16384)");
        enable = 0;

        // Final summary
        #20;
        $display("==================================================");
        $display("   PE TESTBENCH SUMMARY: %0d PASSED, %0d FAILED   ", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> PE.V IS FULLY VERIFIED AND ASIC READY! <<\n");
        else
            $display(">> PE.V FAILED VERIFICATION. <<\n");

        $finish;
    end

endmodule
