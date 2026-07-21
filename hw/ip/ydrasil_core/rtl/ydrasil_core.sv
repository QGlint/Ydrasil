

module ydrasil_core
import ydrasil_pkg::*;
import ydrasil_pipeline_pkg::*;
		 #(
		parameter int BP_ENTRIES  = 0,
		parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
		parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES,
		parameter bit USE_GSHARE  = 1'b0
	)(
	input  wire clk,
	input  wire rst_n
    
    
    ,output wire [31:0]  perip_addr,
    output wire         perip_wen,
	output wire [ 3:0]  perip_mask,
    output wire [31:0]  perip_wdata,
    input  wire [31:0]  perip_rdata
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
    ,output wire        dbg_bp_pred_l0_taken_o
    ,output wire [31:0] dbg_bp_pred_next_pc_o
    ,output wire        dbg_bp_mispredict_o
`endif
);

	// IF <-> MEMS
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr1;
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
	wire        if_id_pred_l0_taken;
	wire        if_id_valid;
	wire [31:0] if_id1_pc;
	wire [31:0] if_id1_instr;
	wire        if_id1_pred_hit;
	wire        if_id1_pred_taken;
	wire [31:0] if_id1_pred_target;
	wire [1:0]  if_id1_pred_counter;
	wire [31:0] if_id1_pred_bht_index;
	wire        if_id1_pred_l0_taken;
	wire        if_id1_valid;
	fetch_pair_pkt_t if_id_fetch_pair;
	pair_ctrl_t if_id_pair_ctrl;
	decode_pair_pkt_t id_decode_pair;
	wire id_if_consume_two;
	rename_pkt_t rn_live_pkt;
	rename_pkt_t rn_live1_pkt;
	issue_pair_pkt_t id_issue_pair;
	wire rename_frontend_stall;
	wire issue_frontend_stall;

	// CTRL signals
	wire                        stall_if;
	wire                        stall_id;
    wire                       stall_pc;
	wire                        flush_if;
	wire                        flush_id;
	wire                        flush_ex;
	wire                        bubble_id;
	wire                        bubble_id_no_alloc;
	wire                        branch_jump;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] branch_target;

	// ID <-> RF
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_raddr_rs1;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_raddr_rs2;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs1;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs2;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_rf_raddr_rs1;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_rf_raddr_rs2;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_rf_rdata_rs1;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_rf_rdata_rs2;

	// ID -> EX
	wire [31:0]                    operand_a;
	wire [31:0]                    operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]     operator;
	wire [31:0]                    bt_a_operand;
	wire [31:0]                    bt_b_operand;
	wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]  operator_lsu;
	wire [31:0]                    id_lsu_rs2_data;
	wire [31:0]                    id_lsu_addr;
	wire                           id_lsu_addr_is_dtcm;
	wire [31:0]                    id_lsu_store_data;
	wire [3:0]                     id_lsu_store_mask;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type;
	wire                           id_alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_rf_waddr_rd;
	wire                           id_ex_jalr;
	wire                           pipe1_issue_valid;
	wire [31:0]                    pipe1_operand_a;
	wire [31:0]                    pipe1_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_operator;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] pipe1_operator_type;
	wire                           pipe1_rf_wen_rd_issue;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_rf_waddr_rd_issue;
	wire [5:0]                     pipe1_rn_pdst_issue;
	wire                           pipe1_rob_valid_issue;
	wire [5:0]                     pipe1_rob_idx_issue;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] pipe1_pc;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] pipe1_instr;

	// EX outputs
	wire                        ex_branch_jump;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_branch_target;
	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]  ex_lsu_mem_addr;
    wire [31:0]                 ex_lsu_result;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] alu_result;
	wire                        alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd;
	wire [5:0]                  alu_rn_pdst;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_alu_result;
	wire                        pipe1_alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_alu_rf_waddr_rd;
	wire [5:0]                  pipe1_alu_rn_pdst;
	wire                        pipe1_alu_rob_valid;
	wire [5:0]                  pipe1_alu_rob_idx;
	wire                        pipe1_instret_inc;
	wire                        pipe1_wb_fwd_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_wb_fwd_addr;
	wire [5:0]                  pipe1_wb_fwd_pdst;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_wb_fwd_data;
	wire                        wb_buf_fwd_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_buf_fwd_addr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] wb_buf_fwd_data;
	wire                        ex_mul_stall;
	wire                        ex_mul_issue;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] ex_mul_issue_waddr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mul_wb_result;
	wire                        mul_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] mul_rf_waddr_rd;
	wire [5:0]                  mul_rn_pdst;
	wire                        mul_result_valid;
	wire                        ex_instret_inc;
	wire                        ex_pc_redirect;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_pc_redirect_target;
	wire                        ex_bp_train_valid;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_bp_train_pc;
	wire                        ex_bp_train_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_bp_train_target;
	wire [1:0]                  ex_bp_train_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_bp_train_bht_index;
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
	wire                        dbg_bp_pred_l0_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] dbg_bp_pred_next_pc;
	wire                        dbg_bp_mispredict;
`endif

	// Branch predictor
	wire                        bp_predict_hit;
	wire                        bp_predict_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict_target;
	wire [1:0]                  bp_predict_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_predict_bht_index;
	wire                        id_fence_i;
	wire                        id_ex_pred_hit;
	wire                        id_ex_pred_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] id_ex_pred_target;
	wire [1:0]                  id_ex_pred_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] id_ex_pred_bht_index;
	wire                        id_ex_pred_l0_taken;
	wire                        id_ex_valid;

	// LSU request path
	wire [1:0]                  operator_lsu_type;
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
	wire                        lsu_fast_fwd_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_rf_waddr_rd;
	wire [5:0]                  lsu_rn_pdst;

	// WB -> RF
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd;
	wire                        rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata1_rd;
	wire                        rf_wen1_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr1_rd;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata2_rd;
	wire                        rf_wen2_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr2_rd;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] wb_rf_wdata_rd;
	wire                        wb_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_rf_waddr_rd;
	wire                        wb_mul_complete;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_mul_complete_waddr;
	wire [5:0]                  wb_mul_complete_pdst;
	wire                        prf_rd0_en;
	wire                        prf_rd1_en;
	wire                        prf_rd2_en;
	wire                        prf_rd3_en;
	wire [5:0]                  prf_rd0_addr;
	wire [5:0]                  prf_rd1_addr;
	wire [5:0]                  prf_rd2_addr;
	wire [5:0]                  prf_rd3_addr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] prf_rd0_data;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] prf_rd1_data;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] prf_rd2_data;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] prf_rd3_data;
	wire                        prf_wr0_en;
	wire                        prf_wr1_en;
	wire [5:0]                  prf_wr0_addr;
	wire [5:0]                  prf_wr1_addr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] prf_wr0_data;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] prf_wr1_data;
	wire                        prf_wr2_en;
	wire [5:0]                  prf_wr2_addr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] prf_wr2_data;
	wire                        wb_backpressure;
	wire                        pipe1_resbuf_full;
	wire                        pipe1_wb_dequeue;
	wire                        pipe1_wb_enqueue;
	wire                        pipe1_wb_pdst_valid;
	wire [5:0]                  pipe1_wb_pdst;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_wb_data;
	wire                        pipe1_wb_rob_valid;
	wire [5:0]                  pipe1_wb_rob_idx;
	reg                         wb_hzd_valid_q;
	reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_hzd_addr_q;
	reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] wb_hzd_data_q;

    //LSU -> CTRL
	wire                            lsu_ctrl_busy;
	wire                            lsu_store_complete;
	wire [5:0]                      lsu_store_rob_idx;

    //LSU -> ID
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs1_addr;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs2_addr;
	wire                            id_ctrl_rs1_ren;
	wire                            id_ctrl_rs2_ren;
	wire                            id_ctrl_rd_wen;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rd_addr;
	wire                            id_ctrl_lsu_req;
	wire [5:0]                      id_ctrl_rs1_psrc;
	wire [5:0]                      id_ctrl_rs2_psrc;
	wire [5:0]                      id_ctrl_pdst;
	wire                            id_ctrl_rob_valid;
	wire [5:0]                      id_ctrl_rob_idx;
	wire                            pipe1_ctrl_rs1_ren;
	wire                            pipe1_ctrl_rs2_ren;
	wire [5:0]                      pipe1_ctrl_rs1_psrc;
	wire [5:0]                      pipe1_ctrl_rs2_psrc;
	wire [5:0]                      id_rn_pdst;
	wire                            rn_if_rd_valid;
	wire                            rn_if_store_valid;
	wire                            rn_if_ctrl_valid;
	wire                            rn_alloc_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    rn_alloc_rd_addr;
	wire                            rn_if1_rd_valid;
	wire                            rn_alloc1_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    rn_alloc1_rd_addr;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] id_ctrl_operator_type;
	wire                            scoreboard_stall;
	wire                            id_frontend_stall;
	wire                            ready_issue_allow;
	wire                            lsu_struct_stall;
	wire                            ex_accept_valid;
	wire                            id_ex_rd_issue;
	wire                            pipe1_rd_issue;
	localparam int RN_REAL_PHYS_REGS = 64;
	localparam int RN_REAL_ROB_DEPTH = 64;
	localparam int RN_REAL_PREG_BITS = 6;
	localparam int RN_REAL_ROB_PTR_BITS = 6;
	wire [RN_REAL_PHYS_REGS-1:0] rn_real_preg_ready;
	wire rn_real_rs1_ready;
	wire rn_real_rs2_ready;
	wire rn_real_pipe1_rs1_ready;
	wire rn_real_pipe1_rs2_ready;
	wire rn_real_live_rs1_ready;
	wire rn_real_live_rs2_ready;
	wire rn_real_live1_rs1_ready;
	wire rn_real_live1_rs2_ready;
	wire rn_real_pipe1_rename_ready;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_rs1_psrc;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_rs2_psrc;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_live_rs1_psrc;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_live_rs2_psrc;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_live1_rs1_psrc;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_live1_rs2_psrc;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_alloc0_pdst;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_alloc1_pdst;
	wire [RN_REAL_ROB_PTR_BITS-1:0] rn_real_alloc0_rob_idx;
	wire [RN_REAL_ROB_PTR_BITS-1:0] rn_real_alloc1_rob_idx;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_wb_pdst;
	wire rn_real_wb_pdst_found;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_lsu_pdst;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_mul_pdst;
	wire [RN_REAL_PREG_BITS-1:0] rn_real_pipe1_pdst;
	wire rn_real_lsu_pdst_found;
	wire rn_real_mul_pdst_found;
	wire rn_real_pipe1_pdst_found;
	wire rn_real_alloc_stall;
	wire rn_real_commit0_valid;
	wire rn_real_commit0_ready;
	wire rn_real_ctrl_block;
	wire rn_real_rs1_uncommitted;
	wire rn_real_rs2_uncommitted;
	wire rn_real_pipe1_rs1_uncommitted;
	wire rn_real_pipe1_rs2_uncommitted;
	wire pipe1_commit_rf_wen;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_commit_arch_rd;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_commit_data;
	wire pipe1_commit1_rf_wen;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_commit1_arch_rd;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_commit1_data;
