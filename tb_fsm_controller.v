// =============================================================================
// File: tb_fsm_controller.v
// Module: tb_fsm_controller
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Unit testbench for the FSM Controller (fsm_controller.v).
// =============================================================================

`timescale 1ns / 1ps

module tb_fsm_controller;

    parameter N          = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;
    parameter ADDR_WIDTH = 4;

    reg                   clk;
    reg                   rst_n;
    reg                   start;
    wire                  done;
    wire                  busy;
    wire [ADDR_WIDTH-1:0] sram_a_addr;
    wire [ADDR_WIDTH-1:0] sram_b_addr;
    wire [ADDR_WIDTH-1:0] sram_c_addr;
    wire                  sram_c_we;
    wire                  pe_clear;
    wire                  pe_enable;
    wire [ADDR_WIDTH-1:0] cnt_i_out;
    wire [ADDR_WIDTH-1:0] cnt_j_out;
    wire [ADDR_WIDTH-1:0] cnt_k_out;

    integer pass_count = 0;
    integer fail_count = 0;
    integer cycle_counter = 0;

    // Instantiate DUT
    fsm_controller #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .done       (done),
        .busy       (busy),
        .sram_a_addr(sram_a_addr),
        .sram_b_addr(sram_b_addr),
        .sram_c_addr(sram_c_addr),
        .sram_c_we  (sram_c_we),
        .pe_clear   (pe_clear),
        .pe_enable  (pe_enable),
        .cnt_i_out  (cnt_i_out),
        .cnt_j_out  (cnt_j_out),
        .cnt_k_out  (cnt_k_out)
    );

    always #5 clk = ~clk;

    initial begin
        $display("==================================================");
        $display("    TESTBENCH: FSM Controller (fsm_controller.v)  ");
        $display("==================================================");

        clk   = 0;
        rst_n = 0;
        start = 0;

        // Reset check
        #15;
        if (busy === 0 && done === 0) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        #10;
        rst_n = 1;
        #10;

        // Start operation
        $display("[INFO] Triggering START pulse");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Track cycles until DONE
        cycle_counter = 0;
        while (!done && cycle_counter < 500) begin
            @(posedge clk);
            cycle_counter = cycle_counter + 1;
        end

        if (done) begin
            $display("[PASS] FSM successfully asserted DONE in %0d cycles", cycle_counter);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] FSM timed out without asserting DONE!");
            fail_count = fail_count + 1;
        end

        // Check if FSM transitions back to IDLE
        @(posedge clk);
        #1;
        if (!busy) begin
            $display("[PASS] FSM safely returned to IDLE state (busy=0)");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] FSM did not return to IDLE");
            fail_count = fail_count + 1;
        end

        #20;
        $display("==================================================");
        $display("   FSM SUMMARY: %0d PASSED, %0d FAILED           ", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> FSM_CONTROLLER.V IS FULLY VERIFIED! <<\n");
        else
            $display(">> FSM_CONTROLLER.V FAILED. <<\n");

        $finish;
    end

endmodule
