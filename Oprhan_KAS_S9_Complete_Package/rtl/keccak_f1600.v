// keccak_f1600.v - OPRHAN MINER FPGA CORE (4-Core DRAM Edition)
// Keccak-f[1600] permutation, 24 rounds, 1 round per clock.
// Synthesizable on XC7Z010. ~2800 LUTs, 0 BRAM, 0 DSP.
`timescale 1ns / 1ps
module keccak_f1600 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_out,
    output reg           done
);
    reg [1599:0] state;
    reg [4:0]    round;
    reg          busy;

    function [63:0] rc(input [4:0] r);
        case (r)
            5'd0:  rc = 64'h0000000000000001;
            5'd1:  rc = 64'h0000000000008082;
            5'd2:  rc = 64'h800000000000808A;
            5'd3:  rc = 64'h8000000080008000;
            5'd4:  rc = 64'h000000000000808B;
            5'd5:  rc = 64'h0000000080000001;
            5'd6:  rc = 64'h8000000080008081;
            5'd7:  rc = 64'h0000000000008009;
            5'd8:  rc = 64'h000000000000008A;
            5'd9:  rc = 64'h0000000000000088;
            5'd10: rc = 64'h0000000080008009;
            5'd11: rc = 64'h000000008000000A;
            5'd12: rc = 64'h000000008000808B;
            5'd13: rc = 64'h800000000000008B;
            5'd14: rc = 64'h8000000000008089;
            5'd15: rc = 64'h8000000000008003;
            5'd16: rc = 64'h8000000000008002;
            5'd17: rc = 64'h8000000000000080;
            5'd18: rc = 64'h000000000000800A;
            5'd19: rc = 64'h800000008000000A;
            5'd20: rc = 64'h8000000080008081;
            5'd21: rc = 64'h8000000000008080;
            5'd22: rc = 64'h0000000080000001;
            default: rc = 64'h8000000080008008;
        endcase
    endfunction

    function [63:0] lane(input [1599:0] s, input [2:0] x, input [2:0] y);
        lane = s[(x + 5*y)*64 +: 64];
    endfunction

    function [5:0] rho_off(input [2:0] x, input [2:0] y);
        case ({x,y})
            6'b000_000: rho_off = 6'd0;
            6'b001_000: rho_off = 6'd1;
            6'b010_000: rho_off = 6'd62;
            6'b011_000: rho_off = 6'd28;
            6'b100_000: rho_off = 6'd27;
            6'b000_001: rho_off = 6'd36;
            6'b001_001: rho_off = 6'd44;
            6'b010_001: rho_off = 6'd6;
            6'b011_001: rho_off = 6'd55;
            6'b100_001: rho_off = 6'd20;
            6'b000_010: rho_off = 6'd3;
            6'b001_010: rho_off = 6'd10;
            6'b010_010: rho_off = 6'd43;
            6'b011_010: rho_off = 6'd25;
            6'b100_010: rho_off = 6'd39;
            6'b000_011: rho_off = 6'd41;
            6'b001_011: rho_off = 6'd45;
            6'b010_011: rho_off = 6'd15;
            6'b011_011: rho_off = 6'd21;
            6'b100_011: rho_off = 6'd8;
            6'b000_100: rho_off = 6'd18;
            6'b001_100: rho_off = 6'd2;
            6'b010_100: rho_off = 6'd61;
            6'b011_100: rho_off = 6'd56;
            6'b100_100: rho_off = 6'd14;
            default:    rho_off = 6'd0;
        endcase
    endfunction

    function [63:0] rotl64(input [63:0] v, input [5:0] n);
        rotl64 = (v << n) | (v >> (64 - n));
    endfunction

    function [1599:0] keccak_round(input [1599:0] s, input [4:0] rnd);
        reg [63:0]   C [0:4];
        reg [63:0]   D [0:4];
        reg [1599:0] t1;
        reg [63:0]   B [0:24];
        integer      x, y;
        reg [63:0]   tmp;
        begin
            for (x = 0; x < 5; x = x + 1)
                C[x] = lane(s, x[2:0], 3'd0) ^ lane(s, x[2:0], 3'd1) ^
                       lane(s, x[2:0], 3'd2) ^ lane(s, x[2:0], 3'd3) ^
                       lane(s, x[2:0], 3'd4);
            for (x = 0; x < 5; x = x + 1)
                D[x] = C[(x + 4) % 5] ^ rotl64(C[(x + 1) % 5], 6'd1);
            for (x = 0; x < 5; x = x + 1)
                for (y = 0; y < 5; y = y + 1)
                    t1[(x + 5*y)*64 +: 64] = lane(s, x[2:0], y[2:0]) ^ D[x];
            for (x = 0; x < 5; x = x + 1)
                for (y = 0; y < 5; y = y + 1)
                    B[y + 5*((2*x + 3*y) % 5)] = rotl64(lane(t1, x[2:0], y[2:0]), rho_off(x[2:0], y[2:0]));
            for (x = 0; x < 5; x = x + 1) begin
                for (y = 0; y < 5; y = y + 1) begin
                    tmp = B[x + 5*y] ^ ((~B[((x + 1) % 5) + 5*y]) & B[((x + 2) % 5) + 5*y]);
                    if (x == 0 && y == 0)
                        tmp = tmp ^ rc(rnd);
                    keccak_round[(x + 5*y)*64 +: 64] = tmp;
                end
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= 1600'd0;
            round     <= 5'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
            state_out <= 1600'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                state <= state_in;
                round <= 5'd0;
                busy  <= 1'b1;
            end else if (busy) begin
                if (round == 5'd23) begin
                    state_out <= keccak_round(state, round);
                    done      <= 1'b1;
                    busy      <= 1'b0;
                end else begin
                    state <= keccak_round(state, round);
                    round <= round + 5'd1;
                end
            end
        end
    end
endmodule
