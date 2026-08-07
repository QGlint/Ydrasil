module ydrasil_completion_ctrl
import ydrasil_pkg::*;
(
    input  wire clk,
    input  wire rst_n,
    input  wire alu_valid_i,
    input  producer_id_t alu_producer_id_i,
    input  wire alu_producer_tracked_i,
    input  wire [REGS_ADDR_WIDTH-1:0] alu_addr_i,
    input  wire [REGS_DATA_WIDTH-1:0] alu_data_i,
    input  wire lsu_valid_i,
    input  producer_id_t lsu_producer_id_i,
    input  wire lsu_producer_tracked_i,
    input  wire [REGS_ADDR_WIDTH-1:0] lsu_addr_i,
    input  wire [REGS_DATA_WIDTH-1:0] lsu_data_i,
    input  wire mul_valid_i,
    input  producer_id_t mul_producer_id_i,
    input  wire [REGS_ADDR_WIDTH-1:0] mul_addr_i,
    input  wire [REGS_DATA_WIDTH-1:0] mul_data_i,
    input  wire dual_valid_i,
    input  producer_id_t dual_producer_id_i,
    input  wire dual_producer_tracked_i,
    input  wire [REGS_ADDR_WIDTH-1:0] dual_addr_i,
    input  wire [REGS_DATA_WIDTH-1:0] dual_data_i,
    output ydrasil_completion_meta_t completion_meta_o [COMPLETION_LANES],
    output logic [REGS_DATA_WIDTH-1:0] completion_data_o [COMPLETION_LANES],
    output logic [REGS_ADDR_WIDTH-1:0] completion_rd_o [COMPLETION_LANES]
);
    integer completion_idx;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (completion_idx = 0; completion_idx < COMPLETION_LANES;
                 completion_idx = completion_idx + 1) begin
                completion_meta_o[completion_idx] <= '0;
                completion_data_o[completion_idx] <= '0;
                completion_rd_o[completion_idx] <= '0;
            end
        end else begin
            completion_meta_o[COMPLETION_ALU].valid <= alu_valid_i;
            completion_meta_o[COMPLETION_ALU].producer_id <= alu_producer_id_i;
            completion_meta_o[COMPLETION_ALU].producer_tracked <=
                alu_producer_tracked_i;
            completion_data_o[COMPLETION_ALU] <= alu_data_i;
            completion_rd_o[COMPLETION_ALU] <= alu_addr_i;

            completion_meta_o[COMPLETION_LSU].valid <= lsu_valid_i;
            completion_meta_o[COMPLETION_LSU].producer_id <= lsu_producer_id_i;
            completion_meta_o[COMPLETION_LSU].producer_tracked <=
                lsu_producer_tracked_i;
            completion_data_o[COMPLETION_LSU] <= lsu_data_i;
            completion_rd_o[COMPLETION_LSU] <= lsu_addr_i;

            completion_meta_o[COMPLETION_MUL].valid <= mul_valid_i;
            completion_meta_o[COMPLETION_MUL].producer_id <= mul_producer_id_i;
            completion_meta_o[COMPLETION_MUL].producer_tracked <=
                mul_valid_i && (mul_addr_i != '0);
            completion_data_o[COMPLETION_MUL] <= mul_data_i;
            completion_rd_o[COMPLETION_MUL] <= mul_addr_i;

            completion_meta_o[COMPLETION_DUAL_ALU].valid <= dual_valid_i;
            completion_meta_o[COMPLETION_DUAL_ALU].producer_id <=
                dual_producer_id_i;
            completion_meta_o[COMPLETION_DUAL_ALU].producer_tracked <=
                dual_producer_tracked_i;
            completion_data_o[COMPLETION_DUAL_ALU] <= dual_data_i;
            completion_rd_o[COMPLETION_DUAL_ALU] <= dual_addr_i;
        end
    end
endmodule
