// =============================================================================
// File: tb_systolic_array.v
// Module: tb_systolic_array
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Testbench for the 4x4 2D Output-Stationary Systolic Array (systolic_array.v)
//   paired with systolic_input_feeder.v:
//     - Test 1: 1..16 x 1..16 test matrix + cycle-by-cycle wavefront check
//     - Test 2: Signed negative & zero matrix (matches golden_model.py)
//     - Test 3: Extreme signed values (-128, 127, 0) after synchronous clear
//     - Test 4: Reset behavior
// =============================================================================

`timescale 1ns / 1ps

module tb_systolic_array;

    localparam N          = 4;
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 24;
    localparam DEPTH      = N * N;

    reg                        clk = 0;
    reg                        rst_n;
    reg                        clear;
    reg                        load_parallel;
    reg                        feed_enable;
    reg  [DEPTH*DATA_WIDTH-1:0] a_mat;
    reg  [DEPTH*DATA_WIDTH-1:0] b_mat;

    wire [N*DATA_WIDTH-1:0]    skew_a;
    wire [N*DATA_WIDTH-1:0]    skew_b;
    wire [N-1:0]               skew_a_valid;
    wire [N-1:0]               skew_b_valid;
    wire                       feed_done;
    wire [DEPTH*ACC_WIDTH-1:0] c_out;

    integer pass_count = 0;
    integer fail_count = 0;
    integer r, c, cyc;

    reg signed [ACC_WIDTH-1:0] expected_c [0:DEPTH-1];

    systolic_input_feeder #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(4)
    ) u_feeder (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (clear),
        .load_en      (1'b0),
        .load_addr    (4'd0),
        .a_load_data  (8'sd0),
        .b_load_data  (8'sd0),
        .load_parallel(load_parallel),
        .a_matrix_in  (a_mat),
        .b_matrix_in  (b_mat),
        .feed_enable  (feed_enable),
        .a_out        (skew_a),
        .b_out        (skew_b),
        .a_valid_out  (skew_a_valid),
        .b_valid_out  (skew_b_valid),
        .feed_done    (feed_done)
    );

    systolic_array #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (clear),
        .a_in      (skew_a),
        .b_in      (skew_b),
        .a_valid_in(skew_a_valid),
        .b_valid_in(skew_b_valid),
        .c_out     (c_out)
    );

    always #5 clk = ~clk;

    task set_mat_element;
        inout [DEPTH*DATA_WIDTH-1:0] mat;
        input integer idx;
        input signed [DATA_WIDTH-1:0] val;
        begin
            mat[idx*DATA_WIDTH +: DATA_WIDTH] = val;
        end
    endtask

    function signed [ACC_WIDTH-1:0] get_c;
        input integer idx;
        begin
            get_c = $signed(c_out[idx*ACC_WIDTH +: ACC_WIDTH]);
        end
    endfunction

    task run_systolic_multiply;
        input [255:0] test_name;
        begin
            // 1. Clear array & feeder
            @(negedge clk);
            clear = 1;
            load_parallel = 0;
            feed_enable = 0;
            @(posedge clk); #1;

            // 2. Parallel load matrices into feeder staging buffers
            @(negedge clk);
            clear = 0;
            load_parallel = 1;
            @(posedge clk); #1;

            // 3. Feed skewed inputs for 2*N - 1 = 7 cycles
            @(negedge clk);
            load_parallel = 0;
            feed_enable = 1;
            for (cyc = 0; cyc < 2*N - 1; cyc = cyc + 1) begin
                @(posedge clk); #1;
            end

            // 4. Drain for N = 4 cycles
            @(negedge clk);
            feed_enable = 0;
            for (cyc = 0; cyc < N; cyc = cyc + 1) begin
                @(posedge clk); #1;
            end

            // 5. Verify all 16 output elements
            $display("--- Checking %0s ---", test_name);
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    if (get_c(r*N + c) === expected_c[r*N + c]) begin
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] %0s C[%0d][%0d]: got %0d, expected %0d",
                                 test_name, r, c, get_c(r*N + c), expected_c[r*N + c]);
                        fail_count = fail_count + 1;
                    end
                end
            end
        end
    endtask

    initial begin
        $display("==================================================");
        $display("   TESTBENCH: 4x4 Systolic Array (systolic_array) ");
        $display("==================================================");

        rst_n = 0; clear = 0; load_parallel = 0; feed_enable = 0;
        a_mat = 0; b_mat = 0;
        #12 rst_n = 1;

        // ---------------------------------------------------------------------
        // Test 1: 1..16 x 1..16 matrix
        // ---------------------------------------------------------------------
        for (r = 0; r < DEPTH; r = r + 1) begin
            set_mat_element(a_mat, r, r + 1);
            set_mat_element(b_mat, r, r + 1);
        end
        expected_c[0]  = 90;  expected_c[1]  = 100; expected_c[2]  = 110; expected_c[3]  = 120;
        expected_c[4]  = 202; expected_c[5]  = 228; expected_c[6]  = 254; expected_c[7]  = 280;
        expected_c[8]  = 314; expected_c[9]  = 356; expected_c[10] = 398; expected_c[11] = 440;
        expected_c[12] = 426; expected_c[13] = 484; expected_c[14] = 542; expected_c[15] = 600;

        run_systolic_multiply("Test 1 (1..16 x 1..16)");

        // Verify PE(0,0) vs PE(3,3) systolic wavefront timing explicitly
        @(negedge clk); clear = 1; @(posedge clk); #1;
        @(negedge clk); clear = 0; load_parallel = 1; @(posedge clk); #1;
        @(negedge clk); load_parallel = 0; feed_enable = 1;
        // Edge 0: feeder outputs t=0 (A00, B00); array hasn't sampled t=0 yet
        @(posedge clk); #1;
        // Edge 1..4: PE(0,0) completes after 4th sample (Edge 4) while PE(3,3) is still 0
        for (cyc = 0; cyc < 4; cyc = cyc + 1) begin
            @(posedge clk); #1;
        end
        if (get_c(0) === 24'sd90 && get_c(15) === 24'sd0) begin
            $display("[PASS] Wavefront timing verified: PE(0,0)=90 ready early while PE(3,3)=0");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Wavefront timing mismatch: PE(0,0)=%0d PE(3,3)=%0d", get_c(0), get_c(15));
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 2: Golden model signed negative & zero matrix
        // ---------------------------------------------------------------------
        // A = [[3,-2,4,1],[5,0,-3,2],[-1,4,2,-5],[2,-1,0,3]]
        set_mat_element(a_mat,  0,  3); set_mat_element(a_mat,  1, -2); set_mat_element(a_mat,  2,  4); set_mat_element(a_mat,  3,  1);
        set_mat_element(a_mat,  4,  5); set_mat_element(a_mat,  5,  0); set_mat_element(a_mat,  6, -3); set_mat_element(a_mat,  7,  2);
        set_mat_element(a_mat,  8, -1); set_mat_element(a_mat,  9,  4); set_mat_element(a_mat, 10,  2); set_mat_element(a_mat, 11, -5);
        set_mat_element(a_mat, 12,  2); set_mat_element(a_mat, 13, -1); set_mat_element(a_mat, 14,  0); set_mat_element(a_mat, 15,  3);

        // B = [[2,1,-3,4],[-4,3,2,0],[1,-2,5,-1],[0,4,-1,2]]
        set_mat_element(b_mat,  0,  2); set_mat_element(b_mat,  1,  1); set_mat_element(b_mat,  2, -3); set_mat_element(b_mat,  3,  4);
        set_mat_element(b_mat,  4, -4); set_mat_element(b_mat,  5,  3); set_mat_element(b_mat,  6,  2); set_mat_element(b_mat,  7,  0);
        set_mat_element(b_mat,  8,  1); set_mat_element(b_mat,  9, -2); set_mat_element(b_mat, 10,  5); set_mat_element(b_mat, 11, -1);
        set_mat_element(b_mat, 12,  0); set_mat_element(b_mat, 13,  4); set_mat_element(b_mat, 14, -1); set_mat_element(b_mat, 15,  2);

        expected_c[0]  =  18; expected_c[1]  =  -7; expected_c[2]  =   6; expected_c[3]  =  10;
        expected_c[4]  =   7; expected_c[5]  =  19; expected_c[6]  = -32; expected_c[7]  =  27;
        expected_c[8]  = -16; expected_c[9]  = -13; expected_c[10] =  26; expected_c[11] = -16;
        expected_c[12] =   8; expected_c[13] =  11; expected_c[14] = -11; expected_c[15] =  14;

        run_systolic_multiply("Test 2 (Signed & Zero)");

        // ---------------------------------------------------------------------
        // Test 3: Extreme signed values (-128 * -128, 0)
        // ---------------------------------------------------------------------
        for (r = 0; r < DEPTH; r = r + 1) begin
            set_mat_element(a_mat, r, (r % 2 == 0) ? -8'sd128 : 8'sd0);
            set_mat_element(b_mat, r, (r % 2 == 0) ? -8'sd128 : 8'sd127);
        end
        // Row 0 = [-128, 0, -128, 0], Row 1 = [-128, 0, -128, 0] ...
        // Col 0 = [-128, -128, -128, -128]^T, Col 1 = [127, 127, 127, 127]^T ...
        // Wait: b_mat[r] with r%2==0: B[0][0]=-128, B[0][1]=127, B[0][2]=-128, B[0][3]=127
        // B[1][0]=-128, B[1][1]=127, ... B[2][0]=-128, B[2][1]=127 ...
        // Row r%2==0 -> A[0]=[-128,0,-128,0], A[1]=[-128,0,-128,0] (since idx 4,6 even!)
        // So every C[i][even] = (-128)*(-128)*2 = 32768, every C[i][odd] = (-128)*(127)*2 = -32512
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                expected_c[r*N + c] = (c % 2 == 0) ? 24'sd32768 : -24'sd32512;
            end
        end
        run_systolic_multiply("Test 3 (Extreme -128/127/0)");
        

        // ---------------------------------------------------------------------
        // Test 4: Reset clears all 16 accumulators
        // ---------------------------------------------------------------------
        rst_n = 0;
        #10;
        for (r = 0; r < DEPTH; r = r + 1) begin
            if (get_c(r) === 24'sd0) pass_count = pass_count + 1;
            else begin
                $display("[FAIL] Reset did not clear C[%0d]: got %0d", r, get_c(r));
                fail_count = fail_count + 1;
            end
        end

        $display("==================================================");
        $display("   SYSTOLIC ARRAY SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display(">> SYSTOLIC_ARRAY.V & INPUT_FEEDER.V VERIFIED! <<\n");
        else
            $display(">> SYSTOLIC_ARRAY.V FAILED! <<\n");
        $finish;
    end

endmodule

