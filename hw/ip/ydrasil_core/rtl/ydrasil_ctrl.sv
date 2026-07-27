module ydrasil_ctrl
import ydrasil_pkg::*;
(
    input wire clk,
    input wire rst_n,
    input wire ex_branch_jump_i,
    input wire ex_branch_resolve_i,
    input wire [INST_ADDR_WIDTH-1:0] ex_branch_target_i,
    input wire [INST_ADDR_WIDTH-1:0] ex_pc_i,
    input wire [INST_ADDR_WIDTH-1:0] ex_pc1_i,
    input ydrasil_ex_hzd_pkt_t ex_hzd_i,
    input ydrasil_ex_hzd_pkt_t ex_hzd1_i,
    input ydrasil_issue_pkt_t issue_pkt_i,
    input ydrasil_issue_pkt_t issue_pkt1_i,
	input ydrasil_issue_feedback_pkt_t issue_feedback_i,
    input ydrasil_completion_bus_t completion_bus_i,
    input ydrasil_lsu_status_pkt_t lsu_status_i,
    input wire trap_stall_i,
    input wire ex_mul_stall_i,
    input wire wb_backpressure_i,
    input wire rf_wen_rd_i,
    input wire [REGS_ADDR_WIDTH-1:0] rf_waddr_rd_i,
    input wire [REGS_DATA_WIDTH-1:0] rf_wdata_rd_i,
    input producer_id_t rf_producer_id_i,
    input wire rf_producer_tracked_i,
    input wire rf_wen_rd1_i,
    input wire [REGS_ADDR_WIDTH-1:0] rf_waddr_rd1_i,
    input wire [REGS_DATA_WIDTH-1:0] rf_wdata_rd1_i,
    input producer_id_t rf_producer_id1_i,
    input wire rf_producer_tracked1_i,

    output ydrasil_issue_state_pkt_t issue_state_o,
    output wire [REGS_NUM-1:0] gpr_pending_o,
    output wire ex_accept_valid_o,
    output wire ex_accept_valid1_o,
    output wire rf_write_commit_o,
    output wire [REGS_NUM-1:0] rf_write_wen_o,
    output wire rf_write_commit1_o,
    output wire [REGS_NUM-1:0] rf_write_wen1_o,
    output ydrasil_commit_pkt_t retire_commit_o,
    output ydrasil_commit_pkt_t retire_commit1_o,
    output wire stall_if_o,
    output wire stall_id_o,
    output wire stall_pc_o,
    output wire bubble_id_o,
    output wire flush_if_o,
    output wire flush_id_o,
    output wire flush_ex_o,
    output wire branch_jump_o,
    output wire [INST_ADDR_WIDTH-1:0] branch_target_o
);

    wire ydrasil_id_ctrl_pkt_t id_ctrl_i = issue_pkt_i.ctrl;
    wire ydrasil_id_ctrl_pkt_t id_ctrl1_i = issue_pkt1_i.ctrl;

    reg [PRODUCER_NUM-1:0] producer_valid_q;
    reg [PRODUCER_NUM-1:0] producer_ready_q;
    reg [PRODUCER_NUM-1:0] producer_writes_gpr_q;
    reg [REGS_ADDR_WIDTH-1:0] producer_rd_q [0:PRODUCER_NUM-1];
    (* max_fanout = 8 *) reg [REGS_DATA_WIDTH-1:0] producer_value_q [0:PRODUCER_NUM-1];
    producer_id_t producer_tag_q [0:PRODUCER_NUM-1];
    reg [INST_ADDR_WIDTH-1:0] producer_pc_q [0:PRODUCER_NUM-1];
    reg [2:0] producer_op_class_q [0:PRODUCER_NUM-1];
    reg [2:0] producer_exc_code_q [0:PRODUCER_NUM-1];
    (* max_fanout = 16 *) reg [REGS_NUM-1:0] latest_valid_q;
    // The operand Future File is indexed directly by architectural register.
    // Tags remain metadata for completion versioning and precise recovery; they
    // are never used to select operand data.
    reg [REGS_DATA_WIDTH-1:0] future_value_q [0:REGS_NUM-1];
    reg [1:0] ready_countdown_q [0:REGS_NUM-1];
    reg [REGS_NUM-1:0] ready_indefinite_q;
    reg [REGS_NUM-1:0] producer_lane_q;
    (* max_fanout = 16 *) producer_id_t latest_id_q [0:REGS_NUM-1];
    ydrasil_gpr_fwd_pkt_t wb_fwd_q;
    ydrasil_gpr_fwd_pkt_t wb_fwd1_q;

    localparam int QUEUE_PTR_WIDTH = PRODUCER_SLOT_WIDTH;
    localparam int QUEUE_COUNT_WIDTH = $clog2(PRODUCER_NUM + 1);
    producer_slot_t queue_head_q;
    producer_slot_t queue_tail_q;
    reg [QUEUE_COUNT_WIDTH-1:0] queue_count_q;

    // Branch recovery stores only the branch tag.  No RAT snapshots remain.
    localparam int BRANCH_TAIL_DEPTH = 4;
    localparam int BRANCH_TAIL_PTR_WIDTH = $clog2(BRANCH_TAIL_DEPTH);
    producer_id_t branch_tag_q [0:BRANCH_TAIL_DEPTH-1];
    reg [BRANCH_TAIL_PTR_WIDTH-1:0] branch_head_q;
    reg [BRANCH_TAIL_PTR_WIDTH-1:0] branch_tail_q;
    reg [2:0] branch_count_q;
    wire [REGS_NUM-1:0] latest_retire_mask;
	ydrasil_hzd_status_pkt_t hzd_status_o;
	ydrasil_hzd_status_pkt_t hzd_status1_o;
	ydrasil_gpr_fwd_pkt_t producer_rs1_fwd_o;
	ydrasil_gpr_fwd_pkt_t producer_rs2_fwd_o;
	ydrasil_gpr_fwd_pkt_t producer_rs3_fwd_o;
	ydrasil_gpr_fwd_pkt_t producer_rs4_fwd_o;

    function automatic producer_slot_t queue_ptr_add(
        input producer_slot_t ptr,
        input [1:0] amount
    );
        reg [QUEUE_PTR_WIDTH:0] sum;
        begin
            sum = ptr + amount;
            queue_ptr_add = (sum >= PRODUCER_NUM) ? sum - PRODUCER_NUM : sum;
        end
    endfunction

    function automatic [QUEUE_COUNT_WIDTH-1:0] queue_distance(
        input producer_slot_t first,
        input producer_slot_t last
    );
        begin
			// This function is used for branch recovery after the branch was
			// proven live. Equal pointers therefore describe a full circular
			// interval, not an empty one.
            queue_distance = (last == first) ? PRODUCER_NUM :
				(last > first) ? last - first : PRODUCER_NUM - first + last;
        end
    endfunction

    function automatic [QUEUE_PTR_WIDTH:0] queue_offset(
        input producer_slot_t base,
        input producer_slot_t slot
    );
        begin
            queue_offset = (slot >= base) ? slot - base :
                PRODUCER_NUM - base + slot;
        end
    endfunction

    wire producer_slot_t queue_head1 = queue_ptr_add(queue_head_q, 2'd1);
    wire queue_commit0 = (queue_count_q != '0) && producer_valid_q[queue_head_q] &&
        producer_ready_q[queue_head_q];
    wire queue_commit1 = queue_commit0 &&
        (queue_count_q > QUEUE_COUNT_WIDTH'(1)) && producer_valid_q[queue_head1] &&
        producer_ready_q[queue_head1];
    wire [1:0] queue_commit_count = {1'b0, queue_commit0} +
        {1'b0, queue_commit1};

    // Retirement previously broadcast two dynamically indexed queue entries
    // into every Future File bit.  Capture the two post-commit heads once and
    // replicate their small control fields by eight-register groups.  The
    // ready-vector update below consequently has no queue-head mux or 5-bit
    // compare in each of its 32 generated instances.
    reg [REGS_NUM-1:0] head0_rd_onehot_q;
    reg [REGS_NUM-1:0] head1_rd_onehot_q;
    (* max_fanout = 8 *) reg [3:0] head0_writes_gpr_rep_q;
    (* max_fanout = 8 *) reg [3:0] head1_writes_gpr_rep_q;
    (* max_fanout = 8 *) producer_id_t head0_tag_rep_q [0:3];
    (* max_fanout = 8 *) producer_id_t head1_tag_rep_q [0:3];

    assign retire_commit_o.valid = queue_commit0;
    assign retire_commit_o.writes_gpr = queue_commit0 &&
        producer_writes_gpr_q[queue_head_q];
    assign retire_commit_o.rd_addr = producer_rd_q[queue_head_q];
    assign retire_commit_o.value = producer_value_q[queue_head_q];
    assign retire_commit_o.pc = producer_pc_q[queue_head_q];
    assign retire_commit1_o.valid = queue_commit1;
    assign retire_commit1_o.writes_gpr = queue_commit1 &&
        producer_writes_gpr_q[queue_head1];
    assign retire_commit1_o.rd_addr = producer_rd_q[queue_head1];
    assign retire_commit1_o.value = producer_value_q[queue_head1];
    assign retire_commit1_o.pc = producer_pc_q[queue_head1];

`ifndef SYNTHESIS
    localparam logic [2:0] DBG_PRODUCER_ALU = 3'd1;
    localparam logic [2:0] DBG_PRODUCER_LOAD = 3'd2;
    localparam logic [2:0] DBG_PRODUCER_MUL = 3'd3;
    localparam logic [2:0] DBG_PRODUCER_OTHER = 3'd4;
    logic [2:0] dbg_producer_kind_q [0:PRODUCER_NUM-1];
`endif

    wire ex_is_load = ex_hzd_i.operator_type[OPERATOR_TYPE_LOAD];
    wire ex_is_alu = ex_hzd_i.operator_type[OPERATOR_TYPE_ALU];
    wire ex_is_bitmanip = ex_hzd_i.operator_type[OPERATOR_TYPE_BITMANIP];
    wire id_ex_rd_issue = ex_accept_valid_o && (ex_hzd_i.rd_addr != '0) &&
        !ex_hzd_i.interrupt && (ex_hzd_i.alu_rf_wen || ex_is_load);
    wire id_ex1_rd_issue = ex_accept_valid1_o && (ex_hzd1_i.rd_addr != '0) &&
        !ex_hzd1_i.interrupt &&
        (ex_hzd1_i.alu_rf_wen ||
         ex_hzd1_i.operator_type[OPERATOR_TYPE_LOAD]);

    wire lane0_bypassable = ex_accept_valid_o && ex_hzd_i.alu_rf_wen &&
        (ex_hzd_i.rd_addr != '0) && !ex_hzd_i.interrupt &&
        completion_bus_i[COMPLETION_ALU].valid &&
        (completion_bus_i[COMPLETION_ALU].producer_id == ex_hzd_i.producer_id);
    wire lane1_bypassable = ex_accept_valid1_o && ex_hzd1_i.alu_rf_wen &&
        (ex_hzd1_i.rd_addr != '0) && !ex_hzd1_i.interrupt &&
        completion_bus_i[COMPLETION_DUAL_ALU].valid &&
        (completion_bus_i[COMPLETION_DUAL_ALU].producer_id == ex_hzd1_i.producer_id);

    function automatic ydrasil_bypass_sel_t bypass_for_source(
        input logic ren,
        input logic [REGS_ADDR_WIDTH-1:0] addr,
        input logic consumer_ok
    );
        begin
            bypass_for_source = BYPASS_NONE;
            if (ren && consumer_ok && latest_valid_q[addr] &&
                !ready_indefinite_q[addr] &&
                (ready_countdown_q[addr] == 2'd1)) begin
                if (!producer_lane_q[addr] && lane0_bypassable &&
                    (latest_id_q[addr] == ex_hzd_i.producer_id))
                    bypass_for_source = BYPASS_LANE0;
                else if (producer_lane_q[addr] && lane1_bypassable &&
                    (latest_id_q[addr] == ex_hzd1_i.producer_id))
                    bypass_for_source = BYPASS_LANE1;
            end
        end
    endfunction

    wire ydrasil_bypass_sel_t bypass0_rs1 = bypass_for_source(
        id_ctrl_i.rs1_ren, id_ctrl_i.rs1_addr, id_ctrl_i.prev_alu_bypass_ok);
    wire ydrasil_bypass_sel_t bypass0_rs2 = bypass_for_source(
        id_ctrl_i.rs2_ren, id_ctrl_i.rs2_addr, id_ctrl_i.prev_alu_bypass_ok);
    wire ydrasil_bypass_sel_t bypass1_rs1 = bypass_for_source(
        id_ctrl1_i.rs1_ren, id_ctrl1_i.rs1_addr, 1'b1);
    wire ydrasil_bypass_sel_t bypass1_rs2 = bypass_for_source(
        id_ctrl1_i.rs2_ren, id_ctrl1_i.rs2_addr, 1'b1);
    wire prev_alu_bypass_rs1 = bypass0_rs1 != BYPASS_NONE;
    wire prev_alu_bypass_rs2 = bypass0_rs2 != BYPASS_NONE;
    wire [PRODUCER_NUM-1:0] producer_complete_mask;
    wire [REGS_DATA_WIDTH-1:0] producer_completion_data [0:PRODUCER_NUM-1];
    wire [PRODUCER_NUM-1:0] producer_wb_retire_mask;
    wire [PRODUCER_NUM-1:0] producer_wb_retire0_mask;
    wire [PRODUCER_NUM-1:0] producer_wb_retire1_mask;
    wire producer_alloc_ex;
    wire producer_alloc_ex1;
    genvar completion_idx;
    generate
        for (completion_idx = 0; completion_idx < PRODUCER_NUM;
             completion_idx = completion_idx + 1) begin : g_completion
            wire lane0_hit = completion_bus_i[0].valid &&
                completion_bus_i[0].producer_tracked &&
                producer_valid_q[completion_idx] &&
                (producer_tag_q[completion_idx] == completion_bus_i[0].producer_id);
            wire lane1_hit = completion_bus_i[1].valid &&
                completion_bus_i[1].producer_tracked &&
                producer_valid_q[completion_idx] &&
                (producer_tag_q[completion_idx] == completion_bus_i[1].producer_id);
            wire lane2_hit = completion_bus_i[2].valid &&
                completion_bus_i[2].producer_tracked &&
                producer_valid_q[completion_idx] &&
                (producer_tag_q[completion_idx] == completion_bus_i[2].producer_id);
            wire lane3_hit = completion_bus_i[3].valid &&
                completion_bus_i[3].producer_tracked &&
                producer_valid_q[completion_idx] &&
                (producer_tag_q[completion_idx] == completion_bus_i[3].producer_id);

            assign producer_complete_mask[completion_idx] = lane0_hit |
                lane1_hit | lane2_hit | lane3_hit;
            assign producer_completion_data[completion_idx] = lane0_hit ?
                completion_bus_i[0].data : lane1_hit ?
                completion_bus_i[1].data : lane2_hit ?
                completion_bus_i[2].data : completion_bus_i[3].data;
        end
    endgenerate

    genvar complete_idx;
    generate
        for (complete_idx = 0; complete_idx < PRODUCER_NUM; complete_idx++) begin : g_retire
            assign producer_wb_retire0_mask[complete_idx] = queue_commit0 &&
                producer_writes_gpr_q[queue_head_q] &&
                (queue_head_q == producer_slot_t'(complete_idx));
            assign producer_wb_retire1_mask[complete_idx] = queue_commit1 &&
                producer_writes_gpr_q[queue_head1] &&
                (queue_head1 == producer_slot_t'(complete_idx));
            assign producer_wb_retire_mask[complete_idx] =
                producer_wb_retire0_mask[complete_idx] |
                producer_wb_retire1_mask[complete_idx];
        end
    endgenerate

    wire [PRODUCER_NUM-1:0] producer_retire_q = producer_wb_retire_mask;

    wire producer_has_free = queue_count_q < QUEUE_COUNT_WIDTH'(PRODUCER_NUM);
    wire producer_has_two_free = queue_count_q <=
        QUEUE_COUNT_WIDTH'(PRODUCER_NUM - 2);
    wire queue_alloc0;
    wire queue_alloc1;
    wire [1:0] queue_alloc_count = {1'b0, queue_alloc0} +
        {1'b0, queue_alloc1};
    wire producer_full_stall = id_ctrl_i.valid && !producer_has_free;
    wire producer_pair_stall = id_ctrl1_i.valid && !producer_has_two_free;
    wire branch_tail_full = branch_count_q == 3'(BRANCH_TAIL_DEPTH);
    wire branch_tail_full_stall = id_ctrl_i.checkpoint_req &&
        branch_tail_full && !ex_branch_resolve_i;

    reg [PRODUCER_ID_WIDTH-1:0] producer_alloc_id;
    reg [PRODUCER_ID_WIDTH-1:0] producer_alloc_id1;
    producer_slot_t alloc_slot0;
    producer_slot_t alloc_slot1;
    always_comb begin
        alloc_slot0 = queue_tail_q;
        alloc_slot1 = queue_ptr_add(alloc_slot0, 2'd1);
        producer_alloc_id = {
            ~producer_tag_q[alloc_slot0][PRODUCER_ID_WIDTH-1], alloc_slot0};
        producer_alloc_id1 = {
            ~producer_tag_q[alloc_slot1][PRODUCER_ID_WIDTH-1], alloc_slot1};
    end

    (* max_fanout = 4 *) wire rs1_has_producer = id_ctrl_i.rs1_ren &&
        latest_valid_q[id_ctrl_i.rs1_addr];
    (* max_fanout = 4 *) wire rs2_has_producer = id_ctrl_i.rs2_ren &&
        latest_valid_q[id_ctrl_i.rs2_addr];
    producer_id_t rs1_producer_id;
    producer_id_t rs2_producer_id;
    producer_slot_t rs1_producer_slot;
    producer_slot_t rs2_producer_slot;
    assign rs1_producer_id = latest_id_q[id_ctrl_i.rs1_addr];
    assign rs2_producer_id = latest_id_q[id_ctrl_i.rs2_addr];
    assign rs1_producer_slot = rs1_producer_id[PRODUCER_SLOT_WIDTH-1:0];
    assign rs2_producer_slot = rs2_producer_id[PRODUCER_SLOT_WIDTH-1:0];
`ifndef SYNTHESIS
    wire [2:0] dbg_rs1_producer_kind = rs1_has_producer ?
        dbg_producer_kind_q[rs1_producer_slot] : 3'd0;
    wire [2:0] dbg_rs2_producer_kind = rs2_has_producer ?
        dbg_producer_kind_q[rs2_producer_slot] : 3'd0;
`endif
    wire rs3_has_producer = id_ctrl1_i.rs1_ren &&
        latest_valid_q[id_ctrl1_i.rs1_addr];
    wire rs4_has_producer = id_ctrl1_i.rs2_ren &&
        latest_valid_q[id_ctrl1_i.rs2_addr];
    producer_id_t rs3_producer_id;
    producer_id_t rs4_producer_id;
    producer_slot_t rs3_producer_slot;
    producer_slot_t rs4_producer_slot;
    assign rs3_producer_id = latest_id_q[id_ctrl1_i.rs1_addr];
    assign rs4_producer_id = latest_id_q[id_ctrl1_i.rs2_addr];
    assign rs3_producer_slot = rs3_producer_id[PRODUCER_SLOT_WIDTH-1:0];
    assign rs4_producer_slot = rs4_producer_id[PRODUCER_SLOT_WIDTH-1:0];
    wire rs1_producer_ready = rs1_has_producer &&
        !ready_indefinite_q[id_ctrl_i.rs1_addr] &&
        (ready_countdown_q[id_ctrl_i.rs1_addr] == '0);
    wire rs2_producer_ready = rs2_has_producer &&
        !ready_indefinite_q[id_ctrl_i.rs2_addr] &&
        (ready_countdown_q[id_ctrl_i.rs2_addr] == '0);
    wire rs3_producer_ready = rs3_has_producer &&
        !ready_indefinite_q[id_ctrl1_i.rs1_addr] &&
        (ready_countdown_q[id_ctrl1_i.rs1_addr] == '0);
    wire rs4_producer_ready = rs4_has_producer &&
        !ready_indefinite_q[id_ctrl1_i.rs2_addr] &&
        (ready_countdown_q[id_ctrl1_i.rs2_addr] == '0);

	wire rs1_issue_hzd0 = id_ex_rd_issue && id_ctrl_i.rs1_ren &&
			(id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr) &&
			(bypass0_rs1 != BYPASS_LANE0);
	wire rs2_issue_hzd0 = id_ex_rd_issue && id_ctrl_i.rs2_ren &&
		(id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr) &&
			(bypass0_rs2 != BYPASS_LANE0);
    wire rs1_issue_hzd1 = id_ex1_rd_issue && id_ctrl_i.rs1_ren &&
        (id_ctrl_i.rs1_addr == ex_hzd1_i.rd_addr) &&
        (bypass0_rs1 != BYPASS_LANE1);
    wire rs2_issue_hzd1 = id_ex1_rd_issue && id_ctrl_i.rs2_ren &&
        (id_ctrl_i.rs2_addr == ex_hzd1_i.rd_addr) &&
        (bypass0_rs2 != BYPASS_LANE1);
    wire rs1_issue_hzd = rs1_issue_hzd0 | rs1_issue_hzd1;
    wire rs2_issue_hzd = rs2_issue_hzd0 | rs2_issue_hzd1;
    wire rd_issue_hzd = 1'b0;
    // A bypassable EX writer is newer than any producer already recorded for
    // the same GPR. Do not let that older WAW entry block or wake the consumer.
	wire rs1_pending_stall = rs1_has_producer && !rs1_producer_ready && !prev_alu_bypass_rs1;
	wire rs2_pending_stall = rs2_has_producer && !rs2_producer_ready && !prev_alu_bypass_rs2;
    wire [BRANCH_TAIL_PTR_WIDTH-1:0] youngest_branch_idx =
        (branch_tail_q == '0) ? BRANCH_TAIL_PTR_WIDTH'(BRANCH_TAIL_DEPTH - 1) :
        branch_tail_q - 1'b1;
    wire producer_id_t youngest_branch_tag =
        branch_tag_q[youngest_branch_idx];
    wire producer_slot_t youngest_branch_slot =
        youngest_branch_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire rd_old_after_youngest_branch =
        queue_offset(queue_head_q,
                     latest_id_q[id_ctrl_i.rd_addr][PRODUCER_SLOT_WIDTH-1:0]) >
        queue_offset(queue_head_q, youngest_branch_slot);
    // Replacement is recovery-safe when there is no unresolved branch, or
    // when the old and new versions are both younger than every unresolved
    // branch and therefore get squashed together. No value reconstruction is
    // needed in either case.
    wire rd_waw_recovery_safe = (branch_count_q == '0) ||
        rd_old_after_youngest_branch;
    wire rd_waw_stall = id_ctrl_i.rd_wen &&
        latest_valid_q[id_ctrl_i.rd_addr] &&
        !rd_waw_recovery_safe;
	wire store_data_wait = id_ctrl_i.store_req &&
		rs2_blocking_hzd;
	// Store data follows the same Future File boundary as every other source.
	// A store reaches the LSU only after both its address and data are ready.
	wire rs2_blocking_hzd = rs2_issue_hzd | rs2_pending_stall;
    wire scoreboard_stall = rs1_issue_hzd | rs1_pending_stall |
        rs2_blocking_hzd | rd_waw_stall;
    wire rs3_issue_hzd = id_ctrl1_i.rs1_ren &&
        ((id_ex_rd_issue && (id_ctrl1_i.rs1_addr == ex_hzd_i.rd_addr) &&
          (bypass1_rs1 != BYPASS_LANE0)) ||
         (id_ex1_rd_issue && (id_ctrl1_i.rs1_addr == ex_hzd1_i.rd_addr) &&
          (bypass1_rs1 != BYPASS_LANE1)));
    wire rs4_issue_hzd = id_ctrl1_i.rs2_ren &&
        ((id_ex_rd_issue && (id_ctrl1_i.rs2_addr == ex_hzd_i.rd_addr) &&
          (bypass1_rs2 != BYPASS_LANE0)) ||
         (id_ex1_rd_issue && (id_ctrl1_i.rs2_addr == ex_hzd1_i.rd_addr) &&
          (bypass1_rs2 != BYPASS_LANE1)));
    wire rs3_pending_stall = rs3_has_producer && !rs3_producer_ready &&
        (bypass1_rs1 == BYPASS_NONE);
    wire rs4_pending_stall = rs4_has_producer && !rs4_producer_ready &&
        (bypass1_rs2 == BYPASS_NONE);
    wire rd1_old_after_youngest_branch =
        queue_offset(queue_head_q,
                     latest_id_q[id_ctrl1_i.rd_addr][PRODUCER_SLOT_WIDTH-1:0]) >
        queue_offset(queue_head_q, youngest_branch_slot);
    wire rd1_waw_recovery_safe = !id_ctrl_i.checkpoint_req &&
        ((branch_count_q == '0) || rd1_old_after_youngest_branch);
    wire rd1_waw_stall = id_ctrl1_i.rd_wen &&
        latest_valid_q[id_ctrl1_i.rd_addr] &&
        !rd1_waw_recovery_safe;
    wire scoreboard_stall1 = rs3_issue_hzd | rs4_issue_hzd |
        rs3_pending_stall | rs4_pending_stall | rd1_waw_stall;
    wire lsu_struct_stall = id_ctrl_i.lsu_req && lsu_status_i.busy;
    // CSR/SYS/fence execute only after all older instructions have retired.
    // Waiting merely for LSU idle allowed a CSR read to pass an older ALU or
    // MUL result that was complete but not yet architecturally committed.
    wire serialize_stall = id_ctrl_i.serialize_before &&
		(!lsu_status_i.idle || (queue_count_q != '0));
`ifndef SYNTHESIS
	wire lsu_serialize_stall = serialize_stall;
`endif
    wire decode_bubble_stall = scoreboard_stall | lsu_struct_stall |
        serialize_stall |
        producer_full_stall | branch_tail_full_stall |
        trap_stall_i |
        wb_backpressure_i;
    // A redirecting EX instruction invalidates every younger Issue entry in
    // this cycle.  Suppress its queue allocation at the same boundary; keeping
    // such an entry would leave a producer that can never receive completion.
    assign queue_alloc0 = id_ctrl_i.valid && !decode_bubble_stall &&
        !ex_mul_stall_i && !ex_branch_jump_i && !ex_hzd_i.flush_younger;
    assign queue_alloc1 = queue_alloc0 && id_ctrl1_i.valid &&
        !scoreboard_stall1 && !producer_pair_stall &&
        !(id_ctrl1_i.lsu_req && lsu_status_i.busy);
    assign producer_alloc_ex = queue_alloc0 && id_ctrl_i.rd_wen;
    assign producer_alloc_ex1 = queue_alloc1 && id_ctrl1_i.rd_wen;
    wire issue0_fixed_alu =
        (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_ALU] ||
         issue_pkt_i.decode.operator_type[OPERATOR_TYPE_BITMANIP]) &&
        !issue_pkt_i.decode.operator_type[OPERATOR_TYPE_MUL];
    wire issue1_fixed_alu =
        (issue_pkt1_i.decode.operator_type[OPERATOR_TYPE_ALU] ||
         issue_pkt1_i.decode.operator_type[OPERATOR_TYPE_BITMANIP]) &&
        !issue_pkt1_i.decode.operator_type[OPERATOR_TYPE_MUL];
    wire issue0_fixed_load = issue_feedback_i.slot0_fixed_dtcm_load &&
        lsu_status_i.idle;
    wire issue1_fixed_load = issue_feedback_i.slot1_fixed_dtcm_load &&
        lsu_status_i.idle;
    wire branch_tail_alloc = id_ctrl_i.checkpoint_req &&
        !decode_bubble_stall && !ex_mul_stall_i && !ex_branch_jump_i &&
        !ex_hzd_i.flush_younger;

    assign rf_write_commit_o = !rf_wen_rd_i || !rf_producer_tracked_i ||
        (latest_valid_q[rf_waddr_rd_i] &&
         (latest_id_q[rf_waddr_rd_i] == rf_producer_id_i));
    assign rf_write_commit1_o = !rf_wen_rd1_i || !rf_producer_tracked1_i ||
        (latest_valid_q[rf_waddr_rd1_i] &&
         (latest_id_q[rf_waddr_rd1_i] == rf_producer_id1_i));

    // Predecode the committed write per GPR.  Keeping the fixed latest-id
    // comparison beside each enable avoids a dynamic lookup followed by a
    // second address decode on the register-file write-enable path.
    assign rf_write_wen_o[0] = 1'b0;
    assign rf_write_wen1_o[0] = 1'b0;
    genvar rf_write_idx;
    generate
        for (rf_write_idx = 1; rf_write_idx < REGS_NUM;
             rf_write_idx = rf_write_idx + 1) begin : g_rf_write_wen
            assign rf_write_wen_o[rf_write_idx] = rf_wen_rd_i &&
                (rf_waddr_rd_i == REGS_ADDR_WIDTH'(rf_write_idx)) &&
                (!rf_producer_tracked_i ||
                 (latest_valid_q[rf_write_idx] &&
                  (latest_id_q[rf_write_idx] == rf_producer_id_i)));
            assign rf_write_wen1_o[rf_write_idx] = rf_wen_rd1_i &&
                (rf_waddr_rd1_i == REGS_ADDR_WIDTH'(rf_write_idx)) &&
                (!rf_producer_tracked1_i ||
                 (latest_valid_q[rf_write_idx] &&
                  (latest_id_q[rf_write_idx] == rf_producer_id1_i)));
        end
    endgenerate
    assign ex_accept_valid_o = ex_hzd_i.valid && !ex_branch_jump_i;
    // 槽位 1 与主 ID/EX 一同受乘除法后端背压。保持期间不得重复
    // 接受同一条简单整数指令，也不得重复分配其生产者。
    assign ex_accept_valid1_o = ex_hzd1_i.valid && !ex_branch_jump_i &&
        !ex_mul_stall_i;
    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;
    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o;
    assign flush_ex_o = branch_jump_o;
    assign stall_id_o = ex_mul_stall_i;
    // Scoreboard pressure stops only the Issue head. ID and IF continue until
    // their elastic queues fill, which is the actual ID/Issue decoupling point.
    assign stall_if_o = 1'b0;
    assign stall_pc_o = 1'b0;
    assign bubble_id_o = decode_bubble_stall;

    // Operand packets only expose values retained in the registered Future
    // File. Completion matching and data capture terminate at that boundary.
    assign producer_rs1_fwd_o.valid = rs1_has_producer &&
        !ready_indefinite_q[id_ctrl_i.rs1_addr] &&
        (ready_countdown_q[id_ctrl_i.rs1_addr] == '0);
    assign producer_rs1_fwd_o.producer_id = rs1_producer_id;
    assign producer_rs1_fwd_o.producer_tracked = rs1_has_producer;
    assign producer_rs1_fwd_o.addr = id_ctrl_i.rs1_addr;
    assign producer_rs1_fwd_o.data = future_value_q[id_ctrl_i.rs1_addr];
    assign producer_rs2_fwd_o.valid = rs2_has_producer &&
        !ready_indefinite_q[id_ctrl_i.rs2_addr] &&
        (ready_countdown_q[id_ctrl_i.rs2_addr] == '0);
    assign producer_rs2_fwd_o.producer_id = rs2_producer_id;
    assign producer_rs2_fwd_o.producer_tracked = rs2_has_producer;
    assign producer_rs2_fwd_o.addr = id_ctrl_i.rs2_addr;
    assign producer_rs2_fwd_o.data = future_value_q[id_ctrl_i.rs2_addr];
    assign producer_rs3_fwd_o.valid = rs3_has_producer &&
        !ready_indefinite_q[id_ctrl1_i.rs1_addr] &&
        (ready_countdown_q[id_ctrl1_i.rs1_addr] == '0);
    assign producer_rs3_fwd_o.producer_id = rs3_producer_id;
    assign producer_rs3_fwd_o.producer_tracked = rs3_has_producer;
    assign producer_rs3_fwd_o.addr = id_ctrl1_i.rs1_addr;
    assign producer_rs3_fwd_o.data = future_value_q[id_ctrl1_i.rs1_addr];
    assign producer_rs4_fwd_o.valid = rs4_has_producer &&
        !ready_indefinite_q[id_ctrl1_i.rs2_addr] &&
        (ready_countdown_q[id_ctrl1_i.rs2_addr] == '0);
    assign producer_rs4_fwd_o.producer_id = rs4_producer_id;
    assign producer_rs4_fwd_o.producer_tracked = rs4_has_producer;
    assign producer_rs4_fwd_o.addr = id_ctrl1_i.rs2_addr;
    assign producer_rs4_fwd_o.data = future_value_q[id_ctrl1_i.rs2_addr];
    assign gpr_pending_o = latest_valid_q;

    wire [REGS_NUM-1:0] gpr_pending_clear_mask = latest_retire_mask;
    wire [REGS_NUM-1:0] gpr_pending_issue_mask =
        (id_ex_rd_issue ? (REGS_NUM'(1) << ex_hzd_i.rd_addr) : '0) |
        (id_ex1_rd_issue ? (REGS_NUM'(1) << ex_hzd1_i.rd_addr) : '0);
    wire [REGS_NUM-1:0] gpr_pending_for_hazard = latest_valid_q;

    assign hzd_status_o.scoreboard_stall = scoreboard_stall;
    assign hzd_status_o.lsu_struct_stall = lsu_struct_stall;
	assign hzd_status_o.prev_alu_bypass_rs1 = prev_alu_bypass_rs1;
	assign hzd_status_o.prev_alu_bypass_rs2 = prev_alu_bypass_rs2;
    assign hzd_status_o.rs1_pending_stall = rs1_pending_stall;
    assign hzd_status_o.rs2_pending_stall = rs2_pending_stall;
    assign hzd_status_o.rd_waw_stall = rd_waw_stall;
    assign hzd_status_o.rs1_issue_hzd = rs1_issue_hzd;
    assign hzd_status_o.rs2_issue_hzd = rs2_issue_hzd;
    assign hzd_status_o.rd_issue_hzd = rd_issue_hzd;
    assign hzd_status_o.issue_load_producer = id_ex_rd_issue && ex_is_load;
    assign hzd_status_o.issue_alu_producer = id_ex_rd_issue &&
        ex_hzd_i.alu_rf_wen && ex_is_alu;
    assign hzd_status_o.issue_mul_div_producer = id_ex_rd_issue &&
        ex_hzd_i.operator_type[OPERATOR_TYPE_MUL];
    assign hzd_status_o.issue_src_hzd = rs1_issue_hzd | rs2_issue_hzd;
    assign hzd_status_o.store_data_wait = store_data_wait;
    assign hzd_status_o.id_ex_rd_issue = id_ex_rd_issue;
    assign hzd_status_o.gpr_pending_clear_mask = gpr_pending_clear_mask;
    assign hzd_status_o.gpr_pending_issue_mask = gpr_pending_issue_mask;
    assign hzd_status_o.gpr_pending_for_hazard = gpr_pending_for_hazard;
    always_comb begin
        hzd_status1_o = '0;
        hzd_status1_o.scoreboard_stall = scoreboard_stall1 |
            producer_pair_stall |
            (id_ctrl1_i.lsu_req && lsu_status_i.busy);
        hzd_status1_o.lsu_struct_stall =
            id_ctrl1_i.lsu_req && lsu_status_i.busy;
        hzd_status1_o.rs1_pending_stall = rs3_pending_stall;
        hzd_status1_o.rs2_pending_stall = rs4_pending_stall;
        hzd_status1_o.rs1_issue_hzd = rs3_issue_hzd;
        hzd_status1_o.rs2_issue_hzd = rs4_issue_hzd;
        hzd_status1_o.issue_src_hzd = rs3_issue_hzd | rs4_issue_hzd;
        hzd_status1_o.gpr_pending_for_hazard = latest_valid_q;
    end
    always_comb begin
		issue_state_o = '0;
		issue_state_o.slot0.hazard = hzd_status_o;
		issue_state_o.slot0.src1 = producer_rs1_fwd_o;
		issue_state_o.slot0.src2 = producer_rs2_fwd_o;
		issue_state_o.slot0.bypass_rs1 = bypass0_rs1;
		issue_state_o.slot0.bypass_rs2 = bypass0_rs2;
		issue_state_o.slot0.producer_id = producer_alloc_id;
		issue_state_o.slot0.producer_tracked = id_ctrl_i.rd_wen;
		issue_state_o.slot1.hazard = hzd_status1_o;
		issue_state_o.slot1.src1 = producer_rs3_fwd_o;
		issue_state_o.slot1.src2 = producer_rs4_fwd_o;
		issue_state_o.slot1.bypass_rs1 = bypass1_rs1;
		issue_state_o.slot1.bypass_rs2 = bypass1_rs2;
		issue_state_o.slot1.producer_id = producer_alloc_id1;
		issue_state_o.slot1.producer_tracked = id_ctrl1_i.rd_wen;
		issue_state_o.wb.wb0 = wb_fwd_q;
		issue_state_o.wb.wb1 = wb_fwd1_q;
	end

    integer slot_idx;
    integer reg_idx;
    wire [REGS_NUM-1:0] latest_valid_next;
    wire producer_slot_t queue_head_after_commit =
        queue_ptr_add(queue_head_q, queue_commit_count);
    wire producer_slot_t head1_after_commit =
        queue_ptr_add(queue_head_after_commit, 2'd1);
    wire head0_next_writes_gpr =
        (queue_alloc0 && (alloc_slot0 == queue_head_after_commit)) ?
            id_ctrl_i.rd_wen :
        (queue_alloc1 && (alloc_slot1 == queue_head_after_commit)) ?
            id_ctrl1_i.rd_wen :
            producer_writes_gpr_q[queue_head_after_commit];
    wire head1_next_writes_gpr =
        (queue_alloc0 && (alloc_slot0 == head1_after_commit)) ?
            id_ctrl_i.rd_wen :
        (queue_alloc1 && (alloc_slot1 == head1_after_commit)) ?
            id_ctrl1_i.rd_wen :
            producer_writes_gpr_q[head1_after_commit];
    wire [REGS_ADDR_WIDTH-1:0] head0_next_rd =
        (queue_alloc0 && (alloc_slot0 == queue_head_after_commit)) ?
            id_ctrl_i.rd_addr :
        (queue_alloc1 && (alloc_slot1 == queue_head_after_commit)) ?
            id_ctrl1_i.rd_addr : producer_rd_q[queue_head_after_commit];
    wire [REGS_ADDR_WIDTH-1:0] head1_next_rd =
        (queue_alloc0 && (alloc_slot0 == head1_after_commit)) ?
            id_ctrl_i.rd_addr :
        (queue_alloc1 && (alloc_slot1 == head1_after_commit)) ?
            id_ctrl1_i.rd_addr : producer_rd_q[head1_after_commit];
    producer_id_t head0_next_tag;
    producer_id_t head1_next_tag;
    assign head0_next_tag =
        (queue_alloc0 && (alloc_slot0 == queue_head_after_commit)) ?
            producer_alloc_id :
        (queue_alloc1 && (alloc_slot1 == queue_head_after_commit)) ?
            producer_alloc_id1 : producer_tag_q[queue_head_after_commit];
    assign head1_next_tag =
        (queue_alloc0 && (alloc_slot0 == head1_after_commit)) ?
            producer_alloc_id :
        (queue_alloc1 && (alloc_slot1 == head1_after_commit)) ?
            producer_alloc_id1 : producer_tag_q[head1_after_commit];
    genvar ready_idx;
    generate
        for (ready_idx = 0; ready_idx < REGS_NUM; ready_idx++) begin : g_ready_next
            wire alloc0_here = producer_alloc_ex &&
                (id_ctrl_i.rd_addr == REGS_ADDR_WIDTH'(ready_idx));
            wire alloc1_here = producer_alloc_ex1 &&
                (id_ctrl1_i.rd_addr == REGS_ADDR_WIDTH'(ready_idx));
            wire retire0_here = queue_commit0 &&
                head0_writes_gpr_rep_q[ready_idx / 8] &&
                head0_rd_onehot_q[ready_idx] &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == head0_tag_rep_q[ready_idx / 8]);
            wire retire1_here = queue_commit1 &&
                head1_writes_gpr_rep_q[ready_idx / 8] &&
                head1_rd_onehot_q[ready_idx] &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == head1_tag_rep_q[ready_idx / 8]);

            assign latest_retire_mask[ready_idx] = retire0_here | retire1_here;
            assign latest_valid_next[ready_idx] = (alloc1_here | alloc0_here) ?
                1'b1 : (retire0_here | retire1_here) ?
                1'b0 : latest_valid_q[ready_idx];
        end
    endgenerate

    wire producer_id_t resolved_branch_tag = branch_tag_q[branch_head_q];
    wire producer_slot_t resolved_branch_slot =
        resolved_branch_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t resolved_branch_next =
        queue_ptr_add(resolved_branch_slot, 2'd1);
    wire resolved_branch_live = (branch_count_q != '0) &&
        producer_valid_q[resolved_branch_slot] &&
        (producer_tag_q[resolved_branch_slot] == resolved_branch_tag);
    wire [QUEUE_COUNT_WIDTH-1:0] recovery_count =
        queue_distance(queue_head_after_commit, resolved_branch_next);
    wire [PRODUCER_NUM-1:0] recovery_live_mask;
    genvar recovery_idx;
    generate
        for (recovery_idx = 0; recovery_idx < PRODUCER_NUM; recovery_idx++) begin : g_recovery_live
            assign recovery_live_mask[recovery_idx] = resolved_branch_live &&
				producer_valid_q[recovery_idx] &&
				((queue_head_after_commit <= resolved_branch_slot) ?
				 ((producer_slot_t'(recovery_idx) >= queue_head_after_commit) &&
				  (producer_slot_t'(recovery_idx) <= resolved_branch_slot)) :
				 ((producer_slot_t'(recovery_idx) >= queue_head_after_commit) ||
				  (producer_slot_t'(recovery_idx) <= resolved_branch_slot)));
        end
    endgenerate

	wire [REGS_NUM-1:0] recovery_rat_valid;
	wire [REGS_NUM-1:0] recovery_rat_indefinite;
	producer_id_t recovery_rat_id [0:REGS_NUM-1];
	genvar recovery_reg;
	generate
		for (recovery_reg = 0; recovery_reg < REGS_NUM;
			 recovery_reg++) begin : g_recovery_rat_clear
			wire producer_slot_t rat_slot =
				latest_id_q[recovery_reg][PRODUCER_SLOT_WIDTH-1:0];
			wire rat_entry_survives = latest_valid_q[recovery_reg] &&
				recovery_live_mask[rat_slot] &&
				(producer_tag_q[rat_slot] == latest_id_q[recovery_reg]);
			assign recovery_rat_valid[recovery_reg] = rat_entry_survives;
			assign recovery_rat_indefinite[recovery_reg] = rat_entry_survives &&
				!(producer_ready_q[rat_slot] || producer_complete_mask[rat_slot]);
			assign recovery_rat_id[recovery_reg] = latest_id_q[recovery_reg];
		end
	endgenerate

    wire completion_latest_hit0 = completion_bus_i[0].valid &&
        completion_bus_i[0].producer_tracked &&
        latest_valid_q[completion_bus_i[0].addr] &&
        (latest_id_q[completion_bus_i[0].addr] ==
         completion_bus_i[0].producer_id);
    wire completion_latest_hit1 = completion_bus_i[1].valid &&
        completion_bus_i[1].producer_tracked &&
        latest_valid_q[completion_bus_i[1].addr] &&
        (latest_id_q[completion_bus_i[1].addr] ==
         completion_bus_i[1].producer_id);
    wire completion_latest_hit2 = completion_bus_i[2].valid &&
        completion_bus_i[2].producer_tracked &&
        latest_valid_q[completion_bus_i[2].addr] &&
        (latest_id_q[completion_bus_i[2].addr] ==
         completion_bus_i[2].producer_id);
    wire completion_latest_hit3 = completion_bus_i[3].valid &&
        completion_bus_i[3].producer_tracked &&
        latest_valid_q[completion_bus_i[3].addr] &&
        (latest_id_q[completion_bus_i[3].addr] ==
         completion_bus_i[3].producer_id);

    integer branch_idx;
    always_ff @(posedge clk) begin
        if (!rst_n || ex_hzd_i.interrupt) begin
            branch_head_q <= '0;
            branch_tail_q <= '0;
            branch_count_q <= '0;
            for (branch_idx = 0; branch_idx < BRANCH_TAIL_DEPTH; branch_idx++)
                branch_tag_q[branch_idx] <= '0;
        end else if (ex_branch_jump_i) begin
            branch_head_q <= '0;
            branch_tail_q <= '0;
            branch_count_q <= '0;
        end else begin
            if (branch_tail_alloc) begin
                branch_tag_q[branch_tail_q] <= producer_alloc_id;
                branch_tail_q <= branch_tail_q + 1'b1;
            end
            if (ex_branch_resolve_i && (branch_count_q != '0))
                branch_head_q <= branch_head_q + 1'b1;
            unique case ({branch_tail_alloc,
                          ex_branch_resolve_i && (branch_count_q != '0)})
                2'b10: branch_count_q <= branch_count_q + 1'b1;
                2'b01: branch_count_q <= branch_count_q - 1'b1;
                default: branch_count_q <= branch_count_q;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            producer_writes_gpr_q <= '0;
            queue_head_q <= '0;
            queue_tail_q <= '0;
            queue_count_q <= '0;
            latest_valid_q <= '0;
            ready_indefinite_q <= '0;
            producer_lane_q <= '0;
            wb_fwd_q <= '0;
            wb_fwd1_q <= '0;
            head0_rd_onehot_q <= '0;
            head1_rd_onehot_q <= '0;
            head0_writes_gpr_rep_q <= '0;
            head1_writes_gpr_rep_q <= '0;
            head0_tag_rep_q[0] <= '0;
            head0_tag_rep_q[1] <= '0;
            head0_tag_rep_q[2] <= '0;
            head0_tag_rep_q[3] <= '0;
            head1_tag_rep_q[0] <= '0;
            head1_tag_rep_q[1] <= '0;
            head1_tag_rep_q[2] <= '0;
            head1_tag_rep_q[3] <= '0;
            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                producer_tag_q[slot_idx] <= '0;
`ifndef SYNTHESIS
                dbg_producer_kind_q[slot_idx] <= '0;
`endif
            end
            for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++) begin
                latest_id_q[reg_idx] <= '0;
                ready_countdown_q[reg_idx] <= '0;
            end
        end else if (ex_hzd_i.interrupt) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            producer_writes_gpr_q <= '0;
            queue_head_q <= '0;
            queue_tail_q <= '0;
            queue_count_q <= '0;
            latest_valid_q <= '0;
            ready_indefinite_q <= '0;
            producer_lane_q <= '0;
            wb_fwd_q <= '0;
            wb_fwd1_q <= '0;
            head0_rd_onehot_q <= '0;
            head1_rd_onehot_q <= '0;
            head0_writes_gpr_rep_q <= '0;
            head1_writes_gpr_rep_q <= '0;
            head0_tag_rep_q[0] <= '0;
            head0_tag_rep_q[1] <= '0;
            head0_tag_rep_q[2] <= '0;
            head0_tag_rep_q[3] <= '0;
            head1_tag_rep_q[0] <= '0;
            head1_tag_rep_q[1] <= '0;
            head1_tag_rep_q[2] <= '0;
            head1_tag_rep_q[3] <= '0;
        end else begin
            if (queue_commit_count != '0)
                queue_head_q <= queue_ptr_add(queue_head_q, queue_commit_count);
            if (queue_alloc_count != '0)
                queue_tail_q <= queue_ptr_add(queue_tail_q, queue_alloc_count);
            queue_count_q <= queue_count_q + QUEUE_COUNT_WIDTH'(queue_alloc_count) -
                QUEUE_COUNT_WIDTH'(queue_commit_count);
            latest_valid_q <= latest_valid_next;

            for (reg_idx = 1; reg_idx < REGS_NUM; reg_idx++) begin
                if (!ready_indefinite_q[reg_idx] &&
                    (ready_countdown_q[reg_idx] != '0))
                    ready_countdown_q[reg_idx] <=
                        ready_countdown_q[reg_idx] - 1'b1;
                if (latest_retire_mask[reg_idx]) begin
                    ready_indefinite_q[reg_idx] <= 1'b0;
                    ready_countdown_q[reg_idx] <= '0;
                end
            end

            if (completion_latest_hit0) begin
                future_value_q[completion_bus_i[0].addr] <= completion_bus_i[0].data;
                ready_indefinite_q[completion_bus_i[0].addr] <= 1'b0;
                ready_countdown_q[completion_bus_i[0].addr] <= '0;
            end
            if (completion_latest_hit1) begin
                future_value_q[completion_bus_i[1].addr] <= completion_bus_i[1].data;
                ready_indefinite_q[completion_bus_i[1].addr] <= 1'b0;
                ready_countdown_q[completion_bus_i[1].addr] <= '0;
            end
            if (completion_latest_hit2) begin
                future_value_q[completion_bus_i[2].addr] <= completion_bus_i[2].data;
                ready_indefinite_q[completion_bus_i[2].addr] <= 1'b0;
                ready_countdown_q[completion_bus_i[2].addr] <= '0;
            end
            if (completion_latest_hit3) begin
                future_value_q[completion_bus_i[3].addr] <= completion_bus_i[3].data;
                ready_indefinite_q[completion_bus_i[3].addr] <= 1'b0;
                ready_countdown_q[completion_bus_i[3].addr] <= '0;
            end
            head0_rd_onehot_q <= head0_next_writes_gpr ?
                (REGS_NUM'(1) << head0_next_rd) : '0;
            head1_rd_onehot_q <= head1_next_writes_gpr ?
                (REGS_NUM'(1) << head1_next_rd) : '0;
            head0_writes_gpr_rep_q <= {4{head0_next_writes_gpr}};
            head1_writes_gpr_rep_q <= {4{head1_next_writes_gpr}};
            head0_tag_rep_q[0] <= head0_next_tag;
            head0_tag_rep_q[1] <= head0_next_tag;
            head0_tag_rep_q[2] <= head0_next_tag;
            head0_tag_rep_q[3] <= head0_next_tag;
            head1_tag_rep_q[0] <= head1_next_tag;
            head1_tag_rep_q[1] <= head1_next_tag;
            head1_tag_rep_q[2] <= head1_next_tag;
            head1_tag_rep_q[3] <= head1_next_tag;
            wb_fwd_q.valid <= rf_wen_rd_i && rf_write_commit_o;
            wb_fwd_q.producer_id <= rf_producer_id_i;
            wb_fwd_q.producer_tracked <= rf_producer_tracked_i;
            wb_fwd_q.addr <= rf_waddr_rd_i;
            wb_fwd_q.data <= rf_wdata_rd_i;
            wb_fwd1_q.valid <= rf_wen_rd1_i && rf_write_commit1_o;
            wb_fwd1_q.producer_id <= rf_producer_id1_i;
            wb_fwd1_q.producer_tracked <= rf_producer_tracked1_i;
            wb_fwd1_q.addr <= rf_waddr_rd1_i;
            wb_fwd1_q.data <= rf_wdata_rd1_i;

            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                if ((queue_commit0 && (queue_head_q == producer_slot_t'(slot_idx))) ||
                    (queue_commit1 && (queue_head1 == producer_slot_t'(slot_idx)))) begin
                    producer_valid_q[slot_idx] <= 1'b0;
                    producer_ready_q[slot_idx] <= 1'b0;
                    producer_writes_gpr_q[slot_idx] <= 1'b0;
                end
                if (producer_complete_mask[slot_idx]) begin
                    if (!producer_op_class_q[slot_idx][2])
                        producer_ready_q[slot_idx] <= 1'b1;
                    producer_value_q[slot_idx] <= producer_completion_data[slot_idx];
                end
            end

            if (ex_branch_resolve_i && resolved_branch_live)
                producer_ready_q[resolved_branch_slot] <= 1'b1;

            if (queue_alloc0) begin
                producer_valid_q[alloc_slot0] <= 1'b1;
                producer_ready_q[alloc_slot0] <=
                    !issue_pkt_i.decode.operator_type[OPERATOR_TYPE_BJP] &&
                    !id_ctrl_i.rd_wen;
                producer_writes_gpr_q[alloc_slot0] <= id_ctrl_i.rd_wen;
                producer_rd_q[alloc_slot0] <= id_ctrl_i.rd_addr;
                producer_tag_q[alloc_slot0] <= producer_alloc_id;
                producer_pc_q[alloc_slot0] <= issue_pkt_i.decode.pc;
                producer_op_class_q[alloc_slot0] <= {
                    issue_pkt_i.decode.operator_type[OPERATOR_TYPE_BJP],
                    issue_pkt_i.decode.operator_type[OPERATOR_TYPE_STORE],
                    issue_pkt_i.decode.operator_type[OPERATOR_TYPE_LOAD]};
                producer_exc_code_q[alloc_slot0] <= '0;
`ifndef SYNTHESIS
                if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_LOAD])
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_LOAD;
                else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_MUL])
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_MUL;
                else if (issue_pkt_i.decode.operator_type[OPERATOR_TYPE_ALU])
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_ALU;
                else
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_OTHER;
`endif
                if (producer_alloc_ex) begin
                    latest_id_q[id_ctrl_i.rd_addr] <= producer_alloc_id;
                    ready_countdown_q[id_ctrl_i.rd_addr] <= issue0_fixed_alu ?
                        2'd1 : issue0_fixed_load ? 2'd2 : '0;
                    ready_indefinite_q[id_ctrl_i.rd_addr] <=
                        !(issue0_fixed_alu || issue0_fixed_load);
                    producer_lane_q[id_ctrl_i.rd_addr] <= 1'b0;
                end
            end
            if (queue_alloc1) begin
                producer_valid_q[alloc_slot1] <= 1'b1;
                producer_ready_q[alloc_slot1] <= !id_ctrl1_i.rd_wen;
                producer_writes_gpr_q[alloc_slot1] <= id_ctrl1_i.rd_wen;
                producer_rd_q[alloc_slot1] <= id_ctrl1_i.rd_addr;
                producer_tag_q[alloc_slot1] <= producer_alloc_id1;
                producer_pc_q[alloc_slot1] <= issue_pkt1_i.decode.pc;
                producer_op_class_q[alloc_slot1] <= {
                    issue_pkt1_i.decode.operator_type[OPERATOR_TYPE_BJP],
                    issue_pkt1_i.decode.operator_type[OPERATOR_TYPE_STORE],
                    issue_pkt1_i.decode.operator_type[OPERATOR_TYPE_LOAD]};
                producer_exc_code_q[alloc_slot1] <= '0;
`ifndef SYNTHESIS
                dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_ALU;
`endif
                if (producer_alloc_ex1) begin
                    latest_id_q[id_ctrl1_i.rd_addr] <= producer_alloc_id1;
                    ready_countdown_q[id_ctrl1_i.rd_addr] <= issue1_fixed_alu ?
                        2'd1 : issue1_fixed_load ? 2'd2 : '0;
                    ready_indefinite_q[id_ctrl1_i.rd_addr] <=
                        !(issue1_fixed_alu || issue1_fixed_load);
                    producer_lane_q[id_ctrl1_i.rd_addr] <= 1'b1;
                end
            end
            if (ex_branch_jump_i && ex_branch_resolve_i && resolved_branch_live) begin
                producer_valid_q <= recovery_live_mask;
                queue_head_q <= queue_head_after_commit;
                queue_tail_q <= resolved_branch_next;
                queue_count_q <= recovery_count;
                latest_valid_q <= recovery_rat_valid;
                ready_indefinite_q <= recovery_rat_indefinite;
                for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++)
                    begin
                        latest_id_q[reg_idx] <= recovery_rat_id[reg_idx];
                        ready_countdown_q[reg_idx] <= '0;
                    end
            end
        end
    end
endmodule
