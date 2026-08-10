

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
	wire [31:0] if_id_pc;
	wire [31:0] if_id_instr;
	wire        if_id_pred_hit;
	wire        if_id_pred_taken;
	wire [31:0] if_id_pred_target;
	wire [1:0]  if_id_pred_counter;
	bp_bht_index_t if_id_pred_bht_index;
	wire        if_id_valid;
	ydrasil_dispatch_domain_t if_id_domain;
		wire        if_id_serial;
		wire        if_id_src0_used;
		wire        if_id_src1_used;
		wire        if_id_dst_writes;
	wire [31:0] if_id1_pc;
	wire [31:0] if_id1_instr;
	wire        if_id1_pred_hit;
	wire        if_id1_pred_taken;
	wire [31:0] if_id1_pred_target;
	wire [1:0]  if_id1_pred_counter;
	bp_bht_index_t if_id1_pred_bht_index;
	wire        if_id1_valid;
	ydrasil_dispatch_domain_t if_id1_domain;
		wire        if_id1_serial;
		wire        if_id1_src0_used;
		wire        if_id1_src1_used;
		wire        if_id1_dst_writes;
	// CTRL signals
		(* max_fanout = 8 *) wire   stall_if;
		(* max_fanout = 8 *) wire   flush_if;
		(* max_fanout = 8 *) wire   flush_id;
		(* max_fanout = 8 *) wire   flush_ex;
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
	wire                                dual_bit_valid;
	ydrasil_lane_b_bit_payload_t        dual_bit_payload;
	wire [31:0]                         dual_bit_operand_a;
	wire [31:0]                         dual_bit_operand_b;
	wire                                dual_bru_valid;
	ydrasil_lane_b_bru_payload_t        dual_bru_payload;
	wire [31:0]                         dual_bru_operand_a;
	wire [31:0]                         dual_bru_operand_b;
	ydrasil_lsu_req_pkt_t         lsu_req_pkt;
	wire                           illegal_instr_ex;

	// EX outputs
	wire                        ex_branch_jump;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_branch_target;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] alu_result;
	wire                        alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd;
	producer_id_t               alu_producer_id;
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

	// Branch predictor
	wire                        bp_predict_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict_target;
	wire [1:0]                  bp_predict_counter;
	wire                        bp_predict1_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict1_target;
	wire [1:0]                  bp_predict1_counter;
	// Raw BRAM predictor outputs.  The architectural prediction path first
		// Feed fetch directly from the BRAM branch predictor.
	wire                        bp_bram_predict_hit;
	wire                        bp_bram_predict_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict_target;
	wire [1:0]                  bp_bram_predict_counter;
	wire                        bp_bram_predict1_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict1_target;
	wire [1:0]                  bp_bram_predict1_counter;
		// Predictor debug observation reflects the registered target table.
		wire l0_hit;
		wire l0_hit1;
	wire                        id_fence_i;
	wire [31:0]                 fence_resume_pc;
	producer_id_t               issue_fence_tag;
	wire [31:0]                 issue_fence_next_pc;
		(* max_fanout = 8 *) wire   pipeline_flush;
	wire                        id_ex_valid;

	// LSU request path
	wire                        dtcm_load_valid;
	wire [BUS_ADDR_WIDTH-1:0]  dtcm_load_addr;
	wire                        dtcm_store_valid;
	wire [BUS_ADDR_WIDTH-1:0]  dtcm_store_addr;
	wire [BUS_DATA_WIDTH-1:0]  dtcm_store_data;
	wire [3:0]                 dtcm_store_mask;
	ydrasil_mem_req_pkt_t       mmio_req_pkt;
	ydrasil_mem_rsp_pkt_t       mmio_rsp_pkt;
	wire                        mmio_req_ready;
	ydrasil_lsu_status_pkt_t    lsu_status_pkt;
	wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]  dtcm_rdata;

	ydrasil_commit_pkt_t         commit_pkt;
	ydrasil_commit_pkt_t         commit_pkt1;
	// LSU allocation and checkpoint handshake.
	wire                            lsq_alloc_ready;
	wire                            lsq_alloc_two_ready;
	producer_slot_t                 lsq_alloc_index0;
	producer_slot_t                 lsq_alloc_index1;
	wire                            lsq_alloc0_valid;
	producer_id_t                   lsq_alloc0_id;
	wire                            lsq_alloc1_valid;
	producer_id_t                   lsq_alloc1_id;
	wire                            issue_checkpoint0_valid;
	producer_id_t                   issue_checkpoint0_id;
	wire                            issue_checkpoint1_valid;
	producer_id_t                   issue_checkpoint1_id;

	// LSU/ID hazard observations are derived from the registered lane boundary.
	ydrasil_ex_hzd_pkt_t            ex_hzd_pkt;
	ydrasil_ex_hzd_pkt_t            ex_hzd_pkt1;
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
	producer_id_t                   retire_value_id0;
	producer_id_t                   retire_value_id1;
	wire                            retire_valid;
	wire                            retire_valid1;
	wire [REGS_DATA_WIDTH-1:0]      retire_value0;
	wire [REGS_DATA_WIDTH-1:0]      retire_value1;
	producer_id_t                   rob_head_id;
	wire                            backend_empty;
	ydrasil_issue_pkt_t             id_issue_pkt;
	ydrasil_issue_pkt_t             id_issue_pkt1;
	ydrasil_source_desc_t           id_decode_src0;
	ydrasil_source_desc_t           id_decode_src1;
	ydrasil_source_desc_t           id_decode_src2;
	ydrasil_source_desc_t           id_decode_src3;
	wire                            id_decode_dst0_writes;
	wire [REGS_ADDR_WIDTH-1:0]     id_decode_dst0_addr;
	ydrasil_issue_pkt_t             dispatch_issue_pkt;
	ydrasil_issue_pkt_t             dispatch_issue_pkt1;

	// Decode-to-backend elastic token.  Rename and LSQ admission consume this
	// registered packet, so raw IF/ID payload and backend credits cannot form a
	// combinational return path into FetchQ pop control.
	typedef struct packed {
		ydrasil_issue_pkt_t   pkt;
		ydrasil_source_desc_t src0;
		ydrasil_source_desc_t src1;
		logic                 serial;
	} decode_backend_token_t;
	decode_backend_token_t decode_backend_token_q [0:1];
	decode_backend_token_t decode_backend_token_d [0:1];
	reg [1:0] decode_backend_count_q;
	reg [1:0] decode_backend_count_d;
	// Rename owns the architectural allocation boundary.  This queue holds
	// fully renamed packets after ROB/RAT, checkpoint, and LSQ reservation have
	// been accepted; the scheduler only consumes these registered tokens.
	typedef struct packed {
		ydrasil_issue_pkt_t pkt;
		logic               serial;
	} renamed_dispatch_token_t;
	localparam int RENAMED_DISPATCH_DEPTH = 4;
	renamed_dispatch_token_t renamed_dispatch_token_q
		[0:RENAMED_DISPATCH_DEPTH-1];
	renamed_dispatch_token_t renamed_dispatch_token_d
		[0:RENAMED_DISPATCH_DEPTH-1];
	reg [2:0] renamed_dispatch_count_q;
	reg [2:0] renamed_dispatch_count_d;
	ydrasil_issue_pkt_t rename_enqueue_pkt0;
	ydrasil_issue_pkt_t rename_enqueue_pkt1;
	wire rename_dispatch_enqueue0;
	wire rename_dispatch_enqueue1;
	wire rename_value_alloc0_valid;
	wire rename_value_alloc1_valid;
	producer_id_t rename_value_alloc0_id;
	producer_id_t rename_value_alloc1_id;
	wire decode_backend_ready = (decode_backend_count_q < 2) &&
		!pipeline_flush && !trap_ctrl_pkt.redirect && !ex_pc_redirect;
	wire decode_backend_consume0 = (decode_backend_count_q != 0) &&
		rename_dispatch_enqueue0;
	wire decode_backend_consume_two = decode_backend_consume0 &&
		(decode_backend_count_q == 2) && rename_dispatch_enqueue1;
	// A two-lane capture is only performed into an empty token queue.  When one
	// token remains, capture lane 0 only; this avoids a same-edge overwrite when
	// the backend consumes the old lane-0 token.
	// Decode valid is exactly the registered ingress valid.  Keep capture
	// control narrow so instruction decode payload cannot feed FetchQ pop.
	wire decode_backend_capture0 = decode_backend_ready && if_id_valid;
	wire decode_backend_capture_two = decode_backend_capture0 &&
		(decode_backend_count_q == 0) && if_id1_valid && !if_id_serial;
	// Capture destination is derived only from the registered occupancy and
	// consume event.  Keep this control independent from the packed token
	// payload next-state below.
	wire decode_backend_capture_to_slot0 = decode_backend_capture0 &&
		((decode_backend_count_q == 0) || decode_backend_consume0);
	ydrasil_source_desc_t           dispatch_src0;
	ydrasil_source_desc_t           dispatch_src1;
	ydrasil_source_desc_t           dispatch_src2;
	ydrasil_source_desc_t           dispatch_src3;
	wire                            dispatch_src0_static_ready;
	wire                            dispatch_src1_static_ready;
	wire                            dispatch_src2_static_ready;
	wire                            dispatch_src3_static_ready;
	ydrasil_compact_uop_t           lane_a_compact_uop;
	ydrasil_compact_uop_t           lane_b_compact_uop;
	wire                            issue_consume_two;
	wire                            issue_slot1_replay;
	wire                            issue_dependency_wait;
	wire                            issue_dependency_wait1;
	wire                            issue_lsu_struct_stall;
	wire                            issue_lsu_struct_stall1;
	wire                            issue_serialize_stall;
	wire                            issue_src0_wait;
	wire                            issue_src1_wait;
	wire                            issue_src2_wait;
	wire                            issue_src3_wait;
	wire                            dispatch_ready;
	wire                            dispatch_two_ready;
	wire                            issue_pipe_has_room;
	wire                            issue_pipe_push;
		wire                            issue_pipe_push_two;
		wire                            decode_if_ready;
		// Scheduler dequeue only advances the FIFO's registered next-state.
		// Rename admission sees the current registered occupancy exclusively, so
		// an issue-side pop never creates a same-cycle ROB/RAT/LSQ allocation
		// credit.
		wire rename_dispatch_consume0 = (renamed_dispatch_count_q != 0) &&
			issue_pipe_push;
		wire rename_dispatch_consume1 = rename_dispatch_consume0 &&
			(renamed_dispatch_count_q >= 2) && issue_pipe_push_two;
		wire [1:0] rename_dispatch_pop_count = {1'b0, rename_dispatch_consume0} +
			{1'b0, rename_dispatch_consume1};
		wire [2:0] rename_dispatch_count_after_pop =
			renamed_dispatch_count_q - rename_dispatch_pop_count;
		wire [2:0] rename_dispatch_free_slots =
			3'd4 - renamed_dispatch_count_q;
		wire rename_raw0_valid = (decode_backend_count_q != 0) &&
			decode_backend_token_q[0].pkt.valid;
		wire rename_raw1_valid = (decode_backend_count_q == 2) &&
			decode_backend_token_q[1].pkt.valid;
		wire rename_raw0_memory =
			(decode_backend_token_q[0].pkt.uop_class == UOP_CLASS_LOAD) ||
			(decode_backend_token_q[0].pkt.uop_class == UOP_CLASS_STORE);
		wire rename_raw1_memory =
			(decode_backend_token_q[1].pkt.uop_class == UOP_CLASS_LOAD) ||
			(decode_backend_token_q[1].pkt.uop_class == UOP_CLASS_STORE);
		wire rename_try_two = rename_raw1_valid &&
			!decode_backend_token_q[0].serial && dispatch_two_ready &&
			(rename_dispatch_free_slots >= 3'd2);
		wire [1:0] rename_lsq_count = {1'b0, rename_raw0_memory} +
			{1'b0, (rename_try_two && rename_raw1_memory)};
		wire rename_lsq_admission_ok = (rename_lsq_count == 0) ? 1'b1 :
			(rename_lsq_count == 1 ? lsq_alloc_ready : lsq_alloc_two_ready);
		assign rename_dispatch_enqueue0 = rename_raw0_valid && dispatch_ready &&
			(rename_dispatch_free_slots != 0) && rename_lsq_admission_ok &&
			!pipeline_flush && !trap_ctrl_pkt.redirect && !ex_pc_redirect;
		assign rename_dispatch_enqueue1 = rename_dispatch_enqueue0 && rename_try_two;

		always_comb begin
			rename_enqueue_pkt0 = dispatch_issue_pkt;
			rename_enqueue_pkt1 = dispatch_issue_pkt1;
			if (rename_raw0_memory)
				rename_enqueue_pkt0.lsq_index = lsq_alloc_index0;
			else
				rename_enqueue_pkt0.lsq_index = '0;
			if (rename_raw1_memory)
				rename_enqueue_pkt1.lsq_index = lsq_alloc_index1;
			else
				rename_enqueue_pkt1.lsq_index = '0;
		end

		// Allocation side effects are owned by rename enqueue, not scheduler
		// ingress. Every packet stores the producer/LSQ identity reserved here.
		assign lsq_alloc0_valid = rename_dispatch_enqueue0 && rename_raw0_memory;
		assign lsq_alloc0_id = rename_enqueue_pkt0.dst.rob_tag;
		assign lsq_alloc1_valid = rename_dispatch_enqueue1 && rename_raw1_memory;
		assign lsq_alloc1_id = rename_enqueue_pkt1.dst.rob_tag;
		assign issue_checkpoint0_valid = rename_dispatch_enqueue0 &&
			(decode_backend_token_q[0].serial ||
			 (rename_enqueue_pkt0.uop_class == UOP_CLASS_BJP));
		assign issue_checkpoint0_id = rename_enqueue_pkt0.dst.rob_tag;
		assign issue_checkpoint1_valid = rename_dispatch_enqueue1 &&
			(decode_backend_token_q[1].serial ||
			 (rename_enqueue_pkt1.uop_class == UOP_CLASS_BJP));
		assign issue_checkpoint1_id = rename_enqueue_pkt1.dst.rob_tag;
		assign rename_value_alloc0_valid = rename_dispatch_enqueue0;
		assign rename_value_alloc1_valid = rename_dispatch_enqueue1;
		assign rename_value_alloc0_id = rename_enqueue_pkt0.dst.rob_tag;
		assign rename_value_alloc1_id = rename_enqueue_pkt1.dst.rob_tag;
		wire                            decode_consume_two;
	wire                            id_ex_execute_valid;
	wire                            ex_accept_valid;
	wire                            ex_accept_valid1;
	wire                            exception_sys_accept =
		csr_in_valid && ex_accept_valid1;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_ex_rdata;
	wire 					    ex_csr_wen;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      ex_csr_wdata;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       ex_csr_waddr;

	// Trap control packets shared by retirement and recovery control.
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

	wire main_store_due_valid = agu_in_valid && agu_in_req.is_store;
	wire ex_no_result_due0_valid = main_store_due_valid ||
		(alu_in_valid && !alu_in_rd_wen &&
		 !alu_in_operator_type[OPERATOR_TYPE_BJP]);
	wire producer_id_t ex_no_result_due0_id;
	assign ex_no_result_due0_id = main_store_due_valid ?
		agu_in_req.producer_id : alu_in_producer_id;
	wire ex_no_result_due1_valid = !dual_meta.rd_wen &&
		(dual_alu_valid || dual_bit_valid || mul_in_valid || csr_in_valid);
	wire serial_complete = csr_in_valid &&
		csr_in_operator_type[OPERATOR_TYPE_CSR] &&
		!csr_in_operator_type[OPERATOR_TYPE_SYS];

	ydrasil_completion_ctrl u_completion_ctrl (
		.clk               (clk),
		.rst_n             (rst_n),
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
			.req_i             (lsu_req_pkt),
			.alloc0_valid_i    (lsq_alloc0_valid),
			.alloc0_producer_id_i(lsq_alloc0_id),
			.alloc0_is_load_i  (rename_enqueue_pkt0.uop_class == UOP_CLASS_LOAD),
			.alloc0_is_store_i (rename_enqueue_pkt0.uop_class == UOP_CLASS_STORE),
			.alloc1_valid_i    (lsq_alloc1_valid),
			.alloc1_producer_id_i(lsq_alloc1_id),
			.alloc1_is_load_i  (rename_enqueue_pkt1.uop_class == UOP_CLASS_LOAD),
			.alloc1_is_store_i (rename_enqueue_pkt1.uop_class == UOP_CLASS_STORE),
			.checkpoint0_valid_i(issue_checkpoint0_valid),
			.checkpoint0_id_i  (issue_checkpoint0_id),
			.checkpoint1_valid_i(issue_checkpoint1_valid),
			.checkpoint1_id_i  (issue_checkpoint1_id),
			.alloc_ready_o     (lsq_alloc_ready),
			.alloc_two_ready_o (lsq_alloc_two_ready),
			.alloc0_index_o    (lsq_alloc_index0),
			.alloc1_index_o    (lsq_alloc_index1),
				.commit0_valid_i   (retire_valid),
					.commit0_id_i      (commit_pkt.producer_id),
				.commit1_valid_i   (retire_valid1),
					.commit1_id_i      (commit_pkt1.producer_id),
				.branch_recovery_i (ex_pc_redirect),
			.trap_flush_i      (trap_ctrl_pkt.redirect),
			.recovery_head_slot_i(rob_head_id[PRODUCER_SLOT_WIDTH-1:0]),
			.recovery_branch_slot_i(ex_bp_train_pkt.producer_id[
				PRODUCER_SLOT_WIDTH-1:0]),
			.recovery_branch_id_i(ex_bp_train_pkt.producer_id),
			.rob_head_id_i      (rob_head_id),
		.completion_meta_i (completion_meta),
		.completion_data_i (completion_data),
		.dtcm_rdata_i      (dtcm_rdata),
		.dtcm_load_valid_o (dtcm_load_valid),
		.dtcm_load_addr_o  (dtcm_load_addr),
		.dtcm_store_valid_o(dtcm_store_valid),
		.dtcm_store_addr_o (dtcm_store_addr),
		.dtcm_store_data_o (dtcm_store_data),
		.dtcm_store_mask_o (dtcm_store_mask),
		.mmio_rsp_i        (mmio_rsp_pkt),
		.mmio_ready_i      (mmio_req_ready),
		.mmio_req_o        (mmio_req_pkt),
		.status_o          (lsu_status_pkt),
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
		.req_ready_o (mmio_req_ready),
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
			.predict_bht_index_o(),
			.predict0_spec_valid_i(1'b0),
			.predict0_spec_conditional_i(1'b0),
			.predict0_spec_taken_i(1'b0),
			.predict_pc1_i    (if_mem_addr1),
			.predict1_hit_o   (),
			.predict1_taken_o (bp_bram_predict1_taken),
			.predict1_target_o(bp_bram_predict1_target),
			.predict1_counter_o(bp_bram_predict1_counter),
			.predict1_bht_index_o(),
			.train_i          (ex_bp_train_pkt),
			.invalidate_i     (id_fence_i)
		);

		ydrasil_if_stage #(
			.FETCHQ_DEPTH(10),
			.BHT_ENTRIES(BHT_ENTRIES)
		) u_ydrasil_if_stage (
			.clk           (clk),
			.rst_n         (rst_n),
				.decode_ready_i  (decode_backend_ready),
				.flush_if_i      (flush_if),
				.consume_two_i   (decode_backend_capture_two),
			.branch_jump_i   (branch_jump),
			.branch_target_i (branch_target),
				.bp_predict_taken_i(bp_bram_predict_taken),
				.bp_predict_target_i(bp_bram_predict_target),
				.bp_predict_counter_i(bp_bram_predict_counter),
				.bp_predict1_taken_i(bp_bram_predict1_taken),
				.bp_predict1_target_i(bp_bram_predict1_target),
				.bp_predict1_counter_i(bp_bram_predict1_counter),
			.bp_invalidate_i(id_fence_i),
				.bp_invalidate_target_i(issue_fence_next_pc),
			.target_ff_train_i(ex_bp_train_pkt),
			.if_mem_addr_o   (if_mem_addr),
			.if_mem_addr1_o  (if_mem_addr1),
			.bp_lookup_pc_o   (bp_lookup_pc),
			.if_mem_rdata_i  (if_mem_rdata),
			.if_mem_rdata1_i (if_mem_rdata1),
			.if_id_pc_o      (if_id_pc),
			.if_id_pred_hit_o(if_id_pred_hit),
			.if_id_pred_taken_o(if_id_pred_taken),
			.if_id_pred_target_o(if_id_pred_target),
			.if_id_pred_counter_o(if_id_pred_counter),
			.if_id_pred_bht_index_o(if_id_pred_bht_index),
			.if_id_valid_o   (if_id_valid),
				.if_id_instr_o   (if_id_instr)
				,.if_id_domain_o (if_id_domain)
					,.if_id_serial_o (if_id_serial)
					,.if_id_src0_used_o(if_id_src0_used)
					,.if_id_src1_used_o(if_id_src1_used)
					,.if_id_dst_writes_o(if_id_dst_writes)
			,.if_id1_pc_o      (if_id1_pc)
			,.if_id1_pred_hit_o(if_id1_pred_hit)
			,.if_id1_pred_taken_o(if_id1_pred_taken)
			,.if_id1_pred_target_o(if_id1_pred_target)
			,.if_id1_pred_counter_o(if_id1_pred_counter)
			,.if_id1_pred_bht_index_o(if_id1_pred_bht_index)
			,.if_id1_valid_o   (if_id1_valid)
					,.if_id1_instr_o   (if_id1_instr)
					,.if_id1_domain_o (if_id1_domain)
						,.if_id1_serial_o (if_id1_serial)
						,.if_id1_src0_used_o(if_id1_src0_used)
						,.if_id1_src1_used_o(if_id1_src1_used)
						,.if_id1_dst_writes_o(if_id1_dst_writes)
				,.target_ff_hit_o  (l0_hit)
				,.target_ff_hit1_o (l0_hit1)
				,.target_ff_correction_o()
			);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.flush_i             (pipeline_flush),
		.issue_ready_i       (decode_backend_ready),
		.if_id_pc_i          (if_id_pc),
		.if_id_instr_i       (if_id_instr),
		.if_id_pred_hit_i    (if_id_pred_hit),
		.if_id_pred_taken_i  (if_id_pred_taken),
		.if_id_pred_target_i (if_id_pred_target),
		.if_id_pred_counter_i(if_id_pred_counter),
		.if_id_pred_bht_index_i(if_id_pred_bht_index),
		.if_id_valid_i       (if_id_valid),
			.if_id_serial_i      (if_id_serial),
			.if_id_domain_i      (if_id_domain),
			.if_id_src0_used_i   (if_id_src0_used),
			.if_id_src1_used_i   (if_id_src1_used),
			.if_id_dst_writes_i  (if_id_dst_writes),
		.if_id1_pc_i         (if_id1_pc),
		.if_id1_instr_i      (if_id1_instr),
		.if_id1_pred_hit_i   (if_id1_pred_hit),
		.if_id1_pred_taken_i (if_id1_pred_taken),
		.if_id1_pred_target_i(if_id1_pred_target),
		.if_id1_pred_counter_i(if_id1_pred_counter),
		.if_id1_pred_bht_index_i(if_id1_pred_bht_index),
		.if_id1_valid_i      (if_id1_valid),
			.if_id1_serial_i     (if_id1_serial),
			.if_id1_domain_i     (if_id1_domain),
			.if_id1_src0_used_i  (if_id1_src0_used),
			.if_id1_src1_used_i  (if_id1_src1_used),
			.if_id1_dst_writes_i (if_id1_dst_writes),
		.if_id_ready_o       (decode_if_ready),
			.if_id_consume_two_o (),
		.issue_pkt_o         (id_issue_pkt),
		.issue_pkt1_o        (id_issue_pkt1),
		.decode_src0_o       (id_decode_src0),
		.decode_src1_o       (id_decode_src1),
		.decode_src2_o       (id_decode_src2),
		.decode_src3_o       (id_decode_src3),
		.decode_dst0_writes_o(id_decode_dst0_writes),
		.decode_dst0_addr_o  (id_decode_dst0_addr)
	);

	// Occupancy/valid state is intentionally computed in its own process.  It
	// only observes registered occupancy, queue handshakes, and narrow valid
	// bits; no packed packet field feeds this next-state.
	always_comb begin
		decode_backend_count_d = decode_backend_count_q;

		if (decode_backend_consume_two) begin
			decode_backend_count_d = '0;
		end else if (decode_backend_consume0) begin
			decode_backend_count_d = decode_backend_count_q - 1'b1;
		end

		if (decode_backend_capture0) begin
			decode_backend_count_d = decode_backend_count_d + 1'b1;
		end
		if (decode_backend_capture_two) begin
			decode_backend_count_d = decode_backend_count_d + 1'b1;
		end
	end

	// Payload movement has a separate next-state process.  It uses only the
	// registered token payload and the narrow control decisions above, so
	// occupancy calculation cannot become a packed-payload feedback path.
	always_comb begin
		decode_backend_token_d[0] = decode_backend_token_q[0];
		decode_backend_token_d[1] = decode_backend_token_q[1];

		if (decode_backend_consume_two) begin
			decode_backend_token_d[0] = '0;
			decode_backend_token_d[1] = '0;
		end else if (decode_backend_consume0) begin
			decode_backend_token_d[0] = decode_backend_token_q[1];
			decode_backend_token_d[1] = '0;
		end

		if (decode_backend_capture0) begin
			if (decode_backend_capture_to_slot0)
				decode_backend_token_d[0] = '{pkt: id_issue_pkt,
					src0: id_decode_src0, src1: id_decode_src1,
					serial: if_id_serial};
			else
				decode_backend_token_d[1] = '{pkt: id_issue_pkt,
					src0: id_decode_src0, src1: id_decode_src1,
					serial: if_id_serial};
		end
		if (decode_backend_capture_two) begin
			decode_backend_token_d[1] = '{pkt: id_issue_pkt1,
				src0: id_decode_src2, src1: id_decode_src3,
				serial: if_id1_serial};
		end
	end

		always_ff @(posedge clk or negedge rst_n) begin
			if (!rst_n || pipeline_flush || trap_ctrl_pkt.redirect ||
				ex_pc_redirect) begin
			decode_backend_count_q <= '0;
			decode_backend_token_q[0] <= '0;
			decode_backend_token_q[1] <= '0;
		end else begin
			decode_backend_count_q <= decode_backend_count_d;
			decode_backend_token_q[0] <= decode_backend_token_d[0];
			decode_backend_token_q[1] <= decode_backend_token_d[1];
			end
		end

		always_comb begin
			renamed_dispatch_count_d = renamed_dispatch_count_q -
				rename_dispatch_pop_count;
			renamed_dispatch_token_d[0] = renamed_dispatch_token_q[0];
			renamed_dispatch_token_d[1] = renamed_dispatch_token_q[1];
			renamed_dispatch_token_d[2] = renamed_dispatch_token_q[2];
			renamed_dispatch_token_d[3] = renamed_dispatch_token_q[3];

			case (rename_dispatch_pop_count)
				2'd2: begin
					renamed_dispatch_token_d[0] = renamed_dispatch_token_q[2];
					renamed_dispatch_token_d[1] = renamed_dispatch_token_q[3];
					renamed_dispatch_token_d[2] = '0;
					renamed_dispatch_token_d[3] = '0;
				end
				2'd1: begin
					renamed_dispatch_token_d[0] = renamed_dispatch_token_q[1];
					renamed_dispatch_token_d[1] = renamed_dispatch_token_q[2];
					renamed_dispatch_token_d[2] = renamed_dispatch_token_q[3];
					renamed_dispatch_token_d[3] = '0;
				end
				default: begin
				end
			endcase

			if (rename_dispatch_enqueue0) begin
				case (rename_dispatch_count_after_pop)
					3'd0: renamed_dispatch_token_d[0] =
						'{pkt: rename_enqueue_pkt0,
						  serial: decode_backend_token_q[0].serial};
					3'd1: renamed_dispatch_token_d[1] =
						'{pkt: rename_enqueue_pkt0,
						  serial: decode_backend_token_q[0].serial};
					3'd2: renamed_dispatch_token_d[2] =
						'{pkt: rename_enqueue_pkt0,
						  serial: decode_backend_token_q[0].serial};
					3'd3: renamed_dispatch_token_d[3] =
						'{pkt: rename_enqueue_pkt0,
						  serial: decode_backend_token_q[0].serial};
					default: begin
					end
				endcase
				renamed_dispatch_count_d = renamed_dispatch_count_d + 1'b1;
			end
			if (rename_dispatch_enqueue1) begin
				case (rename_dispatch_count_after_pop + 3'd1)
					3'd1: renamed_dispatch_token_d[1] =
						'{pkt: rename_enqueue_pkt1,
						  serial: decode_backend_token_q[1].serial};
					3'd2: renamed_dispatch_token_d[2] =
						'{pkt: rename_enqueue_pkt1,
						  serial: decode_backend_token_q[1].serial};
					3'd3: renamed_dispatch_token_d[3] =
						'{pkt: rename_enqueue_pkt1,
						  serial: decode_backend_token_q[1].serial};
					default: begin
					end
				endcase
				renamed_dispatch_count_d = renamed_dispatch_count_d + 1'b1;
			end
		end

		always_ff @(posedge clk or negedge rst_n) begin
			if (!rst_n || pipeline_flush || trap_ctrl_pkt.redirect ||
				ex_pc_redirect) begin
				renamed_dispatch_count_q <= '0;
				renamed_dispatch_token_q[0] <= '0;
				renamed_dispatch_token_q[1] <= '0;
				renamed_dispatch_token_q[2] <= '0;
				renamed_dispatch_token_q[3] <= '0;
			end else begin
				renamed_dispatch_count_q <= renamed_dispatch_count_d;
				renamed_dispatch_token_q[0] <= renamed_dispatch_token_d[0];
				renamed_dispatch_token_q[1] <= renamed_dispatch_token_d[1];
				renamed_dispatch_token_q[2] <= renamed_dispatch_token_d[2];
				renamed_dispatch_token_q[3] <= renamed_dispatch_token_d[3];
			end
		end

		ydrasil_issue_stage u_ydrasil_issue_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
			.flush_id_i          (pipeline_flush),
			.branch_recovery_i   (ex_pc_redirect),
			.trap_flush_i        (trap_ctrl_pkt.redirect),
			.recovery_head_slot_i(rob_head_id[PRODUCER_SLOT_WIDTH-1:0]),
			.recovery_branch_slot_i(ex_bp_train_pkt.producer_id[
				PRODUCER_SLOT_WIDTH-1:0]),
			.queue_pkt_i         (renamed_dispatch_token_q[0].pkt),
			.queue_pkt1_i        (renamed_dispatch_token_q[1].pkt),
			.queue_valid_i       (renamed_dispatch_count_q != 0),
			.queue_valid1_i      (renamed_dispatch_count_q >= 2),
			.value_alloc0_valid_i(rename_value_alloc0_valid),
			.value_alloc0_id_i   (rename_value_alloc0_id),
			.value_alloc1_valid_i(rename_value_alloc1_valid),
			.value_alloc1_id_i   (rename_value_alloc1_id),
			.completion_meta_i   (completion_meta),
			.completion_data_i   (completion_data),
			.commit_pkt_i        (commit_pkt),
			.commit_pkt1_i       (commit_pkt1),
				.retire_id0_i        (retire_value_id0),
				.retire_id1_i        (retire_value_id1),
			.lsu_idle_i          (lsu_status_pkt.idle),
		.rob_head_id_i       (rob_head_id),
			.queue_consume0_o    (issue_pipe_push),
			.queue_consume1_o    (issue_pipe_push_two),
			.issue_pkt_o         (lane_a_compact_uop),
			.issue_pkt1_o        (lane_b_compact_uop),
			.retire_value0_o     (retire_value0),
			.retire_value1_o     (retire_value1),
		.issue_ready_o       (),
		.issue_consume_two_o (issue_consume_two),
		.issue_slot1_replay_o(issue_slot1_replay),
		.issue_fence_o       (id_fence_i),
		.issue_fence_tag_o   (issue_fence_tag),
		.issue_fence_next_pc_o(issue_fence_next_pc),
		.dependency_wait_o   (issue_dependency_wait),
		.dependency_wait1_o  (issue_dependency_wait1),
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
			.dual_bit_valid_o  (dual_bit_valid),
			.dual_bit_payload_o(dual_bit_payload),
			.dual_bit_operand_a_o(dual_bit_operand_a),
			.dual_bit_operand_b_o(dual_bit_operand_b),
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
		.recovery_head_slot_i(rob_head_id[PRODUCER_SLOT_WIDTH-1:0]),
		.recovery_branch_slot_i(ex_bp_train_pkt.producer_id[
			PRODUCER_SLOT_WIDTH-1:0]),
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
		.dual_bit_valid_i   (dual_bit_valid),
		.dual_bit_payload_i (dual_bit_payload),
		.dual_bit_operand_a_i(dual_bit_operand_a),
		.dual_bit_operand_b_i(dual_bit_operand_b),
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
		.alu_result_o       (alu_result),
		.alu_rf_wen_o       (alu_rf_wen_rd),
		.alu_rf_waddr_o     (alu_rf_waddr_rd),
			.alu_producer_id_o  (alu_producer_id),
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
		.lsu_load_valid_i(dtcm_load_valid),
		.lsu_load_addr_i(dtcm_load_addr),
		.lsu_store_valid_i(dtcm_store_valid),
		.lsu_store_addr_i(dtcm_store_addr),
		.lsu_store_data_i(dtcm_store_data),
		.lsu_store_mask_i(dtcm_store_mask),
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
			.ex_no_result_due0_valid_i(ex_no_result_due0_valid),
			.ex_no_result_due0_id_i(ex_no_result_due0_id),
			.ex_no_result_due1_valid_i(ex_no_result_due1_valid),
			.ex_no_result_due1_id_i(dual_meta.producer_id),
			.ex_branch_due_valid_i(dual_bru_valid && !dual_meta.rd_wen),
			.ex_branch_due_id_i(dual_meta.producer_id),
			.serial_complete_i (serial_complete),
			.dispatch_pkt_i    (decode_backend_token_q[0].pkt),
			.dispatch_pkt1_i   (decode_backend_token_q[1].pkt),
			.decode_src0_i     (decode_backend_token_q[0].src0),
			.decode_src1_i     (decode_backend_token_q[0].src1),
			.decode_src2_i     (decode_backend_token_q[1].src0),
			.decode_src3_i     (decode_backend_token_q[1].src1),
				.decode_dst0_writes_i(decode_backend_token_q[0].pkt.dst.writes_gpr),
				.decode_dst0_addr_i(decode_backend_token_q[0].pkt.dst.rd_addr),
				.dispatch_serial_i  (decode_backend_token_q[0].serial),
				.dispatch_serial1_i (decode_backend_token_q[1].serial),
				.rename_enqueue_i (rename_dispatch_enqueue0),
			.rename_enqueue1_i(rename_dispatch_enqueue1),
				.issue_fence_i     (id_fence_i),
			.issue_fence_tag_i (issue_fence_tag),
			.completion_meta_i (completion_meta),
			.completion_rd_i   (completion_rd),
				.ex_mul_stall_i     (ex_mul_stall),
			.retire_value0_i   (retire_value0),
			.retire_value1_i   (retire_value1),
			.dispatch_pkt_o    (dispatch_issue_pkt),
			.dispatch_pkt1_o   (dispatch_issue_pkt1),
			.renamed_src0_o    (dispatch_src0),
				.renamed_src1_o    (dispatch_src1),
				.renamed_src2_o    (dispatch_src2),
				.renamed_src3_o    (dispatch_src3),
				.renamed_src0_static_ready_o(dispatch_src0_static_ready),
				.renamed_src1_static_ready_o(dispatch_src1_static_ready),
				.renamed_src2_static_ready_o(dispatch_src2_static_ready),
				.renamed_src3_static_ready_o(dispatch_src3_static_ready),
					.dispatch_ready_o  (dispatch_ready),
				.dispatch_two_ready_o(dispatch_two_ready),
			.rob_head_id_o     (rob_head_id),
			.backend_empty_o   (backend_empty),
			.ex_accept_valid_o (ex_accept_valid),
			.ex_accept_valid1_o(ex_accept_valid1),
			.retire_commit_o  (commit_pkt),
			.retire_commit1_o (commit_pkt1),
			.retire_valid_o   (retire_valid),
			.retire_valid1_o  (retire_valid1),
				.retire_value_id0_o(retire_value_id0),
				.retire_value_id1_o(retire_value_id1),
		.stall_if_o        (stall_if),
		.flush_if_o        (flush_if),
		.flush_id_o        (flush_id),
			.flush_ex_o        (flush_ex),
			.pipeline_flush_o  (pipeline_flush),
		.branch_jump_o     (branch_jump),
			.branch_target_o   (branch_target)
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
		.ex_accept_valid_i (exception_sys_accept),
		.operator_type_i   (csr_in_operator_type),
		.sys_info_i        (csr_in_sys_info),
		.illegal_instr_i   (illegal_instr_ex),
		.lane_a_valid_i    (id_ex_valid),
		.lane_a_pc_i       (id_instr_addr),
		.lane_b_valid_i    (dual_id_ex_valid),
		.lane_b_pc_i       (dual_id_ex_pc),
		.frontend_pc_i     (if_id_pc),
		.lsu_idle_i        (lsu_status_pkt.idle),
		.backend_empty_i   (backend_empty),
		.mul_stall_i       (ex_mul_stall),
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
