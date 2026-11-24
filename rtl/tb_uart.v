`timescale 1ns/1ps
// Tests uart_tx and uart_rx by wiring tx -> rx (loopback), plus a hand-made frame into rx.
module tb_uart ();
    parameter DIV = 8;  // fast baud for simulation (real board: 434)
    reg clk = 0;
    localparam CLOCK_PERIOD = 20;

    always #(CLOCK_PERIOD / 2) begin : clock_generator
        clk = ~clk;
    end
    reg rst = 1;

    // ---- loopback: tx -> rx ----
    reg tx_start = 0;
    reg [7:0] tx_data;
    wire line, tx_busy, rx_valid;
    wire [7:0] rx_data;
    uart_tx #(.DIV(DIV)) tx (.clk(clk), .reset(rst), .start(tx_start), .data(tx_data), .tx(line), .busy(tx_busy));
    uart_rx #(.DIV(DIV)) rx (.clk(clk), .reset(rst), .rx(line), .data(rx_data), .valid(rx_valid));

    // ---- second rx driven by a bit-banged line ----
    reg  line2 = 1;
    wire v2;
    wire [7:0] d2;
    uart_rx #(.DIV(DIV)) rx2 (.clk(clk), .reset(rst), .rx(line2), .data(d2), .valid(v2));

    integer errors = 0, k;
    reg [7:0] vec [0:5];
    reg [7:0] got;
    reg gotv;
    always @(posedge clk) if (rx_valid) begin
        got <= rx_data;
        gotv <= 1;
    end

    task send;
        input [7:0] b;
        begin
            gotv = 0;
            @(negedge clk);
            tx_data = b;
            tx_start = 1;
            @(negedge clk);
            tx_start = 0;
            if (!tx_busy) begin
                $display("FAIL: busy not asserted");
                errors = errors + 1;
            end
            while (tx_busy) @(negedge clk);
            repeat (2*DIV) @(negedge clk);  // let rx finish
            if (gotv && got === b)
                $display("PASS loopback 0x%h", b);
            else begin
                $display("FAIL loopback sent %h got %h (valid=%b)", b, got, gotv);
                errors = errors + 1;
            end
        end
    endtask

    // drive one 8N1 frame onto line2
    task bitbang;
        input [7:0] b;
        integer j;
        begin
            line2 = 0;
            repeat (DIV) @(posedge clk);
            for (j = 0; j < 8; j = j + 1) begin
                line2 = b[j];
                repeat (DIV) @(posedge clk);
            end
            line2 = 1;
            repeat (DIV) @(posedge clk);
        end
    endtask

    initial begin
        vec[0]=8'h00;
        vec[1]=8'hFF;
        vec[2]=8'hA5;
        vec[3]=8'h3C;
        vec[4]=8'h81;
        vec[5]=8'h01;
        #100 rst = 0;
        repeat (5) @(negedge clk);
        if (line !== 1'b1) begin
            $display("FAIL: tx line not idle-high");
            errors = errors + 1;
        end
        for (k = 0; k < 6; k = k + 1) send(vec[k]);

        // bit-banged frame: LSB first, 0x5A
        bitbang(8'h5A);
        repeat (DIV) @(posedge clk);
        if (d2 === 8'h5A)
            $display("PASS bit-banged 0x5A");
        else begin
            $display("FAIL bit-banged got %h", d2);
            errors = errors + 1;
        end

        // frame with bad stop bit must NOT produce valid
        begin : badstop
            reg sawv;
            sawv = 0;
            fork
                begin
                    line2 = 0;
                    repeat (DIV) @(posedge clk);
                    repeat (8) begin
                        line2 = 1;
                        repeat (DIV) @(posedge clk);
                    end
                    line2 = 0;
                    repeat (DIV) @(posedge clk);
                    line2 = 1;
                end
                begin
                    repeat (14*DIV) begin
                        @(posedge clk);
                        if (v2)
                            sawv = 1;
                    end
                end
            join
            if (!sawv)
                $display("PASS bad stop bit rejected");
            else begin
                $display("FAIL bad stop accepted");
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("ALL UART TESTS PASSED");
        else
            $display("%0d ERRORS", errors);
        $finish;
    end
    initial begin
        #2_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
