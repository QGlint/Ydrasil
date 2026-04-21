`include "define_alu.svh"
`include "define_rv32i_ins.svh"

module ydrasil_id_stage #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    stall_id_i,
    input  logic                    flush_id_i,

    // IF/ID 输入
    input  logic [DATA_WIDTH-1:0]   if_id_pc_i,
    input  logic [31:0]             if_id_instr_i,

    // 简化寄存器堆读端口（由外部 regs 模块实现）
    output logic [4:0]              rs1_addr_o,
    output logic [4:0]              rs2_addr_o,
    input  logic [DATA_WIDTH-1:0]   rs1_rdata_i,
    input  logic [DATA_WIDTH-1:0]   rs2_rdata_i,

    // dispatch 到 ALU
    output logic                    alu_valid_o,
    output logic [DATA_WIDTH-1:0]   alu_op1_o,
    output logic [DATA_WIDTH-1:0]   alu_op2_o,
    output logic [`ALU_OP_WIDTH-1:0] alu_op_info_o,

    // dispatch 到 BRU
    output logic                    bru_valid_o,
    output logic [2:0]              bru_funct3_o,
    output logic [DATA_WIDTH-1:0]   bru_pc_o,
    output logic [DATA_WIDTH-1:0]   bru_rs1_o,
    output logic [DATA_WIDTH-1:0]   bru_rs2_o,
    output logic [DATA_WIDTH-1:0]   bru_imm_o,

    // dispatch 到 LSU/AGU
    output logic                    lsu_valid_o,
    output logic                    lsu_is_load_o,
    output logic                    lsu_is_store_o,
    output logic [2:0]              lsu_funct3_o,
    output logic [DATA_WIDTH-1:0]   lsu_base_o,
    output logic [DATA_WIDTH-1:0]   lsu_offset_o,
    output logic [DATA_WIDTH-1:0]   lsu_store_data_o,

    // 通用写回信息
    output logic                    rd_wen_o,
    output logic [4:0]              rd_addr_o,

    // 用于 debug/后级旁路
    output logic [6:0]              opcode_o,
    output logic [2:0]              funct3_o,
    output logic [6:0]              funct7_o
);

    localparam logic [31:0] RV32I_NOP = `RV32I_INS_NOP;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    logic [4:0] rd;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [6:0] opcode;

    logic is_op;
    logic is_op_imm;
    logic is_load;
    logic is_store;
    logic is_branch;
    logic is_beq;
    logic is_bne;
    logic is_blt;
    logic is_bge;
    logic is_bltu;
    logic is_bgeu;
    logic is_lb;
    logic is_lh;
    logic is_lw;
    logic is_lbu;
    logic is_lhu;
    logic is_sb;
    logic is_sh;
    logic is_sw;
    logic is_jal;
    logic is_jalr;
    logic is_lui;
    logic is_auipc;

    logic [`ALU_OP_WIDTH-1:0] dec_alu_op_info;

    logic                    alu_valid_n;
    logic [DATA_WIDTH-1:0]   alu_op1_n;
    logic [DATA_WIDTH-1:0]   alu_op2_n;
    logic [`ALU_OP_WIDTH-1:0] alu_op_info_n;

    logic                    bru_valid_n;
    logic [2:0]              bru_funct3_n;
    logic [DATA_WIDTH-1:0]   bru_pc_n;
    logic [DATA_WIDTH-1:0]   bru_rs1_n;
    logic [DATA_WIDTH-1:0]   bru_rs2_n;
    logic [DATA_WIDTH-1:0]   bru_imm_n;

    logic                    lsu_valid_n;
    logic                    lsu_is_load_n;
    logic                    lsu_is_store_n;
    logic [2:0]              lsu_funct3_n;
    logic [DATA_WIDTH-1:0]   lsu_base_n;
    logic [DATA_WIDTH-1:0]   lsu_offset_n;
    logic [DATA_WIDTH-1:0]   lsu_store_data_n;

    logic                    rd_wen_n;
    logic [4:0]              rd_addr_n;

    logic [6:0]              opcode_n;
    logic [2:0]              funct3_n;
    logic [6:0]              funct7_n;

    ydrasil_isa_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_isa_decoder (
        .instr_i(if_id_instr_i),
        .opcode_o(opcode),
        .funct3_o(funct3),
        .funct7_o(funct7),
        .rd_o(rd),
        .rs1_o(rs1),
        .rs2_o(rs2),
        .imm_i_o(imm_i),
        .imm_s_o(imm_s),
        .imm_b_o(imm_b),
        .imm_u_o(imm_u),
        .imm_j_o(imm_j),
        .is_op_o(is_op),
        .is_op_imm_o(is_op_imm),
        .is_load_o(is_load),
        .is_store_o(is_store),
        .is_branch_o(is_branch),
        .is_beq_o(is_beq),
        .is_bne_o(is_bne),
        .is_blt_o(is_blt),
        .is_bge_o(is_bge),
        .is_bltu_o(is_bltu),
        .is_bgeu_o(is_bgeu),
        .is_lb_o(is_lb),
        .is_lh_o(is_lh),
        .is_lw_o(is_lw),
        .is_lbu_o(is_lbu),
        .is_lhu_o(is_lhu),
        .is_sb_o(is_sb),
        .is_sh_o(is_sh),
        .is_sw_o(is_sw),
        .is_jal_o(is_jal),
        .is_jalr_o(is_jalr),
        .is_lui_o(is_lui),
        .is_auipc_o(is_auipc),
        .alu_op_info_o(dec_alu_op_info)
    );

    assign rs1_addr_o = rs1;
    assign rs2_addr_o = rs2;

    assign opcode_n = opcode;
    assign funct3_n = funct3;
    assign funct7_n = funct7;

    assign alu_valid_n   = is_op | is_op_imm | is_lui | is_auipc | is_jal | is_jalr;
    assign alu_op1_n     = (is_lui) ? 32'd0 :
                           ((is_auipc | is_jal | is_jalr) ? if_id_pc_i : rs1_rdata_i);
    assign alu_op2_n     = (is_jal | is_jalr) ? 32'd4 :
                           ((is_op) ? rs2_rdata_i : imm_i);
    assign alu_op_info_n = dec_alu_op_info;

    assign bru_valid_n   = is_branch | is_jal | is_jalr;
    assign bru_funct3_n  = funct3;
    assign bru_pc_n      = if_id_pc_i;
    assign bru_rs1_n     = rs1_rdata_i;
    assign bru_rs2_n     = rs2_rdata_i;
    assign bru_imm_n     = is_branch ? imm_b :
                           ((is_jal) ? imm_j :
                           ((is_jalr) ? imm_i : 32'd0));

    assign lsu_valid_n      = is_load | is_store;
    assign lsu_is_load_n    = is_load;
    assign lsu_is_store_n   = is_store;
    assign lsu_funct3_n     = funct3;
    assign lsu_base_n       = rs1_rdata_i;
    assign lsu_offset_n     = is_store ? imm_s :
                              (is_load ? imm_i : 32'd0);
    assign lsu_store_data_n = rs2_rdata_i;

    assign rd_wen_n  = ((is_op | is_op_imm | is_lui | is_auipc | is_jal | is_jalr | is_load) & (rd != 5'd0));
    assign rd_addr_n = rd;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            alu_valid_o      <= 1'b0;
            alu_op1_o        <= '0;
            alu_op2_o        <= '0;
            alu_op_info_o    <= '0;

            bru_valid_o      <= 1'b0;
            bru_funct3_o     <= 3'b000;
            bru_pc_o         <= '0;
            bru_rs1_o        <= '0;
            bru_rs2_o        <= '0;
            bru_imm_o        <= '0;

            lsu_valid_o      <= 1'b0;
            lsu_is_load_o    <= 1'b0;
            lsu_is_store_o   <= 1'b0;
            lsu_funct3_o     <= 3'b000;
            lsu_base_o       <= '0;
            lsu_offset_o     <= '0;
            lsu_store_data_o <= '0;

            rd_wen_o         <= 1'b0;
            rd_addr_o        <= 5'd0;

            opcode_o         <= RV32I_NOP[6:0];
            funct3_o         <= RV32I_NOP[14:12];
            funct7_o         <= RV32I_NOP[31:25];
        end else if (flush_id_i) begin
            alu_valid_o      <= 1'b0;
            alu_op1_o        <= '0;
            alu_op2_o        <= '0;
            alu_op_info_o    <= '0;

            bru_valid_o      <= 1'b0;
            bru_funct3_o     <= 3'b000;
            bru_pc_o         <= '0;
            bru_rs1_o        <= '0;
            bru_rs2_o        <= '0;
            bru_imm_o        <= '0;

            lsu_valid_o      <= 1'b0;
            lsu_is_load_o    <= 1'b0;
            lsu_is_store_o   <= 1'b0;
            lsu_funct3_o     <= 3'b000;
            lsu_base_o       <= '0;
            lsu_offset_o     <= '0;
            lsu_store_data_o <= '0;

            rd_wen_o         <= 1'b0;
            rd_addr_o        <= 5'd0;

            opcode_o         <= RV32I_NOP[6:0];
            funct3_o         <= RV32I_NOP[14:12];
            funct7_o         <= RV32I_NOP[31:25];
        end else if (!stall_id_i) begin
            alu_valid_o      <= alu_valid_n;
            alu_op1_o        <= alu_op1_n;
            alu_op2_o        <= alu_op2_n;
            alu_op_info_o    <= alu_op_info_n;

            bru_valid_o      <= bru_valid_n;
            bru_funct3_o     <= bru_funct3_n;
            bru_pc_o         <= bru_pc_n;
            bru_rs1_o        <= bru_rs1_n;
            bru_rs2_o        <= bru_rs2_n;
            bru_imm_o        <= bru_imm_n;

            lsu_valid_o      <= lsu_valid_n;
            lsu_is_load_o    <= lsu_is_load_n;
            lsu_is_store_o   <= lsu_is_store_n;
            lsu_funct3_o     <= lsu_funct3_n;
            lsu_base_o       <= lsu_base_n;
            lsu_offset_o     <= lsu_offset_n;
            lsu_store_data_o <= lsu_store_data_n;

            rd_wen_o         <= rd_wen_n;
            rd_addr_o        <= rd_addr_n;

            opcode_o         <= opcode_n;
            funct3_o         <= funct3_n;
            funct7_o         <= funct7_n;
        end
    end

endmodule
