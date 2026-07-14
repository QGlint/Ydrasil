

module ydrasil_if_stage 
import ydrasil_pkg::*;
#(
	parameter int FETCHQ_DEPTH = 4
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
		input  wire [1:0]  bp_predict_counter_i,
		input  wire [31:0] bp_predict_bht_index_i,
		input  wire        bp_invalidate_i,

		// 指令存储器接口
		output wire [31:0] if_mem_addr_o,
		output wire [31:0] bp_lookup_pc_o,
		input  wire [31:0] if_mem_rdata_i,

		// IF/ID 流水寄存器输出
		output wire [31:0] if_id_pc_o,
		output wire        if_id_pred_hit_o,
		output wire        if_id_pred_taken_o,
		output wire [31:0] if_id_pred_target_o,
		output wire [1:0]  if_id_pred_counter_o,
		output wire [31:0] if_id_pred_bht_index_o,
		output wire        if_id_valid_o,

		output wire [31:0] if_id_instr_o

	);

	// RV32I 标准 NOP 指令：addi x0, x0, 0
	// 当前 PC、下一拍 PC、以及 PC+4

	wire [31:0] pc_n;
	wire [31:0] pc_plus4;
	wire [31:0] if_id_instr;
	reg [31:0] pc_ff;
	reg        mem_req_valid_ff;
	reg [31:0] mem_req_pc_ff;
	localparam int FETCHQ_PTR_WIDTH = (FETCHQ_DEPTH > 1) ? $clog2(FETCHQ_DEPTH) : 1;
	localparam int FETCHQ_COUNT_WIDTH = $clog2(FETCHQ_DEPTH + 1);
	localparam int FETCHQ_RESERVED_WIDTH = $clog2(FETCHQ_DEPTH + 2);
	localparam logic [FETCHQ_COUNT_WIDTH-1:0] FETCHQ_DEPTH_COUNT = FETCHQ_COUNT_WIDTH'(FETCHQ_DEPTH);
	localparam logic [FETCHQ_RESERVED_WIDTH-1:0] FETCHQ_DEPTH_RESERVED =
		FETCHQ_RESERVED_WIDTH'(FETCHQ_DEPTH);
	reg [FETCHQ_COUNT_WIDTH-1:0] fetchq_count_ff;
	reg [31:0] fetchq_pc_ff [0:FETCHQ_DEPTH-1];
	reg [31:0] fetchq_instr_ff [0:FETCHQ_DEPTH-1];
	reg        fetchq_pred_hit_ff [0:FETCHQ_DEPTH-1];
	reg        fetchq_pred_taken_ff [0:FETCHQ_DEPTH-1];
	reg [31:0] fetchq_pred_target_ff [0:FETCHQ_DEPTH-1];
	reg [1:0]  fetchq_pred_counter_ff [0:FETCHQ_DEPTH-1];
	reg [31:0] fetchq_pred_bht_index_ff [0:FETCHQ_DEPTH-1];
	reg        pending_redirect_valid_ff;
	reg [31:0] pending_redirect_target_ff;

	wire       fetchq_empty;
	wire       fetchq_full;
	wire       fetchq_pop;
	wire       fetchq_push;
	wire       fetchq_push_allowed;
	wire [FETCHQ_RESERVED_WIDTH-1:0] fetchq_reserved_count;
	wire       fetchq_has_capacity;
	wire       can_issue_fetch;
	wire       fetch_issue;
	wire       mem_resp_valid;
	wire       predict_redirect_resp;
	wire       bp_predict_redirect;
	wire [31:0] fetch_addr;
	wire [31:0] fetch_next_pc;
	wire [31:0] flush_target;
	wire [31:0] invalidate_target;
	wire       flush_fetch;
	wire [FETCHQ_COUNT_WIDTH-1:0] fetchq_post_pop_count;
	wire [FETCHQ_PTR_WIDTH-1:0] fetchq_push_index;

	// 默认顺序取指地址：PC + 4
	assign pc_plus4   = pc_ff + 32'd4;
	assign fetchq_empty = (fetchq_count_ff == '0);
	assign fetchq_full  = (fetchq_count_ff == FETCHQ_DEPTH_COUNT);
	assign flush_fetch  = flush_if_i | branch_jump_i;
	assign flush_target = branch_jump_i ? branch_target_i : pc_plus4;
	assign invalidate_target = fetchq_empty ? pc_ff :
	                           (fetchq_pc_ff[0] + 32'd4);
	assign fetchq_pop   = !flush_fetch && !stall_if_i && !fetchq_empty;
	assign mem_resp_valid = !flush_fetch && mem_req_valid_ff;
	assign fetchq_push = mem_resp_valid;
	assign fetchq_push_allowed = fetchq_push && (!fetchq_full || fetchq_pop);
	assign fetchq_reserved_count =
		FETCHQ_RESERVED_WIDTH'(fetchq_count_ff) +
		FETCHQ_RESERVED_WIDTH'(mem_req_valid_ff);
	assign fetchq_has_capacity = (fetchq_reserved_count < FETCHQ_DEPTH_RESERVED);
	assign fetchq_post_pop_count = fetchq_count_ff -
		(fetchq_pop ? FETCHQ_COUNT_WIDTH'(1) : '0);
	assign fetchq_push_index = fetchq_post_pop_count[FETCHQ_PTR_WIDTH-1:0];
	assign can_issue_fetch = !flush_fetch && fetchq_has_capacity;
	assign predict_redirect_resp = mem_resp_valid && bp_predict_taken_i;
	assign fetch_issue = can_issue_fetch && !predict_redirect_resp;
	assign bp_predict_redirect = predict_redirect_resp;
	// 若发生重定向则跳转到目标 PC，否则顺序执行
	assign pc_n       = branch_jump_i ? branch_target_i :
						!fetch_issue ? pc_ff :
						fetch_next_pc;

	assign fetch_addr = pending_redirect_valid_ff ? pending_redirect_target_ff :
	                    pc_ff;
	assign fetch_next_pc = fetch_addr + 32'd4;
	assign if_mem_addr_o = fetch_addr;
	assign bp_lookup_pc_o = fetch_addr;

	assign if_id_pc_o    = fetchq_empty ? ydrasil_pkg::RESET_INS : fetchq_pc_ff[0];
	assign if_id_pred_hit_o = !fetchq_empty && fetchq_pred_hit_ff[0];
	assign if_id_pred_taken_o = !fetchq_empty && fetchq_pred_taken_ff[0];
	assign if_id_pred_target_o = fetchq_empty ? 32'b0 : fetchq_pred_target_ff[0];
	assign if_id_pred_counter_o = fetchq_empty ? 2'b01 : fetchq_pred_counter_ff[0];
	assign if_id_pred_bht_index_o = fetchq_empty ? 32'b0 : fetchq_pred_bht_index_ff[0];
	assign if_id_valid_o = !fetchq_empty;
	assign if_id_instr_o = fetchq_empty ? ydrasil_pkg::RV32I_INS_NOP : fetchq_instr_ff[0];
	assign if_id_instr = if_id_instr_o;

	// IF 级 PC 寄存器：复位置初值，非停顿时更新
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			pc_ff <= ydrasil_pkg::RESET_INS;
		end else begin
			pc_ff <= flush_fetch ? flush_target :
			         bp_invalidate_i ? invalidate_target :
			         pc_n;
		end
	end




	// The fixed head removes the read-pointer mux from the IF output path.
	integer fetchq_shift_idx;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			mem_req_valid_ff <= 1'b0;
			mem_req_pc_ff <= ydrasil_pkg::RESET_INS;
			fetchq_count_ff <= '0;
			pending_redirect_valid_ff <= 1'b0;
			pending_redirect_target_ff <= '0;
		end 
		else if (flush_fetch) begin
			mem_req_valid_ff <= 1'b0;
			mem_req_pc_ff <= flush_target;
			fetchq_count_ff <= '0;
			pending_redirect_valid_ff <= 1'b0;
			pending_redirect_target_ff <= '0;
		end else if (bp_invalidate_i) begin
			mem_req_valid_ff <= 1'b0;
			mem_req_pc_ff <= invalidate_target;
			fetchq_count_ff <= '0;
			pending_redirect_valid_ff <= 1'b0;
			pending_redirect_target_ff <= '0;
		end else begin
			mem_req_valid_ff <= fetch_issue;
			// Payload is don't-care when valid is low.  Updating it every cycle
			// keeps prediction response logic off the register clock-enable path.
			mem_req_pc_ff <= fetch_addr;
			if (pending_redirect_valid_ff && fetch_issue) begin
				pending_redirect_valid_ff <= 1'b0;
			end
			if (predict_redirect_resp) begin
				pending_redirect_valid_ff <= 1'b1;
				pending_redirect_target_ff <= bp_predict_target_i;
			end

			if (fetchq_pop) begin
				for (fetchq_shift_idx = 0; fetchq_shift_idx < FETCHQ_DEPTH-1;
				     fetchq_shift_idx = fetchq_shift_idx + 1) begin
					fetchq_pc_ff[fetchq_shift_idx] <= fetchq_pc_ff[fetchq_shift_idx+1];
					fetchq_instr_ff[fetchq_shift_idx] <= fetchq_instr_ff[fetchq_shift_idx+1];
					fetchq_pred_hit_ff[fetchq_shift_idx] <= fetchq_pred_hit_ff[fetchq_shift_idx+1];
					fetchq_pred_taken_ff[fetchq_shift_idx] <= fetchq_pred_taken_ff[fetchq_shift_idx+1];
					fetchq_pred_target_ff[fetchq_shift_idx] <= fetchq_pred_target_ff[fetchq_shift_idx+1];
					fetchq_pred_counter_ff[fetchq_shift_idx] <= fetchq_pred_counter_ff[fetchq_shift_idx+1];
					fetchq_pred_bht_index_ff[fetchq_shift_idx] <= fetchq_pred_bht_index_ff[fetchq_shift_idx+1];
				end
			end

			if (fetchq_push_allowed) begin
				fetchq_pc_ff[fetchq_push_index] <= mem_req_pc_ff;
				fetchq_instr_ff[fetchq_push_index] <= if_mem_rdata_i;
				fetchq_pred_hit_ff[fetchq_push_index] <= bp_predict_hit_i;
				fetchq_pred_taken_ff[fetchq_push_index] <= bp_predict_taken_i;
				fetchq_pred_target_ff[fetchq_push_index] <= bp_predict_target_i;
				fetchq_pred_counter_ff[fetchq_push_index] <= bp_predict_counter_i;
				fetchq_pred_bht_index_ff[fetchq_push_index] <= bp_predict_bht_index_i;
			end

			case ({fetchq_push_allowed, fetchq_pop})
				2'b10: fetchq_count_ff <= fetchq_count_ff + 1'b1;
				2'b01: fetchq_count_ff <= fetchq_count_ff - 1'b1;
				default: fetchq_count_ff <= fetchq_count_ff;
			endcase
		end
	end

endmodule
