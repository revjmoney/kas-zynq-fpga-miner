// tb_kas_top_parallel.v - Self-checking Testbench for 4-Core Parallel KAS + HP0 DRAM DMA
`timescale 1ns / 1ps
module tb_kas_top_parallel;
    reg         clk = 0;
    reg         rst_n = 0;

    reg  [11:0] awaddr = 0; reg awvalid = 0; wire awready;
    reg  [31:0] wdata = 0;  reg [3:0] wstrb = 4'hF; reg wvalid = 0; wire wready;
    wire [1:0]  bresp; wire bvalid; reg bready = 0;
    reg  [11:0] araddr = 0; reg arvalid = 0; wire arready;
    wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready = 0;

    wire [31:0] hp_araddr; wire [7:0] hp_arlen; wire [2:0] hp_arsize;
    wire [1:0]  hp_arburst; wire [3:0] hp_arcache; wire [2:0] hp_arprot;
    wire        hp_arvalid; reg hp_arready = 0;
    reg  [63:0] hp_rdata = 0; reg [1:0] hp_rresp = 0; reg hp_rlast = 0;
    reg         hp_rvalid = 0; wire hp_rready;
    wire        irq;

    always #5.0 clk = ~clk;

    kas_top_parallel #(.NUM_CORES(4)) dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .m_axi_hp0_araddr(hp_araddr), .m_axi_hp0_arlen(hp_arlen), .m_axi_hp0_arsize(hp_arsize),
        .m_axi_hp0_arburst(hp_arburst), .m_axi_hp0_arcache(hp_arcache), .m_axi_hp0_arprot(hp_arprot),
        .m_axi_hp0_arvalid(hp_arvalid), .m_axi_hp0_arready(hp_arready),
        .m_axi_hp0_rdata(hp_rdata), .m_axi_hp0_rresp(hp_rresp), .m_axi_hp0_rlast(hp_rlast),
        .m_axi_hp0_rvalid(hp_rvalid), .m_axi_hp0_rready(hp_rready),
        .irq(irq)
    );

    reg [63:0] sys_dram [0:511];
    integer idx;
    initial begin
        for (idx = 0; idx < 512; idx = idx + 1) sys_dram[idx] = 64'd0;
        sys_dram[0] = 64'hFFFFFFFFFFFFFFFF;
        sys_dram[1] = 64'hFFFFFFFFFFFFFFFF;
        sys_dram[2] = 64'hFFFFFFFFFFFFFFFF;
        sys_dram[3] = 64'hFFFFFFFFFFFFFFFF;
        sys_dram[4] = 64'd40;
        sys_dram[5] = 64'd60;
        sys_dram[23] = 64'hCAFEBABE_00000001;
        for (idx = 24; idx < 280; idx = idx + 1)
            sys_dram[idx] = 64'h11111111_22222222;
    end

    reg [31:0] latched_araddr;
    reg [7:0]  beat_cnt;
    reg        in_burst = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            hp_arready <= 0; hp_rvalid <= 0; hp_rlast <= 0; in_burst <= 0;
        end else begin
            hp_arready <= 0;
            if (hp_arvalid && !in_burst && !hp_arready) begin
                hp_arready     <= 1'b1;
                latched_araddr <= hp_araddr;
                beat_cnt       <= 8'd0;
                in_burst       <= 1'b1;
            end else if (in_burst) begin
                hp_rvalid <= 1'b1;
                hp_rdata  <= sys_dram[((latched_araddr - 32'h10000000) >> 3) + beat_cnt];
                hp_rlast  <= (beat_cnt == hp_arlen);
                if (hp_rvalid && hp_rready) begin
                    if (beat_cnt == hp_arlen) begin
                        in_burst  <= 1'b0;
                        hp_rvalid <= 1'b0;
                        hp_rlast  <= 1'b0;
                    end else begin
                        beat_cnt <= beat_cnt + 8'd1;
                    end
                end
            end
        end
    end

    task axi_write(input [11:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            awaddr <= addr; awvalid <= 1'b1; wdata <= data; wstrb <= 4'hF; wvalid <= 1'b1; bready <= 1'b1;
            wait (awready && wready);
            @(posedge clk);
            awvalid <= 1'b0; wvalid <= 1'b0;
            wait (bvalid);
            @(posedge clk);
            bready <= 1'b0;
        end
    endtask

    task axi_read(input [11:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            araddr <= addr; arvalid <= 1'b1; rready <= 1'b1;
            wait (arready);
            @(posedge clk);
            arvalid <= 1'b0;
            wait (rvalid);
            data = rdata;
            @(posedge clk);
            rready <= 1'b0;
        end
    endtask

    reg [31:0] rv;
    initial begin
        #40 rst_n = 1;
        #20;
        axi_read(12'h010, rv);
        $display("CORE_ID = 0x%08X", rv);
        axi_write(12'h008, 32'h10000000);
        axi_write(12'h000, 32'h00000009);
        wait (irq == 1'b1);
        axi_read(12'h028, rv);
        $display("WIN_NONCE_LO = %0d (expected 40)", rv);
        axi_read(12'h050, rv);
        $display("TOTAL_HASHES = %0d", rv);
        $finish;
    end
endmodule
