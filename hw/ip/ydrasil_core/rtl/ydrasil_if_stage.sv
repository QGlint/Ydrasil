

module ydrasil_if_stage 
import ydrasil_pkg::*;
#(
)(
	input  wire        clk,
	input  wire        rst_n,

	// 流水线控制信号
	input  wire        stall_if_i,
	input  wire        stall_pc_i,
	input  wire        flush_if_i,

		// 后级跳转
		input  wire        branch_jump_i,
		input  wire [31:0] branch_target_i,

		// 分支预测
		input  wire        bp_predict_hit_i,
		input  wire        bp_predict_taken_i,
		input  wire [31:0] bp_predict_target_i,
		input  wire        bp_invalidate_i,

		// 指令存储器接口
		output wire [31:0] if_mem_addr_o,
		input  wire [31:0] if_mem_rdata_i,

		// IF/ID 流水寄存器输出
		output wire [31:0] if_id_pc_o,
		output wire        if_id_pred_hit_o,
		output wire        if_id_pred_taken_o,
		output wire [31:0] if_id_pred_target_o,
		output wire        if_id_valid_o,

		output wire [31:0] if_id_instr_o

	);

	// RV32I 标准 NOP 指令：addi x0, x0, 0
	// 当前 PC、下一拍 PC、以及 PC+4

	wire [31:0] pc_n;
	wire [31:0] pc_plus4;
	wire [31:0] if_id_instr;
	wire [31:0] pc_now;
	reg [31:0] pc_ff;
	reg [31:0] if_id_pc_ff;
	reg [31:0] if_id_instr_ff;
	reg        if_id_pred_hit_ff;
	reg        if_id_pred_taken_ff;
	reg [31:0] if_id_pred_target_ff;
	reg        if_id_valid_ff;
	reg flush_if_ff;
	reg stall_if_ff;

	// 默认顺序取指地址：PC + 4
	assign pc_plus4   = pc_ff + 32'd4;
	// 若发生重定向则跳转到目标 PC，否则顺序执行
	assign pc_n       = branch_jump_i ? branch_target_i :
						stall_pc_i ? pc_ff :
						bp_invalidate_i ? pc_plus4 :
						bp_predict_taken_i ? bp_predict_target_i : pc_plus4;

	assign if_mem_addr_o = pc_ff;

	assign if_id_pc_o    = if_id_pc_ff;
	assign if_id_pred_hit_o = if_id_pred_hit_ff;
	assign if_id_pred_taken_o = if_id_pred_taken_ff;
	assign if_id_pred_target_o = if_id_pred_target_ff;
	assign if_id_valid_o = if_id_valid_ff;
	assign pc_now =  pc_ff;
	assign if_id_instr_o = if_id_instr;
	assign if_id_instr = 
		stall_if_ff? if_id_instr_ff :
		flush_if_ff ? ydrasil_pkg::RV32I_INS_NOP : if_mem_rdata_i;



	// IF 级 PC 寄存器：复位置初值，非停顿时更新
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			pc_ff <= ydrasil_pkg::RESET_INS;
		end else begin
			pc_ff <= pc_n;
		end
	end




	// IF/ID 流水寄存器：支持复位、冲刷和停顿
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			if_id_pc_ff    <= ydrasil_pkg::RESET_INS;
			if_id_pred_hit_ff <= 1'b0;
			if_id_pred_taken_ff <= 1'b0;
			if_id_pred_target_ff <= '0;
			if_id_valid_ff <= 1'b0;
			flush_if_ff     <= 1'b0;
			if_id_instr_ff <= ydrasil_pkg::RV32I_INS_NOP;
			stall_if_ff    <= 1'b0;
		end 
		else begin
			if(flush_if_i) begin
				if_id_pc_ff    <= pc_now;
				if_id_pred_hit_ff <= 1'b0;
				if_id_pred_taken_ff <= 1'b0;
				if_id_pred_target_ff <= '0;
				if_id_valid_ff <= 1'b0;
				flush_if_ff     <= 1'b1;
			end else if(!stall_if_i) begin
				if_id_pc_ff    <= pc_now;
				if_id_pred_hit_ff <= bp_predict_hit_i & !bp_invalidate_i;
				if_id_pred_taken_ff <= bp_predict_taken_i & !bp_invalidate_i;
				if_id_pred_target_ff <= bp_predict_target_i;
				if_id_valid_ff <= 1'b1;
				flush_if_ff     <= 1'b0;
			end
			if_id_instr_ff <= if_id_instr;
			stall_if_ff    <= stall_if_i & !flush_if_i;
		end
	end

endmodule
