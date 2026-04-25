`include "define_decode.svh"
`include "define_mem_reg.svh"

module ydrasil_core #(
	parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
	input  logic clk_i,
	input  logic rst_n_i
    
    
    ,output logic [31:0]  perip_addr,
    output logic         perip_wen,
	output logic [ 1:0]  perip_mask,
    output logic [31:0]  perip_wdata,
    input  logic [31:0]  perip_rdata
);

	// IF <-> MEMS
	logic [`INST_ADDR_WIDTH-1:0] if_mem_addr;
	logic [`INST_DATA_WIDTH-1:0] if_mem_rdata;

	// IF/ID pipeline
	logic [31:0] if_id_pc;
	logic [31:0] if_id_instr;

	// CTRL signals
	logic                        stall_if;
	logic                        stall_id;
	logic                        flush_if;
	logic                        flush_id;
	logic                        flush_ex;
	logic                        branch_jump;
	logic [`INST_ADDR_WIDTH-1:0] branch_target;

	// ID <-> RF
	logic [`REGS_ADDR_WIDTH-1:0] rf_raddr_rs1;
	logic [`REGS_ADDR_WIDTH-1:0] rf_raddr_rs2;
	logic [`REGS_DATA_WIDTH-1:0] rf_rdata_rs1;
	logic [`REGS_DATA_WIDTH-1:0] rf_rdata_rs2;

	// ID -> EX
	logic [31:0]                    operand_a;
	logic [31:0]                    operand_b;
	logic [`OPERATOR_WIDTH-1:0]     operator;
	logic [31:0]                    bt_a_operand;
	logic [31:0]                    bt_b_operand;
	logic [`OP_LSU_INFO_WIDTH-1:0]  operator_lsu;
	logic [31:0]                    id_lsu_rs2_data;
	logic [`OPERATOR_TYPE_WIDTH-1:0] operator_type;
	logic                           id_alu_rf_wen_rd;
	logic [`REGS_ADDR_WIDTH-1:0]    id_rf_waddr_rd;

	// EX outputs
	logic                        ex_branch_jump;
	logic [`INST_ADDR_WIDTH-1:0] ex_branch_target;
	logic [`BUS_ADDR_WIDTH-1:0]  ex_lsu_mem_addr;
	logic [`REGS_DATA_WIDTH-1:0] alu_result;
	logic                        alu_rf_wen_rd;
	logic [`REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd;

	// LSU request path
	logic [1:0]                  operator_lsu_type;
	logic [`BUS_DATA_WIDTH-1:0]  lsu_mem_wdata;
	logic [`BUS_ADDR_WIDTH-1:0]  lsu_mem_addr;
	logic                        lsu_mem_we;
	logic                        lsu_mem_req;
	logic [3:0]                  lsu_mem_wmask;
	logic [`BUS_DATA_WIDTH-1:0]  lsu_mem_rdata;
	logic                        hold_flag;

	logic [`REGS_DATA_WIDTH-1:0] lsu_wb_result;
	logic                        lsu_rf_wen_rd;
	logic [`REGS_ADDR_WIDTH-1:0] lsu_rf_waddr_rd;

	// WB -> RF
	logic [`REGS_DATA_WIDTH-1:0] rf_wdata_rd;
	logic                        rf_wen_rd;
	logic [`REGS_ADDR_WIDTH-1:0] rf_waddr_rd;

	assign operator_lsu_type[0] = operator_type[`OPERATOR_TYPE_LOAD];
	assign operator_lsu_type[1] = operator_type[`OPERATOR_TYPE_STORE];

	ydrasil_load_store_unit u_ydrasil_load_store_unit (
		.clk               (clk_i),
		.rst_n             (rst_n_i),
		.ex_lsu_mem_addr_i (ex_lsu_mem_addr),
		.id_rd_waddr_i      (id_rf_waddr_rd),
		.operator_lsu_i    (operator_lsu),
		.operator_lsu_type_i(operator_lsu_type),
		.id_lsu_rs2_data_i (id_lsu_rs2_data),
		.lsu_mem_rdata_i   (lsu_mem_rdata),
		.lsu_mem_wdata_o   (lsu_mem_wdata),
		.lsu_mem_addr_o    (lsu_mem_addr),
		.lsu_mem_wen_o     (lsu_mem_we),
		.lsu_mem_req_o     (lsu_mem_req),
		.lsu_mem_wmask_o   (lsu_mem_wmask),
		.lsu_wb_result_o   (lsu_wb_result),
		.lsu_rf_rd_wen_o   (lsu_rf_wen_rd),
		.lsu_rf_rd_waddr_o (lsu_rf_waddr_rd)
	);

	ydrasil_if_stage #(
		.RESET_PC(RESET_PC)
	) u_ydrasil_if_stage (
		.clk_i           (clk_i),
		.rst_n_i         (rst_n_i),
		.stall_if_i      (stall_if),
		.flush_if_i      (flush_if),
		.branch_jump_i   (branch_jump),
		.branch_target_i (branch_target),
		.if_mem_addr_o   (if_mem_addr),
		.if_mem_rdata_i  (if_mem_rdata),
		.if_id_pc_o      (if_id_pc),
		.if_id_instr_o   (if_id_instr)
	);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk_i              (clk_i),
		.rst_n_i            (rst_n_i),
		.stall_id_i         (stall_id),
		.flush_id_i         (flush_id),
		.if_id_pc_i         (if_id_pc),
		.if_id_instr_i      (if_id_instr),
		.rf_addr_rs1_o      (rf_raddr_rs1),
		.rf_addr_rs2_o      (rf_raddr_rs2),
		.rf_rdata_rs1_i     (rf_rdata_rs1),
		.rf_rdata_rs2_i     (rf_rdata_rs2),
		.operand_a_o        (operand_a),
		.operand_b_o        (operand_b),
		.operator_o         (operator),
		.bt_a_operand_o     (bt_a_operand),
		.bt_b_operand_o     (bt_b_operand),
		.operator_lsu_o     (operator_lsu),
		.id_lsu_rs2_data_o  (id_lsu_rs2_data),
		.operator_type_o    (operator_type),
		.id_alu_rf_wen_rd_o (id_alu_rf_wen_rd),
		.id_rf_waddr_rd_o   (id_rf_waddr_rd)
	);

	ydrasil_ex_block u_ydrasil_ex_block (
		.clk_i              (clk_i),
		.rst_n_i            (rst_n_i),
		.flush_ex_i         (flush_ex),
		.bt_a_operand_i     (bt_a_operand),
		.bt_b_operand_i     (bt_b_operand),
		.operand_a_i        (operand_a),
		.operand_b_i        (operand_b),
		.operator_i         (operator),
		.operator_type_i    (operator_type),
		.id_rf_waddr_rd_i   (id_rf_waddr_rd),
		.id_alu_rf_wen_rd_i (id_alu_rf_wen_rd),
		.ex_branch_jump_o   (ex_branch_jump),
		.ex_branch_target_o (ex_branch_target),
		.ex_lsu_mem_addr_o  (ex_lsu_mem_addr),
		.alu_result_o       (alu_result),
		.alu_rf_wen_rd_o    (alu_rf_wen_rd),
		.alu_rf_waddr_rd_o  (alu_rf_waddr_rd)
	);

	ydrasil_mems u_ydrasil_mems (
		.clk           (clk_i),
		.rst_n         (rst_n_i),
		.if_mem_addr_o (if_mem_addr),
		.if_mem_rdata_i(if_mem_rdata),
		.lsu_mem_addr_i(lsu_mem_addr),
		.lsu_mem_data_i(lsu_mem_wdata),
		.lsu_mem_data_o(lsu_mem_rdata),
		.lsu_mem_we_i  (lsu_mem_we),
		.lsu_mem_req_i (lsu_mem_req),
		.lsu_mem_wmask_i(lsu_mem_wmask),
		.hold_flag_o   (hold_flag)
	);

	ydrasil_wb_stage u_ydrasil_wb_stage (
		.clk              (clk_i),
		.rst_n            (rst_n_i),
		.alu_wdata_rd_i   (alu_result),
		.alu_rf_wen_rd_i  (alu_rf_wen_rd),
		.alu_rf_waddr_rd_i(alu_rf_waddr_rd),
		.lsu_wb_result_i  (lsu_wb_result),
		.lsu_rf_wen_rd_i  (lsu_rf_wen_rd),
		.lsu_rf_waddr_rd_i(lsu_rf_waddr_rd),
		.rf_wdata_rd_o    (rf_wdata_rd),
		.rf_wen_rd_o      (rf_wen_rd),
		.rf_waddr_rd_o    (rf_waddr_rd)
	);

	ydrasil_registers u_ydrasil_registers (
		.clk          (clk_i),
		.rst_n        (rst_n_i),
		.rf_wen_rd_i  (rf_wen_rd),
		.rf_waddr_rd_i(rf_waddr_rd),
		.rf_wdata_rd_i(rf_wdata_rd),
		.rf_raddr_rs1_i(rf_raddr_rs1),
		.rf_rdata_rs1_o(rf_rdata_rs1),
		.rf_raddr_rs2_i(rf_raddr_rs2),
		.rf_rdata_rs2_o(rf_rdata_rs2)
	);

	ydrasil_ctrl u_ctrl (
		.rst_n             (rst_n_i),
		.ex_branch_jump_i  (ex_branch_jump),
		.ex_branch_target_i(ex_branch_target),
		.stall_if_o        (stall_if),
		.stall_id_o        (stall_id),
		.flush_if_o        (flush_if),
		.flush_id_o        (flush_id),
		.flush_ex_o        (flush_ex),
		.branch_jump_o     (branch_jump),
		.branch_target_o   (branch_target)
	);

endmodule
