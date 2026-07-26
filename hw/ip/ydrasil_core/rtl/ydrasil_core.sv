

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
	wire [31:0] if_id_pred_bht_index;
	wire [ydrasil_pkg::BP_GHR_WIDTH-1:0] if_id_pred_history;
	wire        if_id_valid;
	wire [31:0] if_id1_pc;
	wire [31:0] if_id1_instr;
	wire        if_id1_pred_hit;
	wire        if_id1_pred_taken;
	wire [31:0] if_id1_pred_target;
	wire [1:0]  if_id1_pred_counter;
	wire [31:0] if_id1_pred_bht_index;
	wire [ydrasil_pkg::BP_GHR_WIDTH-1:0] if_id1_pred_history;
	wire        if_id1_valid;
	wire        if_consume_two;

	// CTRL signals
	wire                        stall_if;
	wire                        stall_id;
    wire                       stall_pc;
	wire                        flush_if;
	wire                        flush_id;
	wire                        flush_ex;
	wire                        bubble_id;
	wire                        branch_jump;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] branch_target;

	// ID <-> RF
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_raddr_rs1;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_raddr_rs2;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs1;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs2;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_raddr_rs3;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_raddr_rs4;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs3;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs4;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] fpr_raddr_rs1;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] fpr_raddr_rs2;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] fpr_raddr_rs3;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] fpr_rdata_rs1;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] fpr_rdata_rs2;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] fpr_rdata_rs3;

	// ID -> EX
	wire [31:0]                    operand_a;
	wire [31:0]                    operand_b;
	wire [31:0]                    alu_operand_a;
	wire [31:0]                    alu_operand_b;
	wire [31:0]                    bru_operand_a;
	wire [31:0]                    bru_operand_b;
	wire [31:0]                    lsu_operand_a;
	wire [31:0]                    lsu_operand_b;
	wire [31:0]                    mul_operand_a;
	wire [31:0]                    mul_operand_b;
	wire [31:0]                    csr_operand_a;
	wire [31:0]                    csr_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]     operator;
	wire [31:0]                    bt_a_operand;
	wire [31:0]                    bt_b_operand;
	ydrasil_lsu_req_pkt_t         id_lsu_req_pkt;
	ydrasil_lsu_req_pkt_t         lsu_req_pkt;
	ydrasil_fpu_req_pkt_t         id_fpu_req_pkt;
	ydrasil_fpu_req_pkt_t         fpu_req_pkt;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type;
	wire                           id_alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_rf_waddr_rd;
	wire                           id_ex_jalr;
	wire                           id_ex_alu_bypass_rs1;
	wire                           id_ex_alu_bypass_rs2;
	wire                           id_ex_dual_bypass_rs1;
	wire                           id_ex_dual_bypass_rs2;
	wire                           id_ex_load_bypass_rs1;
	wire                           id_ex_load_bypass_rs2;
	producer_id_t                  id_ex_load_bypass_producer_id;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]    id_ex_branch_target;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]    id_ex_branch_next_pc;
	wire                           id_ex_branch_eq;
	wire                           id_ex_branch_ge_signed;
	wire                           id_ex_branch_ge_unsigned;

	// EX outputs
	wire                        ex_branch_jump;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_branch_target;
	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]  ex_lsu_mem_addr;
    wire [31:0]                 ex_lsu_result;
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
	ydrasil_gpr_fwd_pkt_t       mul_completion_pkt;
	ydrasil_gpr_fwd_pkt_t       div_completion_pkt;
	wire                        ex_instret_inc;
	wire                        ex_pc_redirect;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_pc_redirect_target;
	wire                        main_pc_redirect;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] main_pc_redirect_target;
	wire                        main_bp_train_valid;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] main_bp_train_pc;
	wire                        main_bp_train_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] main_bp_train_target;
	wire [1:0]                  main_bp_train_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] main_bp_train_bht_index;
	wire [ydrasil_pkg::BP_GHR_WIDTH-1:0] main_bp_recover_history;
	wire                        main_branch_mispredict;
	wire                        ex_branch_mispredict;
	ydrasil_bp_resolve_pkt_t    main_bp_fast_resolve_pkt;
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
	wire                        bp_predict_hit;
	wire                        bp_predict_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict_target;
	wire [1:0]                  bp_predict_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict_bht_index;
	wire [ydrasil_pkg::BP_GHR_WIDTH-1:0] bp_predict_history;
	wire                        bp_predict1_hit;
	wire                        bp_predict1_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict1_target;
	wire [1:0]                  bp_predict1_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict1_bht_index;
	wire [ydrasil_pkg::BP_GHR_WIDTH-1:0] bp_predict1_history;
	ydrasil_bp_spec_update_pkt_t bp_spec_update_pkt;
	ydrasil_bp_recover_pkt_t     bp_recover_pkt;
	ydrasil_bp_train_pkt_t       bp_train_pkt;
	wire                        id_fence_i;
	wire                        id_ex_pred_hit;
	wire                        id_ex_pred_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] id_ex_pred_target;
	wire [1:0]                  id_ex_pred_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] id_ex_pred_bht_index;
	wire [ydrasil_pkg::BP_GHR_WIDTH-1:0] id_ex_pred_history;
	wire                        id_ex_valid;
	producer_id_t               id_ex_producer_id;
	wire                        id_ex_producer_tracked;
	producer_id_t               producer_alloc_id;
	wire                        producer_alloc_tracked;

	// LSU request path
	ydrasil_mem_req_pkt_t       dtcm_req_pkt;
	ydrasil_mem_req_pkt_t       mmio_req_pkt;
	ydrasil_mem_rsp_pkt_t       mmio_rsp_pkt;
	ydrasil_lsu_status_pkt_t    lsu_status_pkt;
	wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]  dtcm_wdata;
	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]  dtcm_addr;
	wire                        dtcm_we;
	wire                        dtcm_req;
	wire [3:0]                  dtcm_wmask;
	wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]  dtcm_rdata;
	wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]  mmio_wdata;
	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]  mmio_addr;
	wire                        mmio_we;
	wire                        mmio_req;
	wire [3:0]                  mmio_wmask;

	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] lsu_wb_result;
	wire                        lsu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_rf_waddr_rd;
	producer_id_t               lsu_producer_id;
	wire                        lsu_producer_tracked;
	wire                        lsu_fp_completion_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_fp_completion_addr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] lsu_fp_completion_data;

	wire                        fpu_busy;
	wire                        fpu_req_ready;
	wire                        fpu_result_valid;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] fpu_result;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] fpu_result_addr;
	wire                        fpu_result_fpr;
	wire                        fpu_result_gpr;
	producer_id_t               fpu_result_producer_id;
	wire                        fpu_result_producer_tracked;
	wire [4:0]                  fpu_result_fflags;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] fpu_result_pc;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] fpu_result_instr;
	wire                        fpu_result_ready;
	wire                        fpu_result_consumed;
	wire                        fpr_write_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] fpr_write_addr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] fpr_write_data;
	wire [2:0]                  csr_frm;
	wire                        csr_fp_enabled;
	wire                        fpu_illegal_ex;
	wire                        fpu_decode_block;
	wire                        fpu_backend_stall;
	reg                         fp_mem_busy_q;

	// WB -> RF
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd;
	wire                        rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] wb_rf_wdata_rd;
	wire                        wb_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_rf_waddr_rd;
	wire [ydrasil_pkg::REGS_NUM-1:0] rf_write_wen;
	producer_id_t               rf_producer_id;
	producer_id_t               wb_rf_producer_id;
	wire                        rf_producer_tracked;
	wire                        wb_rf_producer_tracked;
	wire                        rf_write_commit;
	wire                        wb_backpressure;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd1;
	wire                        rf_wen_rd1;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd1;
	wire [ydrasil_pkg::REGS_NUM-1:0] rf_write_wen1;
	producer_id_t               rf_producer_id1;
	wire                        rf_producer_tracked1;
	wire                        rf_write_commit1;
	wire                        wb_hzd_valid_q;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_hzd_addr_q;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] wb_hzd_data_q;

`ifdef YDRASIL_ENABLE_FPU
	reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd_q;
	reg                         rf_wen_rd_q;
	reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd_q;
	producer_id_t               rf_producer_id_q;
	reg                         rf_producer_tracked_q;
`endif

    //LSU -> CTRL
	wire                            lsu_ctrl_busy;
	wire                            lsu_fast_load;

    //LSU -> ID
	ydrasil_id_ctrl_pkt_t           id_ctrl_pkt;
	ydrasil_id_ctrl_pkt_t           id_ctrl_pkt1;
	ydrasil_ex_hzd_pkt_t            ex_hzd_pkt;
	ydrasil_ex_hzd_pkt_t            ex_hzd_pkt1;
	ydrasil_hzd_status_pkt_t        hzd_status_pkt;
	ydrasil_hzd_status_pkt_t        hzd_status_pkt1;
	ydrasil_gpr_fwd_pkt_t           wb_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           wb_fwd_pkt1;
	ydrasil_gpr_fwd_pkt_t           producer_rs1_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           producer_rs2_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           producer_rs3_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           producer_rs4_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           lsu_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           lsu_wb_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           lsu_load_bypass_pkt;
	ydrasil_gpr_fwd_pkt_t           lsu_load_bypass_q;
	ydrasil_gpr_fwd_pkt_t           lsu_load_wakeup_pkt;
