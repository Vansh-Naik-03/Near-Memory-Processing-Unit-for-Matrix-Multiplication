// NMPU top: connects 3 memories (A, B, C), one PE, and the FSM.
//   busy = 0 -> host controls the memories (load A, B / read C)
//   busy = 1 -> FSM controls the memories
//`timescale 1ns / 1ps

//module nmpu_top #(
//    parameter N          = 4,
//    parameter DATA_WIDTH = 8,
//    parameter ACC_WIDTH  = 24,
//    parameter DEPTH      = N * N,
//    parameter ADDR_WIDTH = 4
//)(
//    input  wire                         clk,
//    input  wire                         rst_n,

//    input  wire                         start,
//    output wire                         done,
//    output wire                         busy,

//    input  wire                         host_we,        // host write enable
//    input  wire [1:0]                   host_bank_sel,  // 00 = A, 01 = B, 10 = C
//    input  wire [ADDR_WIDTH-1:0]        host_addr,
//    input  wire signed [ACC_WIDTH-1:0]  host_wdata,
//    output wire signed [ACC_WIDTH-1:0]  host_rdata
//);

//    // ---------- wires between blocks ----------
//    wire [ADDR_WIDTH-1:0] fsm_a_addr, fsm_b_addr, fsm_c_addr;
//    wire                  fsm_c_we;
//    wire                  pe_clear, pe_enable;

//    wire [DATA_WIDTH-1:0] a_dout, b_dout;
//    wire [ACC_WIDTH-1:0]  c_dout;
//    wire signed [ACC_WIDTH-1:0] pe_acc;

//    // ---------- who controls each memory? (busy decides) ----------
//    // Memory A: FSM only reads it, host can write it
//    wire [ADDR_WIDTH-1:0] a_addr = busy ? fsm_a_addr : host_addr;
//    wire                  a_we   = !busy && host_we && (host_bank_sel == 2'b00);

//    // Memory B: same idea
//    wire [ADDR_WIDTH-1:0] b_addr = busy ? fsm_b_addr : host_addr;
//    wire                  b_we   = !busy && host_we && (host_bank_sel == 2'b01);

//    // Memory C: FSM writes the PE result, host can read (or write)
//    wire [ADDR_WIDTH-1:0] c_addr = busy ? fsm_c_addr : host_addr;
//    wire                  c_we   = busy ? fsm_c_we
//                                        : (host_we && (host_bank_sel == 2'b10));
//    wire [ACC_WIDTH-1:0]  c_din  = busy ? pe_acc : host_wdata;

//    // ---------- what the host reads back ----------
//    // A and B are 8-bit, so sign-extend them to 24 bits
//    assign host_rdata =
//        (host_bank_sel == 2'b00) ? {{(ACC_WIDTH-DATA_WIDTH){a_dout[DATA_WIDTH-1]}}, a_dout} :
//        (host_bank_sel == 2'b01) ? {{(ACC_WIDTH-DATA_WIDTH){b_dout[DATA_WIDTH-1]}}, b_dout} :
//                                   c_dout;

//    // ---------- the three memories ----------
//    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_a (
//        .clk(clk), .rst_n(rst_n), .we(a_we), .addr(a_addr),
//        .din(host_wdata[DATA_WIDTH-1:0]), .dout(a_dout)
//    );

//    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_b (
//        .clk(clk), .rst_n(rst_n), .we(b_we), .addr(b_addr),
//        .din(host_wdata[DATA_WIDTH-1:0]), .dout(b_dout)
//    );

//    sram_bank #(.DEPTH(DEPTH), .DATA_WIDTH(ACC_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sram_c (
//        .clk(clk), .rst_n(rst_n), .we(c_we), .addr(c_addr),
//        .din(c_din), .dout(c_dout)
//    );

//    // ---------- the compute unit ----------
//    pe #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pe (
//        .clk(clk), .rst_n(rst_n),
//        .clear(pe_clear), .enable(pe_enable),
//        .a_in(a_dout), .b_in(b_dout),
//        .reg_a_out(), .reg_b_out(),
//        .acc_out(pe_acc)
//    );

