// Defined ports and parameters
module nonce_counter (clk, rst, clear, inc, start_val, nonce);
    input clk, rst, clear, inc;
    input [31:0] start_val;
	output reg [31:0] nonce; // The nonce is a 32-bit and is edited by the miner to determine a hash that meets the target value
    always @(posedge clk)
		if (rst | clear) nonce <= start_val; // Top-level module sets starting parameter to 32'd0
	else if (inc)    nonce <= nonce + 1'b1; // Standard guessing method of incrementing by 1 so it doubles as a counter
endmodule

// Sampling the nonce ~8 times a second so the HEX digits are readable as the counter updates
module nonce_display (clk, rst, found, nonce, shown);
    input clk, rst, found;
    input [31:0] nonce;
    output reg [31:0] shown;

    parameter DIV = 6_250_000; // 50 MHz / 8 Hz to update 8 times per second
	reg [22:0] cnt; // 23 bits is sufficient to count the bits making up 8 seconds from CLOCK 50 cycles
	wire tick = (cnt == DIV-1);
    always @(posedge clk)
		if (rst) begin // Reset
            cnt <= 0;
            shown <= 0;
        end
        else begin
            cnt <= tick ? 23'd0 : cnt + 1'b1; // Reset cnt to 0 if 8Hz tick has passed, else increment cnt by one bit
			if (found || tick) shown <= nonce; // Two instances where HEX updates the display of HEX: found and tick
			// Tick updates the displays roughly 8 times a second
			// When found is set to high, display will freeze the found nonce
        end
endmodule

module hex7seg (d, seg);
	input [3:0] d; // 4 bit case for each hexadecimal value
	output reg [6:0] seg; // hex digit is 7-segment, active-low, seg = {g,f,e,d,c,b,a}; defined in qsf

    always @(*) begin
		case (d) // Case values according to 7-segment decoder truth table for hexadecimal display
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
	
