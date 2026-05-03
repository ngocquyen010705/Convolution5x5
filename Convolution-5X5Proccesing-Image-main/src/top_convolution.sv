`timescale 1ns/1ps

module top_convolution #(
    parameter int IMAGE_WIDTH = 1920,
    parameter int DATA_W = 24,
    parameter int COEFF_W = 16,
    parameter int KSIZE = 5,
    parameter int KERNEL_Q = 8
) (
    input  logic                            clk,
    input  logic                            rst,
    input  logic                            in_valid,
    input  logic [DATA_W-1:0]               in_pixel,
    input  logic                            kernel_wr_en,
    input  logic [$clog2(KSIZE*KSIZE)-1:0]  kernel_wr_addr,
    input  logic signed [COEFF_W-1:0]       kernel_wr_data,
    output logic                            out_valid,
    output logic [DATA_W-1:0]               out_pixel
);
    logic [DATA_W*KSIZE*KSIZE-1:0] window_flat;
    logic signed [COEFF_W*KSIZE*KSIZE-1:0] kernel_flat;
    logic lb_valid;

    line_buffer_4 #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .DATA_W(DATA_W),
        .KSIZE(KSIZE)
    ) u_line_buffer (
        .clk(clk),
        .rst(rst),
        .valid_in(in_valid),
        .pixel_in(in_pixel),
        .valid_out(lb_valid),
        .window_flat(window_flat)
    );

    kernel_loader #(
        .COEFF_W(COEFF_W),
        .KSIZE(KSIZE),
        .KERNEL_Q(KERNEL_Q)
    ) u_kernel_loader (
        .clk(clk),
        .rst(rst),
        .wr_en(kernel_wr_en),
        .wr_addr(kernel_wr_addr),
        .wr_data(kernel_wr_data),
        .kernel_flat(kernel_flat)
    );

    mac_array_25x3 #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .KSIZE(KSIZE),
        .KERNEL_Q(KERNEL_Q)
    ) u_mac_array (
        .clk(clk),
        .rst(rst),
        .valid_in(lb_valid),
        .window_flat(window_flat),
        .kernel_flat(kernel_flat),
        .valid_out(out_valid),
        .pixel_out(out_pixel)
    );
endmodule
