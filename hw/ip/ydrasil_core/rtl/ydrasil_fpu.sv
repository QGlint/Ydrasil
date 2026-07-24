module ydrasil_fpu
import ydrasil_pkg::*;
(
	input  wire                       clk,
	input  wire                       rst_n,
	input  ydrasil_fpu_req_pkt_t      req_i,
	output wire                       req_ready_o,
	input  wire [2:0]                 frm_i,
	input  wire                       result_ready_i,
	output wire                       busy_o,
	output wire                       result_valid_o,
	output wire [REGS_DATA_WIDTH-1:0] result_o,
	output wire [REGS_ADDR_WIDTH-1:0] result_addr_o,
	output wire                       result_fpr_o,
	output wire                       result_gpr_o,
	output producer_id_t              result_producer_id_o,
	output wire                       result_producer_tracked_o,
	output wire [4:0]                 result_fflags_o,
	output wire [INST_ADDR_WIDTH-1:0] result_pc_o,
	output wire [INST_DATA_WIDTH-1:0] result_instr_o
);
	localparam fpnew_pkg::fpu_implementation_t FPU_IMPLEMENTATION = '{
		PipeRegs: '{
			fpnew_pkg::ADDMUL:  '{default: 10},
			fpnew_pkg::DIVSQRT: '{default: 1},
			fpnew_pkg::NONCOMP: '{default: 2},
			fpnew_pkg::CONV:    '{default: 6}
		},
		UnitTypes: '{
			fpnew_pkg::ADDMUL:  '{default: fpnew_pkg::PARALLEL},
			fpnew_pkg::DIVSQRT: '{default: fpnew_pkg::MERGED},
			fpnew_pkg::NONCOMP: '{default: fpnew_pkg::PARALLEL},
			fpnew_pkg::CONV:    '{default: fpnew_pkg::MERGED}
		},
		PipeConfig: fpnew_pkg::DISTRIBUTED
	};

	logic [2:0][REGS_DATA_WIDTH-1:0] fp_operands;
	fpnew_pkg::roundmode_e fp_roundmode;
	fpnew_pkg::operation_e fp_operation;
	logic fp_op_mod;
	logic fp_in_valid;
	logic fp_in_ready;
	logic [REGS_DATA_WIDTH-1:0] fp_result;
	fpnew_pkg::status_t fp_status;
	logic fp_out_valid;
	logic fp_out_ready;
	logic fp_busy;
	logic fp_tag_unused;

	ydrasil_fpu_req_pkt_t input_q;
	reg [2:0] frm_q;
	reg input_valid_q;
	reg pending_q;
	reg result_valid_q;
	reg [REGS_DATA_WIDTH-1:0] result_data_q;
	reg [4:0] result_fflags_q;
	reg [REGS_ADDR_WIDTH-1:0] result_addr_q;
	reg result_fpr_q;
	reg result_gpr_q;
	producer_id_t result_producer_id_q;
	reg result_producer_tracked_q;
	reg [INST_ADDR_WIDTH-1:0] result_pc_q;
	reg [INST_DATA_WIDTH-1:0] result_instr_q;

	wire special_request = (req_i.op == FPU_OP_MV_X_W) ||
		(req_i.op == FPU_OP_MV_W_X);
	wire accepted = req_i.valid && req_ready_o;
	wire input_consumed = fp_in_valid && fp_in_ready;
	wire fp_output_captured = fp_out_valid && fp_out_ready;
	wire output_consumed = result_valid_q && result_ready_i;

	always_comb begin
		fp_operands = {input_q.operand_c, input_q.operand_b, input_q.operand_a};
		fp_roundmode = (input_q.rm == 3'b111) ? fpnew_pkg::roundmode_e'(frm_q) :
			fpnew_pkg::roundmode_e'(input_q.rm);
		fp_operation = fpnew_pkg::FMADD;
		fp_op_mod = 1'b0;
		case (input_q.op)
			FPU_OP_FMADD:  fp_operation = fpnew_pkg::FMADD;
			FPU_OP_FMSUB:  begin fp_operation = fpnew_pkg::FMADD;  fp_op_mod = 1'b1; end
			FPU_OP_FNMSUB: fp_operation = fpnew_pkg::FNMSUB;
			FPU_OP_FNMADD: begin fp_operation = fpnew_pkg::FNMSUB; fp_op_mod = 1'b1; end
			FPU_OP_ADD:    fp_operation = fpnew_pkg::ADD;
			FPU_OP_SUB:    begin fp_operation = fpnew_pkg::ADD; fp_op_mod = 1'b1; end
			FPU_OP_MUL:    fp_operation = fpnew_pkg::MUL;
			FPU_OP_DIV:    fp_operation = fpnew_pkg::DIV;
			FPU_OP_SQRT:   fp_operation = fpnew_pkg::SQRT;
			FPU_OP_SGNJ:   begin fp_operation = fpnew_pkg::SGNJ; fp_roundmode = fpnew_pkg::RNE; end
			FPU_OP_SGNJN:  begin fp_operation = fpnew_pkg::SGNJ; fp_roundmode = fpnew_pkg::RTZ; end
			FPU_OP_SGNJX:  begin fp_operation = fpnew_pkg::SGNJ; fp_roundmode = fpnew_pkg::RDN; end
			FPU_OP_MIN:    begin fp_operation = fpnew_pkg::MINMAX; fp_roundmode = fpnew_pkg::RNE; end
			FPU_OP_MAX:    begin fp_operation = fpnew_pkg::MINMAX; fp_roundmode = fpnew_pkg::RTZ; end
			FPU_OP_LE:     begin fp_operation = fpnew_pkg::CMP; fp_roundmode = fpnew_pkg::RNE; end
			FPU_OP_LT:     begin fp_operation = fpnew_pkg::CMP; fp_roundmode = fpnew_pkg::RTZ; end
			FPU_OP_EQ:     begin fp_operation = fpnew_pkg::CMP; fp_roundmode = fpnew_pkg::RDN; end
			FPU_OP_CLASS:  fp_operation = fpnew_pkg::CLASSIFY;
			FPU_OP_CVT_W_S:  fp_operation = fpnew_pkg::F2I;
			FPU_OP_CVT_WU_S: begin fp_operation = fpnew_pkg::F2I; fp_op_mod = 1'b1; end
			FPU_OP_CVT_S_W:  fp_operation = fpnew_pkg::I2F;
			FPU_OP_CVT_S_WU: begin fp_operation = fpnew_pkg::I2F; fp_op_mod = 1'b1; end
			default: fp_operation = fpnew_pkg::FMADD;
		endcase
		if ((input_q.op == FPU_OP_ADD) || (input_q.op == FPU_OP_SUB)) begin
			fp_operands[1] = input_q.operand_a;
			fp_operands[2] = input_q.operand_b;
		end
	end

	// 输入边界寄存后再驱动 FPnew，ready 只依赖本地状态，避免 FPnew 的
	// 组合反压路径穿过 issue/decode。
	assign fp_in_valid = input_valid_q;
	assign req_ready_o = !pending_q && !input_valid_q && !result_valid_q;
	// 独立的一项输出缓冲切断核心写回反压到 FPnew 内部状态的组合路径。
	assign fp_out_ready = pending_q && !result_valid_q;

	fpnew_top #(
		.Features(fpnew_pkg::RV32F),
		.Implementation(FPU_IMPLEMENTATION),
		.PulpDivsqrt(1'b0),
		.TagType(logic)
	) u_fpnew (
		.clk_i(clk), .rst_ni(rst_n), .operands_i(fp_operands),
		.rnd_mode_i(fp_roundmode), .op_i(fp_operation), .op_mod_i(fp_op_mod),
		.src_fmt_i(fpnew_pkg::FP32), .dst_fmt_i(fpnew_pkg::FP32),
		.int_fmt_i(fpnew_pkg::INT32), .vectorial_op_i(1'b0), .tag_i(1'b0),
		.simd_mask_i(1'b1), .in_valid_i(fp_in_valid), .in_ready_o(fp_in_ready),
		.flush_i(1'b0), .result_o(fp_result), .status_o(fp_status),
		.tag_o(fp_tag_unused), .out_valid_o(fp_out_valid),
		.out_ready_i(fp_out_ready), .busy_o(fp_busy)
	);

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			input_q <= '0;
			frm_q <= '0;
			input_valid_q <= 1'b0;
			pending_q <= 1'b0;
			result_valid_q <= 1'b0;
			result_data_q <= '0;
			result_fflags_q <= '0;
			result_addr_q <= '0;
			result_fpr_q <= 1'b0;
			result_gpr_q <= 1'b0;
			result_producer_id_q <= '0;
			result_producer_tracked_q <= 1'b0;
			result_pc_q <= '0;
			result_instr_q <= '0;
		end else begin
			if (input_consumed)
				input_valid_q <= 1'b0;
			if (output_consumed)
				result_valid_q <= 1'b0;
			if (fp_output_captured) begin
				pending_q <= 1'b0;
				result_valid_q <= 1'b1;
				result_data_q <= fp_result;
				result_fflags_q <=
					{fp_status.NV, fp_status.DZ, fp_status.OF, fp_status.UF, fp_status.NX};
			end
			if (accepted) begin
				input_q <= req_i;
				frm_q <= frm_i;
				input_valid_q <= !special_request;
				pending_q <= !special_request;
				if (special_request) begin
					result_valid_q <= 1'b1;
					result_data_q <= req_i.operand_a;
					result_fflags_q <= '0;
				end
				result_addr_q <= req_i.rd_addr;
				result_fpr_q <= req_i.rd_fpr;
				result_gpr_q <= req_i.rd_gpr;
				result_producer_id_q <= req_i.producer_id;
				result_producer_tracked_q <= req_i.producer_tracked;
				result_pc_q <= req_i.pc;
				result_instr_q <= req_i.instr;
			end
		end
	end

	assign busy_o = pending_q || input_valid_q || result_valid_q || fp_busy;
	assign result_valid_o = result_valid_q;
	assign result_o = result_data_q;
	assign result_addr_o = result_addr_q;
	assign result_fpr_o = result_fpr_q;
	assign result_gpr_o = result_gpr_q;
	assign result_producer_id_o = result_producer_id_q;
	assign result_producer_tracked_o = result_producer_tracked_q;
	assign result_fflags_o = result_fflags_q;
	assign result_pc_o = result_pc_q;
	assign result_instr_o = result_instr_q;
endmodule
