`timescale 1ns/1ps
// Tests sha256_core alone against FIPS 180-4 vectors.
module tb_sha256_core ();
    reg clk = 0;
    localparam CLOCK_PERIOD = 20;

    always #(CLOCK_PERIOD / 2) begin : clock_generator
        clk = ~clk;
    end
    reg rst = 1, start = 0;
    reg  [511:0] block;
    reg [255:0] hin;
    wire [255:0] hout;
    wire done, busy;
    wire [255:0] iv;
    sha256_iv ivrom(.iv(iv));
    sha256_core dut(.clk(clk), .rst(rst), .start(start), .block(block), .hin(hin),
                    .hout(hout), .done(done), .busy(busy));

    integer errors = 0, cycles;
    reg [255:0] mid;

    // run one block, return when done pulses; measures cycles start->done
    task run;
        input [511:0] b;
        input [255:0] h;
        begin
            @(negedge clk);
            block = b;
            hin = h;
            start = 1;
            @(negedge clk);
            start = 0;
            cycles = 1;
            while (!done) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
        end
    endtask
    task check;
        input [255:0] got;
        input [255:0] exp;
        input [255:0] id;
        begin
            if (got === exp)
                $display("PASS test %0d", id);
            else begin
                $display("FAIL test %0d\n  got %h\n  exp %h", id, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        #55 rst = 0;
        // 1. "abc" (one block)
        run(512'h61626380_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000018, iv);
        check(hout, 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, 1);
        $display("cycles start->done = %0d (expect 114)", cycles);
        if (cycles != 114) errors = errors + 1;

        // 2. 448-bit message, two blocks: block 2 uses block 1's output as hin (chaining)
        run(512'h6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f70718000000000000000, iv);
        mid = hout;
        run(512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c0, mid);
        check(hout, 256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1, 2);

        // 3. start while busy must be ignored: pulse start mid-run, result must still be "abc"
        @(negedge clk);
        block = 512'h61626380_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000018;
        hin = iv;
        start = 1;
        @(negedge clk);
        start = 0;
        repeat (20) @(negedge clk);
        block = ~block;
        start = 1;
        @(negedge clk);
        start = 0;  // ignored (core busy)
        while (!done) @(negedge clk);
        check(hout, 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, 3);

        // 4. reset clears busy/done
        @(negedge clk);
        rst = 1;
        @(negedge clk);
        @(negedge clk);
        rst = 0;
        if (busy || done) begin
            $display("FAIL reset");
            errors = errors + 1;
        end else $display("PASS test 4 (reset)");

        if (errors == 0)
            $display("ALL SHA256 CORE TESTS PASSED");
        else
            $display("%0d ERRORS", errors);
        $finish;
    end
    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
