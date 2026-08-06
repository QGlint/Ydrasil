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
		if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_BJP])
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
		compact_uop_o.illegal_instr = issue_pkt_i.decode.illegal_instr;
    end
endmodule
