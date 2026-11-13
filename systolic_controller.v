// =============================================================================
// File: systolic_controller.v
// Module: systolic_controller
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   5-State FSM Controller for the 2D Output-Stationary Systolic Array.
//
//   States:
//     IDLE    (3'd0): Wait for start pulse; busy=0.
//     LOAD    (3'd1): Clear array/feeder and stream N*N elements from SRAM A & B
//                     into the input feeder's staging buffers (N*N + 1 cycles,
//                     accounting for 1-cycle synchronous SRAM read latency).
//     COMPUTE (3'd2): Enable skewed feeding for 2*N - 1 cycles (cycles 0..2N-2)
//                     so A[i][k] and B[k][j] meet at PE(i,j) at cycle i+j+k.
//     DRAIN   (3'd3): Wait N cycles for the final wavefront to traverse the array
//                     to PE(N-1,N-1), then write back all N*N stationary PE
//                     outputs into single-port SRAM Bank C (N + N*N cycles).
//     DONE    (3'd4): Assert done=1 and release bus (busy=0) until a new
//                     operation is requested, then return to IDLE.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module systolic_controller #(
    parameter N          = 4,
    parameter DEPTH      = N * N,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,            // active-low async reset
    input  wire                  start,            // start matrix multiplication
    output reg                   done,             // high when all outputs are in SRAM C
    output reg                   busy,             // high during LOAD, COMPUTE, DRAIN

    // Array & Feeder control
    output reg                   array_clear,      // 1-cycle clear pulse to systolic_array
    output reg                   feeder_clear,     // 1-cycle clear pulse to input_feeder
    output reg                   feeder_load_en,   // latch SRAM data into feeder buffers
    output reg  [ADDR_WIDTH-1:0] feeder_load_addr, // staging index 0..DEPTH-1
    output reg                   feeder_enable,    // enable skewed systolic feeding

    // Near-Memory SRAM Bank interfaces
    output reg  [ADDR_WIDTH-1:0] sram_a_addr,
    output reg  [ADDR_WIDTH-1:0] sram_b_addr,
    output reg  [ADDR_WIDTH-1:0] sram_c_addr,
    output reg                   sram_c_we,
    output reg  [ADDR_WIDTH-1:0] c_drain_idx,      // selects which PE(r,c) writes to SRAM C

    // Debug / waveform visibility
    output wire [2:0]            state_out
);

    // FSM State Encoding
    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_LOAD    = 3'd1;
    localparam [2:0] STATE_COMPUTE = 3'd2;
    localparam [2:0] STATE_DRAIN   = 3'd3;
    localparam [2:0] STATE_DONE    = 3'd4;

    // Timing constants derived from N and synchronous SRAM latency:
    //   LOAD:    1 cycle SRAM read address setup + DEPTH cycles of element capture
    //   COMPUTE: 2*N - 1 cycles for skewed matrix boundaries (t = 0 .. 2N-2)
    //   DRAIN:   N cycles to flush wavefront through PE(N-1,N-1) + DEPTH cycles writeback
    localparam integer LOAD_LAST_IDX      = DEPTH;          // 16 when N=4
    localparam integer LOAD_ADDR_LAST     = DEPTH - 1;      // 15 when N=4
    localparam integer COMPUTE_LAST_IDX   = 2 * N - 2;      // 6  when N=4 (7 cycles)
    localparam integer ARRAY_DRAIN_LAST   = N - 1;          // 3  when N=4 (4 cycles)
    localparam integer DRAIN_LAST_IDX     = N + DEPTH - 1;  // 19 when N=4 (20 cycles)

    reg [2:0]            state;
    reg                  start_d;
    reg                  pending_start;
    reg [ADDR_WIDTH:0]   load_cnt;
    reg [ADDR_WIDTH:0]   compute_cnt;
    reg [ADDR_WIDTH+1:0] drain_cnt;

    wire [31:0] load_cnt_32    = {{(31-ADDR_WIDTH){1'b0}}, load_cnt};
    wire [31:0] compute_cnt_32 = {{(31-ADDR_WIDTH){1'b0}}, compute_cnt};
    wire [31:0] drain_cnt_32   = {{(30-ADDR_WIDTH){1'b0}}, drain_cnt};

    wire start_pulse = start & ~start_d;

    assign state_out = state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= STATE_IDLE;
            start_d          <= 1'b0;
            pending_start    <= 1'b0;
            done             <= 1'b0;
            busy             <= 1'b0;
            array_clear      <= 1'b0;
            feeder_clear     <= 1'b0;
            feeder_load_en   <= 1'b0;
            feeder_load_addr <= {ADDR_WIDTH{1'b0}};
            feeder_enable    <= 1'b0;
            sram_a_addr      <= {ADDR_WIDTH{1'b0}};
            sram_b_addr      <= {ADDR_WIDTH{1'b0}};
            sram_c_addr      <= {ADDR_WIDTH{1'b0}};
            sram_c_we        <= 1'b0;
            c_drain_idx      <= {ADDR_WIDTH{1'b0}};
            load_cnt         <= {(ADDR_WIDTH+1){1'b0}};
            compute_cnt      <= {(ADDR_WIDTH+1){1'b0}};
            drain_cnt        <= {(ADDR_WIDTH+2){1'b0}};
        end else begin
            start_d      <= start;
            // Default 1-cycle clear pulses to 0
            array_clear  <= 1'b0;
            feeder_clear <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    done           <= 1'b0;
                    feeder_load_en <= 1'b0;
                    feeder_enable  <= 1'b0;
                    sram_c_we      <= 1'b0;

                    if (start_pulse || pending_start) begin
                        pending_start    <= 1'b0;
                        busy             <= 1'b1;
                        array_clear      <= 1'b1;
                        feeder_clear     <= 1'b1;
                        sram_a_addr      <= {ADDR_WIDTH{1'b0}};
                        sram_b_addr      <= {ADDR_WIDTH{1'b0}};
                        feeder_load_addr <= {ADDR_WIDTH{1'b0}};
                        load_cnt         <= {(ADDR_WIDTH+1){1'b0}};
                        state            <= STATE_LOAD;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                STATE_LOAD: begin
                    if (load_cnt_32 < LOAD_LAST_IDX) begin
                        // Capture SRAM output on next edge (1-cycle SRAM read latency)
                        feeder_load_en   <= 1'b1;
                        feeder_load_addr <= load_cnt[ADDR_WIDTH-1:0];
                        if (load_cnt_32 < LOAD_ADDR_LAST) begin
                            sram_a_addr <= load_cnt[ADDR_WIDTH-1:0] + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                            sram_b_addr <= load_cnt[ADDR_WIDTH-1:0] + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        end
                        load_cnt <= load_cnt + 1'b1;
                    end else begin
                        // load_cnt == DEPTH: final element (DEPTH-1) captured on this edge
                        feeder_load_en <= 1'b0;
                        feeder_enable  <= 1'b1;
                        compute_cnt    <= {(ADDR_WIDTH+1){1'b0}};
                        state          <= STATE_COMPUTE;
                    end
                end

                STATE_COMPUTE: begin
                    if (compute_cnt_32 < COMPUTE_LAST_IDX) begin
                        compute_cnt <= compute_cnt + 1'b1;
                    end else begin
                        // Final skewed boundary inputs driven on this cycle; begin draining
                        feeder_enable <= 1'b0;
                        drain_cnt     <= {(ADDR_WIDTH+2){1'b0}};
                        state         <= STATE_DRAIN;
                    end
                end

                STATE_DRAIN: begin
                    if (drain_cnt_32 < ARRAY_DRAIN_LAST) begin
                        // Wait for wavefront to finish propagating to PE(N-1, N-1)
                        sram_c_we <= 1'b0;
                        drain_cnt <= drain_cnt + 1'b1;
                    end else if (drain_cnt_32 == ARRAY_DRAIN_LAST) begin
                        // PE(N-1,N-1) updates on this posedge; start SRAM C writeback next cycle
                        sram_c_we   <= 1'b1;
                        sram_c_addr <= {ADDR_WIDTH{1'b0}};
                        c_drain_idx <= {ADDR_WIDTH{1'b0}};
                        drain_cnt   <= drain_cnt + 1'b1;
                    end else if (drain_cnt_32 < DRAIN_LAST_IDX) begin
                        // Write C[0..DEPTH-2] sequentially into SRAM C
                        sram_c_we   <= 1'b1;
                        sram_c_addr <= sram_c_addr + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        c_drain_idx <= c_drain_idx + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        drain_cnt   <= drain_cnt + 1'b1;
                    end else begin
                        // Final element C[DEPTH-1] written on this posedge
                        sram_c_we <= 1'b0;
                        done      <= 1'b1;
                        busy      <= 1'b0;
                        state     <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    busy <= 1'b0;
                    if (start_pulse) begin
                        done          <= 1'b0;
                        pending_start <= 1'b1;
                        state         <= STATE_IDLE;
                    end else begin
                        done <= 1'b1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
