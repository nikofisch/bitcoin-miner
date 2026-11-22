`timescale 1ns/1ps
// Integration test: SHA core + nonce counter + UART + HEX inside top_miner.
// Mines the real Bitcoin genesis block starting 8 nonces early and checks:
//   - the nonce/hash reported over UART_TX
//   - the nonce on the HEX displays
//   - a UART byte restarts the search and gives the same answer again
module tb_top_miner ();
    parameter UDIV = 8;
    reg clk = 0;
    localparam CLOCK_PERIOD = 20;

    always #(CLOCK_PERIOD / 2) begin : clock_generator
        clk = ~clk;
    end
    reg [3:0] KEY = 4'b1111;
    reg [9:0] SW;
    reg UART_RX = 1;
    wire UART_TX;
    wire [9:0] LEDR;
    wire [6:0] H0,H1,H2,H3,H4,H5;

    top_miner #(.DISPLAY_DIV(100), .UART_DIV(UDIV), .START_NONCE(32'h7c2bac1d - 32'd8)) dut
        (.CLOCK_50(clk), .KEY(KEY), .SW(SW), .UART_RX(UART_RX), .UART_TX(UART_TX), .LEDR(LEDR),
         .HEX0(H0),.HEX1(H1),.HEX2(H2),.HEX3(H3),.HEX4(H4),.HEX5(H5));

    // snoop the board's UART output with our own receiver
    wire [7:0] mon_d;
    wire mon_v;
    uart_rx #(.DIV(UDIV)) mon (.clk(clk), .reset(1'b0), .rx(UART_TX), .data(mon_d), .valid(mon_v));
    reg [287:0] rep;
    integer nb;
    always @(posedge clk) if (mon_v) begin
        rep <= {rep[279:0], mon_d};
        nb <= nb + 1;
    end

    task send_byte;
        input [7:0] b;
        integer j;
        begin
            UART_RX = 0;
            repeat (UDIV) @(posedge clk);
            for (j = 0; j < 8; j = j + 1) begin
                UART_RX = b[j];
                repeat (UDIV) @(posedge clk);
            end
            UART_RX = 1;
            repeat (UDIV) @(posedge clk);
        end
    endtask

    integer errors = 0;
    localparam [255:0] GENESIS_HASH = 256'h000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f;
    reg [6:0] h0_exp;  // HEX0 should show digit D of 7c2bac1d

    task check_report;
        input [255:0] tag;
        begin
            if (nb !== 36) begin
                $display("FAIL %0s: got %0d UART bytes", tag, nb);
                errors = errors + 1;
            end
            else if (rep[287:256] !== 32'h7c2bac1d || rep[255:0] !== GENESIS_HASH) begin
                $display("FAIL %0s: report nonce=%h hash=%h", tag, rep[287:256], rep[255:0]);
                errors = errors + 1;
                end
            else
                $display("PASS %0s: UART reported nonce 7c2bac1d + genesis hash", tag);
        end
    endtask

    initial begin
        SW = 10'd31;
        nb = 0;  // 31 leading zero bits (genesis has 32)
        #5 KEY[0] = 0;
        #100 KEY[0] = 1;
        wait (LEDR[9]);  // found
        wait (dut.state == 4'd9);  // FOUND = report fully sent
        repeat (4*UDIV) @(posedge clk);
        check_report("first run");
        if ({H5,H4,H3,H2,H1,H0} !== {dut.h5.seg,dut.h4.seg,dut.h3.seg,dut.h2.seg,dut.h1.seg,dut.h0.seg} ||
            dut.shown !== 32'h7c2bac1d) begin
            $display("FAIL HEX shows %h, expected 7c2bac1d", dut.shown);
            errors = errors + 1;
            end
        else
            $display("PASS HEX display latched nonce %h", dut.shown);

        // restart over UART
        nb = 0;
        send_byte(8'h52);
        wait (!LEDR[9]);
        $display("PASS search restarted by UART byte");
        wait (dut.state == 4'd9);
        repeat (4*UDIV) @(posedge clk);
        check_report("after restart");

        if (errors == 0)
            $display("ALL TOP-LEVEL TESTS PASSED");
        else
            $display("%0d ERRORS", errors);
        $finish;
    end
    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
