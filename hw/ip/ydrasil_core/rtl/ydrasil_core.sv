

module ydrasil_core
import ydrasil_pkg::*;
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
`ifndef SYNTHESIS
	wire                           id_alu_stable_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_alu_stable_addr;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]    id_alu_stable_data;
`endif
	wire                           id_ex_jalr;
	wire                           pipe1_issue_valid;
	wire [31:0]                    pipe1_operand_a;
	wire [31:0]                    pipe1_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_operator;
	wire                           pipe1_rf_wen_rd_issue;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_rf_waddr_rd_issue;
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
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_alu_result;
	wire                        pipe1_alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_alu_rf_waddr_rd;
	wire                        pipe1_instret_inc;
	wire                        pipe1_wb_fwd_valid;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_wb_fwd_addr;
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

	// WB -> RF
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd;
	wire                        rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd;
	wire                        wb_backpressure;
	wire                        pipe1_resbuf_full;
	wire                        pipe1_wb_dequeue;
	wire                        pipe1_wb_enqueue;
	reg                         wb_hzd_valid_q;
	reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_hzd_addr_q;
	reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] wb_hzd_data_q;

    //LSU -> CTRL
	wire                            lsu_ctrl_busy;

    //LSU -> ID
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs1_addr;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rs2_addr;
	wire                            id_ctrl_rs1_ren;
	wire                            id_ctrl_rs2_ren;
	wire                            id_ctrl_rd_wen;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    id_ctrl_rd_addr;
	wire                            id_ctrl_lsu_req;
