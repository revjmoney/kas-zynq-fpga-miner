// dram_job_dma.v - AXI4-Master (64-bit) Direct DRAM Job Loader for Zynq S_AXI_HP0
`timescale 1ns / 1ps
module dram_job_dma (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [31:0]   dram_base_addr,
    output reg           busy,
    output reg           done,
    output reg           err,
    output reg  [255:0]  target_out,
    output reg  [63:0]   nonce_start_out,
    output reg  [63:0]   nonce_end_out,
    output reg  [1087:0] block_out,
    output reg  [63:0]   job_id_out,
    output reg           mat_wr_en,
    output reg  [7:0]    mat_wr_addr,
    output reg  [63:0]   mat_wr_data,
    output reg  [31:0]   m_axi_araddr,
    output wire [7:0]    m_axi_arlen,
    output wire [2:0]    m_axi_arsize,
    output wire [1:0]    m_axi_arburst,
    output wire [3:0]    m_axi_arcache,
    output wire [2:0]    m_axi_arprot,
    output reg           m_axi_arvalid,
    input  wire          m_axi_arready,
    input  wire [63:0]   m_axi_rdata,
    input  wire [1:0]    m_axi_rresp,
    input  wire          m_axi_rlast,
    input  wire          m_axi_rvalid,
    output reg           m_axi_rready
);
    localparam integer TOTAL_BURSTS = 35;

    assign m_axi_arlen   = 8'd7;     // 8 beats x 8 bytes = 64 bytes per burst
    assign m_axi_arsize  = 3'b011;   // 64-bit
    assign m_axi_arburst = 2'b01;    // INCR
    assign m_axi_arcache = 4'b0011;  // Normal Non-cacheable Bufferable
    assign m_axi_arprot  = 3'b000;

    localparam S_IDLE = 2'd0, S_ADDR = 2'd1, S_DATA = 2'd2, S_DONE = 2'd3;
    reg [1:0] state;
    reg [5:0] burst_cnt;
    reg [8:0] beat_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            err             <= 1'b0;
            m_axi_araddr    <= 32'd0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            burst_cnt       <= 6'd0;
            beat_idx        <= 9'd0;
            mat_wr_en       <= 1'b0;
            mat_wr_addr     <= 8'd0;
            mat_wr_data     <= 64'd0;
            target_out      <= 256'd0;
            nonce_start_out <= 64'd0;
            nonce_end_out   <= 64'd0;
            block_out       <= 1088'd0;
            job_id_out      <= 64'd0;
        end else begin
            done      <= 1'b0;
            mat_wr_en <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        busy          <= 1'b1;
                        err           <= 1'b0;
                        burst_cnt     <= 6'd0;
                        beat_idx      <= 9'd0;
                        m_axi_araddr  <= dram_base_addr;
                        m_axi_arvalid <= 1'b1;
                        state         <= S_ADDR;
                    end
                end
                S_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_DATA;
                    end
                end
                S_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (m_axi_rresp != 2'b00)
                            err <= 1'b1;

                        if (beat_idx < 9'd4) begin
                            target_out[beat_idx[1:0]*64 +: 64] <= m_axi_rdata;
                        end else if (beat_idx == 9'd4) begin
                            nonce_start_out <= m_axi_rdata;
                        end else if (beat_idx == 9'd5) begin
                            nonce_end_out <= m_axi_rdata;
                        end else if (beat_idx >= 9'd6 && beat_idx <= 9'd22) begin
                            block_out[(beat_idx - 9'd6)*64 +: 64] <= m_axi_rdata;
                        end else if (beat_idx == 9'd23) begin
                            job_id_out <= m_axi_rdata;
                        end else if (beat_idx >= 9'd24 && beat_idx <= 9'd279) begin
                            mat_wr_en   <= 1'b1;
                            mat_wr_addr <= beat_idx - 9'd24;
                            mat_wr_data <= m_axi_rdata;
                        end

                        beat_idx <= beat_idx + 9'd1;

                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            if (burst_cnt == TOTAL_BURSTS - 1) begin
                                state <= S_DONE;
                            end else begin
                                burst_cnt     <= burst_cnt + 6'd1;
                                m_axi_araddr  <= m_axi_araddr + 32'd64;
                                m_axi_arvalid <= 1'b1;
                                state         <= S_ADDR;
                            end
                        end
                    end
                end
                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