`ifndef SYNTHESIS
	wire rn_real_ctrl_rs1_block;
	wire rn_real_ctrl_rs2_block;
	wire rn_real_ctrl_at_head;
	wire rn_real_pipe1_branch_order_escape;
	wire rs1_issue_alu_ready_next = 1'b0;
	wire rs2_issue_alu_ready_next = 1'b0;
	wire rs1_branch_ready_next_bypass = 1'b0;
	wire rs2_branch_ready_next_bypass = 1'b0;
`endif

	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       id_csr_raddr;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr;
	wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info;

	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_ex_rdata;
	wire 					    ex_csr_wen;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      ex_csr_wdata;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       ex_csr_waddr;

	// CSR <-> CLINT wires
	wire                             clint_csr_we;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       clint_csr_waddr;
	wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       clint_csr_raddr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      clint_csr_wdata;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_clint_data;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_clint_mtvec;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_clint_mepc;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      csr_clint_mstatus;
	wire                             global_int_en;
	wire                             interrupt;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]      clint_ex_int_addr;
	wire                             clint_stall;
	wire [1:0]                       instret_delta;

	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0] id_instr_addr;

	wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] id_op_sys_info;

`ifndef SYNTHESIS
	wire commit_trace_alloc_valid;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_trace_alloc_pc;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_trace_alloc_instr;
	wire commit_trace_alloc1_valid;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_trace_alloc1_pc;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_trace_alloc1_instr;
	observer_pkt_t observer_pkt;
	observer_dbg_pkt_t observer_dbg_pkt;
`endif

		assign rn_real_rs1_psrc = id_ctrl_rs1_psrc;
		assign rn_real_rs2_psrc = id_ctrl_rs2_psrc;
		assign rn_live_pkt.rs1_ready = rn_real_live_rs1_ready;
		assign rn_live_pkt.rs2_ready = rn_real_live_rs2_ready;
		assign rn_live_pkt.rs1_psrc = rn_real_live_rs1_psrc;
			assign rn_live_pkt.rs2_psrc = rn_real_live_rs2_psrc;
			assign rn_live_pkt.pdst = rn_real_alloc0_pdst;
			assign rn_live_pkt.pdst_valid = 1'b0;
			assign rn_live_pkt.rob_idx = '0;
			assign rn_live_pkt.rob_valid = 1'b0;
			assign rn_live1_pkt.rs1_ready = rn_real_live1_rs1_ready;
			assign rn_live1_pkt.rs2_ready = rn_real_live1_rs2_ready;
			assign rn_live1_pkt.rs1_psrc = rn_real_live1_rs1_psrc;
			assign rn_live1_pkt.rs2_psrc = rn_real_live1_rs2_psrc;
			assign rn_live1_pkt.pdst = rn_real_alloc1_pdst;
			assign rn_live1_pkt.pdst_valid = 1'b0;
			assign rn_live1_pkt.rob_idx = '0;
			assign rn_live1_pkt.rob_valid = 1'b0;
		assign id_frontend_stall = rename_frontend_stall;

		ydrasil_rename_ctrl #(
		.PHYS_REGS(RN_REAL_PHYS_REGS),
		.ROB_DEPTH(RN_REAL_ROB_DEPTH),
		.PREG_BITS(RN_REAL_PREG_BITS),
		.ROB_PTR_BITS(RN_REAL_ROB_PTR_BITS)
	) u_ydrasil_rename_ctrl (
		.clk(clk),
		.rst_n(rst_n),
		.flush_id_i(flush_id),
		.flush_ex_i(flush_ex),
		.interrupt_i(interrupt),
		.if_id_instr_i(id_decode_pair.slot0.instr),
		.if_id1_instr_i(id_decode_pair.slot1.instr),
		.id_ctrl_rs1_ren_i(id_ctrl_rs1_ren),
		.id_ctrl_rs2_ren_i(id_ctrl_rs2_ren),
		.id_ctrl_rd_wen_i(id_ctrl_rd_wen),
		.id_ctrl_rd_addr_i(id_ctrl_rd_addr),
		.id_ctrl_rs1_psrc_i(id_ctrl_rs1_psrc),
		.id_ctrl_rs2_psrc_i(id_ctrl_rs2_psrc),
		.id_ctrl_pdst_i(id_ctrl_pdst),
		.id_ctrl_operator_type_i(id_ctrl_operator_type),
		.pipe1_ctrl_rs1_ren_i(pipe1_ctrl_rs1_ren),
		.pipe1_ctrl_rs2_ren_i(pipe1_ctrl_rs2_ren),
		.pipe1_ctrl_rs1_psrc_i(pipe1_ctrl_rs1_psrc),
		.pipe1_ctrl_rs2_psrc_i(pipe1_ctrl_rs2_psrc),
		.rn_alloc_valid_i(rn_alloc_valid),
		.rn_if_rd_valid_i(rn_if_rd_valid),
		.rn_if_store_valid_i(rn_if_store_valid),
		.rn_if_ctrl_valid_i(rn_if_ctrl_valid),
		.rn_alloc_rd_addr_i(rn_alloc_rd_addr),
		.rn_alloc1_valid_i(rn_alloc1_valid),
		.rn_if1_rd_valid_i(rn_if1_rd_valid),
		.rn_alloc1_rd_addr_i(rn_alloc1_rd_addr),
		.alu_wb_valid_i(alu_rf_wen_rd),
		.alu_wb_arch_rd_i(alu_rf_waddr_rd),
		.alu_wb_pdst_i(alu_rn_pdst),
		.lsu_wb_valid_i(lsu_rf_wen_rd),
		.lsu_wb_arch_rd_i(lsu_rf_waddr_rd),
		.lsu_wb_pdst_i(lsu_rn_pdst),
		.lsu_store_complete_i(lsu_store_complete),
		.lsu_store_rob_idx_i(lsu_store_rob_idx),
		.mul_wb_valid_i(wb_mul_complete),
		.mul_wb_arch_rd_i(wb_mul_complete_waddr),
		.mul_wb_pdst_i(wb_mul_complete_pdst),
			.pipe1_wb_valid_i(pipe1_wb_pdst_valid),
			.pipe1_wb_pdst_i(pipe1_wb_pdst),
			.pipe1_wb_data_i(pipe1_wb_data),
			.pipe1_wb_rob_valid_i(pipe1_wb_rob_valid),
			.pipe1_wb_rob_idx_i(pipe1_wb_rob_idx),
			.pipe1_issue_valid_i(pipe1_issue_valid),
			.pipe1_issue_pdst_i(pipe1_rn_pdst_issue),
			.ctrl_complete_valid_i(id_ex_valid & operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] & id_ctrl_rob_valid),
			.ctrl_complete_rob_idx_i(id_ctrl_rob_idx),
			.wb_rf_wen_i(wb_rf_wen_rd),
		.live_rs1_psrc_o(rn_real_live_rs1_psrc),
		.live_rs2_psrc_o(rn_real_live_rs2_psrc),
		.live1_rs1_psrc_o(rn_real_live1_rs1_psrc),
		.live1_rs2_psrc_o(rn_real_live1_rs2_psrc),
			.alloc_pdst_o(rn_real_alloc0_pdst),
			.alloc1_pdst_o(rn_real_alloc1_pdst),
			.alloc0_rob_idx_o(rn_real_alloc0_rob_idx),
			.alloc1_rob_idx_o(rn_real_alloc1_rob_idx),
			.preg_ready_o(rn_real_preg_ready),
		.rs1_ready_o(rn_real_rs1_ready),
		.rs2_ready_o(rn_real_rs2_ready),
		.rs1_uncommitted_o(rn_real_rs1_uncommitted),
		.rs2_uncommitted_o(rn_real_rs2_uncommitted),
		.pipe1_rs1_ready_o(rn_real_pipe1_rs1_ready),
		.pipe1_rs2_ready_o(rn_real_pipe1_rs2_ready),
		.pipe1_rs1_uncommitted_o(rn_real_pipe1_rs1_uncommitted),
		.pipe1_rs2_uncommitted_o(rn_real_pipe1_rs2_uncommitted),
		.live_rs1_ready_o(rn_real_live_rs1_ready),
		.live_rs2_ready_o(rn_real_live_rs2_ready),
		.live1_rs1_ready_o(rn_real_live1_rs1_ready),
		.live1_rs2_ready_o(rn_real_live1_rs2_ready),
		.pipe1_rename_ready_o(rn_real_pipe1_rename_ready),
		.alloc_stall_o(rn_real_alloc_stall),
		.ctrl_block_o(rn_real_ctrl_block),
		.wb_pdst_found_o(rn_real_wb_pdst_found),
		.lsu_pdst_found_o(rn_real_lsu_pdst_found),
		.mul_pdst_found_o(rn_real_mul_pdst_found),
		.pipe1_pdst_found_o(rn_real_pipe1_pdst_found),
		.wb_pdst_o(rn_real_wb_pdst),
		.lsu_pdst_o(rn_real_lsu_pdst),
		.mul_pdst_o(rn_real_mul_pdst),
		.pipe1_pdst_o(rn_real_pipe1_pdst),
		.commit0_valid_o(rn_real_commit0_valid),
		.commit0_ready_o(rn_real_commit0_ready),
		.pipe1_commit_rf_wen_o(pipe1_commit_rf_wen),
		.pipe1_commit_arch_rd_o(pipe1_commit_arch_rd),
		.pipe1_commit_data_o(pipe1_commit_data),
		.pipe1_commit1_rf_wen_o(pipe1_commit1_rf_wen),
		.pipe1_commit1_arch_rd_o(pipe1_commit1_arch_rd),
		.pipe1_commit1_data_o(pipe1_commit1_data),
