//`timescale 1ns / 1ps

//module tb_nmpu_top;

//    // -------------------------------------------------------------------------
//    // Parameters
//    // -------------------------------------------------------------------------
//    parameter N          = 4;
//    parameter DATA_WIDTH = 8;
//    parameter ACC_WIDTH  = 24;
//    parameter DEPTH      = N * N;   // 16
//    parameter ADDR_WIDTH = 4;

//    // -------------------------------------------------------------------------
//    // DUT Signals
//    // -------------------------------------------------------------------------
//    reg                          clk;
//    reg                          rst_n;
//    reg                          start;
//    wire                         done;
//    wire                         busy;

//    reg                          host_we;
//    reg  [1:0]                   host_bank_sel; // 00 = A, 01 = B, 10 = C
//    reg  [ADDR_WIDTH-1:0]        host_addr;
//    reg  signed [ACC_WIDTH-1:0]  host_wdata;
//    wire signed [ACC_WIDTH-1:0]  host_rdata;

//    // -------------------------------------------------------------------------
//    // Internal Testbench Storage (Signed for accurate Golden Math)
//    // -------------------------------------------------------------------------
//    reg signed [DATA_WIDTH-1:0] mat_a [0:DEPTH-1];
//    reg signed [DATA_WIDTH-1:0] mat_b [0:DEPTH-1];
//    reg signed [ACC_WIDTH-1:0]  c_golden [0:DEPTH-1];

//    integer i, r, c, k;
//    integer pass_count;
//    integer fail_count;
//    integer total_cycles;

//    // -------------------------------------------------------------------------
//    // Instantiate NMPU Top Module (DUT)
//    // -------------------------------------------------------------------------
//    nmpu_top #(
//        .N          (N),
//        .DATA_WIDTH (DATA_WIDTH),
//        .ACC_WIDTH  (ACC_WIDTH),
//        .DEPTH      (DEPTH),
//        .ADDR_WIDTH (ADDR_WIDTH)
//    ) dut (
//        .clk           (clk),
//        .rst_n         (rst_n),
//        .start         (start),
//        .done          (done),
//        .busy          (busy),
//        .host_we       (host_we),
//        .host_bank_sel (host_bank_sel),
//        .host_addr     (host_addr),
//        .host_wdata    (host_wdata),
//        .host_rdata    (host_rdata)
//    );

//    // -------------------------------------------------------------------------
//    // 100 MHz Clock Generation (10 ns period)
//    // -------------------------------------------------------------------------
//    initial clk = 1'b0;
//    always #5 clk = ~clk;

//    // -------------------------------------------------------------------------
//    // Task: Compute Expected Golden Matrix C = A x B in Software/TB
//    // -------------------------------------------------------------------------
//    task compute_golden_c;
//        reg signed [ACC_WIDTH-1:0] sum;
//        begin
//            for (r = 0; r < N; r = r + 1) begin
//                for (c = 0; c < N; c = c + 1) begin
//                    sum = 0;
//                    for (k = 0; k < N; k = k + 1) begin
//                        sum = sum + (mat_a[r * N + k] * mat_b[k * N + c]);
//                    end
//                    c_golden[r * N + c] = sum;
//                end
//            end
//        end
//    endtask

//    // -------------------------------------------------------------------------
//    // Task: Run Complete Load -> Compute -> Readback -> Verify Flow
//    // -------------------------------------------------------------------------
//    task run_nmpu_test(input [255:0] test_name);
//        begin
//            $display("\n===============================================================");
//            $display("   RUNNING TEST: %0s", test_name);
//            $display("===============================================================");

//            // 1. Compute golden reference inside testbench
//            compute_golden_c();

//            // 2. Host writes Matrix A into SRAM Bank A (bank_sel = 2'b00)
//            $display("[HOST] Writing Matrix A to SRAM Bank A...");
//            for (i = 0; i < DEPTH; i = i + 1) begin
//                @(posedge clk);
//                host_we       <= 1'b1;
//                host_bank_sel <= 2'b00;
//                host_addr     <= i[ADDR_WIDTH-1:0];
//                // Sign-extend 8-bit element to 24-bit host_wdata bus
//                host_wdata    <= {{(ACC_WIDTH-DATA_WIDTH){mat_a[i][DATA_WIDTH-1]}}, mat_a[i]};
//            end
//            @(posedge clk);
//            host_we <= 1'b0;