`ifdef YDRASIL_ENABLE_FPU
	ydrasil_gpr_fwd_pkt_t           lsu_completion_q;
`endif
	ydrasil_gpr_fwd_pkt_t           alu_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           main_alu_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           mul_fwd_pkt;
		ydrasil_gpr_fwd_pkt_t           dual_alu_fwd_pkt;
		ydrasil_completion_bus_t        completion_bus;
		ydrasil_issue_pkt_t             issue_pkt;
		ydrasil_issue_pkt_t             issue_pkt1;
		ydrasil_operand_bypass_pkt_t    dual_bypass_issue_pkt;
		ydrasil_operand_bypass_pkt_t    dual_bypass_ex_pkt;
		ydrasil_retire_bus_t            retire_bus;
		ydrasil_gpr_commit_bus_t         gpr_commit_bus;
		ydrasil_commit_pkt_t            commit_pkt;
		ydrasil_commit_pkt_t            commit_pkt1;
		ydrasil_redirect_pkt_t          redirect_pkt;
		ydrasil_redirect_pkt_t          lsu_redirect_pkt;
		ydrasil_decode_pkt_t            decode_pkt;
	ydrasil_decode_pkt_t            decode_pkt1;
	wire                            decode_valid;
	wire                            decode_valid1;
	wire                            decode_if_ready;
	wire                            issue_ready;
	wire                            issue_consume_two;
	wire                            decode_consume_two;
	wire                            load_bypass_completion_ready;
	wire                            load_replay_stall;
	wire                            id_ex_execute_valid;
	wire                            id_ex_issue_valid;
	wire                            ex_backend_stall;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs1_addr;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs2_addr;
	wire                            id_ctrl_rs1_ren;
	wire                            id_ctrl_rs2_ren;
	wire                            id_ctrl_rd_wen;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rd_addr;
	wire                            id_ctrl_lsu_req;
	wire                            id_ctrl_store_req;
	wire                            id_ctrl_prev_alu_bypass_ok;
	wire                            scoreboard_stall;
	wire                            lsu_struct_stall;
	wire                            ex_accept_valid;
	wire                            ex_accept_valid1;
	wire                            id_ex_rd_issue;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_clear_mask;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_issue_mask;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_for_hazard;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_q;
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
	wire                            issue_store_data_ready;
	wire                            prev_alu_bypass_rs1;
		wire                            prev_alu_bypass_rs2;
		reg                             main_complete_valid_q;
		producer_id_t                   main_complete_tag_q;
		rob_tag_t                       redirect_tag_q;
		logic                           redirect_recover_q;

	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       id_csr_raddr;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr;
	wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info;

	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_ex_rdata;
	wire 					    ex_csr_wen;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      ex_csr_wdata;
	wire [1:0]                                    ex_csr_fs_wdata;
	wire                                          ex_csr_mstatus_wen;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       ex_csr_waddr;

	// Trap control packets.  Compatibility aliases remain visible to the
	// existing coverage testbench while new RTL uses the precise names.
	ydrasil_exception_req_pkt_t  exception_req_pkt;
	ydrasil_csr_trap_state_pkt_t trap_csr_state_pkt;
	ydrasil_csr_write_pkt_t      trap_csr_write_pkt;
	ydrasil_trap_ctrl_pkt_t      trap_ctrl_pkt;
	ydrasil_rob_status_pkt_t     rob_status_pkt;
	wire                             interrupt;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]      trap_redirect_addr;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]      clint_ex_int_addr;
	wire                             trap_stall;
	wire                             clint_stall;
	wire                             clint_csr_we;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] clint_csr_waddr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] clint_csr_wdata;
	wire [2:0]                       instret_inc_count;
	wire                             dual_instret_inc;
	wire [31:0]                      dual_operand_a;
	wire [31:0]                      dual_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] dual_operator;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] dual_operator_type;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] dual_rf_waddr;
	producer_id_t                    dual_id_ex_producer_id;
	wire                             dual_id_ex_producer_tracked;
	wire                             dual_id_ex_valid;
	wire [31:0]                      dual_id_ex_pc;
	wire [31:0]                      dual_id_ex_instr;
	ydrasil_branch_issue_pkt_t       dual_branch_issue_pkt;
	ydrasil_bp_resolve_pkt_t         dual_bp_fast_resolve_pkt;
	ydrasil_bp_resolve_pkt_t         dual_bp_resolve_pkt;
	wire [31:0]                      dual_commit_pc;
	wire [31:0]                      dual_commit_instr;
	producer_id_t                    producer_alloc_id1;
	wire                             producer_alloc_tracked1;

	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0] id_instr_addr;

	wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] id_op_sys_info;

