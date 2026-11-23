// matrix_mult_64x64_bram.v - Parallel-Unrolled 64x64 Matrix x Vector Multiplier
// Computes 64 dot-products in 64 clocks (64x faster than serial element-by-element).
`timescale 1ns / 1ps
module matrix_mult_64x64_bram (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [255:0]  vec_in,
    output reg  [5:0]    mat_rd_addr,
    input  wire [255:0]  mat_rd_data,
    output reg  [1023:0] vec_out,
    output reg           done
);
    reg [5:0] row_idx;
    reg       running;
    reg       valid_d1;
    reg [5:0] row_d1;

    wire [7:0] prod [0:63];
    genvar c;
    generate
        for (c = 0; c < 64; c = c + 1) begin : gen_mul
            assign prod[c] = mat_rd_data[c*4 +: 4] * vec_in[c*4 +: 4];
        end
    endgenerate

    wire [9:0] sum_s1 [0:15];
    generate
        for (c = 0; c < 16; c = c + 1) begin : gen_s1
            assign sum_s1[c] = prod[c*4] + prod[c*4+1] + prod[c*4+2] + prod[c*4+3];
        end
    endgenerate

    wire [11:0] sum_s2 [0:3];
    generate
        for (c = 0; c < 4; c = c + 1) begin : gen_s2
            assign sum_s2[c] = sum_s1[c*4] + sum_s1[c*4+1] + sum_s1[c*4+2] + sum_s1[c*4+3];
        end
    endgenerate

    wire [15:0] row_dot = {2'd0, sum_s2[0] + sum_s2[1] + sum_s2[2] + sum_s2[3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_idx     <= 6'd0;
            running     <= 1'b0;
            valid_d1    <= 1'b0;
            row_d1      <= 6'd0;
            mat_rd_addr <= 6'd0;
            vec_out     <= 1024'd0;
            done        <= 1'b0;
        end else begin
            done     <= 1'b0;
            valid_d1 <= running;
            row_d1   <= row_idx;

            if (start && !running) begin
                running     <= 1'b1;
                row_idx     <= 6'd0;
                mat_rd_addr <= 6'd0;
            end else if (running) begin
                if (row_idx == 6'd63) begin
                    running <= 1'b0;
                end else begin
                    row_idx     <= row_idx + 6'd1;
                    mat_rd_addr <= row_idx + 6'd1;
                end
            end

            if (valid_d1) begin
                vec_out[row_d1*16 +: 16] <= row_dot;
                if (row_d1 == 6'd63) begin
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
