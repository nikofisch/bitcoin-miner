	// Reused from the preceding UART echo test. Contains uart_rx and uart_tx.
// UART receiver. 50 MHz / 115200 = approximately 434 cycles per bit.
module uart_rx #(parameter DIV = 434)(
    input wire clk, reset, rx,
    output reg [7:0] data,
    output reg valid
);
    localparam IDLE=2'd0, START_BIT=2'd1, DATA_BITS=2'd2, STOP_BIT=2'd3;
    reg [1:0] state;
    reg [31:0] count;
    reg [2:0] bit_index;
    reg [7:0] bits;
    reg rx_meta, rx_sync;

    // Synchronize the external serial input to the FPGA clock.
    always @(posedge clk) begin
        if (reset) begin rx_meta <= 1; rx_sync <= 1; end
        else begin rx_meta <= rx; rx_sync <= rx_meta; end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE; count <= 0; bit_index <= 0;
            bits <= 0; data <= 0; valid <= 0;
        end else begin
            valid <= 0;
            case (state)
                IDLE: if (!rx_sync) begin
                    count <= DIV/2-1;
                    state <= START_BIT;
                end
                START_BIT: begin
                    if (count != 0) count <= count-1;
                    else if (!rx_sync) begin
                        count <= DIV-1;
                        bit_index <= 0;
                        state <= DATA_BITS;
                    end else state <= IDLE;
                end
                DATA_BITS: begin
                    if (count != 0) count <= count-1;
                    else begin
                        // Sample each data bit in its middle, LSB first.
                        bits[bit_index] <= rx_sync;
                        count <= DIV-1;
                        if (bit_index == 7) state <= STOP_BIT;
                        else bit_index <= bit_index+1;
                    end
                end
                STOP_BIT: begin
                    if (count != 0) count <= count-1;
                    else begin
                        // Only accept a frame with a high stop bit.
                        if (rx_sync) begin data <= bits; valid <= 1; end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

// UART transmitter: start bit, eight data bits, one stop bit.
module uart_tx #(parameter DIV = 434)(
    input wire clk, reset, start,
    input wire [7:0] data,
    output wire tx,
    output reg busy
);
    reg [9:0] frame;
    reg [3:0] bit_index;
    reg [31:0] count;
    assign tx = busy ? frame[0] : 1'b1;

    always @(posedge clk) begin
        if (reset) begin
            frame <= 10'b1111111111;
            bit_index <= 0; count <= 0; busy <= 0;
        end else if (start && !busy) begin
            // The rightmost bit is transmitted first.
            frame <= {1'b1, data, 1'b0};
            bit_index <= 0; count <= DIV-1; busy <= 1;
        end else if (busy) begin
            if (count != 0) count <= count-1;
            else if (bit_index == 9) busy <= 0;
            else begin
                frame <= {1'b1, frame[9:1]};
                bit_index <= bit_index+1;
                count <= DIV-1;
            end
        end
    end
endmodule
