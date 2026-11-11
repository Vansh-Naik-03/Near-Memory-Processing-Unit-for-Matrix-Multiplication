// =============================================================================
// File: tb_sram_bank.v
// Module: tb_sram_bank
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Unit testbench for the On-Chip SRAM Bank (sram_bank.v).
// =============================================================================

`timescale 1ns / 1ps

module tb_sram_bank;

    parameter DEPTH      = 16;
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 4;

    reg                   clk;
    reg                   rst_n;
    reg                   we;
    reg  [ADDR_WIDTH-1:0] addr;
    reg  [DATA_WIDTH-1:0] din;
    wire [DATA_WIDTH-1:0] dout;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    // Instantiate DUT
    sram_bank #(
        .DEPTH     (DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (we),
        .addr (addr),
        .din  (din),
        .dout (dout)
    );

    always #5 clk = ~clk;

    initial begin
        $display("==================================================");
        $display("       TESTBENCH: SRAM Bank (sram_bank.v)         ");
        $display("==================================================");

        clk   = 0;
        rst_n = 0;
        we    = 0;
        addr  = 0;
        din   = 0;

        #15;
        rst_n = 1;
        #10;

        // Test 1: Write walking pattern to all 16 locations
        $display("[INFO] Writing values 10..25 to addresses 0..15");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            we   = 1;
            addr = i[ADDR_WIDTH-1:0];
            din  = 8'd10 + i[7:0];
        end

        @(posedge clk);
        we = 0;

        // Test 2: Read back and verify 1-cycle latency
        $display("[INFO] Reading back and checking values with 1-cycle latency");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            addr = i[ADDR_WIDTH-1:0];
            @(posedge clk);
            #1; // Sample output after 1-cycle read latency
            if (dout === (8'd10 + i[7:0])) begin
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Addr %0d: got %0d, expected %0d", i, dout, 8'd10 + i[7:0]);
                fail_count = fail_count + 1;
            end
        end

        // Test 3: Overwrite test at address 5
        @(posedge clk);
        we   = 1;
        addr = 4'd5;
        din  = 8'hAA;
        @(posedge clk);
        we   = 0;
        addr = 4'd5;
        @(posedge clk);
        #1;
        if (dout === 8'hAA) begin
            $display("[PASS] Overwrite test at addr 5: value 0xAA confirmed");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Overwrite test at addr 5: got %h, expected 0xAA", dout);
            fail_count = fail_count + 1;
        end

        #20;
        $display("==================================================");
        $display("   SRAM SUMMARY: %0d PASSED, %0d FAILED          ", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> SRAM_BANK.V IS FULLY VERIFIED! <<\n");
        else
            $display(">> SRAM_BANK.V FAILED. <<\n");

        $finish;
    end

endmodule
