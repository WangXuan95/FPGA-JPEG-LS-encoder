// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com

// Simple single-clock BRAM-friendly FIFO for the Arty demo.
// Show-ahead (first-word-fall-through) read. Not full-featured; sized for
// the jls_encoder host-AXI path.
`timescale 1ns/1ps

module sync_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 1024       // must be power of 2
) (
    input  wire              clk,
    input  wire              rst,

    input  wire [WIDTH-1:0]  wr_data,
    input  wire              wr_en,
    output wire              full,

    output wire [WIDTH-1:0]  rd_data,
    input  wire              rd_en,
    output wire              empty,

    output reg  [$clog2(DEPTH):0] count
);
    localparam AW = $clog2(DEPTH);

    (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wptr, rptr;

    wire do_wr = wr_en & ~full;
    wire do_rd = rd_en & ~empty;

    always @(posedge clk) begin
        if(rst) begin
            wptr  <= 0;
            rptr  <= 0;
            count <= 0;
        end else begin
            if(do_wr) begin
                mem[wptr] <= wr_data;
                wptr      <= wptr + 1'b1;
            end
            if(do_rd) rptr <= rptr + 1'b1;
            case({do_wr, do_rd})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end

    assign rd_data = mem[rptr];
    assign empty   = (count == 0);
    assign full    = (count == DEPTH);
endmodule
