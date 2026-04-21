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

    // ID 级提前分支决策（给 IF 重定向）
    output logic                    id_redirect_valid_o,
    output logic [DATA_WIDTH-1:0]   id_redirect_pc_o,
    output logic                    id_branch_taken_o,

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
    logic [DATA_WIDTH-1:0] pc_plus4;

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

    logic is_addi;
    logic is_slti;
    logic is_sltiu;
    logic is_xori;
    logic is_ori;
    logic is_andi;
    logic is_slli;
    logic is_srli;
    logic is_srai;
    logic is_add;
    logic is_sub;
    logic is_sll;
    logic is_slt;
    logic is_sltu;
    logic is_xor;
    logic is_srl;
    logic is_sra;
    logic is_or;
    logic is_and;

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

    logic                    cmp_eq;
    logic                    cmp_lt;
    logic                    cmp_ltu;
    logic                    branch_taken_n;
    logic [DATA_WIDTH-1:0]   branch_target_n;
    logic [DATA_WIDTH-1:0]   jal_target_n;
    logic [DATA_WIDTH-1:0]   jalr_target_n;
    logic [DATA_WIDTH-1:0]   redirect_pc_n;
    logic                    redirect_valid_n;

    ydrasil_ins_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_ins_decoder (
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
        .is_jal_o(is_jal),
        .is_jalr_o(is_jalr),
        .is_lui_o(is_lui),
        .is_auipc_o(is_auipc)
    );

    assign rs1_addr_o = rs1;
    assign rs2_addr_o = rs2;

    assign is_beq  = is_branch & (funct3 == `RV32I_INS_BEQ);
    assign is_bne  = is_branch & (funct3 == `RV32I_INS_BNE);
    assign is_blt  = is_branch & (funct3 == `RV32I_INS_BLT);
    assign is_bge  = is_branch & (funct3 == `RV32I_INS_BGE);
    assign is_bltu = is_branch & (funct3 == `RV32I_INS_BLTU);
    assign is_bgeu = is_branch & (funct3 == `RV32I_INS_BGEU);

    assign is_lb   = is_load & (funct3 == `RV32I_INS_LB);
    assign is_lh   = is_load & (funct3 == `RV32I_INS_LH);
    assign is_lw   = is_load & (funct3 == `RV32I_INS_LW);
    assign is_lbu  = is_load & (funct3 == `RV32I_INS_LBU);
    assign is_lhu  = is_load & (funct3 == `RV32I_INS_LHU);
    assign is_sb   = is_store & (funct3 == `RV32I_INS_SB);
    assign is_sh   = is_store & (funct3 == `RV32I_INS_SH);
    assign is_sw   = is_store & (funct3 == `RV32I_INS_SW);

    assign is_addi  = is_op_imm & (funct3 == `RV32I_INS_ADDI);
    assign is_slti  = is_op_imm & (funct3 == `RV32I_INS_SLTI);
    assign is_sltiu = is_op_imm & (funct3 == `RV32I_INS_SLTIU);
    assign is_xori  = is_op_imm & (funct3 == `RV32I_INS_XORI);
    assign is_ori   = is_op_imm & (funct3 == `RV32I_INS_ORI);
    assign is_andi  = is_op_imm & (funct3 == `RV32I_INS_ANDI);
    assign is_slli  = is_op_imm & (funct3 == `RV32I_INS_SLLI) & (funct7 == 7'b0000000);
    assign is_srli  = is_op_imm & (funct3 == `RV32I_INS_SRI) & (funct7 == 7'b0000000);
    assign is_srai  = is_op_imm & (funct3 == `RV32I_INS_SRI) & (funct7 == 7'b0100000);

    assign is_add   = is_op & (funct3 == `RV32I_INS_ADD_SUB) & (funct7 == 7'b0000000);
    assign is_sub   = is_op & (funct3 == `RV32I_INS_ADD_SUB) & (funct7 == 7'b0100000);
    assign is_sll   = is_op & (funct3 == `RV32I_INS_SLL) & (funct7 == 7'b0000000);
    assign is_slt   = is_op & (funct3 == `RV32I_INS_SLT) & (funct7 == 7'b0000000);
    assign is_sltu  = is_op & (funct3 == `RV32I_INS_SLTU) & (funct7 == 7'b0000000);
    assign is_xor   = is_op & (funct3 == `RV32I_INS_XOR) & (funct7 == 7'b0000000);
    assign is_srl   = is_op & (funct3 == `RV32I_INS_SR) & (funct7 == 7'b0000000);
    assign is_sra   = is_op & (funct3 == `RV32I_INS_SR) & (funct7 == 7'b0100000);
    assign is_or    = is_op & (funct3 == `RV32I_INS_OR) & (funct7 == 7'b0000000);
    assign is_and   = is_op & (funct3 == `RV32I_INS_AND) & (funct7 == 7'b0000000);

    assign dec_alu_op_info[`ALU_OP_ADD]   = is_addi | is_add | is_auipc | is_lui;
    assign dec_alu_op_info[`ALU_OP_SUB]   = is_sub;
    assign dec_alu_op_info[`ALU_OP_SLL]   = is_slli | is_sll;
    assign dec_alu_op_info[`ALU_OP_SLT]   = is_slti | is_slt;
    assign dec_alu_op_info[`ALU_OP_SLTU]  = is_sltiu | is_sltu;
    assign dec_alu_op_info[`ALU_OP_XOR]   = is_xori | is_xor;
    assign dec_alu_op_info[`ALU_OP_SRL]   = is_srli | is_srl;
    assign dec_alu_op_info[`ALU_OP_SRA]   = is_srai | is_sra;
    assign dec_alu_op_info[`ALU_OP_OR]    = is_ori | is_or;
    assign dec_alu_op_info[`ALU_OP_AND]   = is_andi | is_and;
    assign dec_alu_op_info[`ALU_OP_LUI]   = is_lui;
    assign dec_alu_op_info[`ALU_OP_AUIPC] = is_auipc;
    assign dec_alu_op_info[`ALU_OP_JUMP]  = is_jal | is_jalr;

    assign pc_plus4 = if_id_pc_i + DATA_WIDTH'(32'd4);

    // comparator 简化：统一比较结果供 branch/jalr 共用
    assign cmp_eq  = (rs1_rdata_i == rs2_rdata_i);
    assign cmp_lt  = ($signed(rs1_rdata_i) < $signed(rs2_rdata_i));
    assign cmp_ltu = (rs1_rdata_i < rs2_rdata_i);

    assign branch_taken_n = (is_beq  & cmp_eq ) |
                            (is_bne  & (~cmp_eq)) |
                            (is_blt  & cmp_lt) |
                            (is_bge  & (~cmp_lt)) |
                            (is_bltu & cmp_ltu) |
                            (is_bgeu & (~cmp_ltu));

    // 提前计算分支目标，减少后级依赖
    assign branch_target_n = if_id_pc_i + imm_b;
    assign jal_target_n    = if_id_pc_i + imm_j;
    assign jalr_target_n   = (rs1_rdata_i + imm_i) & (~DATA_WIDTH'(32'd1));

    assign redirect_valid_n = (is_branch & branch_taken_n) | is_jal | is_jalr;
    assign redirect_pc_n    = is_jalr ? jalr_target_n :
                              (is_jal ? jal_target_n : branch_target_n);

    assign id_branch_taken_o  = branch_taken_n;
    assign id_redirect_valid_o = redirect_valid_n;
    assign id_redirect_pc_o    = redirect_pc_n;

    assign opcode_n = opcode;
    assign funct3_n = funct3;
    assign funct7_n = funct7;

    assign alu_valid_n   = is_op | is_op_imm | is_lui | is_auipc | is_jal | is_jalr;
    assign alu_op1_n     = (is_lui) ? 32'd0 :
                           ((is_auipc | is_jal | is_jalr) ? if_id_pc_i : rs1_rdata_i);
    assign alu_op2_n     = (is_jal | is_jalr) ? pc_plus4 - if_id_pc_i :
                           ((is_op) ? rs2_rdata_i : imm_i);
    assign alu_op_info_n = dec_alu_op_info;

    assign bru_valid_n   = is_branch | is_jal | is_jalr;
    assign bru_funct3_n  = funct3;
    assign bru_pc_n      = if_id_pc_i;
    assign bru_rs1_n     = rs1_rdata_i;
    assign bru_rs2_n     = rs2_rdata_i;
    assign bru_imm_n     = is_branch ? branch_target_n :
                           ((is_jal) ? jal_target_n :
                           ((is_jalr) ? jalr_target_n : '0));

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