//    // ---------- the controller ----------
//    fsm_controller #(.N(N), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_fsm (
//        .clk(clk), .rst_n(rst_n), .start(start),
//        .done(done), .busy(busy),
//        .sram_a_addr(fsm_a_addr), .sram_b_addr(fsm_b_addr),
//        .sram_c_addr(fsm_c_addr), .sram_c_we(fsm_c_we),
//        .pe_clear(pe_clear), .pe_enable(pe_enable),
//        .cnt_i_out(), .cnt_j_out(), .cnt_k_out()
//    );

//endmodule

`timescale 1ns / 1ps
`default_nettype none

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
    output reg                          done,
    output reg                          busy,

    input  wire                         host_we,        // host write enable
    input  wire [1:0]                   host_bank_sel,  // 00 = A, 01 = B, 10 = C
    input  wire [ADDR_WIDTH-1:0]        host_addr,
    input  wire signed [ACC_WIDTH-1:0]  host_wdata,
    output wire signed [ACC_WIDTH-1:0]  host_rdata
);

    // =========================================================================
    // 1. Near-Memory SRAM Signals & Host Arbitration
    // =========================================================================
    reg  [ADDR_WIDTH-1:0] fsm_ab_addr;
    reg  [ADDR_WIDTH-1:0] fsm_c_addr;
    reg                   fsm_c_we;

    wire [DATA_WIDTH-1:0] a_dout, b_dout;
    wire [ACC_WIDTH-1:0]  c_dout;
    wire [ACC_WIDTH-1:0]  nmpu_c_wdata;

    wire [ADDR_WIDTH-1:0] a_addr = busy ? fsm_ab_addr : host_addr;
    wire                  a_we   = !busy && host_we && (host_bank_sel == 2'b00);

    wire [ADDR_WIDTH-1:0] b_addr = busy ? fsm_ab_addr : host_addr;
    wire                  b_we   = !busy && host_we && (host_bank_sel == 2'b01);

    wire [ADDR_WIDTH-1:0] c_addr = busy ? fsm_c_addr : host_addr;
    wire                  c_we   = busy ? fsm_c_we   : (host_we && (host_bank_sel == 2'b10));
    wire [ACC_WIDTH-1:0]  c_din  = busy ? nmpu_c_wdata : host_wdata[ACC_WIDTH-1:0];

    assign host_rdata =
        (host_bank_sel == 2'b00) ? {{(ACC_WIDTH-DATA_WIDTH){a_dout[DATA_WIDTH-1]}}, a_dout} :
        (host_bank_sel == 2'b01) ? {{(ACC_WIDTH-DATA_WIDTH){b_dout[DATA_WIDTH-1]}}, b_dout} :
                                   $signed(c_dout);

    // Existing Single-Port Synchronous SRAM Banks
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

    // =========================================================================
    // 2. NMPU Tightly-Coupled Near-Memory Registers & Broadcast MAC Array
    // =========================================================================
    reg signed [DATA_WIDTH-1:0] nm_a_reg [0:DEPTH-1];
    reg signed [DATA_WIDTH-1:0] nm_b_reg [0:DEPTH-1];
    reg signed [ACC_WIDTH-1:0]  nm_c_acc [0:DEPTH-1];

    reg [1:0] row_sel;
    integer i, c;

    wire signed [2*DATA_WIDTH-1:0] prod [0:N-1][0:N-1];
    wire signed [ACC_WIDTH-1:0]    row_sum [0:N-1];

    genvar gc, gk;
    generate
        for (gc = 0; gc < N; gc = gc + 1) begin : gen_col_bank
            for (gk = 0; gk < N; gk = gk + 1) begin : gen_mac
                assign prod[gc][gk] = nm_a_reg[row_sel * N + gk] * nm_b_reg[gk * N + gc];
            end
            assign row_sum[gc] = ($signed({{(ACC_WIDTH-2*DATA_WIDTH){prod[gc][0][2*DATA_WIDTH-1]}}, prod[gc][0]}) +
                                  $signed({{(ACC_WIDTH-2*DATA_WIDTH){prod[gc][1][2*DATA_WIDTH-1]}}, prod[gc][1]})) +
                                 ($signed({{(ACC_WIDTH-2*DATA_WIDTH){prod[gc][2][2*DATA_WIDTH-1]}}, prod[gc][2]}) +
                                  $signed({{(ACC_WIDTH-2*DATA_WIDTH){prod[gc][3][2*DATA_WIDTH-1]}}, prod[gc][3]}));
        end
    endgenerate

    assign nmpu_c_wdata = nm_c_acc[fsm_c_addr];

    // =========================================================================
    // 3. Fast NMPU Controller (38 Cycles Total vs 45 Systolic Cycles!)
    // =========================================================================
    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_LOAD      = 3'd1;
    localparam [2:0] ST_COMPUTE   = 3'd2;
    localparam [2:0] ST_WRITEBACK = 3'd3;
    localparam [2:0] ST_DONE      = 3'd4;

    reg [2:0]          state;
    reg                start_d;
    reg [ADDR_WIDTH:0] cnt;

    wire start_pulse = start & ~start_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            start_d     <= 1'b0;
            done        <= 1'b0;
            busy        <= 1'b0;
            fsm_ab_addr <= {ADDR_WIDTH{1'b0}};
            fsm_c_addr  <= {ADDR_WIDTH{1'b0}};
            fsm_c_we    <= 1'b0;
            row_sel     <= 2'd0;
            cnt         <= {(ADDR_WIDTH+1){1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                nm_a_reg[i] <= {DATA_WIDTH{1'b0}};
                nm_b_reg[i] <= {DATA_WIDTH{1'b0}};
                nm_c_acc[i] <= {ACC_WIDTH{1'b0}};
            end
        end else begin
            start_d <= start;

            case (state)
                ST_IDLE: begin
                    done     <= 1'b0;
                    fsm_c_we <= 1'b0;
                    if (start_pulse) begin
                        busy        <= 1'b1;
                        fsm_ab_addr <= {ADDR_WIDTH{1'b0}};
                        cnt         <= {(ADDR_WIDTH+1){1'b0}};
                        state       <= ST_LOAD;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                ST_LOAD: begin
                    if (cnt < DEPTH) begin
                        if (cnt > 0) begin
                            nm_a_reg[cnt - 1] <= $signed(a_dout);
                            nm_b_reg[cnt - 1] <= $signed(b_dout);
                        end
                        if (cnt < DEPTH - 1)
                            fsm_ab_addr <= fsm_ab_addr + 1'b1;
                        cnt <= cnt + 1'b1;
                    end else begin
                        nm_a_reg[DEPTH - 1] <= $signed(a_dout);
                        nm_b_reg[DEPTH - 1] <= $signed(b_dout);
                        row_sel             <= 2'd0;
                        cnt                 <= {(ADDR_WIDTH+1){1'b0}};
                        state               <= ST_COMPUTE;
                    end
                end

                ST_COMPUTE: begin
                    for (c = 0; c < N; c = c + 1) begin
                        nm_c_acc[row_sel * N + c] <= row_sum[c];
                    end
                    if (row_sel == N - 1) begin
                        fsm_c_we   <= 1'b1;
                        fsm_c_addr <= {ADDR_WIDTH{1'b0}};
                        cnt        <= {(ADDR_WIDTH+1){1'b0}};
                        state      <= ST_WRITEBACK;
                    end else begin
                        row_sel <= row_sel + 1'b1;
                    end
                end

                ST_WRITEBACK: begin
                    if (cnt < DEPTH - 1) begin
                        fsm_c_we   <= 1'b1;
                        fsm_c_addr <= fsm_c_addr + 1'b1;
                        cnt        <= cnt + 1'b1;
                    end else begin
                        fsm_c_we <= 1'b0;
                        done     <= 1'b1;
                        busy     <= 1'b0;
                        state    <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

