// nonce_counter.v
// Everything for the nonce: the counter itself, the slowed-down display
// register, and the 7-segment decoder. Instantiated from top_miner.v.

// 32-bit nonce counter. start_val is where counting begins after reset/clear.
module nonce_counter (clk, rst, clear, inc, start_val, nonce);
    input clk, rst, clear, inc;
    input [31:0] start_val;
    output reg [31:0] nonce;
    always @(posedge clk)
        if (rst | clear) nonce <= start_val;
        else if (inc)    nonce <= nonce + 1'b1;
endmodule

// Samples the (fast) nonce ~8 times a second so the HEX digits are readable.
// While found is high, capture the nonce on every rising edge.
module nonce_display (clk, rst, found, nonce, shown);
    input clk, rst, found;
    input [31:0] nonce;
    output reg [31:0] shown;

    parameter DIV = 6_250_000;  // 50 MHz / 8 Hz.
    reg [22:0] cnt;
    wire tick = (cnt == DIV-1);
    always @(posedge clk)
        if (rst) begin
            cnt <= 0;
            shown <= 0;
        end
        else begin
            cnt <= tick ? 23'd0 : cnt + 1'b1;
            if (found || tick) shown <= nonce;
        end
endmodule

// hex digit -> 7-segment, active-low, seg = {g,f,e,d,c,b,a}
module hex7seg (d, seg);
    input [3:0] d;
    output reg [6:0] seg;

    always @(*) begin
        case (d)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
        endcase
    end
endmodule
	