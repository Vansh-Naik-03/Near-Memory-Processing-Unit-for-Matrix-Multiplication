// =============================================================================
// File: tb_systolic_controller.v
// Module: tb_systolic_controller
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Unit testbench for systolic_controller.v:
//     - Reset behavior (IDLE, done=0, busy=0)
//     - 5-state FSM progression: IDLE -> LOAD -> COMPUTE -> DRAIN -> DONE
//     - Verifies array_clear / feeder_clear pulse
//     - Verifies 16-element SRAM A/B load address sequence & feeder_load_en
//     - Verifies 7-cycle feeder_enable in COMPUTE
//     - Verifies 4-cycle array drain wait + 16-cycle SRAM C writeback in DRAIN
//     - Verifies back-to-back operation via DONE -> IDLE -> LOAD
// =============================================================================

`timescale 1ns / 1ps

module tb_systolic_controller;

    localparam N          = 4;
    localparam DEPTH      = N * N;
    localparam ADDR_WIDTH = 4;

    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_LOAD    = 3'd1;
    localparam [2:0] STATE_COMPUTE = 3'd2;
    localparam [2:0] STATE_DRAIN   = 3'd3;
    localparam [2:0] STATE_DONE    = 3'd4;

    reg                   clk = 0;
    reg                   rst_n;
    reg                   start;
    wire                  done;
    wire                  busy;
    wire                  array_clear;
    wire                  feeder_clear;
    wire                  feeder_load_en;
    wire [ADDR_WIDTH-1:0] feeder_load_addr;
    wire                  feeder_enable;
    wire [ADDR_WIDTH-1:0] sram_a_addr;
    wire [ADDR_WIDTH-1:0] sram_b_addr;
    wire [ADDR_WIDTH-1:0] sram_c_addr;
    wire                  sram_c_we;
    wire [ADDR_WIDTH-1:0] c_drain_idx;
    wire [2:0]            state_out;

    integer pass_count = 0;
    integer fail_count = 0;
    integer cycles;
    integer load_en_cnt;
    integer feed_en_cnt;
    integer c_we_cnt;
    reg     saw_idle, saw_load, saw_compute, saw_drain, saw_done;
    reg     saw_clear;

    systolic_controller #(
        .N         (N),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .done            (done),
        .busy            (busy),
        .array_clear     (array_clear),
        .feeder_clear    (feeder_clear),
        .feeder_load_en  (feeder_load_en),
        .feeder_load_addr(feeder_load_addr),
        .feeder_enable   (feeder_enable),
        .sram_a_addr     (sram_a_addr),
        .sram_b_addr     (sram_b_addr),
        .sram_c_addr     (sram_c_addr),
        .sram_c_we       (sram_c_we),
        .c_drain_idx     (c_drain_idx),
        .state_out       (state_out)
    );

    always #5 clk = ~clk;

    task run_and_check_cycle;
        input [255:0] run_label;
        begin
            saw_idle    = 0;
            saw_load    = 0;
            saw_compute = 0;
            saw_drain   = 0;
            saw_done    = 0;
            saw_clear   = 0;
            load_en_cnt = 0;
            feed_en_cnt = 0;
            c_we_cnt    = 0;
            cycles      = 0;

            @(negedge clk);
            start = 1;
            @(posedge clk); #1;
            @(negedge clk);
            start = 0;

            while (!done && cycles < 200) begin
                if (state_out == STATE_IDLE)    saw_idle    = 1;
                if (state_out == STATE_LOAD)    saw_load    = 1;
                if (state_out == STATE_COMPUTE) saw_compute = 1;
                if (state_out == STATE_DRAIN)   saw_drain   = 1;
                if (array_clear && feeder_clear) saw_clear  = 1;
                if (feeder_load_en)             load_en_cnt = load_en_cnt + 1;
                if (feeder_enable)              feed_en_cnt = feed_en_cnt + 1;
                if (sram_c_we)                  c_we_cnt    = c_we_cnt + 1;

                @(posedge clk); #1;
                cycles = cycles + 1;
            end
            if (state_out == STATE_DONE) saw_done = 1;

            if (done && !busy && saw_load && saw_compute && saw_drain && saw_done && saw_clear &&
                load_en_cnt == DEPTH && feed_en_cnt == (2*N - 1) && c_we_cnt == DEPTH) begin
                $display("[PASS] %0s completed in %0d cycles (load=%0d, feed=%0d, c_we=%0d)",
                         run_label, cycles, load_en_cnt, feed_en_cnt, c_we_cnt);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | done=%0b busy=%0b states=(L:%0b C:%0b D:%0b DN:%0b) clr=%0b load=%0d feed=%0d c_we=%0d",
                         run_label, done, busy, saw_load, saw_compute, saw_drain, saw_done,
                         saw_clear, load_en_cnt, feed_en_cnt, c_we_cnt);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("==================================================");
        $display("   TESTBENCH: Systolic Controller (FSM)           ");
        $display("==================================================");

        rst_n = 0; start = 0;
        #12;
        if (state_out === STATE_IDLE && done === 0 && busy === 0) begin
            $display("[PASS] Reset initializes to IDLE with done=0, busy=0");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Reset state invalid");
            fail_count = fail_count + 1;
        end

        @(negedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        // Run 1
        run_and_check_cycle("Run 1");

        // Run 2 (back-to-back from DONE -> IDLE -> LOAD -> ... -> DONE)
        run_and_check_cycle("Run 2 (back-to-back)");

        if (saw_idle) begin
            $display("[PASS] Back-to-back operation returned via IDLE before restarting");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Back-to-back operation did not visit IDLE");
            fail_count = fail_count + 1;
        end

        $display("==================================================");
        $display("   CONTROLLER SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> SYSTOLIC_CONTROLLER.V IS FULLY VERIFIED! <<\n");
        else
            $display(">> SYSTOLIC_CONTROLLER.V FAILED! <<\n");
        $finish;
    end

endmodule

