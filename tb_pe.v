// Testbench for pe: checks multiply-accumulate, hold, clear and signed numbers.
`timescale 1ns / 1ps

module tb_pe;

    reg                clk = 0;
    reg                rst_n, clear, enable;
    reg  signed [7:0]  a_in, b_in;
    wire signed [7:0]  reg_a_out, reg_b_out;
    wire signed [23:0] acc_out;

    integer errors = 0;

    pe #(.DATA_WIDTH(8), .ACC_WIDTH(24)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .enable(enable),
        .a_in(a_in), .b_in(b_in),
        .reg_a_out(reg_a_out), .reg_b_out(reg_b_out), .acc_out(acc_out)
    );

    always #5 clk = ~clk;

    // do one MAC step (enable for exactly one clock)
    task mac(input signed [7:0] a, input signed [7:0] b);
        begin
            a_in = a; b_in = b; enable = 1;
            @(negedge clk);
            enable = 0;
        end
    endtask

    task check(input signed [23:0] expected, input [255:0] name);
        begin
            if (acc_out !== expected) begin
                $display("FAIL %0s: got %0d expected %0d", name, acc_out, expected);
                errors = errors + 1;
            end else
                $display("pass %0s: acc = %0d", name, acc_out);
        end
    endtask

    initial begin
        rst_n = 0; clear = 0; enable = 0; a_in = 0; b_in = 0;
        #12;
        check(0, "reset");
        rst_n = 1;
        @(negedge clk);

        mac(5, 12);      check(60,   "5*12");
        mac(7, 8);       check(116,  "+7*8");
        mac(-10, 15);    check(-34,  "+(-10)*15");

        // hold: enable=0, so inputs must be ignored
        a_in = 50; b_in = 50; enable = 0;
        @(negedge clk);  check(-34,  "hold");

        // clear
        clear = 1;
        @(negedge clk);
        clear = 0;       check(0,    "clear");

        mac(127, 127);   check(16129, "127*127");

        clear = 1; @(negedge clk); clear = 0;
        mac(-128, -128); check(16384, "-128*-128");

        mac(0, 99);      check(16384, "times zero");

        if (errors == 0) $display("PE: ALL TESTS PASSED");
        else             $display("PE: %0d ERRORS", errors);
        $finish;
    end

endmodule
