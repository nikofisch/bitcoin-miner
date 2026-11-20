// bas


module sha256_demo (CLOCK_50, KEY, LEDR);

    input CLOCK_50;
    input [3:0] KEY;
    output [9:0] LEDR;

    // padded "abc" version
    localparam [511:0] PADDED_ABC = {24'h616263, 1'b1, 423'b0, 64'd24};

    // known SHA-256 result for "abc".
    localparam [255:0] EXPECTED =
        256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;



    wire Clock, Reset, done;
    wire [255:0] initial, hash;
    reg start, passed, failed;

    assign Clock = CLOCK_50;
    assign Reset = ~KEY[0]; // reset is 1 when key0 is pressed

    // Supply the standard SHA-256 starting values.
    sha256_iv init_values (
        .iv(initial)
    );

    // Connect the hash core to the demo signals.
    sha256_core core (
        .clk(Clock),
        .rst(Reset),
        .start(start),
        .block(PADDED_ABC),
        .hin(initial),
        .hout(hash),
        .done(done),
        .busy()
    );

    always @(posedge Clock) begin
        //  reset config and makes it on initial state
        if (Reset) begin
            start  <= 1'b1;
            passed <= 1'b0;
            failed <= 1'b0;
        end
        else begin
            // starts after release
            start <= 1'b0;

            if (done) begin
                passed <= (hash == EXPECTED); // 1 if hash match
                failed <= (hash != EXPECTED); // 1 if hash dont match
            end
        end
    end

    // LED outputs
    assign LEDR[0] = passed;
    assign LEDR[1] = failed;
    assign LEDR[9:2] = 8'b0;

endmodule