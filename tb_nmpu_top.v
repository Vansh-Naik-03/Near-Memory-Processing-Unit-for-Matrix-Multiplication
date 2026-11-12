// =============================================================================
// File: tb_nmpu_top.v
// Module: tb_nmpu_top
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Full-System Self-Checking Testbench for nmpu_top.
//   Workflow:
//     1. Loads test vectors from Python golden model (a_data.hex, b_data.hex, c_expected.hex)
//     2. Resets system (active-low rst_n)
//     3. Host writes Matrix A into On-Chip Near-Memory Bank A
//     4. Host writes Matrix B into On-Chip Near-Memory Bank B
//     5. Host asserts START pulse to wake NMPU FSM
//     6. Waits for DONE flag from NMPU
//     7. Measures total execution cycles and execution time
//     8. Host reads result Matrix C from Near-Memory Bank C
//     9. Performs bit-accurate comparison against golden reference
//    10. Dumps VCD waveform for Cadence Voltus post-layout power analysis
// =============================================================================

`timescale 1ns / 1ps

module tb_nmpu_top;

    parameter N          = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;
    parameter DEPTH      = N * N;   // 16
    parameter ADDR_WIDTH = 4;

    reg                          clk;
    reg                          rst_n;
    reg                          start;
    wire                         done;
    wire                         busy;

    reg                          host_we;
    reg  [1:0]                   host_bank_sel;
    reg  [ADDR_WIDTH-1:0]        host_addr;
    reg  signed [ACC_WIDTH-1:0]  host_wdata;
    wire signed [ACC_WIDTH-1:0]  host_rdata;

    // Test vector storage
    reg [DATA_WIDTH-1:0] a_hex [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] b_hex [0:DEPTH-1];
    reg [ACC_WIDTH-1:0]  c_hex [0:DEPTH-1];

    integer i, row, col;
    integer pass_count = 0;
    integer fail_count = 0;
    integer total_cycles = 0;

    // Instantiate Top-Level NMPU DUT
    nmpu_top #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .done         (done),
        .busy         (busy),
        .host_we      (host_we),
        .host_bank_sel(host_bank_sel),
        .host_addr    (host_addr),
        .host_wdata   (host_wdata),
        .host_rdata   (host_rdata)
    );

    // 100 MHz clock (10 ns period) - typical ASIC clock constraint
    always #5 clk = ~clk;

    initial begin
        // Waveform dump for Cadence Voltus activity & ModelSim inspection
        $dumpfile("nmpu_full_sim.vcd");
        $dumpvars(0, tb_nmpu_top);

        // Load test matrices from golden model output
       // $readmemh("../sim/test_vectors/a_data.hex", a_hex);
       // $readmemh("../sim/test_vectors/b_data.hex", b_hex);
       // $readmemh("../sim/test_vectors/c_expected.hex", c_hex);
       $readmemh("a_data.hex", a_hex);
       $readmemh("b_data.hex", b_hex);
       $readmemh("c_data.hex", c_hex);
        $readmemh("/home/user/Vansh/NMPU/NMPU.sim/sim_1/behav/xsim", a_hex);
        $readmemh("/home/user/Vansh/NMPU/NMPU.sim/sim_1/behav/xsim", b_hex);
        $readmemh("/home/user/Vansh/NMPU/NMPU.sim/sim_1/behav/xsim", c_hex);

        $display("\n===============================================================");
        $display("   FINAL YEAR PROJECT: Near-Memory Processing Unit (NMPU)       ");
        $display("   Full-System End-to-End Verification Testbench (4x4 Matrix)   ");
        $display("===============================================================\n");

        // Initialize signals
        clk           = 0;
        rst_n         = 0;
        start         = 0;
        host_we       = 0;
        host_bank_sel = 2'b00;
        host_addr     = 0;
        host_wdata    = 0;

        // Step 1: System Reset
        $display("[STAGE 1] Applying asynchronous active-low reset (rst_n = 0)");
        #25;
        rst_n = 1;
        #20;
        $display("[STAGE 1] System reset successfully released.\n");

        // Step 2: Host writes Matrix A into On-Chip SRAM Bank A
        $display("[STAGE 2] Host loading Matrix A into Near-Memory SRAM Bank A...");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            host_we       = 1;
            host_bank_sel = 2'b00;  // SRAM Bank A
            host_addr     = i[ADDR_WIDTH-1:0];
            // Sign-extend 8-bit hex to full host bus
            host_wdata    = {{(ACC_WIDTH-DATA_WIDTH){a_hex[i][DATA_WIDTH-1]}}, a_hex[i]};
        end
        @(posedge clk);
        host_we = 0;
        $display("[STAGE 2] Matrix A (16 elements) loaded.\n");

        // Step 3: Host writes Matrix B into On-Chip SRAM Bank B
        $display("[STAGE 3] Host loading Matrix B into Near-Memory SRAM Bank B...");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            host_we       = 1;
            host_bank_sel = 2'b01;  // SRAM Bank B
            host_addr     = i[ADDR_WIDTH-1:0];
            host_wdata    = {{(ACC_WIDTH-DATA_WIDTH){b_hex[i][DATA_WIDTH-1]}}, b_hex[i]};
        end
        @(posedge clk);
        host_we = 0;
        $display("[STAGE 3] Matrix B (16 elements) loaded.\n");

        // Step 4: Trigger NMPU Matrix Multiplication
        $display("[STAGE 4] Host pulsing START signal to trigger NMPU FSM...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Step 5: Wait for NMPU computation to complete
        $display("[STAGE 5] Computation in progress (Near-Memory Processing)...");
        total_cycles = 0;
        while (!done && total_cycles < 2000) begin
            @(posedge clk);
            total_cycles = total_cycles + 1;
        end

        if (done) begin
            $display("[STAGE 5] [DONE ASSERTED] Computation completed in %0d clock cycles!", total_cycles);
            $display("          Execution latency at 100 MHz = %0d ns\n", total_cycles * 10);
        end else begin
            $display("[FATAL ERROR] Computation timed out! DONE was never asserted.\n");
            $finish;
        end

        #20;

        // Step 6: Read Result Matrix C from SRAM Bank C and compare
        $display("===============================================================");
        $display("   STAGE 6: Verification of Result Matrix C (Output vs Golden)");
        $display("===============================================================");
        $display("   Index | Row | Col | NMPU Output | Golden Expected | Status ");
        $display("   ------+-----+-----+-------------+-----------------+--------");

        for (i = 0; i < DEPTH; i = i + 1) begin
            row = i / N;
            col = i % N;

            @(posedge clk);
            host_we       = 0;
            host_bank_sel = 2'b10; // Read from SRAM Bank C
            host_addr     = i[ADDR_WIDTH-1:0];

            @(posedge clk);
            #1; // Sample output after 1-cycle synchronous SRAM read latency

            if (host_rdata === $signed(c_hex[i])) begin
                $display("    %2d   |  %1d  |  %1d  |    %6d   |     %6d      |  PASS  ",
                         i, row, col, host_rdata, $signed(c_hex[i]));
                pass_count = pass_count + 1;
            end else begin
                $display("    %2d   |  %1d  |  %1d  |    %6d   |     %6d      | *FAIL* ",
                         i, row, col, host_rdata, $signed(c_hex[i]));
                fail_count = fail_count + 1;
            end
        end

        $display("   ------------------------------------------------------------\n");

        // Final Assessment
        $display("===============================================================");
        if (fail_count == 0) begin
            $display("   *** ALL 16 MATRIX ELEMENTS VERIFIED SUCCESSFULLY! ***       ");
            $display("   *** FINAL RESULT: NMPU TESTBENCH PASSED (100%% MATCH) ***    ");
        end else begin
            $display("   *** VERIFICATION FAILED: %0d MISMATCHES DETECTED ***        ", fail_count);
        end
        $display("   Total Matrix Multiply Latency: %0d Clock Cycles", total_cycles);
        $display("   Target Clock Frequency:        100 MHz");
        $display("===============================================================\n");

        #50;
        $finish;
    end

endmodule