//            // 3. Host writes Matrix B into SRAM Bank B (bank_sel = 2'b01)
//            $display("[HOST] Writing Matrix B to SRAM Bank B...");
//            for (i = 0; i < DEPTH; i = i + 1) begin
//                @(posedge clk);
//                host_we       <= 1'b1;
//                host_bank_sel <= 2'b01;
//                host_addr     <= i[ADDR_WIDTH-1:0];
//                host_wdata    <= {{(ACC_WIDTH-DATA_WIDTH){mat_b[i][DATA_WIDTH-1]}}, mat_b[i]};
//            end
//            @(posedge clk);
//            host_we <= 1'b0;

//            // 4. Optional Sanity Check: Read back Bank A[0] and Bank B[0]
//            @(posedge clk);
//            host_bank_sel <= 2'b00;
//            host_addr     <= 4'd0;
//            @(posedge clk);
//            #1;
//            $display("[CHECK] Bank A[0] Readback = %0d (Expected %0d)", host_rdata, mat_a[0]);

//            // 5. Pulse START for 1 clock cycle
//            $display("[NMPU] Pulsing start signal...");
//            @(posedge clk);
//            start <= 1'b1;
//            @(posedge clk);
//            start <= 1'b0;

//            // 6. Wait for DONE assertion and count compute cycles
//            total_cycles = 0;
//            while (!done && total_cycles < 2000) begin
//                @(posedge clk);
//                total_cycles = total_cycles + 1;
//            end

//            if (done) begin
//                $display("[NMPU] DONE asserted in %0d clock cycles (%0d ns at 100 MHz).",
//                         total_cycles, total_cycles * 10);
//            end else begin
//                $display("[FATAL] Timeout waiting for DONE signal!");
//                $finish;
//            end

//            // Wait for busy to deassert completely
//            @(posedge clk);

//            // 7. Host reads Result Matrix C from SRAM Bank C (bank_sel = 2'b10)
//            $display("---------------------------------------------------------------");
//            $display("   Idx | Row | Col | NMPU Output | Golden Expected |  Status   ");
//            $display("   ----+-----+-----+-------------+-----------------+-----------");

//            for (i = 0; i < DEPTH; i = i + 1) begin
//                @(posedge clk);
//                host_we       <= 1'b0;
//                host_bank_sel <= 2'b10;
//                host_addr     <= i[ADDR_WIDTH-1:0];

//                // Wait 1 clock cycle for synchronous SRAM read + 1ns settle time
//                @(posedge clk);
//                #1;

//                if (host_rdata === c_golden[i]) begin
//                    $display("   %2d  |  %1d  |  %1d  |   %7d   |     %7d     |   PASS",
//                             i, i/N, i%N, host_rdata, c_golden[i]);
//                    pass_count = pass_count + 1;
//                end else begin
//                    $display("   %2d  |  %1d  |  %1d  |   %7d   |     %7d     |  *FAIL*",
//                             i, i/N, i%N, host_rdata, c_golden[i]);
//                    fail_count = fail_count + 1;
//                end
//            end
//            $display("---------------------------------------------------------------");
//        end
//    endtask

//    // -------------------------------------------------------------------------
//    // Main Stimulus Sequence
//    // -------------------------------------------------------------------------
//    initial begin
//        $dumpfile("nmpu_top_sim.vcd");
//        $dumpvars(0, tb_nmpu_top);

//        // Initialize inputs
//        rst_n         = 1'b0;
//        start         = 1'b0;
//        host_we       = 1'b0;
//        host_bank_sel = 2'b00;
//        host_addr     = {ADDR_WIDTH{1'b0}};
//        host_wdata    = {ACC_WIDTH{1'b0}};
//        pass_count    = 0;
//        fail_count    = 0;

//        // Apply Reset
//        #25;
//        rst_n = 1'b1;
//        repeat (2) @(posedge clk);

//        // =====================================================================
//        // TEST 1: Simple Positive Sequential Matrix (Easy Hand-Verification)
//        // A = [1..16], B = Identity Matrix -> C should equal A
//        // =====================================================================
//        mat_a[0]  = 8'sd1;   mat_a[1]  = 8'sd2;   mat_a[2]  = 8'sd3;   mat_a[3]  = 8'sd4;
//        mat_a[4]  = 8'sd5;   mat_a[5]  = 8'sd6;   mat_a[6]  = 8'sd7;   mat_a[7]  = 8'sd8;
//        mat_a[8]  = 8'sd9;   mat_a[9]  = 8'sd10;  mat_a[10] = 8'sd11;  mat_a[11] = 8'sd12;
//        mat_a[12] = 8'sd13;  mat_a[13] = 8'sd14;  mat_a[14] = 8'sd15;  mat_a[15] = 8'sd16;

