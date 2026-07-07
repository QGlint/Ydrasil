module ydrasil_decode_slot
import ydrasil_pkg::*;
import ydrasil_pipeline_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire [DATA_WIDTH-1:0] pc_i,
    input  wire [DATA_WIDTH-1:0] instr_i,
    input  wire                  pred_hit_i,
    input  wire                  pred_taken_i,
    input  wire [DATA_WIDTH-1:0] pred_target_i,
    input  wire [1:0]            pred_counter_i,
    input  wire [DATA_WIDTH-1:0] pred_bht_index_i,
    input  wire                  pred_l0_taken_i,
    input  wire                  valid_i,

    output decode_pkt_t          decode_pkt_o
);
    wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     rf_raddr_rs1;
    wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     rf_raddr_rs2;
    wire                                        rf_ren_rs1;
    wire                                        rf_ren_rs2;
    wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     rf_waddr_rd;
    wire                                        rf_wen_rd;
    wire [DATA_WIDTH-1:0]                       imm_i;
    wire                                        operand_b_rs_sel;
    wire                                        operand_a_pc_sel;
    wire                                        operand_a_imm_sel;
    wire                                        bt_a_rs_sel;
    wire                                        operand_b_jump_sel;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      csr_reg_raddr;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      csr_ex_waddr;
    wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]   csr_op_info;
    wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   sys_op_info;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      operator;
    wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   operator_lsu;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type;

    ydrasil_ins_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_ins_decoder (
        .instr_i              (instr_i),
        .rf_waddr_rd_o        (rf_waddr_rd),
        .rf_raddr_rs1_o       (rf_raddr_rs1),
        .rf_raddr_rs2_o       (rf_raddr_rs2),
        .rf_ren_rs1_o         (rf_ren_rs1),
        .rf_ren_rs2_o         (rf_ren_rs2),
        .rf_wen_rd_o          (rf_wen_rd),
        .imm_i_o              (imm_i),
        .operand_b_rs_sel_o   (operand_b_rs_sel),
        .operand_a_pc_sel_o   (operand_a_pc_sel),
        .operand_a_imm_sel_o  (operand_a_imm_sel),
        .bt_a_rs_sel_o        (bt_a_rs_sel),
        .operand_b_jump_sel_o (operand_b_jump_sel),
        .csr_reg_raddr_o      (csr_reg_raddr),
        .csr_ex_waddr_o       (csr_ex_waddr),
        .csr_op_info_o        (csr_op_info),
        .sys_op_info_o        (sys_op_info),
        .operator_o           (operator),
        .operator_lsu_o       (operator_lsu),
        .operator_type_o      (operator_type)
    );

    assign decode_pkt_o.valid = valid_i;
    assign decode_pkt_o.pc = pc_i;
    assign decode_pkt_o.instr = instr_i;
    assign decode_pkt_o.pred_hit = pred_hit_i;
    assign decode_pkt_o.pred_taken = pred_taken_i;
    assign decode_pkt_o.pred_target = pred_target_i;
    assign decode_pkt_o.pred_counter = pred_counter_i;
    assign decode_pkt_o.pred_bht_index = pred_bht_index_i;
    assign decode_pkt_o.pred_l0_taken = pred_l0_taken_i;

    assign decode_pkt_o.rf_raddr_rs1 = rf_raddr_rs1;
    assign decode_pkt_o.rf_raddr_rs2 = rf_raddr_rs2;
    assign decode_pkt_o.rf_ren_rs1 = rf_ren_rs1;
    assign decode_pkt_o.rf_ren_rs2 = rf_ren_rs2;
    assign decode_pkt_o.rf_waddr_rd = rf_waddr_rd;
    assign decode_pkt_o.rf_wen_rd = rf_wen_rd;

    assign decode_pkt_o.imm = imm_i;
    assign decode_pkt_o.operand_b_rs_sel = operand_b_rs_sel;
    assign decode_pkt_o.operand_a_pc_sel = operand_a_pc_sel;
    assign decode_pkt_o.operand_a_imm_sel = operand_a_imm_sel;
    assign decode_pkt_o.bt_a_rs_sel = bt_a_rs_sel;
    assign decode_pkt_o.operand_b_jump_sel = operand_b_jump_sel;

    assign decode_pkt_o.operator = operator;
    assign decode_pkt_o.operator_lsu = operator_lsu;
    assign decode_pkt_o.operator_type = operator_type;
    assign decode_pkt_o.csr_reg_raddr = csr_reg_raddr;
    assign decode_pkt_o.csr_ex_waddr = csr_ex_waddr;
    assign decode_pkt_o.csr_op_info = csr_op_info;
    assign decode_pkt_o.sys_op_info = sys_op_info;
    assign decode_pkt_o.fence_i =
        (instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
        (instr_i[14:12] == 3'b001);
endmodule

module ydrasil_id_stage
import ydrasil_pkg::*;
import ydrasil_pipeline_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire [DATA_WIDTH-1:0] if_id0_pc_i,
    input  wire [DATA_WIDTH-1:0] if_id0_instr_i,
    input  wire                  if_id0_pred_hit_i,
    input  wire                  if_id0_pred_taken_i,
    input  wire [DATA_WIDTH-1:0] if_id0_pred_target_i,
    input  wire [1:0]            if_id0_pred_counter_i,
    input  wire [DATA_WIDTH-1:0] if_id0_pred_bht_index_i,
    input  wire                  if_id0_pred_l0_taken_i,
    input  wire                  if_id0_valid_i,

    input  wire [DATA_WIDTH-1:0] if_id1_pc_i,
    input  wire [DATA_WIDTH-1:0] if_id1_instr_i,
    input  wire                  if_id1_pred_hit_i,
    input  wire                  if_id1_pred_taken_i,
    input  wire [DATA_WIDTH-1:0] if_id1_pred_target_i,
    input  wire [1:0]            if_id1_pred_counter_i,
    input  wire [DATA_WIDTH-1:0] if_id1_pred_bht_index_i,
    input  wire                  if_id1_pred_l0_taken_i,
    input  wire                  if_id1_valid_i,

    output decode_pair_pkt_t     id_decode_pair_o
);
    decode_pkt_t slot0_dec;
    decode_pkt_t slot1_dec;

    ydrasil_decode_slot #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_decode_slot0 (
        .pc_i            (if_id0_pc_i),
        .instr_i         (if_id0_instr_i),
        .pred_hit_i      (if_id0_pred_hit_i),
        .pred_taken_i    (if_id0_pred_taken_i),
        .pred_target_i   (if_id0_pred_target_i),
        .pred_counter_i  (if_id0_pred_counter_i),
        .pred_bht_index_i(if_id0_pred_bht_index_i),
        .pred_l0_taken_i (if_id0_pred_l0_taken_i),
        .valid_i         (if_id0_valid_i),
        .decode_pkt_o    (slot0_dec)
    );

    ydrasil_decode_slot #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_decode_slot1 (
        .pc_i            (if_id1_pc_i),
        .instr_i         (if_id1_instr_i),
        .pred_hit_i      (if_id1_pred_hit_i),
        .pred_taken_i    (if_id1_pred_taken_i),
        .pred_target_i   (if_id1_pred_target_i),
        .pred_counter_i  (if_id1_pred_counter_i),
        .pred_bht_index_i(if_id1_pred_bht_index_i),
        .pred_l0_taken_i (if_id1_pred_l0_taken_i),
        .valid_i         (if_id1_valid_i),
        .decode_pkt_o    (slot1_dec)
    );

    assign id_decode_pair_o.slot0 = slot0_dec;
    assign id_decode_pair_o.slot1 = slot1_dec;
endmodule
