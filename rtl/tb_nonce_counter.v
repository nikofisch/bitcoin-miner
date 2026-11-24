`timescale 1ns/1ps
// Tests nonce_counter, nonce_display and hex7seg (no SHA core needed).
module tb_nonce_counter ();
    reg clk = 0;
    localparam CLOCK_PERIOD = 20;

    always #(CLOCK_PERIOD / 2) begin : clock_generator
        clk = ~clk;
    end
    reg rst = 1, clear = 0, inc = 0, found = 0;
    reg [31:0] start_val = 32'h0000_00F0;
    wire [31:0] nonce, shown;
    nonce_counter nc (.clk(clk), .rst(rst), .clear(clear), .inc(inc), .start_val(start_val), .nonce(nonce));
    nonce_display #(.DIV(50)) nd (.clk(clk), .rst(rst), .found(found), .nonce(nonce), .shown(shown));

    integer errors = 0, k;
    reg [3:0] d;
    wire [6:0] seg;
    hex7seg h (.d(d), .seg(seg));
    reg [6:0] exp [0:15];

    task expect32;
        input [31:0] got;
        input [31:0] e;
        input [255:0] name;
        if (got !== e) begin
            $display("FAIL %0s: got %h expected %h", name, got, e);
            errors = errors + 1;
        end
        else
            $display("PASS %0s = %h", name, got);
    endtask

    initial begin
        exp[0]=7'b1000000;
        exp[1]=7'b1111001;
        exp[2]=7'b0100100;
        exp[3]=7'b0110000;
        exp[4]=7'b0011001;
        exp[5]=7'b0010010;
        exp[6]=7'b0000010;
        exp[7]=7'b1111000;
        exp[8]=7'b0000000;
        exp[9]=7'b0010000;
        exp[10]=7'b0001000;
        exp[11]=7'b0000011;
        exp[12]=7'b1000110;
        exp[13]=7'b0100001;
        exp[14]=7'b0000110;
        exp[15]=7'b0001110;

        // ---- hex7seg: all 16 digits ----
        for (k = 0; k < 16; k = k + 1) begin
            d = k;
            #1;
            if (seg !== exp[k]) begin
                $display("FAIL hex %h: %b vs %b", d, seg, exp[k]);
                errors = errors + 1;
            end
        end
        $display("hex7seg: 16 digits checked");

        // ---- counter ----
        #50 rst = 0;
        @(negedge clk);
        expect32(nonce, 32'hF0, "start value after reset");
        repeat (3) @(negedge clk);
        expect32(nonce, 32'hF0, "holds when inc=0");
        inc = 1;
        repeat (20) @(negedge clk);
        inc = 0;
        expect32(nonce, 32'hF0 + 20, "counts 20");
        clear = 1;
        @(negedge clk);
        clear = 0;
        @(negedge clk);
        expect32(nonce, 32'hF0, "clear back to start_val");
        // wraparound
        start_val = 32'hFFFF_FFFE;
        clear = 1;
        @(negedge clk);
        clear = 0;
        inc = 1;
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        inc = 0;
        expect32(nonce, 32'h0000_0001, "wraps FFFFFFFF -> 0");

        // ---- display: updates only on tick (every 50 clocks), found grabs immediately ----
        start_val = 0;
        clear = 1;
        @(negedge clk);
        clear = 0;
        inc = 1;
        repeat (10) @(negedge clk);
        if (shown === nonce) begin
            $display("FAIL display updated before tick");
            errors = errors + 1;
        end
        else
            $display("PASS display lags the counter between ticks");
        repeat (60) @(negedge clk);
        if (shown === 0) begin
            $display("FAIL display never refreshed");
            errors = errors + 1;
        end
        else
            $display("PASS display refreshed on tick (shown=%0d)", shown);
        found = 1;
        inc = 0;
        @(negedge clk);
        @(negedge clk);
        expect32(shown, nonce, "found grabs nonce");
        repeat (120) @(negedge clk);
        expect32(shown, nonce, "display holds after found");

        if (errors == 0)
            $display("ALL NONCE COUNTER TESTS PASSED");
        else
            $display("%0d ERRORS", errors);
        $finish;
    end
endmodule
