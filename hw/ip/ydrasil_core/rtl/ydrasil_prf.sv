module ydrasil_prf
import ydrasil_pkg::*;
#(
    parameter int PHYS_REGS = 64,
    parameter int PREG_BITS = 6
) (
    input  wire clk,
    input  wire rst_n,

    input  wire rd0_en_i,
    input  wire [PREG_BITS-1:0] rd0_addr_i,
    output wire [REGS_DATA_WIDTH-1:0] rd0_data_o,
    input  wire rd1_en_i,
    input  wire [PREG_BITS-1:0] rd1_addr_i,
    output wire [REGS_DATA_WIDTH-1:0] rd1_data_o,
    input  wire rd2_en_i,
    input  wire [PREG_BITS-1:0] rd2_addr_i,
    output wire [REGS_DATA_WIDTH-1:0] rd2_data_o,
    input  wire rd3_en_i,
    input  wire [PREG_BITS-1:0] rd3_addr_i,
    output wire [REGS_DATA_WIDTH-1:0] rd3_data_o,

    input  wire wr0_en_i,
    input  wire [PREG_BITS-1:0] wr0_addr_i,
    input  wire [REGS_DATA_WIDTH-1:0] wr0_data_i,
    input  wire wr1_en_i,
    input  wire [PREG_BITS-1:0] wr1_addr_i,
    input  wire [REGS_DATA_WIDTH-1:0] wr1_data_i,
    input  wire wr2_en_i,
    input  wire [PREG_BITS-1:0] wr2_addr_i,
    input  wire [REGS_DATA_WIDTH-1:0] wr2_data_i
);

    reg [REGS_DATA_WIDTH-1:0] prf_q [0:PHYS_REGS-1];

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            for (i = 0; i < PHYS_REGS; i = i + 1) begin
                prf_q[i] <= '0;
            end
        end else begin
            if (wr0_en_i && (wr0_addr_i != '0)) begin
                prf_q[wr0_addr_i] <= wr0_data_i;
            end
            if (wr1_en_i && (wr1_addr_i != '0)) begin
                prf_q[wr1_addr_i] <= wr1_data_i;
            end
            if (wr2_en_i && (wr2_addr_i != '0)) begin
                prf_q[wr2_addr_i] <= wr2_data_i;
            end
        end
    end

    assign rd0_data_o =
        (!rd0_en_i || (rd0_addr_i == '0)) ? '0 :
        (wr1_en_i && (wr1_addr_i == rd0_addr_i) && (wr1_addr_i != '0)) ? wr1_data_i :
        (wr0_en_i && (wr0_addr_i == rd0_addr_i) && (wr0_addr_i != '0)) ? wr0_data_i :
        (wr2_en_i && (wr2_addr_i == rd0_addr_i) && (wr2_addr_i != '0)) ? wr2_data_i :
        prf_q[rd0_addr_i];
    assign rd1_data_o =
        (!rd1_en_i || (rd1_addr_i == '0)) ? '0 :
        (wr1_en_i && (wr1_addr_i == rd1_addr_i) && (wr1_addr_i != '0)) ? wr1_data_i :
        (wr0_en_i && (wr0_addr_i == rd1_addr_i) && (wr0_addr_i != '0)) ? wr0_data_i :
        (wr2_en_i && (wr2_addr_i == rd1_addr_i) && (wr2_addr_i != '0)) ? wr2_data_i :
        prf_q[rd1_addr_i];
    assign rd2_data_o =
        (!rd2_en_i || (rd2_addr_i == '0)) ? '0 :
        (wr1_en_i && (wr1_addr_i == rd2_addr_i) && (wr1_addr_i != '0)) ? wr1_data_i :
        (wr0_en_i && (wr0_addr_i == rd2_addr_i) && (wr0_addr_i != '0)) ? wr0_data_i :
        (wr2_en_i && (wr2_addr_i == rd2_addr_i) && (wr2_addr_i != '0)) ? wr2_data_i :
        prf_q[rd2_addr_i];
    assign rd3_data_o =
        (!rd3_en_i || (rd3_addr_i == '0)) ? '0 :
        (wr1_en_i && (wr1_addr_i == rd3_addr_i) && (wr1_addr_i != '0)) ? wr1_data_i :
        (wr0_en_i && (wr0_addr_i == rd3_addr_i) && (wr0_addr_i != '0)) ? wr0_data_i :
        (wr2_en_i && (wr2_addr_i == rd3_addr_i) && (wr2_addr_i != '0)) ? wr2_data_i :
        prf_q[rd3_addr_i];

endmodule
