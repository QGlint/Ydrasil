

module ydrasil_core
import ydrasil_pkg::*;
	 #(
		parameter int BP_ENTRIES  = 0,
		parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
		parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES
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
    ,output wire [31:0] dbg_bp_pred_next_pc_o
    ,output wire        dbg_bp_mispredict_o
`endif
);

	// IF <-> MEMS
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_lookup_pc;
	wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] if_mem_rdata;

	// IF/ID pipeline
	wire [31:0] if_id_pc;
	wire [31:0] if_id_instr;
	wire        if_id_pred_hit;
	wire        if_id_pred_taken;
	wire [31:0] if_id_pred_target;
	wire [1:0]  if_id_pred_counter;
	wire [31:0] if_id_pred_bht_index;
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
	ydrasil_lsu_req_pkt_t         ex_lsu_req_pkt;
	ydrasil_lsu_req_pkt_t         agu_req_q;
	ydrasil_lsu_req_pkt_t         lsu_req_pkt;
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
	wire                        ex_instret_inc;
	wire                        ex_pc_redirect;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_pc_redirect_target;
	wire                        ex_bp_train_valid;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_bp_train_pc;
	wire                        ex_bp_train_taken;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_bp_train_target;
	wire [1:0]                  ex_bp_train_counter;
	wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_bp_train_bht_index;
	reg                         bp_train_valid_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_train_pc_q;
	reg                         bp_train_taken_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_train_target_q;
	reg [1:0]                   bp_train_counter_q;
	reg [ydrasil_pkg::INST_ADDR_WIDTH-1:0] bp_train_bht_index_q;
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
	ydrasil_mem_req_pkt_t       dtcm_req_pkt;
	ydrasil_mem_req_pkt_t       mmio_req_pkt;
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

	// WB -> RF
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd;
	wire                        rf_wen_rd;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd;
	wire [ydrasil_pkg::REGS_NUM-1:0] rf_write_wen;
	producer_id_t               rf_producer_id;
	wire                        rf_producer_tracked;
	wire                        rf_write_commit;
	wire                        wb_backpressure;
	wire                        wb_hzd_valid_q;
	wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_hzd_addr_q;
	wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] wb_hzd_data_q;

    //LSU -> CTRL
	wire                            lsu_ctrl_busy;
	wire                            lsu_fast_load;

    //LSU -> ID
	ydrasil_id_ctrl_pkt_t           id_ctrl_pkt;
	ydrasil_ex_hzd_pkt_t            ex_hzd_pkt;
	ydrasil_hzd_status_pkt_t        hzd_status_pkt;
	ydrasil_gpr_fwd_pkt_t           wb_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           producer_rs1_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           producer_rs2_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           lsu_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           alu_fwd_pkt;
	ydrasil_gpr_fwd_pkt_t           mul_fwd_pkt;
	ydrasil_completion_bus_t        completion_bus;
	ydrasil_decode_pkt_t            decode_pkt;
	wire                            decode_valid;
	wire                            decode_if_ready;
	wire                            issue_ready;
	wire                            id_ex_execute_valid;
	wire                            id_ex_operand_wait;
	wire                            ex_backend_stall;
	wire                            agu_req_send;
	wire                            agu_req_ready;
	wire                            agu_req_stall;
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
	wire [1:0]                       instret_inc_count;

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
		end else begin
			commit_ex_valid_q <= id_ex_execute_valid & !interrupt & !flush_ex;
			commit_ex_pc_q <= id_instr_addr;
			commit_ex_instr_q <= commit_alu_instr;
			commit_lsu_issue_valid_q <= ex_accept_valid & operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD];
			commit_lsu_issue_pc_q <= id_instr_addr;
			commit_lsu_issue_instr_q <= commit_lsu_instr;
			commit_mul_issue_valid_q <= ex_mul_issue;
			commit_mul_issue_pc_q <= id_instr_addr;
			commit_mul_issue_instr_q <= commit_mul_instr;
		end
	end
`endif

	assign agu_req_send = agu_req_q.valid && !lsu_status_pkt.busy;
	assign agu_req_ready = !agu_req_q.valid || agu_req_send;
	assign agu_req_stall = id_ex_valid &&
		(operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] ||
		 operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
		!agu_req_ready;
	assign id_ex_execute_valid = id_ex_valid && !id_ex_operand_wait &&
		!agu_req_stall;
	assign ex_backend_stall = ex_mul_stall | agu_req_stall |
		id_ex_operand_wait;

	assign ex_hzd_pkt.valid = id_ex_execute_valid;
	assign ex_hzd_pkt.interrupt = interrupt;
	assign ex_hzd_pkt.producer_id = id_ex_producer_id;
	assign ex_hzd_pkt.producer_tracked = id_ex_producer_tracked;
	assign ex_hzd_pkt.rd_addr = id_rf_waddr_rd;
	assign ex_hzd_pkt.alu_rf_wen = id_alu_rf_wen_rd;
	assign ex_hzd_pkt.operator_type = operator_type;
	assign ex_hzd_pkt.operator_info = operator;
	assign alu_fwd_pkt.valid = alu_rf_wen_rd;
	assign alu_fwd_pkt.producer_id = alu_producer_id;
	assign alu_fwd_pkt.producer_tracked = alu_fwd_pkt.valid && (alu_fwd_pkt.addr != '0);
	assign alu_fwd_pkt.addr = alu_rf_waddr_rd;
	assign alu_fwd_pkt.data = alu_result;
	assign mul_fwd_pkt.valid = mul_rf_wen_rd;
	assign mul_fwd_pkt.producer_id = mul_producer_id;
	assign mul_fwd_pkt.producer_tracked = mul_fwd_pkt.valid && (mul_fwd_pkt.addr != '0);
	assign mul_fwd_pkt.addr = mul_rf_waddr_rd;
	assign mul_fwd_pkt.data = mul_wb_result;
	assign completion_bus[ydrasil_pkg::COMPLETION_ALU] = alu_fwd_pkt;
	assign completion_bus[ydrasil_pkg::COMPLETION_LSU] = lsu_fwd_pkt;
	assign completion_bus[ydrasil_pkg::COMPLETION_MUL] = mul_fwd_pkt;
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
		ex_lsu_req_pkt = id_lsu_req_pkt;
		ex_lsu_req_pkt.valid = id_lsu_req_pkt.valid & ex_accept_valid;
		ex_lsu_req_pkt.addr = ex_lsu_mem_addr;
		ex_lsu_req_pkt.store_data = ex_lsu_result;
		ex_lsu_req_pkt.addr_is_dtcm =
			(ex_lsu_mem_addr[31:ydrasil_pkg::DTCM_ADDR_WIDTH+2] ==
			 ydrasil_pkg::DTCM_BASE_ADDR[31:ydrasil_pkg::DTCM_ADDR_WIDTH+2]);
		if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SB])
			ex_lsu_req_pkt.store_mask = 4'b0001 << ex_lsu_mem_addr[1:0];
		else if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SH])
			ex_lsu_req_pkt.store_mask = ex_lsu_mem_addr[1] ? 4'b1100 : 4'b0011;
		else if (id_lsu_req_pkt.op[ydrasil_pkg::OP_LSU_SW])
			ex_lsu_req_pkt.store_mask = 4'b1111;
		else
			ex_lsu_req_pkt.store_mask = 4'b0000;
	end

	reg agu_held_store_wake_valid;
	reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] agu_held_store_wake_data;
	reg agu_input_store_wake_valid;
	reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] agu_input_store_wake_data;
	integer agu_wake_lane;
	always_comb begin
		agu_held_store_wake_valid = 1'b0;
		agu_held_store_wake_data = '0;
		agu_input_store_wake_valid = 1'b0;
		agu_input_store_wake_data = '0;
		for (agu_wake_lane = 0; agu_wake_lane < ydrasil_pkg::COMPLETION_LANES;
		     agu_wake_lane = agu_wake_lane + 1) begin
			if (agu_req_q.valid && agu_req_q.is_store &&
			    !agu_req_q.store_data_valid &&
			    agu_req_q.store_data_producer_tracked &&
			    completion_bus[agu_wake_lane].valid &&
			    completion_bus[agu_wake_lane].producer_tracked &&
			    (completion_bus[agu_wake_lane].producer_id ==
			     agu_req_q.store_data_producer_id)) begin
				agu_held_store_wake_valid = 1'b1;
				agu_held_store_wake_data = completion_bus[agu_wake_lane].data;
			end
			if (ex_lsu_req_pkt.valid && ex_lsu_req_pkt.is_store &&
			    !ex_lsu_req_pkt.store_data_valid &&
			    ex_lsu_req_pkt.store_data_producer_tracked &&
			    completion_bus[agu_wake_lane].valid &&
			    completion_bus[agu_wake_lane].producer_tracked &&
			    (completion_bus[agu_wake_lane].producer_id ==
			     ex_lsu_req_pkt.store_data_producer_id)) begin
				agu_input_store_wake_valid = 1'b1;
				agu_input_store_wake_data = completion_bus[agu_wake_lane].data;
			end
		end
	end

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			agu_req_q <= '0;
		end else begin
			if (agu_req_send)
				agu_req_q.valid <= 1'b0;
			else if (agu_held_store_wake_valid) begin
				agu_req_q.store_data <= agu_held_store_wake_data;
				agu_req_q.store_data_valid <= 1'b1;
				agu_req_q.store_data_producer_tracked <= 1'b0;
			end

			if (ex_lsu_req_pkt.valid && agu_req_ready) begin
				agu_req_q <= ex_lsu_req_pkt;
				if (agu_input_store_wake_valid) begin
					agu_req_q.store_data <= agu_input_store_wake_data;
					agu_req_q.store_data_valid <= 1'b1;
					agu_req_q.store_data_producer_tracked <= 1'b0;
				end
			end
		end
	end

	always_comb begin
		lsu_req_pkt = agu_req_q;
		lsu_req_pkt.valid = agu_req_send;
	end
	assign scoreboard_stall = hzd_status_pkt.scoreboard_stall;
	assign lsu_struct_stall = hzd_status_pkt.lsu_struct_stall;
	assign issue_store_data_ready = hzd_status_pkt.issue_store_data_ready;
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
	assign lsu_wb_result = lsu_fwd_pkt.data;
	assign lsu_rf_wen_rd = lsu_fwd_pkt.valid;
	assign lsu_rf_waddr_rd = lsu_fwd_pkt.addr;
	assign lsu_producer_id = lsu_fwd_pkt.producer_id;
	assign lsu_producer_tracked = lsu_fwd_pkt.producer_tracked;
	assign lsu_ctrl_busy = lsu_status_pkt.busy;
	assign lsu_fast_load = lsu_status_pkt.fast_load;

	assign perip_addr = mmio_req_pkt.addr;
	assign perip_wen = mmio_req_pkt.valid && mmio_req_pkt.write;
	assign perip_mask = mmio_req_pkt.wmask;
	assign perip_wdata = mmio_req_pkt.wdata;
	assign instret_inc_count =
		{1'b0, ex_instret_inc} + {1'b0, lsu_rf_wen_rd} + {1'b0, mul_result_valid};

	ydrasil_load_store_unit u_ydrasil_load_store_unit (
		.clk               (clk),
		.rst_n             (rst_n),
		.req_i             (lsu_req_pkt),
		.completion_bus_i  (completion_bus),
		.dtcm_rdata_i      (dtcm_rdata),
		.dtcm_req_o        (dtcm_req_pkt),
		.mmio_rdata_i      (perip_rdata),
		.mmio_req_o        (mmio_req_pkt),
		.status_o          (lsu_status_pkt),
		.completion_o      (lsu_fwd_pkt)
	);

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			bp_train_valid_q <= 1'b0;
			bp_train_pc_q <= '0;
			bp_train_taken_q <= 1'b0;
			bp_train_target_q <= '0;
			bp_train_counter_q <= 2'b01;
			bp_train_bht_index_q <= '0;
		end else begin
			bp_train_valid_q <= ex_bp_train_valid;
			bp_train_pc_q <= ex_bp_train_pc;
			bp_train_taken_q <= ex_bp_train_taken;
			bp_train_target_q <= ex_bp_train_target;
			bp_train_counter_q <= ex_bp_train_counter;
			bp_train_bht_index_q <= ex_bp_train_bht_index;
		end
	end

		ydrasil_branch_predictor #(
			.BP_ENTRIES(BP_ENTRIES),
			.BTB_ENTRIES(BTB_ENTRIES),
			.BHT_ENTRIES(BHT_ENTRIES)
		) u_ydrasil_branch_predictor (
			.clk              (clk),
			.rst_n            (rst_n),
			.predict_pc_i     (bp_lookup_pc),
			.predict_hit_o    (bp_predict_hit),
			.predict_taken_o  (bp_predict_taken),
			.predict_target_o (bp_predict_target),
			.predict_counter_o(bp_predict_counter),
			.predict_bht_index_o(bp_predict_bht_index),
			.train_valid_i    (bp_train_valid_q),
			.train_pc_i       (bp_train_pc_q),
			.train_taken_i    (bp_train_taken_q),
			.train_target_i   (bp_train_target_q),
			.train_counter_i  (bp_train_counter_q),
			.train_bht_index_i(bp_train_bht_index_q),
			.invalidate_i     (id_fence_i)
		);

		ydrasil_if_stage u_ydrasil_if_stage (
			.clk           (clk),
			.rst_n         (rst_n),
			.stall_if_i      (!decode_if_ready),
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
			.if_mem_addr_o   (if_mem_addr),
			.bp_lookup_pc_o   (bp_lookup_pc),
			.if_mem_rdata_i  (if_mem_rdata),
			.if_id_pc_o      (if_id_pc),
			.if_id_pred_hit_o(if_id_pred_hit),
			.if_id_pred_taken_o(if_id_pred_taken),
			.if_id_pred_target_o(if_id_pred_target),
			.if_id_pred_counter_o(if_id_pred_counter),
			.if_id_pred_bht_index_o(if_id_pred_bht_index),
			.if_id_valid_o   (if_id_valid),
			.if_id_instr_o   (if_id_instr)
		);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.flush_i             (flush_id),
		.issue_ready_i       (issue_ready),
		.if_id_pc_i          (if_id_pc),
		.if_id_instr_i       (if_id_instr),
		.if_id_pred_hit_i    (if_id_pred_hit),
		.if_id_pred_taken_i  (if_id_pred_taken),
		.if_id_pred_target_i (if_id_pred_target),
		.if_id_pred_counter_i(if_id_pred_counter),
		.if_id_pred_bht_index_i(if_id_pred_bht_index),
		.if_id_valid_i       (if_id_valid),
		.if_id_ready_o       (decode_if_ready),
		.decode_valid_o      (decode_valid),
		.decode_pkt_o        (decode_pkt)
	);

	ydrasil_issue_stage u_ydrasil_issue_stage (
		.clk                 (clk),
		.rst_n               (rst_n),
		.stall_id_i          (stall_id),
		.bubble_id_i         (bubble_id),
		.flush_id_i          (flush_id),
		.decode_valid_i      (decode_valid),
		.decode_pkt_i        (decode_pkt),
		.issue_ready_o       (issue_ready),
		.rf_addr_rs1_o       (rf_raddr_rs1),
		.rf_addr_rs2_o      (rf_raddr_rs2),
		.rf_rdata_rs1_i     (rf_rdata_rs1),
		.rf_rdata_rs2_i     (rf_rdata_rs2),
		.wb_fwd_i           (wb_fwd_pkt),
			.producer_rs1_fwd_i (producer_rs1_fwd_pkt),
			.producer_rs2_fwd_i (producer_rs2_fwd_pkt),
				.completion_bus_i   (completion_bus),
			.hzd_status_i       (hzd_status_pkt),
		.producer_alloc_id_i(producer_alloc_id),
		.producer_alloc_tracked_i(producer_alloc_tracked),
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
			.id_ex_operand_wait_o(id_ex_operand_wait),
		.id_ex_producer_id_o(id_ex_producer_id),
		.id_ex_producer_tracked_o(id_ex_producer_tracked),
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
		.interrupt_i        (interrupt),
		.clint_ex_int_addr_i(clint_ex_int_addr),
		.id_rf_waddr_rd_i   (id_rf_waddr_rd),
		.id_alu_rf_wen_rd_i (id_alu_rf_wen_rd),
		.id_ex_producer_id_i(id_ex_producer_id),
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
		.alu_producer_id_o  (alu_producer_id),
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

	ydrasil_mems u_ydrasil_mems (
		.clk           (clk),
		.rst_n         (rst_n),
		.if_mem_addr_i (if_mem_addr),
		.if_mem_rdata_o(if_mem_rdata),
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
		.mul_wdata_rd_i   (mul_wb_result),
		.mul_rf_wen_rd_i  (mul_rf_wen_rd),
		.mul_rf_waddr_rd_i(mul_rf_waddr_rd),
		.mul_producer_id_i(mul_producer_id),
		.wb_mul_complete_o(),
		.wb_mul_complete_waddr_o(),
		.wb_backpressure_o(wb_backpressure),
		.rf_wdata_rd_o    (rf_wdata_rd),
		.rf_wen_rd_o      (rf_wen_rd),
		.rf_waddr_rd_o    (rf_waddr_rd),
		.rf_producer_id_o (rf_producer_id)
		,.rf_producer_tracked_o(rf_producer_tracked)
	);

	ydrasil_registers u_ydrasil_registers (
		.clk          (clk),
		.rst_n        (rst_n),
		.rf_write_wen_i(rf_write_wen),
		.rf_wdata_rd_i(rf_wdata_rd),
		.rf_raddr_rs1_i(rf_raddr_rs1),
		.rf_rdata_rs1_o(rf_rdata_rs1),
		.rf_raddr_rs2_i(rf_raddr_rs2),
		.rf_rdata_rs2_o(rf_rdata_rs2)
	);

		ydrasil_ctrl u_ctrl (
			.clk               (clk),
			.rst_n             (rst_n),
			.ex_branch_jump_i  (ex_pc_redirect),
			.ex_branch_target_i(ex_pc_redirect_target),
			.ex_hzd_i          (ex_hzd_pkt),
			.id_ctrl_i         (id_ctrl_pkt),
			.completion_bus_i  (completion_bus),
			.lsu_status_i      (lsu_status_pkt),
			.clint_stall_i     (clint_stall),
			.ex_mul_stall_i     (ex_backend_stall),
			.wb_backpressure_i  (wb_backpressure),
			.rf_wen_rd_i       (rf_wen_rd),
			.rf_waddr_rd_i     (rf_waddr_rd),
			.rf_wdata_rd_i     (rf_wdata_rd),
			.rf_producer_id_i  (rf_producer_id),
			.rf_producer_tracked_i(rf_producer_tracked),
			.hzd_status_o      (hzd_status_pkt),
			.wb_fwd_o          (wb_fwd_pkt),
			.producer_rs1_fwd_o(producer_rs1_fwd_pkt),
			.producer_rs2_fwd_o(producer_rs2_fwd_pkt),
			.gpr_pending_o     (gpr_pending_q),
			.ex_accept_valid_o (ex_accept_valid),
			.producer_alloc_id_o(producer_alloc_id),
			.producer_alloc_tracked_o(producer_alloc_tracked),
			.rf_write_commit_o(rf_write_commit),
			.rf_write_wen_o   (rf_write_wen),
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
		.mul_wdata_i      (mul_wb_result)
	);
`endif



endmodule
