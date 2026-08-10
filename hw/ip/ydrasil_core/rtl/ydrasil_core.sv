

module ydrasil_core
import ydrasil_pkg::*;
import ydrasil_axi_pkg::*;
	 #(
		parameter int BP_ENTRIES  = 0,
		parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
		parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES
	)(
	input  wire clk,
	input  wire rst_n,
	output ydrasil_axi_lite_m2s_pkt_t axi_m2s_o,
	input  ydrasil_axi_lite_s2m_pkt_t axi_s2m_i,
	input  ydrasil_irq_pkt_t          irq_i
`ifdef YDRASIL_RETIRE_TRACE
    ,output wire                       retire0_valid_o
    ,output wire [31:0]                retire0_pc_o
    ,output wire                       retire1_valid_o
    ,output wire [31:0]                retire1_pc_o
`endif
`ifndef SYNTHESIS
    ,output wire [31:0] dbg_bp_predict_pc_o
    ,output wire        dbg_bp_predict_hit_o
    ,output wire        dbg_bp_predict_taken_o
    ,output wire [31:0] dbg_bp_predict_target_o
    ,output wire [1:0]  dbg_bp_predict_counter_o
    ,output wire        dbg_bp_resolve_valid_o
    ,output wire [31:0] dbg_bp_resolve_pc_o
    ,output wire        dbg_bp_actual_taken_o
    ,output wire [31:0] dbg_bp_actual_target_o
    ,output wire [31:0] dbg_bp_actual_next_pc_o
    ,output wire        dbg_bp_pred_hit_o
    ,output wire        dbg_bp_pred_taken_o
    ,output wire [31:0] dbg_bp_pred_target_o
    ,output wire [1:0]  dbg_bp_pred_counter_o
    ,output wire [31:0] dbg_bp_pred_next_pc_o
    ,output wire        dbg_bp_mispredict_o
`endif
);

	// IF <-> MEMS
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr1;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_lookup_pc;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] if_mem_rdata;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] if_mem_rdata1;

	// IF/ID pipeline
	wire [31:0] if_resume_pc;
	wire [31:0] if_id_pc;
	wire [31:0] if_id_instr;
	wire        if_id_pred_hit;
	wire        if_id_pred_taken;
	wire [31:0] if_id_pred_target;
	wire [1:0]  if_id_pred_counter;
	bp_bht_index_t if_id_pred_bht_index;
	wire        if_id_valid;
	wire [31:0] if_id1_pc;
	wire [31:0] if_id1_instr;
	wire        if_id1_pred_hit;
	wire        if_id1_pred_taken;
	wire [31:0] if_id1_pred_target;
	wire [1:0]  if_id1_pred_counter;
	bp_bht_index_t if_id1_pred_bht_index;
	wire        if_id1_valid;
	// CTRL signals
		(* max_fanout = 8 *) wire   stall_if;
		(* max_fanout = 8 *) wire   stall_id;
		(* max_fanout = 8 *) wire   flush_if;
		(* max_fanout = 8 *) wire   flush_id;
		(* max_fanout = 8 *) wire   flush_ex;
		(* max_fanout = 8 *) wire   bubble_id;
	wire                        branch_jump;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] branch_target;

	// ID -> EX
	wire [31:0]                    alu_operand_a;
	wire [31:0]                    alu_operand_b;
	wire [31:0]                    lsu_operand_a;
	wire [31:0]                    lsu_operand_b;
	wire [31:0]                    mul_operand_a;
	wire [31:0]                    mul_operand_b;
	wire [31:0]                    csr_operand_a;
	wire                           alu_in_valid;
	wire [31:0]                    alu_in_operand_a;
	wire [31:0]                    alu_in_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] alu_in_operator;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] alu_in_operator_type;
	wire                           alu_in_rd_wen;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] alu_in_rd_addr;
	producer_id_t                  alu_in_producer_id;
	wire [31:0]                    lane_a_pc;
	wire                           agu_in_valid;
	wire [31:0]                    agu_in_operand_a;
	wire [31:0]                    agu_in_operand_b;
	ydrasil_lsu_req_pkt_t          agu_in_req;
	wire [31:0]                    agu_in_store_data;
	wire                           csr_in_valid;
	wire [31:0]                    csr_in_operand_a;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] csr_in_operator_type;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] csr_in_raddr;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] csr_in_waddr;
	wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] csr_in_op_info;
	wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] csr_in_sys_info;
	wire                           mul_in_valid;
	wire [31:0]                    mul_in_operand_a;
	wire [31:0]                    mul_in_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] mul_in_operator;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] mul_in_operator_type;
	ydrasil_lane_b_meta_t               dual_meta;
	wire                                dual_alu_valid;
	ydrasil_lane_b_alu_payload_t        dual_alu_payload;
	wire [31:0]                         dual_alu_operand_a;
	wire [31:0]                         dual_alu_operand_b;
	wire                                dual_bru_valid;
	ydrasil_lane_b_bru_payload_t        dual_bru_payload;
	wire [31:0]                         dual_bru_operand_a;
	wire [31:0]                         dual_bru_operand_b;
	ydrasil_lsu_req_pkt_t         lsu_req_pkt;
	wire                           illegal_instr_ex;

	// EX outputs
	wire                        ex_branch_jump;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_branch_target;
	wire                        ex_mul_stall;
	wire                        ex_mul_issue;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] ex_mul_issue_waddr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mul_wb_result;
	wire                        mul_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] mul_rf_waddr_rd;
	producer_id_t               mul_producer_id;
	wire                        mul_result_valid;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] slow_wb_result;
	wire                        slow_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] slow_rf_waddr_rd;
	producer_id_t               slow_producer_id;
	wire                        ex_instret_inc;
	wire                        ex_pc_redirect;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_pc_redirect_target;
	ydrasil_bp_train_pkt_t      ex_bp_train_pkt;
	wire                        ex_branch_mispredict;
