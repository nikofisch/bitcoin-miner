module uart_connection (
    input wire CLOCK_50,
    input wire [3:0] KEY,
    input wire UART_RX,
    output wire UART_TX,
    output wire [9:0] LEDR
);
    reg [1:0] reset_sync;
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) reset_sync <= 2'b11;
        else reset_sync <= {reset_sync[0], 1'b0};
    end
    wire reset = reset_sync[1];
    wire [7:0] rx_data;
    wire rx_valid, tx_busy;
    reg [7:0] tx_data, last_byte;
    reg tx_start;

    uart_rx receiver (
        .clk(CLOCK_50), .reset(reset), .rx(UART_RX),
        .data(rx_data), .valid(rx_valid)
    );
    uart_tx transmitter (
        .clk(CLOCK_50), .reset(reset), .start(tx_start),
        .data(tx_data), .tx(UART_TX), .busy(tx_busy)
    );

    always @(posedge CLOCK_50) begin
        if (reset) begin
            tx_start <= 0;
            tx_data <= 0;
            last_byte <= 0;
        end else begin
            tx_start <= 0;
            if (rx_valid) begin
                last_byte <= rx_data;
                if (!tx_busy && !tx_start) begin
                    tx_data <= rx_data;
                    tx_start <= 1;
                end
            end
        end
    end
    assign LEDR = {1'b0, tx_busy, last_byte};
endmodule

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
                        bits[bit_index] <= rx_sync;
                        count <= DIV-1;
                        if (bit_index == 7) state <= STOP_BIT;
                        else bit_index <= bit_index+1;
                    end
                end
                STOP_BIT: begin
                    if (count != 0) count <= count-1;
                    else begin
                        if (rx_sync) begin data <= bits; valid <= 1; end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

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
