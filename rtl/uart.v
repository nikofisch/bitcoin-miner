// UART receiver. At 50 MHz and 115200 baud, one bit takes about 434 clocks.
module uart_rx (clk, reset, rx, data, valid);

    input clk, reset, rx;
    output reg [7:0] data;
    output reg valid;

    parameter DIV = 434;

    localparam IDLE      = 2'b00,
               START_BIT = 2'b01,
               DATA_BITS = 2'b10,
               STOP_BIT  = 2'b11;

    reg [1:0] state;
    reg [31:0] count;
    reg [2:0] bit_index;
    reg [7:0] bits;
    reg rx_meta, rx_sync;

    // Bring the external UART signal into the FPGA clock domain.
    always @(posedge clk) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state     <= IDLE;
            count     <= 0;
            bit_index <= 0;
            bits      <= 0;
            data      <= 0;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    // The line goes low at the start of a frame.
                    if (!rx_sync) begin
                        count <= DIV / 2 - 1;
                        state <= START_BIT;
                    end
                end

                START_BIT: begin
                    // Check that the start bit is still low halfway through.
                    if (count != 0) begin
                        count <= count - 1'b1;
                    end else if (!rx_sync) begin
                        count     <= DIV - 1;
                        bit_index <= 0;
                        state     <= DATA_BITS;
                    end else begin
                        state <= IDLE;
                    end
                end

                DATA_BITS: begin
                    if (count != 0) begin
                        count <= count - 1'b1;
                    end else begin
                        // Sample each bit at its midpoint, starting with bit 0.
                        bits[bit_index] <= rx_sync;
                        count           <= DIV - 1;

                        if (bit_index == 7)
                            state <= STOP_BIT;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                end

                STOP_BIT: begin
                    if (count != 0) begin
                        count <= count - 1'b1;
                    end else begin
                        // Publish the byte if the stop bit is high.
                        if (rx_sync) begin
                            data  <= bits;
                            valid <= 1'b1;
                        end

                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule


// UART transmitter. Sends one start bit, eight data bits, and one stop bit.
module uart_tx (clk, reset, start, data, tx, busy);

    input clk, reset, start;
    input [7:0] data;
    output tx;
    output reg busy;

    parameter DIV = 434;

    reg [9:0] frame;
    reg [3:0] bit_index;
    reg [31:0] count;

    // Send the lowest bit of the frame. The idle line is high.
    assign tx = busy ? frame[0] : 1'b1;

    always @(posedge clk) begin
        if (reset) begin
            frame     <= 10'b1111111111;
            bit_index <= 0;
            count     <= 0;
            busy      <= 1'b0;
        end else if (start && !busy) begin
            // The low start bit goes out first, followed by data[0].
            frame     <= {1'b1, data, 1'b0};
            bit_index <= 0;
            count     <= DIV - 1;
            busy      <= 1'b1;
        end else if (busy) begin
            if (count != 0) begin
                count <= count - 1'b1;
            end else if (bit_index == 9) begin
                // The stop bit has been held for a full bit period.
                busy <= 1'b0;
            end else begin
                // Shift the next bit into frame[0].
                frame     <= {1'b1, frame[9:1]};
                bit_index <= bit_index + 1'b1;
                count     <= DIV - 1;
            end
        end
    end

endmodule