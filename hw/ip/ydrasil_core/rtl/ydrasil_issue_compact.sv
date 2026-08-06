module ydrasil_issue_compactor
import ydrasil_pkg::*;
(
    input  ydrasil_issue_pkt_t   issue_pkt_i,
    output ydrasil_compact_uop_t compact_uop_o
);
    always_comb begin
        compact_uop_o = '0;
        compact_uop_o.valid = issue_pkt_i.valid;
        compact_uop_o.lane_mask = issue_pkt_i.lane_mask;
        compact_uop_o.src0 = issue_pkt_i.src0;
        compact_uop_o.src1 = issue_pkt_i.src1;
        compact_uop_o.dst = issue_pkt_i.dst;

        compact_uop_o.op_class = issue_pkt_i.uop_class;
        compact_uop_o.subop = issue_pkt_i.uop_subop;
        compact_uop_o.lsu_subop = issue_pkt_i.uop_lsu_subop;

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
