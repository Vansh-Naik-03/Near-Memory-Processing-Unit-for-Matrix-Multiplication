// NMPU top: connects 3 memories (A, B, C), one PE, and the FSM.
//   busy = 0 -> host controls the memories (load A, B / read C)
//   busy = 1 -> FSM controls the memories
`timescale 1ns / 1ps

module nmpu_top #(
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

    // ---------- wires between blocks ----------
    wire [ADDR_WIDTH-1:0] fsm_a_addr, fsm_b_addr, fsm_c_addr;
    wire                  fsm_c_we;
    wire                  pe_clear, pe_enable;

    wire [DATA_WIDTH-1:0] a_dout, b_dout;
    wire [ACC_WIDTH-1:0]  c_dout;
    wire signed [ACC_WIDTH-1:0] pe_acc;

    // ---------- who controls each memory? (busy decides) ----------
    // Memory A: FSM only reads it, host can write it
    wire [ADDR_WIDTH-1:0] a_addr = busy ? fsm_a_addr : host_addr;
    wire                  a_we   = !busy && host_we && (host_bank_sel == 2'b00);

    // Memory B: same idea
    wire [ADDR_WIDTH-1:0] b_addr = busy ? fsm_b_addr : host_addr;
    wire                  b_we   = !busy && host_we && (host_bank_sel == 2'b01);

    // Memory C: FSM writes the PE result, host can read (or write)
    wire [ADDR_WIDTH-1:0] c_addr = busy ? fsm_c_addr : host_addr;
    wire                  c_we   = busy ? fsm_c_we
                                        : (host_we && (host_bank_sel == 2'b10));
    wire [ACC_WIDTH-1:0]  c_din  = busy ? pe_acc : host_wdata;

    // ---------- what the host reads back ----------
    // A and B are 8-bit, so sign-extend them to 24 bits
    assign host_rdata =
        (host_bank_sel == 2'b00) ? {{(ACC_WIDTH-DATA_WIDTH){a_dout[DATA_WIDTH-1]}}, a_dout} :
        (host_bank_sel == 2'b01) ? {{(ACC_WIDTH-DATA_WIDTH){b_dout[DATA_WIDTH-1]}}, b_dout} :
                                   c_dout;

    // ---------- the three memories ----------
    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_a (
        .clk(clk), .rst_n(rst_n), .we(a_we), .addr(a_addr),
        .din(host_wdata[DATA_WIDTH-1:0]), .dout(a_dout)
    );

    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_b (
        .clk(clk), .rst_n(rst_n), .we(b_we), .addr(b_addr),
        .din(host_wdata[DATA_WIDTH-1:0]), .dout(b_dout)
    );

    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(ACC_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_c (
        .clk(clk), .rst_n(rst_n), .we(c_we), .addr(c_addr),
        .din(c_din), .dout(c_dout)
    );

    // ---------- the compute unit ----------
    pe #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pe (
        .clk(clk), .rst_n(rst_n),
        .clear(pe_clear), .enable(pe_enable),
        .a_in(a_dout), .b_in(b_dout),
        .reg_a_out(), .reg_b_out(),
        .acc_out(pe_acc)
    );

    // ---------- the controller ----------
    fsm_controller #(.N(N), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_fsm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .done(done), .busy(busy),
        .sram_a_addr(fsm_a_addr), .sram_b_addr(fsm_b_addr),
        .sram_c_addr(fsm_c_addr), .sram_c_we(fsm_c_we),
        .pe_clear(pe_clear), .pe_enable(pe_enable),
        .cnt_i_out(), .cnt_j_out(), .cnt_k_out()
    );

endmodule
