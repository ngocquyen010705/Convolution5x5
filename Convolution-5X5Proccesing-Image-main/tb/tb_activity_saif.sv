`timescale 1ns/1ps

`include "saif_clock_cfg.svh"

`ifndef TB_CLK_HALF_NS
`define TB_CLK_HALF_NS 5
`endif

module tb_activity_saif;
    localparam int IMAGE_W = 640;
    localparam int IMAGE_H = 480;
    localparam int KSIZE = 5;
    localparam int PIXELS = IMAGE_W * IMAGE_H;

    logic clk;
    logic rst;
    logic in_valid;
    logic [23:0] in_pixel;
    logic kernel_wr_en;
    logic [4:0] kernel_wr_addr;
    logic signed [15:0] kernel_wr_data;
    logic out_valid;
    logic [23:0] out_pixel;
    realtime clk_half_ns;

    int x;
    int y;
    int idx;

    logic [23:0] frame_mem [0:PIXELS-1];
    logic signed [15:0] kernel_mem [0:KSIZE*KSIZE-1];

    top_convolution #(
        .IMAGE_WIDTH(IMAGE_W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_pixel(in_pixel),
        .kernel_wr_en(kernel_wr_en),
        .kernel_wr_addr(kernel_wr_addr),
        .kernel_wr_data(kernel_wr_data),
        .out_valid(out_valid),
        .out_pixel(out_pixel)
    );

    initial begin
        clk = 1'b0;
        clk_half_ns = `TB_CLK_HALF_NS;
        if (clk_half_ns < 0.001) begin
            clk_half_ns = 0.001;
        end
        $display("TB SAIF clock half-period = %0.3f ns (period=%0.3f ns)", clk_half_ns, clk_half_ns * 2.0);
    end
    always #(clk_half_ns) clk = ~clk;

    task write_kernel(input [4:0] addr, input signed [15:0] data);
        begin
            @(negedge clk);
            kernel_wr_en   = 1'b1;
            kernel_wr_addr = addr;
            kernel_wr_data = data;
            @(posedge clk);
            @(negedge clk);
            kernel_wr_en   = 1'b0;
            kernel_wr_addr = '0;
            kernel_wr_data = '0;
        end
    endtask

    initial begin
        $readmemh("../hex/test_frame_0.hex", frame_mem);
        $readmemh("../sim/kernel.hex", kernel_mem);

        rst            = 1'b1;
        in_valid       = 1'b0;
        in_pixel       = '0;
        kernel_wr_en   = 1'b0;
        kernel_wr_addr = '0;
        kernel_wr_data = '0;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        for (idx = 0; idx < KSIZE*KSIZE; idx++) begin
            write_kernel(idx[4:0], kernel_mem[idx]);
        end

        for (y = 0; y < IMAGE_H; y++) begin
            for (x = 0; x < IMAGE_W; x++) begin
                idx = (y * IMAGE_W) + x;
                @(negedge clk);
                in_valid = 1'b1;
                in_pixel = frame_mem[idx];
                @(posedge clk);
            end
        end

        @(negedge clk);
        in_valid = 1'b0;
        in_pixel = '0;

        repeat (128) @(posedge clk);
        $display("TB SAIF DONE: streamed %0d pixels", PIXELS);
        $finish;
    end
endmodule