`ifndef SYNTHESIS
		.ctrl_rs1_block_o(rn_real_ctrl_rs1_block),
		.ctrl_rs2_block_o(rn_real_ctrl_rs2_block),
		.ctrl_at_head_o(rn_real_ctrl_at_head),
		.pipe1_branch_order_escape_o(rn_real_pipe1_branch_order_escape),
`endif
		.unused_o()
	);

	ydrasil_rename_stage u_ydrasil_rename_stage (
		.clk(clk),
		.rst_n(rst_n),
		.flush_i(flush_id),
		.stall_i(stall_id),
		.bubble_i(bubble_id),
		.id_decode_pair_i(id_decode_pair),
		.rn_live0_i(rn_live_pkt),
			.rn_live1_i(rn_live1_pkt),
			.rn_alloc_stall_i(rn_real_alloc_stall),
			.issue_stall_i(issue_frontend_stall),
			.alloc0_rob_idx_i(rn_real_alloc0_rob_idx),
			.alloc1_rob_idx_i(rn_real_alloc1_rob_idx),
			.rename_issue_pair_o(id_issue_pair),
		.rename_frontend_stall_o(rename_frontend_stall),
		.rn_alloc_valid_o(rn_alloc_valid),
		.rn_alloc_rd_addr_o(rn_alloc_rd_addr),
			.rn_if_rd_valid_o(rn_if_rd_valid),
			.rn_if_store_valid_o(rn_if_store_valid),
			.rn_alloc1_valid_o(rn_alloc1_valid),
		.rn_alloc1_rd_addr_o(rn_alloc1_rd_addr),
		.rn_if1_rd_valid_o(rn_if1_rd_valid),
		.rn_if_ctrl_valid_o(rn_if_ctrl_valid)
`ifndef SYNTHESIS
		,
		.commit_trace_alloc_valid_o(commit_trace_alloc_valid),
		.commit_trace_alloc_pc_o(commit_trace_alloc_pc),
		.commit_trace_alloc_instr_o(commit_trace_alloc_instr),
		.commit_trace_alloc1_valid_o(commit_trace_alloc1_valid),
		.commit_trace_alloc1_pc_o(commit_trace_alloc1_pc),
		.commit_trace_alloc1_instr_o(commit_trace_alloc1_instr)
`endif
	);

