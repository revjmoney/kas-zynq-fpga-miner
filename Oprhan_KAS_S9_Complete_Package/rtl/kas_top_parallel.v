// kas_top_parallel.v - Multi-Core Parallel KAS Engine + Zynq HP0 DRAM DMA
`timescale 1ns / 1ps
module kas_top_parallel #(
    parameter integer NUM_CORES = 4
)(
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [11:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [11:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    output wire [31:0] m_axi_hp0_araddr,
    output wire [7:0]  m_axi_hp0_arlen,
    output wire [2:0]  m_axi_hp0_arsize,
    output wire [1:0]  m_axi_hp0_arburst,
    output wire [3:0]  m_axi_hp0_arcache,
    output wire [2:0]  m_axi_hp0_arprot,
    output wire        m_axi_hp0_arvalid,
    input  wire        m_axi_hp0_arready,
    input  wire [63:0] m_axi_hp0_rdata,
    input  wire [1:0]  m_axi_hp0_rresp,
    input  wire        m_axi_hp0_rlast,
    input  wire        m_axi_hp0_rvalid,
    output wire        m_axi_hp0_rready,
    output wire        irq
);
    reg        enable_r;
    reg        soft_reset_pulse;
    reg        clear_found_pulse;
    reg        dma_start_pulse;
    reg [31:0] dram_base_addr;
    reg        dma_done_latched;

    wire core_rst_n = s_axi_aresetn & ~soft_reset_pulse;

    wire          dma_busy;
    wire          dma_done;
    wire          dma_err;
    wire [255:0]  job_target;
    wire [63:0]   job_nonce_start;
    wire [63:0]   job_nonce_end;
    wire [1087:0] job_block;
    wire [63:0]   job_id;
    wire          mat_wr_en;
    wire [7:0]    mat_wr_addr;
    wire [63:0]   mat_wr_data;

    dram_job_dma u_dma (
        .clk            (s_axi_aclk),
        .rst_n          (core_rst_n),
        .start          (dma_start_pulse),
        .dram_base_addr (dram_base_addr),
        .busy           (dma_busy),
        .done           (dma_done),
        .err            (dma_err),
        .target_out     (job_target),
        .nonce_start_out(job_nonce_start),
        .nonce_end_out  (job_nonce_end),
        .block_out      (job_block),
        .job_id_out     (job_id),
        .mat_wr_en      (mat_wr_en),
        .mat_wr_addr    (mat_wr_addr),
        .mat_wr_data    (mat_wr_data),
        .m_axi_araddr   (m_axi_hp0_araddr),
        .m_axi_arlen    (m_axi_hp0_arlen),
        .m_axi_arsize   (m_axi_hp0_arsize),
        .m_axi_arburst  (m_axi_hp0_arburst),
        .m_axi_arcache  (m_axi_hp0_arcache),
        .m_axi_arprot   (m_axi_hp0_arprot),
        .m_axi_arvalid  (m_axi_hp0_arvalid),
        .m_axi_arready  (m_axi_hp0_arready),
        .m_axi_rdata    (m_axi_hp0_rdata),
        .m_axi_rresp    (m_axi_hp0_rresp),
        .m_axi_rlast    (m_axi_hp0_rlast),
        .m_axi_rvalid   (m_axi_hp0_rvalid),
        .m_axi_rready   (m_axi_hp0_rready)
    );

    wire [NUM_CORES-1:0] lane_busy;
    wire [NUM_CORES-1:0] lane_found;
    wire [NUM_CORES-1:0] lane_exhausted;
    wire [63:0]          lane_found_nonce [0:NUM_CORES-1];
    wire [255:0]         lane_found_hash  [0:NUM_CORES-1];
    wire [63:0]          lane_hashes_done [0:NUM_CORES-1];

    wire cores_run_en = enable_r & ~dma_busy & ~dma_start_pulse;

    genvar g;
    generate
        for (g = 0; g < NUM_CORES; g = g + 1) begin : gen_lanes
            kas_core_lane #(
                .CORE_ID  (g),
                .NUM_CORES(NUM_CORES)
            ) u_lane (
                .clk           (s_axi_aclk),
                .rst_n         (core_rst_n),
                .enable        (cores_run_en),
                .clear_found   (clear_found_pulse | dma_start_pulse),
                .block_template(job_block),
                .nonce_start   (job_nonce_start),
                .nonce_end     (job_nonce_end),
                .target        (job_target),
                .mat_wr_en     (mat_wr_en),
                .mat_wr_addr   (mat_wr_addr),
                .mat_wr_data   (mat_wr_data),
                .found_nonce   (lane_found_nonce[g]),
                .found_hash    (lane_found_hash[g]),
                .found         (lane_found[g]),
                .exhausted     (lane_exhausted[g]),
                .hashes_done   (lane_hashes_done[g]),
                .busy          (lane_busy[g])
            );
        end
    endgenerate

    wire any_busy      = (|lane_busy) | dma_busy;
    wire any_found     = |lane_found;
    wire all_exhausted = &lane_exhausted;

    reg [3:0]   win_lane;
    reg [63:0]  win_nonce;
    reg [255:0] win_hash;
    reg [63:0]  total_hashes;
    integer idx;

    always @(*) begin
        win_lane     = 4'd0;
        win_nonce    = lane_found_nonce[0];
        win_hash     = lane_found_hash[0];
        total_hashes = 64'd0;
        for (idx = NUM_CORES - 1; idx >= 0; idx = idx - 1) begin
            if (lane_found[idx]) begin
                win_lane  = idx[3:0];
                win_nonce = lane_found_nonce[idx];
                win_hash  = lane_found_hash[idx];
            end
        end
        for (idx = 0; idx < NUM_CORES; idx = idx + 1) begin
            total_hashes = total_hashes + lane_hashes_done[idx];
        end
    end

    assign irq = any_found | all_exhausted;

    wire [9:0] wr_idx = s_axi_awaddr[11:2];
    wire [9:0] rd_idx = s_axi_araddr[11:2];

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready     <= 1'b0;
            s_axi_wready      <= 1'b0;
            s_axi_bvalid      <= 1'b0;
            s_axi_bresp       <= 2'b00;
            enable_r          <= 1'b0;
            soft_reset_pulse  <= 1'b0;
            clear_found_pulse <= 1'b0;
            dma_start_pulse   <= 1'b0;
            dram_base_addr    <= 32'd0;
            dma_done_latched  <= 1'b0;
        end else begin
            s_axi_awready     <= 1'b0;
            s_axi_wready      <= 1'b0;
            soft_reset_pulse  <= 1'b0;
            clear_found_pulse <= 1'b0;
            dma_start_pulse   <= 1'b0;

            if (dma_done)
                dma_done_latched <= 1'b1;

            if (s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid && !s_axi_awready) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;

                case (wr_idx)
                    10'd0: begin
                        if (s_axi_wstrb[0]) begin
                            enable_r          <= s_axi_wdata[0];
                            soft_reset_pulse  <= s_axi_wdata[1];
                            clear_found_pulse <= s_axi_wdata[2];
                            dma_start_pulse   <= s_axi_wdata[3];
                            if (s_axi_wdata[1] || s_axi_wdata[3])
                                dma_done_latched <= 1'b0;
                        end
                    end
                    10'd2: begin
                        if (s_axi_wstrb[0]) dram_base_addr[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) dram_base_addr[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) dram_base_addr[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) dram_base_addr[31:24] <= s_axi_wdata[31:24];
                    end
                    default: ;
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            s_axi_arready <= 1'b0;
            if (s_axi_arvalid && !s_axi_rvalid && !s_axi_arready) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                case (rd_idx)
                    10'd0:  s_axi_rdata <= {31'd0, enable_r};
                    10'd1:  s_axi_rdata <= {26'd0, dma_err, dma_done_latched, dma_busy, all_exhausted, any_found, any_busy};
                    10'd2:  s_axi_rdata <= dram_base_addr;
                    10'd3:  s_axi_rdata <= NUM_CORES[31:0];
                    10'd4:  s_axi_rdata <= 32'h4B415334; // "KAS4"
                    10'd5:  s_axi_rdata <= job_id[31:0];
                    10'd6:  s_axi_rdata <= job_id[63:32];
                    10'd7:  s_axi_rdata <= {{(32-NUM_CORES){1'b0}}, lane_found};
                    10'd8:  s_axi_rdata <= {{(32-NUM_CORES){1'b0}}, lane_exhausted};
                    10'd9:  s_axi_rdata <= {28'd0, win_lane};
                    10'd10: s_axi_rdata <= win_nonce[31:0];
                    10'd11: s_axi_rdata <= win_nonce[63:32];
                    10'd12: s_axi_rdata <= win_hash[31:0];
                    10'd13: s_axi_rdata <= win_hash[63:32];
                    10'd14: s_axi_rdata <= win_hash[95:64];
                    10'd15: s_axi_rdata <= win_hash[127:96];
                    10'd16: s_axi_rdata <= win_hash[159:128];
                    10'd17: s_axi_rdata <= win_hash[191:160];
                    10'd18: s_axi_rdata <= win_hash[223:192];
                    10'd19: s_axi_rdata <= win_hash[255:224];
                    10'd20: s_axi_rdata <= total_hashes[31:0];
                    10'd21: s_axi_rdata <= total_hashes[63:32];
                    default: s_axi_rdata <= 32'h00000000;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
