// =============================================================================
// File: tb_systolic_top.v
// Module: tb_systolic_top
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Full-System End-to-End Self-Checking Testbench for systolic_top.v.
//
//   Run from the project root (where test_vectors/ lives):
//     iverilog -Wall -g2001 -o tb_systolic_top.vvp \
//       sram_bank.v systolic_pe.v systolic_array.v \
//       systolic_input_feeder.v systolic_controller.v systolic_top.v \
//       tb_systolic_top.v
//     vvp tb_systolic_top.vvp
//
//   Test plan:
//     Test 1 : Sequential 1..16 × 1..16  → expected C[0][0]=90 .. C[3][3]=600
//     Test 2 : Signed/zero matrix        → golden_model.py reference vectors
//     Test 3 : Identity × signed matrix  → result equals B (I×B = B)
//     Test 4 : Extreme signed boundaries → -128/127/0 alternating
//     Test 5 : Reset during DONE then restart (robustness)
//
//   Latency printed per run; compare against NMPU baseline of 177 cycles.
// =============================================================================

`timescale 1ns / 1ps

module tb_systolic_top;

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

    systolic_top #(
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
                $display("[INFO]  %0s: completed in %0d cycles (%0d ns @ 100 MHz; NMPU baseline: 177)",
                         test_label, total_cycles, total_cycles * 10);
            end

            // -----------------------------------------------------------------
            // Phase 4: Read SRAM Bank C and bit-compare against expected
            // -----------------------------------------------------------------
            $display("   Idx | Row | Col | Systolic C | Expected C | Status");
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
    // Initial block: run all tests
    // =========================================================================
    initial begin
        $dumpfile("systolic_sim.vcd");
        $dumpvars(0, tb_systolic_top);

        // Load golden model test vectors (signed/zero matrices)
        // Works from project root (test_vectors/) or flat in Vivado xsim directory
        $readmemh("test_vectors/sys_signed_a.hex", a_signed_hex);
        $readmemh("test_vectors/sys_signed_b.hex", b_signed_hex);
        $readmemh("test_vectors/sys_signed_c.hex", c_signed_hex);
        if (a_signed_hex[0] === 8'hxx) begin
            $readmemh("sys_signed_a.hex", a_signed_hex);
            $readmemh("sys_signed_b.hex", b_signed_hex);
            $readmemh("sys_signed_c.hex", c_signed_hex);
        end

        $display("\n================================================================");
        $display("   SYSTOLIC ARRAY: Full-System End-to-End Verification          ");
        $display("   4x4 Output-Stationary | 8-bit signed | 100 MHz target         ");
        $display("================================================================\n");

        rst_n = 0; start = 0;
        host_we = 0; host_bank_sel = 0; host_addr = 0; host_wdata = 0;
        #25;
        rst_n = 1;
        #15;

        // =====================================================================
        // TEST 1: Sequential 1..16 x 1..16
        // Expected: C[i][j] = row_i . col_j of same matrix
        // C[0][0]=90, C[0][1]=100, ..., C[3][3]=600
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
        // TEST 2: Golden model signed & zero matrix (from systolic_golden_model.py)
        // Back-to-back from DONE state (checks pending_start mechanism)
        // =====================================================================
        for (i = 0; i < DEPTH; i = i + 1) begin
            a_vec[i] = $signed(a_signed_hex[i]);
            b_vec[i] = $signed(b_signed_hex[i]);
            c_exp[i] = $signed(c_signed_hex[i]);
        end
        run_and_verify("Test 2 (Signed & Zero - Golden Model)");

        // =====================================================================
        // TEST 3: Identity × Signed matrix (I*B = B)
        // A = identity matrix, B = signed test matrix from golden model
        // Expected C = B
        // =====================================================================
        // A = identity
        for (i = 0; i < DEPTH; i = i + 1)
            a_vec[i] = (i/N == i%N) ? 8'sd1 : 8'sd0;
        // B and expected C = same signed matrix
        a_vec[0]=1; a_vec[1]=0; a_vec[2]=0; a_vec[3]=0;
        a_vec[4]=0; a_vec[5]=1; a_vec[6]=0; a_vec[7]=0;
        a_vec[8]=0; a_vec[9]=0; a_vec[10]=1; a_vec[11]=0;
        a_vec[12]=0; a_vec[13]=0; a_vec[14]=0; a_vec[15]=1;

        b_vec[0]=3;  b_vec[1]=-2; b_vec[2]=4;  b_vec[3]=1;
        b_vec[4]=5;  b_vec[5]=0;  b_vec[6]=-3; b_vec[7]=2;
        b_vec[8]=-1; b_vec[9]=4;  b_vec[10]=2; b_vec[11]=-5;
        b_vec[12]=2; b_vec[13]=-1; b_vec[14]=0; b_vec[15]=3;

        // Expected = B (identity property)
        c_exp[0]=3;  c_exp[1]=-2; c_exp[2]=4;  c_exp[3]=1;
        c_exp[4]=5;  c_exp[5]=0;  c_exp[6]=-3; c_exp[7]=2;
        c_exp[8]=-1; c_exp[9]=4;  c_exp[10]=2; c_exp[11]=-5;
        c_exp[12]=2; c_exp[13]=-1; c_exp[14]=0; c_exp[15]=3;

        run_and_verify("Test 3 (Identity x Signed)");

        // =====================================================================
        // TEST 4: Extreme signed values (-128/127/0 alternating)
        // Back-to-back (3rd consecutive run from DONE)
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
        // Verifies that rst_n clears all accumulators and new compute is clean
        // =====================================================================
        // Apply reset while in DONE state
        @(negedge clk);
        rst_n = 0;
        #15;
        rst_n = 1;
        #10;

        // After reset: load zero matrix A, identity B → expect all zeros
        for (i = 0; i < DEPTH; i = i + 1) begin
            a_vec[i] = 8'sd0;
            b_vec[i] = (i/N == i%N) ? 8'sd1 : 8'sd0;
        end
        for (i = 0; i < DEPTH; i = i + 1)
            c_exp[i] = 24'sd0;

        run_and_verify("Test 5 (Reset then restart - Zero x Identity)");

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n================================================================");
        $display("   SYSTOLIC TOP SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================");
        if (fail_count == 0)
            $display("   *** ALL %0d ELEMENT CHECKS PASSED (100%% BIT-ACCURATE) ***\n",
                     pass_count);
        else
            $display("   *** VERIFICATION FAILED: %0d mismatches detected ***\n", fail_count);
        $finish;
    end

endmodule
