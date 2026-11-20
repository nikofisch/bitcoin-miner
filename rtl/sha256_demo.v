module sha256_demo (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    output wire [9:0] LEDR
);
    localparam [511:0] PADDED_ABC = {24'h616263, 1'b1, 423'b0, 64'd24};
    localparam [255:0] EXPECTED =
        256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;

    wire rst = ~KEY[0];
    wire [255:0] iv, hash;
    wire done;
    reg start, passed, failed;

    sha256_iv init_values (.iv(iv));

    sha256_core core (
        .clk(CLOCK_50),
        .rst(rst),
        .start(start),
        .block(PADDED_ABC),
        .hin(iv),
        .hout(hash),
        .done(done),
        .busy()
    );

    always @(posedge CLOCK_50) begin
        if (rst) begin
            start  <= 1'b1;
            passed <= 1'b0;
            failed <= 1'b0;
        end else begin
            // The core sees start high on the first clock after reset.
            start <= 1'b0;
            if (done) begin
                passed <= (hash == EXPECTED);
                failed <= (hash != EXPECTED);
            end
        end
    end

    assign LEDR = {8'b0, failed, passed};
endmodule