`ifndef SYNTHESIS
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_alu_instr;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_lsu_instr;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_mul_instr;
	reg commit_ex_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_ex_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_ex_instr_q;
	reg commit_lsu_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_lsu_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_lsu_issue_instr_q;
	reg commit_mul_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_mul_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_mul_issue_instr_q;
	reg commit_fpu_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_fpu_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_fpu_issue_instr_q;

	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_instr;
	always_comb begin
		if ((id_instr_addr >= ydrasil_pkg::DTCM_BASE_ADDR) &&
		    (id_instr_addr < (ydrasil_pkg::DTCM_BASE_ADDR +
		     ((32'd1 << ydrasil_pkg::DTCM_ADDR_WIDTH) << 2)))) begin
			commit_instr = u_ydrasil_mems.u_dtcm.u_dram.mem_r[
				id_instr_addr[ydrasil_pkg::DTCM_ADDR_WIDTH+1:2]
			];
		end else begin
			commit_instr = u_ydrasil_mems.u_itcm.u_irom.mem_r[
				id_instr_addr[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]
			];
		end
	end
	assign commit_alu_instr = commit_instr;
	assign commit_lsu_instr = commit_instr;
	assign commit_mul_instr = commit_instr;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			commit_ex_valid_q <= 1'b0;
			commit_ex_pc_q <= '0;
			commit_ex_instr_q <= '0;
			commit_lsu_issue_valid_q <= 1'b0;
			commit_lsu_issue_pc_q <= '0;
			commit_lsu_issue_instr_q <= '0;
			commit_mul_issue_valid_q <= 1'b0;
			commit_mul_issue_pc_q <= '0;
			commit_mul_issue_instr_q <= '0;
			commit_fpu_issue_valid_q <= 1'b0;
			commit_fpu_issue_pc_q <= '0;
			commit_fpu_issue_instr_q <= '0;
		end else begin
			commit_ex_valid_q <= id_ex_execute_valid & !interrupt & !flush_ex;
			commit_ex_pc_q <= id_instr_addr;
			commit_ex_instr_q <= commit_alu_instr;
			commit_lsu_issue_valid_q <= ex_accept_valid & id_ex_execute_valid &
				operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD];
			commit_lsu_issue_pc_q <= id_instr_addr;
			commit_lsu_issue_instr_q <= commit_lsu_instr;
			commit_mul_issue_valid_q <= ex_mul_issue;
			commit_mul_issue_pc_q <= id_instr_addr;
			commit_mul_issue_instr_q <= commit_mul_instr;
			commit_fpu_issue_valid_q <= fpu_req_pkt.valid && fpu_req_ready;
			commit_fpu_issue_pc_q <= id_fpu_req_pkt.pc;
			commit_fpu_issue_instr_q <= id_fpu_req_pkt.instr;
		end
	end
`endif

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n || flush_ex)
			lsu_load_bypass_q <= '0;
		else
			lsu_load_bypass_q <= lsu_load_bypass_pkt;
	end

	wire load_bypass_current_match = lsu_load_bypass_pkt.valid &&
		lsu_load_bypass_pkt.producer_tracked &&
		(lsu_load_bypass_pkt.producer_id == id_ex_load_bypass_producer_id);
	wire load_bypass_held_match = lsu_load_bypass_q.valid &&
		lsu_load_bypass_q.producer_tracked &&
		(lsu_load_bypass_q.producer_id == id_ex_load_bypass_producer_id);
	wire load_bypass_ex_valid = load_bypass_current_match ||
		load_bypass_held_match;
	wire [REGS_DATA_WIDTH-1:0] load_bypass_ex_data =
		load_bypass_current_match ? lsu_load_bypass_pkt.data :
		lsu_load_bypass_q.data;
	assign load_bypass_completion_ready = load_bypass_ex_valid;
	assign load_replay_stall = 1'b0;
	wire fpu_csr_ex = id_ex_valid && operator_type[OPERATOR_TYPE_CSR] &&
		!operator_type[OPERATOR_TYPE_SYS] &&
		((id_ex_csr_waddr == CSR_FFLAGS) || (id_ex_csr_waddr == CSR_FRM) ||
		 (id_ex_csr_waddr == CSR_FCSR));
	wire csr_fp_enabled_ex = ex_csr_mstatus_wen ?
		(|ex_csr_fs_wdata) : csr_fp_enabled;
	assign fpu_illegal_ex =
		(id_ex_valid && operator_type[OPERATOR_TYPE_FPU] &&
		 (id_fpu_req_pkt.illegal || !csr_fp_enabled_ex ||
		  ((id_fpu_req_pkt.rm == 3'b111) && (csr_frm > 3'b100)))) ||
		(fpu_csr_ex && !csr_fp_enabled_ex);
	// 非法浮点指令仍从 issue 队列消费并交给 CLINT 触发 trap；只屏蔽执行副作用。
	// 这样可避免 FS/CSR 判定组合反馈到前端 decode/issue 关键路径。
	assign id_ex_issue_valid = id_ex_valid;
	assign id_ex_execute_valid = id_ex_issue_valid && !fpu_illegal_ex;
	assign ex_backend_stall = ex_mul_stall | load_replay_stall | fpu_backend_stall;

	assign ex_hzd_pkt.valid = id_ex_issue_valid;
	assign ex_hzd_pkt.interrupt = interrupt;
	assign ex_hzd_pkt.producer_id = id_ex_producer_id;
	assign ex_hzd_pkt.producer_tracked = id_ex_producer_tracked;
	assign ex_hzd_pkt.rd_addr = id_rf_waddr_rd;
	assign ex_hzd_pkt.alu_rf_wen = id_alu_rf_wen_rd;
	assign ex_hzd_pkt.operator_type = operator_type;
	assign ex_hzd_pkt.operator_info = operator;
	assign ex_hzd_pkt1.valid = dual_id_ex_valid;
	assign ex_hzd_pkt1.interrupt = interrupt;
	assign ex_hzd_pkt1.producer_id = dual_id_ex_producer_id;
	assign ex_hzd_pkt1.producer_tracked = dual_id_ex_producer_tracked;
	assign ex_hzd_pkt1.rd_addr = dual_rf_waddr;
	assign ex_hzd_pkt1.alu_rf_wen = dual_id_ex_producer_tracked;
	assign ex_hzd_pkt1.operator_type = dual_operator_type;
	assign ex_hzd_pkt1.operator_info = dual_operator;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n || interrupt) begin
			main_complete_valid_q <= 1'b0;
			main_complete_tag_q <= '0;
			redirect_tag_q <= '0;
			redirect_recover_q <= 1'b0;
		end else begin
			// ECALL/EBREAK/MRET remain incomplete at the ROB head until CLINT
			// finishes the trap/return sequence and flushes the window. Allowing
			// the generic ALU completion to retire them would expose younger
			// instructions while trap CSRs are still being updated.
			main_complete_valid_q <= ex_instret_inc &&
				!operator_type[OPERATOR_TYPE_SYS] &&
				!operator_type[OPERATOR_TYPE_LOAD] &&
				!operator_type[OPERATOR_TYPE_STORE] &&
				!operator_type[OPERATOR_TYPE_MUL] &&
				!operator_type[OPERATOR_TYPE_FPU];
			main_complete_tag_q <= id_ex_producer_id;
			// Capture the branch tag at the same EX1/EX2 boundary as the BRU
			// redirect registers. main_complete_tag_q is one cycle later than
			// the BRU input because it follows the registered issue outputs.
			redirect_tag_q <= id_ex_producer_id;
			redirect_recover_q <= 1'b1;
		end
	end
	assign main_alu_fwd_pkt.valid = main_complete_valid_q;
	assign main_alu_fwd_pkt.producer_id = main_complete_tag_q;
	assign main_alu_fwd_pkt.producer_tracked = main_complete_valid_q;
	assign main_alu_fwd_pkt.addr = alu_rf_waddr_rd;
	assign main_alu_fwd_pkt.data = alu_result;
	always_comb begin
		alu_fwd_pkt = main_alu_fwd_pkt;
		if (div_completion_pkt.valid)
			alu_fwd_pkt = div_completion_pkt;
	end
	// Mul and FPU share one completion lane. Arbitration is based on result
	// validity, not GPR write enable: rd=x0 multiplies and FPR-only operations
	// still have to complete their ROB entry.
	always_comb begin
		mul_fwd_pkt = '0;
		if (mul_completion_pkt.valid) begin
			mul_fwd_pkt = mul_completion_pkt;
		end else if (fpu_result_consumed) begin
			mul_fwd_pkt.valid = 1'b1;
			mul_fwd_pkt.producer_id = fpu_result_producer_id;
			mul_fwd_pkt.producer_tracked = fpu_result_producer_tracked;
			mul_fwd_pkt.addr = fpu_result_addr;
			mul_fwd_pkt.data = fpu_result;
		end
	end
	assign mul_result_valid = mul_completion_pkt.valid;
	assign mul_producer_id = mul_completion_pkt.producer_id;
	assign mul_rf_waddr_rd = mul_completion_pkt.addr;
	assign mul_wb_result = mul_completion_pkt.data;
	assign mul_rf_wen_rd = mul_completion_pkt.valid &&
		(mul_completion_pkt.addr != '0);
	assign completion_bus[ydrasil_pkg::COMPLETION_ALU] = alu_fwd_pkt;
`ifdef YDRASIL_ENABLE_FPU
	// FPU 配置增加了布局压力；仅延迟 producer 唤醒一拍，使 LSU 返回到
	// decode/scoreboard 的长控制链从靠近 decode 的寄存边界起步。
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n)
			lsu_completion_q <= '0;
		else
			lsu_completion_q <= lsu_fwd_pkt;
	end
	assign lsu_wb_fwd_pkt = lsu_completion_q;
`else
	assign lsu_wb_fwd_pkt = lsu_fwd_pkt;
`endif
	assign completion_bus[ydrasil_pkg::COMPLETION_LSU] = lsu_wb_fwd_pkt;
	assign completion_bus[ydrasil_pkg::COMPLETION_MUL] = mul_fwd_pkt;
	assign completion_bus[ydrasil_pkg::COMPLETION_DUAL_ALU] = dual_alu_fwd_pkt;
	assign wb_hzd_valid_q = wb_fwd_pkt.valid;
	assign wb_hzd_addr_q = wb_fwd_pkt.addr;
	assign wb_hzd_data_q = wb_fwd_pkt.data;
	assign id_ctrl_rs1_addr = id_ctrl_pkt.rs1_addr;
	assign id_ctrl_rs2_addr = id_ctrl_pkt.rs2_addr;
	assign id_ctrl_rs1_ren = id_ctrl_pkt.rs1_ren;
	assign id_ctrl_rs2_ren = id_ctrl_pkt.rs2_ren;
	assign id_ctrl_rd_wen = id_ctrl_pkt.rd_wen;
	assign id_ctrl_rd_addr = id_ctrl_pkt.rd_addr;
	assign id_ctrl_lsu_req = id_ctrl_pkt.lsu_req;
	assign id_ctrl_store_req = id_ctrl_pkt.store_req;
	assign id_ctrl_prev_alu_bypass_ok = id_ctrl_pkt.prev_alu_bypass_ok;
	always_comb begin
		lsu_req_pkt = id_lsu_req_pkt;
		lsu_req_pkt.valid = id_lsu_req_pkt.valid & ex_accept_valid & id_ex_execute_valid;
		lsu_req_pkt.addr = id_lsu_req_pkt.addr_valid ? ex_lsu_mem_addr : '0;
		lsu_req_pkt.store_data = ex_lsu_result;
		if (id_ex_load_bypass_rs2 && load_bypass_completion_ready) begin
			lsu_req_pkt.store_data_valid = 1'b1;
			lsu_req_pkt.store_data_producer_tracked = 1'b0;
		end
		lsu_req_pkt.addr_is_dtcm = id_lsu_req_pkt.addr_valid &&
			(ex_lsu_mem_addr[31:ydrasil_pkg::DTCM_ADDR_WIDTH+2] ==
			 ydrasil_pkg::DTCM_BASE_ADDR[31:ydrasil_pkg::DTCM_ADDR_WIDTH+2]);
		if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SB])
			lsu_req_pkt.store_mask = 4'b0001 << ex_lsu_mem_addr[1:0];
		else if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SH])
			lsu_req_pkt.store_mask = ex_lsu_mem_addr[1] ? 4'b1100 : 4'b0011;
		else if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SW])
			lsu_req_pkt.store_mask = 4'b1111;
		else
			lsu_req_pkt.store_mask = 4'b0000;
	end
`ifdef YDRASIL_ENABLE_FPU
	always_comb begin
		fpu_req_pkt = id_fpu_req_pkt;
		fpu_req_pkt.valid = id_fpu_req_pkt.valid & ex_accept_valid &
			!interrupt & !flush_ex & !fpu_illegal_ex;
	end
	assign fpu_backend_stall = id_fpu_req_pkt.valid && !fpu_req_ready;
	assign fpu_decode_block = decode_valid &&
		(decode_pkt.fp_valid ||
		 (decode_pkt.operator_type[OPERATOR_TYPE_CSR] &&
		  !decode_pkt.operator_type[OPERATOR_TYPE_SYS] &&
		  ((decode_pkt.csr_raddr == CSR_FFLAGS) || (decode_pkt.csr_raddr == CSR_FRM) ||
		   (decode_pkt.csr_raddr == CSR_FCSR)))) &&
		(fpu_busy || fp_mem_busy_q ||
		 (id_ex_valid && operator_type[OPERATOR_TYPE_FPU]));
	assign fpu_result_ready = !mul_result_valid;
	assign fpu_result_consumed = fpu_result_valid && fpu_result_ready;
	assign fpr_write_valid = lsu_fp_completion_valid ||
		(fpu_result_consumed && fpu_result_fpr);
	assign fpr_write_addr = lsu_fp_completion_valid ?
		lsu_fp_completion_addr : fpu_result_addr;
	assign fpr_write_data = lsu_fp_completion_valid ?
		lsu_fp_completion_data : fpu_result;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			fp_mem_busy_q <= 1'b0;
		end else begin
			if (ex_accept_valid && id_ex_execute_valid &&
			    operator_type[OPERATOR_TYPE_FPU] &&
			    (operator_type[OPERATOR_TYPE_LOAD] || operator_type[OPERATOR_TYPE_STORE]))
				fp_mem_busy_q <= 1'b1;
			if (lsu_fp_completion_valid ||
			    (fp_mem_busy_q && lsu_status_pkt.idle))
				fp_mem_busy_q <= 1'b0;
		end
	end
`else
	always_comb begin
		fpu_req_pkt = '0;
	end
	assign fpu_backend_stall = 1'b0;
	assign fpu_decode_block = 1'b0;
	assign fpu_result_ready = 1'b0;
	assign fpu_result_consumed = 1'b0;
	assign fpr_write_valid = 1'b0;
	assign fpr_write_addr = '0;
	assign fpr_write_data = '0;
	assign fpu_busy = 1'b0;
	assign fpu_req_ready = 1'b1;
	assign fpu_result_valid = 1'b0;
	assign fpu_result = '0;
	assign fpu_result_addr = '0;
	assign fpu_result_fpr = 1'b0;
	assign fpu_result_gpr = 1'b0;
	assign fpu_result_producer_id = '0;
	assign fpu_result_producer_tracked = 1'b0;
	assign fpu_result_fflags = '0;
	assign fpu_result_pc = '0;
	assign fpu_result_instr = '0;
	assign fpr_rdata_rs1 = '0;
	assign fpr_rdata_rs2 = '0;
	assign fpr_rdata_rs3 = '0;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) fp_mem_busy_q <= 1'b0;
		else fp_mem_busy_q <= 1'b0;
	end
`endif
	assign scoreboard_stall = 1'b0;
	assign lsu_struct_stall = lsu_status_pkt.busy;
	assign issue_store_data_ready = 1'b1;
	assign prev_alu_bypass_rs1 = 1'b0;
	assign prev_alu_bypass_rs2 = 1'b0;
	assign rs1_pending_stall = 1'b0;
	assign rs2_pending_stall = 1'b0;
	assign rd_waw_stall = 1'b0;
	assign rs1_issue_hzd = 1'b0;
	assign rs2_issue_hzd = 1'b0;
	assign rd_issue_hzd = 1'b0;
	assign issue_load_producer = 1'b0;
	assign issue_alu_producer = 1'b0;
	assign issue_mul_div_producer = 1'b0;
	assign issue_src_hzd = 1'b0;
	assign store_data_wait = 1'b0;
	assign id_ex_rd_issue = 1'b0;
	assign gpr_pending_clear_mask = '0;
	assign gpr_pending_issue_mask = '0;
	assign gpr_pending_for_hazard = '0;
`ifndef SYNTHESIS
	assign dbg_bp_predict_pc_o = bp_lookup_pc;
	assign dbg_bp_predict_hit_o = bp_predict_hit;
	assign dbg_bp_predict_taken_o = bp_predict_taken;
	assign dbg_bp_predict_target_o = bp_predict_target;
	assign dbg_bp_predict_counter_o = bp_predict_counter;
	assign dbg_bp_resolve_valid_o = dbg_bp_resolve_valid;
	assign dbg_bp_resolve_pc_o = dbg_bp_resolve_pc;
	assign dbg_bp_actual_taken_o = dbg_bp_actual_taken;
	assign dbg_bp_actual_target_o = dbg_bp_actual_target;
	assign dbg_bp_actual_next_pc_o = dbg_bp_actual_next_pc;
	assign dbg_bp_pred_hit_o = dbg_bp_pred_hit;
	assign dbg_bp_pred_taken_o = dbg_bp_pred_taken;
	assign dbg_bp_pred_target_o = dbg_bp_pred_target;
	assign dbg_bp_pred_counter_o = dbg_bp_pred_counter;
	assign dbg_bp_pred_next_pc_o = dbg_bp_pred_next_pc;
	assign dbg_bp_mispredict_o = dbg_bp_mispredict;
`endif
	assign dtcm_wdata = dtcm_req_pkt.wdata;
	assign dtcm_addr = dtcm_req_pkt.addr;
	assign dtcm_we = dtcm_req_pkt.write;
	assign dtcm_req = dtcm_req_pkt.valid;
	assign dtcm_wmask = dtcm_req_pkt.wmask;
	assign mmio_wdata = mmio_req_pkt.wdata;
	assign mmio_addr = mmio_req_pkt.addr;
	assign mmio_we = mmio_req_pkt.write;
	assign mmio_req = mmio_req_pkt.valid;
	assign mmio_wmask = mmio_req_pkt.wmask;
	assign lsu_wb_result = lsu_wb_fwd_pkt.data;
	assign lsu_rf_wen_rd = lsu_wb_fwd_pkt.valid;
	assign lsu_rf_waddr_rd = lsu_wb_fwd_pkt.addr;
	assign lsu_producer_id = lsu_wb_fwd_pkt.producer_id;
	assign lsu_producer_tracked = lsu_wb_fwd_pkt.producer_tracked;
	assign lsu_ctrl_busy = lsu_status_pkt.busy;
	assign lsu_fast_load = lsu_status_pkt.fast_load;
	assign commit_pkt = gpr_commit_bus.slot0;
	assign commit_pkt1 = gpr_commit_bus.slot1;
	assign rf_wdata_rd1 = commit_pkt1.value;
	assign rf_wen_rd1 = commit_pkt1.valid && commit_pkt1.writes_gpr;
	assign rf_waddr_rd1 = commit_pkt1.rd_addr;
	assign rf_producer_id1 = commit_pkt1.rob_tag;
	assign rf_producer_tracked1 = rf_wen_rd1;
	assign rf_wdata_rd = commit_pkt.value;
	assign rf_wen_rd = commit_pkt.valid && commit_pkt.writes_gpr;
	assign rf_waddr_rd = commit_pkt.rd_addr;
	assign rf_producer_id = commit_pkt.rob_tag;
	assign rf_producer_tracked = rf_wen_rd;

	assign interrupt = trap_ctrl_pkt.redirect;
	assign trap_redirect_addr = trap_ctrl_pkt.redirect_addr;
	assign trap_stall = trap_ctrl_pkt.stall;
	assign clint_ex_int_addr = trap_redirect_addr;
	assign clint_stall = trap_stall;
	assign clint_csr_we = trap_csr_write_pkt.valid;
	assign clint_csr_waddr = trap_csr_write_pkt.addr;
	assign clint_csr_wdata = trap_csr_write_pkt.data;
	assign instret_inc_count = {2'b0, retire_bus.slot0.valid} +
		{2'b0, retire_bus.slot1.valid} +
		{2'b0, retire_bus.slot2.valid} +
		{2'b0, retire_bus.slot3.valid} +
		{2'b0, trap_ctrl_pkt.retire};

	ydrasil_load_store_unit u_ydrasil_load_store_unit (
		.clk               (clk),
		.rst_n             (rst_n),
		.req_i             (lsu_req_pkt),
		.redirect_pkt_i    (lsu_redirect_pkt),
		.completion_bus_i  (completion_bus),
		.dtcm_rdata_i      (dtcm_rdata),
		.dtcm_req_o        (dtcm_req_pkt),
		.mmio_rsp_i        (mmio_rsp_pkt),
		.mmio_req_o        (mmio_req_pkt),
		.status_o          (lsu_status_pkt),
		.completion_o      (lsu_fwd_pkt),
		.load_bypass_o     (lsu_load_bypass_pkt),
		.load_wakeup_o     (lsu_load_wakeup_pkt),
		.fp_completion_valid_o(lsu_fp_completion_valid),
		.fp_completion_addr_o(lsu_fp_completion_addr),
		.fp_completion_data_o(lsu_fp_completion_data)
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

`ifdef YDRASIL_ENABLE_FPU
	ydrasil_fpu_registers u_ydrasil_fpu_registers (
		.clk(clk), .rst_n(rst_n),
		.write_valid_i(fpr_write_valid), .write_addr_i(fpr_write_addr),
		.write_data_i(fpr_write_data),
		.read_addr1_i(fpr_raddr_rs1), .read_addr2_i(fpr_raddr_rs2),
		.read_addr3_i(fpr_raddr_rs3),
		.read_data1_o(fpr_rdata_rs1), .read_data2_o(fpr_rdata_rs2),
		.read_data3_o(fpr_rdata_rs3)
	);

	ydrasil_fpu u_ydrasil_fpu (
		.clk(clk), .rst_n(rst_n), .req_i(fpu_req_pkt),
		.req_ready_o(fpu_req_ready), .frm_i(csr_frm),
		.result_ready_i(fpu_result_ready), .busy_o(fpu_busy),
		.result_valid_o(fpu_result_valid), .result_o(fpu_result),
		.result_addr_o(fpu_result_addr), .result_fpr_o(fpu_result_fpr),
		.result_gpr_o(fpu_result_gpr),
		.result_producer_id_o(fpu_result_producer_id),
		.result_producer_tracked_o(fpu_result_producer_tracked),
		.result_fflags_o(fpu_result_fflags), .result_pc_o(fpu_result_pc),
		.result_instr_o(fpu_result_instr)
	);
`endif

	assign ex_pc_redirect = main_pc_redirect ||
		(dual_bp_resolve_pkt.valid && dual_bp_resolve_pkt.redirect);
	assign ex_pc_redirect_target = main_pc_redirect ? main_pc_redirect_target :
		dual_bp_resolve_pkt.next_pc;
	assign ex_branch_mispredict = main_branch_mispredict ||
		(dual_bp_resolve_pkt.valid && dual_bp_resolve_pkt.redirect);

	function automatic logic [ydrasil_pkg::BP_GHR_WIDTH-1:0]
		recovered_history(input ydrasil_bp_resolve_pkt_t resolve);
		if (resolve.conditional)
			recovered_history = {
				resolve.pred_history[ydrasil_pkg::BP_GHR_WIDTH-2:0],
				resolve.taken
			};
		else
			recovered_history = resolve.pred_history;
	endfunction

	wire main_fast_redirect = main_bp_fast_resolve_pkt.valid &&
		main_bp_fast_resolve_pkt.redirect;
	wire dual_fast_redirect = !main_fast_redirect &&
		dual_bp_fast_resolve_pkt.valid && dual_bp_fast_resolve_pkt.redirect;
	// A registered redirect is always older than any new combinational result.
	wire bp_fast_redirect = !ex_pc_redirect &&
		(main_fast_redirect || dual_fast_redirect);
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_fast_redirect_target =
		main_fast_redirect ? main_bp_fast_resolve_pkt.next_pc :
		dual_bp_fast_resolve_pkt.next_pc;
	ydrasil_bp_resolve_pkt_t bp_fast_selected_pkt;
	reg bp_fast_redirect_seen_q;
	always_comb begin
		bp_fast_selected_pkt = dual_bp_fast_resolve_pkt;
		if (main_fast_redirect)
			bp_fast_selected_pkt = main_bp_fast_resolve_pkt;
	end
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n)
			bp_fast_redirect_seen_q <= 1'b0;
		else
			bp_fast_redirect_seen_q <= bp_fast_redirect;
	end

	ydrasil_bp_resolve_pkt_t bp_registered_selected_pkt;
	always_comb begin
		bp_registered_selected_pkt = dual_bp_resolve_pkt;
		if (main_pc_redirect) begin
			bp_registered_selected_pkt = '0;
			bp_registered_selected_pkt.valid = 1'b1;
			bp_registered_selected_pkt.redirect = 1'b1;
			bp_registered_selected_pkt.conditional = main_branch_mispredict;
			bp_registered_selected_pkt.pc = main_bp_train_pc;
			bp_registered_selected_pkt.taken = main_bp_train_taken;
			bp_registered_selected_pkt.next_pc = main_pc_redirect_target;
			bp_registered_selected_pkt.pred_history = main_bp_recover_history;
		end
	end
	always_comb begin
		bp_recover_pkt = '0;
		if (bp_fast_redirect) begin
			bp_recover_pkt.valid = 1'b1;
			bp_recover_pkt.history = recovered_history(bp_fast_selected_pkt);
		end else if (ex_pc_redirect && !bp_fast_redirect_seen_q) begin
			bp_recover_pkt.valid = 1'b1;
			bp_recover_pkt.history =
				recovered_history(bp_registered_selected_pkt);
		end
	end

	localparam int BP_TRAIN_QUEUE_DEPTH = 8;
	localparam int BP_TRAIN_QUEUE_COUNT_WIDTH =
		$clog2(BP_TRAIN_QUEUE_DEPTH + 1);
	ydrasil_bp_train_pkt_t bp_train_queue_q [0:BP_TRAIN_QUEUE_DEPTH-1];
	reg [BP_TRAIN_QUEUE_COUNT_WIDTH-1:0] bp_train_queue_count_q;
	ydrasil_bp_train_pkt_t main_bp_train_pkt;
	ydrasil_bp_train_pkt_t dual_bp_train_pkt;
	wire bp_train_dequeue = bp_train_queue_count_q != '0;
	wire dual_bp_train_enqueue = dual_bp_resolve_pkt.valid && !main_pc_redirect;
	wire [1:0] bp_train_enqueue_count =
		{1'b0, main_bp_train_valid} + {1'b0, dual_bp_train_enqueue};
	wire [BP_TRAIN_QUEUE_COUNT_WIDTH-1:0] bp_train_post_count =
		bp_train_queue_count_q - bp_train_dequeue;
	integer bp_train_queue_idx;
	always_comb begin
		main_bp_train_pkt = '0;
		main_bp_train_pkt.valid = main_bp_train_valid;
		main_bp_train_pkt.pc = main_bp_train_pc;
		main_bp_train_pkt.taken = main_bp_train_taken;
		main_bp_train_pkt.target = main_bp_train_target;
		main_bp_train_pkt.counter = main_bp_train_counter;
		main_bp_train_pkt.bht_index = main_bp_train_bht_index;

		dual_bp_train_pkt = '0;
		dual_bp_train_pkt.valid = dual_bp_train_enqueue;
		dual_bp_train_pkt.pc = dual_bp_resolve_pkt.pc;
		dual_bp_train_pkt.taken = dual_bp_resolve_pkt.taken;
		dual_bp_train_pkt.target = dual_bp_resolve_pkt.target;
		dual_bp_train_pkt.counter = dual_bp_resolve_pkt.pred_counter;
		dual_bp_train_pkt.bht_index = dual_bp_resolve_pkt.pred_bht_index;

		bp_train_pkt = '0;
		if (bp_train_dequeue)
			bp_train_pkt = bp_train_queue_q[0];
	end
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n || id_fence_i) begin
			bp_train_queue_count_q <= '0;
			for (bp_train_queue_idx = 0;
			     bp_train_queue_idx < BP_TRAIN_QUEUE_DEPTH;
			     bp_train_queue_idx = bp_train_queue_idx + 1)
				bp_train_queue_q[bp_train_queue_idx] <= '0;
		end else begin
			if (bp_train_dequeue) begin
				for (bp_train_queue_idx = 0;
				     bp_train_queue_idx < BP_TRAIN_QUEUE_DEPTH-1;
				     bp_train_queue_idx = bp_train_queue_idx + 1)
					bp_train_queue_q[bp_train_queue_idx] <=
						bp_train_queue_q[bp_train_queue_idx+1];
				bp_train_queue_q[BP_TRAIN_QUEUE_DEPTH-1] <= '0;
			end
			if (main_bp_train_valid)
				bp_train_queue_q[bp_train_post_count] <= main_bp_train_pkt;
			if (dual_bp_train_enqueue)
				bp_train_queue_q[bp_train_post_count + main_bp_train_valid] <=
					dual_bp_train_pkt;
			bp_train_queue_count_q <= bp_train_post_count +
				BP_TRAIN_QUEUE_COUNT_WIDTH'(bp_train_enqueue_count);
		end
	end
`ifndef SYNTHESIS
	always_ff @(posedge clk) begin
		if (rst_n && !id_fence_i)
			assert (bp_train_post_count + bp_train_enqueue_count <=
				BP_TRAIN_QUEUE_DEPTH)
				else $fatal(1, "branch predictor training queue overflow");
	end
`endif

			ydrasil_branch_predictor #(
			.BP_ENTRIES(BP_ENTRIES),
			.BTB_ENTRIES(BTB_ENTRIES),
			.BHT_ENTRIES(BHT_ENTRIES),
			.USE_GSHARE(1'b1)
		) u_ydrasil_branch_predictor (
			.clk              (clk),
			.rst_n            (rst_n),
			.predict_pc_i     (bp_lookup_pc),
			.predict_hit_o    (bp_predict_hit),
			.predict_taken_o  (bp_predict_taken),
			.predict_target_o (bp_predict_target),
			.predict_counter_o(bp_predict_counter),
			.predict_bht_index_o(bp_predict_bht_index),
			.predict_history_o(bp_predict_history),
			.spec_update_i    (bp_spec_update_pkt),
			.recover_i        (bp_recover_pkt),
			.train_i          (bp_train_pkt),
			.invalidate_i     (id_fence_i)
		);

		ydrasil_branch_predictor #(
			.BP_ENTRIES(BP_ENTRIES),
			.BTB_ENTRIES(BTB_ENTRIES),
			.BHT_ENTRIES(BHT_ENTRIES),
			.USE_GSHARE(1'b1)
		) u_ydrasil_branch_predictor1 (
			.clk(clk), .rst_n(rst_n),
			.predict_pc_i(if_mem_addr1),
			.predict_hit_o(bp_predict1_hit),
			.predict_taken_o(bp_predict1_taken),
			.predict_target_o(bp_predict1_target),
			.predict_counter_o(bp_predict1_counter),
			.predict_bht_index_o(bp_predict1_bht_index),
			.predict_history_o(bp_predict1_history),
			.spec_update_i(bp_spec_update_pkt),
			.recover_i(bp_recover_pkt),
			.train_i(bp_train_pkt),
			.invalidate_i(id_fence_i)
			);

	assign stall_id = ex_backend_stall;
	assign stall_if = !decode_if_ready || trap_stall;
	assign stall_pc = !decode_if_ready || trap_stall;
	assign bubble_id = !issue_pkt.valid || trap_stall;
	assign branch_jump = bp_fast_redirect ||
		(ex_pc_redirect && !bp_fast_redirect_seen_q);
	assign branch_target = bp_fast_redirect ? bp_fast_redirect_target :
		ex_pc_redirect_target;
	assign redirect_pkt.valid = ex_pc_redirect;
	assign redirect_pkt.recover_rob = main_pc_redirect ? redirect_recover_q :
		dual_bp_resolve_pkt.valid;
	assign redirect_pkt.rob_tag = main_pc_redirect ? redirect_tag_q :
		dual_bp_resolve_pkt.rob_tag;
	assign redirect_pkt.target = ex_pc_redirect_target;
	assign redirect_pkt.replay_valid = ex_pc_redirect && id_ex_valid;
	assign redirect_pkt.replay_tag = id_ex_producer_id;
	assign redirect_pkt.replay1_valid = ex_pc_redirect && dual_id_ex_valid;
	assign redirect_pkt.replay1_tag = dual_id_ex_producer_id;
	always_comb begin
		lsu_redirect_pkt = redirect_pkt;
		if (interrupt) begin
			lsu_redirect_pkt = '0;
			lsu_redirect_pkt.valid = 1'b1;
			lsu_redirect_pkt.target = clint_ex_int_addr;
		end
	end
	assign flush_if = branch_jump;
	assign flush_id = ex_pc_redirect;
	assign flush_ex = ex_pc_redirect;
	assign ex_accept_valid = id_ex_issue_valid && !ex_pc_redirect;
	assign ex_accept_valid1 = dual_id_ex_valid && !stall_id && !ex_pc_redirect;
	assign producer_alloc_id = issue_pkt.rob_tag;
	assign producer_alloc_tracked = issue_pkt.valid;
	assign producer_alloc_id1 = issue_pkt1.rob_tag;
	assign producer_alloc_tracked1 = issue_pkt1.valid;
	assign decode_pkt = issue_pkt.decode;
	assign decode_pkt1 = issue_pkt1.decode;
	assign decode_valid = issue_pkt.valid;
	assign decode_valid1 = issue_pkt1.valid;
	always_comb begin
		dual_bypass_issue_pkt = '0;
		dual_bypass_issue_pkt.rs1_early_alu = issue_pkt1.rs1_early_alu;
		dual_bypass_issue_pkt.rs2_early_alu = issue_pkt1.rs2_early_alu;
		dual_bypass_issue_pkt.rs1_early_dual = issue_pkt1.rs1_early_dual;
		dual_bypass_issue_pkt.rs2_early_dual = issue_pkt1.rs2_early_dual;
		dual_bypass_issue_pkt.rs1_early_load = issue_pkt1.rs1_early_load;
		dual_bypass_issue_pkt.rs2_early_load = issue_pkt1.rs2_early_load;
		dual_bypass_issue_pkt.rs1_tag = issue_pkt1.rs1_tag;
		dual_bypass_issue_pkt.rs2_tag = issue_pkt1.rs2_tag;
	end
	assign gpr_pending_q = '0;
	assign wb_fwd_pkt = '0;
	assign wb_fwd_pkt1 = '0;
	assign producer_rs1_fwd_pkt = '0;
	assign producer_rs2_fwd_pkt = '0;
	assign producer_rs3_fwd_pkt = '0;
	assign producer_rs4_fwd_pkt = '0;
	always_comb begin
		hzd_status_pkt = '0;
			hzd_status_pkt.issue_addr_ready = issue_pkt.rs1_ready;
			hzd_status_pkt.prev_alu_bypass_rs1 = issue_pkt.rs1_early_alu;
			hzd_status_pkt.prev_alu_bypass_rs2 = issue_pkt.rs2_early_alu;
			hzd_status_pkt.prev_dual_bypass_rs1 = issue_pkt.rs1_early_dual;
			hzd_status_pkt.prev_dual_bypass_rs2 = issue_pkt.rs2_early_dual;
			hzd_status_pkt.prev_load_bypass_rs1 = issue_pkt.rs1_early_load;
			hzd_status_pkt.prev_load_bypass_rs2 = issue_pkt.rs2_early_load;
			hzd_status_pkt.prev_load_producer_id = issue_pkt.rs1_early_load ?
				issue_pkt.rs1_tag : issue_pkt.rs2_tag;
		hzd_status_pkt.addr_producer_id = issue_pkt.rs1_tag;
		hzd_status_pkt.addr_producer_tracked = issue_pkt.valid &&
			(issue_pkt.decode.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] ||
			 issue_pkt.decode.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
			!issue_pkt.rs1_ready;
		// The packed issue packet carries the renamed store-data dependency
		// directly into the LSU.  This lets address-ready stores leave the ROB
		// scheduler while their data is still being produced.
		hzd_status_pkt.issue_store_data_ready = issue_pkt.rs2_ready;
		hzd_status_pkt.store_data_producer_id = issue_pkt.rs2_tag;
		hzd_status_pkt.store_data_producer_tracked = issue_pkt.valid &&
			issue_pkt.decode.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
			!issue_pkt.rs2_ready;
		hzd_status_pkt1 = '0;
		hzd_status_pkt1.issue_store_data_ready = 1'b1;
	end

			ydrasil_if_stage u_ydrasil_if_stage (
			.clk           (clk),
			.rst_n         (rst_n),
			.stall_if_i      (stall_if),
	        .stall_pc_i      (stall_pc),
			.flush_if_i      (flush_if),
			.consume_two_i   (decode_consume_two),
			.branch_jump_i   (branch_jump),
			.branch_target_i (branch_target),
			.bp_predict_hit_i(bp_predict_hit),
			.bp_predict_taken_i(bp_predict_taken),
			.bp_predict_target_i(bp_predict_target),
			.bp_predict_counter_i(bp_predict_counter),
			.bp_predict_bht_index_i(bp_predict_bht_index),
			.bp_predict_history_i(bp_predict_history),
			.bp_predict1_hit_i(bp_predict1_hit),
			.bp_predict1_taken_i(bp_predict1_taken),
			.bp_predict1_target_i(bp_predict1_target),
			.bp_predict1_counter_i(bp_predict1_counter),
			.bp_predict1_bht_index_i(bp_predict1_bht_index),
			.bp_predict1_history_i(bp_predict1_history),
			.bp_invalidate_i(id_fence_i),
			.bp_spec_update_o(bp_spec_update_pkt),
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
			.if_id_pred_history_o(if_id_pred_history),
			.if_id_valid_o   (if_id_valid),
			.if_id_instr_o   (if_id_instr)
			,.if_id1_pc_o      (if_id1_pc)
			,.if_id1_pred_hit_o(if_id1_pred_hit)
			,.if_id1_pred_taken_o(if_id1_pred_taken)
			,.if_id1_pred_target_o(if_id1_pred_target)
			,.if_id1_pred_counter_o(if_id1_pred_counter)
			,.if_id1_pred_bht_index_o(if_id1_pred_bht_index)
			,.if_id1_pred_history_o(if_id1_pred_history)
			,.if_id1_valid_o   (if_id1_valid)
			,.if_id1_instr_o   (if_id1_instr)
		);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.redirect_pkt_i      (redirect_pkt),
		.trap_ctrl_i         (trap_ctrl_pkt),
		.issue_ready_i       (issue_ready && !trap_stall),
		.lsu_ready_i         (!lsu_status_pkt.busy),
		.serial_ready_i      (lsu_status_pkt.idle && !clint_stall && !fpu_busy),
		.completion_bus_i    (completion_bus),
		.load_wakeup_i       (lsu_load_wakeup_pkt),
		.if_id_pc_i          (if_id_pc),
		.if_id_instr_i       (if_id_instr),
		.if_id_pred_hit_i    (if_id_pred_hit),
		.if_id_pred_taken_i  (if_id_pred_taken),
		.if_id_pred_target_i (if_id_pred_target),
		.if_id_pred_counter_i(if_id_pred_counter),
		.if_id_pred_bht_index_i(if_id_pred_bht_index),
		.if_id_pred_history_i(if_id_pred_history),
		.if_id_valid_i       (if_id_valid),
		.if_id1_pc_i         (if_id1_pc),
		.if_id1_instr_i      (if_id1_instr),
		.if_id1_pred_hit_i   (if_id1_pred_hit),
		.if_id1_pred_taken_i (if_id1_pred_taken),
		.if_id1_pred_target_i(if_id1_pred_target),
		.if_id1_pred_counter_i(if_id1_pred_counter),
		.if_id1_pred_bht_index_i(if_id1_pred_bht_index),
		.if_id1_pred_history_i(if_id1_pred_history),
		.if_id1_valid_i      (if_id1_valid),
		.rf_rdata_rs1_i      (rf_rdata_rs1),
		.rf_rdata_rs2_i      (rf_rdata_rs2),
		.rf_rdata_rs3_i      (rf_rdata_rs3),
		.rf_rdata_rs4_i      (rf_rdata_rs4),
		.if_id_ready_o       (decode_if_ready),
		.if_id_consume_two_o (decode_consume_two),
		.rf_addr_rs1_o       (rf_raddr_rs1),
		.rf_addr_rs2_o       (rf_raddr_rs2),
		.rf_addr_rs3_o       (rf_raddr_rs3),
		.rf_addr_rs4_o       (rf_raddr_rs4),
		.issue_pkt_o         (issue_pkt),
		.issue_pkt1_o        (issue_pkt1),
		.retire_bus_o        (retire_bus),
		.gpr_commit_bus_o     (gpr_commit_bus),
		.status_o            (rob_status_pkt)
	);

	ydrasil_issue_stage u_ydrasil_issue_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.stall_id_i          (stall_id),
		.bubble_id_i         (bubble_id | fpu_decode_block),
		.flush_id_i          (flush_id),
		.decode_valid_i      (decode_valid),
		.decode_pkt_i        (decode_pkt),
		.decode_valid1_i     (decode_valid1),
		.decode_pkt1_i       (decode_pkt1),
		.issue_ready_o       (issue_ready),
		.issue_consume_two_o (issue_consume_two),
		.rf_addr_rs1_o       (),
		.rf_addr_rs2_o       (),
		.rf_addr_rs3_o       (),
		.rf_addr_rs4_o       (),
		.rf_rdata_rs1_i     (issue_pkt.rs1_value),
		.rf_rdata_rs2_i     (issue_pkt.rs2_value),
		.rf_rdata_rs3_i     (issue_pkt1.rs1_value),
		.rf_rdata_rs4_i     (issue_pkt1.rs2_value),
		.fpr_addr_rs1_o     (fpr_raddr_rs1),
		.fpr_addr_rs2_o     (fpr_raddr_rs2),
		.fpr_addr_rs3_o     (fpr_raddr_rs3),
		.fpr_rdata_rs1_i    (fpr_rdata_rs1),
		.fpr_rdata_rs2_i    (fpr_rdata_rs2),
		.fpr_rdata_rs3_i    (fpr_rdata_rs3),
		.wb_fwd_i           (wb_fwd_pkt),
		.wb_fwd1_i          (wb_fwd_pkt1),
		.producer_rs1_fwd_i (producer_rs1_fwd_pkt),
		.producer_rs2_fwd_i (producer_rs2_fwd_pkt),
		.producer_rs3_fwd_i (producer_rs3_fwd_pkt),
		.producer_rs4_fwd_i (producer_rs4_fwd_pkt),
		.completion_bus_i   (completion_bus),
		.hzd_status_i       (hzd_status_pkt),
		.hzd_status1_i      (hzd_status_pkt1),
		.producer_alloc_id_i(issue_pkt.rob_tag),
		.producer_alloc_tracked_i(issue_pkt.valid),
		.producer_alloc_id1_i(issue_pkt1.rob_tag),
		.producer_alloc_tracked1_i(issue_pkt1.valid),
		.dual_bypass_pkt_i (dual_bypass_issue_pkt),
		.operand_a_o        (operand_a),
		.operand_b_o        (operand_b),
		.alu_operand_a_o    (alu_operand_a),
		.alu_operand_b_o    (alu_operand_b),
		.bru_operand_a_o    (bru_operand_a),
		.bru_operand_b_o    (bru_operand_b),
		.lsu_operand_a_o    (lsu_operand_a),
		.lsu_operand_b_o    (lsu_operand_b),
		.mul_operand_a_o    (mul_operand_a),
		.mul_operand_b_o    (mul_operand_b),
		.csr_operand_a_o    (csr_operand_a),
		.csr_operand_b_o    (csr_operand_b),
		.operator_o         (operator),
		.bt_a_operand_o     (bt_a_operand),
		.bt_b_operand_o     (bt_b_operand),
		.lsu_req_o          (id_lsu_req_pkt),
		.fpu_req_o          (id_fpu_req_pkt),
		.operator_type_o    (operator_type),
		.id_ctrl_o          (id_ctrl_pkt),
		.id_csr_raddr_o     (id_csr_raddr),
		.id_ex_csr_waddr_o  (id_ex_csr_waddr),
		.id_op_csr_info_o   (id_op_csr_info),
		.id_op_sys_info_o   (id_op_sys_info),
		.id_instr_addr_o    (id_instr_addr),
		.id_ex_jalr_o       (id_ex_jalr),
		.id_ex_alu_bypass_rs1_o(id_ex_alu_bypass_rs1),
		.id_ex_alu_bypass_rs2_o(id_ex_alu_bypass_rs2),
		.id_ex_dual_bypass_rs1_o(id_ex_dual_bypass_rs1),
		.id_ex_dual_bypass_rs2_o(id_ex_dual_bypass_rs2),
		.id_ex_load_bypass_rs1_o(id_ex_load_bypass_rs1),
		.id_ex_load_bypass_rs2_o(id_ex_load_bypass_rs2),
		.id_ex_load_bypass_producer_id_o(id_ex_load_bypass_producer_id),
		.id_ex_branch_target_o(id_ex_branch_target),
		.id_ex_branch_next_pc_o(id_ex_branch_next_pc),
		.id_ex_branch_eq_o  (id_ex_branch_eq),
		.id_ex_branch_ge_signed_o(id_ex_branch_ge_signed),
		.id_ex_branch_ge_unsigned_o(id_ex_branch_ge_unsigned),
		.id_fence_i_o       (id_fence_i),
		.id_ex_pred_hit_o   (id_ex_pred_hit),
		.id_ex_pred_taken_o (id_ex_pred_taken),
		.id_ex_pred_target_o(id_ex_pred_target),
		.id_ex_pred_counter_o(id_ex_pred_counter),
		.id_ex_pred_bht_index_o(id_ex_pred_bht_index),
		.id_ex_pred_history_o(id_ex_pred_history),
		.id_ex_valid_o      (id_ex_valid),
		.id_ex_producer_id_o(id_ex_producer_id),
		.id_ex_producer_tracked_o(id_ex_producer_tracked),
		.dual_operand_a_o   (dual_operand_a),
		.dual_operand_b_o   (dual_operand_b),
		.dual_operator_o    (dual_operator),
		.dual_operator_type_o(dual_operator_type),
		.dual_rf_waddr_o    (dual_rf_waddr),
		.dual_producer_id_o (dual_id_ex_producer_id),
		.dual_producer_tracked_o(dual_id_ex_producer_tracked),
		.dual_valid_o       (dual_id_ex_valid),
		.dual_pc_o          (dual_id_ex_pc),
		.dual_instr_o       (dual_id_ex_instr),
		.dual_bypass_pkt_o  (dual_bypass_ex_pkt),
		.dual_branch_pkt_o  (dual_branch_issue_pkt),
		.id_ctrl1_o         (id_ctrl_pkt1),
		.id_alu_rf_wen_rd_o (id_alu_rf_wen_rd),
		.id_rf_waddr_rd_o   (id_rf_waddr_rd)
	);

	ydrasil_ex_block u_ydrasil_ex_block (
		.clk                (clk),
		.rst_n              (rst_n),
		.flush_ex_i         (flush_ex),
		.bt_a_operand_i     (bt_a_operand),
		.bt_b_operand_i     (bt_b_operand),
		.operand_a_i        (operand_a),
		.operand_b_i        (operand_b),
		.alu_operand_a_i    (alu_operand_a),
		.alu_operand_b_i    (alu_operand_b),
		.bru_operand_a_i    (bru_operand_a),
		.bru_operand_b_i    (bru_operand_b),
		.lsu_operand_a_i    (lsu_operand_a),
		.lsu_operand_b_i    (lsu_operand_b),
		.lsu_store_data_i   (id_lsu_req_pkt.store_data),
		.mul_operand_a_i    (mul_operand_a),
		.mul_operand_b_i    (mul_operand_b),
		.csr_operand_a_i    (csr_operand_a),
		.csr_operand_b_i    (csr_operand_b),
		.operator_i         (operator),
		.operator_type_i    (operator_type),
		.id_ex_valid_i      (id_ex_execute_valid),
		.id_ex_jalr_i       (id_ex_jalr),
		.id_ex_alu_bypass_rs1_i(id_ex_alu_bypass_rs1),
		.id_ex_alu_bypass_rs2_i(id_ex_alu_bypass_rs2),
		.id_ex_dual_bypass_rs1_i(id_ex_dual_bypass_rs1),
		.id_ex_dual_bypass_rs2_i(id_ex_dual_bypass_rs2),
		.dual_bypass_valid_i(dual_alu_fwd_pkt.valid),
		.dual_bypass_data_i (dual_alu_fwd_pkt.data),
		.id_ex_load_bypass_rs1_i(id_ex_load_bypass_rs1),
		.id_ex_load_bypass_rs2_i(id_ex_load_bypass_rs2),
		.load_bypass_valid_i(load_bypass_ex_valid),
		.load_bypass_data_i(load_bypass_ex_data),
		.id_ex_branch_target_i(id_ex_branch_target),
		.id_ex_branch_next_pc_i(id_ex_branch_next_pc),
		.id_ex_branch_eq_i  (id_ex_branch_eq),
		.id_ex_branch_ge_signed_i(id_ex_branch_ge_signed),
		.id_ex_branch_ge_unsigned_i(id_ex_branch_ge_unsigned),
		.id_ex_pred_hit_i   (id_ex_pred_hit),
		.id_ex_pred_taken_i (id_ex_pred_taken),
		.id_ex_pred_target_i(id_ex_pred_target),
		.id_ex_pred_counter_i(id_ex_pred_counter),
		.id_ex_pred_bht_index_i(id_ex_pred_bht_index),
		.id_ex_pred_history_i(id_ex_pred_history),
			.trap_redirect_i   (interrupt),
			.trap_redirect_addr_i(trap_redirect_addr),
		.id_rf_waddr_rd_i   (id_rf_waddr_rd),
		.id_alu_rf_wen_rd_i (id_alu_rf_wen_rd),
		.id_ex_producer_id_i(id_ex_producer_id),
		.id_ex_csr_waddr_i  (id_ex_csr_waddr) ,
		.id_op_csr_info_i   (id_op_csr_info) ,
		.csr_ex_rdata_i     (csr_ex_rdata) ,
		.ex_csr_wen_o       (ex_csr_wen),
		.ex_csr_wdata_o     (ex_csr_wdata),
		.ex_csr_fs_wdata_o  (ex_csr_fs_wdata),
		.ex_csr_mstatus_wen_o(ex_csr_mstatus_wen),
		.ex_csr_waddr_o     (ex_csr_waddr),
		.ex_branch_jump_o   (ex_branch_jump),
		.ex_branch_target_o (ex_branch_target),
		.ex_pc_redirect_o   (main_pc_redirect),
		.ex_pc_redirect_target_o(main_pc_redirect_target),
		.ex_bp_train_valid_o(main_bp_train_valid),
		.ex_bp_train_pc_o   (main_bp_train_pc),
		.ex_bp_train_taken_o(main_bp_train_taken),
		.ex_bp_train_target_o(main_bp_train_target),
		.ex_bp_train_counter_o(main_bp_train_counter),
		.ex_bp_train_bht_index_o(main_bp_train_bht_index),
		.ex_bp_recover_history_o(main_bp_recover_history),
		.ex_branch_mispredict_o(main_branch_mispredict),
		.ex_bp_fast_resolve_o(main_bp_fast_resolve_pkt),
		.ex_lsu_mem_addr_o  (ex_lsu_mem_addr),
		.ex_lsu_result_o    (ex_lsu_result),
		.alu_result_o       (alu_result),
		.alu_rf_wen_rd_o    (alu_rf_wen_rd),
		.alu_rf_waddr_rd_o  (alu_rf_waddr_rd),
		.alu_producer_id_o  (alu_producer_id),
		.mul_issue_o        (ex_mul_issue),
		.mul_issue_waddr_o  (ex_mul_issue_waddr),
		.mul_completion_pkt_o(mul_completion_pkt),
		.div_completion_pkt_o(div_completion_pkt),
		.ex_instret_inc_o   (ex_instret_inc),
		.ex_mul_stall_o     (ex_mul_stall)
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

	wire dual_rs1_main_bypass = dual_bypass_ex_pkt.rs1_early_alu &&
		main_alu_fwd_pkt.valid && main_alu_fwd_pkt.producer_tracked &&
		(main_alu_fwd_pkt.producer_id == dual_bypass_ex_pkt.rs1_tag);
	wire dual_rs2_main_bypass = dual_bypass_ex_pkt.rs2_early_alu &&
		main_alu_fwd_pkt.valid && main_alu_fwd_pkt.producer_tracked &&
		(main_alu_fwd_pkt.producer_id == dual_bypass_ex_pkt.rs2_tag);
	wire dual_rs1_dual_bypass = dual_bypass_ex_pkt.rs1_early_dual &&
		dual_alu_fwd_pkt.valid && dual_alu_fwd_pkt.producer_tracked &&
		(dual_alu_fwd_pkt.producer_id == dual_bypass_ex_pkt.rs1_tag);
	wire dual_rs2_dual_bypass = dual_bypass_ex_pkt.rs2_early_dual &&
		dual_alu_fwd_pkt.valid && dual_alu_fwd_pkt.producer_tracked &&
		(dual_alu_fwd_pkt.producer_id == dual_bypass_ex_pkt.rs2_tag);
	wire dual_rs1_load_current = dual_bypass_ex_pkt.rs1_early_load &&
		lsu_load_bypass_pkt.valid && lsu_load_bypass_pkt.producer_tracked &&
		(lsu_load_bypass_pkt.producer_id == dual_bypass_ex_pkt.rs1_tag);
	wire dual_rs2_load_current = dual_bypass_ex_pkt.rs2_early_load &&
		lsu_load_bypass_pkt.valid && lsu_load_bypass_pkt.producer_tracked &&
		(lsu_load_bypass_pkt.producer_id == dual_bypass_ex_pkt.rs2_tag);
	wire dual_rs1_load_held = dual_bypass_ex_pkt.rs1_early_load &&
		lsu_load_bypass_q.valid && lsu_load_bypass_q.producer_tracked &&
		(lsu_load_bypass_q.producer_id == dual_bypass_ex_pkt.rs1_tag);
	wire dual_rs2_load_held = dual_bypass_ex_pkt.rs2_early_load &&
		lsu_load_bypass_q.valid && lsu_load_bypass_q.producer_tracked &&
		(lsu_load_bypass_q.producer_id == dual_bypass_ex_pkt.rs2_tag);
	wire [31:0] dual_exec_operand_a = dual_rs1_main_bypass ?
		main_alu_fwd_pkt.data : dual_rs1_dual_bypass ?
		dual_alu_fwd_pkt.data : dual_rs1_load_current ?
		lsu_load_bypass_pkt.data : dual_rs1_load_held ?
		lsu_load_bypass_q.data : dual_operand_a;
	wire [31:0] dual_exec_operand_b = dual_rs2_main_bypass ?
		main_alu_fwd_pkt.data : dual_rs2_dual_bypass ?
		dual_alu_fwd_pkt.data : dual_rs2_load_current ?
		lsu_load_bypass_pkt.data : dual_rs2_load_held ?
		lsu_load_bypass_q.data : dual_operand_b;

	ydrasil_dual_alu u_ydrasil_dual_alu (
		.clk                 (clk),
		.rst_n               (rst_n),
		.flush_i             (flush_ex),
		.interrupt_i         (interrupt),
		.valid_i             (dual_id_ex_valid && !stall_id),
		.operand_a_i         (dual_exec_operand_a),
		.operand_b_i         (dual_exec_operand_b),
		.operator_i          (dual_operator),
		.operator_type_i     (dual_operator_type),
		.rd_addr_i           (dual_rf_waddr),
		.producer_id_i       (dual_id_ex_producer_id),
		.producer_tracked_i  (dual_id_ex_producer_tracked),
		.pc_i                (dual_id_ex_pc),
		.instr_i             (dual_id_ex_instr),
		.branch_issue_i      (dual_branch_issue_pkt),
		.completion_o        (dual_alu_fwd_pkt),
		.bp_fast_resolve_o   (dual_bp_fast_resolve_pkt),
		.bp_resolve_o        (dual_bp_resolve_pkt),
		.instret_valid_o     (dual_instret_inc),
		.commit_pc_o         (dual_commit_pc),
		.commit_instr_o      (dual_commit_instr)
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

	assign wb_backpressure = 1'b0;

	ydrasil_registers u_ydrasil_registers (
		.clk          (clk),
		.rst_n        (rst_n),
		.commit_pkt_i (commit_pkt),
		.commit_pkt1_i(commit_pkt1),
		.rf_raddr_rs1_i(rf_raddr_rs1),
		.rf_rdata_rs1_o(rf_rdata_rs1),
		.rf_raddr_rs2_i(rf_raddr_rs2),
		.rf_rdata_rs2_o(rf_rdata_rs2)
		,.rf_raddr_rs3_i(rf_raddr_rs3)
		,.rf_rdata_rs3_o(rf_rdata_rs3)
		,.rf_raddr_rs4_i(rf_raddr_rs4)
		,.rf_rdata_rs4_o(rf_rdata_rs4)
		);

	ydrasil_registers_csr u_ydrasil_registers_csr (
		.clk               (clk),
		.rst_n             (rst_n),
		.instret_inc_count_i(instret_inc_count),
		.ex_csr_wen_i      (ex_csr_wen),
		.id_csr_raddr_i    (id_csr_raddr),
		.ex_csr_waddr_i    (ex_csr_waddr),
		.ex_csr_data_i     (ex_csr_wdata),
			.trap_csr_write_i (trap_csr_write_pkt),
			.irq_i            (irq_i),
		.fp_flags_valid_i  (fpu_result_consumed),
		.fp_flags_i        (fpu_result_fflags),
		.fp_state_dirty_i  (fpu_result_consumed | lsu_fp_completion_valid |
			(ex_accept_valid && operator_type[OPERATOR_TYPE_FPU] &&
			 operator_type[OPERATOR_TYPE_STORE])),
		.frm_o             (csr_frm),
		.fp_enabled_o      (csr_fp_enabled),
			.trap_state_o     (trap_csr_state_pkt),
			.csr_ex_data_o     (csr_ex_rdata)
		);

	assign exception_req_pkt.valid =
		(ex_accept_valid && operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS]) ||
		fpu_illegal_ex;
	assign exception_req_pkt.ecall = id_op_sys_info[ydrasil_pkg::OP_SYS_ECALL];
	assign exception_req_pkt.ebreak = id_op_sys_info[ydrasil_pkg::OP_SYS_EBREAK];
	assign exception_req_pkt.mret = id_op_sys_info[ydrasil_pkg::OP_SYS_MRET];
	assign exception_req_pkt.illegal = fpu_illegal_ex;
	assign exception_req_pkt.pc = id_instr_addr;
	assign exception_req_pkt.tval = fpu_illegal_ex ? id_fpu_req_pkt.instr : 32'b0;

	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] async_resume_pc =
		rob_status_pkt.resume_pc;
	wire trap_backend_idle = lsu_status_pkt.idle &&
		rob_status_pkt.execution_idle &&
		!id_ex_valid && !dual_id_ex_valid && !ex_mul_stall &&
		!wb_backpressure && !fpu_busy && !fpu_result_valid;

		ydrasil_exception_ctrl u_exception_ctrl (
			.clk               (clk),
			.rst_n             (rst_n),
			.exception_req_i   (exception_req_pkt),
			.irq_i             (irq_i),
			.csr_state_i       (trap_csr_state_pkt),
			.backend_idle_i    (trap_backend_idle),
			.async_pc_i        (async_resume_pc),
			.csr_write_o       (trap_csr_write_pkt),
			.trap_ctrl_o       (trap_ctrl_pkt)
		);

`ifndef SYNTHESIS
	ydrasil_commit_trace_rob u_ydrasil_commit_trace (
		.clk          (clk),
		.rst_n        (rst_n),
		.retire_bus_i (retire_bus)
	);
`endif



endmodule
