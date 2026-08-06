module ydrasil_issue_compactor
import ydrasil_pkg::*;
(
    input  ydrasil_issue_pkt_t   issue_pkt_i,
    output ydrasil_compact_uop_t compact_uop_o
);
    always_comb begin
        compact_uop_o = '0;
        compact_uop_o.valid = issue_pkt_i.valid;
        compact_uop_o.lane1 = issue_pkt_i.lane1;
        compact_uop_o.pair_eligible = issue_pkt_i.pair_eligible;
        compact_uop_o.lane_mask = issue_pkt_i.lane_mask;
        compact_uop_o.src0 = issue_pkt_i.src0;
        compact_uop_o.src1 = issue_pkt_i.src1;
        compact_uop_o.dst = issue_pkt_i.dst;

        compact_uop_o.op_class = UOP_CLASS_ALU;
        if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_FPU]) begin
            if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_LOAD])
                compact_uop_o.op_class = UOP_CLASS_FP_LOAD;
            else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_STORE])
                compact_uop_o.op_class = UOP_CLASS_FP_STORE;
            else
                compact_uop_o.op_class = UOP_CLASS_FPU;
        end else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_BJP])
            compact_uop_o.op_class = UOP_CLASS_BJP;
        else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_LOAD])
            compact_uop_o.op_class = UOP_CLASS_LOAD;
        else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_STORE])
            compact_uop_o.op_class = UOP_CLASS_STORE;
        else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_SYS])
            compact_uop_o.op_class = UOP_CLASS_SYS;
        else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_CSR])
            compact_uop_o.op_class = UOP_CLASS_CSR;
        else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_MUL])
            compact_uop_o.op_class = UOP_CLASS_MUL;
        else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_BITMANIP])
            compact_uop_o.op_class = UOP_CLASS_BITMANIP;

        compact_uop_o.subop = '0;
        unique case (1'b1)
            issue_pkt_i.decode.operator_info[0]:  compact_uop_o.subop = 6'd0;
            issue_pkt_i.decode.operator_info[1]:  compact_uop_o.subop = 6'd1;
            issue_pkt_i.decode.operator_info[2]:  compact_uop_o.subop = 6'd2;
            issue_pkt_i.decode.operator_info[3]:  compact_uop_o.subop = 6'd3;
            issue_pkt_i.decode.operator_info[4]:  compact_uop_o.subop = 6'd4;
            issue_pkt_i.decode.operator_info[5]:  compact_uop_o.subop = 6'd5;
            issue_pkt_i.decode.operator_info[6]:  compact_uop_o.subop = 6'd6;
            issue_pkt_i.decode.operator_info[7]:  compact_uop_o.subop = 6'd7;
            issue_pkt_i.decode.operator_info[8]:  compact_uop_o.subop = 6'd8;
            issue_pkt_i.decode.operator_info[9]:  compact_uop_o.subop = 6'd9;
            issue_pkt_i.decode.operator_info[10]: compact_uop_o.subop = 6'd10;
            issue_pkt_i.decode.operator_info[11]: compact_uop_o.subop = 6'd11;
            issue_pkt_i.decode.operator_info[12]: compact_uop_o.subop = 6'd12;
            issue_pkt_i.decode.operator_info[13]: compact_uop_o.subop = 6'd13;
            issue_pkt_i.decode.operator_info[14]: compact_uop_o.subop = 6'd14;
            issue_pkt_i.decode.operator_info[15]: compact_uop_o.subop = 6'd15;
            issue_pkt_i.decode.operator_info[16]: compact_uop_o.subop = 6'd16;
            issue_pkt_i.decode.operator_info[17]: compact_uop_o.subop = 6'd17;
            issue_pkt_i.decode.operator_info[18]: compact_uop_o.subop = 6'd18;
            issue_pkt_i.decode.operator_info[19]: compact_uop_o.subop = 6'd19;
            issue_pkt_i.decode.operator_info[20]: compact_uop_o.subop = 6'd20;
            issue_pkt_i.decode.operator_info[21]: compact_uop_o.subop = 6'd21;
            issue_pkt_i.decode.operator_info[22]: compact_uop_o.subop = 6'd22;
            issue_pkt_i.decode.operator_info[23]: compact_uop_o.subop = 6'd23;
            issue_pkt_i.decode.operator_info[24]: compact_uop_o.subop = 6'd24;
            issue_pkt_i.decode.operator_info[25]: compact_uop_o.subop = 6'd25;
            issue_pkt_i.decode.operator_info[26]: compact_uop_o.subop = 6'd26;
            issue_pkt_i.decode.operator_info[27]: compact_uop_o.subop = 6'd27;
            issue_pkt_i.decode.operator_info[28]: compact_uop_o.subop = 6'd28;
            issue_pkt_i.decode.operator_info[29]: compact_uop_o.subop = 6'd29;
            issue_pkt_i.decode.operator_info[30]: compact_uop_o.subop = 6'd30;
            issue_pkt_i.decode.operator_info[31]: compact_uop_o.subop = 6'd31;
            issue_pkt_i.decode.operator_info[32]: compact_uop_o.subop = 6'd32;
            issue_pkt_i.decode.operator_info[33]: compact_uop_o.subop = 6'd33;
            issue_pkt_i.decode.operator_info[34]: compact_uop_o.subop = 6'd34;
            issue_pkt_i.decode.operator_info[35]: compact_uop_o.subop = 6'd35;
            issue_pkt_i.decode.operator_info[36]: compact_uop_o.subop = 6'd36;
            issue_pkt_i.decode.operator_info[37]: compact_uop_o.subop = 6'd37;
            issue_pkt_i.decode.operator_info[38]: compact_uop_o.subop = 6'd38;
            issue_pkt_i.decode.operator_info[39]: compact_uop_o.subop = 6'd39;
            default: compact_uop_o.subop = '0;
        endcase

        compact_uop_o.lsu_subop = '0;
        unique case (1'b1)
            issue_pkt_i.decode.operator_lsu[OP_LSU_LB]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_LB);
            issue_pkt_i.decode.operator_lsu[OP_LSU_LH]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_LH);
            issue_pkt_i.decode.operator_lsu[OP_LSU_LW]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_LW);
            issue_pkt_i.decode.operator_lsu[OP_LSU_LBU]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_LBU);
            issue_pkt_i.decode.operator_lsu[OP_LSU_LHU]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_LHU);
            issue_pkt_i.decode.operator_lsu[OP_LSU_SB]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_SB);
            issue_pkt_i.decode.operator_lsu[OP_LSU_SH]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_SH);
            issue_pkt_i.decode.operator_lsu[OP_LSU_SW]:
                compact_uop_o.lsu_subop = UOP_LSU_SUBOP_WIDTH'(OP_LSU_SW);
            default: compact_uop_o.lsu_subop = '0;
        endcase

        compact_uop_o.pc = issue_pkt_i.decode.pc;
        compact_uop_o.instr = issue_pkt_i.decode.instr;
        compact_uop_o.imm = issue_pkt_i.decode.imm;
        compact_uop_o.operand_b_rs_sel = issue_pkt_i.decode.operand_b_rs_sel;
        compact_uop_o.operand_a_pc_sel = issue_pkt_i.decode.operand_a_pc_sel;
        compact_uop_o.operand_a_imm_sel = issue_pkt_i.decode.operand_a_imm_sel;
        compact_uop_o.bt_a_rs_sel = issue_pkt_i.decode.bt_a_rs_sel;
        compact_uop_o.operand_b_jump_sel = issue_pkt_i.decode.operand_b_jump_sel;
        compact_uop_o.pred_hit = issue_pkt_i.decode.pred_hit;
        compact_uop_o.pred_taken = issue_pkt_i.decode.pred_taken;
        compact_uop_o.pred_target = issue_pkt_i.decode.pred_target;
        compact_uop_o.pred_counter = issue_pkt_i.decode.pred_counter;
        compact_uop_o.pred_bht_index = issue_pkt_i.decode.pred_bht_index;
        compact_uop_o.csr_raddr = issue_pkt_i.decode.csr_raddr;
        compact_uop_o.csr_waddr = issue_pkt_i.decode.csr_waddr;
        compact_uop_o.csr_op_info = issue_pkt_i.decode.csr_op_info;
        compact_uop_o.sys_op_info = issue_pkt_i.decode.sys_op_info;
        compact_uop_o.fence_i = issue_pkt_i.decode.fence_i;
        compact_uop_o.fp_valid = issue_pkt_i.decode.fp_valid;
        compact_uop_o.fp_illegal = issue_pkt_i.decode.fp_illegal;
        compact_uop_o.fp_op = issue_pkt_i.decode.fp_op;
        compact_uop_o.fp_rm = issue_pkt_i.decode.fp_rm;
        compact_uop_o.fp_rs1_addr = issue_pkt_i.decode.fp_rs1_addr;
        compact_uop_o.fp_rs2_addr = issue_pkt_i.decode.fp_rs2_addr;
        compact_uop_o.fp_rs3_addr = issue_pkt_i.decode.fp_rs3_addr;
        compact_uop_o.fp_rd_addr = issue_pkt_i.decode.fp_rd_addr;
        compact_uop_o.fp_rs1_fpr = issue_pkt_i.decode.fp_rs1_fpr;
        compact_uop_o.fp_rs2_fpr = issue_pkt_i.decode.fp_rs2_fpr;
        compact_uop_o.fp_rs3_fpr = issue_pkt_i.decode.fp_rs3_fpr;
        compact_uop_o.fp_rd_fpr = issue_pkt_i.decode.fp_rd_fpr;
        compact_uop_o.fp_rd_gpr = issue_pkt_i.decode.fp_rd_gpr;
    end
