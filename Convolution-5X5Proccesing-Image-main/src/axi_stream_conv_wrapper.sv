`timescale 1ns/1ps

module axi_stream_conv_wrapper #(
    parameter int DATA_W = 24,
    parameter int COEFF_W = 16,
    parameter int KSIZE = 5,
    parameter int KERNEL_Q = 8,
    parameter int IMAGE_WIDTH = 640
) (
    input  logic                           aclk,
    input  logic                           aresetn,

    input  logic                           s_axis_tvalid,
    output logic                           s_axis_tready,
    input  logic [DATA_W-1:0]              s_axis_tdata,

    output logic                           m_axis_tvalid,
    input  logic                           m_axis_tready,
    output logic [DATA_W-1:0]              m_axis_tdata,

    input  logic                           kernel_wr_en,
    input  logic [$clog2(KSIZE*KSIZE)-1:0] kernel_wr_addr,
    input  logic signed [COEFF_W-1:0]      kernel_wr_data,

    output logic                           overflow_flag
);
    logic rst;
    logic in_valid;
    logic [DATA_W-1:0] in_pixel;
    logic core_out_valid;
    logic [DATA_W-1:0] core_out_pixel;

    logic out_buf_valid;
    logic [DATA_W-1:0] out_buf_data;

    assign rst = ~aresetn;

    // Conservative flow control: accept input only when output buffer can move.
    assign s_axis_tready = (~out_buf_valid) | m_axis_tready;
    assign in_valid = s_axis_tvalid & s_axis_tready;
    assign in_pixel = s_axis_tdata;

    top_convolution #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .KSIZE(KSIZE),
        .KERNEL_Q(KERNEL_Q)
    ) u_top_convolution (
        .clk(aclk),
        .rst(rst),
        .in_valid(in_valid),
        .in_pixel(in_pixel),
        .kernel_wr_en(kernel_wr_en),
        .kernel_wr_addr(kernel_wr_addr),
        .kernel_wr_data(kernel_wr_data),
        .out_valid(core_out_valid),
        .out_pixel(core_out_pixel)
    );

    always_ff @(posedge aclk) begin
        if (rst) begin
            out_buf_valid <= 1'b0;
            out_buf_data <= '0;
            overflow_flag <= 1'b0;
        end else begin
            if (out_buf_valid && m_axis_tready) begin
                out_buf_valid <= 1'b0;
            end

            if (core_out_valid) begin
                if (!out_buf_valid || m_axis_tready) begin
                    out_buf_valid <= 1'b1;
                    out_buf_data <= core_out_pixel;
                end else begin
                    overflow_flag <= 1'b1;
                end
            end
        end
    end

    assign m_axis_tvalid = out_buf_valid;
    assign m_axis_tdata = out_buf_data;
endmodule
