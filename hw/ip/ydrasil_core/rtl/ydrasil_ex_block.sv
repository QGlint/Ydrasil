`include "define_alu.svh"
`include "config.svh"

module ydrasil_ex_block #(
	parameter int DATA_WIDTH = 32
)(
	input  logic                            clk_i,
    input  logic                            rst_n_i,
	input  logic                            ex_valid_i,

    input  logic [DATA_WIDTH-1:0]           bt_a_operand_i,
    input  logic [DATA_WIDTH-1:0]           bt_b_operand_i,
	
    input  logic [DATA_WIDTH-1:0]           alu_operand_a_i,
	input  logic [DATA_WIDTH-1:0]           alu_operand_b_i,
	input  logic [`ALU_OP_INFO_WIDTH-1:0]   alu_operator_i,
	input  logic [4:0]                      alu_rd_i,
	input  logic                            int_assert_i,

	output logic                            branch_decision_o,     // to ID
    output logic [DATA_WIDTH-1:0]           branch_target_o, // to IF

	output logic [`REG_DATA_WIDTH-1:0]      result_o,
	output logic                            register_we_o,
	output logic [`REG_ADDR_WIDTH-1:0]      register_waddr_o
);

	logic [DATA_WIDTH-1:0] bt_addr_n;

	// 分支目标地址：EX 内部单独加法器计算 PC + imm_b
	logic [32:0] bt_alu_result;
    assign bt_alu_result = bt_a_operand_i + bt_b_operand_i;
	
    assign branch_target_o = bt_alu_result;

	// 内部例化 ALU，EX 直接透传控制和操作数
	ydrasil_alu #(
		.DATAWIDTH(DATA_WIDTH)
	) u_ydrasil_alu (
		.rst_n            (rst_n_i),
		.req_alu_i        (ex_valid_i),
		.operand_a_i      (alu_operand_a_i),
		.operand_b_i      (alu_operand_b_i),
		.operator_i       (alu_operator_i),
		.alu_rd_i         (alu_rd_i),
		.int_assert_i     (int_assert_i),
		.comp_result_o    (comp_result_o),
		.result_o         (result_o),
		.register_we_o    (register_we_o),
		.register_waddr_o (register_waddr_o)
	);

endmodule