//        mat_b[0]  = 8'sd1;   mat_b[1]  = 8'sd0;   mat_b[2]  = 8'sd0;   mat_b[3]  = 8'sd0;
//        mat_b[4]  = 8'sd0;   mat_b[5]  = 8'sd1;   mat_b[6]  = 8'sd0;   mat_b[7]  = 8'sd0;
//        mat_b[8]  = 8'sd0;   mat_b[9]  = 8'sd0;   mat_b[10] = 8'sd1;   mat_b[11] = 8'sd0;
//        mat_b[12] = 8'sd0;   mat_b[13] = 8'sd0;   mat_b[14] = 8'sd0;   mat_b[15] = 8'sd1;

//        run_nmpu_test("Test 1: Matrix A * Identity Matrix B");

//        // =====================================================================
//        // TEST 2: Signed Mixed Positive/Negative Matrix (From Your Waveform)
//        // =====================================================================
//        mat_a[0]  =  8'sd17;  mat_a[1]  = -8'sd1;   mat_a[2]  = -8'sd53;  mat_a[3]  = -8'sd68;
//        mat_a[4]  = -8'sd82;  mat_a[5]  =  8'sd119; mat_a[6]  =  8'sd16;  mat_a[7]  = -8'sd52;
//        mat_a[8]  = -8'sd35;  mat_a[9]  = -8'sd18;  mat_a[10] = -8'sd1;   mat_a[11] = -8'sd85;
//        mat_a[12] = -8'sd84;  mat_a[13] =  8'sd51;  mat_a[14] =  8'sd69;  mat_a[15] =  8'sd16;

//        mat_b[0]  =  8'sd34;  mat_b[1]  =  8'sd85;  mat_b[2]  = -8'sd86;  mat_b[3]  = -8'sd60;
//        mat_b[4]  = -8'sd74;  mat_b[5]  = -8'sd69;  mat_b[6]  = -8'sd4;   mat_b[7]  =  8'sd31;
//        mat_b[8]  =  8'sd67;  mat_b[9]  =  8'sd115; mat_b[10] = -8'sd41;  mat_b[11] = -8'sd53;
//        mat_b[12] = -8'sd92;  mat_b[13] = -8'sd74;  mat_b[14] = -8'sd29;  mat_b[15] = -8'sd29;

//        run_nmpu_test("Test 2: Signed 8-bit Matrix Multiply");

//        // =====================================================================
//        // Final Summary
//        // =====================================================================
//        $display("\n===============================================================");
//        $display("   FINAL VERIFICATION SUMMARY                                  ");
//        $display("   Total Passed: %0d / %0d", pass_count, pass_count + fail_count);
//        $display("   Total Failed: %0d / %0d", fail_count, pass_count + fail_count);
//        if (fail_count == 0)
//            $display("   STATUS: *** ALL TESTS PASSED ***");
//        else
//            $display("   STATUS: *** MISMATCH DETECTED (Check FSM/PE timing) ***");
//        $display("===============================================================\n");

//        #50;
//        $finish;
//    end

//endmodule
// =============================================================================
// File: tb_nmpu_top.v
// Module: tb_nmpu_top
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Full-System End-to-End Self-Checking Testbench for nmpu_top.v.
//   Mirrors tb_systolic_top.v (Tests 1 to 5) line-for-line for direct
//   architectural verification and cycle-count comparison.
//
//   Test plan:
//     Test 1 : Sequential 1..16 x 1..16  -> expected C[0][0]=90 .. C[3][3]=600
//     Test 2 : Signed/zero matrix        -> golden_model.py reference vectors
//     Test 3 : Identity x signed matrix  -> result equals B (I*B = B)
//     Test 4 : Extreme signed boundaries -> -128/127/0 alternating
//     Test 5 : Reset during DONE then restart (robustness)
// =============================================================================

