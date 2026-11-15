// sha256_core.v
// Iterative single-block SHA-256 compression engine.
// Processes one 512-bit message block per run, taking ~72 clock cycles
// (1 cycle to load/schedule + 64 round cycles + a few to finalize).
//
// Usage:
//   - Assert `start` for one cycle with `block` and `hin` valid.
//   - `block` is the 512-bit message block, MSB-first (block[511:480] is
//     the first 32-bit word W0, etc.) matching SHA-256's big-endian word order.
//   - `hin` is the 256-bit chaining value going in: {H0,H1,H2,H3,H4,H5,H6,H7},
//     each 32 bits, MSB-first. For the very first block of a message, this is
//     the standard SHA-256 initial hash value (see sha256_iv below).
//   - When `done` pulses high, `hout` holds the new 256-bit chaining value
//     (= hin + compression result), in the same {H0..H7} word order.
//   - For a multi-block message, feed `hout` from block N as `hin` for block N+1.

module sha256_core (
    input wire clk,
    input wire rst, // synchronous, active high
    input wire start, // pulse 1 cycle to begin
    input wire [511:0] block, // 512-bit message block
    input wire [255:0] hin, // chaining value in
    output reg [255:0] hout, // chaining value out (valid when done=1)
    output reg done, // pulses 1 cycle when hout is valid
    output reg busy
    );

    // ------------------------------------------------------------------
    // Round constants K[0..63] (FIPS 180-4)
    // ------------------------------------------------------------------
    reg [31:0] K [0:63];
    initial begin
        K[0] = 32'h428a2f98; K[1] = 32'h71374491; K[2] = 32'hb5c0fbcf; K[3] = 32'he9b5dba5;
        K[4] = 32'h3956c25b; K[5] = 32'h59f111f1; K[6] = 32'h923f82a4; K[7] = 32'hab1c5ed5;
        K[8] = 32'hd807aa98; K[9] = 32'h12835b01; K[10] = 32'h243185be; K[11] = 32'h550c7dc3;
        K[12] = 32'h72be5d74; K[13] = 32'h80deb1fe; K[14] = 32'h9bdc06a7; K[15] = 32'hc19bf174;
        K[16] = 32'he49b69c1; K[17] = 32'hefbe4786; K[18] = 32'h0fc19dc6; K[19] = 32'h240ca1cc;
        K[20] = 32'h2de92c6f; K[21] = 32'h4a7484aa; K[22] = 32'h5cb0a9dc; K[23] = 32'h76f988da;
        K[24] = 32'h983e5152; K[25] = 32'ha831c66d; K[26] = 32'hb00327c8; K[27] = 32'hbf597fc7;
        K[28] = 32'hc6e00bf3; K[29] = 32'hd5a79147; K[30] = 32'h06ca6351; K[31] = 32'h14292967;
        K[32] = 32'h27b70a85; K[33] = 32'h2e1b2138; K[34] = 32'h4d2c6dfc; K[35] = 32'h53380d13;
        K[36] = 32'h650a7354; K[37] = 32'h766a0abb; K[38] = 32'h81c2c92e; K[39] = 32'h92722c85;
        K[40] = 32'ha2bfe8a1; K[41] = 32'ha81a664b; K[42] = 32'hc24b8b70; K[43] = 32'hc76c51a3;
        K[44] = 32'hd192e819; K[45] = 32'hd6990624; K[46] = 32'hf40e3585; K[47] = 32'h106aa070;
        K[48] = 32'h19a4c116; K[49] = 32'h1e376c08; K[50] = 32'h2748774c; K[51] = 32'h34b0bcb5;
        K[52] = 32'h391c0cb3; K[53] = 32'h4ed8aa4a; K[54] = 32'h5b9cca4f; K[55] = 32'h682e6ff3;
        K[56] = 32'h748f82ee; K[57] = 32'h78a5636f; K[58] = 32'h84c87814; K[59] = 32'h8cc70208;
        K[60] = 32'h90befffa; K[61] = 32'ha4506ceb; K[62] = 32'hbef9a3f7; K[63] = 32'hc67178f2;
    end

    // ------------------------------------------------------------------
    // Message schedule W[0..63]
    // ------------------------------------------------------------------
    reg [31:0] w [0:63];

    function [31:0] rotr;
        input [31:0] x;
        input [4:0] n;
        begin
            rotr = (x >> n) | (x << (32 - n));
        end
    endfunction

    function [31:0] sig0; // lowercase sigma0, used in message schedule
        input [31:0] x;
        begin
            sig0 = rotr(x,7) ^ rotr(x,18) ^ (x >> 3);
        end
    endfunction

    function [31:0] sig1; // lowercase sigma1
        input [31:0] x;
        begin
            sig1 = rotr(x,17) ^ rotr(x,19) ^ (x >> 10);
        end
    endfunction

    function [31:0] bigsig0; // uppercase Sigma0, used in round function
        input [31:0] x;
        begin
            bigsig0 = rotr(x,2) ^ rotr(x,13) ^ rotr(x,22);
        end
    endfunction

    function [31:0] bigsig1; // uppercase Sigma1
        input [31:0] x;
        begin
            bigsig1 = rotr(x,6) ^ rotr(x,11) ^ rotr(x,25);
        end
    endfunction

    function [31:0] ch;
        input [31:0] e, f, g;
        begin
            ch = (e & f) ^ (~e & g);
        end
    endfunction

    function [31:0] maj;
        input [31:0] a, b, c;
        begin
            maj = (a & b) ^ (a & c) ^ (b & c);
        end
    endfunction

    // ------------------------------------------------------------------
    // Working variables + control FSM
    // ------------------------------------------------------------------
    reg [31:0] a,b,c,d,e,f,g,h;
    reg [255:0] hin_latched;
    reg [6:0] t; // round index 0..63
    integer i;

    localparam ST_IDLE = 3'd0,
    ST_SCHEDULE = 3'd1, // fill w[0..63] combinationally (1 cycle)
    ST_ROUNDS = 3'd2, // 64 cycles, one round each
    ST_FINALIZE = 3'd3, // add a..h back into hin -> hout
    ST_DONE = 3'd4;

    reg [2:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0; // default: done pulses only in ST_FINALIZE->ST_DONE transition

            case (state)
                // ---------------------------------------------------
                ST_IDLE: begin
                    if (start) begin
                        hin_latched <= hin;
                        // Split the 512-bit block into W0..W15, MSB-first word order
                        for (i = 0; i < 16; i = i + 1)
                        w[i] <= block[511 - i*32 -: 32];
                        busy <= 1'b1;
                        state <= ST_SCHEDULE;
                    end
                end

                // ---------------------------------------------------
                // Extend the schedule to W16..W63 in one combinational pass.
                ST_SCHEDULE: begin
                    // Blocking assignment is required here: each w[i] depends
                    // on w[i-2] etc. computed earlier in this SAME loop pass.
                    // Non-blocking would make those reads see last cycle's
                    // (still-X) values instead of the value just computed.
                    for (i = 16; i < 64; i = i + 1)
                    w[i] = sig1(w[i-2]) + w[i-7] + sig0(w[i-15]) + w[i-16];

                    // Initialize working variables from the chaining value
                    a <= hin_latched[255:224]; b <= hin_latched[223:192];
                    c <= hin_latched[191:160]; d <= hin_latched[159:128];
                    e <= hin_latched[127:96]; f <= hin_latched[95:64];
                    g <= hin_latched[63:32]; h <= hin_latched[31:0];

                    t <= 7'd0;
                    state <= ST_ROUNDS;
                end

                // ---------------------------------------------------
                ST_ROUNDS: begin
                    begin : round_body
                        reg [31:0] t1, t2;
                        t1 = h + bigsig1(e) + ch(e,f,g) + K[t] + w[t];
                        t2 = bigsig0(a) + maj(a,b,c);
                        h <= g;
                        g <= f;
                        f <= e;
                        e <= d + t1;
                        d <= c;
                        c <= b;
                        b <= a;
                        a <= t1 + t2;
                    end

                    if (t == 7'd63)
                    state <= ST_FINALIZE;
                    else
                    t <= t + 7'd1;
                end

                // ---------------------------------------------------
                ST_FINALIZE: begin
                    hout <= { hin_latched[255:224] + a,
                    hin_latched[223:192] + b,
                    hin_latched[191:160] + c,
                    hin_latched[159:128] + d,
                    hin_latched[127:96] + e,
                    hin_latched[95:64] + f,
                    hin_latched[63:32] + g,
                    hin_latched[31:0] + h };
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

// ----------------------------------------------------------------------
// Standard SHA-256 initial hash value (H0..H7), for hashing the first
// block of any message. Instantiate/connect this constant to `hin` when
// starting a brand-new hash (not continuing a chained multi-block message).
// ----------------------------------------------------------------------
module sha256_iv (
    output wire [255:0] iv
    );
    assign iv = 256'h6a09e667_bb67ae85_3c6ef372_a54ff53a_510e527f_9b05688c_1f83d9ab_5be0cd19;
endmodule
