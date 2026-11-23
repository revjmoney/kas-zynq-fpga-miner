// matrix_ram_64x256.v - Simple Dual-Port BRAM (64 rows x 256 bits = 16 Kbit)
// Uses 4x RAMB18E1 (2x RAMB36E1) per core out of 60 BRAM36 blocks on XC7Z010.
`timescale 1ns / 1ps
module matrix_ram_64x256 (
    input  wire         clk,
    input  wire         wr_en,
    input  wire [7:0]   wr_addr,
    input  wire [63:0]  wr_data,
    input  wire [5:0]   rd_addr,
    output reg  [255:0] rd_data
);
    (* ram_style = "block" *) reg [63:0] bank0 [0:63];
    (* ram_style = "block" *) reg [63:0] bank1 [0:63];
    (* ram_style = "block" *) reg [63:0] bank2 [0:63];
    (* ram_style = "block" *) reg [63:0] bank3 [0:63];

    wire [5:0] wr_row = wr_addr[7:2];
    wire [1:0] wr_sel = wr_addr[1:0];

    always @(posedge clk) begin
        if (wr_en) begin
            case (wr_sel)
                2'd0: bank0[wr_row] <= wr_data;
                2'd1: bank1[wr_row] <= wr_data;
                2'd2: bank2[wr_row] <= wr_data;
                2'd3: bank3[wr_row] <= wr_data;
            endcase
        end
        rd_data <= {bank3[rd_addr], bank2[rd_addr], bank1[rd_addr], bank0[rd_addr]};
    end
endmodule
