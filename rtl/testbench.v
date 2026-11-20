`timescale 1ns / 1ps

module tb_sha256_demo ();

    parameter CLOCK_PERIOD = 20; // 20 ns period = 50 MHz

    reg clk;
    reg [3:0] key;

    // need leds for modelsim
    wire [9:0] leds;

    initial begin
        clk = 1'b0;
    end
    

    // clock generator 
    always begin : Clock_Generator
        #(CLOCK_PERIOD / 2) clk = ~clk;
    end

    // connect module
    sha256_demo dut (clk, key, leds);

    initial begin


        // pressing KEY0 down to reset the demo
        key = 4'b1110;
        repeat (4) @(negedge clk);
        

        // check if reset works
        if (leds !== 10'b0)
            $fatal(1, "FAIL: expected all LEDs off during reset, got %b", leds);

        // Release KEY0 to start hashing "abc".
        key[0] = 1'b1;
        repeat (150) @(negedge clk); // wait 150 cycles


        // checks if only led 1 is on
        if (leds !== 10'b0000000001)
            $fatal(1, "FAIL: expected only LED0 on, got %b", leds);

        $display("PASS: SHA256(abc) = %h", dut.hash);
        $finish;
    end

endmodule