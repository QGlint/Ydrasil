module if_stage #(
	parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
	input  logic        clk,
	input  logic        rst_n,

	// 流水线控制信号
	input  logic        i_stall_if,
	input  logic        i_stall_id,
	input  logic        i_flush_if_id,

	// 后级重定向（通常来自 EX 级分支/跳转结果）
	input  logic        i_redirect_valid,
	input  logic [31:0] i_redirect_pc,

	// 指令存储器接口
	output logic        o_imem_req,
	output logic [31:0] o_imem_addr,
	input  logic [31:0] i_imem_rdata,
	input  logic        i_imem_valid,

	// IF/ID 流水寄存器输出
	output logic [31:0] o_if_id_pc,
	output logic [31:0] o_if_id_pc4,
	output logic [31:0] o_if_id_instr,
	output logic        o_if_id_valid,

	// 可选调试输出：当前 IF 级 PC
	output logic [31:0] o_if_pc
);

	// RV32I 标准 NOP 指令：addi x0, x0, 0
	localparam logic [31:0] RV32I_NOP = 32'h0000_0013;

	// 当前 PC、下一拍 PC、以及 PC+4
	logic [31:0] pc_q;
	logic [31:0] pc_n;
	logic [31:0] pc_plus4;

	// 默认顺序取指地址：PC + 4
	assign pc_plus4   = pc_q + 32'd4;
	// 若发生重定向则跳转到目标 PC，否则顺序执行
	assign pc_n       = i_redirect_valid ? i_redirect_pc : pc_plus4;

	// 当前实现为常发请求，地址固定取当前 PC
	assign o_imem_req  = rst_n;
	assign o_imem_addr = pc_q;
	assign o_if_pc     = pc_q;

	// IF 级 PC 寄存器：复位置初值，非停顿时更新
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			pc_q <= RESET_PC;
		end else if (!i_stall_if) begin
			pc_q <= pc_n;
		end
	end

	// IF/ID 流水寄存器：支持复位、冲刷和停顿
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			o_if_id_pc    <= RESET_PC;
			o_if_id_pc4   <= RESET_PC + 32'd4;
			o_if_id_instr <= RV32I_NOP;
			o_if_id_valid <= 1'b0;
		end else if (i_flush_if_id || i_redirect_valid) begin
			// 冲刷错误路径指令，向后级注入气泡（NOP + invalid）
			o_if_id_pc    <= pc_q;
			o_if_id_pc4   <= pc_plus4;
			o_if_id_instr <= RV32I_NOP;
			o_if_id_valid <= 1'b0;
		end else if (!i_stall_id) begin
			// 正常拍：锁存当前取指结果到 IF/ID
			o_if_id_pc    <= pc_q;
			o_if_id_pc4   <= pc_plus4;
			o_if_id_instr <= i_imem_rdata;
			o_if_id_valid <= i_imem_valid;
		end
	end

endmodule
