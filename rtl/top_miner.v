// top_miner.v -- the ONE top-level module. Only wiring + control lives here;
// every block is its own file:
//   sha256_core.v    sha256_core, sha256_iv
//   uart.v           uart_rx, uart_tx
//   nonce_counter.v  nonce_counter, nonce_display, hex7seg
//
// Flow: midstate (block 1) -> per nonce: block 2 -> 2nd SHA-256 -> compare
//       -> not found: nonce+1 | found: send nonce + hash over UART, freeze.
// Any byte received on UART while FOUND restarts the search.
//
// SW[4:0]  = N, required leading zero bits (0..31)
// HEX5..0  = nonce (frozen when found)
// LEDR[9]  = found, LEDR[8] = searching, LEDR[7] = UART tx busy, LEDR[3:0] = FSM state
// KEY[0]   = reset (active low)
// UART out (36 bytes, MSB first): 4-byte nonce, then 32-byte hash in Bitcoin display order

module top_miner (
    CLOCK_50, KEY, SW, UART_RX, UART_TX, LEDR,
    HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);

    input CLOCK_50;
    input [3:0] KEY;
    input [9:0] SW;
    input UART_RX;
    output UART_TX;
    output [9:0] LEDR;
    output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    parameter DISPLAY_DIV = 6_250_000;
    parameter UART_DIV = 434;
    parameter [31:0] START_NONCE = 32'd0;

    wire clk;
    assign clk = CLOCK_50;

    // reset: async assert, synchronous release
    reg [1:0] rst_sync;
    always @(posedge clk or negedge KEY[0])
        if (!KEY[0]) rst_sync <= 2'b11;
        else         rst_sync <= {rst_sync[0], 1'b0};
    wire rst;
    assign rst = rst_sync[1];

    // header (Bitcoin genesis block, raw bytes)
    // block 1 = bytes 0..63: version, prev hash, first 28 bytes of merkle root
    localparam [511:0] BLOCK1 = 512'h0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa;
    // block 2 starts with bytes 64..75: last 4 merkle bytes, time, bits (nonce follows)
    localparam [95:0]  TAIL   = 96'h4b1e5e4a29ab5f49ffff001d;

    // SHA-256
    wire [255:0] iv;
    sha256_iv iv_rom (.iv(iv));

    reg          core_start;
    reg  [511:0] core_block;
    reg  [255:0] core_hin;
    wire [255:0] core_hout;
    wire         core_done, core_busy;
    sha256_core core (.clk(clk), .rst(rst), .start(core_start),
                      .block(core_block), .hin(core_hin),
                      .hout(core_hout), .done(core_done), .busy(core_busy));

    // UART
    wire [7:0] rx_data;
    wire       rx_valid, tx_busy;
    reg  [7:0] tx_data;
    reg        tx_start;
    uart_rx #(.DIV(UART_DIV)) urx (.clk(clk), .reset(rst), .rx(UART_RX),
                                   .data(rx_data), .valid(rx_valid));
    uart_tx #(.DIV(UART_DIV)) utx (.clk(clk), .reset(rst), .start(tx_start),
                                   .data(tx_data), .tx(UART_TX), .busy(tx_busy));

    // control FSM
    localparam MID_GO=4'd0, MID_WAIT=4'd1, H1_GO=4'd2, H1_WAIT=4'd3,
               H2_GO=4'd4,  H2_WAIT=4'd5, CHECK=4'd6,
               SEND_GO=4'd7, SEND_WAIT=4'd8, FOUND=4'd9;
    reg [3:0]   state;
    reg [255:0] midstate, digest1, digest2;
    reg [5:0]   tx_idx;  // which of the 36 UART bytes

    wire found = (state >= SEND_GO);  // SEND_GO, SEND_WAIT, FOUND

    // nonce
    wire [31:0] nonce, shown;
    reg         nonce_inc;
    wire        nonce_clear = (state == FOUND) & rx_valid;
    nonce_counter nc (.clk(clk), .rst(rst), .clear(nonce_clear), .inc(nonce_inc),
                      .start_val(START_NONCE), .nonce(nonce));

    // header stores the nonce little-endian
    wire [31:0]  nonce_le = {nonce[7:0], nonce[15:8], nonce[23:16], nonce[31:24]};
    // block 2 = 12 B tail + 4 B nonce + 0x80 + zeros + 64-bit length (80 B = 640 bits)
    wire [511:0] block2   = {TAIL, nonce_le, 8'h80, 312'd0, 64'd640};

    // target compare
    // Bitcoin displays hashes byte-reversed, so the "leading zeros" are at the end of the digest
    reg [255:0] hash_rev;
    integer i;
    always @(*) begin
        for (i = 0; i < 32; i = i + 1)
            hash_rev[8*i +: 8] = digest2[255 - 8*i -: 8];
    end

    wire [255:0] mask = ~({256{1'b1}} >> SW[4:0]);
    wire         hit  = ((hash_rev & mask) == 256'd0);

    // UART report: {nonce, hash_rev}, byte tx_idx
    wire [287:0] report = {nonce, hash_rev};

    // combinational control outputs
    always @(*) begin
        core_start = 1'b0;
        core_block = BLOCK1;
        core_hin   = iv;
        nonce_inc  = 1'b0;
        tx_start   = 1'b0;
        tx_data    = report[287 - 8*tx_idx -: 8];
        case (state)
            MID_GO:
                core_start = 1'b1;
            H1_GO: begin
                core_start = 1'b1;
                core_block = block2;
                core_hin = midstate;
            end
            H2_GO: begin
                core_start = 1'b1;
                core_block = {digest1, 1'b1, 191'd0, 64'd256};
            end
            CHECK:
                nonce_inc = ~hit;
            SEND_GO:
                tx_start = 1'b1;
            default: ;
        endcase
    end

    // Update the state and save hash results on each rising edge.
    always @(posedge clk) begin
        if (rst) begin
            state   <= MID_GO;
            midstate <= 0;
            digest1 <= 0;
            digest2 <= 0;
            tx_idx  <= 0;
        end else begin
            case (state)
                MID_GO:
                    state <= MID_WAIT;
                MID_WAIT: begin
                    if (core_done) begin
                        midstate <= core_hout;
                        state    <= H1_GO;
                    end
                end
                H1_GO:
                    state <= H1_WAIT;
                H1_WAIT: begin
                    if (core_done) begin
                        digest1 <= core_hout;
                        state   <= H2_GO;
                    end
                end
                H2_GO:
                    state <= H2_WAIT;
                H2_WAIT: begin
                    if (core_done) begin
                        digest2 <= core_hout;
                        state   <= CHECK;
                    end
                end
                CHECK: begin
                    if (hit) begin
                        tx_idx <= 0;
                        state  <= SEND_GO;
                    end else begin
                        state <= H1_GO;
                    end
                end
                SEND_GO:
                    state <= SEND_WAIT;
                SEND_WAIT: begin
                    if (!tx_busy) begin
                        if (tx_idx == 6'd35) begin
                            state <= FOUND;
                        end else begin
                            tx_idx <= tx_idx + 1'b1;
                            state  <= SEND_GO;
                        end
                    end
                end
                FOUND: begin
                    if (rx_valid)
                        state <= H1_GO;
                end
                default:
                    state <= MID_GO;
            endcase
        end
    end

    // HEX display
    nonce_display #(.DIV(DISPLAY_DIV)) nd (.clk(clk), .rst(rst), .found(found),
                                           .nonce(nonce), .shown(shown));
    hex7seg h0 (shown[3:0],   HEX0);
    hex7seg h1 (shown[7:4],   HEX1);
    hex7seg h2 (shown[11:8],  HEX2);
    hex7seg h3 (shown[15:12], HEX3);
    hex7seg h4 (shown[19:16], HEX4);
    hex7seg h5 (shown[23:20], HEX5);

    // LEDs
    assign LEDR[9]   = found;
    assign LEDR[8]   = ~found;
    assign LEDR[7]   = tx_busy;
    assign LEDR[6:4] = 3'b0;
    assign LEDR[3:0] = state;
endmodule
