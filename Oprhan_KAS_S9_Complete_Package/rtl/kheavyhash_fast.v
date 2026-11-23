// kheavyhash_fast.v - Pipelined-Matrix kHeavyHash Engine (~116 clocks/hash)
`timescale 1ns / 1ps
module kheavyhash_fast (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [1087:0] block_in,
    output wire [5:0]    mat_rd_addr,
    input  wire [255:0]  mat_rd_data,
    output reg  [255:0]  hash_out,
    output reg           done
);
    localparam S_IDLE    = 3'd0,
               S_KECCAK1 = 3'd1,
               S_MATRIX  = 3'd2,
               S_KECCAK2 = 3'd3,
               S_DONE    = 3'd4;

    reg [2:0]    state;
    reg [1599:0] keccak_in;
    reg          keccak_start;
    wire [1599:0] keccak_out;
    wire         keccak_done;

    reg          matrix_start;
    wire [1023:0] matrix_out;
    wire         matrix_done;

    wire [255:0]  mat_vec            = keccak_out[255:0];
    wire [1087:0] padded_matrix_rate = {1'b1, 62'd0, 1'b1, matrix_out};

    keccak_f1600 u_keccak (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (keccak_start),
        .state_in (keccak_in),
        .state_out(keccak_out),
        .done     (keccak_done)
    );

    matrix_mult_64x64_bram u_mat (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (matrix_start),
        .vec_in     (mat_vec),
        .mat_rd_addr(mat_rd_addr),
        .mat_rd_data(mat_rd_data),
        .vec_out    (matrix_out),
        .done       (matrix_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            done         <= 1'b0;
            hash_out     <= 256'd0;
            keccak_start <= 1'b0;
            matrix_start <= 1'b0;
            keccak_in    <= 1600'd0;
        end else begin
            keccak_start <= 1'b0;
            matrix_start <= 1'b0;
            done         <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        keccak_in    <= {512'd0, block_in};
                        keccak_start <= 1'b1;
                        state        <= S_KECCAK1;
                    end
                end
                S_KECCAK1: begin
                    if (keccak_done) begin
                        matrix_start <= 1'b1;
                        state        <= S_MATRIX;
                    end
                end
                S_MATRIX: begin
                    if (matrix_done) begin
                        keccak_in    <= {512'd0, padded_matrix_rate};
                        keccak_start <= 1'b1;
                        state        <= S_KECCAK2;
                    end
                end
                S_KECCAK2: begin
                    if (keccak_done) begin
                        hash_out <= keccak_out[255:0];
                        done     <= 1'b1;
                        state    <= S_DONE;
                    end
                end
                S_DONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
