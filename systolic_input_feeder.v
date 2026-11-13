// =============================================================================
// File: systolic_input_feeder.v
// Module: systolic_input_feeder
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Input staging buffer and skewed feeder for the 2D Output-Stationary
//   Systolic Array.
//
//   Supports two loading modes:
//     1. Sequential load (load_en=1): loads 1 element per cycle from SRAM A & B
//        into internal N x N staging registers (handles single-port SRAM bandwidth).
//     2. Parallel load (load_parallel=1): loads full N x N matrices in 1 cycle
//        for standalone array simulation/testing.
//
//   Skewed Feeding Schedule (for t = 0 .. 2*N - 2, i.e. 0 .. 6 when N = 4):
//     - A[i][k] enters row i at cycle t = k + i  (active for i <= t < i + N)
//     - B[k][j] enters col j at cycle t = k + j  (active for j <= t < j + N)
//
//   Cycle-by-Cycle Schedule for N = 4:
//     t=0: Row0=A00          | Col0=B00
//     t=1: Row0=A01,Row1=A10 | Col0=B10,Col1=B01
//     t=2: Row0=A02,Row1=A11,Row2=A20 | Col0=B20,Col1=B11,Col2=B02
//     t=3: Row0=A03,Row1=A12,Row2=A21,Row3=A30 | Col0=B30,Col1=B21,Col2=B12,Col3=B03
//     t=4: Row1=A13,Row2=A22,Row3=A31 | Col1=B31,Col2=B22,Col3=B13
//     t=5: Row2=A23,Row3=A32 | Col2=B32,Col3=B23
//     t=6: Row3=A33          | Col3=B33
//     t>=7 (DRAIN): outputs driven to 0 with valid=0
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module systolic_input_feeder #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = N * N,
    parameter ADDR_WIDTH = 4
)(
    input  wire                        clk,
    input  wire                        rst_n,         // active-low async reset
    input  wire                        clear,         // reset feed counter & outputs

    // Sequential load interface (from SRAM Bank A & Bank B)
    input  wire                        load_en,
    input  wire [ADDR_WIDTH-1:0]       load_addr,
    input  wire signed [DATA_WIDTH-1:0] a_load_data,
    input  wire signed [DATA_WIDTH-1:0] b_load_data,

    // Optional parallel load interface (for direct testbench use)
    input  wire                        load_parallel,
    input  wire [DEPTH*DATA_WIDTH-1:0] a_matrix_in,
    input  wire [DEPTH*DATA_WIDTH-1:0] b_matrix_in,

    // Feeding control
    input  wire                        feed_enable,   // assert during COMPUTE

    // Skewed outputs to systolic_array left & top boundaries
    output reg  [N*DATA_WIDTH-1:0]     a_out,
    output reg  [N*DATA_WIDTH-1:0]     b_out,
    output reg  [N-1:0]                a_valid_out,
    output reg  [N-1:0]                b_valid_out,
    output wire                        feed_done
);

    localparam [ADDR_WIDTH:0] TOTAL_FEED_CYCLES = 2 * N - 1;

    // Staging register files for Matrix A and Matrix B (row-major)
    reg signed [DATA_WIDTH-1:0] a_buf [0:DEPTH-1];
    reg signed [DATA_WIDTH-1:0] b_buf [0:DEPTH-1];

    reg [ADDR_WIDTH:0] cycle_cnt;
    wire [31:0]        cyc_ext = {{(31-ADDR_WIDTH){1'b0}}, cycle_cnt};
    integer idx;

    assign feed_done = (cycle_cnt >= TOTAL_FEED_CYCLES);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                a_buf[idx] <= {DATA_WIDTH{1'b0}};
                b_buf[idx] <= {DATA_WIDTH{1'b0}};
            end
            cycle_cnt   <= {(ADDR_WIDTH+1){1'b0}};
            a_out       <= {(N*DATA_WIDTH){1'b0}};
            b_out       <= {(N*DATA_WIDTH){1'b0}};
            a_valid_out <= {N{1'b0}};
            b_valid_out <= {N{1'b0}};
        end else if (clear) begin
            cycle_cnt   <= {(ADDR_WIDTH+1){1'b0}};
            a_out       <= {(N*DATA_WIDTH){1'b0}};
            b_out       <= {(N*DATA_WIDTH){1'b0}};
            a_valid_out <= {N{1'b0}};
            b_valid_out <= {N{1'b0}};
        end else begin
            // Stage 1: Load operands into local staging buffers
            if (load_parallel) begin
                for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                    a_buf[idx] <= $signed(a_matrix_in[idx*DATA_WIDTH +: DATA_WIDTH]);
                    b_buf[idx] <= $signed(b_matrix_in[idx*DATA_WIDTH +: DATA_WIDTH]);
                end
            end else if (load_en) begin
                a_buf[load_addr] <= a_load_data;
                b_buf[load_addr] <= b_load_data;
            end

            // Stage 2: Drive skewed inputs onto the systolic array boundaries
            if (feed_enable && (cycle_cnt < TOTAL_FEED_CYCLES)) begin
                for (idx = 0; idx < N; idx = idx + 1) begin
                    // Row idx receives A[idx][cycle_cnt - idx] when idx <= cycle_cnt < idx + N
                    if ((cyc_ext >= idx) && (cyc_ext < (idx + N))) begin
                        a_out[idx*DATA_WIDTH +: DATA_WIDTH] <= a_buf[idx*N + (cyc_ext - idx)];
                        a_valid_out[idx] <= 1'b1;
                    end else begin
                        a_out[idx*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                        a_valid_out[idx] <= 1'b0;
                    end

                    // Column idx receives B[cycle_cnt - idx][idx] when idx <= cycle_cnt < idx + N
                    if ((cyc_ext >= idx) && (cyc_ext < (idx + N))) begin
                        b_out[idx*DATA_WIDTH +: DATA_WIDTH] <= b_buf[(cyc_ext - idx)*N + idx];
                        b_valid_out[idx] <= 1'b1;
                    end else begin
                        b_out[idx*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                        b_valid_out[idx] <= 1'b0;
                    end
                end
                cycle_cnt <= cycle_cnt + 1'b1;
            end else begin
                // Drain or idle: deassert valids and drive zeros
                a_out       <= {(N*DATA_WIDTH){1'b0}};
                b_out       <= {(N*DATA_WIDTH){1'b0}};
                a_valid_out <= {N{1'b0}};
                b_valid_out <= {N{1'b0}};
            end
        end
    end

endmodule

`default_nettype wire
