// =============================================================================
// File: nmpu_top.v
// Module: nmpu_top
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Top-Level Integration of the Near-Memory Processing Unit (NMPU).
//   Contains:
//     - On-Chip Near-Memory SRAM Bank A (Matrix A)
//     - On-Chip Near-Memory SRAM Bank B (Matrix B)
//     - On-Chip Near-Memory SRAM Bank C (Result Matrix C)
//     - Processing Element (PE) / MAC Compute Core with accumulator feedback
//     - NMPU FSM Control Unit with autonomous (i, j, k) address generation
//     - External Host Interface (for loading A & B, triggering START, reading C)
//
// Conforms to ASIC standard cell flow (active-low rst_n, glitch-free muxing).
// =============================================================================

`timescale 1ns / 1ps

module nmpu_top #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24,
    parameter DEPTH      = N * N,            // 16 elements per matrix
    parameter ADDR_WIDTH = 4                 // clog2(16)
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // Host Control Signals
    input  wire                          start,       // Pulse to initiate matrix multiplication
    output wire                          done,        // Asserted high when C is complete
    output wire                          busy,        // High while computation is running

    // Host Memory Interface (active when busy == 0)
    input  wire                          host_we,        // Host write enable
    input  wire [1:0]                    host_bank_sel,  // 2'b00: SRAM A, 2'b01: SRAM B, 2'b10: SRAM C
    input  wire [ADDR_WIDTH-1:0]          host_addr,      // Host address (0..N*N-1)
    input  wire signed [ACC_WIDTH-1:0]   host_wdata,     // Host write data
    output wire signed [ACC_WIDTH-1:0]   host_rdata      // Host read data from selected bank
);

    // =========================================================================
    // Internal Interconnect Wires
    // =========================================================================

    // FSM <-> Memory Control Signals
    wire [ADDR_WIDTH-1:0] fsm_sram_a_addr;
    wire [ADDR_WIDTH-1:0] fsm_sram_b_addr;
    wire [ADDR_WIDTH-1:0] fsm_sram_c_addr;
    wire                  fsm_sram_c_we;

    // FSM <-> PE Control Signals
    wire                  pe_clear;
    wire                  pe_enable;

    // SRAM Data outputs
    wire [DATA_WIDTH-1:0] sram_a_dout;
    wire [DATA_WIDTH-1:0] sram_b_dout;
    wire [ACC_WIDTH-1:0]  sram_c_dout;

    // PE Accumulator output
    wire signed [ACC_WIDTH-1:0] pe_acc_out;

    // =========================================================================
    // Memory Multiplexing (Near-Memory vs. Host Bus)
    // When busy == 1: FSM has exclusive near-memory access (no bus overhead)
    // When busy == 0: Host has access to load A & B and read result C
    // =========================================================================

    // SRAM A multiplexing
    wire [ADDR_WIDTH-1:0] mux_a_addr = busy ? fsm_sram_a_addr : host_addr;
    wire                  mux_a_we   = busy ? 1'b0 : (host_we && (host_bank_sel == 2'b00));
    wire [DATA_WIDTH-1:0] mux_a_din  = host_wdata[DATA_WIDTH-1:0];

    // SRAM B multiplexing
    wire [ADDR_WIDTH-1:0] mux_b_addr = busy ? fsm_sram_b_addr : host_addr;
    wire                  mux_b_we   = busy ? 1'b0 : (host_we && (host_bank_sel == 2'b01));
    wire [DATA_WIDTH-1:0] mux_b_din  = host_wdata[DATA_WIDTH-1:0];

    // SRAM C multiplexing
    wire [ADDR_WIDTH-1:0] mux_c_addr = busy ? fsm_sram_c_addr : host_addr;
    wire                  mux_c_we   = busy ? fsm_sram_c_we   : (host_we && (host_bank_sel == 2'b10));
    wire [ACC_WIDTH-1:0]  mux_c_din  = busy ? pe_acc_out      : host_wdata;

    // Host read multiplexer
    assign host_rdata = (host_bank_sel == 2'b00) ? {{(ACC_WIDTH-DATA_WIDTH){sram_a_dout[DATA_WIDTH-1]}}, sram_a_dout} :
                        (host_bank_sel == 2'b01) ? {{(ACC_WIDTH-DATA_WIDTH){sram_b_dout[DATA_WIDTH-1]}}, sram_b_dout} :
                                                   sram_c_dout;

    // =========================================================================
    // On-Chip SRAM Banks (Near Memory)
    // =========================================================================

    // Bank A: Holds Matrix A (N x N elements, 8-bit signed)
    sram_bank #(
        .DEPTH     (DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sram_a (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (mux_a_we),
        .addr (mux_a_addr),
        .din  (mux_a_din),
        .dout (sram_a_dout)
    );

    // Bank B: Holds Matrix B (N x N elements, 8-bit signed)
    sram_bank #(
        .DEPTH     (DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sram_b (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (mux_b_we),
        .addr (mux_b_addr),
        .din  (mux_b_din),
        .dout (sram_b_dout)
    );

    // Bank C: Holds Result Matrix C (N x N elements, full precision 24-bit signed)
    sram_bank #(
        .DEPTH     (DEPTH),
        .DATA_WIDTH(ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sram_c (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (mux_c_we),
        .addr (mux_c_addr),
        .din  (mux_c_din),
        .dout (sram_c_dout)
    );

    // =========================================================================
    // Compute Core: Processing Element (PE)
    // =========================================================================
    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_pe (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (pe_clear),
        .enable   (pe_enable),
        .a_in     (sram_a_dout),
        .b_in     (sram_b_dout),
        .reg_a_out(),
        .reg_b_out(),
        .acc_out  (pe_acc_out)
    );

    // =========================================================================
    // Control Unit: Autonomous FSM Controller
    // =========================================================================
    fsm_controller #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_fsm (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .done       (done),
        .busy       (busy),
        .sram_a_addr(fsm_sram_a_addr),
        .sram_b_addr(fsm_sram_b_addr),
        .sram_c_addr(fsm_sram_c_addr),
        .sram_c_we  (fsm_sram_c_we),
        .pe_clear   (pe_clear),
        .pe_enable  (pe_enable),
        .cnt_i_out  (),
        .cnt_j_out  (),
        .cnt_k_out  ()
    );

endmodule
