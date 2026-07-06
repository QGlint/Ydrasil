module ydrasil_id_issue_stage
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    input wire stall_id_i,
    input wire bubble_id_i,
    input wire flush_id_i,
    input wire [DATA_WIDTH-1:0] if_id_pc_i,
    input wire [DATA_WIDTH-1:0] if_id_instr_i,
    input wire if_id_valid_i,
    output wire [4:0] rf_addr_rs1_o,
    output wire [4:0] rf_addr_rs2_o,
    input wire [DATA_WIDTH-1:0] rf_rdata_rs1_i,
    input wire [DATA_WIDTH-1:0] rf_rdata_rs2_i,
    output wire [4:0] pipe1_rf_addr_rs1_o,
    output wire [4:0] pipe1_rf_addr_rs2_o,
    input wire [DATA_WIDTH-1:0] pipe1_rf_rdata_rs1_i,
    input wire [DATA_WIDTH-1:0] pipe1_rf_rdata_rs2_i,
    input wire wb_fwd_valid_i,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_fwd_addr_i,
    input wire [DATA_WIDTH-1:0] wb_fwd_data_i,
    input wire lsu_fwd_valid_i,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_fwd_addr_i,
    input wire [5:0] lsu_fwd_pdst_i,
    input wire [DATA_WIDTH-1:0] lsu_fwd_data_i,
    input wire alu_fwd_valid_i,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] alu_fwd_addr_i,
    input wire [5:0] alu_fwd_pdst_i,
    input wire [DATA_WIDTH-1:0] alu_fwd_data_i,
    input wire pipe1_alu_fwd_valid_i,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_alu_fwd_addr_i,
    input wire [5:0] pipe1_alu_fwd_pdst_i,
    input wire [DATA_WIDTH-1:0] pipe1_alu_fwd_data_i,
    input wire prf_rs1_ready_i,
    input wire prf_rs2_ready_i,
    input wire [DATA_WIDTH-1:0] prf_rs1_data_i,
    input wire [DATA_WIDTH-1:0] prf_rs2_data_i,
    input wire prf_rs1_uncommitted_i,
    input wire prf_rs2_uncommitted_i,
    input wire pipe1_prf_rs1_ready_i,
    input wire pipe1_prf_rs2_ready_i,
    input wire [DATA_WIDTH-1:0] pipe1_prf_rs1_data_i,
    input wire [DATA_WIDTH-1:0] pipe1_prf_rs2_data_i,
    input wire pipe1_prf_rs1_uncommitted_i,
    input wire pipe1_prf_rs2_uncommitted_i,
    input wire rn_if_rs1_ready_i,
    input wire rn_if_rs2_ready_i,
    input wire [5:0] rn_if_rs1_psrc_i,
    input wire [5:0] rn_if_rs2_psrc_i,
    input wire rs1_issue_alu_ready_next_i,
    input wire rs2_issue_alu_ready_next_i,
    input wire rs1_issue_alu_stable_bypass_i,
    input wire rs2_issue_alu_stable_bypass_i,
    input wire ready_issue_allow_i,
    input wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_i,
    input wire [63:0] rn_preg_ready_i,
    input wire pipe1_resbuf_full_i,
    output wire issue_frontend_stall_o,
    output wire rn_alloc_valid_o,
    output wire [DATA_WIDTH-1:0] operand_a,
    output wire [DATA_WIDTH-1:0] operand_b,
    output wire [DATA_WIDTH-1:0] bt_a_operand,
    output wire [DATA_WIDTH-1:0] bt_b_operand,
    output wire id_fence_i,
    input wire id_advance,
    input wire skid_valid_ff,
    input wire [4:0] skid_rf_raddr_rs1_ff,
    input wire [4:0] skid_rf_raddr_rs2_ff,
    input wire skid_rf_ren_rs1_ff,
    input wire skid_rf_ren_rs2_ff,
    input wire [4:0] skid_rf_waddr_rd_ff,
    input wire skid_rf_wen_rd_ff,
    input wire [DATA_WIDTH-1:0] skid_imm_ff,
    input wire skid_operand_b_rs_sel_ff,
    input wire skid_operand_a_pc_sel_ff,
    input wire skid_operand_a_imm_sel_ff,
    input wire skid_bt_a_rs_sel_ff,
    input wire skid_operand_b_jump_sel_ff,
    input wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] skid_operator_ff,
    input wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] skid_operator_lsu_ff,
    input wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] skid_operator_type_ff,
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] skid_csr_reg_raddr_ff,
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] skid_csr_ex_waddr_ff,
    input wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] skid_csr_op_info_ff,
    input wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] skid_sys_op_info_ff,
    input wire skid_fence_i_ff,
    input wire [5:0] skid_rn_rs1_psrc_ff,
    input wire [5:0] skid_rn_rs2_psrc_ff,
    input wire [5:0] skid_rn_pdst_ff,
    input wire skid_rn_pdst_valid_ff,
    input wire skid_rn_rs1_ready_ff,
    input wire skid_rn_rs2_ready_ff,
    input wire uopq2_buf_valid_ff,
    input wire [DATA_WIDTH-1:0] uopq2_buf_pc_ff,
    input wire [DATA_WIDTH-1:0] uopq2_buf_instr_ff,
    input wire [4:0] uopq2_buf_rf_raddr_rs1_ff,
    input wire [4:0] uopq2_buf_rf_raddr_rs2_ff,
    input wire uopq2_buf_rf_ren_rs1_ff,
    input wire uopq2_buf_rf_ren_rs2_ff,
    input wire [4:0] uopq2_buf_rf_waddr_rd_ff,
    input wire uopq2_buf_rf_wen_rd_ff,
    input wire [DATA_WIDTH-1:0] uopq2_buf_imm_ff,
    input wire uopq2_buf_operand_b_rs_sel_ff,
    input wire uopq2_buf_operand_a_pc_sel_ff,
    input wire uopq2_buf_operand_a_imm_sel_ff,
    input wire uopq2_buf_operand_b_jump_sel_ff,
    input wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] uopq2_buf_operator_ff,
    input wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq2_buf_operator_type_ff,
    input wire uopq2_buf_fence_i_ff,
    input wire [5:0] uopq2_buf_rn_rs1_psrc_ff,
    input wire [5:0] uopq2_buf_rn_rs2_psrc_ff,
    input wire [5:0] uopq2_buf_rn_pdst_ff,
	    input wire uopq2_buf_rn_pdst_valid_ff,
	    input wire uopq2_buf_rs1_ready_ff,
	    input wire uopq2_buf_rs2_ready_ff,
	    input wire uopq3_buf_valid_ff,
	    input wire [DATA_WIDTH-1:0] uopq3_buf_pc_ff,
	    input wire [DATA_WIDTH-1:0] uopq3_buf_instr_ff,
	    input wire [4:0] uopq3_buf_rf_raddr_rs1_ff,
	    input wire [4:0] uopq3_buf_rf_raddr_rs2_ff,
	    input wire uopq3_buf_rf_ren_rs1_ff,
	    input wire uopq3_buf_rf_ren_rs2_ff,
	    input wire [4:0] uopq3_buf_rf_waddr_rd_ff,
	    input wire uopq3_buf_rf_wen_rd_ff,
	    input wire [DATA_WIDTH-1:0] uopq3_buf_imm_ff,
	    input wire uopq3_buf_operand_b_rs_sel_ff,
	    input wire uopq3_buf_operand_a_pc_sel_ff,
	    input wire uopq3_buf_operand_a_imm_sel_ff,
	    input wire uopq3_buf_operand_b_jump_sel_ff,
	    input wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] uopq3_buf_operator_ff,
	    input wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq3_buf_operator_type_ff,
	    input wire uopq3_buf_fence_i_ff,
	    input wire [5:0] uopq3_buf_rn_rs1_psrc_ff,
	    input wire [5:0] uopq3_buf_rn_rs2_psrc_ff,
	    input wire [5:0] uopq3_buf_rn_pdst_ff,
	    input wire uopq3_buf_rn_pdst_valid_ff,
	    input wire uopq3_buf_rs1_ready_ff,
	    input wire uopq3_buf_rs2_ready_ff,
    input wire issue_valid_ff,
    input wire issue_wait_rs1_ff,
    input wire issue_wait_rs2_ff,
    input wire [DATA_WIDTH-1:0] issue_pc_ff,
    input wire issue_pred_hit_ff,
    input wire issue_pred_taken_ff,
    input wire [DATA_WIDTH-1:0] issue_pred_target_ff,
    input wire [1:0] issue_pred_counter_ff,
    input wire [DATA_WIDTH-1:0] issue_pred_bht_index_ff,
    input wire issue_pred_l0_taken_ff,
    input wire [4:0] issue_rf_raddr_rs1_ff,
    input wire [4:0] issue_rf_raddr_rs2_ff,
    input wire issue_rf_ren_rs1_ff,
    input wire issue_rf_ren_rs2_ff,
    input wire [4:0] issue_rf_waddr_rd_ff,
    input wire issue_rf_wen_rd_ff,
    input wire [DATA_WIDTH-1:0] issue_imm_ff,
    input wire issue_operand_b_rs_sel_ff,
    input wire issue_operand_a_pc_sel_ff,
    input wire issue_operand_a_imm_sel_ff,
    input wire issue_bt_a_rs_sel_ff,
    input wire issue_operand_b_jump_sel_ff,
    input wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] issue_operator_ff,
    input wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] issue_operator_lsu_ff,
    input wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff,
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] issue_csr_reg_raddr_ff,
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] issue_csr_ex_waddr_ff,
    input wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] issue_csr_op_info_ff,
    input wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] issue_sys_op_info_ff,
    input wire issue_fence_i_ff,
    input wire [5:0] issue_rn_rs1_psrc_ff,
    input wire [5:0] issue_rn_rs2_psrc_ff,
    input wire [5:0] issue_rn_pdst_ff,
    input wire issue_rn_pdst_valid_ff,
