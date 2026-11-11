// =============================================================================
// File: sram_bank.v
// Module: sram_bank
// Project: Near-Memory Processing Unit (NMPU)
// Description:
//   Synchronous On-Chip Near-Memory SRAM Bank.
//   Used for SRAM A, SRAM B, and SRAM C.
//   Synthesizable into ASIC standard cell register files or memory macros.
//   Features 1-clock-cycle synchronous read latency.
// =============================================================================

`timescale 1ns / 1ps

module sram_bank #(
    parameter DEPTH      = 16,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4   // clog2(16)
)(
    input  wire                   clk,
    input  wire                   rst_n,   // Optional reset to clear memory contents
    input  wire                   we,      // Write enable
    input  wire [ADDR_WIDTH-1:0]  addr,    // Memory address
    input  wire [DATA_WIDTH-1:0]  din,     // Data input to write
    output reg  [DATA_WIDTH-1:0]  dout     // Synchronous data output read
);

    // Internal memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    integer idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= {DATA_WIDTH{1'b0}};
            // Optional memory zeroing on reset for simulation determinism
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                mem[idx] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            if (we) begin
                mem[addr] <= din;
            end
            dout <= mem[addr]; // 1-cycle synchronous read
        end
    end

endmodule
