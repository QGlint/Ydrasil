module ydrasil_if_stage
import ydrasil_pkg::*;
import ydrasil_pipeline_pkg::*;
#(
)(
	input  wire        clk,
	input  wire        rst_n,

	// 流水线控制信号
	input  wire        stall_if_i,
	input  wire        stall_pc_i,
	input  wire        flush_if_i,
	input  wire        consume_two_i,

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
	input  wire        l0_train_valid_i,
	input  wire [31:0] l0_train_pc_i,
	input  wire        l0_train_taken_i,
	input  wire [31:0] l0_train_target_i,

	// 指令存储器接口
	output wire [31:0] if_mem_addr_o,
	output wire [31:0] if_mem_addr1_o,
	input  wire [31:0] if_mem_rdata_i,
	input  wire [31:0] if_mem_rdata1_i,

	// IF/ID 流水寄存器输出
	output wire [31:0] if_id_pc_o,
	output wire        if_id_pred_hit_o,
	output wire        if_id_pred_taken_o,
	output wire [31:0] if_id_pred_target_o,
	output wire [1:0]  if_id_pred_counter_o,
	output wire [31:0] if_id_pred_bht_index_o,
	output wire        if_id_pred_l0_taken_o,
	output wire        if_id_valid_o,
	output wire [31:0] if_id1_pc_o,
	output wire        if_id1_pred_hit_o,
	output wire        if_id1_pred_taken_o,
	output wire [31:0] if_id1_pred_target_o,
	output wire [1:0]  if_id1_pred_counter_o,
	output wire [31:0] if_id1_pred_bht_index_o,
	output wire        if_id1_pred_l0_taken_o,
	output wire        if_id1_valid_o,
	output fetch_pair_pkt_t if_id_fetch_pair_o,
	output pair_ctrl_t if_id_pair_ctrl_o,
	output wire        dbg_sync_bp_redirect_o,

	output wire [31:0] if_id_instr_o,
	output wire [31:0] if_id1_instr_o
);

	localparam int FETCH_Q_DEPTH = 4;
	localparam int FETCH_Q_COUNT_WIDTH = $clog2(FETCH_Q_DEPTH + 1);
	localparam logic [FETCH_Q_COUNT_WIDTH:0] FETCH_Q_DEPTH_COUNT = FETCH_Q_DEPTH;
	localparam logic [FETCH_Q_COUNT_WIDTH:0] FETCH_Q_PAIR_ROOM_MAX = FETCH_Q_DEPTH - 2;
	localparam int L0_ENTRIES = 32;
	localparam int L0_INDEX_WIDTH = $clog2(L0_ENTRIES);
	localparam int L0_TAG_WIDTH = 32 - L0_INDEX_WIDTH - 2;

	reg [31:0] pc_ff;
	reg        mem_resp_valid_ff;
	reg        mem_resp_valid1_ff;
	reg [31:0] mem_resp_pc_ff;
	reg [31:0] mem_resp_pc1_ff;
	reg        mem_resp_l0_taken_ff;
	reg        mem_resp1_l0_taken_ff;
	reg [31:0] mem_resp_l0_target_ff;
	reg [31:0] mem_resp1_l0_target_ff;
	predict_pkt_t mem_resp_pred0_ff;
	predict_pkt_t mem_resp_pred1_ff;
	pair_ctrl_t   mem_resp_pair_ctrl_ff;

	reg        fetch_valid_ff [0:FETCH_Q_DEPTH-1];
	reg [31:0] fetch_pc_ff [0:FETCH_Q_DEPTH-1];
	reg [31:0] fetch_instr_ff [0:FETCH_Q_DEPTH-1];
	reg        fetch_pred_l0_taken_ff [0:FETCH_Q_DEPTH-1];
	reg        fetch_pred_hit_ff [0:FETCH_Q_DEPTH-1];
	reg        fetch_pred_taken_ff [0:FETCH_Q_DEPTH-1];
	reg [31:0] fetch_pred_target_ff [0:FETCH_Q_DEPTH-1];
	reg [1:0]  fetch_pred_counter_ff [0:FETCH_Q_DEPTH-1];
	reg [31:0] fetch_pred_bht_index_ff [0:FETCH_Q_DEPTH-1];
	pair_ctrl_t fetch_pair_ctrl_ff [0:FETCH_Q_DEPTH-1];
	reg [FETCH_Q_COUNT_WIDTH-1:0] fetch_count_ff;

	reg        l0_valid_ff [0:L0_ENTRIES-1];
	reg [L0_TAG_WIDTH-1:0] l0_tag_ff [0:L0_ENTRIES-1];
	reg [31:0] l0_target_ff [0:L0_ENTRIES-1];
	reg [1:0]  l0_counter_ff [0:L0_ENTRIES-1];

	reg [31:0] perf_fetch_q_full;
	reg [31:0] perf_fetch_q_empty;
	reg [31:0] perf_fetch_q_push;
	reg [31:0] perf_fetch_q_pop;
	reg [31:0] perf_decode_blocked_by_uopq;
	reg [31:0] perf_sync_bp_taken_bubble;
	reg [31:0] perf_l0_hit;
	reg [31:0] perf_l0_taken;
	reg [31:0] perf_fq_occ_0;
	reg [31:0] perf_fq_occ_1;
	reg [31:0] perf_fq_occ_2;
	reg [31:0] perf_fq_occ_3;
	reg [31:0] perf_fq_occ_4;
	reg [31:0] perf_fq_flush_drop;
	reg [31:0] perf_fq_full_block_req;
	reg [31:0] perf_fq_backend_stall_pop;
	reg [31:0] perf_fq_empty_id_bubble;
	reg [31:0] perf_fq_sync_redirect_flush;
	reg [31:0] perf_fq_ex_redirect_flush;
	reg [31:0] perf_l0_lookup;
	reg [31:0] perf_l0_correct_taken;
	reg [31:0] perf_l0_wrong_taken;
	reg [31:0] perf_l0_train_taken;
	reg [31:0] perf_l0_train_not_taken;
	reg [31:0] perf_l0_counter_inc;
	reg [31:0] perf_l0_counter_dec;
	reg [31:0] perf_fetch2_req;
	reg [31:0] perf_fetch2_valid2;
	reg [31:0] perf_fetch2_valid1_only;
	reg [31:0] perf_fetch2_align_block;
	reg [31:0] perf_fetch2_redirect_kill_slot1;
	reg [31:0] perf_fetch2_irom_stall;
	reg [31:0] perf_pair_ctrl_try;
	reg [31:0] perf_pair_ctrl_allow;
	reg [31:0] perf_pair_block_predictor;
	reg [31:0] perf_pair_block_queue;
	reg [31:0] perf_pair_block_rule;
	reg [31:0] perf_pair_block_rename;
	reg [31:0] perf_pair_block_issue;
	reg [31:0] perf_pair_slot1_kill;

	wire [31:0] pc_plus4;
	wire [31:0] pc_plus8;
	wire        fetch_q_valid;
	wire        fetch_q_slot1_valid;
	wire        fetch_q_full;
	wire        pop_fire;
	wire        pop_two_fire;
	wire        enqueue_fire;
	wire        enqueue1_fire;
	wire        enqueue1_killed;
	wire        request_fire;
	wire        request_two_fire;
	wire        bp_predict_redirect;
	predict_pkt_t request_pred0;
	predict_pkt_t request_pred1;
	predict_pkt_t enqueue_pred0;
	predict_pkt_t enqueue_pred1;
	pair_ctrl_t request_pair_ctrl;
	pair_ctrl_t mem_resp_pair_ctrl;
	pair_ctrl_t if_id_pair_ctrl;
	wire [FETCH_Q_COUNT_WIDTH:0] reserved_count;
	wire [FETCH_Q_COUNT_WIDTH:0] enqueue_count;
	wire [FETCH_Q_COUNT_WIDTH:0] pop_count;
	wire        pair_room_for_two;
	wire        pair_predictor_suppress;
	wire        pair_itcm_suppress;
	wire        pair_queue_suppress;
	wire        flush_queue;
	wire [31:0] pc_n;
	wire [L0_INDEX_WIDTH-1:0] l0_predict_index;
	wire [L0_TAG_WIDTH-1:0]   l0_predict_tag;
	wire                      l0_predict_hit;
	wire                      l0_predict_taken;
	wire [31:0]               l0_predict_target;
	wire [L0_INDEX_WIDTH-1:0] l0_predict1_index;
	wire [L0_TAG_WIDTH-1:0]   l0_predict1_tag;
	wire                      l0_predict1_hit;
	wire                      l0_predict1_taken;
	wire [31:0]               l0_predict1_target;
	wire [L0_INDEX_WIDTH-1:0] l0_train_index;
	wire [L0_TAG_WIDTH-1:0]   l0_train_tag;
	wire                      l0_train_hit;
	wire                      l0_train_fire;
	wire                      fq_full_block_req;
	wire                      fq_empty_id_bubble;
	wire                      l0_train_pred_taken;
	wire                      l0_counter_inc;
	wire                      l0_counter_dec;
	wire                      request_two_itcm_ok;
	wire                      request_two_dtcm_block;

	assign pc_plus4 = pc_ff + 32'd4;
	assign pc_plus8 = pc_ff + 32'd8;
	assign fetch_q_valid = fetch_count_ff != '0;
	assign fetch_q_slot1_valid = fetch_count_ff > FETCH_Q_COUNT_WIDTH'(1);
	assign fetch_q_full = fetch_count_ff == FETCH_Q_DEPTH[FETCH_Q_COUNT_WIDTH-1:0];

	assign if_id_valid_o = fetch_q_valid;
	assign if_id_pc_o = fetch_q_valid ? fetch_pc_ff[0] : ydrasil_pkg::RESET_INS;
	assign if_id_instr_o = fetch_q_valid ? fetch_instr_ff[0] : ydrasil_pkg::RV32I_INS_NOP;
	assign if_id_pred_hit_o =
		fetch_q_valid && !bp_invalidate_i && fetch_pred_hit_ff[0];
	assign if_id_pred_taken_o =
		fetch_q_valid && !bp_invalidate_i && fetch_pred_taken_ff[0];
	assign if_id_pred_target_o = fetch_pred_target_ff[0];
	assign if_id_pred_counter_o =
		(fetch_q_valid && !bp_invalidate_i) ? fetch_pred_counter_ff[0] : 2'b01;
	assign if_id_pred_bht_index_o = fetch_pred_bht_index_ff[0];
	assign if_id_pred_l0_taken_o =
		fetch_q_valid && !bp_invalidate_i && fetch_pred_l0_taken_ff[0];

	assign if_id1_valid_o = fetch_q_slot1_valid;
	assign if_id1_pc_o = fetch_q_slot1_valid ? fetch_pc_ff[1] : (ydrasil_pkg::RESET_INS + 32'd4);
	assign if_id1_instr_o = fetch_q_slot1_valid ? fetch_instr_ff[1] : ydrasil_pkg::RV32I_INS_NOP;
	assign if_id1_pred_hit_o =
		fetch_q_slot1_valid && !bp_invalidate_i && fetch_pred_hit_ff[1];
	assign if_id1_pred_taken_o =
		fetch_q_slot1_valid && !bp_invalidate_i && fetch_pred_taken_ff[1];
	assign if_id1_pred_target_o = fetch_pred_target_ff[1];
	assign if_id1_pred_counter_o =
		(fetch_q_slot1_valid && !bp_invalidate_i) ? fetch_pred_counter_ff[1] : 2'b01;
	assign if_id1_pred_bht_index_o = fetch_pred_bht_index_ff[1];
	assign if_id1_pred_l0_taken_o =
		fetch_q_slot1_valid && !bp_invalidate_i && fetch_pred_l0_taken_ff[1];
	assign if_id_pair_ctrl = fetch_q_valid ? fetch_pair_ctrl_ff[0] : '0;
	assign if_id_pair_ctrl_o.request_valid = if_id_pair_ctrl.request_valid & fetch_q_valid;
	assign if_id_pair_ctrl_o.fetch_pair_try = if_id_pair_ctrl.fetch_pair_try;
	assign if_id_pair_ctrl_o.fetch_pair_allow = if_id_pair_ctrl.fetch_pair_allow;
	assign if_id_pair_ctrl_o.decode_pair_allow = if_id_pair_ctrl.decode_pair_allow;
	assign if_id_pair_ctrl_o.slot1_valid =
		if_id_pair_ctrl.slot1_valid & fetch_q_slot1_valid & !bp_invalidate_i;
	assign if_id_pair_ctrl_o.slot1_kill = if_id_pair_ctrl.slot1_kill;
	assign if_id_pair_ctrl_o.block_reason = if_id_pair_ctrl.block_reason;
	assign if_id_fetch_pair_o.slot0.valid = if_id_valid_o;
	assign if_id_fetch_pair_o.slot0.pc = if_id_pc_o;
	assign if_id_fetch_pair_o.slot0.instr = if_id_instr_o;
	assign if_id_fetch_pair_o.slot0.pred.valid = if_id_valid_o;
	assign if_id_fetch_pair_o.slot0.pred.hit = if_id_pred_hit_o;
	assign if_id_fetch_pair_o.slot0.pred.taken = if_id_pred_taken_o;
	assign if_id_fetch_pair_o.slot0.pred.target = if_id_pred_target_o;
	assign if_id_fetch_pair_o.slot0.pred.counter = if_id_pred_counter_o;
	assign if_id_fetch_pair_o.slot0.pred.bht_index = if_id_pred_bht_index_o;
	assign if_id_fetch_pair_o.slot0.pred.l0_taken = if_id_pred_l0_taken_o;
	assign if_id_fetch_pair_o.slot0.pred.redirect_consumed = if_id_pred_l0_taken_o;
	assign if_id_fetch_pair_o.slot1.valid = if_id1_valid_o;
	assign if_id_fetch_pair_o.slot1.pc = if_id1_pc_o;
	assign if_id_fetch_pair_o.slot1.instr = if_id1_instr_o;
	assign if_id_fetch_pair_o.slot1.pred.valid = if_id1_valid_o;
	assign if_id_fetch_pair_o.slot1.pred.hit = if_id1_pred_hit_o;
	assign if_id_fetch_pair_o.slot1.pred.taken = if_id1_pred_taken_o;
	assign if_id_fetch_pair_o.slot1.pred.target = if_id1_pred_target_o;
	assign if_id_fetch_pair_o.slot1.pred.counter = if_id1_pred_counter_o;
	assign if_id_fetch_pair_o.slot1.pred.bht_index = if_id1_pred_bht_index_o;
	assign if_id_fetch_pair_o.slot1.pred.l0_taken = if_id1_pred_l0_taken_o;
	assign if_id_fetch_pair_o.slot1.pred.redirect_consumed = if_id1_pred_l0_taken_o;
	assign if_id_fetch_pair_o.pair_ctrl = if_id_pair_ctrl_o;

	assign l0_predict_index = pc_ff[L0_INDEX_WIDTH+1:2];
	assign l0_predict_tag = pc_ff[31:L0_INDEX_WIDTH+2];
	assign l0_predict_hit =
		l0_valid_ff[l0_predict_index] &&
		(l0_tag_ff[l0_predict_index] == l0_predict_tag);
	assign l0_predict_taken = l0_predict_hit && l0_counter_ff[l0_predict_index][1];
	assign l0_predict_target = l0_target_ff[l0_predict_index];
	assign l0_predict1_index = pc_plus4[L0_INDEX_WIDTH+1:2];
	assign l0_predict1_tag = pc_plus4[31:L0_INDEX_WIDTH+2];
	assign l0_predict1_hit =
		l0_valid_ff[l0_predict1_index] &&
		(l0_tag_ff[l0_predict1_index] == l0_predict1_tag);
	assign l0_predict1_taken =
		l0_predict1_hit && l0_counter_ff[l0_predict1_index][1];
	assign l0_predict1_target = l0_target_ff[l0_predict1_index];

	assign request_pred0.valid = request_fire;
	assign request_pred0.hit = l0_predict_taken;
	assign request_pred0.taken = l0_predict_taken;
	assign request_pred0.target = l0_predict_target;
	assign request_pred0.counter = 2'b01;
	assign request_pred0.bht_index = '0;
	assign request_pred0.l0_taken = l0_predict_taken;
	assign request_pred0.redirect_consumed = l0_predict_taken;

	assign request_pred1.valid = request_two_fire;
	assign request_pred1.hit = l0_predict1_taken;
	assign request_pred1.taken = l0_predict1_taken;
	assign request_pred1.target = l0_predict1_target;
	assign request_pred1.counter = 2'b01;
	assign request_pred1.bht_index = '0;
	assign request_pred1.l0_taken = l0_predict1_taken;
	assign request_pred1.redirect_consumed = 1'b0;

	assign enqueue_pred0 = mem_resp_pred0_ff;

	assign enqueue_pred1 = mem_resp_pred1_ff;

	assign l0_train_index = l0_train_pc_i[L0_INDEX_WIDTH+1:2];
	assign l0_train_tag = l0_train_pc_i[31:L0_INDEX_WIDTH+2];
	assign l0_train_hit =
		l0_valid_ff[l0_train_index] &&
		(l0_tag_ff[l0_train_index] == l0_train_tag);
	assign l0_train_fire = l0_train_valid_i && !bp_invalidate_i;
	assign l0_train_pred_taken =
		l0_train_hit && l0_counter_ff[l0_train_index][1];
	assign l0_counter_inc =
		l0_train_fire && l0_train_taken_i &&
		(!l0_train_hit || (l0_counter_ff[l0_train_index] != 2'b11));
	assign l0_counter_dec =
		l0_train_fire && !l0_train_taken_i && l0_train_hit &&
		(l0_counter_ff[l0_train_index] != 2'b00);
	assign request_two_dtcm_block =
		((pc_ff >= ydrasil_pkg::DTCM_BASE_ADDR) &&
		 (pc_ff < (ydrasil_pkg::DTCM_BASE_ADDR +
		           ((32'd1 << ydrasil_pkg::DTCM_ADDR_WIDTH) << 2)))) ||
		((pc_plus4 >= ydrasil_pkg::DTCM_BASE_ADDR) &&
		 (pc_plus4 < (ydrasil_pkg::DTCM_BASE_ADDR +
		              ((32'd1 << ydrasil_pkg::DTCM_ADDR_WIDTH) << 2))));
	assign request_two_itcm_ok = !request_two_dtcm_block;

	assign bp_predict_redirect =
		!branch_jump_i && !flush_if_i && !stall_if_i && !stall_pc_i &&
		!bp_invalidate_i && if_id_valid_o && if_id_pred_taken_o &&
		!fetch_pred_l0_taken_ff[0];

	assign pop_fire = !flush_if_i && !bp_predict_redirect &&
		!stall_if_i && fetch_q_valid;
	assign pop_two_fire = pop_fire && consume_two_i && fetch_q_slot1_valid;
	assign pop_count =
		pop_two_fire ? {{(FETCH_Q_COUNT_WIDTH-1){1'b0}}, 2'd2} :
		pop_fire     ? {{FETCH_Q_COUNT_WIDTH{1'b0}}, 1'b1} :
		               '0;
	assign enqueue_fire = !flush_if_i && !bp_predict_redirect &&
		mem_resp_valid_ff;
	assign enqueue1_fire = !flush_if_i && !bp_predict_redirect &&
		mem_resp_valid1_ff && mem_resp_pair_ctrl.slot1_valid;
	assign enqueue1_killed = mem_resp_valid1_ff && flush_queue;
	assign enqueue_count =
		{{FETCH_Q_COUNT_WIDTH{1'b0}}, enqueue_fire} +
		{{FETCH_Q_COUNT_WIDTH{1'b0}}, enqueue1_fire};

	assign reserved_count =
		{1'b0, fetch_count_ff} +
		{{FETCH_Q_COUNT_WIDTH{1'b0}}, mem_resp_valid_ff} +
		{{FETCH_Q_COUNT_WIDTH{1'b0}}, mem_resp_valid1_ff} -
		pop_count;
	assign request_fire =
		!branch_jump_i && !flush_if_i && !bp_predict_redirect &&
		!stall_pc_i && !bp_invalidate_i &&
		(reserved_count < FETCH_Q_DEPTH_COUNT);
	assign pair_room_for_two = reserved_count <= FETCH_Q_PAIR_ROOM_MAX;
	assign pair_predictor_suppress =
		request_fire && pair_room_for_two && request_two_itcm_ok &&
		(request_pred0.redirect_consumed | request_pred1.redirect_consumed);
	assign pair_itcm_suppress =
		request_fire && pair_room_for_two && !request_two_itcm_ok;
	assign pair_queue_suppress =
		request_fire && !pair_room_for_two;
	assign request_two_fire =
		request_fire && request_two_itcm_ok && pair_room_for_two &&
		!request_pred0.redirect_consumed && !request_pred1.redirect_consumed;
	assign request_pair_ctrl.request_valid = request_fire;
	assign request_pair_ctrl.fetch_pair_try = request_fire;
	assign request_pair_ctrl.fetch_pair_allow = request_two_fire;
	assign request_pair_ctrl.decode_pair_allow = 1'b0;
	assign request_pair_ctrl.slot1_valid = request_two_fire;
	assign request_pair_ctrl.slot1_kill = 1'b0;
	assign request_pair_ctrl.block_reason =
		request_two_fire ? PAIR_BLOCK_NONE :
		pair_predictor_suppress ? PAIR_BLOCK_PREDICTOR :
		pair_queue_suppress ? PAIR_BLOCK_QUEUE :
		pair_itcm_suppress ? PAIR_BLOCK_ITCM :
		(!request_fire && (branch_jump_i | flush_if_i | bp_predict_redirect)) ? PAIR_BLOCK_REDIRECT :
		(!request_fire && (stall_pc_i | bp_invalidate_i)) ? PAIR_BLOCK_STALL :
		PAIR_BLOCK_NONE;
	assign mem_resp_pair_ctrl = '{
		request_valid: mem_resp_pair_ctrl_ff.request_valid,
		fetch_pair_try: mem_resp_pair_ctrl_ff.fetch_pair_try,
		fetch_pair_allow: mem_resp_pair_ctrl_ff.fetch_pair_allow,
		decode_pair_allow: mem_resp_pair_ctrl_ff.decode_pair_allow,
		slot1_valid: mem_resp_pair_ctrl_ff.slot1_valid,
		slot1_kill: 1'b0,
		block_reason: mem_resp_pair_ctrl_ff.block_reason
	};
	assign flush_queue = flush_if_i | branch_jump_i | bp_predict_redirect;
	assign fq_full_block_req =
		!branch_jump_i && !flush_if_i && !bp_predict_redirect &&
		!stall_pc_i && !bp_invalidate_i &&
		(reserved_count >= FETCH_Q_DEPTH_COUNT);
	assign fq_empty_id_bubble = !stall_if_i && !fetch_q_valid;
	assign dbg_sync_bp_redirect_o = bp_predict_redirect;

	assign pc_n =
		branch_jump_i       ? branch_target_i :
		bp_predict_redirect ? if_id_pred_target_o :
		request_fire        ? (request_pred0.redirect_consumed ? request_pred0.target :
		                       request_two_fire ? pc_plus8 : pc_plus4) :
		                      pc_ff;

	assign if_mem_addr_o = pc_ff;
	assign if_mem_addr1_o = pc_plus4;

	integer i;
	integer append_idx;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			pc_ff <= ydrasil_pkg::RESET_INS;
			mem_resp_valid_ff <= 1'b0;
			mem_resp_valid1_ff <= 1'b0;
			mem_resp_pc_ff <= ydrasil_pkg::RESET_INS;
			mem_resp_pc1_ff <= ydrasil_pkg::RESET_INS + 32'd4;
			mem_resp_l0_taken_ff <= 1'b0;
			mem_resp1_l0_taken_ff <= 1'b0;
			mem_resp_l0_target_ff <= '0;
			mem_resp1_l0_target_ff <= '0;
			mem_resp_pred0_ff <= '0;
			mem_resp_pred1_ff <= '0;
			mem_resp_pair_ctrl_ff <= '0;
			fetch_count_ff <= '0;
			perf_fetch_q_full <= '0;
			perf_fetch_q_empty <= '0;
			perf_fetch_q_push <= '0;
			perf_fetch_q_pop <= '0;
			perf_decode_blocked_by_uopq <= '0;
			perf_sync_bp_taken_bubble <= '0;
			perf_l0_hit <= '0;
			perf_l0_taken <= '0;
			perf_fq_occ_0 <= '0;
			perf_fq_occ_1 <= '0;
			perf_fq_occ_2 <= '0;
			perf_fq_occ_3 <= '0;
			perf_fq_occ_4 <= '0;
			perf_fq_flush_drop <= '0;
			perf_fq_full_block_req <= '0;
			perf_fq_backend_stall_pop <= '0;
			perf_fq_empty_id_bubble <= '0;
			perf_fq_sync_redirect_flush <= '0;
			perf_fq_ex_redirect_flush <= '0;
			perf_l0_lookup <= '0;
			perf_l0_correct_taken <= '0;
			perf_l0_wrong_taken <= '0;
			perf_l0_train_taken <= '0;
			perf_l0_train_not_taken <= '0;
			perf_l0_counter_inc <= '0;
			perf_l0_counter_dec <= '0;
			perf_fetch2_req <= '0;
			perf_fetch2_valid2 <= '0;
			perf_fetch2_valid1_only <= '0;
			perf_fetch2_align_block <= '0;
			perf_fetch2_redirect_kill_slot1 <= '0;
			perf_fetch2_irom_stall <= '0;
			perf_pair_ctrl_try <= '0;
			perf_pair_ctrl_allow <= '0;
			perf_pair_block_predictor <= '0;
			perf_pair_block_queue <= '0;
			perf_pair_block_rule <= '0;
			perf_pair_block_rename <= '0;
			perf_pair_block_issue <= '0;
			perf_pair_slot1_kill <= '0;
			for (i = 0; i < FETCH_Q_DEPTH; i = i + 1) begin
				fetch_valid_ff[i] <= 1'b0;
				fetch_pc_ff[i] <= ydrasil_pkg::RESET_INS;
				fetch_instr_ff[i] <= ydrasil_pkg::RV32I_INS_NOP;
				fetch_pred_l0_taken_ff[i] <= 1'b0;
				fetch_pred_hit_ff[i] <= 1'b0;
				fetch_pred_taken_ff[i] <= 1'b0;
				fetch_pred_target_ff[i] <= '0;
				fetch_pred_counter_ff[i] <= 2'b01;
				fetch_pred_bht_index_ff[i] <= '0;
				fetch_pair_ctrl_ff[i] <= '0;
			end
			for (i = 0; i < L0_ENTRIES; i = i + 1) begin
				l0_valid_ff[i] <= 1'b0;
				l0_tag_ff[i] <= '0;
				l0_target_ff[i] <= '0;
				l0_counter_ff[i] <= 2'b01;
			end
		end else begin
			pc_ff <= pc_n;

			if (flush_queue) begin
				mem_resp_valid_ff <= 1'b0;
				mem_resp_valid1_ff <= 1'b0;
				mem_resp_l0_taken_ff <= 1'b0;
				mem_resp1_l0_taken_ff <= 1'b0;
			end else begin
				mem_resp_valid_ff <= request_fire;
				mem_resp_valid1_ff <= request_two_fire;
				if (request_fire) begin
					mem_resp_pc_ff <= pc_ff;
					mem_resp_pc1_ff <= pc_plus4;
					mem_resp_l0_taken_ff <= request_pred0.redirect_consumed;
					mem_resp_l0_target_ff <= request_pred0.target;
					mem_resp1_l0_taken_ff <= request_pred1.l0_taken;
					mem_resp1_l0_target_ff <= request_pred1.target;
					mem_resp_pred0_ff <= request_pred0;
					mem_resp_pred1_ff <= request_pred1;
					mem_resp_pair_ctrl_ff <= request_pair_ctrl;
				end
			end

			if (flush_queue) begin
				fetch_count_ff <= '0;
				for (i = 0; i < FETCH_Q_DEPTH; i = i + 1) begin
					fetch_valid_ff[i] <= 1'b0;
					fetch_pair_ctrl_ff[i] <= '0;
				end
			end else begin
				append_idx = fetch_count_ff - pop_count;
				if (pop_fire) begin
				for (i = 0; i < FETCH_Q_DEPTH; i = i + 1) begin
					if ((i + pop_count) < fetch_count_ff) begin
						fetch_valid_ff[i] <= fetch_valid_ff[i+pop_count];
						fetch_pc_ff[i] <= fetch_pc_ff[i+pop_count];
						fetch_instr_ff[i] <= fetch_instr_ff[i+pop_count];
						fetch_pred_l0_taken_ff[i] <= fetch_pred_l0_taken_ff[i+pop_count];
						fetch_pred_hit_ff[i] <= fetch_pred_hit_ff[i+pop_count];
						fetch_pred_taken_ff[i] <= fetch_pred_taken_ff[i+pop_count];
						fetch_pred_target_ff[i] <= fetch_pred_target_ff[i+pop_count];
						fetch_pred_counter_ff[i] <= fetch_pred_counter_ff[i+pop_count];
						fetch_pred_bht_index_ff[i] <= fetch_pred_bht_index_ff[i+pop_count];
						fetch_pair_ctrl_ff[i] <= fetch_pair_ctrl_ff[i+pop_count];
					end else begin
						fetch_valid_ff[i] <= 1'b0;
						fetch_pair_ctrl_ff[i] <= '0;
					end
				end
				end
				if (enqueue_fire && (append_idx < FETCH_Q_DEPTH)) begin
					fetch_valid_ff[append_idx] <= 1'b1;
					fetch_pc_ff[append_idx] <= mem_resp_pc_ff;
					fetch_instr_ff[append_idx] <= if_mem_rdata_i;
					fetch_pred_l0_taken_ff[append_idx] <= enqueue_pred0.redirect_consumed;
					fetch_pred_hit_ff[append_idx] <= enqueue_pred0.hit;
					fetch_pred_taken_ff[append_idx] <= enqueue_pred0.taken;
					fetch_pred_target_ff[append_idx] <= enqueue_pred0.target;
					fetch_pred_counter_ff[append_idx] <= enqueue_pred0.counter;
					fetch_pred_bht_index_ff[append_idx] <= enqueue_pred0.bht_index;
					fetch_pair_ctrl_ff[append_idx] <= mem_resp_pair_ctrl;
					append_idx = append_idx + 1;
				end
				if (enqueue1_fire && (append_idx < FETCH_Q_DEPTH)) begin
					fetch_valid_ff[append_idx] <= 1'b1;
					fetch_pc_ff[append_idx] <= mem_resp_pc1_ff;
					fetch_instr_ff[append_idx] <= if_mem_rdata1_i;
					fetch_pred_l0_taken_ff[append_idx] <= enqueue_pred1.redirect_consumed;
					fetch_pred_hit_ff[append_idx] <= enqueue_pred1.hit;
					fetch_pred_taken_ff[append_idx] <= enqueue_pred1.taken;
					fetch_pred_target_ff[append_idx] <= enqueue_pred1.target;
					fetch_pred_counter_ff[append_idx] <= enqueue_pred1.counter;
					fetch_pred_bht_index_ff[append_idx] <= enqueue_pred1.bht_index;
					fetch_pair_ctrl_ff[append_idx] <= '0;
				end
				fetch_count_ff <= fetch_count_ff -
					pop_count[FETCH_Q_COUNT_WIDTH-1:0] +
					enqueue_count[FETCH_Q_COUNT_WIDTH-1:0];
			end

			if (bp_invalidate_i) begin
				for (i = 0; i < L0_ENTRIES; i = i + 1) begin
					l0_valid_ff[i] <= 1'b0;
					l0_counter_ff[i] <= 2'b01;
				end
			end else if (l0_train_fire) begin
				if (l0_train_taken_i) begin
					l0_valid_ff[l0_train_index] <= 1'b1;
					l0_tag_ff[l0_train_index] <= l0_train_tag;
					l0_target_ff[l0_train_index] <= l0_train_target_i;
					l0_counter_ff[l0_train_index] <=
						l0_train_hit ?
						((l0_counter_ff[l0_train_index] == 2'b11) ?
						 l0_counter_ff[l0_train_index] :
						 (l0_counter_ff[l0_train_index] + 2'b01)) :
						2'b10;
				end else if (l0_train_hit) begin
					l0_counter_ff[l0_train_index] <=
						(l0_counter_ff[l0_train_index] == 2'b00) ?
						l0_counter_ff[l0_train_index] :
						(l0_counter_ff[l0_train_index] - 2'b01);
				end
			end

			perf_fetch_q_full <= perf_fetch_q_full +
				(fetch_q_full ? 32'd1 : 32'd0);
			perf_fetch_q_empty <= perf_fetch_q_empty +
				((!stall_if_i && !fetch_q_valid) ? 32'd1 : 32'd0);
			perf_fetch_q_push <= perf_fetch_q_push +
				{31'd0, enqueue_fire} + {31'd0, enqueue1_fire};
			perf_fetch_q_pop <= perf_fetch_q_pop +
				(pop_two_fire ? 32'd2 : (pop_fire ? 32'd1 : 32'd0));
			perf_decode_blocked_by_uopq <= perf_decode_blocked_by_uopq +
				((stall_if_i && fetch_q_valid) ? 32'd1 : 32'd0);
			perf_sync_bp_taken_bubble <= perf_sync_bp_taken_bubble +
				(bp_predict_redirect ? 32'd1 : 32'd0);
			perf_l0_hit <= perf_l0_hit +
				((request_fire && l0_predict_hit) ? 32'd1 : 32'd0);
			perf_l0_taken <= perf_l0_taken +
				((request_fire && l0_predict_taken) ? 32'd1 : 32'd0);
			perf_fq_occ_0 <= perf_fq_occ_0 +
				((fetch_count_ff == 0) ? 32'd1 : 32'd0);
			perf_fq_occ_1 <= perf_fq_occ_1 +
				((fetch_count_ff == 1) ? 32'd1 : 32'd0);
			perf_fq_occ_2 <= perf_fq_occ_2 +
				((fetch_count_ff == 2) ? 32'd1 : 32'd0);
			perf_fq_occ_3 <= perf_fq_occ_3 +
				((fetch_count_ff == 3) ? 32'd1 : 32'd0);
			perf_fq_occ_4 <= perf_fq_occ_4 +
				((fetch_count_ff == 4) ? 32'd1 : 32'd0);
			perf_fq_flush_drop <= perf_fq_flush_drop +
				(flush_queue ? {{(32-FETCH_Q_COUNT_WIDTH){1'b0}}, fetch_count_ff} : 32'd0);
			perf_fq_full_block_req <= perf_fq_full_block_req +
				(fq_full_block_req ? 32'd1 : 32'd0);
			perf_fq_backend_stall_pop <= perf_fq_backend_stall_pop +
				((stall_if_i && fetch_q_valid) ? 32'd1 : 32'd0);
			perf_fq_empty_id_bubble <= perf_fq_empty_id_bubble +
				(fq_empty_id_bubble ? 32'd1 : 32'd0);
			perf_fq_sync_redirect_flush <= perf_fq_sync_redirect_flush +
				(bp_predict_redirect ? 32'd1 : 32'd0);
			perf_fq_ex_redirect_flush <= perf_fq_ex_redirect_flush +
				(branch_jump_i ? 32'd1 : 32'd0);
			perf_l0_lookup <= perf_l0_lookup +
				(request_fire ? 32'd1 : 32'd0);
			perf_l0_correct_taken <= perf_l0_correct_taken +
				((l0_train_fire && l0_train_taken_i && l0_train_pred_taken &&
				  (l0_target_ff[l0_train_index] == l0_train_target_i)) ? 32'd1 : 32'd0);
			perf_l0_wrong_taken <= perf_l0_wrong_taken +
				((l0_train_fire && l0_train_pred_taken &&
				  (!l0_train_taken_i ||
				   (l0_target_ff[l0_train_index] != l0_train_target_i))) ? 32'd1 : 32'd0);
			perf_l0_train_taken <= perf_l0_train_taken +
				((l0_train_fire && l0_train_taken_i) ? 32'd1 : 32'd0);
			perf_l0_train_not_taken <= perf_l0_train_not_taken +
				((l0_train_fire && !l0_train_taken_i) ? 32'd1 : 32'd0);
			perf_l0_counter_inc <= perf_l0_counter_inc +
				(l0_counter_inc ? 32'd1 : 32'd0);
			perf_l0_counter_dec <= perf_l0_counter_dec +
				(l0_counter_dec ? 32'd1 : 32'd0);
			perf_fetch2_req <= perf_fetch2_req +
				(request_two_fire ? 32'd1 : 32'd0);
			perf_fetch2_valid2 <= perf_fetch2_valid2 +
				((enqueue_fire && enqueue1_fire) ? 32'd1 : 32'd0);
			perf_fetch2_valid1_only <= perf_fetch2_valid1_only +
				((enqueue_fire && !enqueue1_fire) ? 32'd1 : 32'd0);
			perf_fetch2_align_block <= perf_fetch2_align_block +
				((request_fire && request_two_dtcm_block) ? 32'd1 : 32'd0);
			perf_fetch2_redirect_kill_slot1 <= perf_fetch2_redirect_kill_slot1 +
				(enqueue1_killed ? 32'd1 : 32'd0);
			perf_fetch2_irom_stall <= perf_fetch2_irom_stall + 32'd0;
			perf_pair_ctrl_try <= perf_pair_ctrl_try +
				(request_pair_ctrl.fetch_pair_try ? 32'd1 : 32'd0);
			perf_pair_ctrl_allow <= perf_pair_ctrl_allow +
				(request_two_fire ? 32'd1 : 32'd0);
			perf_pair_block_predictor <= perf_pair_block_predictor +
				(pair_predictor_suppress ? 32'd1 : 32'd0);
			perf_pair_block_queue <= perf_pair_block_queue +
				(pair_queue_suppress ? 32'd1 : 32'd0);
			perf_pair_block_rule <= perf_pair_block_rule +
				(pair_itcm_suppress ? 32'd1 : 32'd0);
			perf_pair_block_rename <= perf_pair_block_rename + 32'd0;
			perf_pair_block_issue <= perf_pair_block_issue + 32'd0;
			perf_pair_slot1_kill <= perf_pair_slot1_kill +
				((mem_resp_valid1_ff && mem_resp_pair_ctrl.slot1_kill) ? 32'd1 : 32'd0);
		end
	end

endmodule
