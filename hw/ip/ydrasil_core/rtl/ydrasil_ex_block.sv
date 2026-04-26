`include "define_decode.svh"
`include "define_mem_reg.svh"

module ydrasil_ex_block #(
	parameter int DATA_WIDTH = 32
)(
	input  wire                            clk_i,
    input  wire                            rst_n_i,
	input  wire                            flush_ex_i,

    input  wire [DATA_WIDTH-1:0]           bt_a_operand_i,
    input  wire [DATA_WIDTH-1:0]           bt_b_operand_i,
	
    input  wire [DATA_WIDTH-1:0]           operand_a_i,
	input  wire [DATA_WIDTH-1:0]           operand_b_i,
	input  wire [`OPERATOR_WIDTH-1:0]      operator_i,
	input  wire [`OPERATOR_TYPE_WIDTH-1:0] operator_type_i,
    input  wire [ 4:0]                     id_rf_waddr_rd_i,
    input  wire                            id_alu_rf_wen_rd_i,

	output wire                            ex_branch_jump_o,      // to CTRL
	output wire [DATA_WIDTH-1:0]           ex_branch_target_o, // to CTRL
    output wire [`BUS_ADDR_WIDTH-1:0]      ex_lsu_mem_addr_o,      // to EX 


    output wire [`REGS_DATA_WIDTH-1:0]     alu_result_o,
    output wire                            alu_rf_wen_rd_o,
    output wire [`REGS_ADDR_WIDTH-1:0]     alu_rf_waddr_rd_o
);

	// 分支目标地址：EX 内部单独加法器计算 PC + imm_b
	wire [31:0] bt_alu_result;
	wire [`REGS_DATA_WIDTH-1:0]     alu_result;
	wire                            alu_rf_wen_rd;
	wire [`REGS_ADDR_WIDTH-1:0]     alu_rf_waddr_rd;

	reg [`REGS_DATA_WIDTH-1:0]     alu_result_ff;
	reg                            alu_rf_wen_rd_ff;
	reg [`REGS_ADDR_WIDTH-1:0]     alu_rf_waddr_rd_ff;
	
	wire ex_branch_jump;

    assign bt_alu_result = bt_a_operand_i + bt_b_operand_i;
	assign ex_lsu_mem_addr_o = alu_result;
    assign ex_branch_target_o = bt_alu_result;

	// 内部例化 ALU，EX 直接透传控制和操作数


	assign ex_branch_jump_o = ex_branch_jump;

	ydrasil_alu #(
		.DATAWIDTH(DATA_WIDTH)
	) u_ydrasil_alu (
		// .rst_n            (rst_n_i),
		// .req_alu_i        (ex_valid_i),
		.operand_a_i      (operand_a_i),
		.operand_b_i      (operand_b_i),
		.operator_i       (operator_i),
		.operator_type_i  (operator_type_i),
		.id_rf_waddr_rd_i (id_rf_waddr_rd_i),
		.id_alu_rf_wen_rd_i   (id_alu_rf_wen_rd_i),
		.comp_result_o    (ex_branch_jump),
		.alu_result_o     (alu_result),
		.alu_rf_wen_rd_o  (alu_rf_wen_rd),
		.alu_rf_waddr_rd_o (alu_rf_waddr_rd)
	);

	always @(posedge clk_i or negedge rst_n_i) begin
		if(!rst_n_i) begin
			alu_result_ff <= '0;
			alu_rf_wen_rd_ff <= 1'b0;
			alu_rf_waddr_rd_ff <= '0;
		end 
		else if(flush_ex_i) begin
			alu_result_ff <= '0;
			alu_rf_wen_rd_ff <= 1'b0;
			alu_rf_waddr_rd_ff <= '0;
		end
		else begin
			alu_result_ff <= alu_result;
			alu_rf_wen_rd_ff <= alu_rf_wen_rd;
			alu_rf_waddr_rd_ff <= alu_rf_waddr_rd;
		end
	end

	assign alu_result_o = alu_result_ff;
	assign alu_rf_wen_rd_o = alu_rf_wen_rd_ff;
	assign alu_rf_waddr_rd_o = alu_rf_waddr_rd_ff;


endmodule
