`timescale 1ns/1ps

module tb_sha256_demo;
    reg clk = 1'b0;
    reg [3:0] key = 4'b1110; // KEY0 starts pressed.
    wire [9:0] leds;

    always #10 clk = ~clk; // 50 MHz clock.

    sha256_demo dut (
    .CLOCK_50(clk),
    .KEY(key),
    .LEDR(leds)
    );

    initial begin
        // Hold reset, then release KEY0 to start hashing.
        repeat (4) @(negedge clk);
        key[0] = 1'b1;

        // Give the core time to finish and the LEDs time to update.
        repeat (150) @(negedge clk);

        if (leds[1:0] !== 2'b01)
        $fatal(1, "FAIL: expected LED0 on and LED1 off, got %b",
        leds[1:0]);

        $display("PASS: SHA256(abc) = %h", dut.hash);
        $finish;
    end
endmodule
