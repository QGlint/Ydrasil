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
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  stall_id_i,
    input  wire                  bubble_id_i,
    input  wire                  flush_id_i,
    input  fetch_pair_pkt_t      if_id_fetch_pair_i,

    output decode_pair_pkt_t     id_decode_pair_o,
    output wire                  consume_two_o
);
    decode_pkt_t slot0_dec;
    decode_pkt_t slot1_dec;
    decode_pair_pkt_t decode_pair_next;
    decode_pair_pkt_t decode_pair_ff;
    pair_ctrl_t  decode_pair_ctrl;
    wire slot0_pair_stop;
    wire slot1_pair_simple_int;
    wire slot1_pair_unsupported;
    wire slot0_pair_writes_rd;
    wire slot1_pair_uses_rs2;
    wire slot_pair_raw;
    wire slot_pair_waw;
    wire id_hold;

    ydrasil_decode_slot #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_decode_slot0 (
        .pc_i            (if_id_fetch_pair_i.slot0.pc),
        .instr_i         (if_id_fetch_pair_i.slot0.instr),
        .pred_hit_i      (if_id_fetch_pair_i.slot0.pred.hit),
        .pred_taken_i    (if_id_fetch_pair_i.slot0.pred.taken),
        .pred_target_i   (if_id_fetch_pair_i.slot0.pred.target),
        .pred_counter_i  (if_id_fetch_pair_i.slot0.pred.counter),
        .pred_bht_index_i(if_id_fetch_pair_i.slot0.pred.bht_index),
        .pred_l0_taken_i (if_id_fetch_pair_i.slot0.pred.l0_taken),
        .valid_i         (if_id_fetch_pair_i.slot0.valid),
        .decode_pkt_o    (slot0_dec)
    );

    ydrasil_decode_slot #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_decode_slot1 (
        .pc_i            (if_id_fetch_pair_i.slot1.pc),
        .instr_i         (if_id_fetch_pair_i.slot1.instr),
        .pred_hit_i      (if_id_fetch_pair_i.slot1.pred.hit),
        .pred_taken_i    (if_id_fetch_pair_i.slot1.pred.taken),
        .pred_target_i   (if_id_fetch_pair_i.slot1.pred.target),
        .pred_counter_i  (if_id_fetch_pair_i.slot1.pred.counter),
        .pred_bht_index_i(if_id_fetch_pair_i.slot1.pred.bht_index),
        .pred_l0_taken_i (if_id_fetch_pair_i.slot1.pred.l0_taken),
        .valid_i         (if_id_fetch_pair_i.slot1.valid),
        .decode_pkt_o    (slot1_dec)
    );

    assign decode_pair_next.slot0 = slot0_dec;
    assign decode_pair_next.slot1 = slot1_dec;
    assign decode_pair_next.pair_ctrl = decode_pair_ctrl;
    assign id_decode_pair_o = decode_pair_ff;
    assign id_hold = stall_id_i | bubble_id_i;
    assign consume_two_o = !id_hold && !flush_id_i &&
        decode_pair_ctrl.decode_pair_allow;

    assign slot0_pair_stop =
        slot0_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
        slot0_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
        slot0_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
        slot0_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
        slot0_dec.fence_i;
    assign slot1_pair_simple_int =
        (slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] ||
         slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP]) &&
        !slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !slot1_dec.fence_i;
    assign slot1_pair_unsupported = slot1_dec.valid && !slot1_pair_simple_int;
    assign slot0_pair_writes_rd =
        slot0_dec.valid &&
        (slot0_dec.rf_wen_rd || slot0_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD]) &&
        (slot0_dec.rf_waddr_rd != '0) &&
        !slot0_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS];
    assign slot1_pair_uses_rs2 =
        slot1_dec.rf_ren_rs2 || slot1_dec.operand_b_rs_sel ||
        slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];
    assign slot_pair_raw =
        slot0_pair_writes_rd && slot1_dec.valid &&
        ((slot1_dec.rf_ren_rs1 &&
          (slot1_dec.rf_raddr_rs1 == slot0_dec.rf_waddr_rd)) ||
         (slot1_pair_uses_rs2 &&
          (slot1_dec.rf_raddr_rs2 == slot0_dec.rf_waddr_rd)));
    assign slot_pair_waw =
        slot0_pair_writes_rd && slot1_dec.valid &&
        (slot1_dec.rf_wen_rd || slot1_dec.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD]) &&
        (slot1_dec.rf_waddr_rd != '0) &&
        (slot1_dec.rf_waddr_rd == slot0_dec.rf_waddr_rd);

    always_comb begin
        decode_pair_ctrl = if_id_fetch_pair_i.pair_ctrl;
        decode_pair_ctrl.decode_pair_allow =
            if_id_fetch_pair_i.pair_ctrl.slot1_valid &&
            slot0_dec.valid && slot1_dec.valid &&
            !slot0_pair_stop && !slot1_pair_unsupported;
        if (if_id_fetch_pair_i.pair_ctrl.block_reason == PAIR_BLOCK_NONE &&
            if_id_fetch_pair_i.pair_ctrl.slot1_valid &&
            !decode_pair_ctrl.decode_pair_allow) begin
            decode_pair_ctrl.block_reason = PAIR_BLOCK_RULE;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decode_pair_ff <= '0;
        end else if (flush_id_i) begin
            decode_pair_ff <= '0;
        end else if (!id_hold) begin
            decode_pair_ff <= decode_pair_next;
        end
    end
endmodule