`ifndef SYNTHESIS
    input wire [DATA_WIDTH-1:0] alu_stable_data_ff,
`endif
    input wire [DATA_WIDTH-1:0] decode_pc,
    input wire [DATA_WIDTH-1:0] decode_instr,
    input wire decode_pred_hit,
    input wire decode_pred_taken,
    input wire [DATA_WIDTH-1:0] decode_pred_target,
    input wire [1:0] decode_pred_counter,
    input wire [DATA_WIDTH-1:0] decode_pred_bht_index,
    input wire decode_pred_l0_taken,
    input wire decode_valid,
    output wire issue_wait_rs1_ready,
    output wire issue_wait_rs2_ready,
    output wire issue_wait_block,
    output wire issue_slot0_fire,
    output wire issue_slot1_bypass_fire,
    output wire pipe1_dual_fire,
    output wire pair1_fire,
    output wire pipe1_dual_supported,
    output wire pipe1_dual_operands_ready,
    output wire pipe1_dual_raw_pipe0,
    output wire pipe1_dual_waw_pipe0,
    output wire pipe1_dual_war_pipe0,
    output wire pipe1_dual_pending_rd,
    output wire pipe1_younger_flush_risk,
    output wire pipe1_younger_flush_block,
    output wire pipe1_pipe0_present_safe,
    output wire pipe1_pipe0_blocked_load_safe,
    output wire pipe1_pipe0_blocked_store_safe,
    output wire pipe1_pipe0_empty_safe,
    output wire pipe1_dual_pipe0_safe,
    output wire pipe1_dual_rs1_ready,
    output wire pipe1_dual_rs2_ready,
    output wire pipe1_dual_rs1_alu_fwd,
    output wire pipe1_dual_rs2_alu_fwd,
    output wire pipe1_dual_rs1_p1alu_fwd,
    output wire pipe1_dual_rs2_p1alu_fwd,
    output wire pipe1_dual_rs1_wb_fwd,
    output wire pipe1_dual_rs2_wb_fwd,
    output wire [DATA_WIDTH-1:0] pipe1_dual_rs1_data,
    output wire [DATA_WIDTH-1:0] pipe1_dual_rs2_data,
    output wire [DATA_WIDTH-1:0] pipe1_dual_operand_a,
    output wire [DATA_WIDTH-1:0] pipe1_dual_operand_b,
    output wire pair1_refill_dep_p1,
    output wire pair1_refill_dep_p0,
    output wire pair1_refill_srcs_ready,
    output wire pair1_refill_simple_alu,
    output wire pair1_refill_direct,
    output wire issue_fire,
    output wire issue_accept,
    output wire issue_load_from_skid,
    output wire issue_load_from_uopq2,
    output wire skid_fill,
    output wire skid_drain,
	    output wire uopq2_buf_capture,
	    output wire uopq3_buf_capture,
	    output wire uopq2_buf_capture_supported,
    output wire uopq2_buf_capture_operands_ready,
    output wire uopq2_refill_from_if,
    output wire issue_alu_stable_candidate,
    output wire [DATA_WIDTH-1:0] issue_alu_stable_result,
    output wire ri_slot1_valid,
    output wire ri_slot1_supported,
    output wire ri_slot1_block_raw,
    output wire ri_slot1_block_waw,
    output wire ri_slot1_block_war,
    output wire ri_slot1_block_ctrl,
    output wire ri_slot1_block_mem,
    output wire ri_slot1_block_unsupported,
    output wire ri_slot1_block_old_unsupported,
    output wire ri_slot1_block_rs1_pending,
    output wire ri_slot1_block_rs2_pending,
    output wire ri_slot1_block_rd_pending,
    output wire ri_slot1_ready,
    output wire ri_slot1_ready_when_slot0_blocked,
    output wire ri_slot1_ready_when_slot0_ready,
    output wire ri_slot1_fire_blocked_by_single_issue,
    output wire ri_slot1_fire_blocked_by_wb_order,
    output wire ri_bypass_flush_killed,
    output wire [4:0] selected_rf_raddr_rs1,
    output wire [4:0] selected_rf_raddr_rs2,
    output wire selected_rf_ren_rs1,
    output wire selected_rf_ren_rs2,
    output wire [4:0] selected_rf_waddr_rd,
    output wire selected_rf_wen_rd,
    output wire [DATA_WIDTH-1:0] selected_pc,
    output wire [DATA_WIDTH-1:0] selected_imm,
    output wire selected_operand_b_rs_sel,
    output wire selected_operand_a_pc_sel,
    output wire selected_operand_a_imm_sel,
    output wire selected_bt_a_rs_sel,
    output wire selected_operand_b_jump_sel,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] selected_operator,
    output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] selected_operator_lsu,
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] selected_operator_type,
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] selected_csr_reg_raddr,
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] selected_csr_ex_waddr,
    output wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] selected_csr_op_info,
    output wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] selected_sys_op_info,
    output wire selected_fence_i,
    output wire [5:0] selected_rn_rs1_psrc,
    output wire [5:0] selected_rn_rs2_psrc,
    output wire [5:0] selected_rn_pdst,
    output wire selected_rn_pdst_valid,
    output wire selected_pred_hit,
    output wire selected_pred_taken,
    output wire [DATA_WIDTH-1:0] selected_pred_target,
    output wire [1:0] selected_pred_counter,
    output wire [DATA_WIDTH-1:0] selected_pred_bht_index,
    output wire selected_pred_l0_taken,
    output wire [4:0] slot1_rf_raddr_rs1,
    output wire [4:0] slot1_rf_raddr_rs2,
    output wire slot1_rf_ren_rs1,
    output wire slot1_rf_ren_rs2,
    output wire [4:0] slot1_rf_waddr_rd,
    output wire slot1_rf_wen_rd,
    output wire [DATA_WIDTH-1:0] slot1_imm,
    output wire slot1_operand_b_rs_sel,
    output wire slot1_operand_a_pc_sel,
    output wire slot1_operand_a_imm_sel,
    output wire slot1_bt_a_rs_sel,
    output wire slot1_operand_b_jump_sel,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] slot1_operator,
    output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] slot1_operator_lsu,
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] slot1_operator_type,
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] slot1_csr_reg_raddr,
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] slot1_csr_ex_waddr,
    output wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] slot1_csr_op_info,
    output wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] slot1_sys_op_info,
    output wire slot1_fence_i,
    output wire uopq0_valid,
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq0_operator_type,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] uopq0_operator,
    output wire uopq0_fence_i,
    output wire uopq0_rf_wen_rd,
    output wire [4:0] uopq0_rf_waddr_rd,
    output wire uopq1_valid,
    output wire [DATA_WIDTH-1:0] uopq1_pc,
    output wire [DATA_WIDTH-1:0] uopq1_instr,
    output wire [4:0] uopq1_rf_raddr_rs1,
    output wire [4:0] uopq1_rf_raddr_rs2,
    output wire uopq1_rf_ren_rs1,
    output wire uopq1_rf_ren_rs2,
    output wire [4:0] uopq1_rf_waddr_rd,
    output wire uopq1_rf_wen_rd,
    output wire [DATA_WIDTH-1:0] uopq1_imm,
    output wire uopq1_operand_b_rs_sel,
    output wire uopq1_operand_a_pc_sel,
    output wire uopq1_operand_a_imm_sel,
    output wire uopq1_operand_b_jump_sel,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] uopq1_operator,
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq1_operator_type,
    output wire uopq1_fence_i,
    output wire uopq2_valid,
    output wire [DATA_WIDTH-1:0] uopq2_pc,
    output wire [DATA_WIDTH-1:0] uopq2_instr,
    output wire [4:0] uopq2_rf_raddr_rs1,
    output wire [4:0] uopq2_rf_raddr_rs2,
    output wire uopq2_rf_ren_rs1,
    output wire uopq2_rf_ren_rs2,
    output wire [4:0] uopq2_rf_waddr_rd,
    output wire uopq2_rf_wen_rd,
    output wire [DATA_WIDTH-1:0] uopq2_imm,
    output wire uopq2_operand_b_rs_sel,
    output wire uopq2_operand_a_pc_sel,
    output wire uopq2_operand_a_imm_sel,
    output wire uopq2_operand_b_jump_sel,
	    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] uopq2_operator,
	    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq2_operator_type,
	    output wire uopq2_fence_i,
	    output wire uopq3_valid,
	    output wire [DATA_WIDTH-1:0] uopq3_pc,
	    output wire [DATA_WIDTH-1:0] uopq3_instr,
	    output wire [4:0] uopq3_rf_raddr_rs1,
	    output wire [4:0] uopq3_rf_raddr_rs2,
	    output wire uopq3_rf_ren_rs1,
	    output wire uopq3_rf_ren_rs2,
	    output wire [4:0] uopq3_rf_waddr_rd,
	    output wire uopq3_rf_wen_rd,
	    output wire [DATA_WIDTH-1:0] uopq3_imm,
	    output wire uopq3_operand_b_rs_sel,
	    output wire uopq3_operand_a_pc_sel,
	    output wire uopq3_operand_a_imm_sel,
	    output wire uopq3_operand_b_jump_sel,
	    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] uopq3_operator,
	    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq3_operator_type,
	    output wire uopq3_fence_i,
	    output wire pipe1_sel_from1,
	    output wire pipe1_sel_from2,
	    output wire pipe1_sel_from3,
    output wire [DATA_WIDTH-1:0] pipe1_sel_pc,
    output wire [DATA_WIDTH-1:0] pipe1_sel_instr,
    output wire [4:0] pipe1_sel_rf_raddr_rs1,
    output wire [4:0] pipe1_sel_rf_raddr_rs2,
    output wire pipe1_sel_rf_ren_rs1,
    output wire pipe1_sel_rf_ren_rs2,
    output wire [4:0] pipe1_sel_rf_waddr_rd,
    output wire pipe1_sel_rf_wen_rd,
    output wire [5:0] pipe1_sel_rs1_psrc,
    output wire [5:0] pipe1_sel_rs2_psrc,
    output wire [5:0] pipe1_sel_pdst,
    output wire pipe1_sel_pdst_valid,
    output wire [DATA_WIDTH-1:0] pipe1_sel_imm,
    output wire pipe1_sel_operand_b_rs_sel,
    output wire pipe1_sel_operand_a_pc_sel,
    output wire pipe1_sel_operand_a_imm_sel,
    output wire pipe1_sel_operand_b_jump_sel,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_sel_operator,
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] pipe1_sel_operator_type,
	    output wire pipe1_uopq1_supported,
	    output wire pipe1_uopq2_supported,
	    output wire pipe1_uopq3_supported,
	    output wire pipe1_uopq1_operands_ready,
	    output wire pipe1_uopq2_operands_ready,
	    output wire pipe1_uopq3_operands_ready,
	    output wire pipe1_uopq1_safe,
	    output wire pipe1_uopq2_safe,
	    output wire pipe1_uopq3_safe,
	    output wire pipe1_uopq1_store_war_pipe0,
	    output wire pipe1_uopq2_store_war_pipe0,
	    output wire pipe1_uopq3_store_war_pipe0,
    output wire pipe1_p0_ready_context,
    output wire pipe1_p0_blocked_context,
    output wire pipe1_p0_empty_base,
    output wire pipe1_p0_empty_context,
	    output wire pipe1_fire_from1,
	    output wire pipe1_fire_from2,
	    output wire pipe1_fire_from3,
    input wire [4:0] if_id_trace_rf_waddr_rd,
    input wire if_id_trace_rf_wen_rd,
    input wire if_id_trace_operand_b_rs_sel,
    input wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] if_id_trace_operator,
    input wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] if_id_trace_operator_type,
    input wire [4:0] if_id_trace_rf_raddr_rs1,
    input wire [4:0] if_id_trace_rf_raddr_rs2,
    input wire if_id_trace_rf_ren_rs1,
    input wire if_id_trace_rf_ren_rs2,
    output wire pipe1_refill_skid_from_if,
    output wire pipe1_take_if_id,
    output wire pipe1_uopq1_order_safe,
    output wire ri_slot1_rs1_clear_fwd,
    output wire ri_slot1_rs2_read,
    output wire ri_slot1_rs2_clear_fwd,
    output wire if_id_rn_pdst_valid,
    output wire if_id_live_accept,
    output wire [DATA_WIDTH-1:0] issue_rs2_data,
    output wire rs1_lsu_fwd,
    output wire rs2_lsu_fwd,
    output wire rs1_wb_fwd,
    output wire rs2_wb_fwd,
    output wire slot0_rs1_prf_ready,
    output wire slot0_rs2_prf_ready
);

    assign slot1_rf_raddr_rs1 = skid_rf_raddr_rs1_ff;
    assign slot1_rf_raddr_rs2 = skid_rf_raddr_rs2_ff;
    assign slot1_rf_ren_rs1 = skid_rf_ren_rs1_ff;
    assign slot1_rf_ren_rs2 = skid_rf_ren_rs2_ff;
    assign slot1_rf_waddr_rd = skid_rf_waddr_rd_ff;
    assign slot1_rf_wen_rd = skid_rf_wen_rd_ff;
    assign slot1_imm = skid_imm_ff;
    assign slot1_operand_b_rs_sel = skid_operand_b_rs_sel_ff;
    assign slot1_operand_a_pc_sel = skid_operand_a_pc_sel_ff;
    assign slot1_operand_a_imm_sel = skid_operand_a_imm_sel_ff;
    assign slot1_bt_a_rs_sel = skid_bt_a_rs_sel_ff;
    assign slot1_operand_b_jump_sel = skid_operand_b_jump_sel_ff;
    assign slot1_operator = skid_operator_ff;
    assign slot1_operator_lsu = skid_operator_lsu_ff;
    assign slot1_operator_type = skid_operator_type_ff;
    assign slot1_csr_reg_raddr = skid_csr_reg_raddr_ff;
    assign slot1_csr_ex_waddr = skid_csr_ex_waddr_ff;
    assign slot1_csr_op_info = skid_csr_op_info_ff;
    assign slot1_sys_op_info = skid_sys_op_info_ff;
    assign slot1_fence_i = skid_fence_i_ff;

    assign uopq0_valid = issue_valid_ff;
    assign uopq0_operator_type = issue_operator_type_ff;
    assign uopq0_operator = issue_operator_ff;
    assign uopq0_fence_i = issue_fence_i_ff;
    assign uopq0_rf_wen_rd = issue_rf_wen_rd_ff;
    assign uopq0_rf_waddr_rd = issue_rf_waddr_rd_ff;

    assign uopq1_valid = skid_valid_ff;
    assign uopq1_pc = decode_pc;
    assign uopq1_instr = decode_instr;
    assign uopq1_rf_raddr_rs1 = slot1_rf_raddr_rs1;
    assign uopq1_rf_raddr_rs2 = slot1_rf_raddr_rs2;
    assign uopq1_rf_ren_rs1 = slot1_rf_ren_rs1;
    assign uopq1_rf_ren_rs2 = slot1_rf_ren_rs2;
    assign uopq1_rf_waddr_rd = slot1_rf_waddr_rd;
    assign uopq1_rf_wen_rd = slot1_rf_wen_rd;
    assign uopq1_imm = slot1_imm;
    assign uopq1_operand_b_rs_sel = slot1_operand_b_rs_sel;
    assign uopq1_operand_a_pc_sel = slot1_operand_a_pc_sel;
    assign uopq1_operand_a_imm_sel = slot1_operand_a_imm_sel;
    assign uopq1_operand_b_jump_sel = slot1_operand_b_jump_sel;
    assign uopq1_operator = slot1_operator;
    assign uopq1_operator_type = slot1_operator_type;
    assign uopq1_fence_i = slot1_fence_i;

    assign uopq2_valid = uopq2_buf_valid_ff;
    assign uopq2_pc = uopq2_buf_pc_ff;
    assign uopq2_instr = uopq2_buf_instr_ff;
    assign uopq2_rf_raddr_rs1 = uopq2_buf_rf_raddr_rs1_ff;
    assign uopq2_rf_raddr_rs2 = uopq2_buf_rf_raddr_rs2_ff;
    assign uopq2_rf_ren_rs1 = uopq2_buf_rf_ren_rs1_ff;
    assign uopq2_rf_ren_rs2 = uopq2_buf_rf_ren_rs2_ff;
    assign uopq2_rf_waddr_rd = uopq2_buf_rf_waddr_rd_ff;
    assign uopq2_rf_wen_rd = uopq2_buf_rf_wen_rd_ff;
    assign uopq2_imm = uopq2_buf_imm_ff;
    assign uopq2_operand_b_rs_sel = uopq2_buf_operand_b_rs_sel_ff;
    assign uopq2_operand_a_pc_sel = uopq2_buf_operand_a_pc_sel_ff;
    assign uopq2_operand_a_imm_sel = uopq2_buf_operand_a_imm_sel_ff;
    assign uopq2_operand_b_jump_sel = uopq2_buf_operand_b_jump_sel_ff;
	    assign uopq2_operator = uopq2_buf_operator_ff;
	    assign uopq2_operator_type = uopq2_buf_operator_type_ff;
	    assign uopq2_fence_i = uopq2_buf_fence_i_ff;

	    assign uopq3_valid = uopq3_buf_valid_ff;
	    assign uopq3_pc = uopq3_buf_pc_ff;
	    assign uopq3_instr = uopq3_buf_instr_ff;
	    assign uopq3_rf_raddr_rs1 = uopq3_buf_rf_raddr_rs1_ff;
	    assign uopq3_rf_raddr_rs2 = uopq3_buf_rf_raddr_rs2_ff;
	    assign uopq3_rf_ren_rs1 = uopq3_buf_rf_ren_rs1_ff;
	    assign uopq3_rf_ren_rs2 = uopq3_buf_rf_ren_rs2_ff;
	    assign uopq3_rf_waddr_rd = uopq3_buf_rf_waddr_rd_ff;
	    assign uopq3_rf_wen_rd = uopq3_buf_rf_wen_rd_ff;
	    assign uopq3_imm = uopq3_buf_imm_ff;
	    assign uopq3_operand_b_rs_sel = uopq3_buf_operand_b_rs_sel_ff;
	    assign uopq3_operand_a_pc_sel = uopq3_buf_operand_a_pc_sel_ff;
	    assign uopq3_operand_a_imm_sel = uopq3_buf_operand_a_imm_sel_ff;
	    assign uopq3_operand_b_jump_sel = uopq3_buf_operand_b_jump_sel_ff;
	    assign uopq3_operator = uopq3_buf_operator_ff;
	    assign uopq3_operator_type = uopq3_buf_operator_type_ff;
	    assign uopq3_fence_i = uopq3_buf_fence_i_ff;

    assign selected_rf_raddr_rs1 =
        issue_slot1_bypass_fire ? slot1_rf_raddr_rs1 : issue_rf_raddr_rs1_ff;
    assign selected_rf_raddr_rs2 =
        issue_slot1_bypass_fire ? slot1_rf_raddr_rs2 : issue_rf_raddr_rs2_ff;
    assign selected_rf_ren_rs1 =
        issue_slot1_bypass_fire ? slot1_rf_ren_rs1 : issue_rf_ren_rs1_ff;
    assign selected_rf_ren_rs2 =
        issue_slot1_bypass_fire ? slot1_rf_ren_rs2 : issue_rf_ren_rs2_ff;
    assign selected_rf_waddr_rd =
        issue_slot1_bypass_fire ? slot1_rf_waddr_rd : issue_rf_waddr_rd_ff;
    assign selected_rf_wen_rd =
        issue_slot1_bypass_fire ? slot1_rf_wen_rd : issue_rf_wen_rd_ff;
    assign selected_pc =
        issue_slot1_bypass_fire ? decode_pc : issue_pc_ff;
    assign selected_imm =
        issue_slot1_bypass_fire ? slot1_imm : issue_imm_ff;
    assign selected_operand_b_rs_sel =
        issue_slot1_bypass_fire ? slot1_operand_b_rs_sel : issue_operand_b_rs_sel_ff;
    assign selected_operand_a_pc_sel =
        issue_slot1_bypass_fire ? slot1_operand_a_pc_sel : issue_operand_a_pc_sel_ff;
    assign selected_operand_a_imm_sel =
        issue_slot1_bypass_fire ? slot1_operand_a_imm_sel : issue_operand_a_imm_sel_ff;
    assign selected_bt_a_rs_sel =
        issue_slot1_bypass_fire ? slot1_bt_a_rs_sel : issue_bt_a_rs_sel_ff;
    assign selected_operand_b_jump_sel =
        issue_slot1_bypass_fire ? slot1_operand_b_jump_sel : issue_operand_b_jump_sel_ff;
    assign selected_operator =
        issue_slot1_bypass_fire ? slot1_operator : issue_operator_ff;
    assign selected_operator_lsu =
        issue_slot1_bypass_fire ? slot1_operator_lsu : issue_operator_lsu_ff;
    assign selected_operator_type =
        issue_slot1_bypass_fire ? slot1_operator_type : issue_operator_type_ff;
    assign selected_csr_reg_raddr =
        issue_slot1_bypass_fire ? slot1_csr_reg_raddr : issue_csr_reg_raddr_ff;
    assign selected_csr_ex_waddr =
        issue_slot1_bypass_fire ? slot1_csr_ex_waddr : issue_csr_ex_waddr_ff;
    assign selected_csr_op_info =
        issue_slot1_bypass_fire ? slot1_csr_op_info : issue_csr_op_info_ff;
    assign selected_sys_op_info =
        issue_slot1_bypass_fire ? slot1_sys_op_info : issue_sys_op_info_ff;
    assign selected_fence_i =
        issue_slot1_bypass_fire ? slot1_fence_i : issue_fence_i_ff;
    assign selected_rn_rs1_psrc =
        issue_slot1_bypass_fire ? skid_rn_rs1_psrc_ff : issue_rn_rs1_psrc_ff;
    assign selected_rn_rs2_psrc =
        issue_slot1_bypass_fire ? skid_rn_rs2_psrc_ff : issue_rn_rs2_psrc_ff;
    assign selected_rn_pdst =
        issue_slot1_bypass_fire ? skid_rn_pdst_ff : issue_rn_pdst_ff;
    assign selected_rn_pdst_valid =
        issue_slot1_bypass_fire ? skid_rn_pdst_valid_ff : issue_rn_pdst_valid_ff;
    assign selected_pred_hit =
        issue_slot1_bypass_fire ? decode_pred_hit : issue_pred_hit_ff;
    assign selected_pred_taken =
        issue_slot1_bypass_fire ? decode_pred_taken : issue_pred_taken_ff;
    assign selected_pred_target =
        issue_slot1_bypass_fire ? decode_pred_target : issue_pred_target_ff;
    assign selected_pred_counter =
        issue_slot1_bypass_fire ? decode_pred_counter : issue_pred_counter_ff;
    assign selected_pred_bht_index =
        issue_slot1_bypass_fire ? decode_pred_bht_index : issue_pred_bht_index_ff;
    assign selected_pred_l0_taken =
        issue_slot1_bypass_fire ? decode_pred_l0_taken : issue_pred_l0_taken_ff;

    assign rf_addr_rs1_o = selected_rf_raddr_rs1;
    assign rf_addr_rs2_o = selected_rf_raddr_rs2;
    assign pipe1_rf_addr_rs1_o = pipe1_sel_rf_raddr_rs1;
    assign pipe1_rf_addr_rs2_o = pipe1_sel_rf_raddr_rs2;

    // Keep ALU source selection consistent with decoder control outputs.
    wire slot0_rs1_wb_fwd =
        wb_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rn_rs1_psrc_ff == {1'b0, issue_rf_raddr_rs1_ff}) &&
        !prf_rs1_uncommitted_i &&
        (issue_rf_raddr_rs1_ff == wb_fwd_addr_i);
    wire slot0_rs2_wb_fwd =
        wb_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rn_rs2_psrc_ff == {1'b0, issue_rf_raddr_rs2_ff}) &&
        !prf_rs2_uncommitted_i &&
        (issue_rf_raddr_rs2_ff == wb_fwd_addr_i);
    wire slot0_rs1_lsu_fwd =
        lsu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == lsu_fwd_addr_i) &&
        (issue_rn_rs1_psrc_ff == lsu_fwd_pdst_i);
    wire slot0_rs2_lsu_fwd =
        lsu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == lsu_fwd_addr_i) &&
        (issue_rn_rs2_psrc_ff == lsu_fwd_pdst_i);
    wire slot0_rs1_alu_fwd =
        alu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == alu_fwd_addr_i) &&
        (issue_rn_rs1_psrc_ff == alu_fwd_pdst_i);
    wire slot0_rs2_alu_fwd =
        alu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == alu_fwd_addr_i) &&
        (issue_rn_rs2_psrc_ff == alu_fwd_pdst_i);
    wire slot0_rs1_stable_fwd = rs1_issue_alu_stable_bypass_i;
    wire slot0_rs2_stable_fwd = rs2_issue_alu_stable_bypass_i;
    wire slot0_rs1_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == pipe1_alu_fwd_addr_i) &&
        (issue_rn_rs1_psrc_ff == pipe1_alu_fwd_pdst_i);
    wire slot0_rs2_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == pipe1_alu_fwd_addr_i) &&
        (issue_rn_rs2_psrc_ff == pipe1_alu_fwd_pdst_i);
    wire slot0_rs1_pending_cleared =
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rn_rs1_psrc_ff != issue_rn_pdst_ff) &&
        rn_preg_ready_i[issue_rn_rs1_psrc_ff];
    wire slot0_rs2_pending_cleared =
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rn_rs2_psrc_ff != issue_rn_pdst_ff) &&
        rn_preg_ready_i[issue_rn_rs2_psrc_ff];
    assign slot0_rs1_prf_ready =
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rn_rs1_psrc_ff != issue_rn_pdst_ff) &&
        prf_rs1_ready_i;
    assign slot0_rs2_prf_ready =
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rn_rs2_psrc_ff != issue_rn_pdst_ff) &&
        prf_rs2_ready_i;
    assign rs1_wb_fwd =
        wb_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rn_rs1_psrc == {1'b0, selected_rf_raddr_rs1}) &&
        !prf_rs1_uncommitted_i &&
        (selected_rf_raddr_rs1 == wb_fwd_addr_i);
    assign rs2_wb_fwd =
        wb_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rn_rs2_psrc == {1'b0, selected_rf_raddr_rs2}) &&
        !prf_rs2_uncommitted_i &&
        (selected_rf_raddr_rs2 == wb_fwd_addr_i);
    assign rs1_lsu_fwd =
        lsu_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rf_raddr_rs1 == lsu_fwd_addr_i) &&
        (selected_rn_rs1_psrc == lsu_fwd_pdst_i);
    assign rs2_lsu_fwd =
        lsu_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rf_raddr_rs2 == lsu_fwd_addr_i) &&
        (selected_rn_rs2_psrc == lsu_fwd_pdst_i);
    wire rs1_alu_fwd =
        alu_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rf_raddr_rs1 == alu_fwd_addr_i) &&
        (selected_rn_rs1_psrc == alu_fwd_pdst_i);
    wire rs2_alu_fwd =
        alu_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rf_raddr_rs2 == alu_fwd_addr_i) &&
        (selected_rn_rs2_psrc == alu_fwd_pdst_i);
    wire rs1_stable_fwd =
        !issue_slot1_bypass_fire && rs1_issue_alu_stable_bypass_i;
    wire rs2_stable_fwd =
        !issue_slot1_bypass_fire && rs2_issue_alu_stable_bypass_i;
    wire rs1_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rf_raddr_rs1 == pipe1_alu_fwd_addr_i) &&
        (selected_rn_rs1_psrc == pipe1_alu_fwd_pdst_i);
    wire rs2_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rf_raddr_rs2 == pipe1_alu_fwd_addr_i) &&
        (selected_rn_rs2_psrc == pipe1_alu_fwd_pdst_i);
    wire [DATA_WIDTH-1:0] issue_alu_stable_data = alu_stable_data_ff;
    wire selected_prf_operand_allowed =
        selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] |
        selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
        selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
        selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
        selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] |
        selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR];
	wire selected_prf_rs1_allowed =
		selected_prf_operand_allowed &&
		selected_rf_ren_rs1 &&
		(selected_rf_raddr_rs1 != '0) &&
		(selected_rn_rs1_psrc != '0) &&
		(prf_rs1_uncommitted_i || (selected_rn_rs1_psrc != {1'b0, selected_rf_raddr_rs1})) &&
		(selected_rn_rs1_psrc != selected_rn_pdst);
	wire selected_prf_rs2_allowed =
		selected_prf_operand_allowed &&
		(selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
		(selected_rf_raddr_rs2 != '0) &&
		(selected_rn_rs2_psrc != '0) &&
		(prf_rs2_uncommitted_i || (selected_rn_rs2_psrc != {1'b0, selected_rf_raddr_rs2})) &&
		(selected_rn_rs2_psrc != selected_rn_pdst);
    wire [DATA_WIDTH-1:0] issue_rs1_data =
        (!issue_slot1_bypass_fire && selected_prf_rs1_allowed && prf_rs1_ready_i) ? prf_rs1_data_i :
        rs1_lsu_fwd ? lsu_fwd_data_i :
        rs1_stable_fwd ? issue_alu_stable_data :
        rs1_alu_fwd ? alu_fwd_data_i :
        rs1_p1alu_fwd ? pipe1_alu_fwd_data_i :
        rs1_wb_fwd  ? wb_fwd_data_i  :
        rf_rdata_rs1_i;
    assign issue_rs2_data =
        (!issue_slot1_bypass_fire && selected_prf_rs2_allowed && prf_rs2_ready_i) ? prf_rs2_data_i :
        rs2_lsu_fwd ? lsu_fwd_data_i :
        rs2_stable_fwd ? issue_alu_stable_data :
        rs2_alu_fwd ? alu_fwd_data_i :
        rs2_p1alu_fwd ? pipe1_alu_fwd_data_i :
        rs2_wb_fwd  ? wb_fwd_data_i  :
        rf_rdata_rs2_i;

    assign operand_a     =  selected_operand_a_pc_sel ? selected_pc :
                            selected_operand_a_imm_sel ? selected_imm : issue_rs1_data;
    assign operand_b     = selected_operand_b_jump_sel ? 32'h4 :
                            selected_operand_b_rs_sel ? issue_rs2_data : selected_imm;

`ifdef YDRASIL_RN_DEBUG_DISPLAY
	always_ff @(posedge clk) begin
		if (rst_n && issue_fire &&
		    ((selected_pc >= 32'h8000_007c && selected_pc <= 32'h8000_0090) ||
		     (selected_pc >= 32'h8000_0380 && selected_pc <= 32'h8000_0438) ||
		     (selected_pc >= 32'h8000_2da8 && selected_pc <= 32'h8000_2dc8) ||
		     (selected_pc >= 32'h8000_1e60 && selected_pc <= 32'h8000_1eb4))) begin
			$display("[ID_RN_DBG] pc=0x%08h instr=0x%08h slot1=%0b rs1=x%0d ren=%0b psrc=%0d prf_ready=%0b prf_uncomm=%0b prf=0x%08h rf=0x%08h data=0x%08h use_prf=%0b alu_fwd=%0b wb_fwd=%0b rs2=x%0d psrc=%0d rd=x%0d pdst=%0d gpr_pending_rs1=%0b op_a=0x%08h op_b=0x%08h",
			         selected_pc,
			         (issue_slot1_bypass_fire ? decode_instr : 32'h0),
			         issue_slot1_bypass_fire,
			         selected_rf_raddr_rs1,
			         selected_rf_ren_rs1,
			         selected_rn_rs1_psrc,
			         prf_rs1_ready_i,
			         prf_rs1_uncommitted_i,
			         prf_rs1_data_i,
			         rf_rdata_rs1_i,
			         issue_rs1_data,
			         (!issue_slot1_bypass_fire && selected_prf_rs1_allowed && prf_rs1_ready_i),
			         rs1_alu_fwd,
			         rs1_wb_fwd,
			         selected_rf_raddr_rs2,
			         selected_rn_rs2_psrc,
			         selected_rf_waddr_rd,
                     selected_rn_pdst,
                     ((selected_rf_raddr_rs1 != '0) ? gpr_pending_i[selected_rf_raddr_rs1] : 1'b0),
                     operand_a,
                     operand_b);
		end
		if (rst_n && pair1_fire &&
		    ((pipe1_sel_pc >= 32'h8000_007c && pipe1_sel_pc <= 32'h8000_0090) ||
		     (pipe1_sel_pc >= 32'h8000_2da8 && pipe1_sel_pc <= 32'h8000_2dc8))) begin
            $display("[P1_RN_DBG] pc=0x%08h instr=0x%08h rs1=x%0d ren=%0b psrc=%0d prf_ready=%0b prf=0x%08h rf=0x%08h data=0x%08h rs2=x%0d psrc=%0d rd=x%0d pdst=%0d p1safe=%0b younger_flush_risk=%0b",
                     pipe1_sel_pc,
                     pipe1_sel_instr,
                     pipe1_sel_rf_raddr_rs1,
                     pipe1_sel_rf_ren_rs1,
                     pipe1_sel_rs1_psrc,
                     pipe1_prf_rs1_ready_i,
                     pipe1_prf_rs1_data_i,
                     pipe1_rf_rdata_rs1_i,
                     pipe1_dual_rs1_data,
                     pipe1_sel_rf_raddr_rs2,
                     pipe1_sel_rs2_psrc,
                     pipe1_sel_rf_waddr_rd,
                     pipe1_sel_pdst,
                     pipe1_uopq1_safe,
                     pipe1_younger_flush_risk);
        end
    end
`endif

    assign issue_alu_stable_candidate =
        issue_slot0_fire &&
        issue_rf_wen_rd_ff && (issue_rf_waddr_rd_ff != '0) &&
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        (issue_operator_ff[ydrasil_pkg::OP_ALU_LUI] |
         (issue_operator_ff[ydrasil_pkg::OP_ALU_ADD] &&
          !issue_operand_b_rs_sel_ff &&
          issue_rf_ren_rs1_ff &&
          (issue_rf_raddr_rs1_ff == '0)));
    assign issue_alu_stable_result = issue_imm_ff;


    assign bt_a_operand = selected_bt_a_rs_sel ? issue_rs1_data : selected_pc;
    assign bt_b_operand = selected_imm;
    assign id_fence_i = (decode_instr[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                        (decode_instr[14:12] == 3'b001);

    assign issue_wait_rs1_ready =
        !issue_wait_rs1_ff | slot0_rs1_stable_fwd | slot0_rs1_alu_fwd | slot0_rs1_p1alu_fwd |
        slot0_rs1_lsu_fwd | slot0_rs1_wb_fwd | slot0_rs1_pending_cleared |
        slot0_rs1_prf_ready;
    assign issue_wait_rs2_ready =
        !issue_wait_rs2_ff | slot0_rs2_stable_fwd | slot0_rs2_alu_fwd | slot0_rs2_p1alu_fwd |
        slot0_rs2_lsu_fwd | slot0_rs2_wb_fwd | slot0_rs2_pending_cleared |
        slot0_rs2_prf_ready;
    wire slot0_rs1_phys_block =
        issue_valid_ff &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rn_rs1_psrc_ff != '0) &&
        (issue_rn_rs1_psrc_ff != issue_rn_pdst_ff) &&
        !rn_preg_ready_i[issue_rn_rs1_psrc_ff] &&
        !slot0_rs1_stable_fwd &&
        !slot0_rs1_alu_fwd &&
        !slot0_rs1_p1alu_fwd &&
        !slot0_rs1_lsu_fwd &&
        !slot0_rs1_wb_fwd;
    wire slot0_rs2_phys_block =
        issue_valid_ff &&
        (issue_rf_ren_rs2_ff | issue_operand_b_rs_sel_ff |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rn_rs2_psrc_ff != '0) &&
        (issue_rn_rs2_psrc_ff != issue_rn_pdst_ff) &&
        !rn_preg_ready_i[issue_rn_rs2_psrc_ff] &&
        !slot0_rs2_stable_fwd &&
        !slot0_rs2_alu_fwd &&
        !slot0_rs2_p1alu_fwd &&
        !slot0_rs2_lsu_fwd &&
        !slot0_rs2_wb_fwd;
    wire slot1_bypass_rs1_phys_ready =
        !slot1_rf_ren_rs1 ||
        (slot1_rf_raddr_rs1 == '0) ||
        (skid_rn_rs1_psrc_ff == '0) ||
        (rn_preg_ready_i[skid_rn_rs1_psrc_ff] &&
         (skid_rn_rs1_psrc_ff == {1'b0, slot1_rf_raddr_rs1}));
    wire slot1_bypass_rs2_phys_ready =
        !(slot1_rf_ren_rs2 | slot1_operand_b_rs_sel |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) ||
        (slot1_rf_raddr_rs2 == '0) ||
        (skid_rn_rs2_psrc_ff == '0) ||
        (rn_preg_ready_i[skid_rn_rs2_psrc_ff] &&
         (skid_rn_rs2_psrc_ff == {1'b0, slot1_rf_raddr_rs2}));
    assign issue_wait_block =
        (issue_wait_rs1_ff & !issue_wait_rs1_ready) |
        (issue_wait_rs2_ff & !issue_wait_rs2_ready) |
        slot0_rs1_phys_block |
        slot0_rs2_phys_block |
        rs1_issue_alu_ready_next_i |
        rs2_issue_alu_ready_next_i;
    assign issue_slot0_fire =
        issue_valid_ff & id_advance & !issue_wait_block;
    assign issue_slot1_bypass_fire =
        ready_issue_allow_i & issue_valid_ff & issue_wait_block &
	        !stall_id_i & !flush_id_i & ri_slot1_ready &
	        slot1_bypass_rs1_phys_ready & slot1_bypass_rs2_phys_ready &
	        !((pipe1_uopq1_safe | pipe1_uopq2_safe | pipe1_uopq3_safe) &&
	          !pipe1_resbuf_full_i);
    assign issue_fire = issue_slot0_fire | issue_slot1_bypass_fire;
    assign issue_accept =
        id_advance & decode_valid & (!issue_valid_ff | issue_slot0_fire);
    assign issue_load_from_skid = issue_accept & skid_valid_ff;
    assign issue_load_from_uopq2 = issue_accept & !skid_valid_ff & uopq2_buf_valid_ff;
    assign skid_fill =
        id_advance && issue_valid_ff && issue_wait_block &&
        !skid_valid_ff && !uopq2_buf_valid_ff && if_id_valid_i;
    assign uopq2_buf_capture_supported =
        if_id_valid_i &&
        if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        if_id_trace_rf_wen_rd && (if_id_trace_rf_waddr_rd != '0) &&
        (((if_id_trace_operator[ydrasil_pkg::OP_ALU_ADD] |
           if_id_trace_operator[ydrasil_pkg::OP_ALU_SUB] |
           if_id_trace_operator[ydrasil_pkg::OP_ALU_SLT] |
           if_id_trace_operator[ydrasil_pkg::OP_ALU_SLTU]) &&
          if_id_trace_rf_ren_rs1 && (if_id_trace_rf_raddr_rs1 != '0) &&
          (!if_id_trace_operand_b_rs_sel || if_id_trace_rf_ren_rs2)) |
         ((if_id_trace_operator[ydrasil_pkg::OP_ALU_XOR] |
           if_id_trace_operator[ydrasil_pkg::OP_ALU_OR] |
           if_id_trace_operator[ydrasil_pkg::OP_ALU_AND]) &&
          if_id_trace_rf_ren_rs1 && (if_id_trace_rf_raddr_rs1 != '0) &&
          (!if_id_trace_operand_b_rs_sel || if_id_trace_rf_ren_rs2)));
    assign uopq2_buf_capture_operands_ready =
        uopq2_buf_capture_supported &&
        (!if_id_trace_rf_ren_rs1 || (if_id_trace_rf_raddr_rs1 == '0) ||
	         rn_if_rs1_ready_i ||
         (alu_fwd_valid_i && (if_id_trace_rf_raddr_rs1 == alu_fwd_addr_i) &&
          (rn_if_rs1_psrc_i == alu_fwd_pdst_i)) ||
         (wb_fwd_valid_i && (if_id_trace_rf_raddr_rs1 == wb_fwd_addr_i) &&
          (rn_if_rs1_psrc_i == {1'b0, if_id_trace_rf_raddr_rs1})) ||
         (pipe1_alu_fwd_valid_i && (if_id_trace_rf_raddr_rs1 == pipe1_alu_fwd_addr_i) &&
          (rn_if_rs1_psrc_i == pipe1_alu_fwd_pdst_i))) &&
        (!if_id_trace_rf_ren_rs2 || (if_id_trace_rf_raddr_rs2 == '0) ||
         rn_if_rs2_ready_i ||
         (alu_fwd_valid_i && (if_id_trace_rf_raddr_rs2 == alu_fwd_addr_i) &&
          (rn_if_rs2_psrc_i == alu_fwd_pdst_i)) ||
         (wb_fwd_valid_i && (if_id_trace_rf_raddr_rs2 == wb_fwd_addr_i) &&
          (rn_if_rs2_psrc_i == {1'b0, if_id_trace_rf_raddr_rs2})) ||
         (pipe1_alu_fwd_valid_i && (if_id_trace_rf_raddr_rs2 == pipe1_alu_fwd_addr_i) &&
          (rn_if_rs2_psrc_i == pipe1_alu_fwd_pdst_i)));
	    assign uopq2_buf_capture =
	        !flush_id_i &&
	        id_advance && issue_valid_ff && issue_wait_block &&
	        skid_valid_ff && !uopq2_buf_valid_ff &&
	        !issue_slot1_bypass_fire && !pair1_fire &&
	        uopq2_buf_capture_supported;
	    assign uopq3_buf_capture =
	        !flush_id_i &&
	        id_advance && issue_valid_ff && issue_wait_block &&
	        skid_valid_ff && uopq2_buf_valid_ff && !uopq3_buf_valid_ff &&
	        !issue_slot1_bypass_fire && !pair1_fire &&
	        uopq2_buf_capture_supported;
    assign skid_drain = issue_accept & skid_valid_ff;
    assign pipe1_refill_skid_from_if =
        pair1_fire &&
        !pair1_refill_direct && !pipe1_fire_from2 &&
        !uopq2_buf_valid_ff && !pipe1_p0_empty_base && if_id_valid_i;
	    assign uopq2_refill_from_if =
	        pipe1_fire_from2 &&
	        !uopq3_buf_valid_ff && uopq2_buf_capture_supported;
    assign pipe1_take_if_id =
        1'b0;
    assign if_id_live_accept =
        if_id_valid_i && !flush_id_i &&
        ((issue_accept && !skid_valid_ff && !uopq2_buf_valid_ff) ||
	         (issue_load_from_skid && !uopq2_buf_valid_ff &&
	          !(pipe1_p0_empty_base && pair1_fire)) ||
	         skid_fill ||
	         uopq2_buf_capture ||
	         uopq3_buf_capture ||
	         uopq2_refill_from_if ||
         pipe1_refill_skid_from_if ||
         pipe1_take_if_id);
    assign issue_frontend_stall_o =
        (!flush_id_i & !stall_id_i & !bubble_id_i &
	         issue_valid_ff & issue_wait_block & skid_valid_ff &
	         !(pair1_fire | uopq2_buf_capture | uopq3_buf_capture)) |
        (!flush_id_i & !stall_id_i & !bubble_id_i &
         if_id_valid_i & !if_id_live_accept);
    assign if_id_rn_pdst_valid =
        if_id_valid_i &&
        (if_id_trace_rf_waddr_rd != '0) &&
        (if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         (if_id_trace_rf_wen_rd &&
          !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS]));
    assign rn_alloc_valid_o =
        (if_id_rn_pdst_valid |
         (if_id_valid_i && if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP])) &&
        if_id_live_accept;

    assign pipe1_pipe0_present_safe =
        uopq0_valid &&
        (uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] |
         uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL]) &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        !uopq0_fence_i;
    assign pipe1_pipe0_empty_safe =
        !uopq0_valid;
    assign pipe1_pipe0_blocked_load_safe =
        issue_valid_ff && issue_wait_block &&
        (skid_valid_ff || uopq2_buf_valid_ff) &&
        !stall_id_i && !flush_id_i &&
        uopq0_valid &&
        uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        !uopq0_fence_i;
    assign pipe1_pipe0_blocked_store_safe =
        issue_valid_ff && issue_wait_block &&
        (skid_valid_ff || uopq2_buf_valid_ff) &&
        !stall_id_i && !flush_id_i &&
        uopq0_valid &&
        uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        !uopq0_fence_i;
    assign pipe1_dual_pipe0_safe =
        pipe1_pipe0_present_safe | pipe1_pipe0_empty_safe |
        pipe1_pipe0_blocked_load_safe | pipe1_pipe0_blocked_store_safe;
    assign pipe1_uopq1_supported =
        uopq1_valid &&
        uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
	        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
	        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
	        uopq1_rf_wen_rd && (uopq1_rf_waddr_rd != '0) &&
	        (((uopq1_operator[ydrasil_pkg::OP_ALU_ADD] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_SUB] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_SLT] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_SLTU] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_SLL] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_SRL] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_SRA]) &&
	          uopq1_rf_ren_rs1 && (uopq1_rf_raddr_rs1 != '0) &&
	          (!uopq1_operand_b_rs_sel || uopq1_rf_ren_rs2)) |
	         ((uopq1_operator[ydrasil_pkg::OP_ALU_XOR] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_OR] |
	           uopq1_operator[ydrasil_pkg::OP_ALU_AND]) &&
	          uopq1_rf_ren_rs1 && (uopq1_rf_raddr_rs1 != '0) &&
	          (!uopq1_operand_b_rs_sel || uopq1_rf_ren_rs2)));
	    assign pipe1_uopq2_supported =
	        uopq2_valid &&
	        uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
	        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
	        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
	        uopq2_rf_wen_rd && (uopq2_rf_waddr_rd != '0) &&
	        (((uopq2_operator[ydrasil_pkg::OP_ALU_ADD] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_SUB] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_SLT] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_SLTU] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_SLL] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_SRL] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_SRA]) &&
	          uopq2_rf_ren_rs1 && (uopq2_rf_raddr_rs1 != '0) &&
	          (!uopq2_operand_b_rs_sel || uopq2_rf_ren_rs2)) |
	         ((uopq2_operator[ydrasil_pkg::OP_ALU_XOR] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_OR] |
	           uopq2_operator[ydrasil_pkg::OP_ALU_AND]) &&
		          uopq2_rf_ren_rs1 && (uopq2_rf_raddr_rs1 != '0) &&
		          (!uopq2_operand_b_rs_sel || uopq2_rf_ren_rs2)));
	    assign pipe1_uopq3_supported =
	        uopq3_valid &&
	        uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
	        !uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
	        !uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
	        !uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
	        !uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
	        !uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
	        !uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
	        !uopq3_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
	        uopq3_rf_wen_rd && (uopq3_rf_waddr_rd != '0) &&
	        (((uopq3_operator[ydrasil_pkg::OP_ALU_ADD] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_SUB] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_SLT] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_SLTU] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_SLL] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_SRL] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_SRA]) &&
	          uopq3_rf_ren_rs1 && (uopq3_rf_raddr_rs1 != '0) &&
	          (!uopq3_operand_b_rs_sel || uopq3_rf_ren_rs2)) |
	         ((uopq3_operator[ydrasil_pkg::OP_ALU_XOR] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_OR] |
	           uopq3_operator[ydrasil_pkg::OP_ALU_AND]) &&
	          uopq3_rf_ren_rs1 && (uopq3_rf_raddr_rs1 != '0) &&
	          (!uopq3_operand_b_rs_sel || uopq3_rf_ren_rs2)));
	    assign pipe1_uopq1_operands_ready =
	        pipe1_uopq1_supported &&
	        (!uopq1_rf_ren_rs1 || (uopq1_rf_raddr_rs1 == '0) ||
	         skid_rn_rs1_ready_ff ||
	         rn_preg_ready_i[skid_rn_rs1_psrc_ff] ||
	         (alu_fwd_valid_i && (uopq1_rf_raddr_rs1 == alu_fwd_addr_i) &&
	          (skid_rn_rs1_psrc_ff == alu_fwd_pdst_i)) ||
	         (wb_fwd_valid_i && (uopq1_rf_raddr_rs1 == wb_fwd_addr_i) &&
	          (skid_rn_rs1_psrc_ff == {1'b0, uopq1_rf_raddr_rs1})) ||
	         (pipe1_alu_fwd_valid_i && (uopq1_rf_raddr_rs1 == pipe1_alu_fwd_addr_i) &&
	          (skid_rn_rs1_psrc_ff == pipe1_alu_fwd_pdst_i))) &&
	        (!uopq1_rf_ren_rs2 || (uopq1_rf_raddr_rs2 == '0) ||
	         skid_rn_rs2_ready_ff ||
	         rn_preg_ready_i[skid_rn_rs2_psrc_ff] ||
	         (alu_fwd_valid_i && (uopq1_rf_raddr_rs2 == alu_fwd_addr_i) &&
	          (skid_rn_rs2_psrc_ff == alu_fwd_pdst_i)) ||
	         (wb_fwd_valid_i && (uopq1_rf_raddr_rs2 == wb_fwd_addr_i) &&
	          (skid_rn_rs2_psrc_ff == {1'b0, uopq1_rf_raddr_rs2})) ||
	         (pipe1_alu_fwd_valid_i && (uopq1_rf_raddr_rs2 == pipe1_alu_fwd_addr_i) &&
	          (skid_rn_rs2_psrc_ff == pipe1_alu_fwd_pdst_i)));
	    assign pipe1_uopq2_operands_ready =
	        pipe1_uopq2_supported &&
        (!uopq2_rf_ren_rs1 || (uopq2_rf_raddr_rs1 == '0) ||
         uopq2_buf_rs1_ready_ff ||
         rn_preg_ready_i[uopq2_buf_rn_rs1_psrc_ff] ||
         (alu_fwd_valid_i && (uopq2_rf_raddr_rs1 == alu_fwd_addr_i) &&
          (uopq2_buf_rn_rs1_psrc_ff == alu_fwd_pdst_i)) ||
         (wb_fwd_valid_i && (uopq2_rf_raddr_rs1 == wb_fwd_addr_i) &&
          (uopq2_buf_rn_rs1_psrc_ff == {1'b0, uopq2_rf_raddr_rs1})) ||
         (pipe1_alu_fwd_valid_i && (uopq2_rf_raddr_rs1 == pipe1_alu_fwd_addr_i) &&
          (uopq2_buf_rn_rs1_psrc_ff == pipe1_alu_fwd_pdst_i))) &&
        (!uopq2_rf_ren_rs2 || (uopq2_rf_raddr_rs2 == '0) ||
         uopq2_buf_rs2_ready_ff ||
         rn_preg_ready_i[uopq2_buf_rn_rs2_psrc_ff] ||
	         (alu_fwd_valid_i && (uopq2_rf_raddr_rs2 == alu_fwd_addr_i) &&
	          (uopq2_buf_rn_rs2_psrc_ff == alu_fwd_pdst_i)) ||
	         (wb_fwd_valid_i && (uopq2_rf_raddr_rs2 == wb_fwd_addr_i) &&
	          (uopq2_buf_rn_rs2_psrc_ff == {1'b0, uopq2_rf_raddr_rs2})) ||
	         (pipe1_alu_fwd_valid_i && (uopq2_rf_raddr_rs2 == pipe1_alu_fwd_addr_i) &&
	          (uopq2_buf_rn_rs2_psrc_ff == pipe1_alu_fwd_pdst_i)));
	    assign pipe1_uopq3_operands_ready =
	        pipe1_uopq3_supported &&
	        (!uopq3_rf_ren_rs1 || (uopq3_rf_raddr_rs1 == '0) ||
	         uopq3_buf_rs1_ready_ff ||
	         rn_preg_ready_i[uopq3_buf_rn_rs1_psrc_ff] ||
	         (alu_fwd_valid_i && (uopq3_rf_raddr_rs1 == alu_fwd_addr_i) &&
	          (uopq3_buf_rn_rs1_psrc_ff == alu_fwd_pdst_i)) ||
	         (wb_fwd_valid_i && (uopq3_rf_raddr_rs1 == wb_fwd_addr_i) &&
	          (uopq3_buf_rn_rs1_psrc_ff == {1'b0, uopq3_rf_raddr_rs1})) ||
	         (pipe1_alu_fwd_valid_i && (uopq3_rf_raddr_rs1 == pipe1_alu_fwd_addr_i) &&
	          (uopq3_buf_rn_rs1_psrc_ff == pipe1_alu_fwd_pdst_i))) &&
	        (!uopq3_rf_ren_rs2 || (uopq3_rf_raddr_rs2 == '0) ||
	         uopq3_buf_rs2_ready_ff ||
	         rn_preg_ready_i[uopq3_buf_rn_rs2_psrc_ff] ||
	         (alu_fwd_valid_i && (uopq3_rf_raddr_rs2 == alu_fwd_addr_i) &&
	          (uopq3_buf_rn_rs2_psrc_ff == alu_fwd_pdst_i)) ||
	         (wb_fwd_valid_i && (uopq3_rf_raddr_rs2 == wb_fwd_addr_i) &&
	          (uopq3_buf_rn_rs2_psrc_ff == {1'b0, uopq3_rf_raddr_rs2})) ||
	         (pipe1_alu_fwd_valid_i && (uopq3_rf_raddr_rs2 == pipe1_alu_fwd_addr_i) &&
	          (uopq3_buf_rn_rs2_psrc_ff == pipe1_alu_fwd_pdst_i)));
	    assign pipe1_uopq1_store_war_pipe0 =
	        1'b0;
	    assign pipe1_uopq2_store_war_pipe0 =
	        1'b0;
	    assign pipe1_uopq3_store_war_pipe0 =
	        1'b0;
    assign pipe1_uopq1_safe =
        pipe1_dual_pipe0_safe && pipe1_uopq1_supported &&
        skid_rn_pdst_valid_ff;
    assign pipe1_uopq1_order_safe =
        !uopq1_valid ||
        ((uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] |
          uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL]) &&
         !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
         !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
         !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
         !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
         !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
         !uopq1_fence_i);
    wire pipe1_uopq2_order_safe =
        !uopq2_valid ||
        (uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
         !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
         !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
         !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
         !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
         !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
         !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
         !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
         !uopq2_fence_i);
	    assign pipe1_uopq2_safe =
	        pipe1_dual_pipe0_safe && pipe1_uopq2_supported &&
        pipe1_uopq1_order_safe &&
	        uopq2_buf_rn_pdst_valid_ff;
	    assign pipe1_uopq3_safe =
	        pipe1_dual_pipe0_safe && pipe1_uopq3_supported &&
	        pipe1_uopq1_order_safe &&
	        pipe1_uopq2_order_safe &&
	        uopq3_buf_rn_pdst_valid_ff;
    assign pipe1_younger_flush_risk =
        (uopq2_valid &&
         (uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] |
          uopq2_fence_i)) |
        (if_id_valid_i &&
         (if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] |
          id_fence_i));
    assign pipe1_younger_flush_block =
        (uopq2_valid &&
         (uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] |
          uopq2_fence_i)) |
        (if_id_valid_i &&
         (if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          (if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
           !pipe1_p0_empty_context) |
          id_fence_i));
	    wire pipe1_uopq2_ready_candidate =
	        pipe1_uopq2_safe && !issue_load_from_uopq2 && pipe1_uopq2_operands_ready;
	    wire pipe1_uopq3_ready_candidate =
	        pipe1_uopq3_safe && pipe1_uopq3_operands_ready;
	    assign pipe1_sel_from1 =
	        pipe1_uopq1_safe &&
	        (pipe1_uopq1_operands_ready ||
	         (!pipe1_uopq2_ready_candidate && !pipe1_uopq3_ready_candidate));
	    assign pipe1_sel_from2 =
	        (!pipe1_uopq1_safe || !pipe1_uopq1_operands_ready) &&
	        pipe1_uopq2_safe && !issue_load_from_uopq2 &&
	        (pipe1_uopq2_operands_ready ||
	         (!pipe1_uopq1_safe && !pipe1_uopq3_ready_candidate));
	    assign pipe1_sel_from3 =
	        (!pipe1_uopq1_safe || !pipe1_uopq1_operands_ready) &&
	        !pipe1_uopq2_ready_candidate &&
	        pipe1_uopq3_ready_candidate;
	    assign pipe1_sel_pc = pipe1_sel_from3 ? uopq3_pc : pipe1_sel_from2 ? uopq2_pc : uopq1_pc;
	    assign pipe1_sel_instr = pipe1_sel_from3 ? uopq3_instr : pipe1_sel_from2 ? uopq2_instr : uopq1_instr;
	    assign pipe1_sel_rf_raddr_rs1 = pipe1_sel_from3 ? uopq3_rf_raddr_rs1 : pipe1_sel_from2 ? uopq2_rf_raddr_rs1 : uopq1_rf_raddr_rs1;
	    assign pipe1_sel_rf_raddr_rs2 = pipe1_sel_from3 ? uopq3_rf_raddr_rs2 : pipe1_sel_from2 ? uopq2_rf_raddr_rs2 : uopq1_rf_raddr_rs2;
	    assign pipe1_sel_rf_ren_rs1 = pipe1_sel_from3 ? uopq3_rf_ren_rs1 : pipe1_sel_from2 ? uopq2_rf_ren_rs1 : uopq1_rf_ren_rs1;
	    assign pipe1_sel_rf_ren_rs2 = pipe1_sel_from3 ? uopq3_rf_ren_rs2 : pipe1_sel_from2 ? uopq2_rf_ren_rs2 : uopq1_rf_ren_rs2;
	    assign pipe1_sel_rf_waddr_rd = pipe1_sel_from3 ? uopq3_rf_waddr_rd : pipe1_sel_from2 ? uopq2_rf_waddr_rd : uopq1_rf_waddr_rd;
	    assign pipe1_sel_rf_wen_rd = pipe1_sel_from3 ? uopq3_rf_wen_rd : pipe1_sel_from2 ? uopq2_rf_wen_rd : uopq1_rf_wen_rd;
	    assign pipe1_sel_rs1_psrc = pipe1_sel_from3 ? uopq3_buf_rn_rs1_psrc_ff : pipe1_sel_from2 ? uopq2_buf_rn_rs1_psrc_ff : skid_rn_rs1_psrc_ff;
	    assign pipe1_sel_rs2_psrc = pipe1_sel_from3 ? uopq3_buf_rn_rs2_psrc_ff : pipe1_sel_from2 ? uopq2_buf_rn_rs2_psrc_ff : skid_rn_rs2_psrc_ff;
	    assign pipe1_sel_pdst = pipe1_sel_from3 ? uopq3_buf_rn_pdst_ff : pipe1_sel_from2 ? uopq2_buf_rn_pdst_ff : skid_rn_pdst_ff;
	    assign pipe1_sel_pdst_valid = pipe1_sel_from3 ? uopq3_buf_rn_pdst_valid_ff : pipe1_sel_from2 ? uopq2_buf_rn_pdst_valid_ff : skid_rn_pdst_valid_ff;
	    assign pipe1_sel_imm = pipe1_sel_from3 ? uopq3_imm : pipe1_sel_from2 ? uopq2_imm : uopq1_imm;
    assign pipe1_sel_operand_b_rs_sel =
	        pipe1_sel_from3 ? uopq3_operand_b_rs_sel : pipe1_sel_from2 ? uopq2_operand_b_rs_sel : uopq1_operand_b_rs_sel;
    assign pipe1_sel_operand_a_pc_sel =
	        pipe1_sel_from3 ? uopq3_operand_a_pc_sel : pipe1_sel_from2 ? uopq2_operand_a_pc_sel : uopq1_operand_a_pc_sel;
    assign pipe1_sel_operand_a_imm_sel =
	        pipe1_sel_from3 ? uopq3_operand_a_imm_sel : pipe1_sel_from2 ? uopq2_operand_a_imm_sel : uopq1_operand_a_imm_sel;
    assign pipe1_sel_operand_b_jump_sel =
	        pipe1_sel_from3 ? uopq3_operand_b_jump_sel : pipe1_sel_from2 ? uopq2_operand_b_jump_sel : uopq1_operand_b_jump_sel;
	    assign pipe1_sel_operator = pipe1_sel_from3 ? uopq3_operator : pipe1_sel_from2 ? uopq2_operator : uopq1_operator;
	    assign pipe1_sel_operator_type =
	        pipe1_sel_from3 ? uopq3_operator_type : pipe1_sel_from2 ? uopq2_operator_type : uopq1_operator_type;
	    assign pipe1_dual_supported =
	        (pipe1_sel_from1 && pipe1_uopq1_supported) ||
	        (pipe1_sel_from2 && pipe1_uopq2_supported) ||
	        (pipe1_sel_from3 && pipe1_uopq3_supported);
    assign pipe1_dual_rs1_alu_fwd =
        alu_fwd_valid_i && pipe1_sel_rf_ren_rs1 &&
        (pipe1_sel_rf_raddr_rs1 != '0) &&
        (pipe1_sel_rf_raddr_rs1 == alu_fwd_addr_i) &&
        (pipe1_sel_rs1_psrc == alu_fwd_pdst_i);
    assign pipe1_dual_rs2_alu_fwd =
        alu_fwd_valid_i && pipe1_sel_rf_ren_rs2 &&
        (pipe1_sel_rf_raddr_rs2 != '0) &&
        (pipe1_sel_rf_raddr_rs2 == alu_fwd_addr_i) &&
        (pipe1_sel_rs2_psrc == alu_fwd_pdst_i);
    assign pipe1_dual_rs1_wb_fwd =
        wb_fwd_valid_i && pipe1_sel_rf_ren_rs1 &&
        (pipe1_sel_rf_raddr_rs1 != '0) &&
        (pipe1_sel_rs1_psrc == {1'b0, pipe1_sel_rf_raddr_rs1}) &&
        !pipe1_prf_rs1_uncommitted_i &&
        (pipe1_sel_rf_raddr_rs1 == wb_fwd_addr_i);
    assign pipe1_dual_rs2_wb_fwd =
        wb_fwd_valid_i && pipe1_sel_rf_ren_rs2 &&
        (pipe1_sel_rf_raddr_rs2 != '0) &&
        (pipe1_sel_rs2_psrc == {1'b0, pipe1_sel_rf_raddr_rs2}) &&
        !pipe1_prf_rs2_uncommitted_i &&
        (pipe1_sel_rf_raddr_rs2 == wb_fwd_addr_i);
    assign pipe1_dual_rs1_p1alu_fwd =
        pipe1_alu_fwd_valid_i && pipe1_sel_rf_ren_rs1 &&
        (pipe1_sel_rf_raddr_rs1 != '0) &&
        (pipe1_sel_rf_raddr_rs1 == pipe1_alu_fwd_addr_i) &&
        (pipe1_sel_rs1_psrc == pipe1_alu_fwd_pdst_i);
    assign pipe1_dual_rs2_p1alu_fwd =
        pipe1_alu_fwd_valid_i && pipe1_sel_rf_ren_rs2 &&
        (pipe1_sel_rf_raddr_rs2 != '0) &&
        (pipe1_sel_rf_raddr_rs2 == pipe1_alu_fwd_addr_i) &&
        (pipe1_sel_rs2_psrc == pipe1_alu_fwd_pdst_i);
    assign pipe1_dual_rs1_ready =
        !pipe1_sel_rf_ren_rs1 || (pipe1_sel_rf_raddr_rs1 == '0) ||
        pipe1_prf_rs1_ready_i;
    assign pipe1_dual_rs2_ready =
        !pipe1_sel_rf_ren_rs2 || (pipe1_sel_rf_raddr_rs2 == '0) ||
        pipe1_prf_rs2_ready_i;
    assign pipe1_dual_operands_ready =
        pipe1_dual_supported && pipe1_dual_rs1_ready && pipe1_dual_rs2_ready;
	    wire pipe1_prf_rs1_allowed =
	        pipe1_sel_rf_ren_rs1 &&
	        (pipe1_sel_rf_raddr_rs1 != '0) &&
	        (pipe1_sel_rs1_psrc != '0) &&
	        (pipe1_prf_rs1_uncommitted_i || (pipe1_sel_rs1_psrc != {1'b0, pipe1_sel_rf_raddr_rs1})) &&
	        (pipe1_sel_rs1_psrc != pipe1_sel_pdst);
	    wire pipe1_prf_rs2_allowed =
	        pipe1_sel_rf_ren_rs2 &&
	        (pipe1_sel_rf_raddr_rs2 != '0) &&
	        (pipe1_sel_rs2_psrc != '0) &&
	        (pipe1_prf_rs2_uncommitted_i || (pipe1_sel_rs2_psrc != {1'b0, pipe1_sel_rf_raddr_rs2})) &&
	        (pipe1_sel_rs2_psrc != pipe1_sel_pdst);
    assign pipe1_dual_rs1_data =
        (pipe1_prf_rs1_allowed && pipe1_prf_rs1_ready_i) ? pipe1_prf_rs1_data_i :
        pipe1_dual_rs1_alu_fwd ? alu_fwd_data_i :
        pipe1_dual_rs1_p1alu_fwd ? pipe1_alu_fwd_data_i :
        pipe1_dual_rs1_wb_fwd  ? wb_fwd_data_i  :
        pipe1_rf_rdata_rs1_i;
    assign pipe1_dual_rs2_data =
        (pipe1_prf_rs2_allowed && pipe1_prf_rs2_ready_i) ? pipe1_prf_rs2_data_i :
        pipe1_dual_rs2_alu_fwd ? alu_fwd_data_i :
        pipe1_dual_rs2_p1alu_fwd ? pipe1_alu_fwd_data_i :
        pipe1_dual_rs2_wb_fwd  ? wb_fwd_data_i  :
        pipe1_rf_rdata_rs2_i;
    assign pipe1_dual_operand_a =
        (pipe1_sel_operand_a_pc_sel | pipe1_sel_operator[ydrasil_pkg::OP_ALU_AUIPC]) ? pipe1_sel_pc :
        pipe1_sel_operand_a_imm_sel ? pipe1_sel_imm : pipe1_dual_rs1_data;
    assign pipe1_dual_operand_b =
        pipe1_sel_operand_b_jump_sel ? 32'h4 :
        pipe1_sel_operand_b_rs_sel ? pipe1_dual_rs2_data : pipe1_sel_imm;
    assign pair1_refill_dep_p1 =
        if_id_valid_i && slot1_rf_wen_rd && (slot1_rf_waddr_rd != '0) &&
        ((if_id_trace_rf_ren_rs1 && (if_id_trace_rf_raddr_rs1 == slot1_rf_waddr_rd)) |
         (if_id_trace_rf_ren_rs2 && (if_id_trace_rf_raddr_rs2 == slot1_rf_waddr_rd)) |
         (if_id_trace_rf_wen_rd && (if_id_trace_rf_waddr_rd == slot1_rf_waddr_rd)));
    assign pair1_refill_dep_p0 =
        if_id_valid_i && issue_rf_wen_rd_ff && (issue_rf_waddr_rd_ff != '0) &&
        ((if_id_trace_rf_ren_rs1 && (if_id_trace_rf_raddr_rs1 == issue_rf_waddr_rd_ff)) |
         (if_id_trace_rf_ren_rs2 && (if_id_trace_rf_raddr_rs2 == issue_rf_waddr_rd_ff)) |
         (if_id_trace_rf_wen_rd && (if_id_trace_rf_waddr_rd == issue_rf_waddr_rd_ff)));
	    assign pair1_refill_srcs_ready =
	        (!if_id_trace_rf_ren_rs1 || (if_id_trace_rf_raddr_rs1 == '0) ||
	         rn_if_rs1_ready_i) &&
	        (!if_id_trace_rf_ren_rs2 || (if_id_trace_rf_raddr_rs2 == '0) ||
	         rn_if_rs2_ready_i);
    assign pair1_refill_simple_alu =
        if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
    assign pair1_refill_direct =
        1'b0;
	    assign pipe1_dual_raw_pipe0 =
	        1'b0;
	    assign pipe1_dual_waw_pipe0 =
	        1'b0;
	    assign pipe1_dual_war_pipe0 =
	        (pipe1_sel_from1 && pipe1_uopq1_store_war_pipe0) |
	        (pipe1_sel_from2 && pipe1_uopq2_store_war_pipe0) |
	        (pipe1_sel_from3 && pipe1_uopq3_store_war_pipe0);
    assign pipe1_dual_pending_rd =
        pipe1_dual_supported && !pipe1_sel_pdst_valid;
    assign pipe1_p0_ready_context = issue_slot0_fire;
	    assign pipe1_p0_blocked_context =
	        issue_valid_ff && issue_wait_block &&
	        (skid_valid_ff || pipe1_uopq2_safe || pipe1_uopq3_safe) &&
	        !stall_id_i && !flush_id_i;
	    assign pipe1_p0_empty_base =
	        !issue_valid_ff && skid_valid_ff && !uopq2_buf_valid_ff && !uopq3_buf_valid_ff &&
	        !stall_id_i && !bubble_id_i && !flush_id_i;
    assign pipe1_p0_empty_context =
        pipe1_p0_empty_base;
    assign pipe1_dual_fire =
        (pipe1_p0_ready_context | pipe1_p0_blocked_context | pipe1_p0_empty_context) &&
        ready_issue_allow_i && !flush_id_i &&
        pipe1_dual_pipe0_safe && pipe1_dual_operands_ready &&
        !pipe1_younger_flush_block &&
        !pipe1_dual_raw_pipe0 && !pipe1_dual_waw_pipe0 &&
        !pipe1_dual_war_pipe0 && !pipe1_dual_pending_rd &&
        !pipe1_resbuf_full_i;
    assign pair1_fire = pipe1_dual_fire;
	    assign pipe1_fire_from1 = pair1_fire && pipe1_sel_from1;
	    assign pipe1_fire_from2 = pair1_fire && pipe1_sel_from2;
	    assign pipe1_fire_from3 = pair1_fire && pipe1_sel_from3;

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && pipe1_refill_skid_from_if && if_id_rn_pdst_valid &&
            !rn_alloc_valid_o) begin
            $fatal(1, "pipe1 refill from IF/ID without rename allocation pc=0x%08h instr=0x%08h rd=x%0d",
                   if_id_pc_i, if_id_instr_i, if_id_trace_rf_waddr_rd);
        end
        if (rst_n && pipe1_take_if_id && if_id_rn_pdst_valid &&
            !rn_alloc_valid_o) begin
            $fatal(1, "pipe1 IF/ID issue without rename allocation pc=0x%08h instr=0x%08h rd=x%0d",
                   if_id_pc_i, if_id_instr_i, if_id_trace_rf_waddr_rd);
        end
        if (rst_n && pipe1_fire_from2 && !uopq2_buf_valid_ff) begin
            $fatal(1, "pipe1 from2 fired without held uopq2 entry");
        end
        if (rst_n && pipe1_fire_from2 && !uopq2_buf_rn_pdst_valid_ff) begin
            $fatal(1, "pipe1 from2 fired without held rename destination");
        end
        if (rst_n && pair1_fire && pipe1_p0_empty_context && !pipe1_sel_from1) begin
            $fatal(1, "pipe1 empty-slot0 context selected non-skid entry");
        end
        if (rst_n && pair1_fire && pipe1_p0_empty_context &&
            (if_id_live_accept || rn_alloc_valid_o || pipe1_refill_skid_from_if)) begin
            $fatal(1, "pipe1 empty-slot0 context overlaps new rename allocation");
        end
        if (rst_n && pair1_fire && pipe1_p0_empty_context &&
            !skid_rn_pdst_valid_ff) begin
            $fatal(1, "pipe1 empty-slot0 fire without held rename destination");
        end
	        if (rst_n && pair1_fire && pipe1_sel_from1 &&
	            ((pipe1_sel_rf_ren_rs1 && (pipe1_sel_rf_raddr_rs1 != '0) &&
	              !rn_preg_ready_i[pipe1_sel_rs1_psrc] && !pipe1_dual_rs1_ready) ||
	             (pipe1_sel_rf_ren_rs2 && (pipe1_sel_rf_raddr_rs2 != '0) &&
	              !rn_preg_ready_i[pipe1_sel_rs2_psrc] && !pipe1_dual_rs2_ready))) begin
            $fatal(1, "pipe1 from1 fired with stale skid operand ready pc=0x%08h instr=0x%08h",
                   pipe1_sel_pc, pipe1_sel_instr);
        end
        if (rst_n && pair1_fire && pipe1_pipe0_blocked_store_safe &&
            pipe1_sel_rf_wen_rd && (pipe1_sel_rf_waddr_rd != '0) &&
            ((issue_rf_ren_rs1_ff && (pipe1_sel_rf_waddr_rd == issue_rf_raddr_rs1_ff)) ||
             ((issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
              (pipe1_sel_rf_waddr_rd == issue_rf_raddr_rs2_ff)))) begin
            $fatal(1, "pipe1 bypassed older blocked store with WAR hazard store_pc=0x%08h pipe1_pc=0x%08h rd=x%0d",
                   issue_pc_ff, pipe1_sel_pc, pipe1_sel_rf_waddr_rd);
        end
        if (rst_n && uopq2_buf_capture && !rn_alloc_valid_o) begin
            $fatal(1, "uopq2 capture without rename allocation pc=0x%08h instr=0x%08h rd=x%0d",
                   if_id_pc_i, if_id_instr_i, if_id_trace_rf_waddr_rd);
        end
        if (rst_n && uopq2_refill_from_if && if_id_rn_pdst_valid &&
            !rn_alloc_valid_o) begin
            $fatal(1, "uopq2 refill from IF/ID without rename allocation pc=0x%08h instr=0x%08h rd=x%0d",
                   if_id_pc_i, if_id_instr_i, if_id_trace_rf_waddr_rd);
        end
        if (rst_n && !flush_id_i && !stall_id_i && !bubble_id_i &&
            if_id_valid_i && !if_id_live_accept && !issue_frontend_stall_o) begin
            $fatal(1, "IF/ID live instruction neither accepted nor stalled pc=0x%08h instr=0x%08h skid=%0b uopq2=%0b issue_accept=%0b pair1_fire=%0b",
                   if_id_pc_i, if_id_instr_i, skid_valid_ff, uopq2_buf_valid_ff,
                   issue_accept, pair1_fire);
        end
        if (rst_n && uopq2_buf_valid_ff && !pipe1_fire_from2 && !issue_load_from_uopq2 &&
            !issue_load_from_skid && !pipe1_refill_skid_from_if &&
            !uopq3_buf_capture && rn_alloc_valid_o) begin
            $fatal(1, "rename allocation while held uopq2 is not being drained");
        end
    end
`endif

    assign ri_slot1_valid = skid_valid_ff;
    assign ri_slot1_supported =
        ri_slot1_valid &&
        (slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] |
         slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP]) &&
        !(slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL]);
	    assign ri_slot1_block_raw =
	        1'b0;
	    assign ri_slot1_block_waw =
	        1'b0;
	    assign ri_slot1_block_war =
	        1'b0;
    assign ri_slot1_block_ctrl =
        ri_slot1_valid && issue_valid_ff &&
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP];
    assign ri_slot1_block_mem =
        ri_slot1_valid && issue_valid_ff &&
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign ri_slot1_block_old_unsupported =
        ri_slot1_valid && issue_valid_ff &&
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL]);
    assign ri_slot1_rs1_clear_fwd =
        (wb_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (skid_rn_rs1_psrc_ff == {1'b0, slot1_rf_raddr_rs1}) &
         (slot1_rf_raddr_rs1 == wb_fwd_addr_i)) |
        (lsu_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (skid_rn_rs1_psrc_ff == lsu_fwd_pdst_i) &
         (slot1_rf_raddr_rs1 == lsu_fwd_addr_i)) |
        (alu_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (skid_rn_rs1_psrc_ff == alu_fwd_pdst_i) &
         (slot1_rf_raddr_rs1 == alu_fwd_addr_i)) |
        (pipe1_alu_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (skid_rn_rs1_psrc_ff == pipe1_alu_fwd_pdst_i) &
         (slot1_rf_raddr_rs1 == pipe1_alu_fwd_addr_i));
    assign ri_slot1_rs2_read = slot1_rf_ren_rs2 | slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];
    assign ri_slot1_rs2_clear_fwd =
        (wb_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (skid_rn_rs2_psrc_ff == {1'b0, slot1_rf_raddr_rs2}) &
         (slot1_rf_raddr_rs2 == wb_fwd_addr_i)) |
        (lsu_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (skid_rn_rs2_psrc_ff == lsu_fwd_pdst_i) &
         (slot1_rf_raddr_rs2 == lsu_fwd_addr_i)) |
        (alu_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (skid_rn_rs2_psrc_ff == alu_fwd_pdst_i) &
         (slot1_rf_raddr_rs2 == alu_fwd_addr_i)) |
        (pipe1_alu_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (skid_rn_rs2_psrc_ff == pipe1_alu_fwd_pdst_i) &
         (slot1_rf_raddr_rs2 == pipe1_alu_fwd_addr_i));
    wire ri_slot1_rd_clear_fwd =
        (wb_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == wb_fwd_addr_i)) |
        (lsu_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == lsu_fwd_addr_i)) |
        (alu_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == alu_fwd_addr_i)) |
        (pipe1_alu_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == pipe1_alu_fwd_addr_i));
	    assign ri_slot1_block_rs1_pending =
	        ri_slot1_valid && slot1_rf_ren_rs1 && (slot1_rf_raddr_rs1 != '0) &&
	        !rn_preg_ready_i[skid_rn_rs1_psrc_ff] && !ri_slot1_rs1_clear_fwd;
	    assign ri_slot1_block_rs2_pending =
	        ri_slot1_valid && ri_slot1_rs2_read && (slot1_rf_raddr_rs2 != '0) &&
	        !rn_preg_ready_i[skid_rn_rs2_psrc_ff] && !ri_slot1_rs2_clear_fwd;
	    assign ri_slot1_block_rd_pending =
	        1'b0;
    assign ri_slot1_block_unsupported = ri_slot1_valid && !ri_slot1_supported;
    assign ri_slot1_ready =
        ri_slot1_valid && ri_slot1_supported &&
        !ri_slot1_block_raw && !ri_slot1_block_waw &&
        !ri_slot1_block_war && !ri_slot1_block_ctrl &&
        !ri_slot1_block_mem && !ri_slot1_block_old_unsupported &&
        !ri_slot1_block_rs1_pending && !ri_slot1_block_rs2_pending &&
        !ri_slot1_block_rd_pending;
    assign ri_slot1_ready_when_slot0_blocked =
        ri_slot1_ready && issue_valid_ff && issue_wait_block;
    assign ri_slot1_ready_when_slot0_ready =
        ri_slot1_ready && issue_valid_ff && !issue_wait_block;
    assign ri_slot1_fire_blocked_by_single_issue =
        ri_slot1_ready_when_slot0_ready && id_advance && !stall_id_i && !flush_id_i;
    assign ri_slot1_fire_blocked_by_wb_order =
        1'b0;
    assign ri_bypass_flush_killed =
        ready_issue_allow_i && issue_valid_ff && issue_wait_block && ri_slot1_ready && flush_id_i;

endmodule
