`timescale 1ns/1ps

module axi_lite_kernel_ctrl #(
    parameter int COEFF_W = 16,
    parameter int KSIZE = 5,
    parameter int ADDR_W = 6
) (
    input  logic                           aclk,
    input  logic                           aresetn,

    input  logic [ADDR_W-1:0]              s_axil_awaddr,
    input  logic                           s_axil_awvalid,
    output logic                           s_axil_awready,

    input  logic [31:0]                    s_axil_wdata,
    input  logic [3:0]                     s_axil_wstrb,
    input  logic                           s_axil_wvalid,
    output logic                           s_axil_wready,

    output logic [1:0]                     s_axil_bresp,
    output logic                           s_axil_bvalid,
    input  logic                           s_axil_bready,

    input  logic [ADDR_W-1:0]              s_axil_araddr,
    input  logic                           s_axil_arvalid,
    output logic                           s_axil_arready,

    output logic [31:0]                    s_axil_rdata,
    output logic [1:0]                     s_axil_rresp,
    output logic                           s_axil_rvalid,
    input  logic                           s_axil_rready,

    output logic                           kernel_wr_en,
    output logic [$clog2(KSIZE*KSIZE)-1:0] kernel_wr_addr,
    output logic signed [COEFF_W-1:0]      kernel_wr_data,
    input  logic                           overflow_flag
);
    localparam int TAPS = KSIZE * KSIZE;

    logic [31:0] reg_ctrl;
    logic [31:0] reg_status;

    logic [ADDR_W-1:0] awaddr_latched;
    logic              awaddr_valid;
    logic [ADDR_W-1:0] write_addr;

    assign s_axil_awready = 1'b1;
    assign s_axil_wready = 1'b1;
    assign s_axil_arready = 1'b1;

    assign s_axil_bresp = 2'b00;
    assign s_axil_rresp = 2'b00;

    always_comb begin
        if (s_axil_awvalid) begin
            write_addr = s_axil_awaddr;
        end else begin
            write_addr = awaddr_latched;
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            reg_ctrl <= '0;
            reg_status <= '0;
            kernel_wr_en <= 1'b0;
            kernel_wr_addr <= '0;
            kernel_wr_data <= '0;
            s_axil_bvalid <= 1'b0;
            s_axil_rvalid <= 1'b0;
            s_axil_rdata <= '0;
            awaddr_latched <= '0;
            awaddr_valid <= 1'b0;
        end else begin
            kernel_wr_en <= 1'b0;
            reg_status[0] <= overflow_flag;

            if (s_axil_awvalid) begin
                awaddr_latched <= s_axil_awaddr;
                awaddr_valid <= 1'b1;
            end

            if (s_axil_wvalid && (s_axil_awvalid || awaddr_valid)) begin
                case (write_addr)
                    6'h00: begin
                        reg_ctrl <= s_axil_wdata;
                    end
                    6'h04: begin
                        if (s_axil_wdata[7:0] < TAPS) begin
                            kernel_wr_addr <= s_axil_wdata[$clog2(KSIZE*KSIZE)-1:0];
                        end
                    end
                    6'h08: begin
                        kernel_wr_data <= s_axil_wdata[COEFF_W-1:0];
                    end
                    6'h0C: begin
                        // Writing bit0=1 commits kernel write transaction.
                        if (s_axil_wdata[0]) begin
                            kernel_wr_en <= 1'b1;
                        end
                    end
                    default: begin
                    end
                endcase
                s_axil_bvalid <= 1'b1;
                awaddr_valid <= 1'b0;
            end

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end

            if (s_axil_arvalid) begin
                case (s_axil_araddr)
                    6'h00: s_axil_rdata <= reg_ctrl;
                    6'h10: s_axil_rdata <= reg_status;
                    default: s_axil_rdata <= 32'h0;
                endcase
                s_axil_rvalid <= 1'b1;
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end
endmodule
