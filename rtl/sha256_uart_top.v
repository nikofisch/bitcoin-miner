module sha256_uart_top (CLOCK_50, KEY, UART_RX, UART_TX, LEDR);

    input CLOCK_50;
    input [3:0] KEY;
    input UART_RX;
    output UART_TX;
    output [9:0] LEDR;

    parameter CLOCK_HZ = 50000000;
    parameter BAUD = 115200;
    parameter RX_TIMEOUT_CYCLES = 25000000;

    localparam RECEIVE      = 3'b000,
               START_FIRST  = 3'b001,
               WAIT_FIRST   = 3'b010,
               START_SECOND = 3'b011,
               WAIT_SECOND  = 3'b100,
               SEND_BYTE    = 3'b101,
               WAIT_TX_BUSY = 3'b110,
               WAIT_TX_DONE = 3'b111;

    wire Clock, Reset;
    reg [1:0] reset_sync;

    wire [7:0] rx_data;
    wire rx_valid, tx_busy;
    reg [7:0] tx_data;
    reg tx_start;

    reg [2:0] state;
    reg [5:0] rx_count;
    reg [4:0] tx_count;
    reg [31:0] rx_timeout;

    reg [511:0] block_buffer;
    reg [255:0] first_digest, hash_buffer;
    reg [7:0] last_rx;
    reg result_ready;

    wire [255:0] iv, core_out;
    wire core_start, core_done;
    wire [511:0] core_block;

    assign Clock = CLOCK_50;
    assign Reset = reset_sync[1];

    // KEY0 asserts reset when pressed. Two clock edges release it.
    always @(posedge Clock or negedge KEY[0]) begin
        if (!KEY[0])
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end

    // UART receiver and transmitter.
    uart_rx #(.DIV(CLOCK_HZ / BAUD)) receiver (
        .clk(Clock),
        .reset(Reset),
        .rx(UART_RX),
        .data(rx_data),
        .valid(rx_valid)
    );

    uart_tx #(.DIV(CLOCK_HZ / BAUD)) transmitter (
        .clk(Clock),
        .reset(Reset),
        .start(tx_start),
        .data(tx_data),
        .tx(UART_TX),
        .busy(tx_busy)
    );

    // Start the same SHA-256 core once for each pass.
    assign core_start = (state == START_FIRST) || (state == START_SECOND);

    // Python pads the first message. The FPGA pads the first digest.
    assign core_block = (state == START_SECOND)
                      ? {first_digest, 1'b1, 191'b0, 64'd256}
                      : block_buffer;

    sha256_iv initial_hash (
        .iv(iv)
    );

    sha256_core core (
        .clk(Clock),
        .rst(Reset),
        .start(core_start),
        .block(core_block),
        .hin(iv),
        .hout(core_out),
        .done(core_done),
        .busy()
    );

    // LED9 shows that the hash is ready. LED8 shows request activity.
    assign LEDR[9] = result_ready;
    assign LEDR[8] = (state != RECEIVE) || (rx_count != 0);
    assign LEDR[7:0] = last_rx;

    // Controller states and register updates.
    always @(posedge Clock) begin
        if (Reset) begin
            state        <= RECEIVE;
            rx_count     <= 0;
            tx_count     <= 0;
            rx_timeout   <= 0;
            block_buffer <= 0;
            first_digest <= 0;
            hash_buffer  <= 0;
            tx_data      <= 0;
            tx_start     <= 0;
            last_rx      <= 0;
            result_ready <= 0;
        end else begin
            // SEND_BYTE raises tx_start for one clock cycle.
            tx_start <= 1'b0;

            if (rx_valid)
                last_rx <= rx_data;

            case (state)
                RECEIVE: begin
                    if (rx_valid) begin
                        rx_timeout   <= 0;
                        result_ready <= 0;
                        block_buffer <= {block_buffer[503:0], rx_data};

                        if (rx_count == 63) begin
                            rx_count <= 0;
                            state    <= START_FIRST;
                        end else begin
                            rx_count <= rx_count + 1'b1;
                        end
                    end else if (rx_count != 0) begin
                        // Discard a partial block if the next byte takes too long.
                        if (rx_timeout == RX_TIMEOUT_CYCLES - 1) begin
                            rx_count     <= 0;
                            rx_timeout   <= 0;
                            block_buffer <= 0;
                        end else begin
                            rx_timeout <= rx_timeout + 1'b1;
                        end
                    end else begin
                        rx_timeout <= 0;
                    end
                end

                START_FIRST: begin
                    state <= WAIT_FIRST;
                end

                WAIT_FIRST: begin
                    if (core_done) begin
                        first_digest <= core_out;
                        state        <= START_SECOND;
                    end
                end

                START_SECOND: begin
                    state <= WAIT_SECOND;
                end

                WAIT_SECOND: begin
                    if (core_done) begin
                        hash_buffer  <= core_out;
                        tx_count     <= 0;
                        result_ready <= 1'b1;
                        state        <= SEND_BYTE;
                    end
                end

                SEND_BYTE: begin
                    if (!tx_busy) begin
                        tx_data  <= hash_buffer[255:248];
                        tx_start <= 1'b1;
                        state    <= WAIT_TX_BUSY;
                    end
                end

                WAIT_TX_BUSY: begin
                    if (tx_busy)
                        state <= WAIT_TX_DONE;
                end

                WAIT_TX_DONE: begin
                    if (!tx_busy) begin
                        if (tx_count == 31) begin
                            state <= RECEIVE;
                        end else begin
                            hash_buffer <= {hash_buffer[247:0], 8'b0};
                            tx_count    <= tx_count + 1'b1;
                            state       <= SEND_BYTE;
                        end
                    end
                end

                default: begin
                    state <= RECEIVE;
                end
            endcase
        end
    end

endmodule