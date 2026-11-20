// Receive exactly 64 padded bytes; return 32 raw double-SHA256 digest bytes.
// First input byte -> block[511:504]; first output byte -> hout[255:248].
// Protocol supports a single request at a time; it has no queue or framing CRC.
// The host must wait for the entire 32-byte response before sending a new job.
// Input messages before padding must be <=55 bytes (one-block first SHA).
module sha256_uart_top #(
    parameter CLOCK_HZ=50000000,
    parameter BAUD=115200,
    parameter RX_TIMEOUT_CYCLES=25000000
)(
    input wire CLOCK_50,
    input wire [3:0] KEY,
    input wire UART_RX,
    output wire UART_TX,
    output wire [9:0] LEDR
);
    reg [1:0] reset_sync;
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) reset_sync<=2'b11;
        else reset_sync<={reset_sync[0],1'b0};
    end
    wire reset=reset_sync[1];

    wire [7:0] rx_data;
    wire rx_valid,tx_busy;
    reg [7:0] tx_data;
    reg tx_start;
    uart_rx #(.DIV(CLOCK_HZ/BAUD)) receiver(
        .clk(CLOCK_50),.reset(reset),.rx(UART_RX),.data(rx_data),.valid(rx_valid));
    uart_tx #(.DIV(CLOCK_HZ/BAUD)) transmitter(
        .clk(CLOCK_50),.reset(reset),.start(tx_start),.data(tx_data),.tx(UART_TX),.busy(tx_busy));

    localparam RECEIVE=0, START_FIRST=1, WAIT_FIRST=2,
        START_SECOND=3, WAIT_SECOND=4, SEND_BYTE=5,
        WAIT_TX_BUSY=6, WAIT_TX_DONE=7;
    reg [2:0] state;
    reg [5:0] rx_count;
    reg [4:0] tx_count;
    reg [31:0] rx_timeout;
    reg [511:0] block_buffer;
    reg [255:0] first_digest,hash_buffer;
    reg [7:0] last_rx;
    reg result_ready;

    wire [255:0] iv,core_out;
    wire core_done;
    wire core_start=(state==START_FIRST || state==START_SECOND);
    // Second SHA hashes RAW 32-byte digest, not its 64-character hex string.
    // Its padded chunk is: digest || 0x80 || 23 zero bytes || length 256 bits.
    wire [511:0] core_block=(state==START_SECOND)?
        {first_digest,1'b1,191'b0,64'd256}:block_buffer;
    sha256_iv initial_hash(iv);
    sha256_core core(.clk(CLOCK_50),.rst(reset),.start(core_start),
        .block(core_block),.hin(iv),.hout(core_out),.done(core_done),.busy());

    // LEDs 0..7: last input byte. LED8: request active. LED9: hash computed.
    assign LEDR={result_ready,((state!=RECEIVE)||(rx_count!=0)),last_rx};

    always @(posedge CLOCK_50) begin
        if (reset) begin
            state<=RECEIVE;rx_count<=0;tx_count<=0;rx_timeout<=0;
            block_buffer<=0;first_digest<=0;hash_buffer<=0;
            tx_data<=0;tx_start<=0;last_rx<=0;result_ready<=0;
        end else begin
            tx_start<=0;
            if (rx_valid) last_rx<=rx_data;
            case (state)
                RECEIVE: begin
                    if (rx_valid) begin
                        rx_timeout<=0;result_ready<=0;
                        block_buffer<={block_buffer[503:0],rx_data};
                        if (rx_count==63) begin
                            rx_count<=0;state<=START_FIRST;
                        end else rx_count<=rx_count+1'b1;
                    end else if (rx_count!=0) begin
                        // Discard an incomplete packet after an inter-byte gap.
                        if (rx_timeout==RX_TIMEOUT_CYCLES-1) begin
                            rx_count<=0;rx_timeout<=0;block_buffer<=0;
                        end else rx_timeout<=rx_timeout+1'b1;
                    end else rx_timeout<=0;
                end
                // START is a distinct state: the 64th byte is now in the buffer.
                START_FIRST:state<=WAIT_FIRST;
                WAIT_FIRST:if (core_done) begin
                    first_digest<=core_out;state<=START_SECOND;
                end
                START_SECOND:state<=WAIT_SECOND;
                WAIT_SECOND:if (core_done) begin
                    hash_buffer<=core_out;tx_count<=0;result_ready<=1;
                    state<=SEND_BYTE;
                end
                SEND_BYTE:if (!tx_busy) begin
                    tx_data<=hash_buffer[255:248];tx_start<=1;
                    state<=WAIT_TX_BUSY;
                end
                // Wait until UART has accepted start, then until it finishes.
                WAIT_TX_BUSY:if (tx_busy) state<=WAIT_TX_DONE;
                WAIT_TX_DONE:if (!tx_busy) begin
                    if (tx_count==31) state<=RECEIVE;
                    else begin
                        hash_buffer<={hash_buffer[247:0],8'b0};
                        tx_count<=tx_count+1'b1;state<=SEND_BYTE;
                    end
                end
                default:state<=RECEIVE;
            endcase
        end
    end
endmodule