`ifndef SYNTHESIS
	wire rn_real_ctrl_rs1_ready = rn_real_rs1_ready;
	wire rn_real_ctrl_rs2_ready = rn_real_rs2_ready;
	wire rn_real_ctrl_rs1_legacy_fwd = 1'b0;
	wire rn_real_ctrl_rs2_legacy_fwd = 1'b0;
	wire [RN_REAL_ROB_PTR_BITS-1:0] rn_real_rob_head_q =
		u_ydrasil_rename_ctrl.rob_head_q;
	wire [RN_REAL_ROB_PTR_BITS-1:0] rn_real_rob_tail_q =
		u_ydrasil_rename_ctrl.rob_tail_q;
	wire [6:0] rn_real_rob_occ_q = u_ydrasil_rename_ctrl.rob_occ_q;
	wire [6:0] rn_real_free_count_q = u_ydrasil_rename_ctrl.free_count_q;
	wire rn_real_alloc0_valid = u_ydrasil_rename_ctrl.alloc_valid;
	wire rn_real_ctrl_older_rob_block = u_ydrasil_rename_ctrl.ctrl_older_rob_block;
	wire [RN_REAL_PHYS_REGS-1:0] rn_real_busy_q = u_ydrasil_rename_ctrl.busy_q;
	wire rn_real_rob_pipe1_q [0:RN_REAL_ROB_DEPTH-1];
	wire rn_real_rob_valid_q [0:RN_REAL_ROB_DEPTH-1];
	wire rn_real_rob_ready_q [0:RN_REAL_ROB_DEPTH-1];
	genvar rn_dbg_i;
	generate
		for (rn_dbg_i = 0; rn_dbg_i < RN_REAL_ROB_DEPTH; rn_dbg_i = rn_dbg_i + 1) begin : gen_rn_dbg_alias
			assign rn_real_rob_pipe1_q[rn_dbg_i] = u_ydrasil_rename_ctrl.rob_pipe1_q[rn_dbg_i];
			assign rn_real_rob_valid_q[rn_dbg_i] = u_ydrasil_rename_ctrl.rob_valid_q[rn_dbg_i];
			assign rn_real_rob_ready_q[rn_dbg_i] = u_ydrasil_rename_ctrl.rob_ready_q[rn_dbg_i];
		end
	endgenerate
`endif
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			wb_hzd_valid_q <= 1'b0;
			wb_hzd_addr_q <= '0;
			wb_hzd_data_q <= '0;
		end else if (interrupt) begin
			wb_hzd_valid_q <= 1'b0;
			wb_hzd_addr_q <= '0;
			wb_hzd_data_q <= '0;
		end else begin
			wb_hzd_valid_q <= rf_wen_rd & (rf_waddr_rd != '0);
			wb_hzd_addr_q <= rf_waddr_rd;
			wb_hzd_data_q <= rf_wdata_rd;
		end
	end

	assign perip_addr = mmio_addr;
	assign perip_wen = mmio_req && mmio_we;
	assign perip_mask = mmio_wmask;
	assign perip_wdata = mmio_wdata;

	wire pipe1_instret_inc_count = pipe1_instret_inc;
	wire pipe1_issue_valid_to_ex = pipe1_issue_valid;
	wire [31:0] pipe1_operand_a_to_ex = pipe1_operand_a;
	wire [31:0] pipe1_operand_b_to_ex = pipe1_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_operator_to_ex = pipe1_operator;
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] pipe1_operator_type_to_ex = pipe1_operator_type;
		wire pipe1_rf_wen_rd_to_ex = pipe1_rf_wen_rd_issue;
		wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_rf_waddr_rd_to_ex = pipe1_rf_waddr_rd_issue;
		wire [5:0] pipe1_rn_pdst_to_ex = pipe1_rn_pdst_issue;
		wire pipe1_rob_valid_to_ex = pipe1_rob_valid_issue;
		wire [5:0] pipe1_rob_idx_to_ex = pipe1_rob_idx_issue;
		wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_alu_result_to_wb = pipe1_alu_result;
		wire pipe1_alu_rf_wen_rd_to_wb = pipe1_alu_rf_wen_rd;
		wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_alu_rf_waddr_rd_to_wb = pipe1_alu_rf_waddr_rd;
		wire [5:0] pipe1_alu_rn_pdst_to_wb = pipe1_alu_rn_pdst;
		wire pipe1_alu_rob_valid_to_wb = pipe1_alu_rob_valid;
		wire [5:0] pipe1_alu_rob_idx_to_wb = pipe1_alu_rob_idx;
	wire pipe1_resbuf_full_to_id = pipe1_resbuf_full;

	wire pipe0_retire_valid = ex_instret_inc | lsu_rf_wen_rd | mul_result_valid;
	wire pipe1_retire_valid = pipe1_instret_inc_count;
	assign instret_delta = {1'b0, pipe0_retire_valid} + {1'b0, pipe1_retire_valid};

	assign prf_rd0_en = id_ctrl_rs1_ren;
	assign prf_rd1_en = id_ctrl_rs2_ren;
	assign prf_rd2_en = pipe1_ctrl_rs1_ren;
	assign prf_rd3_en = pipe1_ctrl_rs2_ren;
	assign prf_rd0_addr = rn_real_rs1_psrc;
	assign prf_rd1_addr = rn_real_rs2_psrc;
	assign prf_rd2_addr = pipe1_ctrl_rs1_psrc;
	assign prf_rd3_addr = pipe1_ctrl_rs2_psrc;

	ydrasil_load_store_unit u_ydrasil_load_store_unit (
		.clk               (clk),
		.rst_n             (rst_n),
		.ex_lsu_mem_addr_i (ex_lsu_mem_addr),
		.id_rd_waddr_i      (id_rf_waddr_rd),
		.id_rn_pdst_i      (id_rn_pdst),
		.operator_lsu_i    (operator_lsu),
		.operator_lsu_type_i(operator_lsu_type),
        .ex_lsu_rd_data_i (ex_lsu_result),
		.id_lsu_rs2_data_i (id_lsu_rs2_data),
		.id_lsu_rs2_raddr_i('0),
		.id_lsu_addr_i     (id_lsu_addr),
		.id_lsu_addr_is_dtcm_i(id_lsu_addr_is_dtcm),
		.id_lsu_store_data_i(id_lsu_store_data),
		.id_lsu_store_mask_i(id_lsu_store_mask),
		.dtcm_rdata_i      (dtcm_rdata),
		.dtcm_wdata_o      (dtcm_wdata),
		.dtcm_addr_o       (dtcm_addr),
		.dtcm_wen_o        (dtcm_we),
		.dtcm_req_o        (dtcm_req),
		.dtcm_wmask_o      (dtcm_wmask),
		.mmio_rdata_i      (perip_rdata),
		.mmio_wdata_o      (mmio_wdata),
		.mmio_addr_o       (mmio_addr),
		.mmio_wen_o        (mmio_we),
		.mmio_req_o        (mmio_req),
		.mmio_wmask_o      (mmio_wmask),
		.lsu_ctrl_busy_o        (lsu_ctrl_busy),
		.id_store_rob_idx_i     (id_ctrl_rob_idx),
		.lsu_store_complete_o   (lsu_store_complete),
		.lsu_store_rob_idx_o    (lsu_store_rob_idx),
		.lsu_wb_result_o   (lsu_wb_result),
		.lsu_rf_rd_wen_o   (lsu_rf_wen_rd),
		.lsu_rf_rd_waddr_o (lsu_rf_waddr_rd),
		.lsu_rn_pdst_o     (lsu_rn_pdst),
		.lsu_fast_fwd_valid_o(lsu_fast_fwd_valid)
	);

		ydrasil_branch_predictor #(
			.BP_ENTRIES(BP_ENTRIES),
			.BTB_ENTRIES(BTB_ENTRIES),
			.BHT_ENTRIES(BHT_ENTRIES),
			.USE_GSHARE(USE_GSHARE)
		) u_ydrasil_branch_predictor (
			.clk              (clk),
			.rst_n            (rst_n),
			.predict_pc_i     (if_mem_addr),
			.predict_hit_o    (bp_predict_hit),
			.predict_taken_o  (bp_predict_taken),
			.predict_target_o (bp_predict_target),
			.predict_counter_o(bp_predict_counter),
			.predict_bht_index_o(bp_predict_bht_index),
			.train_valid_i    (ex_bp_train_valid),
			.train_pc_i       (ex_bp_train_pc),
			.train_taken_i    (ex_bp_train_taken),
			.train_target_i   (ex_bp_train_target),
			.train_counter_i  (ex_bp_train_counter),
			.train_bht_index_i(ex_bp_train_bht_index),
			.invalidate_i     (id_fence_i)
		);

		ydrasil_if_stage u_ydrasil_if_stage (
			.clk           (clk),
			.rst_n         (rst_n),
			.stall_if_i      (stall_if),
	        .stall_pc_i      (stall_pc),
			.flush_if_i      (flush_if),
			.consume_two_i    (id_if_consume_two),
			.branch_jump_i   (branch_jump),
			.branch_target_i (branch_target),
			.bp_predict_hit_i(bp_predict_hit),
			.bp_predict_taken_i(bp_predict_taken),
			.bp_predict_target_i(bp_predict_target),
			.bp_predict_counter_i(bp_predict_counter),
			.bp_predict_bht_index_i(bp_predict_bht_index),
			.bp_invalidate_i(id_fence_i),
			.l0_train_valid_i(ex_bp_train_valid),
			.l0_train_pc_i(ex_bp_train_pc),
			.l0_train_taken_i(ex_bp_train_taken),
			.l0_train_target_i(ex_bp_train_target),
			.if_mem_addr_o   (if_mem_addr),
			.if_mem_addr1_o  (if_mem_addr1),
			.if_mem_rdata_i  (if_mem_rdata),
			.if_mem_rdata1_i (if_mem_rdata1),
			.if_id_pc_o      (if_id_pc),
			.if_id_pred_hit_o(if_id_pred_hit),
			.if_id_pred_taken_o(if_id_pred_taken),
			.if_id_pred_target_o(if_id_pred_target),
			.if_id_pred_counter_o(if_id_pred_counter),
			.if_id_pred_bht_index_o(if_id_pred_bht_index),
			.if_id_pred_l0_taken_o(if_id_pred_l0_taken),
			.if_id_valid_o   (if_id_valid),
			.if_id1_pc_o     (if_id1_pc),
			.if_id1_pred_hit_o(if_id1_pred_hit),
			.if_id1_pred_taken_o(if_id1_pred_taken),
			.if_id1_pred_target_o(if_id1_pred_target),
			.if_id1_pred_counter_o(if_id1_pred_counter),
			.if_id1_pred_bht_index_o(if_id1_pred_bht_index),
			.if_id1_pred_l0_taken_o(if_id1_pred_l0_taken),
			.if_id1_valid_o  (if_id1_valid),
			.if_id_fetch_pair_o(if_id_fetch_pair),
			.if_id_pair_ctrl_o(if_id_pair_ctrl),
			.dbg_sync_bp_redirect_o(),
			.if_id_instr_o   (if_id_instr),
			.if_id1_instr_o  (if_id1_instr)
		);

		ydrasil_id_stage u_ydrasil_id_stage (
			.clk                  (clk),
			.rst_n                (rst_n),
			.stall_id_i           (stall_id | id_frontend_stall),
			.bubble_id_i          (bubble_id),
			.flush_id_i           (flush_id),
			.if_id_fetch_pair_i   (if_id_fetch_pair),
			.id_decode_pair_o     (id_decode_pair),
			.consume_two_o        (id_if_consume_two)
		);

		ydrasil_issue_stage u_ydrasil_issue_stage (
			.clk                 (clk),
			.rst_n               (rst_n),
			.stall_id_i          (stall_id),
			.bubble_id_i         (bubble_id),
			.bubble_id_no_alloc_i(bubble_id_no_alloc),
			.flush_id_i          (flush_id),
			.id_issue_pair_i     (id_issue_pair),
			.rf_addr_rs1_o       (rf_raddr_rs1),
		.rf_addr_rs2_o      (rf_raddr_rs2),
		.rf_rdata_rs1_i     (rf_rdata_rs1),
		.rf_rdata_rs2_i     (rf_rdata_rs2),
		.pipe1_rf_addr_rs1_o(pipe1_rf_raddr_rs1),
		.pipe1_rf_addr_rs2_o(pipe1_rf_raddr_rs2),
		.pipe1_rf_rdata_rs1_i(pipe1_rf_rdata_rs1),
		.pipe1_rf_rdata_rs2_i(pipe1_rf_rdata_rs2),
		.wb_fwd_valid_i     (wb_hzd_valid_q),
		.wb_fwd_addr_i      (wb_hzd_addr_q),
		.wb_fwd_data_i      (wb_hzd_data_q),
		.lsu_fwd_valid_i    (lsu_fast_fwd_valid),
		.lsu_fwd_addr_i     (lsu_rf_waddr_rd),
		.lsu_fwd_pdst_i     (lsu_rn_pdst),
		.lsu_fwd_data_i     (lsu_wb_result),
		.alu_fwd_valid_i    (alu_rf_wen_rd),
		.alu_fwd_addr_i     (alu_rf_waddr_rd),
		.alu_fwd_pdst_i     (alu_rn_pdst),
		.alu_fwd_data_i     (alu_result),
		.pipe1_alu_fwd_valid_i(pipe1_alu_rf_wen_rd),
		.pipe1_alu_fwd_addr_i(pipe1_alu_rf_waddr_rd),
		.pipe1_alu_fwd_pdst_i(pipe1_alu_rn_pdst),
		.pipe1_alu_fwd_data_i(pipe1_alu_result),
		.prf_rs1_ready_i   (rn_real_rs1_ready),
		.prf_rs2_ready_i   (rn_real_rs2_ready),
		.prf_rs1_data_i    (prf_rd0_data),
		.prf_rs2_data_i    (prf_rd1_data),
		.prf_rs1_uncommitted_i(rn_real_rs1_uncommitted),
		.prf_rs2_uncommitted_i(rn_real_rs2_uncommitted),
		.pipe1_prf_rs1_ready_i(rn_real_pipe1_rs1_ready),
		.pipe1_prf_rs2_ready_i(rn_real_pipe1_rs2_ready),
			.pipe1_prf_rs1_data_i(prf_rd2_data),
			.pipe1_prf_rs2_data_i(prf_rd3_data),
			.pipe1_prf_rs1_uncommitted_i(rn_real_pipe1_rs1_uncommitted),
			.pipe1_prf_rs2_uncommitted_i(rn_real_pipe1_rs2_uncommitted),
			.ready_issue_allow_i(ready_issue_allow),
				.gpr_pending_i('0),
			.rn_preg_ready_i(rn_real_preg_ready),
			.pipe1_resbuf_full_i(pipe1_resbuf_full_to_id),
		.issue_frontend_stall_o(issue_frontend_stall),
		.operand_a_o        (operand_a),
		.operand_b_o        (operand_b),
		.operator_o         (operator),
		.bt_a_operand_o     (bt_a_operand),
		.bt_b_operand_o     (bt_b_operand),
		.operator_lsu_o     (operator_lsu),
		.id_lsu_rs2_data_o  (id_lsu_rs2_data),
		.id_lsu_addr_o      (id_lsu_addr),
		.id_lsu_addr_is_dtcm_o(id_lsu_addr_is_dtcm),
		.id_lsu_store_data_o(id_lsu_store_data),
		.id_lsu_store_mask_o(id_lsu_store_mask),
		.operator_type_o    (operator_type),
		.id_ctrl_rs1_addr_o (id_ctrl_rs1_addr),
		.id_ctrl_rs2_addr_o (id_ctrl_rs2_addr),
		.id_ctrl_rs1_ren_o  (id_ctrl_rs1_ren),
		.id_ctrl_rs2_ren_o  (id_ctrl_rs2_ren),
		.id_ctrl_rd_wen_o   (id_ctrl_rd_wen),
		.id_ctrl_rd_addr_o  (id_ctrl_rd_addr),
		.id_ctrl_lsu_req_o  (id_ctrl_lsu_req),
		.id_ctrl_rs1_psrc_o (id_ctrl_rs1_psrc),
		.id_ctrl_rs2_psrc_o (id_ctrl_rs2_psrc),
		.id_ctrl_pdst_o     (id_ctrl_pdst),
		.pipe1_ctrl_rs1_ren_o(pipe1_ctrl_rs1_ren),
		.pipe1_ctrl_rs2_ren_o(pipe1_ctrl_rs2_ren),
		.pipe1_ctrl_rs1_psrc_o(pipe1_ctrl_rs1_psrc),
		.pipe1_ctrl_rs2_psrc_o(pipe1_ctrl_rs2_psrc),
		.id_rn_pdst_o       (id_rn_pdst),
		.id_ctrl_operator_type_o(id_ctrl_operator_type),
		.id_csr_raddr_o     (id_csr_raddr),
		.id_ex_csr_waddr_o  (id_ex_csr_waddr),
		.id_op_csr_info_o   (id_op_csr_info),
		.id_op_sys_info_o   (id_op_sys_info),
		.id_instr_addr_o    (id_instr_addr),
		.id_ex_jalr_o       (id_ex_jalr),
		.id_fence_i_o       (id_fence_i),
		.id_ex_pred_hit_o   (id_ex_pred_hit),
		.id_ex_pred_taken_o (id_ex_pred_taken),
		.id_ex_pred_target_o(id_ex_pred_target),
		.id_ex_pred_counter_o(id_ex_pred_counter),
		.id_ex_pred_bht_index_o(id_ex_pred_bht_index),
		.id_ex_pred_l0_taken_o(id_ex_pred_l0_taken),
		.id_ex_valid_o      (id_ex_valid),
		.id_alu_rf_wen_rd_o (id_alu_rf_wen_rd),
		.id_rf_waddr_rd_o   (id_rf_waddr_rd),
		.id_ctrl_rob_valid_o(id_ctrl_rob_valid),
		.id_ctrl_rob_idx_o  (id_ctrl_rob_idx),
		.pipe1_issue_valid_o(pipe1_issue_valid),
		.pipe1_operand_a_o  (pipe1_operand_a),
		.pipe1_operand_b_o  (pipe1_operand_b),
		.pipe1_operator_o   (pipe1_operator),
		.pipe1_operator_type_o(pipe1_operator_type),
		.pipe1_rf_wen_rd_o  (pipe1_rf_wen_rd_issue),
		.pipe1_rf_waddr_rd_o(pipe1_rf_waddr_rd_issue),
		.pipe1_rn_pdst_o    (pipe1_rn_pdst_issue),
		.pipe1_rob_valid_o  (pipe1_rob_valid_issue),
		.pipe1_rob_idx_o    (pipe1_rob_idx_issue),
		.pipe1_pc_o         (pipe1_pc),
		.pipe1_instr_o      (pipe1_instr)
	);

	ydrasil_ex_block u_ydrasil_ex_block (
		.clk                (clk),
		.rst_n              (rst_n),
		.flush_ex_i         (flush_ex),
		.bt_a_operand_i     (bt_a_operand),
		.bt_b_operand_i     (bt_b_operand),
		.operand_a_i        (operand_a),
		.operand_b_i        (operand_b),
		.operator_i         (operator),
		.operator_type_i    (operator_type),
		.id_ex_valid_i      (id_ex_valid),
		.id_ex_jalr_i       (id_ex_jalr),
		.id_ex_pred_hit_i   (id_ex_pred_hit),
		.id_ex_pred_taken_i (id_ex_pred_taken),
			.id_ex_pred_target_i(id_ex_pred_target),
			.id_ex_pred_counter_i(id_ex_pred_counter),
			.id_ex_pred_bht_index_i(id_ex_pred_bht_index),
			.id_ex_pred_l0_taken_i(id_ex_pred_l0_taken),
			.interrupt_i        (interrupt),
		.clint_ex_int_addr_i(clint_ex_int_addr),
		.id_rf_waddr_rd_i   (id_rf_waddr_rd),
		.id_alu_rf_wen_rd_i (id_alu_rf_wen_rd),
		.id_rn_pdst_i       (id_rn_pdst),
		.pipe1_issue_valid_i(pipe1_issue_valid_to_ex),
		.pipe1_operand_a_i  (pipe1_operand_a_to_ex),
		.pipe1_operand_b_i  (pipe1_operand_b_to_ex),
		.pipe1_operator_i   (pipe1_operator_to_ex),
		.pipe1_operator_type_i(pipe1_operator_type_to_ex),
			.pipe1_rf_wen_rd_i  (pipe1_rf_wen_rd_to_ex),
			.pipe1_rf_waddr_rd_i(pipe1_rf_waddr_rd_to_ex),
			.pipe1_rn_pdst_i    (pipe1_rn_pdst_to_ex),
			.pipe1_rob_valid_i  (pipe1_rob_valid_to_ex),
			.pipe1_rob_idx_i    (pipe1_rob_idx_to_ex),
			.id_ex_csr_waddr_i  (id_ex_csr_waddr) ,
		.id_op_csr_info_i   (id_op_csr_info) ,
		.csr_ex_rdata_i     (csr_ex_rdata) ,
		.ex_csr_wen_o       (ex_csr_wen),
		.ex_csr_wdata_o     (ex_csr_wdata),
		.ex_csr_waddr_o     (ex_csr_waddr),
		.ex_branch_jump_o   (ex_branch_jump),
		.ex_branch_target_o (ex_branch_target),
		.ex_pc_redirect_o   (ex_pc_redirect),
		.ex_pc_redirect_target_o(ex_pc_redirect_target),
		.ex_bp_train_valid_o(ex_bp_train_valid),
		.ex_bp_train_pc_o   (ex_bp_train_pc),
		.ex_bp_train_taken_o(ex_bp_train_taken),
		.ex_bp_train_target_o(ex_bp_train_target),
		.ex_bp_train_counter_o(ex_bp_train_counter),
		.ex_bp_train_bht_index_o(ex_bp_train_bht_index),
		.ex_branch_mispredict_o(ex_branch_mispredict),
		.ex_lsu_mem_addr_o  (ex_lsu_mem_addr),
		.ex_lsu_result_o    (ex_lsu_result),
		.alu_result_o       (alu_result),
		.alu_rf_wen_rd_o    (alu_rf_wen_rd),
		.alu_rf_waddr_rd_o  (alu_rf_waddr_rd),
		.alu_rn_pdst_o      (alu_rn_pdst),
		.pipe1_alu_result_o (pipe1_alu_result),
			.pipe1_alu_rf_wen_rd_o(pipe1_alu_rf_wen_rd),
			.pipe1_alu_rf_waddr_rd_o(pipe1_alu_rf_waddr_rd),
			.pipe1_alu_rn_pdst_o(pipe1_alu_rn_pdst),
			.pipe1_alu_rob_valid_o(pipe1_alu_rob_valid),
			.pipe1_alu_rob_idx_o(pipe1_alu_rob_idx),
			.pipe1_instret_inc_o(pipe1_instret_inc),
		.mul_issue_o        (ex_mul_issue),
		.mul_issue_waddr_o  (ex_mul_issue_waddr),
		.mul_wdata_rd_o     (mul_wb_result),
		.mul_rf_wen_rd_o    (mul_rf_wen_rd),
		.mul_rf_waddr_rd_o  (mul_rf_waddr_rd),
		.mul_rn_pdst_o      (mul_rn_pdst),
		.mul_result_valid_o (mul_result_valid),
		.ex_instret_inc_o   (ex_instret_inc),
		.ex_mul_stall_o     (ex_mul_stall),
		.ex_prf_wr_en_o     (prf_wr2_en),
		.ex_prf_wr_addr_o   (prf_wr2_addr),
		.ex_prf_wr_data_o   (prf_wr2_data)
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
		,.dbg_bp_pred_l0_taken_o(dbg_bp_pred_l0_taken)
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
		.lsu_mem_addr_i(dtcm_addr),
		.lsu_mem_data_i(dtcm_wdata),
		.lsu_mem_data_o(dtcm_rdata),
		.lsu_mem_we_i  (dtcm_we),
		.lsu_mem_req_i (dtcm_req),
		.lsu_mem_wmask_i(dtcm_wmask),
        .dram_sel_i     (1'b1)
		// .hold_flag_o   (hold_flag)
	);

	ydrasil_wb_stage u_ydrasil_wb_stage (
		.clk              (clk),
		.rst_n            (rst_n),
		.flush_i          (flush_id | flush_ex | interrupt),
		.alu_wdata_rd_i   (alu_result),
		.alu_rf_wen_rd_i  (alu_rf_wen_rd),
		.alu_rf_waddr_rd_i(alu_rf_waddr_rd),
			.pipe1_alu_wdata_rd_i(pipe1_alu_result_to_wb),
			.pipe1_alu_rf_wen_rd_i(pipe1_alu_rf_wen_rd_to_wb),
			.pipe1_alu_rf_waddr_rd_i(pipe1_alu_rf_waddr_rd_to_wb),
			.pipe1_alu_rn_pdst_i(pipe1_alu_rn_pdst_to_wb),
			.pipe1_alu_rob_valid_i(pipe1_alu_rob_valid_to_wb),
			.pipe1_alu_rob_idx_i(pipe1_alu_rob_idx_to_wb),
			.lsu_wb_result_i  (lsu_wb_result),
		.lsu_rf_wen_rd_i  (lsu_rf_wen_rd),
		.lsu_rf_waddr_rd_i(lsu_rf_waddr_rd),
		.mul_wdata_rd_i   (mul_wb_result),
		.mul_rf_wen_rd_i  (mul_rf_wen_rd),
		.mul_rf_waddr_rd_i(mul_rf_waddr_rd),
		.mul_rn_pdst_i    (mul_rn_pdst),
		.wb_mul_complete_o(wb_mul_complete),
		.wb_mul_complete_waddr_o(wb_mul_complete_waddr),
		.wb_mul_complete_pdst_o(wb_mul_complete_pdst),
		.wb_backpressure_o(wb_backpressure),
		.pipe1_resbuf_full_o(pipe1_resbuf_full),
		.pipe1_wb_dequeue_o(pipe1_wb_dequeue),
		.pipe1_wb_enqueue_o(pipe1_wb_enqueue),
			.pipe1_wb_pdst_valid_o(pipe1_wb_pdst_valid),
			.pipe1_wb_pdst_o(pipe1_wb_pdst),
			.pipe1_wb_data_o(pipe1_wb_data),
			.pipe1_wb_rob_valid_o(pipe1_wb_rob_valid),
			.pipe1_wb_rob_idx_o(pipe1_wb_rob_idx),
			.pipe1_fwd_valid_o(pipe1_wb_fwd_valid),
		.pipe1_fwd_addr_o(pipe1_wb_fwd_addr),
		.pipe1_fwd_pdst_o(pipe1_wb_fwd_pdst),
		.pipe1_fwd_data_o(pipe1_wb_fwd_data),
		.wb_buf_fwd_valid_o(wb_buf_fwd_valid),
		.wb_buf_fwd_addr_o(wb_buf_fwd_addr),
		.wb_buf_fwd_data_o(wb_buf_fwd_data),
		.rf_wdata_rd_o    (wb_rf_wdata_rd),
		.rf_wen_rd_o      (wb_rf_wen_rd),
		.rf_waddr_rd_o    (wb_rf_waddr_rd),
		.alu_pdst_found_i (rn_real_wb_pdst_found),
		.lsu_pdst_found_i (rn_real_lsu_pdst_found),
		.mul_pdst_found_i (rn_real_mul_pdst_found),
		.alu_rn_pdst_i     (alu_rn_pdst)
	);

	ydrasil_prf #(
		.PHYS_REGS(64),
		.PREG_BITS(6)
	) u_ydrasil_prf (
		.clk       (clk),
		.rst_n     (rst_n),
		.rd0_en_i  (prf_rd0_en),
		.rd0_addr_i(prf_rd0_addr),
		.rd0_data_o(prf_rd0_data),
		.rd1_en_i  (prf_rd1_en),
		.rd1_addr_i(prf_rd1_addr),
		.rd1_data_o(prf_rd1_data),
		.rd2_en_i  (prf_rd2_en),
		.rd2_addr_i(prf_rd2_addr),
		.rd2_data_o(prf_rd2_data),
		.rd3_en_i  (prf_rd3_en),
		.rd3_addr_i(prf_rd3_addr),
		.rd3_data_o(prf_rd3_data),
		.wr0_en_i  (prf_wr0_en),
		.wr0_addr_i(prf_wr0_addr),
		.wr0_data_i(prf_wr0_data),
		.wr1_en_i  (prf_wr1_en),
		.wr1_addr_i(prf_wr1_addr),
		.wr1_data_i(prf_wr1_data),
		.wr2_en_i  (prf_wr2_en),
		.wr2_addr_i(prf_wr2_addr),
		.wr2_data_i(prf_wr2_data)
	);

	ydrasil_registers u_ydrasil_registers (
		.clk          (clk),
		.rst_n        (rst_n),
		.rf_wen_rd_i  (rf_wen_rd),
		.rf_waddr_rd_i(rf_waddr_rd),
		.rf_wdata_rd_i(rf_wdata_rd),
		.rf_wen1_rd_i  (rf_wen1_rd),
		.rf_waddr1_rd_i(rf_waddr1_rd),
		.rf_wdata1_rd_i(rf_wdata1_rd),
		.rf_wen2_rd_i  (rf_wen2_rd),
		.rf_waddr2_rd_i(rf_waddr2_rd),
		.rf_wdata2_rd_i(rf_wdata2_rd),
		.rf_raddr_rs1_i(rf_raddr_rs1),
		.rf_rdata_rs1_o(rf_rdata_rs1),
		.rf_raddr_rs2_i(rf_raddr_rs2),
		.rf_rdata_rs2_o(rf_rdata_rs2),
		.pipe1_rf_raddr_rs1_i(pipe1_rf_raddr_rs1),
		.pipe1_rf_rdata_rs1_o(pipe1_rf_rdata_rs1),
		.pipe1_rf_raddr_rs2_i(pipe1_rf_raddr_rs2),
		.pipe1_rf_rdata_rs2_o(pipe1_rf_rdata_rs2)
	);

		ydrasil_ctrl u_ctrl (
			.clk               (clk),
			.rst_n             (rst_n),
			.interrupt_i       (interrupt),
			.ex_branch_jump_i  (ex_pc_redirect),
			.ex_branch_target_i(ex_pc_redirect_target),
			.rn_ctrl_block_i   (rn_real_ctrl_block),
			.rn_alloc_stall_i  (rn_real_alloc_stall),
			.id_ctrl_lsu_req_i (id_ctrl_lsu_req),
			.lsu_ctrl_busy_i   (lsu_ctrl_busy),
			.id_frontend_stall_i(id_frontend_stall),
			.clint_stall_i     (clint_stall),
			.ex_mul_stall_i     (ex_mul_stall),
			.wb_backpressure_i  (wb_backpressure),
				.id_ex_valid_i     (id_ex_valid),
				.id_alu_rf_wen_rd_i(id_alu_rf_wen_rd),
				.id_rf_waddr_rd_i  (id_rf_waddr_rd),
					.id_ex_div_op_i    ({operator[ydrasil_pkg::OP_MUL_DIV],
					                     operator[ydrasil_pkg::OP_MUL_DIVU],
					                     operator[ydrasil_pkg::OP_MUL_REM],
					                     operator[ydrasil_pkg::OP_MUL_REMU]}),
				.operator_type_i   (operator_type),
				.pipe1_issue_valid_i(pipe1_issue_valid),
					.pipe1_rf_wen_rd_issue_i(pipe1_rf_wen_rd_issue),
					.pipe1_rf_waddr_rd_issue_i(pipe1_rf_waddr_rd_issue),
					.rn_wb_pdst_found_i(rn_real_wb_pdst_found),
					.rn_wb_pdst_i(rn_real_wb_pdst),
					.rn_lsu_pdst_found_i(rn_real_lsu_pdst_found),
					.rn_lsu_pdst_i(rn_real_lsu_pdst),
					.rn_mul_pdst_found_i(rn_real_mul_pdst_found),
					.rn_mul_pdst_i(rn_real_mul_pdst),
					.rn_pipe1_pdst_found_i(rn_real_pipe1_pdst_found),
					.rn_pipe1_pdst_i(rn_real_pipe1_pdst),
					.alu_result_i(alu_result),
					.lsu_wb_result_i(lsu_wb_result),
					.pipe1_wb_data_i(pipe1_wb_data),
					.pipe1_commit_rf_wen_i(pipe1_commit_rf_wen),
					.pipe1_commit_arch_rd_i(pipe1_commit_arch_rd),
					.pipe1_commit_data_i(pipe1_commit_data),
					.pipe1_commit1_rf_wen_i(pipe1_commit1_rf_wen),
					.pipe1_commit1_arch_rd_i(pipe1_commit1_arch_rd),
					.pipe1_commit1_data_i(pipe1_commit1_data),
					.wb_rf_wen_rd_i(wb_rf_wen_rd),
					.wb_rf_waddr_rd_i(wb_rf_waddr_rd),
					.wb_rf_wdata_rd_i(wb_rf_wdata_rd),
					.scoreboard_stall_o(scoreboard_stall),
					.lsu_struct_stall_o(lsu_struct_stall),
					.ready_issue_allow_o(ready_issue_allow),
					.bubble_id_o       (bubble_id),
					.bubble_id_no_alloc_o(bubble_id_no_alloc),
				.ex_accept_valid_o (ex_accept_valid),
				.id_ex_rd_issue_o  (id_ex_rd_issue),
				.pipe1_rd_issue_o  (pipe1_rd_issue),
				.operator_lsu_type_o(operator_lsu_type),
				.prf_wr0_en_o(prf_wr0_en),
				.prf_wr1_en_o(prf_wr1_en),
				.prf_wr0_addr_o(prf_wr0_addr),
				.prf_wr1_addr_o(prf_wr1_addr),
				.prf_wr0_data_o(prf_wr0_data),
				.prf_wr1_data_o(prf_wr1_data),
				.rf_wen_rd_o(rf_wen_rd),
				.rf_waddr_rd_o(rf_waddr_rd),
				.rf_wdata_rd_o(rf_wdata_rd),
				.rf_wen1_rd_o(rf_wen1_rd),
				.rf_waddr1_rd_o(rf_waddr1_rd),
				.rf_wdata1_rd_o(rf_wdata1_rd),
				.rf_wen2_rd_o(rf_wen2_rd),
				.rf_waddr2_rd_o(rf_waddr2_rd),
				.rf_wdata2_rd_o(rf_wdata2_rd),
				.stall_if_o        (stall_if),
				.stall_id_o        (stall_id),
			.stall_pc_o        (stall_pc),
			.flush_if_o        (flush_if),
			.flush_id_o        (flush_id),
			.flush_ex_o        (flush_ex),
			.branch_jump_o     (branch_jump),
			.branch_target_o   (branch_target)
	);

	ydrasil_registers_csr u_ydrasil_registers_csr (
		.clk               (clk),
		.rst_n             (rst_n),
		.instret_delta_i   (instret_delta),
		.ex_csr_wen_i      (ex_csr_wen),
		.id_csr_raddr_i    (id_csr_raddr),
		.ex_csr_waddr_i    (ex_csr_waddr),
		.ex_csr_data_i     (ex_csr_wdata),
		.clint_csr_we_i    (clint_csr_we),
		.clint_csr_raddr_i (clint_csr_raddr),
		.clint_csr_waddr_i (clint_csr_waddr),
		.clint_csr_data_i  (clint_csr_wdata),
		.global_int_en_o   (global_int_en),
		.csr_clint_data_o  (csr_clint_data),
		.csr_clint_mtvec   (csr_clint_mtvec),
		.csr_clint_mepc    (csr_clint_mepc),
		.csr_clint_mstatus (csr_clint_mstatus),
		.csr_ex_data_o     (csr_ex_rdata)
	);

	ydrasil_clint u_clint (
		.clk               (clk),
		.rst_n             (rst_n),
		.instr_addr_i       (id_instr_addr),
		.ex_branch_jump_i       (ex_branch_jump),
		.ex_branch_target_i       (ex_branch_target),
        .sys_op_info_i      (id_op_sys_info),
        .sys_op_i           (ex_accept_valid & operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS]), // 只要有任意
		.csr_clint_data_i  (csr_clint_data),
		.csr_clint_mtvec   (csr_clint_mtvec),
		.csr_clint_mepc    (csr_clint_mepc),
		.csr_clint_mstatus (csr_clint_mstatus),
		.global_int_en_i   (global_int_en),
		.clint_stall_o     (clint_stall),
		.clint_csr_we_o    (clint_csr_we),
		.clint_csr_waddr_o (clint_csr_waddr),
		.clint_csr_raddr_o (clint_csr_raddr),
		.clint_csr_data_o  (clint_csr_wdata),
		.interrupt_o        (interrupt),
		.clint_ex_int_addr_o      (clint_ex_int_addr)
	);

	`ifndef SYNTHESIS
		assign observer_pkt.flush_id = flush_id;
		assign observer_pkt.flush_ex = flush_ex;
		assign observer_pkt.interrupt = interrupt;
		assign observer_pkt.if_id_instr = if_id_instr;
		assign observer_pkt.bp_predict_pc = if_mem_addr;
		assign observer_pkt.bp_predict_hit = bp_predict_hit;
		assign observer_pkt.bp_predict_taken = bp_predict_taken;
		assign observer_pkt.bp_predict_target = bp_predict_target;
		assign observer_pkt.bp_predict_counter = bp_predict_counter;
		assign observer_pkt.dbg_bp_resolve_valid = dbg_bp_resolve_valid;
		assign observer_pkt.dbg_bp_resolve_pc = dbg_bp_resolve_pc;
		assign observer_pkt.dbg_bp_actual_taken = dbg_bp_actual_taken;
		assign observer_pkt.dbg_bp_actual_target = dbg_bp_actual_target;
		assign observer_pkt.dbg_bp_actual_next_pc = dbg_bp_actual_next_pc;
		assign observer_pkt.dbg_bp_pred_hit = dbg_bp_pred_hit;
		assign observer_pkt.dbg_bp_pred_taken = dbg_bp_pred_taken;
		assign observer_pkt.dbg_bp_pred_target = dbg_bp_pred_target;
		assign observer_pkt.dbg_bp_pred_counter = dbg_bp_pred_counter;
		assign observer_pkt.dbg_bp_pred_l0_taken = dbg_bp_pred_l0_taken;
		assign observer_pkt.dbg_bp_pred_next_pc = dbg_bp_pred_next_pc;
		assign observer_pkt.dbg_bp_mispredict = dbg_bp_mispredict;
		assign observer_pkt.alu_rf_wen_rd = alu_rf_wen_rd;
		assign observer_pkt.alu_rf_waddr_rd = alu_rf_waddr_rd;
		assign observer_pkt.alu_result = alu_result;
		assign observer_pkt.alu_rn_pdst = alu_rn_pdst;
		assign observer_pkt.lsu_rf_wen_rd = lsu_rf_wen_rd;
		assign observer_pkt.lsu_rf_waddr_rd = lsu_rf_waddr_rd;
		assign observer_pkt.lsu_wb_result = lsu_wb_result;
		assign observer_pkt.wb_mul_complete = wb_mul_complete;
		assign observer_pkt.wb_mul_complete_waddr = wb_mul_complete_waddr;
		assign observer_pkt.pipe1_alu_rf_wen_rd_to_wb = pipe1_alu_rf_wen_rd_to_wb;
		assign observer_pkt.pipe1_alu_rf_waddr_rd_to_wb = pipe1_alu_rf_waddr_rd_to_wb;
		assign observer_pkt.pipe1_alu_result_to_wb = pipe1_alu_result_to_wb;
		assign observer_pkt.id_ex_valid = id_ex_valid;
		assign observer_pkt.id_ex_rd_issue = id_ex_rd_issue;
		assign observer_pkt.id_alu_rf_wen_rd = id_alu_rf_wen_rd;
		assign observer_pkt.id_rf_waddr_rd = id_rf_waddr_rd;
		assign observer_pkt.operator_type = operator_type;
		assign observer_pkt.id_ctrl_rs1_ren = id_ctrl_rs1_ren;
		assign observer_pkt.id_ctrl_rs2_ren = id_ctrl_rs2_ren;
		assign observer_pkt.id_ctrl_rd_wen = id_ctrl_rd_wen;
		assign observer_pkt.id_ctrl_rs1_addr = id_ctrl_rs1_addr;
		assign observer_pkt.id_ctrl_rs2_addr = id_ctrl_rs2_addr;
		assign observer_pkt.id_ctrl_rd_addr = id_ctrl_rd_addr;
		assign observer_pkt.id_instr_addr = id_instr_addr;
		assign observer_pkt.rn_alloc_valid = rn_alloc_valid;
		assign observer_pkt.rn_alloc_rd_addr = rn_alloc_rd_addr;
		assign observer_pkt.commit_trace_alloc_valid = commit_trace_alloc_valid;
		assign observer_pkt.commit_trace_alloc_pc = commit_trace_alloc_pc;
		assign observer_pkt.commit_trace_alloc_instr = commit_trace_alloc_instr;
		assign observer_pkt.commit_trace_alloc1_valid = commit_trace_alloc1_valid;
		assign observer_pkt.commit_trace_alloc1_pc = commit_trace_alloc1_pc;
		assign observer_pkt.commit_trace_alloc1_instr = commit_trace_alloc1_instr;
		assign observer_pkt.pipe1_issue_valid = pipe1_issue_valid;
		assign observer_pkt.pipe1_issue_valid_to_ex = pipe1_issue_valid_to_ex;
		assign observer_pkt.pipe1_rf_wen_rd_to_ex = pipe1_rf_wen_rd_to_ex;
		assign observer_pkt.pipe1_rf_waddr_rd_to_ex = pipe1_rf_waddr_rd_to_ex;
		assign observer_pkt.pipe1_rd_issue = pipe1_rd_issue;
		assign observer_pkt.pipe1_rf_waddr_rd_issue = pipe1_rf_waddr_rd_issue;
		assign observer_pkt.pipe1_rf_raddr_rs1 = pipe1_rf_raddr_rs1;
		assign observer_pkt.pipe1_rf_raddr_rs2 = pipe1_rf_raddr_rs2;
		assign observer_pkt.pipe1_pc = pipe1_pc;
		assign observer_pkt.pipe1_commit_rf_wen = pipe1_commit_rf_wen;
		assign observer_pkt.rs1_pending_stall = 1'b0;
		assign observer_pkt.rs2_pending_stall = 1'b0;
		assign observer_pkt.rd_waw_stall = 1'b0;
		assign observer_pkt.wb_rf_wen_rd = wb_rf_wen_rd;
		assign observer_pkt.wb_rf_waddr_rd = wb_rf_waddr_rd;
		assign observer_pkt.wb_rf_wdata_rd = wb_rf_wdata_rd;
		assign observer_pkt.wb_hzd_valid = wb_hzd_valid_q;
		assign observer_pkt.wb_hzd_addr = wb_hzd_addr_q;
		assign observer_pkt.ex_mul_issue = ex_mul_issue;
		assign observer_pkt.rf_wen_rd = rf_wen_rd;
		assign observer_pkt.rf_waddr_rd = rf_waddr_rd;
		assign observer_pkt.rf_wdata_rd = rf_wdata_rd;
		assign observer_pkt.prf_rd0_en = prf_rd0_en;
		assign observer_pkt.prf_rd1_en = prf_rd1_en;
		assign observer_pkt.prf_rd2_en = prf_rd2_en;
		assign observer_pkt.prf_rd3_en = prf_rd3_en;
		assign observer_pkt.prf_rd0_addr = prf_rd0_addr;
		assign observer_pkt.prf_rd1_addr = prf_rd1_addr;
		assign observer_pkt.prf_rd2_addr = prf_rd2_addr;
		assign observer_pkt.prf_rd3_addr = prf_rd3_addr;
		assign observer_pkt.prf_wr0_en = prf_wr0_en;
		assign observer_pkt.prf_wr1_en = prf_wr1_en;
		assign observer_pkt.prf_wr0_addr = prf_wr0_addr;
		assign observer_pkt.prf_wr1_addr = prf_wr1_addr;
		assign observer_pkt.prf_wr0_data = prf_wr0_data;
		assign observer_pkt.prf_wr1_data = prf_wr1_data;
		assign observer_pkt.rn_real_wb_pdst_found = rn_real_wb_pdst_found;
		assign observer_pkt.rn_real_wb_pdst = rn_real_wb_pdst;
		assign observer_pkt.rn_real_lsu_pdst_found = rn_real_lsu_pdst_found;
		assign observer_pkt.rn_real_lsu_pdst = rn_real_lsu_pdst;
		assign observer_pkt.rn_real_mul_pdst_found = rn_real_mul_pdst_found;
		assign observer_pkt.rn_real_mul_pdst = rn_real_mul_pdst;
		assign observer_pkt.rn_real_pipe1_pdst_found = rn_real_pipe1_pdst_found;
		assign observer_pkt.rn_real_pipe1_pdst = rn_real_pipe1_pdst;

		assign dbg_bp_predict_pc_o = observer_dbg_pkt.bp_predict_pc;
		assign dbg_bp_predict_hit_o = observer_dbg_pkt.bp_predict_hit;
		assign dbg_bp_predict_taken_o = observer_dbg_pkt.bp_predict_taken;
		assign dbg_bp_predict_target_o = observer_dbg_pkt.bp_predict_target;
		assign dbg_bp_predict_counter_o = observer_dbg_pkt.bp_predict_counter;
		assign dbg_bp_resolve_valid_o = observer_dbg_pkt.bp_resolve_valid;
		assign dbg_bp_resolve_pc_o = observer_dbg_pkt.bp_resolve_pc;
		assign dbg_bp_actual_taken_o = observer_dbg_pkt.bp_actual_taken;
		assign dbg_bp_actual_target_o = observer_dbg_pkt.bp_actual_target;
		assign dbg_bp_actual_next_pc_o = observer_dbg_pkt.bp_actual_next_pc;
		assign dbg_bp_pred_hit_o = observer_dbg_pkt.bp_pred_hit;
		assign dbg_bp_pred_taken_o = observer_dbg_pkt.bp_pred_taken;
		assign dbg_bp_pred_target_o = observer_dbg_pkt.bp_pred_target;
		assign dbg_bp_pred_counter_o = observer_dbg_pkt.bp_pred_counter;
		assign dbg_bp_pred_l0_taken_o = observer_dbg_pkt.bp_pred_l0_taken;
		assign dbg_bp_pred_next_pc_o = observer_dbg_pkt.bp_pred_next_pc;
		assign dbg_bp_mispredict_o = observer_dbg_pkt.bp_mispredict;

		ydrasil_core_observer u_ydrasil_core_observer (
			.clk(clk),
			.rst_n(rst_n),
			.observer_i(observer_pkt),
			.observer_dbg_o(observer_dbg_pkt)
			);
	`endif



endmodule
