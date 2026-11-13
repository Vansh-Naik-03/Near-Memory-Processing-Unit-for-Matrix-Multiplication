// =============================================================================
// File: systolic_top.v
// Module: systolic_top
// Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
// Description:
//   Independent Top-Level Module for the 2D 4x4 Output-Stationary Systolic
//   Array Architecture.
//
//   Designed with the same external host/SRAM interface as nmpu_top.v so both
//   architectures can be independently simulated, synthesized, and compared in
//   terms of latency, throughput, area, timing, and power without modifying
//   any existing NMPU modules.
//
//   Architecture components:
//     - u_sram_a, u_sram_b, u_sram_c: Existing synchronous SRAM banks
//     - u_sys_ctrl: 5-state FSM controller (IDLE -> LOAD -> COMPUTE -> DRAIN -> DONE)
//     - u_feeder:   Input staging buffer & skewed boundary feeder
//     - u_array:    N x N (16 PEs) 2D Output-Stationary Systolic Array
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module systolic_top #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24,
    parameter DEPTH      = N * N,
    parameter ADDR_WIDTH = 4
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,
    output wire                         done,
    output wire                         busy,

    input  wire                         host_we,        // host write enable
    input  wire [1:0]                   host_bank_sel,  // 00 = A, 01 = B, 10 = C
    input  wire [ADDR_WIDTH-1:0]        host_addr,
    input  wire signed [ACC_WIDTH-1:0]  host_wdata,
    output wire signed [ACC_WIDTH-1:0]  host_rdata
);

    // ---------- Controller <-> SRAM / Feeder / Array wires ----------
    wire [ADDR_WIDTH-1:0] fsm_a_addr, fsm_b_addr, fsm_c_addr;
    wire                  fsm_c_we;
    wire [ADDR_WIDTH-1:0] c_drain_idx;

    wire                  array_clear, feeder_clear;
    wire                  feeder_load_en, feeder_enable;
    wire [ADDR_WIDTH-1:0] feeder_load_addr;

    // ---------- SRAM data buses ----------
    wire [DATA_WIDTH-1:0] a_dout, b_dout;
    wire [ACC_WIDTH-1:0]  c_dout;

    // ---------- Feeder <-> Systolic Array buses ----------
    wire [N*DATA_WIDTH-1:0]   skew_a_out, skew_b_out;
    wire [N-1:0]              skew_a_valid, skew_b_valid;
    wire [DEPTH*ACC_WIDTH-1:0] array_c_out;

    // Select stationary PE accumulator element during DRAIN writeback
    wire [ACC_WIDTH-1:0] c_drain_data = array_c_out[c_drain_idx*ACC_WIDTH +: ACC_WIDTH];

    // ---------- Memory arbitration (busy=0: Host, busy=1: Systolic Controller) ----------
    wire [ADDR_WIDTH-1:0] a_addr = busy ? fsm_a_addr : host_addr;
    wire                  a_we   = !busy && host_we && (host_bank_sel == 2'b00);

    wire [ADDR_WIDTH-1:0] b_addr = busy ? fsm_b_addr : host_addr;
    wire                  b_we   = !busy && host_we && (host_bank_sel == 2'b01);

    wire [ADDR_WIDTH-1:0] c_addr = busy ? fsm_c_addr : host_addr;
    wire                  c_we   = busy ? fsm_c_we
                                        : (host_we && (host_bank_sel == 2'b10));
    wire [ACC_WIDTH-1:0]  c_din  = busy ? c_drain_data : host_wdata[ACC_WIDTH-1:0];

    // Sign-extend 8-bit A/B reads to ACC_WIDTH on host readback
    assign host_rdata =
        (host_bank_sel == 2'b00) ? {{(ACC_WIDTH-DATA_WIDTH){a_dout[DATA_WIDTH-1]}}, a_dout} :
        (host_bank_sel == 2'b01) ? {{(ACC_WIDTH-DATA_WIDTH){b_dout[DATA_WIDTH-1]}}, b_dout} :
                                   $signed(c_dout);

//     ---------- Near-Memory SRAM Banks (reusing existing sram_bank.v) ----------
    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_a (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (a_we),
        .addr (a_addr),
        .din  (host_wdata[DATA_WIDTH-1:0]),
        .dout (a_dout)
    );

    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_b (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (b_we),
        .addr (b_addr),
        .din  (host_wdata[DATA_WIDTH-1:0]),
        .dout (b_dout)
    );

    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(ACC_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_c (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (c_we),
        .addr (c_addr),
        .din  (c_din),
        .dout (c_dout)
    );

    // ---------- 5-State Systolic Controller ----------
    systolic_controller #(
        .N         (N),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sys_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .done            (done),
        .busy            (busy),
        .array_clear     (array_clear),
        .feeder_clear    (feeder_clear),
        .feeder_load_en  (feeder_load_en),
        .feeder_load_addr(feeder_load_addr),
        .feeder_enable   (feeder_enable),
        .sram_a_addr     (fsm_a_addr),
        .sram_b_addr     (fsm_b_addr),
        .sram_c_addr     (fsm_c_addr),
        .sram_c_we       (fsm_c_we),
        .c_drain_idx     (c_drain_idx),
        .state_out       ()
    );

    // ---------- Input Staging & Temporal Skew Feeder ----------
    systolic_input_feeder #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_feeder (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (feeder_clear),
        .load_en      (feeder_load_en),
        .load_addr    (feeder_load_addr),
        .a_load_data  ($signed(a_dout)),
        .b_load_data  ($signed(b_dout)),
        .load_parallel(1'b0),
        .a_matrix_in  ({(DEPTH*DATA_WIDTH){1'b0}}),
        .b_matrix_in  ({(DEPTH*DATA_WIDTH){1'b0}}),
        .feed_enable  (feeder_enable),
        .a_out        (skew_a_out),
        .b_out        (skew_b_out),
        .a_valid_out  (skew_a_valid),
        .b_valid_out  (skew_b_valid),
        .feed_done    ()
    );

    // ---------- 4x4 Output-Stationary Systolic Array (16 PEs) ----------
    systolic_array #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_array (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (array_clear),
        .a_in      (skew_a_out),
        .b_in      (skew_b_out),
        .a_valid_in(skew_a_valid),
        .b_valid_in(skew_b_valid),
        .c_out     (array_c_out)
    );

endmodule

`default_nettype wire
