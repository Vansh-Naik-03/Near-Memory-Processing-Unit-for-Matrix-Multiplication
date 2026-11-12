// FSM controller: the "brain". It runs three loops for C = A x B:
//   for i (row)  for j (column)  for k (dot-product step):  C[i][j] += A[i][k] * B[k][j]
// Matrices are stored row by row, so address = row*N + column.
`timescale 1ns / 1ps

module fsm_controller #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 24,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,      // host says "go"
    output reg                   done,       // 1 when finished
    output reg                   busy,       // 1 while working

    output reg [ADDR_WIDTH-1:0]  sram_a_addr,
    output reg [ADDR_WIDTH-1:0]  sram_b_addr,
    output reg [ADDR_WIDTH-1:0]  sram_c_addr,
    output reg                   sram_c_we,

    output reg                   pe_clear,
    output reg                   pe_enable,
    output wire [ADDR_WIDTH-1:0] cnt_i_out,  // for watching in waveforms
    output wire [ADDR_WIDTH-1:0] cnt_j_out,
    output wire [ADDR_WIDTH-1:0] cnt_k_out
);

    // the steps the FSM goes through
    localparam IDLE      = 3'd0;  // wait for start
    localparam INIT      = 3'd1;  // clear PE, ask memory for A[i][0], B[0][j]
    localparam FETCH     = 3'd2;  // wait 1 clock for memory to answer
    localparam MAC       = 3'd3;  // multiply-accumulate; ask for next pair
    localparam WRITE_C   = 3'd4;  // save result into C
    localparam NEXT      = 3'd5;  // move to next (i, j)
    localparam FINISH    = 3'd6;  // tell host we are done

    reg [2:0] state;
    reg [2:0] i, j, k;   // loop counters

    assign cnt_i_out = i;
    assign cnt_j_out = j;
    assign cnt_k_out = k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;  busy <= 0;
            sram_a_addr <= 0;  sram_b_addr <= 0;  sram_c_addr <= 0;
            sram_c_we <= 0;  pe_clear <= 0;  pe_enable <= 0;
            i <= 0;  j <= 0;  k <= 0;
        end else begin
            // these are 1-clock pulses, so default to 0 every clock
            pe_clear  <= 0;
            pe_enable <= 0;
            sram_c_we <= 0;

            case (state)

                IDLE: begin
                    done <= 0;
                    if (start) begin
                        busy  <= 1;
                        i <= 0;  j <= 0;  k <= 0;
                        state <= INIT;
                    end else
                        busy <= 0;
                end

                INIT: begin
                    pe_clear    <= 1;              // start C[i][j] from 0
                    k           <= 0;
                    sram_a_addr <= i * N;          // A[i][0]
                    sram_b_addr <= j;              // B[0][j]
                    state       <= FETCH;
                end

                FETCH: begin
                    state <= MAC;                  // just wait for memory data
                end

                MAC: begin
                    pe_enable <= 1;                // PE does acc += a*b
                    if (k == N - 1)
                        state <= WRITE_C;          // last step of dot product
                    else begin
                        k           <= k + 1;
                        sram_a_addr <= i * N + (k + 1);   // A[i][k+1]
                        sram_b_addr <= (k + 1) * N + j;   // B[k+1][j]
                        state       <= FETCH;
                    end
                end

                WRITE_C: begin
                    sram_c_we   <= 1;              // write PE result into C
                    sram_c_addr <= i * N + j;      // C[i][j]
                    state       <= NEXT;
                end

                NEXT: begin
                    if (i == N - 1 && j == N - 1)
                        state <= FINISH;           // all cells done
                    else begin
                        if (j == N - 1) begin      // end of row -> next row
                            j <= 0;
                            i <= i + 1;
                        end else
                            j <= j + 1;            // next column
                        state <= INIT;
                    end
                end

                FINISH: begin
                    done  <= 1;
                    busy  <= 0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
