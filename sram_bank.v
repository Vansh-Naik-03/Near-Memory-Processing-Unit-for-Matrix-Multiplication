// SRAM bank: a small memory. Write when we=1, read always (output appears 1 clock later).
`timescale 1ns / 1ps

module sram_bank #(
    parameter DEPTH      = 16,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,   // active-low reset
    input  wire                  we,      // write enable
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] din,
    output reg  [DATA_WIDTH-1:0] dout
);

    // the memory itself: DEPTH boxes, each DATA_WIDTH bits wide
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reset: empty every box and the output
            dout <= 0;
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= 0;
        end else begin
            if (we)
                mem[addr] <= din;   // write
            dout <= mem[addr];      // read (1 clock delay)
        end
    end

endmodule