`ifndef SYNTHESIS
	wire                        dbg_bp_resolve_valid;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] dbg_bp_resolve_pc;
	wire                        dbg_bp_actual_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] dbg_bp_actual_target;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] dbg_bp_actual_next_pc;
	wire                        dbg_bp_pred_hit;
	wire                        dbg_bp_pred_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] dbg_bp_pred_target;
	wire [1:0]                  dbg_bp_pred_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] dbg_bp_pred_next_pc;
	wire                        dbg_bp_mispredict;
`endif

	// Raw BRAM predictor outputs are captured by the IF response boundary.
	wire                        bp_bram_predict_hit;
	wire                        bp_bram_predict_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict_target;
	wire [1:0]                  bp_bram_predict_counter;
	bp_bht_index_t              bp_bram_predict_bht_index;
	wire                        bp_bram_predict1_hit;
	wire                        bp_bram_predict1_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict1_target;
	wire [1:0]                  bp_bram_predict1_counter;
	bp_bht_index_t              bp_bram_predict1_bht_index;
		// Compatibility observability now reflects the FF target table.
		wire l0_hit;
		wire l0_hit1;
	wire                        id_fence_i;
	wire [31:0]                 fence_resume_pc;
	producer_id_t               issue_fence_tag;
	wire [31:0]                 issue_fence_next_pc;
		(* max_fanout = 8 *) wire   pipeline_flush;
	wire                        id_ex_valid;

	// LSU request path
	ydrasil_dtcm_req_pkt_t      dtcm_req_pkt;
	ydrasil_mem_req_pkt_t       mmio_req_pkt;
	ydrasil_mem_rsp_pkt_t       mmio_rsp_pkt;
	ydrasil_lsu_status_pkt_t    lsu_status_pkt;
	wire [1:0]                  lsu_issue_credit;
	wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]  dtcm_rdata;
	// DV observes these protocol fields hierarchically. Keep them out of the
	// synthesis cone; the LSU request packet is the architectural interface.
