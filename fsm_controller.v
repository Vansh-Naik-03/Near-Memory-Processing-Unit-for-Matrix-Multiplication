// =============================================================================
// File: fsm_controller.v
// Module: fsm_controller
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Control Unit (FSM) for Near-Memory Matrix Multiplication.
//   Manages:
//     - 3-level nested loop counters (i, j, k) for N x N matrix multiplication
//     - Address generation for SRAM A, SRAM B, and SRAM C
//     - Synchronous SRAM read/write control signals
//     - PE array clear, enable, and accumulation control
//     - START / DONE handshake interface with Host
// =============================================================================

`timescale 1ns / 1ps

module fsm_controller #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24,
    parameter ADDR_WIDTH = 4   // clog2(N*N) = clog2(16) = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start,           // Start pulse from Host
    output reg                    done,            // High when matrix C is fully computed
    output reg                    busy,            // High during computation

    // Memory control signals for Near-Memory SRAM banks
    output reg  [ADDR_WIDTH-1:0]  sram_a_addr,
    output reg  [ADDR_WIDTH-1:0]  sram_b_addr,
    output reg  [ADDR_WIDTH-1:0]  sram_c_addr,
    output reg                    sram_c_we,

    // PE control signals
    output reg                    pe_clear,        // Clear PE accumulator before new element
    output reg                    pe_enable,       // Enable MAC step
    output reg  [ADDR_WIDTH-1:0]  cnt_i_out,       // Current row index
    output reg  [ADDR_WIDTH-1:0]  cnt_j_out,       // Current col index
    output reg  [ADDR_WIDTH-1:0]  cnt_k_out        // Current inner product index
);

    // State definitions
    localparam [2:0]
        ST_IDLE     = 3'd0,
        ST_INIT_ELEM= 3'd1,
        ST_FETCH    = 3'd2,
        ST_MAC      = 3'd3,
        ST_WRITE_C  = 3'd4,
        ST_NEXT_ELEM= 3'd5,
        ST_DONE     = 3'd6;

    reg [2:0] state;

    // Loop counters (i: row of A/C, j: col of B/C, k: dot-product index)
    reg [$clog2(N):0] i_cnt;
    reg [$clog2(N):0] j_cnt;
    reg [$clog2(N):0] k_cnt;

    // Expose internal counters for monitoring/debugging
    always @(*) begin
        cnt_i_out = i_cnt[ADDR_WIDTH-1:0];
        cnt_j_out = j_cnt[ADDR_WIDTH-1:0];
        cnt_k_out = k_cnt[ADDR_WIDTH-1:0];
    end

    // Sequential FSM logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            done        <= 1'b0;
            busy        <= 1'b0;
            sram_a_addr <= {ADDR_WIDTH{1'b0}};
            sram_b_addr <= {ADDR_WIDTH{1'b0}};
            sram_c_addr <= {ADDR_WIDTH{1'b0}};
            sram_c_we   <= 1'b0;
            pe_clear    <= 1'b0;
            pe_enable   <= 1'b0;
            i_cnt       <= 0;
            j_cnt       <= 0;
            k_cnt       <= 0;
        end else begin
            // Default single-cycle pulses
            pe_clear  <= 1'b0;
            pe_enable <= 1'b0;
            sram_c_we <= 1'b0;

            case (state)

                // -------------------------------------------------------------
                // ST_IDLE: Wait for Host start pulse
                // -------------------------------------------------------------
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        i_cnt <= 0;
                        j_cnt <= 0;
                        k_cnt <= 0;
                        state <= ST_INIT_ELEM;
                    end else begin
                        busy  <= 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // ST_INIT_ELEM: Clear PE accumulator for new element C[i, j]
                // -------------------------------------------------------------
                ST_INIT_ELEM: begin
                    pe_clear    <= 1'b1;
                    k_cnt       <= 0;
                    // Present address for k=0
                    sram_a_addr <= (i_cnt * N) + 0;
                    sram_b_addr <= (0 * N) + j_cnt;
                    state       <= ST_FETCH;
                end

                // -------------------------------------------------------------
                // ST_FETCH: Wait 1 cycle for SRAM synchronous read latency
                // -------------------------------------------------------------
                ST_FETCH: begin
                    // On next cycle, SRAM read data will be stable at PE inputs
                    state <= ST_MAC;
                end

                // -------------------------------------------------------------
                // ST_MAC: Execute Multiply-Accumulate in PE
                // -------------------------------------------------------------
                ST_MAC: begin
                    pe_enable <= 1'b1;

                    if (k_cnt == N - 1) begin
                        // Inner dot product complete for C[i, j]
                        state <= ST_WRITE_C;
                    end else begin
                        // Advance k and request next pair of operands
                        k_cnt       <= k_cnt + 1;
                        sram_a_addr <= (i_cnt * N) + (k_cnt + 1);
                        sram_b_addr <= ((k_cnt + 1) * N) + j_cnt;
                        state       <= ST_FETCH;
                    end
                end

                // -------------------------------------------------------------
                // ST_WRITE_C: Store accumulated result into SRAM C
                // -------------------------------------------------------------
                ST_WRITE_C: begin
                    sram_c_we   <= 1'b1;
                    sram_c_addr <= (i_cnt * N) + j_cnt;
                    state       <= ST_NEXT_ELEM;
                end

                // -------------------------------------------------------------
                // ST_NEXT_ELEM: Advance (i, j) counters to next matrix cell
                // -------------------------------------------------------------
                ST_NEXT_ELEM: begin
                    if (i_cnt == N - 1 && j_cnt == N - 1) begin
                        // All N x N elements computed!
                        state <= ST_DONE;
                    end else begin
                        if (j_cnt == N - 1) begin
                            j_cnt <= 0;
                            i_cnt <= i_cnt + 1;
                        end else begin
                            j_cnt <= j_cnt + 1;
                        end
                        state <= ST_INIT_ELEM;
                    end
                end

                // -------------------------------------------------------------
                // ST_DONE: Signal completion to Host
                // -------------------------------------------------------------
                ST_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;

            endcase
        end
    end

endmodule
