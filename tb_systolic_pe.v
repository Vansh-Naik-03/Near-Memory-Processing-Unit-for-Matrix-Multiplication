// =============================================================================
// File: tb_systolic_pe.v
// Module: tb_systolic_pe
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Unit testbench for systolic_pe.v:
//     - Asynchronous active-low reset (rst_n)
//     - Synchronous clear
//     - Signed multiplication (positive, negative, zero, extreme -128)
//     - 4-cycle dot-product accumulation
//     - Valid-signal gating (only accumulates when a_valid_in && b_valid_in)
//     - Horizontal (a_out, a_valid_out) & vertical (b_out, b_valid_out) forwarding
// =============================================================================

`timescale 1ns / 1ps

module tb_systolic_pe;

    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 24;

    reg                         clk = 0;
    reg                         rst_n;
    reg                         clear;
    reg  signed [DATA_WIDTH-1:0] a_in;
    reg  signed [DATA_WIDTH-1:0] b_in;
    reg                         a_valid_in;
    reg                         b_valid_in;

    wire signed [DATA_WIDTH-1:0] a_out;
    wire signed [DATA_WIDTH-1:0] b_out;
    wire                        a_valid_out;
    wire                        b_valid_out;
    wire signed [ACC_WIDTH-1:0] acc_out;

    integer pass_count = 0;
    integer fail_count = 0;

    systolic_pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (clear),
        .a_in       (a_in),
        .b_in       (b_in),
        .a_valid_in (a_valid_in),
        .b_valid_in (b_valid_in),
        .a_out      (a_out),
        .b_out      (b_out),
        .a_valid_out(a_valid_out),
        .b_valid_out(b_valid_out),
        .acc_out    (acc_out)
    );

    always #5 clk = ~clk;

    task check_pe;
        input signed [ACC_WIDTH-1:0]  exp_acc;
        input signed [DATA_WIDTH-1:0] exp_a_out;
        input signed [DATA_WIDTH-1:0] exp_b_out;
        input                         exp_a_val;
        input                         exp_b_val;
        input [255:0]                 label;
        begin
            if (acc_out === exp_acc && a_out === exp_a_out && b_out === exp_b_out &&
                a_valid_out === exp_a_val && b_valid_out === exp_b_val) begin
                $display("[PASS] %0s | acc=%0d, a_out=%0d (v=%0b), b_out=%0d (v=%0b)",
                         label, acc_out, a_out, a_valid_out, b_out, b_valid_out);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | got acc=%0d a_out=%0d(v=%0b) b_out=%0d(v=%0b) | exp acc=%0d a_out=%0d(v=%0b) b_out=%0d(v=%0b)",
                         label, acc_out, a_out, a_valid_out, b_out, b_valid_out,
                         exp_acc, exp_a_out, exp_a_val, exp_b_out, exp_b_val);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("==================================================");
        $display("   TESTBENCH: Systolic PE (systolic_pe.v)         ");
        $display("==================================================");

        rst_n = 0; clear = 0;
        a_in = 0; b_in = 0;
        a_valid_in = 0; b_valid_in = 0;

        #12;
        check_pe(0, 0, 0, 0, 0, "Async reset");

        @(negedge clk);
        rst_n = 1;

        // 4-cycle signed accumulation + forwarding check
        a_in = 8'sd5; b_in = 8'sd12; a_valid_in = 1; b_valid_in = 1;
        @(posedge clk); #1;
        check_pe(60, 5, 12, 1, 1, "Cycle 1: 5 * 12 = 60");

        @(negedge clk);
        a_in = -8'sd7; b_in = 8'sd8; a_valid_in = 1; b_valid_in = 1;
        @(posedge clk); #1;
        check_pe(4, -7, 8, 1, 1, "Cycle 2: +(-7 * 8) = 4");

        @(negedge clk);
        a_in = -8'sd10; b_in = -8'sd15; a_valid_in = 1; b_valid_in = 1;
        @(posedge clk); #1;
        check_pe(154, -10, -15, 1, 1, "Cycle 3: +(-10 * -15) = 154");

        @(negedge clk);
        a_in = 8'sd0; b_in = 8'sd99; a_valid_in = 1; b_valid_in = 1;
        @(posedge clk); #1;
        check_pe(154, 0, 99, 1, 1, "Cycle 4: +(0 * 99) = 154");

        // Valid gating: only a_valid_in = 1 (should NOT accumulate, still forwards)
        @(negedge clk);
        a_in = 8'sd25; b_in = 8'sd4; a_valid_in = 1; b_valid_in = 0;
        @(posedge clk); #1;
        check_pe(154, 25, 4, 1, 0, "Valid gate: b_valid=0 holds acc");

        // Valid gating: only b_valid_in = 1 (should NOT accumulate)
        @(negedge clk);
        a_in = 8'sd25; b_in = 8'sd4; a_valid_in = 0; b_valid_in = 1;
        @(posedge clk); #1;
        check_pe(154, 25, 4, 0, 1, "Valid gate: a_valid=0 holds acc");

        // Synchronous clear
        @(negedge clk);
        clear = 1; a_valid_in = 0; b_valid_in = 0;
        @(posedge clk); #1;
        check_pe(0, 0, 0, 0, 0, "Sync clear");

        // Signed extremes: -128 * -128 = 16384, -128 * 127 = -16256
        @(negedge clk);
        clear = 0;
        a_in = -8'sd128; b_in = -8'sd128; a_valid_in = 1; b_valid_in = 1;
        @(posedge clk); #1;
        check_pe(16384, -128, -128, 1, 1, "Extreme: -128 * -128");

        @(negedge clk);
        a_in = -8'sd128; b_in = 8'sd127; a_valid_in = 1; b_valid_in = 1;
        @(posedge clk); #1;
        check_pe(128, -128, 127, 1, 1, "Extreme: +(-128 * 127) = 128");

        $display("==================================================");
        $display("   SYSTOLIC PE SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> SYSTOLIC_PE.V IS FULLY VERIFIED! <<\n");
        else
            $display(">> SYSTOLIC_PE.V FAILED! <<\n");
        $finish;
    end

endmodule

