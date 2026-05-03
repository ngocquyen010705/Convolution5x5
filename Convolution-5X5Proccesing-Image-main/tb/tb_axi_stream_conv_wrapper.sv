`timescale 1ns/1ps

module tb_axi_stream_conv_wrapper;
    localparam int DATA_W = 24;

    logic aclk;
    logic aresetn;

    logic s_axis_tvalid;
    logic s_axis_tready;
    logic [DATA_W-1:0] s_axis_tdata;

    logic m_axis_tvalid;
    logic m_axis_tready;
    logic [DATA_W-1:0] m_axis_tdata;

    logic kernel_wr_en;
    logic [4:0] kernel_wr_addr;
    logic signed [15:0] kernel_wr_data;
    logic overflow_flag;

    int i;
    int accepted;
    int produced;

    axi_stream_conv_wrapper #(
        .IMAGE_WIDTH(16)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .kernel_wr_en(kernel_wr_en),
        .kernel_wr_addr(kernel_wr_addr),
        .kernel_wr_data(kernel_wr_data),
        .overflow_flag(overflow_flag)
    );

    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    task write_kernel(input [4:0] addr, input signed [15:0] data);
        begin
            @(negedge aclk);
            kernel_wr_en = 1'b1;
            kernel_wr_addr = addr;
            kernel_wr_data = data;
            @(posedge aclk);
            @(negedge aclk);
            kernel_wr_en = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("../sim/dump_axi_wrapper.vcd");
        $dumpvars(0, tb_axi_stream_conv_wrapper);

        aresetn = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata = '0;
        m_axis_tready = 1'b1;
        kernel_wr_en = 1'b0;
        kernel_wr_addr = '0;
        kernel_wr_data = '0;
        accepted = 0;
        produced = 0;

        repeat (6) @(posedge aclk);
        aresetn = 1'b1;

        for (i = 0; i < 25; i++) begin
            if (i == 12) begin
                write_kernel(i[4:0], 16'sd16);
            end else begin
                write_kernel(i[4:0], 16'sd0);
            end
        end

        for (i = 0; i < 16*16; i++) begin
            @(negedge aclk);
            s_axis_tvalid = 1'b1;
            s_axis_tdata = {8'(i), 8'(i>>1), 8'(i>>2)};
            // Current core does not support downstream backpressure propagation.
            // Keep sink always ready in this phase; randomized tready comes in AXI hardening phase.
            m_axis_tready = 1'b1;

            @(posedge aclk);
            if (s_axis_tvalid && s_axis_tready) begin
                accepted = accepted + 1;
            end
        end

        @(negedge aclk);
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b1;

        repeat (200) @(posedge aclk);

        if (overflow_flag) begin
            $display("TB FAIL: overflow_flag asserted");
            $fatal;
        end

        if (accepted != 256) begin
            $display("TB FAIL: accepted=%0d expected=256", accepted);
            $fatal;
        end

        $display("TB PASS: accepted=%0d produced=%0d", accepted, produced);
        $finish;
    end

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            produced = produced + 1;
        end
    end
endmodule
