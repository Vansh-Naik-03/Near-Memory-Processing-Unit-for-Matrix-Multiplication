`timescale 1ns / 1ps

module tb_nmpu_top;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter N          = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;
    parameter DEPTH      = N * N;   // 16
    parameter ADDR_WIDTH = 4;

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    reg                          clk;
    reg                          rst_n;
    reg                          start;
    wire                         done;
    wire                         busy;

    reg                          host_we;
    reg  [1:0]                   host_bank_sel; // 00 = A, 01 = B, 10 = C
    reg  [ADDR_WIDTH-1:0]        host_addr;
    reg  signed [ACC_WIDTH-1:0]  host_wdata;
    wire signed [ACC_WIDTH-1:0]  host_rdata;

    // -------------------------------------------------------------------------
    // Internal Testbench Storage (Signed for accurate Golden Math)
    // -------------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] mat_a [0:DEPTH-1];
    reg signed [DATA_WIDTH-1:0] mat_b [0:DEPTH-1];
    reg signed [ACC_WIDTH-1:0]  c_golden [0:DEPTH-1];

    integer i, r, c, k;
    integer pass_count;
    integer fail_count;
    integer total_cycles;

    // -------------------------------------------------------------------------
    // Instantiate NMPU Top Module (DUT)
    // -------------------------------------------------------------------------
    nmpu_top #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .DEPTH      (DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .done          (done),
        .busy          (busy),
        .host_we       (host_we),
        .host_bank_sel (host_bank_sel),
        .host_addr     (host_addr),
        .host_wdata    (host_wdata),
        .host_rdata    (host_rdata)
    );

    // -------------------------------------------------------------------------
    // 100 MHz Clock Generation (10 ns period)
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Task: Compute Expected Golden Matrix C = A x B in Software/TB
    // -------------------------------------------------------------------------
    task compute_golden_c;
        reg signed [ACC_WIDTH-1:0] sum;
        begin
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    sum = 0;
                    for (k = 0; k < N; k = k + 1) begin
                        sum = sum + (mat_a[r * N + k] * mat_b[k * N + c]);
                    end
                    c_golden[r * N + c] = sum;
                end
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: Run Complete Load -> Compute -> Readback -> Verify Flow
    // -------------------------------------------------------------------------
    task run_nmpu_test(input [255:0] test_name);
        begin
            $display("\n===============================================================");
            $display("   RUNNING TEST: %0s", test_name);
            $display("===============================================================");

            // 1. Compute golden reference inside testbench
            compute_golden_c();

            // 2. Host writes Matrix A into SRAM Bank A (bank_sel = 2'b00)
            $display("[HOST] Writing Matrix A to SRAM Bank A...");
            for (i = 0; i < DEPTH; i = i + 1) begin
                @(posedge clk);
                host_we       <= 1'b1;
                host_bank_sel <= 2'b00;
                host_addr     <= i[ADDR_WIDTH-1:0];
                // Sign-extend 8-bit element to 24-bit host_wdata bus
                host_wdata    <= {{(ACC_WIDTH-DATA_WIDTH){mat_a[i][DATA_WIDTH-1]}}, mat_a[i]};
            end
            @(posedge clk);
            host_we <= 1'b0;

            // 3. Host writes Matrix B into SRAM Bank B (bank_sel = 2'b01)
            $display("[HOST] Writing Matrix B to SRAM Bank B...");
            for (i = 0; i < DEPTH; i = i + 1) begin
                @(posedge clk);
                host_we       <= 1'b1;
                host_bank_sel <= 2'b01;
                host_addr     <= i[ADDR_WIDTH-1:0];
                host_wdata    <= {{(ACC_WIDTH-DATA_WIDTH){mat_b[i][DATA_WIDTH-1]}}, mat_b[i]};
            end
            @(posedge clk);
            host_we <= 1'b0;

            // 4. Optional Sanity Check: Read back Bank A[0] and Bank B[0]
            @(posedge clk);
            host_bank_sel <= 2'b00;
            host_addr     <= 4'd0;
            @(posedge clk);
            #1;
            $display("[CHECK] Bank A[0] Readback = %0d (Expected %0d)", host_rdata, mat_a[0]);

            // 5. Pulse START for 1 clock cycle
            $display("[NMPU] Pulsing start signal...");
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            // 6. Wait for DONE assertion and count compute cycles
            total_cycles = 0;
            while (!done && total_cycles < 2000) begin
                @(posedge clk);
                total_cycles = total_cycles + 1;
            end

            if (done) begin
                $display("[NMPU] DONE asserted in %0d clock cycles (%0d ns at 100 MHz).",
                         total_cycles, total_cycles * 10);
            end else begin
                $display("[FATAL] Timeout waiting for DONE signal!");
                $finish;
            end

            // Wait for busy to deassert completely
            @(posedge clk);

            // 7. Host reads Result Matrix C from SRAM Bank C (bank_sel = 2'b10)
            $display("---------------------------------------------------------------");
            $display("   Idx | Row | Col | NMPU Output | Golden Expected |  Status   ");
            $display("   ----+-----+-----+-------------+-----------------+-----------");

            for (i = 0; i < DEPTH; i = i + 1) begin
                @(posedge clk);
                host_we       <= 1'b0;
                host_bank_sel <= 2'b10;
                host_addr     <= i[ADDR_WIDTH-1:0];

                // Wait 1 clock cycle for synchronous SRAM read + 1ns settle time
                @(posedge clk);
                #1;

                if (host_rdata === c_golden[i]) begin
                    $display("   %2d  |  %1d  |  %1d  |   %7d   |     %7d     |   PASS",
                             i, i/N, i%N, host_rdata, c_golden[i]);
                    pass_count = pass_count + 1;
                end else begin
                    $display("   %2d  |  %1d  |  %1d  |   %7d   |     %7d     |  *FAIL*",
                             i, i/N, i%N, host_rdata, c_golden[i]);
                    fail_count = fail_count + 1;
                end
            end
            $display("---------------------------------------------------------------");
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Stimulus Sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("nmpu_top_sim.vcd");
        $dumpvars(0, tb_nmpu_top);

        // Initialize inputs
        rst_n         = 1'b0;
        start         = 1'b0;
        host_we       = 1'b0;
        host_bank_sel = 2'b00;
        host_addr     = {ADDR_WIDTH{1'b0}};
        host_wdata    = {ACC_WIDTH{1'b0}};
        pass_count    = 0;
        fail_count    = 0;

        // Apply Reset
        #25;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // =====================================================================
        // TEST 1: Simple Positive Sequential Matrix (Easy Hand-Verification)
        // A = [1..16], B = Identity Matrix -> C should equal A
        // =====================================================================
        mat_a[0]  = 8'sd1;   mat_a[1]  = 8'sd2;   mat_a[2]  = 8'sd3;   mat_a[3]  = 8'sd4;
        mat_a[4]  = 8'sd5;   mat_a[5]  = 8'sd6;   mat_a[6]  = 8'sd7;   mat_a[7]  = 8'sd8;
        mat_a[8]  = 8'sd9;   mat_a[9]  = 8'sd10;  mat_a[10] = 8'sd11;  mat_a[11] = 8'sd12;
        mat_a[12] = 8'sd13;  mat_a[13] = 8'sd14;  mat_a[14] = 8'sd15;  mat_a[15] = 8'sd16;

        mat_b[0]  = 8'sd1;   mat_b[1]  = 8'sd0;   mat_b[2]  = 8'sd0;   mat_b[3]  = 8'sd0;
        mat_b[4]  = 8'sd0;   mat_b[5]  = 8'sd1;   mat_b[6]  = 8'sd0;   mat_b[7]  = 8'sd0;
        mat_b[8]  = 8'sd0;   mat_b[9]  = 8'sd0;   mat_b[10] = 8'sd1;   mat_b[11] = 8'sd0;
        mat_b[12] = 8'sd0;   mat_b[13] = 8'sd0;   mat_b[14] = 8'sd0;   mat_b[15] = 8'sd1;

        run_nmpu_test("Test 1: Matrix A * Identity Matrix B");

        // =====================================================================
        // TEST 2: Signed Mixed Positive/Negative Matrix (From Your Waveform)
        // =====================================================================
        mat_a[0]  =  8'sd17;  mat_a[1]  = -8'sd1;   mat_a[2]  = -8'sd53;  mat_a[3]  = -8'sd68;
        mat_a[4]  = -8'sd82;  mat_a[5]  =  8'sd119; mat_a[6]  =  8'sd16;  mat_a[7]  = -8'sd52;
        mat_a[8]  = -8'sd35;  mat_a[9]  = -8'sd18;  mat_a[10] = -8'sd1;   mat_a[11] = -8'sd85;
        mat_a[12] = -8'sd84;  mat_a[13] =  8'sd51;  mat_a[14] =  8'sd69;  mat_a[15] =  8'sd16;

        mat_b[0]  =  8'sd34;  mat_b[1]  =  8'sd85;  mat_b[2]  = -8'sd86;  mat_b[3]  = -8'sd60;
        mat_b[4]  = -8'sd74;  mat_b[5]  = -8'sd69;  mat_b[6]  = -8'sd4;   mat_b[7]  =  8'sd31;
        mat_b[8]  =  8'sd67;  mat_b[9]  =  8'sd115; mat_b[10] = -8'sd41;  mat_b[11] = -8'sd53;
        mat_b[12] = -8'sd92;  mat_b[13] = -8'sd74;  mat_b[14] = -8'sd29;  mat_b[15] = -8'sd29;

        run_nmpu_test("Test 2: Signed 8-bit Matrix Multiply");

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n===============================================================");
        $display("   FINAL VERIFICATION SUMMARY                                  ");
        $display("   Total Passed: %0d / %0d", pass_count, pass_count + fail_count);
        $display("   Total Failed: %0d / %0d", fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("   STATUS: *** ALL TESTS PASSED ***");
        else
            $display("   STATUS: *** MISMATCH DETECTED (Check FSM/PE timing) ***");
        $display("===============================================================\n");

        #50;
        $finish;
    end

endmodule
