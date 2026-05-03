`timescale 1ns/1ps

module line_buffer_4 #(
    parameter int IMAGE_WIDTH = 640,
    parameter int DATA_W = 24,
    parameter int KSIZE = 5
) (
    input  logic                        clk,
    input  logic                        rst,
    input  logic                        valid_in,
    input  logic [DATA_W-1:0]           pixel_in,
    output logic                        valid_out,
    output logic [DATA_W*KSIZE*KSIZE-1:0] window_flat
);
    logic [DATA_W-1:0] line0 [0:IMAGE_WIDTH-1];
    logic [DATA_W-1:0] line1 [0:IMAGE_WIDTH-1];
    logic [DATA_W-1:0] line2 [0:IMAGE_WIDTH-1];
    logic [DATA_W-1:0] line3 [0:IMAGE_WIDTH-1];

    logic [DATA_W-1:0] sr0 [0:KSIZE-1];
    logic [DATA_W-1:0] sr1 [0:KSIZE-1];
    logic [DATA_W-1:0] sr2 [0:KSIZE-1];
    logic [DATA_W-1:0] sr3 [0:KSIZE-1];
    logic [DATA_W-1:0] sr4 [0:KSIZE-1];

    logic [15:0] x_count;
    logic [15:0] y_count;
    logic [DATA_W-1:0] p0;
    logic [DATA_W-1:0] p1;
    logic [DATA_W-1:0] p2;
    logic [DATA_W-1:0] p3;

    int i_ff;
    int i_comb;

    always_ff @(posedge clk) begin
        if (rst) begin
            x_count <= '0;
            y_count <= '0;
            for (i_ff = 0; i_ff < KSIZE; i_ff++) begin
                sr0[i_ff] <= '0;
                sr1[i_ff] <= '0;
                sr2[i_ff] <= '0;
                sr3[i_ff] <= '0;
                sr4[i_ff] <= '0;
            end
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;
            if (valid_in) begin
                p0 = line0[x_count];
                p1 = line1[x_count];
                p2 = line2[x_count];
                p3 = line3[x_count];

                line3[x_count] <= line2[x_count];
                line2[x_count] <= line1[x_count];
                line1[x_count] <= line0[x_count];
                line0[x_count] <= pixel_in;

                for (i_ff = 0; i_ff < KSIZE-1; i_ff++) begin
                    sr0[i_ff] <= sr0[i_ff+1];
                    sr1[i_ff] <= sr1[i_ff+1];
                    sr2[i_ff] <= sr2[i_ff+1];
                    sr3[i_ff] <= sr3[i_ff+1];
                    sr4[i_ff] <= sr4[i_ff+1];
                end

                sr0[KSIZE-1] <= p3;
                sr1[KSIZE-1] <= p2;
                sr2[KSIZE-1] <= p1;
                sr3[KSIZE-1] <= p0;
                sr4[KSIZE-1] <= pixel_in;

                if ((x_count >= KSIZE-1) && (y_count >= KSIZE-1)) begin
                    valid_out <= 1'b1;
                end

                if (x_count == IMAGE_WIDTH-1) begin
                    x_count <= '0;
                    y_count <= y_count + 16'd1;
                end else begin
                    x_count <= x_count + 16'd1;
                end
            end
        end
    end

    always_comb begin
        for (i_comb = 0; i_comb < KSIZE; i_comb++) begin
            window_flat[(0*KSIZE+i_comb)*DATA_W +: DATA_W] = sr0[i_comb];
            window_flat[(1*KSIZE+i_comb)*DATA_W +: DATA_W] = sr1[i_comb];
            window_flat[(2*KSIZE+i_comb)*DATA_W +: DATA_W] = sr2[i_comb];
            window_flat[(3*KSIZE+i_comb)*DATA_W +: DATA_W] = sr3[i_comb];
            window_flat[(4*KSIZE+i_comb)*DATA_W +: DATA_W] = sr4[i_comb];
        end
    end
endmodule
