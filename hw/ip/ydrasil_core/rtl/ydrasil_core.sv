

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
	wire        if_id_valid;
	wire [31:0] if_id1_pc;
	wire [31:0] if_id1_instr;
	wire        if_id1_pred_hit;
	wire        if_id1_pred_taken;
	wire [31:0] if_id1_pred_target;
	wire [1:0]  if_id1_pred_counter;
	wire [31:0] if_id1_pred_bht_index;
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
	ydrasil_lsu_req_pkt_t         main_lsu_req_pkt;
	ydrasil_lsu_req_pkt_t         dual_lsu_req_pkt;
	ydrasil_fpu_req_pkt_t         id_fpu_req_pkt;
	ydrasil_fpu_req_pkt_t         fpu_req_pkt;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type;
	wire                           id_alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_rf_waddr_rd;
	wire                           id_ex_jalr;
	wire                           id_ex_alu_bypass_rs1;
	wire                           id_ex_alu_bypass_rs2;
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
	wire                        bp_predict_hit;
	wire                        bp_predict_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict_target;
	wire [1:0]                  bp_predict_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict_bht_index;
	wire                        bp_predict1_hit;
	wire                        bp_predict1_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict1_target;
	wire [1:0]                  bp_predict1_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict1_bht_index;
	// Raw BRAM predictor outputs.  The architectural prediction path first
	// consults the 16-entry FF L0-BTB and falls back to these outputs.
	wire                        bp_bram_predict_hit;
	wire                        bp_bram_predict_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict_target;
	wire [1:0]                  bp_bram_predict_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict_bht_index;
	wire                        bp_bram_predict1_hit;
	wire                        bp_bram_predict1_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict1_target;
	wire [1:0]                  bp_bram_predict1_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_bram_predict1_bht_index;
	localparam int L0_ENTRIES = 16;
	localparam int L0_INDEX_WIDTH = 4;
	reg [L0_ENTRIES-1:0] l0_valid_q;
	reg [L0_ENTRIES-1:0] l0_taken_q;
	reg [L0_ENTRIES-1:0] l0_conditional_q;
	reg [31:0] l0_target_q [0:L0_ENTRIES-1];
	reg [25:0] l0_tag_q [0:L0_ENTRIES-1];
	wire [L0_INDEX_WIDTH-1:0] l0_index = bp_lookup_pc[5:2];
	wire [25:0] l0_tag = bp_lookup_pc[31:6];
	wire [L0_INDEX_WIDTH-1:0] l0_index1 = if_mem_addr1[5:2];
	wire [25:0] l0_tag1 = if_mem_addr1[31:6];
	wire l0_hit = l0_valid_q[l0_index] && (l0_tag_q[l0_index] == l0_tag);
	wire l0_hit1 = l0_valid_q[l0_index1] && (l0_tag_q[l0_index1] == l0_tag1);
	wire                        id_fence_i;
	wire                        id_ex_pred_hit;
	wire                        id_ex_pred_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] id_ex_pred_target;
	wire [1:0]                  id_ex_pred_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] id_ex_pred_bht_index;
	wire                        id_ex_valid;
	producer_id_t               id_ex_producer_id;
	wire                        id_ex_producer_tracked;
	producer_id_t               producer_alloc_id;
	wire                        producer_alloc_tracked;

	// LSU request path
	ydrasil_dtcm_req_pkt_t      dtcm_req_pkt;
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
	wire                        wb_backpressure_unused;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd1;
	wire                        rf_wen_rd1;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd1;
	wire [ydrasil_pkg::REGS_NUM-1:0] rf_write_wen1;
	producer_id_t               rf_producer_id1;
	wire                        rf_producer_tracked1;
	wire                        rf_write_commit1;
	ydrasil_commit_pkt_t         commit_pkt;
	ydrasil_commit_pkt_t         commit_pkt1;
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
	assign id_ctrl_pkt = id_issue_pkt.ctrl;
	assign id_ctrl_pkt1 = id_issue_pkt1.ctrl;
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
`ifdef YDRASIL_ENABLE_FPU
	ydrasil_gpr_fwd_pkt_t           lsu_completion_q;
`endif
	ydrasil_gpr_fwd_pkt_t           alu_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           mul_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           dual_alu_fwd_pkt;
	ydrasil_completion_bus_t        completion_bus;
	ydrasil_issue_pkt_t             id_issue_pkt;
	ydrasil_issue_pkt_t             id_issue_pkt1;
	ydrasil_issue_pkt_t             issue_pkt;
	ydrasil_issue_pkt_t             issue_pkt1;
	ydrasil_issue_wb_pkt_t          issue_wb_pkt;
	always_comb begin
		issue_pkt = id_issue_pkt;
		issue_pkt.schedule.hazard = hzd_status_pkt;
		issue_pkt.schedule.src1 = producer_rs1_fwd_pkt;
		issue_pkt.schedule.src2 = producer_rs2_fwd_pkt;
		issue_pkt.schedule.producer_id = producer_alloc_id;
		issue_pkt.schedule.producer_tracked = producer_alloc_tracked;
		issue_pkt1 = id_issue_pkt1;
		issue_pkt1.schedule.hazard = hzd_status_pkt1;
		issue_pkt1.schedule.src1 = producer_rs3_fwd_pkt;
		issue_pkt1.schedule.src2 = producer_rs4_fwd_pkt;
		issue_pkt1.schedule.producer_id = producer_alloc_id1;
		issue_pkt1.schedule.producer_tracked = producer_alloc_tracked1;
	end
	assign issue_wb_pkt.wb0 = wb_fwd_pkt;
	assign issue_wb_pkt.wb1 = wb_fwd_pkt1;
	wire                            decode_valid = issue_pkt.valid;
	ydrasil_decode_pkt_t            decode_pkt;
	assign decode_pkt = issue_pkt.decode;
	wire                            decode_if_ready;
	wire                            issue_ready;
	wire                            issue_consume_two;
	wire                            decode_consume_two;
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
	wire                            prev_alu_bypass_rs1;
	wire                            prev_alu_bypass_rs2;

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
	wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] dual_operator_lsu;
	wire [31:0]                      dual_store_data;
	wire                             dual_store_data_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] dual_rf_waddr;
	producer_id_t                    dual_id_ex_producer_id;
	wire                             dual_id_ex_producer_tracked;
	wire                             dual_id_ex_valid;
	wire [31:0]                      dual_id_ex_pc;
	wire [31:0]                      dual_id_ex_instr;
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
	reg commit_dual_lsu_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_dual_lsu_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_dual_lsu_issue_instr_q;
	reg commit_mul_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_mul_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_mul_issue_instr_q;
	reg commit_fpu_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_fpu_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_fpu_issue_instr_q;

	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_instr;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] retire_instr;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] retire_instr1;
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
	always_comb begin
		if ((commit_pkt.pc >= ydrasil_pkg::DTCM_BASE_ADDR) &&
		    (commit_pkt.pc < (ydrasil_pkg::DTCM_BASE_ADDR +
		     ((32'd1 << ydrasil_pkg::DTCM_ADDR_WIDTH) << 2)))) begin
			retire_instr = u_ydrasil_mems.u_dtcm.u_dram.mem_r[
				commit_pkt.pc[ydrasil_pkg::DTCM_ADDR_WIDTH+1:2]
			];
		end else begin
			retire_instr = u_ydrasil_mems.u_itcm.u_irom.mem_r[
				commit_pkt.pc[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]
			];
		end
		if ((commit_pkt1.pc >= ydrasil_pkg::DTCM_BASE_ADDR) &&
		    (commit_pkt1.pc < (ydrasil_pkg::DTCM_BASE_ADDR +
		     ((32'd1 << ydrasil_pkg::DTCM_ADDR_WIDTH) << 2)))) begin
			retire_instr1 = u_ydrasil_mems.u_dtcm.u_dram.mem_r[
				commit_pkt1.pc[ydrasil_pkg::DTCM_ADDR_WIDTH+1:2]
			];
		end else begin
			retire_instr1 = u_ydrasil_mems.u_itcm.u_irom.mem_r[
				commit_pkt1.pc[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]
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
			commit_dual_lsu_issue_valid_q <= 1'b0;
			commit_dual_lsu_issue_pc_q <= '0;
			commit_dual_lsu_issue_instr_q <= '0;
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
			commit_dual_lsu_issue_valid_q <= dual_lsu_req_pkt.valid &&
				dual_lsu_req_pkt.is_load;
			commit_dual_lsu_issue_pc_q <= dual_id_ex_pc;
			commit_dual_lsu_issue_instr_q <= dual_id_ex_instr;
			commit_mul_issue_valid_q <= ex_mul_issue;
			commit_mul_issue_pc_q <= id_instr_addr;
			commit_mul_issue_instr_q <= commit_mul_instr;
			commit_fpu_issue_valid_q <= fpu_req_pkt.valid && fpu_req_ready;
			commit_fpu_issue_pc_q <= id_fpu_req_pkt.pc;
			commit_fpu_issue_instr_q <= id_fpu_req_pkt.instr;
		end
	end
`endif

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
	assign ex_backend_stall = ex_mul_stall | fpu_backend_stall;

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
	assign slow_wb_result = mul_rf_wen_rd ? mul_wb_result : fpu_result;
	assign slow_rf_wen_rd = mul_rf_wen_rd | (fpu_result_consumed & fpu_result_gpr);
	assign slow_rf_waddr_rd = mul_rf_wen_rd ? mul_rf_waddr_rd : fpu_result_addr;
	assign slow_producer_id = mul_rf_wen_rd ? mul_producer_id : fpu_result_producer_id;
	assign mul_fwd_pkt.valid = slow_rf_wen_rd;
	assign mul_fwd_pkt.producer_id = slow_producer_id;
	assign mul_fwd_pkt.producer_tracked = mul_fwd_pkt.valid && (mul_fwd_pkt.addr != '0);
	assign mul_fwd_pkt.addr = slow_rf_waddr_rd;
	assign mul_fwd_pkt.data = slow_wb_result;
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
		main_lsu_req_pkt = id_lsu_req_pkt;
		main_lsu_req_pkt.valid = id_lsu_req_pkt.valid & ex_accept_valid & id_ex_execute_valid;
		main_lsu_req_pkt.addr = ex_lsu_mem_addr;
		main_lsu_req_pkt.store_data = ex_lsu_result;
		main_lsu_req_pkt.addr_is_dtcm =
			(ex_lsu_mem_addr[31:ydrasil_pkg::DTCM_ADDR_WIDTH+2] ==
			 ydrasil_pkg::DTCM_BASE_ADDR[31:ydrasil_pkg::DTCM_ADDR_WIDTH+2]);
		if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SB])
				main_lsu_req_pkt.store_mask = 4'b0001 << ex_lsu_mem_addr[1:0];
		else if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SH])
				main_lsu_req_pkt.store_mask = ex_lsu_mem_addr[1] ? 4'b1100 : 4'b0011;
		else if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SW])
				main_lsu_req_pkt.store_mask = 4'b1111;
		else
				main_lsu_req_pkt.store_mask = 4'b0000;
		lsu_req_pkt = dual_lsu_req_pkt.valid ? dual_lsu_req_pkt :
			main_lsu_req_pkt;
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
	assign fpu_result_ready = fpu_result_fpr ||
		(fpu_result_gpr && !mul_rf_wen_rd && !wb_backpressure);
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
	assign scoreboard_stall = hzd_status_pkt.scoreboard_stall;
	assign lsu_struct_stall = hzd_status_pkt.lsu_struct_stall;
	assign prev_alu_bypass_rs1 = hzd_status_pkt.prev_alu_bypass_rs1;
	assign prev_alu_bypass_rs2 = hzd_status_pkt.prev_alu_bypass_rs2;
	assign rs1_pending_stall = hzd_status_pkt.rs1_pending_stall;
	assign rs2_pending_stall = hzd_status_pkt.rs2_pending_stall;
	assign rd_waw_stall = hzd_status_pkt.rd_waw_stall;
	assign rs1_issue_hzd = hzd_status_pkt.rs1_issue_hzd;
	assign rs2_issue_hzd = hzd_status_pkt.rs2_issue_hzd;
	assign rd_issue_hzd = hzd_status_pkt.rd_issue_hzd;
	assign issue_load_producer = hzd_status_pkt.issue_load_producer;
	assign issue_alu_producer = hzd_status_pkt.issue_alu_producer;
	assign issue_mul_div_producer = hzd_status_pkt.issue_mul_div_producer;
	assign issue_src_hzd = hzd_status_pkt.issue_src_hzd;
	assign store_data_wait = hzd_status_pkt.store_data_wait;
	assign id_ex_rd_issue = hzd_status_pkt.id_ex_rd_issue;
	assign gpr_pending_clear_mask = hzd_status_pkt.gpr_pending_clear_mask;
	assign gpr_pending_issue_mask = hzd_status_pkt.gpr_pending_issue_mask;
	assign gpr_pending_for_hazard = hzd_status_pkt.gpr_pending_for_hazard;
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
	assign dtcm_wdata = dtcm_req_pkt.store.wdata;
	assign dtcm_addr = dtcm_req_pkt.store.addr;
	assign dtcm_we = dtcm_req_pkt.store.valid;
	assign dtcm_req = dtcm_req_pkt.load.valid | dtcm_req_pkt.store.valid;
	assign dtcm_wmask = dtcm_req_pkt.store.wmask;
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
	assign rf_wdata_rd1 = dual_alu_fwd_pkt.data;
	assign rf_wen_rd1 = dual_alu_fwd_pkt.valid;
	assign rf_waddr_rd1 = dual_alu_fwd_pkt.addr;
	assign rf_producer_id1 = dual_alu_fwd_pkt.producer_id;
	assign rf_producer_tracked1 = dual_alu_fwd_pkt.producer_tracked;

`ifdef YDRASIL_ENABLE_FPU
	// 将写回仲裁与高扇出的 GPR 写使能译码隔开，避免 FPU 面积增加后
	// MUL FIFO 状态跨越核心到寄存器堆形成 200 MHz 关键路径。
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			rf_wdata_rd_q <= '0;
			rf_wen_rd_q <= 1'b0;
			rf_waddr_rd_q <= '0;
			rf_producer_id_q <= '0;
			rf_producer_tracked_q <= 1'b0;
		end else begin
			rf_wdata_rd_q <= wb_rf_wdata_rd;
			rf_wen_rd_q <= wb_rf_wen_rd;
			rf_waddr_rd_q <= wb_rf_waddr_rd;
			rf_producer_id_q <= wb_rf_producer_id;
			rf_producer_tracked_q <= wb_rf_producer_tracked;
		end
	end
	assign rf_wdata_rd = rf_wdata_rd_q;
	assign rf_wen_rd = rf_wen_rd_q;
	assign rf_waddr_rd = rf_waddr_rd_q;
	assign rf_producer_id = rf_producer_id_q;
	assign rf_producer_tracked = rf_producer_tracked_q;
`else
	assign rf_wdata_rd = wb_rf_wdata_rd;
	assign rf_wen_rd = wb_rf_wen_rd;
	assign rf_waddr_rd = wb_rf_waddr_rd;
	assign rf_producer_id = wb_rf_producer_id;
	assign rf_producer_tracked = wb_rf_producer_tracked;
`endif

	assign interrupt = trap_ctrl_pkt.redirect;
	assign trap_redirect_addr = trap_ctrl_pkt.redirect_addr;
	assign trap_stall = trap_ctrl_pkt.stall;
	assign clint_ex_int_addr = trap_redirect_addr;
	assign clint_stall = trap_stall;
	assign clint_csr_we = trap_csr_write_pkt.valid;
	assign clint_csr_waddr = trap_csr_write_pkt.addr;
	assign clint_csr_wdata = trap_csr_write_pkt.data;
	assign instret_inc_count = {2'b0, commit_pkt.valid} +
		{2'b0, commit_pkt1.valid};

	ydrasil_load_store_unit u_ydrasil_load_store_unit (
		.clk               (clk),
		.rst_n             (rst_n),
		.req_i             (lsu_req_pkt),
		.dtcm_rdata_i      (dtcm_rdata),
		.dtcm_req_o        (dtcm_req_pkt),
		.mmio_rsp_i        (mmio_rsp_pkt),
		.mmio_req_o        (mmio_req_pkt),
		.status_o          (lsu_status_pkt),
		.completion_o      (lsu_fwd_pkt),
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
			.predict0_spec_valid_i(l0_hit),
			.predict0_spec_conditional_i(l0_conditional_q[l0_index]),
			.predict0_spec_taken_i(l0_taken_q[l0_index]),
			.predict_pc1_i    (if_mem_addr1),
			.predict1_hit_o   (bp_bram_predict1_hit),
			.predict1_taken_o (bp_bram_predict1_taken),
			.predict1_target_o(bp_bram_predict1_target),
			.predict1_counter_o(bp_bram_predict1_counter),
			.predict1_bht_index_o(bp_bram_predict1_bht_index),
			.train_i          (ex_bp_train_pkt),
			.invalidate_i     (id_fence_i)
		);

	// L0-BTB is a small FF array in F1.  Training is synchronous with the
	// shared BRAM predictor, so a hit costs no extra cycle and a stale entry is
	// invalidated by the same fence/redirect epoch.
	integer l0_idx;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n || id_fence_i) begin
			l0_valid_q <= '0;
			l0_conditional_q <= '0;
			for (l0_idx = 0; l0_idx < L0_ENTRIES; l0_idx = l0_idx + 1) begin
				l0_taken_q[l0_idx] <= 1'b0;
				l0_target_q[l0_idx] <= '0;
				l0_tag_q[l0_idx] <= '0;
			end
		end else if (ex_bp_train_pkt.valid) begin
			l0_valid_q[ex_bp_train_pkt.pc[5:2]] <= 1'b1;
			l0_taken_q[ex_bp_train_pkt.pc[5:2]] <= ex_bp_train_pkt.taken;
			l0_conditional_q[ex_bp_train_pkt.pc[5:2]] <= ex_bp_train_pkt.conditional;
			l0_target_q[ex_bp_train_pkt.pc[5:2]] <= ex_bp_train_pkt.target;
			l0_tag_q[ex_bp_train_pkt.pc[5:2]] <= ex_bp_train_pkt.pc[31:6];
		end
	end

	assign bp_predict_hit = bp_bram_predict_hit;
	assign bp_predict_taken = bp_bram_predict_taken;
	assign bp_predict_target = bp_bram_predict_target;
	assign bp_predict_counter = bp_bram_predict_counter;
	assign bp_predict_bht_index = bp_bram_predict_bht_index;
	assign bp_predict1_hit = bp_bram_predict1_hit;
	assign bp_predict1_taken = bp_bram_predict1_taken;
	assign bp_predict1_target = bp_bram_predict1_target;
	assign bp_predict1_counter = bp_bram_predict1_counter;
	assign bp_predict1_bht_index = bp_bram_predict1_bht_index;

		ydrasil_if_stage u_ydrasil_if_stage (
			.clk           (clk),
			.rst_n         (rst_n),
			.stall_if_i      (!decode_if_ready),
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
			.bp_predict1_hit_i(bp_predict1_hit),
			.bp_predict1_taken_i(bp_predict1_taken),
			.bp_predict1_target_i(bp_predict1_target),
			.bp_predict1_counter_i(bp_predict1_counter),
			.bp_predict1_bht_index_i(bp_predict1_bht_index),
			.l0_predict_hit_i(l0_hit),
			.l0_predict_taken_i(l0_taken_q[l0_index]),
			.l0_predict_target_i(l0_target_q[l0_index]),
			.l0_predict1_hit_i(l0_hit1),
			.l0_predict1_taken_i(l0_taken_q[l0_index1]),
			.l0_predict1_target_i(l0_target_q[l0_index1]),
			.bp_invalidate_i(id_fence_i),
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
			,.if_id1_pc_o      (if_id1_pc)
			,.if_id1_pred_hit_o(if_id1_pred_hit)
			,.if_id1_pred_taken_o(if_id1_pred_taken)
			,.if_id1_pred_target_o(if_id1_pred_target)
			,.if_id1_pred_counter_o(if_id1_pred_counter)
			,.if_id1_pred_bht_index_o(if_id1_pred_bht_index)
			,.if_id1_valid_o   (if_id1_valid)
			,.if_id1_instr_o   (if_id1_instr)
		);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.flush_i             (flush_id),
		.issue_ready_i       (issue_ready),
		.issue_consume_two_i (issue_consume_two),
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
		.bubble_id_i         (bubble_id | fpu_decode_block),
		.flush_id_i          (flush_id),
		.issue_pkt_i         (issue_pkt),
		.issue_pkt1_i        (issue_pkt1),
		.issue_ready_o       (issue_ready),
		.issue_consume_two_o (issue_consume_two),
		.rf_addr_rs1_o       (rf_raddr_rs1),
		.rf_addr_rs2_o      (rf_raddr_rs2),
		.rf_addr_rs3_o      (rf_raddr_rs3),
		.rf_addr_rs4_o      (rf_raddr_rs4),
		.rf_rdata_rs1_i     (rf_rdata_rs1),
		.rf_rdata_rs2_i     (rf_rdata_rs2),
		.rf_rdata_rs3_i     (rf_rdata_rs3),
		.rf_rdata_rs4_i     (rf_rdata_rs4),
		.fpr_addr_rs1_o     (fpr_raddr_rs1),
		.fpr_addr_rs2_o     (fpr_raddr_rs2),
		.fpr_addr_rs3_o     (fpr_raddr_rs3),
		.fpr_rdata_rs1_i    (fpr_rdata_rs1),
		.fpr_rdata_rs2_i    (fpr_rdata_rs2),
		.fpr_rdata_rs3_i    (fpr_rdata_rs3),
		.issue_wb_i         (issue_wb_pkt),
		.completion_bus_i   (completion_bus),
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
		.id_csr_raddr_o     (id_csr_raddr),
		.id_ex_csr_waddr_o  (id_ex_csr_waddr),
		.id_op_csr_info_o   (id_op_csr_info),
		.id_op_sys_info_o   (id_op_sys_info),
		.id_instr_addr_o    (id_instr_addr),
		.id_ex_jalr_o       (id_ex_jalr),
		.id_ex_alu_bypass_rs1_o(id_ex_alu_bypass_rs1),
		.id_ex_alu_bypass_rs2_o(id_ex_alu_bypass_rs2),
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
		.id_ex_valid_o      (id_ex_valid),
		.id_ex_producer_id_o(id_ex_producer_id),
		.id_ex_producer_tracked_o(id_ex_producer_tracked),
		.dual_operand_a_o   (dual_operand_a),
		.dual_operand_b_o   (dual_operand_b),
		.dual_operator_o    (dual_operator),
		.dual_operator_type_o(dual_operator_type),
		.dual_operator_lsu_o(dual_operator_lsu),
		.dual_store_data_o  (dual_store_data),
		.dual_store_data_valid_o(dual_store_data_valid),
		.dual_rf_waddr_o    (dual_rf_waddr),
		.dual_producer_id_o (dual_id_ex_producer_id),
		.dual_producer_tracked_o(dual_id_ex_producer_tracked),
		.dual_valid_o       (dual_id_ex_valid),
		.dual_pc_o          (dual_id_ex_pc),
		.dual_instr_o       (dual_id_ex_instr),
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
		.ex_pc_redirect_o   (ex_pc_redirect),
		.ex_pc_redirect_target_o(ex_pc_redirect_target),
		.ex_bp_train_o      (ex_bp_train_pkt),
		.ex_branch_mispredict_o(ex_branch_mispredict),
		.ex_lsu_mem_addr_o  (ex_lsu_mem_addr),
		.ex_lsu_result_o    (ex_lsu_result),
		.alu_result_o       (alu_result),
		.alu_rf_wen_rd_o    (alu_rf_wen_rd),
		.alu_rf_waddr_rd_o  (alu_rf_waddr_rd),
			.alu_producer_id_o  (alu_producer_id),
			.completion_o       (alu_fwd_pkt),
		.mul_issue_o        (ex_mul_issue),
		.mul_issue_waddr_o  (ex_mul_issue_waddr),
		.mul_wdata_rd_o     (mul_wb_result),
		.mul_rf_wen_rd_o    (mul_rf_wen_rd),
		.mul_rf_waddr_rd_o  (mul_rf_waddr_rd),
		.mul_producer_id_o  (mul_producer_id),
		.mul_result_valid_o (mul_result_valid),
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

	ydrasil_dual_alu u_ydrasil_dual_alu (
		.clk                 (clk),
		.rst_n               (rst_n),
		.flush_i             (flush_ex),
		.interrupt_i         (interrupt),
		.valid_i             (ex_accept_valid1),
		.operand_a_i         (dual_operand_a),
		.operand_b_i         (dual_operand_b),
		.operator_i          (dual_operator),
		.operator_type_i     (dual_operator_type),
		.operator_lsu_i      (dual_operator_lsu),
		.store_data_i        (dual_store_data),
		.store_data_valid_i  (dual_store_data_valid),
		.rd_addr_i           (dual_rf_waddr),
		.producer_id_i       (dual_id_ex_producer_id),
		.producer_tracked_i  (dual_id_ex_producer_tracked),
		.pc_i                (dual_id_ex_pc),
		.instr_i             (dual_id_ex_instr),
		.completion_o        (dual_alu_fwd_pkt),
		.lsu_req_o           (dual_lsu_req_pkt),
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

	ydrasil_wb_stage u_ydrasil_wb_stage (
		.clk              (clk),
		.rst_n            (rst_n),
		.alu_wdata_rd_i   (alu_result),
		.alu_rf_wen_rd_i  (alu_rf_wen_rd),
		.alu_rf_waddr_rd_i(alu_rf_waddr_rd),
		.alu_producer_id_i(alu_producer_id),
		.lsu_wb_result_i  (lsu_wb_result),
		.lsu_rf_wen_rd_i  (lsu_rf_wen_rd),
		.lsu_rf_waddr_rd_i(lsu_rf_waddr_rd),
		.lsu_producer_id_i(lsu_producer_id),
		.lsu_producer_tracked_i(lsu_producer_tracked),
		.mul_wdata_rd_i   (slow_wb_result),
		.mul_rf_wen_rd_i  (slow_rf_wen_rd),
		.mul_rf_waddr_rd_i(slow_rf_waddr_rd),
		.mul_producer_id_i(slow_producer_id),
		.wb_mul_complete_o(),
		.wb_mul_complete_waddr_o(),
		.wb_backpressure_o(wb_backpressure_unused),
		.rf_wdata_rd_o    (wb_rf_wdata_rd),
		.rf_wen_rd_o      (wb_rf_wen_rd),
		.rf_waddr_rd_o    (wb_rf_waddr_rd),
		.rf_producer_id_o (wb_rf_producer_id)
		,.rf_producer_tracked_o(wb_rf_producer_tracked)
	);
	// Completion visibility is provided by the four-lane Future File broadcast;
	// ARF writes now come from the two-wide retirement ROB, so WB arbitration
	// cannot exert architectural backpressure.
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

		ydrasil_ctrl u_ctrl (
			.clk               (clk),
			.rst_n             (rst_n),
			.ex_branch_jump_i  (ex_pc_redirect),
			.ex_branch_resolve_i(ex_bp_train_pkt.valid && ex_bp_train_pkt.conditional),
			.ex_branch_target_i(ex_pc_redirect_target),
			.ex_pc_i           (id_instr_addr),
			.ex_pc1_i          (dual_id_ex_pc),
			.ex_hzd_i          (ex_hzd_pkt),
			.ex_hzd1_i         (ex_hzd_pkt1),
			.id_ctrl_i         (id_ctrl_pkt),
			.id_ctrl1_i        (id_ctrl_pkt1),
			.completion_bus_i  (completion_bus),
			.lsu_status_i      (lsu_status_pkt),
				.trap_stall_i      (trap_stall),
			.ex_mul_stall_i     (ex_backend_stall),
			.wb_backpressure_i  (wb_backpressure),
			.rf_wen_rd_i       (rf_wen_rd),
			.rf_waddr_rd_i     (rf_waddr_rd),
			.rf_wdata_rd_i     (rf_wdata_rd),
			.rf_producer_id_i  (rf_producer_id),
			.rf_producer_tracked_i(rf_producer_tracked),
			.rf_wen_rd1_i      (rf_wen_rd1),
			.rf_waddr_rd1_i    (rf_waddr_rd1),
			.rf_wdata_rd1_i    (rf_wdata_rd1),
			.rf_producer_id1_i (rf_producer_id1),
			.rf_producer_tracked1_i(rf_producer_tracked1),
			.hzd_status_o      (hzd_status_pkt),
			.hzd_status1_o     (hzd_status_pkt1),
			.wb_fwd_o          (wb_fwd_pkt),
			.wb_fwd1_o         (wb_fwd_pkt1),
			.producer_rs1_fwd_o(producer_rs1_fwd_pkt),
			.producer_rs2_fwd_o(producer_rs2_fwd_pkt),
			.producer_rs3_fwd_o(producer_rs3_fwd_pkt),
			.producer_rs4_fwd_o(producer_rs4_fwd_pkt),
			.gpr_pending_o     (gpr_pending_q),
			.ex_accept_valid_o (ex_accept_valid),
			.ex_accept_valid1_o(ex_accept_valid1),
			.producer_alloc_id_o(producer_alloc_id),
			.producer_alloc_tracked_o(producer_alloc_tracked),
			.producer_alloc_id1_o(producer_alloc_id1),
			.producer_alloc_tracked1_o(producer_alloc_tracked1),
			.rf_write_commit_o(rf_write_commit),
			.rf_write_wen_o   (rf_write_wen),
			.rf_write_commit1_o(rf_write_commit1),
			.rf_write_wen1_o  (rf_write_wen1),
			.retire_commit_o  (commit_pkt),
			.retire_commit1_o (commit_pkt1),
		.stall_if_o        (stall_if),
		.stall_id_o        (stall_id),
        .stall_pc_o        (stall_pc),
		.bubble_id_o       (bubble_id),
		.flush_if_o        (flush_if),
		.flush_id_o        (flush_id),
		.flush_ex_o        (flush_ex),
		.branch_jump_o     (branch_jump),
		.branch_target_o   (branch_target)
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
		dual_id_ex_valid ? (dual_id_ex_pc + 32'd4) :
		id_ex_valid ? (id_instr_addr + 32'd4) : if_id_pc;
	wire trap_backend_idle = lsu_status_pkt.idle && !(|gpr_pending_q) &&
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
	ydrasil_commit_trace u_ydrasil_commit_trace (
		.clk              (clk),
		.rst_n            (rst_n),
		.alu_valid_i      (commit_ex_valid_q & alu_rf_wen_rd),
		.alu_pc_i         (commit_ex_pc_q),
		.alu_instr_i      (commit_ex_instr_q),
		.alu_waddr_i      (alu_rf_waddr_rd),
		.alu_wdata_i      (alu_result),
		.dual_alu_valid_i(dual_alu_fwd_pkt.valid),
		.dual_alu_pc_i   (dual_commit_pc),
		.dual_alu_instr_i(dual_commit_instr),
			.dual_alu_waddr_i(dual_alu_fwd_pkt.addr),
			.dual_alu_wdata_i(dual_alu_fwd_pkt.data),
			.dual_lsu_issue_valid_i(commit_dual_lsu_issue_valid_q),
			.dual_lsu_issue_pc_i(commit_dual_lsu_issue_pc_q),
			.dual_lsu_issue_instr_i(commit_dual_lsu_issue_instr_q),
			.lsu_issue_valid_i(commit_lsu_issue_valid_q),
		.lsu_issue_pc_i   (commit_lsu_issue_pc_q),
		.lsu_issue_instr_i(commit_lsu_issue_instr_q),
		.lsu_valid_i      (lsu_rf_wen_rd),
		.lsu_waddr_i      (lsu_rf_waddr_rd),
		.lsu_wdata_i      (lsu_wb_result),
		.lsu_fp_valid_i   (lsu_fp_completion_valid),
		.lsu_fp_waddr_i   (lsu_fp_completion_addr),
		.lsu_fp_wdata_i   (lsu_fp_completion_data),
		.mul_issue_valid_i(commit_mul_issue_valid_q),
		.mul_issue_pc_i   (commit_mul_issue_pc_q),
		.mul_issue_instr_i(commit_mul_issue_instr_q),
		.mul_valid_i      (mul_rf_wen_rd),
		.mul_waddr_i      (mul_rf_waddr_rd),
		.mul_wdata_i      (mul_wb_result),
		.fpu_issue_valid_i(commit_fpu_issue_valid_q),
		.fpu_issue_pc_i   (commit_fpu_issue_pc_q),
		.fpu_issue_instr_i(commit_fpu_issue_instr_q),
		.fpu_valid_i      (fpu_result_consumed),
		.fpu_result_fpr_i (fpu_result_fpr),
		.fpu_waddr_i      (fpu_result_addr),
		.fpu_wdata_i      (fpu_result),
		.retire_i         (commit_pkt),
		.retire_instr_i   (retire_instr),
		.retire1_i        (commit_pkt1),
		.retire1_instr_i  (retire_instr1)
	);
`endif



endmodule