`timescale 1ns / 1ps

module tb_nmpu_top;

    localparam N          = 4;
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 24;
    localparam DEPTH      = N * N;
    localparam ADDR_WIDTH = 4;

    reg                         clk = 0;
    reg                         rst_n;
    reg                         start;
    wire                        done;
    wire                        busy;

    reg                         host_we;
    reg  [1:0]                  host_bank_sel;
    reg  [ADDR_WIDTH-1:0]       host_addr;
    reg  signed [ACC_WIDTH-1:0] host_wdata;
    wire signed [ACC_WIDTH-1:0] host_rdata;

    // Hex vector storage for golden model signed test (Test 2)
    reg [DATA_WIDTH-1:0] a_signed_hex [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] b_signed_hex [0:DEPTH-1];
    reg [ACC_WIDTH-1:0]  c_signed_hex [0:DEPTH-1];

    // Per-test matrices (programmatic)
    reg signed [DATA_WIDTH-1:0] a_vec [0:DEPTH-1];
    reg signed [DATA_WIDTH-1:0] b_vec [0:DEPTH-1];
    reg signed [ACC_WIDTH-1:0]  c_exp [0:DEPTH-1];

    integer i, row, col;
    integer pass_count = 0;
    integer fail_count = 0;
    integer total_cycles;

    // Instantiate NMPU Top-Level Module
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

    always #5 clk = ~clk;

    // =========================================================================
    // Task: load A and B into SRAMs, trigger compute, verify SRAM C outputs
    // =========================================================================
    task run_and_verify;
        input [511:0] test_label;
        integer idx;
        begin
            // -----------------------------------------------------------------
            // Phase 1: Host writes Matrix A into SRAM Bank A
            // -----------------------------------------------------------------
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                @(negedge clk);
                host_we       = 1;
                host_bank_sel = 2'b00;
                host_addr     = idx[ADDR_WIDTH-1:0];
                host_wdata    = {{(ACC_WIDTH-DATA_WIDTH){a_vec[idx][DATA_WIDTH-1]}}, a_vec[idx]};
                @(posedge clk);
            end

            // -----------------------------------------------------------------
            // Phase 2: Host writes Matrix B into SRAM Bank B
            // -----------------------------------------------------------------
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                @(negedge clk);
                host_we       = 1;
                host_bank_sel = 2'b01;
                host_addr     = idx[ADDR_WIDTH-1:0];
                host_wdata    = {{(ACC_WIDTH-DATA_WIDTH){b_vec[idx][DATA_WIDTH-1]}}, b_vec[idx]};
                @(posedge clk);
            end
            @(negedge clk);
            host_we = 0;

            // -----------------------------------------------------------------
            // Phase 3: Pulse start and measure latency to done
            // -----------------------------------------------------------------
            @(negedge clk);
            start = 1;
            @(posedge clk); #1;
            @(negedge clk);
            start = 0;

            total_cycles = 1;
            while (!done && total_cycles < 2000) begin
                @(posedge clk); #1;
                total_cycles = total_cycles + 1;
            end

            if (!done) begin
                $display("[FATAL] %0s: DONE never asserted (timeout at %0d cycles)",
                         test_label, total_cycles);
                fail_count = fail_count + 1;
            end else if (busy) begin
                $display("[FAIL]  %0s: busy still high when done asserted", test_label);
                fail_count = fail_count + 1;
            end else begin
                $display("[INFO]  %0s: completed in %0d cycles (%0d ns @ 100 MHz; Systolic baseline: 45)",
                         test_label, total_cycles, total_cycles * 10);
            end

            // -----------------------------------------------------------------
            // Phase 4: Read SRAM Bank C and bit-compare against expected
            // -----------------------------------------------------------------
            $display("   Idx | Row | Col |   NMPU C   | Expected C | Status");
            $display("   ----+-----+-----+------------+------------+-------");
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                row = idx / N;
                col = idx % N;

                @(negedge clk);
                host_we       = 0;
                host_bank_sel = 2'b10;
                host_addr     = idx[ADDR_WIDTH-1:0];
                @(posedge clk);
                @(posedge clk); #1;  // 1-cycle synchronous SRAM read latency

                if (host_rdata === c_exp[idx]) begin
                    $display("    %2d |  %1d  |  %1d  |   %7d  |   %7d  | PASS",
                             idx, row, col, host_rdata, c_exp[idx]);
                    pass_count = pass_count + 1;
                end else begin
                    $display("    %2d |  %1d  |  %1d  |   %7d  |   %7d  | *FAIL*",
                             idx, row, col, host_rdata, c_exp[idx]);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    // =========================================================================
    // Initial block: run all 5 tests
    // =========================================================================
    initial begin
        $dumpfile("nmpu_sim.vcd");
        $dumpvars(0, tb_nmpu_top);

        // Try loading hex files exported by Vivado (a_data.hex or sys_signed_a.hex)
        $readmemh("a_data.hex", a_signed_hex);
        $readmemh("b_data.hex", b_signed_hex);
        $readmemh("c_data.hex", c_signed_hex);
        if (a_signed_hex[0] === 8'hxx) begin
            $readmemh("test_vectors/sys_signed_a.hex", a_signed_hex);
            $readmemh("test_vectors/sys_signed_b.hex", b_signed_hex);
            $readmemh("test_vectors/sys_signed_c.hex", c_signed_hex);
        end
        if (a_signed_hex[0] === 8'hxx) begin
            $readmemh("sys_signed_a.hex", a_signed_hex);
            $readmemh("sys_signed_b.hex", b_signed_hex);
            $readmemh("sys_signed_c.hex", c_signed_hex);
        end

        $display("\n================================================================");
        $display("   NMPU ARCHITECTURE: Full-System End-to-End Verification       ");
        $display("   4x4 Broadcast + Adder-Tree | 8-bit signed | 100 MHz target   ");
        $display("================================================================\n");

        rst_n = 0; start = 0;
        host_we = 0; host_bank_sel = 0; host_addr = 0; host_wdata = 0;
        #25;
        rst_n = 1;
        #15;

        // =====================================================================
        // TEST 1: Sequential 1..16 x 1..16
        // Expected: C[0][0]=90, C[0][1]=100, ..., C[3][3]=600
        // =====================================================================
        for (i = 0; i < DEPTH; i = i + 1) begin
            a_vec[i] = i + 1;
            b_vec[i] = i + 1;
        end
        c_exp[0]  = 90;  c_exp[1]  = 100; c_exp[2]  = 110; c_exp[3]  = 120;
        c_exp[4]  = 202; c_exp[5]  = 228; c_exp[6]  = 254; c_exp[7]  = 280;
        c_exp[8]  = 314; c_exp[9]  = 356; c_exp[10] = 398; c_exp[11] = 440;
        c_exp[12] = 426; c_exp[13] = 484; c_exp[14] = 542; c_exp[15] = 600;

        run_and_verify("Test 1 (Sequential 1..16 x 1..16)");

        // =====================================================================
        // TEST 2: Golden model signed & zero matrix
        // =====================================================================
//        if (a_signed_hex[0] === 8'hxx) begin
//            // Built-in fallback if hex files are not present in xsim folder
//            a_vec[0]= 2; a_vec[1]=-1; a_vec[2]= 0; a_vec[3]= 3;
//            a_vec[4]=-2; a_vec[5]= 4; a_vec[6]= 1; a_vec[7]= 0;
//            a_vec[8]= 0; a_vec[9]= 2; a_vec[10]=-3; a_vec[11]= 1;
//            a_vec[12]=1; a_vec[13]=0; a_vec[14]= 2; a_vec[15]=-2;

//            b_vec[0]= 1; b_vec[1]= 2; b_vec[2]= 0; b_vec[3]=-1;
//            b_vec[4]= 3; b_vec[5]= 0; b_vec[6]=-2; b_vec[7]= 2;
//            b_vec[8]= 0; b_vec[9]= 1; b_vec[10]= 4; b_vec[11]= 0;
//            b_vec[12]=-1; b_vec[13]=2; b_vec[14]= 1; b_vec[15]= 3;

//            c_exp[0]=-4; c_exp[1]=10; c_exp[2]= 5; c_exp[3]= 5;
//            c_exp[4]=10; c_exp[5]=-3; c_exp[6]=-4; c_exp[7]=10;
//            c_exp[8]= 5; c_exp[9]=-1; c_exp[10]=-15;c_exp[11]=7;
//            c_exp[12]=3; c_exp[13]=0; c_exp[14]= 6; c_exp[15]=-7;
//        end else begin
//            for (i = 0; i < DEPTH; i = i + 1) begin
//                a_vec[i] = $signed(a_signed_hex[i]);
//                b_vec[i] = $signed(b_signed_hex[i]);
//                c_exp[i] = $signed(c_signed_hex[i]);
//            end
//        end
//        run_and_verify("Test 2 (Signed & Zero - Golden Model)");
// =====================================================================
        // TEST 2: Golden model signed & zero matrix
        // =====================================================================
        if ((a_signed_hex[0] === 8'hxx) || (b_signed_hex[0] === 8'hxx)) begin
            // Built-in fallback if hex files are not present
            a_vec[0]= 2; a_vec[1]=-1; a_vec[2]= 0; a_vec[3]= 3;
            a_vec[4]=-2; a_vec[5]= 4; a_vec[6]= 1; a_vec[7]= 0;
            a_vec[8]= 0; a_vec[9]= 2; a_vec[10]=-3; a_vec[11]= 1;
            a_vec[12]=1; a_vec[13]=0; a_vec[14]= 2; a_vec[15]=-2;

            b_vec[0]= 1; b_vec[1]= 2; b_vec[2]= 0; b_vec[3]=-1;
            b_vec[4]= 3; b_vec[5]= 0; b_vec[6]=-2; b_vec[7]= 2;
            b_vec[8]= 0; b_vec[9]= 1; b_vec[10]= 4; b_vec[11]= 0;
            b_vec[12]=-1; b_vec[13]=2; b_vec[14]= 1; b_vec[15]= 3;
        end else begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                a_vec[i] = $signed(a_signed_hex[i]);
                b_vec[i] = $signed(b_signed_hex[i]);
            end
        end

        // Automatically compute exact 24-bit signed golden reference C = A * B
        for (row = 0; row < N; row = row + 1) begin
            for (col = 0; col < N; col = col + 1) begin
                c_exp[row*N + col] = 24'sd0;
                for (i = 0; i < N; i = i + 1) begin
                    c_exp[row*N + col] = c_exp[row*N + col] + (a_vec[row*N + i] * b_vec[i*N + col]);
                end
            end
        end
        run_and_verify("Test 2 (Signed & Zero - Golden Model)");

        // =====================================================================
        // TEST 3: Identity x Signed matrix (I*B = B)
        // =====================================================================
        a_vec[0]=1; a_vec[1]=0; a_vec[2]=0; a_vec[3]=0;
        a_vec[4]=0; a_vec[5]=1; a_vec[6]=0; a_vec[7]=0;
        a_vec[8]=0; a_vec[9]=0; a_vec[10]=1; a_vec[11]=0;
        a_vec[12]=0; a_vec[13]=0; a_vec[14]=0; a_vec[15]=1;

        b_vec[0]=3;  b_vec[1]=-2; b_vec[2]=4;  b_vec[3]=1;
        b_vec[4]=5;  b_vec[5]=0;  b_vec[6]=-3; b_vec[7]=2;
        b_vec[8]=-1; b_vec[9]=4;  b_vec[10]=2; b_vec[11]=-5;
        b_vec[12]=2; b_vec[13]=-1; b_vec[14]=0; b_vec[15]=3;

        c_exp[0]=3;  c_exp[1]=-2; c_exp[2]=4;  c_exp[3]=1;
        c_exp[4]=5;  c_exp[5]=0;  c_exp[6]=-3; c_exp[7]=2;
        c_exp[8]=-1; c_exp[9]=4;  c_exp[10]=2; c_exp[11]=-5;
        c_exp[12]=2; c_exp[13]=-1; c_exp[14]=0; c_exp[15]=3;

        run_and_verify("Test 3 (Identity x Signed)");

        // =====================================================================
        // TEST 4: Extreme signed values (-128/127/0 alternating)
        // =====================================================================
        for (i = 0; i < DEPTH; i = i + 1) begin
            a_vec[i] = (i % 2 == 0) ? -8'sd128 : 8'sd0;
            b_vec[i] = (i % 2 == 0) ? -8'sd128 : 8'sd127;
        end
        for (row = 0; row < N; row = row + 1) begin
            for (col = 0; col < N; col = col + 1) begin
                c_exp[row*N + col] = (col % 2 == 0) ? 24'sd32768 : -24'sd32512;
            end
        end
        run_and_verify("Test 4 (Extreme Signed -128/127/0)");

        // =====================================================================
        // TEST 5: Reset during DONE state, then restart with new data
        // =====================================================================
        @(negedge clk);
        rst_n = 0;
        #15;
        rst_n = 1;
        #10;

        for (i = 0; i < DEPTH; i = i + 1) begin
            a_vec[i] = 8'sd0;
            b_vec[i] = (i/N == i%N) ? 8'sd1 : 8'sd0;
            c_exp[i] = 24'sd0;
        end

        run_and_verify("Test 5 (Reset then restart - Zero x Identity)");

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n================================================================");
        $display("   NMPU TOP SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================");
        if (fail_count == 0)
            $display("   *** ALL %0d ELEMENT CHECKS PASSED (100%% BIT-ACCURATE) ***\n",
                     pass_count);
        else
            $display("   *** VERIFICATION FAILED: %0d mismatches detected ***\n", fail_count);
        $finish;
    end

endmodule
