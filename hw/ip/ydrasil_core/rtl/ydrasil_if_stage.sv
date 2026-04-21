
module ydrasil_if_stage #(
	parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
	input  logic        clk_i,
	input  logic        rst_n_i,

	// 流水线控制信号
	input  logic        stall_if_i,
	input  logic        flush_if_i,

	// 后级重定向
	input  logic        redirect_valid_i,
	input  logic [31:0] redirect_pc_i,

	// 指令存储器接口
	output logic [31:0] imem_addr_o,
	input  logic [31:0] imem_rdata_i,

	// IF/ID 流水寄存器输出
	output logic [31:0] if_id_pc_o,

	output logic [31:0] if_id_instr_o

);

	// RV32I 标准 NOP 指令：addi x0, x0, 0
	localparam logic [31:0] RV32I_NOP = 32'h0000_0013;

	// 当前 PC、下一拍 PC、以及 PC+4
	logic [31:0] pc_q;
	logic [31:0] pc_n;
	logic [31:0] pc_plus4;

	logic [31:0] if_id_pc_q;

	logic [31:0] if_id_instr_q;
	logic [31:0] if_id_instr_n;


	// 默认顺序取指地址：PC + 4
	assign pc_plus4   = pc_q + 32'd4;
	// 若发生重定向则跳转到目标 PC，否则顺序执行
	assign pc_n       = redirect_valid_i ? redirect_pc_i : pc_plus4;

	assign imem_addr_o = pc_q;

	assign if_id_pc_o    = if_id_pc_q;

	assign if_id_instr_o = if_id_instr_q;
	assign if_id_instr_n = flush_if_i ? RV32I_NOP : imem_rdata_i;



	// IF 级 PC 寄存器：复位置初值，非停顿时更新
	always_ff @(posedge clk_i or negedge rst_n_i) begin
		if (!rst_n_i) begin
			pc_q <= RESET_PC;
		end else if (!stall_if_i) begin
			pc_q <= pc_n;
		end
	end




	// IF/ID 流水寄存器：支持复位、冲刷和停顿
	always_ff @(posedge clk_i or negedge rst_n_i) begin
		if (!rst_n_i) begin
			if_id_pc_q    <= RESET_PC;
			if_id_instr_q <= RV32I_NOP;
		end 
		else begin
			if_id_pc_q    <= pc_q;
			if_id_instr_q <= if_id_instr_n;
		end
	end

endmodule