`ifndef SYNTHESIS
	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]  dtcm_addr;
	wire                        dtcm_we;
	wire                        dtcm_req;
	wire [3:0]                  dtcm_wmask;
	wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]  mmio_wdata;
	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]  mmio_addr;
	wire                        mmio_we;
	wire                        mmio_req;
	wire [3:0]                  mmio_wmask;
`endif

	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] lsu_wb_result;
	wire                        lsu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_rf_waddr_rd;
	producer_id_t               lsu_producer_id;
	wire                        lsu_producer_tracked;

	// Kept as a constant for DV's hierarchical stall accounting.  Architectural
	// GPR writes are generated by the two-wide retirement packets below.
	wire                        wb_backpressure;

	ydrasil_commit_pkt_t         commit_pkt;
	ydrasil_commit_pkt_t         commit_pkt1;
    //LSU -> CTRL
	wire                            lsu_ctrl_busy;
	wire                            lsu_fast_load;

	// LSU -> ID compatibility probes are derived from the compact Issue head.
	ydrasil_ex_hzd_pkt_t            ex_hzd_pkt;
	ydrasil_ex_hzd_pkt_t            ex_hzd_pkt1;
	ydrasil_gpr_fwd_pkt_t           lsu_fwd_pkt;
	ydrasil_reservation_pkt_t       dtcm_reservation;
	wire [REGS_DATA_WIDTH-1:0]      dtcm_resp_data;
	ydrasil_gpr_fwd_pkt_t           lsu_wb_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           alu_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           mul_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           dual_alu_fwd_pkt;
	ydrasil_completion_bus_t        completion_bus;
	ydrasil_completion_meta_t       completion_meta [COMPLETION_LANES];
	wire [REGS_DATA_WIDTH-1:0]      completion_data [COMPLETION_LANES];
	wire [REGS_ADDR_WIDTH-1:0]      completion_rd [COMPLETION_LANES];
	wire                            alu_completion_valid;
	producer_id_t                   alu_completion_producer_id;
	wire                            alu_completion_producer_tracked;
	wire [REGS_ADDR_WIDTH-1:0]      alu_completion_addr;
	wire [REGS_DATA_WIDTH-1:0]      alu_completion_data;
	wire                            lsu_completion_valid;
	producer_id_t                   lsu_completion_producer_id;
	wire                            lsu_completion_producer_tracked;
	wire [REGS_ADDR_WIDTH-1:0]      lsu_completion_addr;
	wire [REGS_DATA_WIDTH-1:0]      lsu_completion_data;
	wire                            dual_completion_valid;
	producer_id_t                   dual_completion_producer_id;
	wire                            dual_completion_producer_tracked;
	wire [REGS_ADDR_WIDTH-1:0]      dual_completion_addr;
	wire [REGS_DATA_WIDTH-1:0]      dual_completion_data;
	producer_slot_t                 retire_value_slot0;
	producer_slot_t                 retire_value_slot1;
	wire [REGS_DATA_WIDTH-1:0]      retire_value0;
	wire [REGS_DATA_WIDTH-1:0]      retire_value1;
	producer_id_t                   rob_head_id;
	wire [ydrasil_pkg::PRODUCER_NUM-1:0] producer_valid;
	wire [ydrasil_pkg::PRODUCER_NUM-1:0] producer_ready;
	wire [ydrasil_pkg::PRODUCER_NUM-1:0] producer_epoch;
	wire [ydrasil_pkg::PRODUCER_NUM-1:0]
	                                branch_recovery_keep_mask;
	wire [ydrasil_pkg::PRODUCER_NUM-1:0] lsu_flush_keep_mask =
		branch_recovery_keep_mask |
		(commit_pkt.valid ?
		 (ydrasil_pkg::PRODUCER_NUM'(1) << retire_value_slot0) : '0) |
		(commit_pkt1.valid ?
		 (ydrasil_pkg::PRODUCER_NUM'(1) << retire_value_slot1) : '0);
	ydrasil_id_issue_pkt_t          id_issue_pkt;
	ydrasil_id_issue_pkt_t          id_issue_pkt1;
	ydrasil_issue_pkt_t             dispatch_issue_pkt;
	ydrasil_issue_pkt_t             dispatch_issue_pkt1;
	ydrasil_compact_uop_t           issue_head_compact_uop;
	wire                            issue_consume_two;
	wire                            issue_slot1_replay;
	wire                            issue_scoreboard_stall;
	wire                            issue_scoreboard_stall1;
	wire                            issue_lsu_struct_stall;
	wire                            issue_lsu_struct_stall1;
	wire                            issue_serialize_stall;
	wire                            issue_src0_wait;
	wire                            issue_src1_wait;
	wire                            issue_src2_wait;
	wire                            issue_src3_wait;
	wire                            dispatch_ready;
	wire                            issue_pipe_has_room;
	wire                            issue_pipe_push;
	wire                            issue_pipe_push_two;
	wire                            decode_if_ready;
	wire                            decode_consume_two;
	wire                            id_ex_execute_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs1_addr;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs2_addr;
	wire                            id_ctrl_rs1_ren;
	wire                            id_ctrl_rs2_ren;
	wire                            id_ctrl_rd_wen;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rd_addr;
	wire                            id_ctrl_lsu_req;
	wire                            id_ctrl_store_req;
	wire                            scoreboard_stall;
	wire                            lsu_struct_stall;
	wire                            ex_accept_valid;
	wire                            ex_accept_valid1;
	wire                            id_ex_rd_issue;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_clear_mask;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_issue_mask;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_for_hazard;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_q;
	wire                            retire_pending;
	wire                            rs1_pending_stall;
	wire                            rs2_pending_stall;
	wire                            rd_waw_stall;
	wire                            rs1_issue_hzd;
	wire                            rs2_issue_hzd;
	wire                            rd_issue_hzd;
	wire                            issue_load_producer;
	wire                            issue_alu_producer;
	wire                            issue_mul_div_producer;
	wire                            issue_src_hzd;
	wire                            store_data_wait;


	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_ex_rdata;
	wire 					    ex_csr_wen;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      ex_csr_wdata;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       ex_csr_waddr;

	// Trap control packets.  Compatibility aliases remain visible to the
	// existing coverage testbench while new RTL uses the precise names.
	ydrasil_csr_trap_state_pkt_t trap_csr_state_pkt;
	ydrasil_csr_write_pkt_t      trap_csr_write_pkt;
	ydrasil_trap_ctrl_pkt_t      trap_ctrl_pkt;
	wire                             interrupt;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]      trap_redirect_addr;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]      clint_ex_int_addr;
	wire                             trap_stall;
	wire                             clint_stall;
	wire                             clint_csr_we;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] clint_csr_waddr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] clint_csr_wdata;
	wire                             dual_instret_inc;
	wire [31:0]                      dual_operand_a;
	wire [31:0]                      dual_operand_b;
	wire                             dual_id_ex_valid;
	wire [31:0]                      dual_id_ex_pc;
	wire [31:0]                      dual_id_ex_instr;
	wire [31:0]                      dual_commit_pc;
	wire [31:0]                      dual_commit_instr;

	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0] id_instr_addr;


	ydrasil_completion_ctrl u_completion_ctrl (
		.alu_valid_i       (alu_completion_valid),
		.alu_producer_id_i (alu_completion_producer_id),
		.alu_producer_tracked_i(alu_completion_producer_tracked),
		.alu_addr_i        (alu_completion_addr),
		.alu_data_i        (alu_completion_data),
		.lsu_valid_i       (lsu_completion_valid),
		.lsu_producer_id_i (lsu_completion_producer_id),
		.lsu_producer_tracked_i(lsu_completion_producer_tracked),
		.lsu_addr_i        (lsu_completion_addr),
		.lsu_data_i        (lsu_completion_data),
		.mul_valid_i       (mul_rf_wen_rd),
		.mul_producer_id_i (mul_producer_id),
		.mul_addr_i        (mul_rf_waddr_rd),
		.mul_data_i        (mul_wb_result),
		.dual_valid_i      (dual_completion_valid),
		.dual_producer_id_i(dual_completion_producer_id),
		.dual_producer_tracked_i(dual_completion_producer_tracked),
		.dual_addr_i       (dual_completion_addr),
		.dual_data_i       (dual_completion_data),
		.completion_meta_o (completion_meta),
		.completion_data_o (completion_data),
		.completion_rd_o   (completion_rd)
	);
	ydrasil_load_store_unit u_ydrasil_load_store_unit (
			.clk               (clk),
			.rst_n             (rst_n),
			.flush_i           (flush_ex),
			.flush_keep_mask_i (lsu_flush_keep_mask),
			.req_i             (lsu_req_pkt),
		.completion_meta_i (completion_meta),
		.completion_data_i (completion_data),
		.dtcm_rdata_i      (dtcm_rdata),
		.dtcm_req_o        (dtcm_req_pkt),
		.mmio_rsp_i        (mmio_rsp_pkt),
		.mmio_req_o        (mmio_req_pkt),
		.status_o          (lsu_status_pkt),
		.issue_credit_o     (lsu_issue_credit),
		.dtcm_reservation_o(dtcm_reservation),
		.dtcm_resp_data_o   (dtcm_resp_data),
		.completion_valid_o (lsu_completion_valid),
		.completion_data_o  (lsu_completion_data),
		.completion_addr_o  (lsu_completion_addr),
		.completion_producer_id_o(lsu_completion_producer_id),
		.completion_producer_tracked_o(lsu_completion_producer_tracked)
	);

	ydrasil_axi_lite_master u_ydrasil_axi_lite_master (
		.clk         (clk),
		.rst_n       (rst_n),
		.req_valid_i (mmio_req_pkt.valid),
		.req_write_i (mmio_req_pkt.write),
		.req_addr_i  (mmio_req_pkt.addr),
		.req_wdata_i (mmio_req_pkt.wdata),
		.req_wstrb_i (mmio_req_pkt.wmask),
		.rsp_valid_o (mmio_rsp_pkt.valid),
		.rsp_rdata_o (mmio_rsp_pkt.rdata),
		.rsp_error_o (mmio_rsp_pkt.error),
		.axi_m2s_o   (axi_m2s_o),
		.axi_s2m_i   (axi_s2m_i)
	);

		ydrasil_branch_predictor #(
			.BP_ENTRIES(BP_ENTRIES),
			.BTB_ENTRIES(BTB_ENTRIES),
			.BHT_ENTRIES(BHT_ENTRIES)
		) u_ydrasil_branch_predictor (
			.clk              (clk),
			.rst_n            (rst_n),
			.predict_pc_i     (bp_lookup_pc),
			.predict_hit_o    (bp_bram_predict_hit),
			.predict_taken_o  (bp_bram_predict_taken),
			.predict_target_o (bp_bram_predict_target),
			.predict_counter_o(bp_bram_predict_counter),
			.predict_bht_index_o(bp_bram_predict_bht_index),
			.predict_pc1_i    (if_mem_addr1),
			.predict1_hit_o   (bp_bram_predict1_hit),
			.predict1_taken_o (bp_bram_predict1_taken),
			.predict1_target_o(bp_bram_predict1_target),
			.predict1_counter_o(bp_bram_predict1_counter),
			.predict1_bht_index_o(bp_bram_predict1_bht_index),
			.train_i          (ex_bp_train_pkt),
			.invalidate_i     (id_fence_i)
		);

		ydrasil_if_stage #(
			.FETCHQ_DEPTH(10),
			.BHT_ENTRIES(BHT_ENTRIES)
		) u_ydrasil_if_stage (
			.clk           (clk),
			.rst_n         (rst_n),
				.decode_ready_i  (decode_if_ready),
			.flush_if_i      (flush_if),
			.consume_two_i   (decode_consume_two),
			.branch_jump_i   (branch_jump),
			.branch_target_i (branch_target),
				.bp_predict_hit_i(bp_bram_predict_hit),
				.bp_predict_taken_i(bp_bram_predict_taken),
				.bp_predict_target_i(bp_bram_predict_target),
				.bp_predict_counter_i(bp_bram_predict_counter),
				.bp_predict_bht_index_i(bp_bram_predict_bht_index),
				.bp_predict1_hit_i(bp_bram_predict1_hit),
				.bp_predict1_taken_i(bp_bram_predict1_taken),
				.bp_predict1_target_i(bp_bram_predict1_target),
				.bp_predict1_counter_i(bp_bram_predict1_counter),
				.bp_predict1_bht_index_i(bp_bram_predict1_bht_index),
			.bp_invalidate_i(id_fence_i),
				.bp_invalidate_target_i(issue_fence_next_pc),
			.target_ff_train_i(ex_bp_train_pkt),
			.if_mem_addr_o   (if_mem_addr),
			.if_mem_addr1_o  (if_mem_addr1),
			.bp_lookup_pc_o   (bp_lookup_pc),
			.if_mem_rdata_i  (if_mem_rdata),
			.if_mem_rdata1_i (if_mem_rdata1),
			.if_resume_pc_o  (if_resume_pc),
			.if_id_pc_o      (if_id_pc),
			.if_id_pred_hit_o(if_id_pred_hit),
			.if_id_pred_taken_o(if_id_pred_taken),
			.if_id_pred_target_o(if_id_pred_target),
			.if_id_pred_counter_o(if_id_pred_counter),
			.if_id_pred_bht_index_o(if_id_pred_bht_index),
			.if_id_valid_o   (if_id_valid),
			.if_id_instr_o   (if_id_instr)
			,.if_id1_pc_o      (if_id1_pc)
			,.if_id1_pred_hit_o(if_id1_pred_hit)
			,.if_id1_pred_taken_o(if_id1_pred_taken)
			,.if_id1_pred_target_o(if_id1_pred_target)
			,.if_id1_pred_counter_o(if_id1_pred_counter)
			,.if_id1_pred_bht_index_o(if_id1_pred_bht_index)
			,.if_id1_valid_o   (if_id1_valid)
				,.if_id1_instr_o   (if_id1_instr)
				,.target_ff_hit_o  (l0_hit)
				,.target_ff_hit1_o (l0_hit1)
				,.target_ff_correction_o()
			);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.flush_i             (pipeline_flush),
		.issue_ready_i       (issue_pipe_has_room),
		.if_id_pc_i          (if_id_pc),
		.if_id_instr_i       (if_id_instr),
		.if_id_pred_hit_i    (if_id_pred_hit),
		.if_id_pred_taken_i  (if_id_pred_taken),
		.if_id_pred_target_i (if_id_pred_target),
		.if_id_pred_counter_i(if_id_pred_counter),
		.if_id_pred_bht_index_i(if_id_pred_bht_index),
		.if_id_valid_i       (if_id_valid),
		.if_id1_pc_i         (if_id1_pc),
		.if_id1_instr_i      (if_id1_instr),
		.if_id1_pred_hit_i   (if_id1_pred_hit),
		.if_id1_pred_taken_i (if_id1_pred_taken),
		.if_id1_pred_target_i(if_id1_pred_target),
		.if_id1_pred_counter_i(if_id1_pred_counter),
		.if_id1_pred_bht_index_i(if_id1_pred_bht_index),
		.if_id1_valid_i      (if_id1_valid),
		.if_id_ready_o       (decode_if_ready),
		.if_id_consume_two_o (decode_consume_two),
		.issue_pkt_o         (id_issue_pkt),
		.issue_pkt1_o        (id_issue_pkt1)
	);

	ydrasil_issue_stage u_ydrasil_issue_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.stall_id_i          (stall_id),
		.bubble_id_i         (bubble_id),
		.flush_id_i          (pipeline_flush),
		.decode_pkt_i        (id_issue_pkt),
		.decode_pkt1_i       (id_issue_pkt1),
		.dispatch_pkt_i      (dispatch_issue_pkt),
		.dispatch_pkt1_i     (dispatch_issue_pkt1),
		.dispatch_ready_i    (dispatch_ready),
		.rob_head_id_i       (rob_head_id),
		.producer_valid_i    (producer_valid),
		.producer_ready_i    (producer_ready),
		.producer_epoch_i    (producer_epoch),
			.completion_meta_i   (completion_meta),
			.completion_data_i   (completion_data),
			.main_completion_valid_i(alu_completion_valid),
			.main_completion_producer_id_i(alu_completion_producer_id),
			.main_completion_producer_tracked_i(alu_completion_producer_tracked),
			.main_completion_data_i(alu_completion_data),
			.dual_completion_valid_i(dual_completion_valid),
			.dual_completion_producer_id_i(dual_completion_producer_id),
			.dual_completion_producer_tracked_i(dual_completion_producer_tracked),
			.dual_completion_data_i(dual_completion_data),
			.commit_pkt_i        (commit_pkt),
			.commit_pkt1_i       (commit_pkt1),
			.retire_slot0_i      (retire_value_slot0),
			.retire_slot1_i      (retire_value_slot1),
			.lsu_idle_i          (lsu_status_pkt.idle),
		.lsu_credit_i        (lsu_issue_credit),
		.dtcm_reservation_i (dtcm_reservation),
		.dtcm_resp_data_i   (dtcm_resp_data),
		.decode_ready_o      (issue_pipe_has_room),
		.decode_consume_two_o(),
		.dispatch_accept_o   (issue_pipe_push),
		.dispatch_accept1_o  (issue_pipe_push_two),
			.issue_pkt_o         (issue_head_compact_uop),
			.retire_value0_o     (retire_value0),
			.retire_value1_o     (retire_value1),
		.issue_ready_o       (),
		.issue_consume_two_o (issue_consume_two),
		.issue_slot1_replay_o(issue_slot1_replay),
		.issue_fence_o       (id_fence_i),
		.issue_fence_tag_o   (issue_fence_tag),
		.issue_fence_next_pc_o(issue_fence_next_pc),
		.scoreboard_stall_o  (issue_scoreboard_stall),
		.scoreboard_stall1_o (issue_scoreboard_stall1),
		.lsu_struct_stall_o  (issue_lsu_struct_stall),
		.lsu_struct_stall1_o (issue_lsu_struct_stall1),
		.serialize_stall_o   (issue_serialize_stall),
		.src0_wait_o         (issue_src0_wait),
		.src1_wait_o         (issue_src1_wait),
		.src2_wait_o         (issue_src2_wait),
			.src3_wait_o         (issue_src3_wait),
			.illegal_instr_o    (illegal_instr_ex),
			.alu_in_valid_o     (alu_in_valid),
			.alu_in_operand_a_o (alu_in_operand_a),
			.alu_in_operand_b_o (alu_in_operand_b),
			.alu_in_operator_o  (alu_in_operator),
			.alu_in_operator_type_o(alu_in_operator_type),
			.alu_in_rd_wen_o    (alu_in_rd_wen),
			.alu_in_rd_addr_o   (alu_in_rd_addr),
			.alu_in_producer_id_o(alu_in_producer_id),
			.lane_a_pc_o        (lane_a_pc),
			.agu_in_valid_o     (agu_in_valid),
			.agu_in_operand_a_o (agu_in_operand_a),
			.agu_in_operand_b_o (agu_in_operand_b),
			.agu_in_req_o       (agu_in_req),
			.agu_in_store_data_o(agu_in_store_data),
			.csr_in_valid_o     (csr_in_valid),
			.csr_in_operand_a_o (csr_in_operand_a),
			.csr_in_operator_type_o(csr_in_operator_type),
			.csr_in_raddr_o     (csr_in_raddr),
			.csr_in_waddr_o     (csr_in_waddr),
			.csr_in_op_info_o   (csr_in_op_info),
			.csr_in_sys_info_o  (csr_in_sys_info),
			.mul_in_valid_o     (mul_in_valid),
			.mul_in_operand_a_o (mul_in_operand_a),
			.mul_in_operand_b_o (mul_in_operand_b),
			.mul_in_operator_o  (mul_in_operator),
			.mul_in_operator_type_o(mul_in_operator_type),
			.dual_meta_o       (dual_meta),
			.dual_alu_valid_o  (dual_alu_valid),
			.dual_alu_payload_o(dual_alu_payload),
			.dual_alu_operand_a_o(dual_alu_operand_a),
			.dual_alu_operand_b_o(dual_alu_operand_b),
			.dual_bru_valid_o  (dual_bru_valid),
			.dual_bru_payload_o(dual_bru_payload),
				.dual_bru_operand_a_o(dual_bru_operand_a),
				.dual_bru_operand_b_o(dual_bru_operand_b)
		);

	ydrasil_execute_stage u_ydrasil_execute_stage (
		.clk                (clk),
		.rst_n              (rst_n),
		.flush_i            (flush_ex),
		.trap_redirect_i   (trap_ctrl_pkt.redirect),
		.trap_redirect_addr_i(trap_ctrl_pkt.redirect_addr),
		.branch_recovery_keep_mask_i(branch_recovery_keep_mask),
		.ex_accept_valid1_i(ex_accept_valid1),
		.alu_valid_i        (alu_in_valid),
		.alu_operand_a_i    (alu_in_operand_a),
		.alu_operand_b_i    (alu_in_operand_b),
		.alu_operator_i     (alu_in_operator),
		.alu_operator_type_i(alu_in_operator_type),
		.alu_rd_wen_i       (alu_in_rd_wen),
		.alu_rd_addr_i      (alu_in_rd_addr),
		.alu_producer_id_i  (alu_in_producer_id),
		.lane_a_pc_i        (lane_a_pc),
		.illegal_instr_i    (illegal_instr_ex),
		.agu_valid_i        (agu_in_valid),
		.agu_operand_a_i    (agu_in_operand_a),
		.agu_operand_b_i    (agu_in_operand_b),
		.agu_req_i          (agu_in_req),
		.agu_store_data_i   (agu_in_store_data),
		.csr_valid_i        (csr_in_valid),
		.csr_operand_a_i    (csr_in_operand_a),
		.csr_operator_type_i(csr_in_operator_type),
		.csr_waddr_i        (csr_in_waddr),
		.csr_op_info_i      (csr_in_op_info),
		.csr_rdata_i        (csr_ex_rdata),
		.mul_valid_i        (mul_in_valid),
		.mul_operand_a_i    (mul_in_operand_a),
		.mul_operand_b_i    (mul_in_operand_b),
		.mul_operator_i     (mul_in_operator),
		.mul_operator_type_i(mul_in_operator_type),
		.dual_meta_i        (dual_meta),
		.dual_alu_valid_i   (dual_alu_valid),
		.dual_alu_payload_i (dual_alu_payload),
		.dual_alu_operand_a_i(dual_alu_operand_a),
		.dual_alu_operand_b_i(dual_alu_operand_b),
		.dual_bru_valid_i   (dual_bru_valid),
		.dual_bru_payload_i (dual_bru_payload),
		.dual_bru_operand_a_i(dual_bru_operand_a),
		.dual_bru_operand_b_i(dual_bru_operand_b),
		.ex_hzd_o           (ex_hzd_pkt),
		.ex_hzd1_o          (ex_hzd_pkt1),
		.lsu_req_o          (lsu_req_pkt),
		.lane_a_pc_o        (id_instr_addr),
		.lane_b_pc_o        (dual_id_ex_pc),
		.lane_a_valid_o     (id_ex_valid),
		.lane_b_valid_o     (dual_id_ex_valid),
		.lane_a_execute_valid_o(id_ex_execute_valid),
		.ex_csr_wen_o       (ex_csr_wen),
		.ex_csr_wdata_o     (ex_csr_wdata),
		.ex_csr_waddr_o     (ex_csr_waddr),
			.alu_completion_valid_o(alu_completion_valid),
			.alu_completion_producer_id_o(alu_completion_producer_id),
			.alu_completion_producer_tracked_o(alu_completion_producer_tracked),
			.alu_completion_addr_o(alu_completion_addr),
			.alu_completion_data_o(alu_completion_data),
			.mul_issue_o        (ex_mul_issue),
		.mul_issue_waddr_o  (ex_mul_issue_waddr),
		.mul_result_o       (mul_wb_result),
		.mul_rf_wen_o       (mul_rf_wen_rd),
		.mul_rf_waddr_o     (mul_rf_waddr_rd),
		.mul_producer_id_o  (mul_producer_id),
		.mul_result_valid_o (mul_result_valid),
		.mul_stall_o        (ex_mul_stall),
		.dual_completion_valid_o(dual_completion_valid),
		.dual_completion_producer_id_o(dual_completion_producer_id),
		.dual_completion_producer_tracked_o(dual_completion_producer_tracked),
		.dual_completion_addr_o(dual_completion_addr),
		.dual_completion_data_o(dual_completion_data),
			.ex_branch_jump_o  (ex_branch_jump),
		.ex_branch_target_o(ex_branch_target),
		.ex_pc_redirect_o  (ex_pc_redirect),
		.ex_pc_redirect_target_o(ex_pc_redirect_target),
		.ex_bp_train_o     (ex_bp_train_pkt),
		.ex_branch_mispredict_o(ex_branch_mispredict),
		.dual_instret_valid_o(dual_instret_inc),
		.dual_commit_pc_o  (dual_commit_pc),
		.dual_commit_instr_o(dual_commit_instr)
`ifndef SYNTHESIS
		,.dbg_bp_resolve_valid_o(dbg_bp_resolve_valid)
		,.dbg_bp_resolve_pc_o(dbg_bp_resolve_pc)
		,.dbg_bp_actual_taken_o(dbg_bp_actual_taken)
		,.dbg_bp_actual_target_o(dbg_bp_actual_target)
		,.dbg_bp_actual_next_pc_o(dbg_bp_actual_next_pc)
		,.dbg_bp_pred_hit_o(dbg_bp_pred_hit)
		,.dbg_bp_pred_taken_o(dbg_bp_pred_taken)
		,.dbg_bp_pred_target_o(dbg_bp_pred_target)
		,.dbg_bp_pred_counter_o(dbg_bp_pred_counter)
		,.dbg_bp_pred_next_pc_o(dbg_bp_pred_next_pc)
		,.dbg_bp_mispredict_o(dbg_bp_mispredict)
`endif
	);

	ydrasil_mems u_ydrasil_mems (
		.clk           (clk),
		.rst_n         (rst_n),
		.if_mem_addr_i (if_mem_addr),
		.if_mem_rdata_o(if_mem_rdata),
		.if_mem_addr1_i(if_mem_addr1),
		.if_mem_rdata1_o(if_mem_rdata1),
		.lsu_mem_req_i (dtcm_req_pkt),
		.lsu_mem_data_o(dtcm_rdata),
        .dram_sel_i     (1'b1)
		// .hold_flag_o   (hold_flag)
	);

		ydrasil_ctrl u_ctrl (
			.clk               (clk),
			.rst_n             (rst_n),
			.ex_branch_jump_i  (ex_pc_redirect),
				.ex_branch_resolve_i(ex_bp_train_pkt.valid),
			.ex_branch_producer_id_i(ex_bp_train_pkt.producer_id),
			.ex_branch_target_i(ex_pc_redirect_target),
			.ex_pc_i           (id_instr_addr),
			.ex_pc1_i          (dual_id_ex_pc),
			.ex_hzd_i          (ex_hzd_pkt),
			.ex_hzd1_i         (ex_hzd_pkt1),
			.dispatch_pkt_i    (id_issue_pkt),
			.dispatch_pkt1_i   (id_issue_pkt1),
			.dispatch_accept_i (issue_pipe_push),
			.dispatch_accept1_i(issue_pipe_push_two),
			.issue_pkt_i       (issue_head_compact_uop),
				.issue_fence_i     (id_fence_i),
			.issue_fence_tag_i (issue_fence_tag),
			.completion_meta_i (completion_meta),
			.completion_rd_i   (completion_rd),
				.trap_stall_i      (trap_ctrl_pkt.stall),
				.ex_mul_stall_i     (ex_mul_stall),
			.retire_value0_i   (retire_value0),
			.retire_value1_i   (retire_value1),
			.dispatch_pkt_o    (dispatch_issue_pkt),
			.dispatch_pkt1_o   (dispatch_issue_pkt1),
			.dispatch_ready_o  (dispatch_ready),
			.rob_head_id_o     (rob_head_id),
			.producer_valid_o  (producer_valid),
			.producer_ready_o  (producer_ready),
			.producer_epoch_o  (producer_epoch),
			.gpr_pending_o     (gpr_pending_q),
			.retire_pending_o  (retire_pending),
			.ex_accept_valid_o (ex_accept_valid),
			.ex_accept_valid1_o(ex_accept_valid1),
			.retire_commit_o  (commit_pkt),
			.retire_commit1_o (commit_pkt1),
			.retire_value_slot0_o(retire_value_slot0),
			.retire_value_slot1_o(retire_value_slot1),
		.stall_if_o        (stall_if),
		.stall_id_o        (stall_id),
		.bubble_id_o       (bubble_id),
		.flush_if_o        (flush_if),
		.flush_id_o        (flush_id),
			.flush_ex_o        (flush_ex),
			.pipeline_flush_o  (pipeline_flush),
		.branch_jump_o     (branch_jump),
		.branch_target_o   (branch_target),
		.branch_recovery_keep_mask_o(branch_recovery_keep_mask)
	);

	ydrasil_csr_stage u_ydrasil_csr_stage (
		.clk               (clk),
		.rst_n             (rst_n),
		.retire_i          (commit_pkt),
		.retire1_i         (commit_pkt1),
		.ex_csr_wen_i      (ex_csr_wen),
		.id_csr_raddr_i    (csr_in_raddr),
		.ex_csr_waddr_i    (ex_csr_waddr),
		.ex_csr_data_i     (ex_csr_wdata),
		.trap_csr_write_i (trap_csr_write_pkt),
		.irq_i            (irq_i),
		.trap_state_o     (trap_csr_state_pkt),
		.csr_ex_data_o    (csr_ex_rdata)
	);

	ydrasil_exception_stage u_ydrasil_exception_stage (
		.clk               (clk),
		.rst_n             (rst_n),
		.irq_i             (irq_i),
		.csr_state_i       (trap_csr_state_pkt),
		.ex_accept_valid_i (ex_accept_valid),
		.operator_type_i   (alu_in_operator_type),
		.sys_info_i        (csr_in_sys_info),
		.illegal_instr_i   (illegal_instr_ex),
		.lane_a_valid_i    (id_ex_valid),
		.lane_a_pc_i       (id_instr_addr),
		.lane_b_valid_i    (dual_id_ex_valid),
		.lane_b_pc_i       (dual_id_ex_pc),
		.frontend_pc_i     (if_resume_pc),
		.lsu_idle_i        (lsu_status_pkt.idle),
		.retire_pending_i  (retire_pending),
		.mul_stall_i       (ex_mul_stall),
		.redirect_pending_i(ex_pc_redirect || id_fence_i),
		.csr_write_o       (trap_csr_write_pkt),
		.trap_ctrl_o       (trap_ctrl_pkt)
	);

`ifndef SYNTHESIS
	ydrasil_commit_trace u_ydrasil_commit_trace (
		.clk              (clk),
			.rst_n            (rst_n),
			.retire_i         (commit_pkt),
			.retire1_i        (commit_pkt1)
`ifdef YDRASIL_RETIRE_TRACE
			,.retire0_valid_o (retire0_valid_o)
			,.retire0_pc_o    (retire0_pc_o)
			,.retire1_valid_o (retire1_valid_o)
			,.retire1_pc_o    (retire1_pc_o)
`else
			,.retire0_valid_o ()
			,.retire0_pc_o    ()
			,.retire1_valid_o ()
			,.retire1_pc_o    ()
`endif
			,.dbg_bp_predict_pc_o(dbg_bp_predict_pc_o)
			,.dbg_bp_predict_hit_o(dbg_bp_predict_hit_o)
			,.dbg_bp_predict_taken_o(dbg_bp_predict_taken_o)
			,.dbg_bp_predict_target_o(dbg_bp_predict_target_o)
			,.dbg_bp_predict_counter_o(dbg_bp_predict_counter_o)
			,.dbg_bp_resolve_valid_o(dbg_bp_resolve_valid_o)
			,.dbg_bp_resolve_pc_o(dbg_bp_resolve_pc_o)
			,.dbg_bp_actual_taken_o(dbg_bp_actual_taken_o)
			,.dbg_bp_actual_target_o(dbg_bp_actual_target_o)
			,.dbg_bp_actual_next_pc_o(dbg_bp_actual_next_pc_o)
			,.dbg_bp_pred_hit_o(dbg_bp_pred_hit_o)
			,.dbg_bp_pred_taken_o(dbg_bp_pred_taken_o)
			,.dbg_bp_pred_target_o(dbg_bp_pred_target_o)
			,.dbg_bp_pred_counter_o(dbg_bp_pred_counter_o)
			,.dbg_bp_pred_next_pc_o(dbg_bp_pred_next_pc_o)
			,.dbg_bp_mispredict_o(dbg_bp_mispredict_o)
	);
`endif



endmodule