endmodule

module ydrasil_issue_expander
import ydrasil_pkg::*;
(
    input  ydrasil_compact_uop_t compact_uop_i,
    output ydrasil_issue_pkt_t   issue_pkt_o
);
    always_comb begin
        issue_pkt_o = '0;
        issue_pkt_o.valid = compact_uop_i.valid;
        issue_pkt_o.lane1 = compact_uop_i.lane1;
        issue_pkt_o.pair_eligible = compact_uop_i.pair_eligible;
        issue_pkt_o.static_pair = compact_uop_i.pair_eligible;
        issue_pkt_o.lane_mask = compact_uop_i.lane_mask;
        issue_pkt_o.uop_class = compact_uop_i.op_class;
        issue_pkt_o.uop_subop = compact_uop_i.subop;
        issue_pkt_o.uop_lsu_subop = compact_uop_i.lsu_subop;
        issue_pkt_o.src0 = compact_uop_i.src0;
        issue_pkt_o.src1 = compact_uop_i.src1;
        issue_pkt_o.dst = compact_uop_i.dst;
        issue_pkt_o.target = compact_uop_i.pc + compact_uop_i.imm;
        issue_pkt_o.next_pc = compact_uop_i.pc + 32'd4;

        issue_pkt_o.decode.pc = compact_uop_i.pc;
        issue_pkt_o.decode.instr = compact_uop_i.instr;
        issue_pkt_o.decode.imm = compact_uop_i.imm;
        issue_pkt_o.decode.rs1_addr = compact_uop_i.src0.arch_addr;
        issue_pkt_o.decode.rs2_addr = compact_uop_i.src1.arch_addr;
        issue_pkt_o.decode.rd_addr = compact_uop_i.dst.rd_addr;
        issue_pkt_o.decode.rs1_ren = compact_uop_i.src0.used;
        issue_pkt_o.decode.rs2_ren = compact_uop_i.src1.used;
        issue_pkt_o.decode.rd_wen = compact_uop_i.dst.writes_gpr;
        issue_pkt_o.decode.operand_b_rs_sel = compact_uop_i.operand_b_rs_sel;
        issue_pkt_o.decode.operand_a_pc_sel = compact_uop_i.operand_a_pc_sel;
        issue_pkt_o.decode.operand_a_imm_sel = compact_uop_i.operand_a_imm_sel;
        issue_pkt_o.decode.bt_a_rs_sel = compact_uop_i.bt_a_rs_sel;
        issue_pkt_o.decode.operand_b_jump_sel = compact_uop_i.operand_b_jump_sel;
        issue_pkt_o.decode.pred_hit = compact_uop_i.pred_hit;
        issue_pkt_o.decode.pred_taken = compact_uop_i.pred_taken;
        issue_pkt_o.decode.pred_target = compact_uop_i.pred_target;
        issue_pkt_o.decode.pred_counter = compact_uop_i.pred_counter;
        issue_pkt_o.decode.pred_bht_index = compact_uop_i.pred_bht_index;
        issue_pkt_o.decode.csr_raddr = compact_uop_i.csr_raddr;
        issue_pkt_o.decode.csr_waddr = compact_uop_i.csr_waddr;
        issue_pkt_o.decode.csr_op_info = compact_uop_i.csr_op_info;
        issue_pkt_o.decode.sys_op_info = compact_uop_i.sys_op_info;
        issue_pkt_o.decode.fence_i = compact_uop_i.fence_i;
        issue_pkt_o.decode.fp_valid = compact_uop_i.fp_valid;
        issue_pkt_o.decode.fp_illegal = compact_uop_i.fp_illegal;
        issue_pkt_o.decode.fp_op = compact_uop_i.fp_op;
        issue_pkt_o.decode.fp_rm = compact_uop_i.fp_rm;
        issue_pkt_o.decode.fp_rs1_addr = compact_uop_i.fp_rs1_addr;
        issue_pkt_o.decode.fp_rs2_addr = compact_uop_i.fp_rs2_addr;
        issue_pkt_o.decode.fp_rs3_addr = compact_uop_i.fp_rs3_addr;
        issue_pkt_o.decode.fp_rd_addr = compact_uop_i.fp_rd_addr;
        issue_pkt_o.decode.fp_rs1_fpr = compact_uop_i.fp_rs1_fpr;
        issue_pkt_o.decode.fp_rs2_fpr = compact_uop_i.fp_rs2_fpr;
        issue_pkt_o.decode.fp_rs3_fpr = compact_uop_i.fp_rs3_fpr;
        issue_pkt_o.decode.fp_rd_fpr = compact_uop_i.fp_rd_fpr;
        issue_pkt_o.decode.fp_rd_gpr = compact_uop_i.fp_rd_gpr;

        unique case (compact_uop_i.op_class)
            UOP_CLASS_BJP:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_BJP] = 1'b1;
            UOP_CLASS_LOAD:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_LOAD] = 1'b1;
            UOP_CLASS_STORE:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_STORE] = 1'b1;
            UOP_CLASS_CSR:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_CSR] = 1'b1;
            UOP_CLASS_SYS: begin
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_CSR] = 1'b1;
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_SYS] = 1'b1;
            end
            UOP_CLASS_MUL:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_MUL] = 1'b1;
            UOP_CLASS_BITMANIP:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_BITMANIP] = 1'b1;
            UOP_CLASS_FPU:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_FPU] = 1'b1;
            UOP_CLASS_FP_LOAD: begin
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_FPU] = 1'b1;
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_LOAD] = 1'b1;
            end
            UOP_CLASS_FP_STORE: begin
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_FPU] = 1'b1;
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_STORE] = 1'b1;
            end
            default:
                issue_pkt_o.decode.operator_type[OPERATOR_TYPE_ALU] = 1'b1;
        endcase
        if (compact_uop_i.subop < UOP_SUBOP_WIDTH'(OPERATOR_WIDTH))
            issue_pkt_o.decode.operator_info[compact_uop_i.subop] = 1'b1;
        issue_pkt_o.decode.operator_lsu[compact_uop_i.lsu_subop] = 1'b1;

        issue_pkt_o.memory_op =
            (compact_uop_i.op_class == UOP_CLASS_LOAD) ||
            (compact_uop_i.op_class == UOP_CLASS_STORE) ||
            (compact_uop_i.op_class == UOP_CLASS_FP_LOAD) ||
            (compact_uop_i.op_class == UOP_CLASS_FP_STORE);
        issue_pkt_o.ctrl.valid = compact_uop_i.valid;
        issue_pkt_o.ctrl.rs1_addr = compact_uop_i.src0.arch_addr;
        issue_pkt_o.ctrl.rs2_addr = compact_uop_i.src1.arch_addr;
        issue_pkt_o.ctrl.rd_addr = compact_uop_i.dst.rd_addr;
        issue_pkt_o.ctrl.rs1_ren = compact_uop_i.src0.used;
        issue_pkt_o.ctrl.rs2_ren = compact_uop_i.src1.used;
        issue_pkt_o.ctrl.rd_wen = compact_uop_i.dst.writes_gpr;
        issue_pkt_o.ctrl.lsu_req = issue_pkt_o.memory_op;
        issue_pkt_o.ctrl.store_req =
            (compact_uop_i.op_class == UOP_CLASS_STORE) ||
            (compact_uop_i.op_class == UOP_CLASS_FP_STORE);
        issue_pkt_o.ctrl.serialize_before =
            (compact_uop_i.op_class == UOP_CLASS_CSR) ||
            (compact_uop_i.op_class == UOP_CLASS_SYS) || compact_uop_i.fence_i;
        issue_pkt_o.ctrl.checkpoint_req =
            compact_uop_i.op_class == UOP_CLASS_BJP;
    end
endmodule