`ifndef SYNTHESIS
	wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] id_ctrl_operator_type;
`endif
	wire                            scoreboard_stall;
	wire                            id_frontend_stall;
	wire                            ready_issue_allow;
	wire                            lsu_struct_stall;
	wire                            ex_accept_valid;
	reg [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_q;
	wire                            id_ex_rd_issue;
`ifndef SYNTHESIS
	reg [2:0]                       mul_inflight_q;
	wire                            mul_inflight;
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
	wire                             instret_inc;

	wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0] id_instr_addr;

	wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] id_op_sys_info;

`ifndef SYNTHESIS
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_alu_instr;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_lsu_instr;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_mul_instr;
	wire commit_trace_alloc_valid;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_trace_alloc_pc;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_trace_alloc_instr;
	wire commit_pipe0_is_load;
	reg commit_ex_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_ex_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_ex_instr_q;
	reg commit_lsu_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_lsu_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_lsu_issue_instr_q;
	reg commit_mul_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_mul_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_mul_issue_instr_q;
	reg commit_pipe1_issue_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] commit_pipe1_issue_pc_q;
	reg [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_pipe1_issue_instr_q;

	function automatic [ydrasil_pkg::INST_DATA_WIDTH-1:0] commit_read_instr;
		input [ydrasil_pkg::INST_ADDR_WIDTH-1:0] pc;
		begin
			if ((pc >= ydrasil_pkg::DTCM_BASE_ADDR) &&
			    (pc < (ydrasil_pkg::DTCM_BASE_ADDR + ((32'd1 << ydrasil_pkg::DTCM_ADDR_WIDTH) << 2)))) begin
				commit_read_instr =
					u_ydrasil_mems.u_dtcm.u_dram.mem_r[
						pc[ydrasil_pkg::DTCM_ADDR_WIDTH+1:2]
					];
			end else begin
				commit_read_instr =
					u_ydrasil_mems.u_itcm.u_irom.mem_r[
						pc[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]
					];
			end
		end
	endfunction

	assign commit_alu_instr = commit_read_instr(id_instr_addr);
	assign commit_lsu_instr = commit_read_instr(id_instr_addr);
	assign commit_mul_instr = commit_read_instr(id_instr_addr);
	assign commit_pipe0_is_load = operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD];

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
			commit_pipe1_issue_valid_q <= 1'b0;
			commit_pipe1_issue_pc_q <= '0;
			commit_pipe1_issue_instr_q <= '0;
		end else begin
			commit_ex_valid_q <= id_ex_valid & !interrupt & !flush_ex;
			commit_ex_pc_q <= id_instr_addr;
			commit_ex_instr_q <= commit_alu_instr;
			commit_lsu_issue_valid_q <=
				ex_accept_valid & commit_pipe0_is_load & (id_rf_waddr_rd != '0) & !interrupt;
			commit_lsu_issue_pc_q <= id_instr_addr;
			commit_lsu_issue_instr_q <= commit_lsu_instr;
			commit_mul_issue_valid_q <= ex_mul_issue;
			commit_mul_issue_pc_q <= id_instr_addr;
			commit_mul_issue_instr_q <= commit_mul_instr;
			commit_pipe1_issue_valid_q <=
				pipe1_issue_valid_to_ex & pipe1_rf_wen_rd_to_ex &
				(pipe1_rf_waddr_rd_to_ex != '0) & !interrupt & !flush_ex;
			commit_pipe1_issue_pc_q <= pipe1_pc;
			commit_pipe1_issue_instr_q <= pipe1_instr;
		end
	end
`endif

	assign ex_accept_valid = id_ex_valid & !flush_ex;
	assign id_ex_rd_issue =
		ex_accept_valid & (id_rf_waddr_rd != '0) & !interrupt &
		(id_alu_rf_wen_rd | operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD]);
`ifndef SYNTHESIS
	assign dbg_bp_predict_pc_o = if_mem_addr;
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
	assign dbg_bp_pred_l0_taken_o = dbg_bp_pred_l0_taken;
	assign dbg_bp_pred_next_pc_o = dbg_bp_pred_next_pc;
	assign dbg_bp_mispredict_o = dbg_bp_mispredict;
`endif
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_clear_mask =
		wb_hzd_valid_q ? (ydrasil_pkg::REGS_NUM'(1) << wb_hzd_addr_q) : '0;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_issue_mask =
		id_ex_rd_issue ? (ydrasil_pkg::REGS_NUM'(1) << id_rf_waddr_rd) : '0;
`ifdef YDRASIL_ENABLE_PIPE1_REAL
	wire pipe1_rd_issue =
		pipe1_issue_valid & pipe1_rf_wen_rd_issue &
		(pipe1_rf_waddr_rd_issue != '0) & !flush_ex & !interrupt;
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_pipe1_issue_mask =
		pipe1_rd_issue ? (ydrasil_pkg::REGS_NUM'(1) << pipe1_rf_waddr_rd_issue) : '0;
`else
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_pipe1_issue_mask = '0;
`endif
	wire id_ex_rd_flush_kill =
		flush_ex & id_ex_valid & (id_rf_waddr_rd != '0) &
		(id_alu_rf_wen_rd | operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD]);
`ifdef YDRASIL_ENABLE_PIPE1_REAL
	wire pipe1_rd_flush_kill =
		flush_ex & pipe1_issue_valid & (pipe1_rf_waddr_rd_issue != '0) &
		pipe1_rf_wen_rd_issue;
`else
	wire pipe1_rd_flush_kill = 1'b0;
`endif
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_flush_kill_mask =
		(id_ex_rd_flush_kill ? (ydrasil_pkg::REGS_NUM'(1) << id_rf_waddr_rd) : '0) |
		(pipe1_rd_flush_kill ? (ydrasil_pkg::REGS_NUM'(1) << pipe1_rf_waddr_rd_issue) : '0);
	wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_for_hazard =
		(gpr_pending_q & ~gpr_pending_clear_mask & ~gpr_pending_flush_kill_mask) |
		gpr_pending_issue_mask | gpr_pending_pipe1_issue_mask;
	wire rs1_clear_fwd =
		(wb_hzd_valid_q & id_ctrl_rs1_ren & (id_ctrl_rs1_addr != '0) &
		 (id_ctrl_rs1_addr == wb_hzd_addr_q)) |
		(lsu_fast_fwd_valid & id_ctrl_rs1_ren & (id_ctrl_rs1_addr != '0) &
		 (id_ctrl_rs1_addr == lsu_rf_waddr_rd)) |
		(pipe1_wb_fwd_valid & id_ctrl_rs1_ren & (id_ctrl_rs1_addr != '0) &
		 (id_ctrl_rs1_addr == pipe1_wb_fwd_addr)) |
		(alu_rf_wen_rd & id_ctrl_rs1_ren & (id_ctrl_rs1_addr != '0) &
		 (id_ctrl_rs1_addr == alu_rf_waddr_rd));
	wire rs2_clear_fwd =
		(wb_hzd_valid_q & id_ctrl_rs2_ren & (id_ctrl_rs2_addr != '0) &
		 (id_ctrl_rs2_addr == wb_hzd_addr_q)) |
		(lsu_fast_fwd_valid & id_ctrl_rs2_ren & (id_ctrl_rs2_addr != '0) &
		 (id_ctrl_rs2_addr == lsu_rf_waddr_rd)) |
		(pipe1_wb_fwd_valid & id_ctrl_rs2_ren & (id_ctrl_rs2_addr != '0) &
		 (id_ctrl_rs2_addr == pipe1_wb_fwd_addr)) |
		(alu_rf_wen_rd & id_ctrl_rs2_ren & (id_ctrl_rs2_addr != '0) &
		 (id_ctrl_rs2_addr == alu_rf_waddr_rd));
	wire rd_clear_fwd =
		(wb_hzd_valid_q & id_ctrl_rd_wen & (id_ctrl_rd_addr != '0) &
		 (id_ctrl_rd_addr == wb_hzd_addr_q)) |
		(lsu_fast_fwd_valid & id_ctrl_rd_wen & (id_ctrl_rd_addr != '0) &
		 (id_ctrl_rd_addr == lsu_rf_waddr_rd)) |
		(alu_rf_wen_rd & id_ctrl_rd_wen & (id_ctrl_rd_addr != '0) &
		 (id_ctrl_rd_addr == alu_rf_waddr_rd));
	wire rs1_issue_raw_hzd =
		id_ex_rd_issue & id_ctrl_rs1_ren & (id_ctrl_rs1_addr == id_rf_waddr_rd);
	wire rs2_issue_raw_hzd =
		id_ex_rd_issue & id_ctrl_rs2_ren & (id_ctrl_rs2_addr == id_rf_waddr_rd);
	wire rd_issue_raw_hzd =
		id_ex_rd_issue & id_ctrl_rd_wen & (id_ctrl_rd_addr == id_rf_waddr_rd);
`ifdef YDRASIL_ENABLE_PIPE1_REAL
	wire pipe1_issue_rs1_hzd =
		pipe1_rd_issue & id_ctrl_rs1_ren & (id_ctrl_rs1_addr == pipe1_rf_waddr_rd_issue);
	wire pipe1_issue_rs2_hzd =
		pipe1_rd_issue & id_ctrl_rs2_ren & (id_ctrl_rs2_addr == pipe1_rf_waddr_rd_issue);
	wire pipe1_issue_rd_hzd =
		pipe1_rd_issue & id_ctrl_rd_wen & (id_ctrl_rd_addr == pipe1_rf_waddr_rd_issue);
`else
	wire pipe1_issue_rs1_hzd = 1'b0;
	wire pipe1_issue_rs2_hzd = 1'b0;
	wire pipe1_issue_rd_hzd = 1'b0;
`endif
	wire rs1_pending_stall =
		id_ctrl_rs1_ren && gpr_pending_q[id_ctrl_rs1_addr] && !rs1_clear_fwd;
	wire rs2_pending_stall =
		id_ctrl_rs2_ren && gpr_pending_q[id_ctrl_rs2_addr] && !rs2_clear_fwd;
	wire rd_waw_stall =
		id_ctrl_rd_wen && gpr_pending_q[id_ctrl_rd_addr] && !rd_clear_fwd;
	wire issue_load_producer =
		id_ex_rd_issue & operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD];
	wire issue_alu_producer =
		id_ex_rd_issue & id_alu_rf_wen_rd &
		operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU];
	wire issue_mul_div_producer =
		id_ex_rd_issue & operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL];
`ifndef SYNTHESIS
	wire issue_alu_stable_producer =
		issue_alu_producer &
		!operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &
		!operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &
		!operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &
		!operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &
		!operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &
		!operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &
		!operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
	wire issue_alu_stable_slot_hit =
		id_alu_stable_valid & issue_alu_stable_producer &
		(id_alu_stable_addr == id_rf_waddr_rd);
`else
	wire issue_alu_stable_slot_hit = 1'b0;
`endif
	wire rs1_issue_alu_ready_next_raw = rs1_issue_raw_hzd & issue_alu_producer;
	wire rs2_issue_alu_ready_next_raw = rs2_issue_raw_hzd & issue_alu_producer;
	wire rd_issue_alu_ready_next = rd_issue_raw_hzd & issue_alu_producer;
	wire rs1_issue_hzd = rs1_issue_raw_hzd & !issue_alu_producer;
	wire rs2_issue_hzd = rs2_issue_raw_hzd & !issue_alu_producer;
	wire rd_issue_hzd = rd_issue_raw_hzd & !issue_alu_producer;
	wire issue_src_hzd = rs1_issue_hzd | rs2_issue_hzd;
`ifndef SYNTHESIS
	assign mul_inflight = (mul_inflight_q != 3'd0) | ex_mul_issue;
	wire id_ctrl_simple_alu_consumer =
		id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &
		!id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &
		!id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &
		!id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &
		!id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &
		!id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &
		!id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &
		!id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
	wire rs1_issue_alu_stable_bypass =
		rs1_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
		id_ctrl_simple_alu_consumer &
		!mul_inflight &
		!rs2_pending_stall & !rd_waw_stall &
		!rs2_issue_hzd & !rd_issue_hzd &
		!pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;
	wire rs2_issue_alu_stable_bypass =
		rs2_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
		id_ctrl_simple_alu_consumer &
		!mul_inflight &
		!rs1_pending_stall & !rd_waw_stall &
		!rs1_issue_hzd & !rd_issue_hzd &
		!pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;
	wire id_ctrl_branch_consumer =
		id_ctrl_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP];
	wire rs1_branch_ready_next_bypass =
		rs1_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
		id_ctrl_branch_consumer &
		!mul_inflight &
		!rs2_pending_stall & !rd_waw_stall &
		!rs2_issue_hzd & !rd_issue_hzd &
		!pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;
	wire rs2_branch_ready_next_bypass =
		rs2_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
		id_ctrl_branch_consumer &
		!mul_inflight &
		!rs1_pending_stall & !rd_waw_stall &
		!rs1_issue_hzd & !rd_issue_hzd &
		!pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;
`else
	wire rs1_issue_alu_stable_bypass = 1'b0;
	wire rs2_issue_alu_stable_bypass = 1'b0;
	wire rs1_branch_ready_next_bypass = 1'b0;
	wire rs2_branch_ready_next_bypass = 1'b0;
`endif
`ifndef SYNTHESIS
	wire rs1_issue_alu_stable_issue_bypass =
		rs1_issue_alu_stable_bypass | rs1_branch_ready_next_bypass;
	wire rs2_issue_alu_stable_issue_bypass =
		rs2_issue_alu_stable_bypass | rs2_branch_ready_next_bypass;
`else
	wire rs1_issue_alu_stable_issue_bypass = 1'b0;
	wire rs2_issue_alu_stable_issue_bypass = 1'b0;
`endif
	wire rs1_issue_alu_ready_next =
		rs1_issue_alu_ready_next_raw & !rs1_issue_alu_stable_issue_bypass;
	wire rs2_issue_alu_ready_next =
		rs2_issue_alu_ready_next_raw & !rs2_issue_alu_stable_issue_bypass;

	assign scoreboard_stall =
		rs1_issue_hzd | rs2_issue_hzd | rd_issue_hzd |
		pipe1_issue_rs1_hzd | pipe1_issue_rs2_hzd | pipe1_issue_rd_hzd |
		rs1_pending_stall |
		rs2_pending_stall |
		rd_waw_stall;
	assign lsu_struct_stall = id_ctrl_lsu_req & lsu_ctrl_busy;
	assign ready_issue_allow =
		!lsu_struct_stall & !clint_stall & !wb_backpressure & !ex_mul_stall;
	assign bubble_id = scoreboard_stall | lsu_struct_stall | clint_stall | wb_backpressure;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			gpr_pending_q <= '0;
			wb_hzd_valid_q <= 1'b0;
			wb_hzd_addr_q <= '0;
			wb_hzd_data_q <= '0;
`ifndef SYNTHESIS
			mul_inflight_q <= '0;
`endif
		end else if (interrupt) begin
			gpr_pending_q <= '0;
			wb_hzd_valid_q <= 1'b0;
			wb_hzd_addr_q <= '0;
			wb_hzd_data_q <= '0;
`ifndef SYNTHESIS
			mul_inflight_q <= '0;
`endif
		end else begin
			gpr_pending_q <= gpr_pending_for_hazard;
			wb_hzd_valid_q <= rf_wen_rd & (rf_waddr_rd != '0);
			wb_hzd_addr_q <= rf_waddr_rd;
			wb_hzd_data_q <= rf_wdata_rd;
`ifndef SYNTHESIS
			mul_inflight_q <= mul_inflight_q +
				(ex_mul_issue ? 3'd1 : 3'd0) -
				(mul_result_valid ? 3'd1 : 3'd0);
`endif
		end
	end

	assign operator_lsu_type[0] = ex_accept_valid & operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD];
	assign operator_lsu_type[1] = ex_accept_valid & operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];

	assign perip_addr = mmio_addr;
	assign perip_wen = mmio_req && mmio_we;
	assign perip_mask = mmio_wmask;
	assign perip_wdata = mmio_wdata;

`ifdef YDRASIL_ENABLE_PIPE1_REAL
	wire pipe1_instret_inc_count = pipe1_instret_inc;
	wire pipe1_issue_valid_to_ex = pipe1_issue_valid;
	wire [31:0] pipe1_operand_a_to_ex = pipe1_operand_a;
	wire [31:0] pipe1_operand_b_to_ex = pipe1_operand_b;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_operator_to_ex = pipe1_operator;
	wire pipe1_rf_wen_rd_to_ex = pipe1_rf_wen_rd_issue;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_rf_waddr_rd_to_ex = pipe1_rf_waddr_rd_issue;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_alu_result_to_wb = pipe1_alu_result;
	wire pipe1_alu_rf_wen_rd_to_wb = pipe1_alu_rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_alu_rf_waddr_rd_to_wb = pipe1_alu_rf_waddr_rd;
	wire pipe1_resbuf_full_to_id = pipe1_resbuf_full;
`else
	wire pipe1_instret_inc_count = 1'b0;
	wire pipe1_issue_valid_to_ex = 1'b0;
	wire [31:0] pipe1_operand_a_to_ex = '0;
	wire [31:0] pipe1_operand_b_to_ex = '0;
	wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_operator_to_ex = '0;
	wire pipe1_rf_wen_rd_to_ex = 1'b0;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_rf_waddr_rd_to_ex = '0;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_alu_result_to_wb = '0;
	wire pipe1_alu_rf_wen_rd_to_wb = 1'b0;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_alu_rf_waddr_rd_to_wb = '0;
	wire pipe1_resbuf_full_to_id = 1'b0;
`endif

	assign instret_inc = ex_instret_inc | pipe1_instret_inc_count | lsu_rf_wen_rd | mul_result_valid;

	ydrasil_load_store_unit u_ydrasil_load_store_unit (
		.clk               (clk),
		.rst_n             (rst_n),
		.ex_lsu_mem_addr_i (ex_lsu_mem_addr),
		.id_rd_waddr_i      (id_rf_waddr_rd),
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
		.lsu_wb_result_o   (lsu_wb_result),
		.lsu_rf_rd_wen_o   (lsu_rf_wen_rd),
		.lsu_rf_rd_waddr_o (lsu_rf_waddr_rd),
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
			.dbg_sync_bp_redirect_o(),
			.if_id_instr_o   (if_id_instr)
		);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.stall_id_i          (stall_id),
		.bubble_id_i         (bubble_id),
		.flush_id_i          (flush_id),
		.if_id_pc_i          (if_id_pc),
		.if_id_instr_i       (if_id_instr),
		.if_id_pred_hit_i    (if_id_pred_hit),
		.if_id_pred_taken_i  (if_id_pred_taken),
		.if_id_pred_target_i (if_id_pred_target),
		.if_id_pred_counter_i(if_id_pred_counter),
		.if_id_pred_bht_index_i(if_id_pred_bht_index),
		.if_id_pred_l0_taken_i(if_id_pred_l0_taken),
		.if_id_valid_i       (if_id_valid),
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
		.lsu_fwd_data_i     (lsu_wb_result),
		.alu_fwd_valid_i    (alu_rf_wen_rd),
		.alu_fwd_addr_i     (alu_rf_waddr_rd),
		.alu_fwd_data_i     (alu_result),
		.pipe1_alu_fwd_valid_i(pipe1_wb_fwd_valid),
		.pipe1_alu_fwd_addr_i(pipe1_wb_fwd_addr),
		.pipe1_alu_fwd_data_i(pipe1_wb_fwd_data),
		.rs1_issue_alu_ready_next_i(rs1_issue_alu_ready_next),
		.rs2_issue_alu_ready_next_i(rs2_issue_alu_ready_next),
`ifndef SYNTHESIS
		.rs1_issue_alu_stable_bypass_i(rs1_issue_alu_stable_issue_bypass),
		.rs2_issue_alu_stable_bypass_i(rs2_issue_alu_stable_issue_bypass),
`endif
		.ready_issue_allow_i(ready_issue_allow),
		.gpr_pending_i(gpr_pending_for_hazard),
		.pipe1_resbuf_full_i(pipe1_resbuf_full_to_id),
		.issue_frontend_stall_o(id_frontend_stall),
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
`ifndef SYNTHESIS
		.id_ctrl_operator_type_o(id_ctrl_operator_type),
`endif
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
`ifndef SYNTHESIS
		.id_alu_stable_valid_o(id_alu_stable_valid),
		.id_alu_stable_addr_o (id_alu_stable_addr),
		.id_alu_stable_data_o (id_alu_stable_data),
`endif
		.pipe1_issue_valid_o(pipe1_issue_valid),
		.pipe1_operand_a_o  (pipe1_operand_a),
		.pipe1_operand_b_o  (pipe1_operand_b),
		.pipe1_operator_o   (pipe1_operator),
		.pipe1_rf_wen_rd_o  (pipe1_rf_wen_rd_issue),
		.pipe1_rf_waddr_rd_o(pipe1_rf_waddr_rd_issue),
		.pipe1_pc_o         (pipe1_pc),
		.pipe1_instr_o      (pipe1_instr)
`ifndef SYNTHESIS
		,.commit_trace_alloc_valid_o(commit_trace_alloc_valid)
		,.commit_trace_alloc_pc_o(commit_trace_alloc_pc)
		,.commit_trace_alloc_instr_o(commit_trace_alloc_instr)
`endif
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
		.pipe1_issue_valid_i(pipe1_issue_valid_to_ex),
		.pipe1_operand_a_i  (pipe1_operand_a_to_ex),
		.pipe1_operand_b_i  (pipe1_operand_b_to_ex),
		.pipe1_operator_i   (pipe1_operator_to_ex),
		.pipe1_rf_wen_rd_i  (pipe1_rf_wen_rd_to_ex),
		.pipe1_rf_waddr_rd_i(pipe1_rf_waddr_rd_to_ex),
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
		.pipe1_alu_result_o (pipe1_alu_result),
		.pipe1_alu_rf_wen_rd_o(pipe1_alu_rf_wen_rd),
		.pipe1_alu_rf_waddr_rd_o(pipe1_alu_rf_waddr_rd),
		.pipe1_instret_inc_o(pipe1_instret_inc),
		.mul_issue_o        (ex_mul_issue),
		.mul_issue_waddr_o  (ex_mul_issue_waddr),
		.mul_wdata_rd_o     (mul_wb_result),
		.mul_rf_wen_rd_o    (mul_rf_wen_rd),
		.mul_rf_waddr_rd_o  (mul_rf_waddr_rd),
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
		.alu_wdata_rd_i   (alu_result),
		.alu_rf_wen_rd_i  (alu_rf_wen_rd),
		.alu_rf_waddr_rd_i(alu_rf_waddr_rd),
		.pipe1_alu_wdata_rd_i(pipe1_alu_result_to_wb),
		.pipe1_alu_rf_wen_rd_i(pipe1_alu_rf_wen_rd_to_wb),
		.pipe1_alu_rf_waddr_rd_i(pipe1_alu_rf_waddr_rd_to_wb),
		.lsu_wb_result_i  (lsu_wb_result),
		.lsu_rf_wen_rd_i  (lsu_rf_wen_rd),
		.lsu_rf_waddr_rd_i(lsu_rf_waddr_rd),
		.mul_wdata_rd_i   (mul_wb_result),
		.mul_rf_wen_rd_i  (mul_rf_wen_rd),
		.mul_rf_waddr_rd_i(mul_rf_waddr_rd),
		.wb_mul_complete_o(),
		.wb_mul_complete_waddr_o(),
		.wb_backpressure_o(wb_backpressure),
		.pipe1_resbuf_full_o(pipe1_resbuf_full),
		.pipe1_wb_dequeue_o(pipe1_wb_dequeue),
		.pipe1_wb_enqueue_o(pipe1_wb_enqueue),
		.pipe1_fwd_valid_o(pipe1_wb_fwd_valid),
		.pipe1_fwd_addr_o(pipe1_wb_fwd_addr),
		.pipe1_fwd_data_o(pipe1_wb_fwd_data),
		.wb_buf_fwd_valid_o(wb_buf_fwd_valid),
		.wb_buf_fwd_addr_o(wb_buf_fwd_addr),
		.wb_buf_fwd_data_o(wb_buf_fwd_data),
		.rf_wdata_rd_o    (rf_wdata_rd),
		.rf_wen_rd_o      (rf_wen_rd),
		.rf_waddr_rd_o    (rf_waddr_rd)
	);

	ydrasil_registers u_ydrasil_registers (
		.clk          (clk),
		.rst_n        (rst_n),
		.rf_wen_rd_i  (rf_wen_rd),
		.rf_waddr_rd_i(rf_waddr_rd),
		.rf_wdata_rd_i(rf_wdata_rd),
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
			.rst_n             (rst_n),
			.ex_branch_jump_i  (ex_pc_redirect),
			.ex_branch_target_i(ex_pc_redirect_target),
			.scoreboard_stall_i (scoreboard_stall),
			.lsu_struct_stall_i (lsu_struct_stall),
			.id_frontend_stall_i(id_frontend_stall),
	        .clint_stall_i        (clint_stall),
			.ex_mul_stall_i     (ex_mul_stall),
			.wb_backpressure_i  (wb_backpressure),
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
		.instret_inc_i     (instret_inc),
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
	ydrasil_commit_trace u_ydrasil_commit_trace (
		.clk              (clk),
		.rst_n            (rst_n),
		.flush_i          (flush_id | flush_ex | interrupt),
		.alloc_valid_i    (commit_trace_alloc_valid),
		.alloc_pc_i       (commit_trace_alloc_pc),
		.alloc_instr_i    (commit_trace_alloc_instr),
		.alu_valid_i      (commit_ex_valid_q & alu_rf_wen_rd),
		.alu_pc_i         (commit_ex_pc_q),
		.alu_instr_i      (commit_ex_instr_q),
		.alu_waddr_i      (alu_rf_waddr_rd),
		.alu_wdata_i      (alu_result),
		.lsu_issue_valid_i(commit_lsu_issue_valid_q),
		.lsu_issue_pc_i   (commit_lsu_issue_pc_q),
		.lsu_issue_instr_i(commit_lsu_issue_instr_q),
		.lsu_valid_i      (lsu_rf_wen_rd),
		.lsu_waddr_i      (lsu_rf_waddr_rd),
		.lsu_wdata_i      (lsu_wb_result),
		.mul_issue_valid_i(commit_mul_issue_valid_q),
		.mul_issue_pc_i   (commit_mul_issue_pc_q),
		.mul_issue_instr_i(commit_mul_issue_instr_q),
		.mul_valid_i      (mul_rf_wen_rd),
		.mul_waddr_i      (mul_rf_waddr_rd),
		.mul_wdata_i      (mul_wb_result),
		.pipe1_issue_valid_i(commit_pipe1_issue_valid_q),
		.pipe1_issue_pc_i (commit_pipe1_issue_pc_q),
		.pipe1_issue_instr_i(commit_pipe1_issue_instr_q),
		.pipe1_valid_i    (pipe1_alu_rf_wen_rd_to_wb),
		.pipe1_waddr_i    (pipe1_alu_rf_waddr_rd_to_wb),
		.pipe1_wdata_i    (pipe1_alu_result_to_wb)
	);
`endif



endmodule
