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
    input  wire [REGS_DATA_WIDTH-1:0] wr1_data_i
);

    reg [REGS_DATA_WIDTH-1:0] prf_q [0:PHYS_REGS-1];

    function automatic [REGS_DATA_WIDTH-1:0] read_prf;
        input rd_en;
        input [PREG_BITS-1:0] rd_addr;
        begin
            if (!rd_en || (rd_addr == '0)) begin
                read_prf = '0;
            end else if (wr1_en_i && (wr1_addr_i == rd_addr) && (wr1_addr_i != '0)) begin
                read_prf = wr1_data_i;
            end else if (wr0_en_i && (wr0_addr_i == rd_addr) && (wr0_addr_i != '0)) begin
                read_prf = wr0_data_i;
            end else begin
                read_prf = prf_q[rd_addr];
            end
        end
    endfunction

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
        end
    end

    assign rd0_data_o = read_prf(rd0_en_i, rd0_addr_i);
    assign rd1_data_o = read_prf(rd1_en_i, rd1_addr_i);
    assign rd2_data_o = read_prf(rd2_en_i, rd2_addr_i);
    assign rd3_data_o = read_prf(rd3_en_i, rd3_addr_i);

endmodule
