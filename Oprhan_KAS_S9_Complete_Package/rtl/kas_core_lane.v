// kas_core_lane.v - Independent Parallel Worker Core with Strided Nonce Engine
`timescale 1ns / 1ps
module kas_core_lane #(
    parameter integer CORE_ID   = 0,
    parameter integer NUM_CORES = 4
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          enable,
    input  wire          clear_found,
    input  wire [1087:0] block_template,
    input  wire [63:0]   nonce_start,
    input  wire [63:0]   nonce_end,
    input  wire [255:0]  target,
    input  wire          mat_wr_en,
    input  wire [7:0]    mat_wr_addr,
    input  wire [63:0]   mat_wr_data,
    output reg  [63:0]   found_nonce,
    output reg  [255:0]  found_hash,
    output reg           found,
    output reg           exhausted,
    output reg  [63:0]   hashes_done,
    output reg           busy
);
    reg [63:0]   nonce;
    reg [1087:0] block_in;
    reg          kh_start;
    wire [255:0] kh_hash;
    wire         kh_done;

    wire [5:0]   mat_rd_addr;
    wire [255:0] mat_rd_data;

    localparam S_IDLE  = 2'd0,
               S_HASH  = 2'd1,
               S_CHECK = 2'd2,
               S_HALT  = 2'd3;
    reg [1:0] state;

    matrix_ram_64x256 u_mat_ram (
        .clk    (clk),
        .wr_en  (mat_wr_en),
        .wr_addr(mat_wr_addr),
        .wr_data(mat_wr_data),
        .rd_addr(mat_rd_addr),
        .rd_data(mat_rd_data)
    );

    kheavyhash_fast u_kh (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (kh_start),
        .block_in   (block_in),
        .mat_rd_addr(mat_rd_addr),
        .mat_rd_data(mat_rd_data),
        .hash_out   (kh_hash),
        .done       (kh_done)
    );

    wire [63:0] init_nonce = nonce_start + CORE_ID[63:0];
    wire [63:0] next_nonce = nonce + NUM_CORES[63:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nonce       <= 64'd0;
            block_in    <= 1088'd0;
            hashes_done <= 64'd0;
            found       <= 1'b0;
            exhausted   <= 1'b0;
            found_nonce <= 64'd0;
            found_hash  <= 256'd0;
            busy        <= 1'b0;
            state       <= S_IDLE;
            kh_start    <= 1'b0;
        end else begin
            kh_start <= 1'b0;

            if (clear_found) begin
                found     <= 1'b0;
                exhausted <= 1'b0;
            end

            if (!enable) begin
                busy  <= 1'b0;
                state <= S_IDLE;
            end else begin
                case (state)
                    S_IDLE: begin
                        if (!found && !exhausted) begin
                            if (init_nonce > nonce_end) begin
                                exhausted <= 1'b1;
                                busy      <= 1'b0;
                                state     <= S_HALT;
                            end else begin
                                nonce       <= init_nonce;
                                hashes_done <= 64'd0;
                                busy        <= 1'b1;
                                state       <= S_HASH;
                            end
                        end else begin
                            busy <= 1'b0;
                        end
                    end
                    S_HASH: begin
                        block_in <= {block_template[1087:64], nonce};
                        kh_start <= 1'b1;
                        state    <= S_CHECK;
                    end
                    S_CHECK: begin
                        if (kh_done) begin
                            hashes_done <= hashes_done + 64'd1;
                            if (kh_hash <= target) begin
                                found       <= 1'b1;
                                found_nonce <= nonce;
                                found_hash  <= kh_hash;
                                busy        <= 1'b0;
                                state       <= S_HALT;
                            end else if (next_nonce > nonce_end || next_nonce < nonce) begin
                                exhausted <= 1'b1;
                                busy      <= 1'b0;
                                state     <= S_HALT;
                            end else begin
                                nonce <= next_nonce;
                                state <= S_HASH;
                            end
                        end
                    end
                    S_HALT: begin
                        busy <= 1'b0;
                        if (clear_found)
                            state <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
