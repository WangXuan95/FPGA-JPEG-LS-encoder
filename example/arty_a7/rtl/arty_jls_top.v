// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com

// Arty A7-100T top for the JPEG-LS encoder demo.
// 100 MHz input clock → MMCM → 50 MHz fabric clock
// EJTAG-AXI bridge from fpgacapZero provides AXI4 over JTAG
// BTN0 = async reset (active high)
// LED0-3 reflect encoder status (see axi_jls_ctrl)

`timescale 1ns/1ps

module arty_jls_top (
    input  wire       clk,        // 100 MHz, pin E3
    input  wire [3:0] btn,        // btn[0] = reset
    output wire [3:0] led
);

    // -----------------------------------------------------------------------
    // MMCM: 100 MHz -> 50 MHz
    // VCO = 100 * 10 / 1 = 1000 MHz; CLKOUT0 = 1000 / 20 = 50 MHz
    // -----------------------------------------------------------------------
    wire clk50, clk50_raw;
    wire clkfb, clkfb_buf;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKIN1_PERIOD    (10.0),
        .CLKFBOUT_MULT_F  (10.0),
        .DIVCLK_DIVIDE    (1),
        .CLKOUT0_DIVIDE_F (20.0),
        .CLKOUT0_PHASE    (0.0),
        .STARTUP_WAIT     ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk),
        .CLKFBIN  (clkfb_buf),
        .CLKFBOUT (clkfb),
        .CLKOUT0  (clk50_raw),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG u_bufg_fb  (.I(clkfb),    .O(clkfb_buf));
    BUFG u_bufg_50  (.I(clk50_raw), .O(clk50));

    // -----------------------------------------------------------------------
    // Reset synchroniser (to clk50)
    // -----------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [3:0] rst_sync;
    wire async_rst = btn[0] | ~mmcm_locked;
    always @(posedge clk50 or posedge async_rst) begin
        if(async_rst) rst_sync <= 4'b1111;
        else          rst_sync <= {rst_sync[2:0], 1'b0};
    end
    wire rst = rst_sync[3];

    // -----------------------------------------------------------------------
    // EJTAG-AXI bridge (fpgacapZero, Xilinx 7-series wrapper)
    // -----------------------------------------------------------------------
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [7:0]  awlen, arlen;
    wire [2:0]  awsize, arsize, awprot, arprot;
    wire [1:0]  awburst, arburst, bresp, rresp;
    wire [3:0]  wstrb;
    wire        awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire        arvalid, arready, rvalid, rready, rlast;
    wire [255:0] d_tck, d_tck_e, d_axi, d_axi_e;

    fcapz_ejtagaxi_xilinx7 #(
        .ADDR_W    (32),
        .DATA_W    (32),
        .FIFO_DEPTH(256),
        .TIMEOUT   (4096)
    ) u_ejtagaxi (
        .axi_clk(clk50),
        .axi_rst(rst),
        .m_axi_awaddr (awaddr), .m_axi_awlen  (awlen),
        .m_axi_awsize (awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_awprot (awprot),
        .m_axi_wdata  (wdata),  .m_axi_wstrb  (wstrb),
        .m_axi_wvalid (wvalid), .m_axi_wready (wready),
        .m_axi_wlast  (wlast),
        .m_axi_bresp  (bresp),  .m_axi_bvalid (bvalid),
        .m_axi_bready (bready),
        .m_axi_araddr (araddr), .m_axi_arlen  (arlen),
        .m_axi_arsize (arsize), .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_arprot (arprot),
        .m_axi_rdata  (rdata),  .m_axi_rresp  (rresp),
        .m_axi_rvalid (rvalid), .m_axi_rlast  (rlast),
        .m_axi_rready (rready),
        .debug_tck(d_tck), .debug_tck_edge(d_tck_e),
        .debug_axi(d_axi), .debug_axi_edge(d_axi_e)
    );

    // -----------------------------------------------------------------------
    // JPEG-LS encoder control/glue
    // -----------------------------------------------------------------------
    axi_jls_ctrl #(
        .NEAR            (0),
        .IN_FIFO_DEPTH   (1024),
        .OUT_FIFO_DEPTH  (256),
        .SOF_HOLD_CYCLES (512)
    ) u_ctrl (
        .clk       (clk50),
        .rst       (rst),

        .s_awaddr  (awaddr), .s_awlen  (awlen),
        .s_awsize  (awsize), .s_awburst(awburst),
        .s_awvalid (awvalid), .s_awready(awready),

        .s_wdata   (wdata),  .s_wstrb  (wstrb),
        .s_wlast   (wlast),  .s_wvalid (wvalid),
        .s_wready  (wready),

        .s_bresp   (bresp),  .s_bvalid (bvalid),
        .s_bready  (bready),

        .s_araddr  (araddr), .s_arlen  (arlen),
        .s_arsize  (arsize), .s_arburst(arburst),
        .s_arvalid (arvalid), .s_arready(arready),

        .s_rdata   (rdata),  .s_rresp  (rresp),
        .s_rlast   (rlast),  .s_rvalid (rvalid),
        .s_rready  (rready),

        .leds      (led)
    );

    // AXI PROT signals unused
    assign awprot = 3'b000;
    assign arprot = 3'b000;

    wire _u = &{1'b0, d_tck, d_tck_e, d_axi, d_axi_e, 1'b0};

endmodule
