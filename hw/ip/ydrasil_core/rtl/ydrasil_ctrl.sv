module ydrasil_ctrl
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ex_branch_jump_i,
    input  wire                         ex_branch_resolve_i,
    input  producer_id_t                ex_branch_producer_id_i,
    input  wire [INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    input  wire [INST_ADDR_WIDTH-1:0]   ex_pc_i,
    input  wire [INST_ADDR_WIDTH-1:0]   ex_pc1_i,
    input  ydrasil_ex_hzd_pkt_t         ex_hzd_i,
    input  ydrasil_ex_hzd_pkt_t         ex_hzd1_i,
	input  wire                         ex_no_result_due0_valid_i,
	input  producer_id_t                ex_no_result_due0_id_i,
	input  wire                         ex_no_result_due1_valid_i,
	input  producer_id_t                ex_no_result_due1_id_i,
	input  wire                         ex_branch_due_valid_i,
	input  producer_id_t                ex_branch_due_id_i,
	input  wire                         serial_complete_i,
	    input  ydrasil_issue_pkt_t          dispatch_pkt_i,
	    input  ydrasil_issue_pkt_t          dispatch_pkt1_i,
	    input  ydrasil_source_desc_t        decode_src0_i,
	    input  ydrasil_source_desc_t        decode_src1_i,
	    input  ydrasil_source_desc_t        decode_src2_i,
	    input  ydrasil_source_desc_t        decode_src3_i,
	    input  wire                         decode_dst0_writes_i,
	    input  wire [REGS_ADDR_WIDTH-1:0]  decode_dst0_addr_i,
    input  wire                         dispatch_serial_i,
    input  wire                         dispatch_serial1_i,
    input  wire                         dispatch_accept_i,
    input  wire                         dispatch_accept1_i,
    input  ydrasil_compact_uop_t        issue_pkt_i,
    input  ydrasil_compact_uop_t        issue_pkt1_i,
    input  wire                         issue_fence_i,
    input  producer_id_t                issue_fence_tag_i,
	    input  ydrasil_completion_meta_t    completion_meta_i [COMPLETION_LANES],
	    input  wire [REGS_ADDR_WIDTH-1:0]   completion_rd_i [COMPLETION_LANES],
    input  wire                         trap_stall_i,
    input  wire                         ex_mul_stall_i,
    input  wire [REGS_DATA_WIDTH-1:0]   retire_value0_i,
    input  wire [REGS_DATA_WIDTH-1:0]   retire_value1_i,

	    output ydrasil_issue_pkt_t          dispatch_pkt_o,
	    output ydrasil_issue_pkt_t          dispatch_pkt1_o,
	    output ydrasil_source_desc_t        renamed_src0_o,
	    output ydrasil_source_desc_t        renamed_src1_o,
	    output ydrasil_source_desc_t        renamed_src2_o,
	    output ydrasil_source_desc_t        renamed_src3_o,
	    output wire                         renamed_src0_static_ready_o,
	    output wire                         renamed_src1_static_ready_o,
	    output wire                         renamed_src2_static_ready_o,
	    output wire                         renamed_src3_static_ready_o,
    output wire                         dispatch_ready_o,
    output wire                         dispatch_two_ready_o,
    output wire                         issue_at_rob_head_o,
    output producer_id_t                rob_head_id_o,
    output wire                         backend_empty_o,
    output wire                         ex_accept_valid_o,
    output wire                         ex_accept_valid1_o,
    output ydrasil_commit_pkt_t         retire_commit_o,
    output ydrasil_commit_pkt_t         retire_commit1_o,
    output wire                         retire_valid_o,
    output wire                         retire_valid1_o,
    output producer_id_t                retire_value_id0_o,
    output producer_id_t                retire_value_id1_o,
    output wire                         stall_if_o,
    output wire                         stall_id_o,
    output wire                         bubble_id_o,
    output wire                         flush_if_o,
    output wire                         flush_id_o,
    output wire                         flush_ex_o,
    output wire                         pipeline_flush_o,
    output wire                         branch_jump_o,
    output wire [INST_ADDR_WIDTH-1:0]   branch_target_o
);
    localparam int QUEUE_COUNT_WIDTH = $clog2(PRODUCER_NUM + 1);

    reg [PRODUCER_NUM-1:0] producer_valid_q;
    // In-order retirement state only. Rename/source readiness never reads
    // this vector; dependency availability lives in RS-local tokens and the
    // generation-qualified Value File.
    reg [PRODUCER_NUM-1:0] producer_done_q;
    reg [PRODUCER_NUM-1:0] producer_writes_gpr_q;
    reg [REGS_ADDR_WIDTH-1:0] producer_rd_q [0:PRODUCER_NUM-1];
    // A producer ID is the physical slot plus one generation bit.  The slot
    // is implicit when indexing this table, so only store the generation bit
    // rather than replicating a full tag in every producer entry.
    reg [PRODUCER_NUM-1:0] producer_epoch_q;
    reg [INST_ADDR_WIDTH-1:0] producer_pc_q [0:PRODUCER_NUM-1];
    ydrasil_result_class_t producer_result_class_q [0:PRODUCER_NUM-1];
`ifndef SYNTHESIS
    reg [2:0] producer_op_class_q [0:PRODUCER_NUM-1];
`endif

    reg [REGS_NUM-1:0] latest_valid_q;
    producer_id_t latest_id_q [0:REGS_NUM-1];
    // Keep the completion class beside the RAT tag.  Reading it back through
    // the producer file turns every decode source into two cascaded dynamic
    // selects (architectural register -> producer slot).  This small mirror
    // removes that second select from the decode/issue boundary.
    ydrasil_result_class_t latest_class_q [0:REGS_NUM-1];

    producer_slot_t queue_head_q;
    producer_slot_t queue_tail_q;
    reg [QUEUE_COUNT_WIDTH-1:0] queue_count_q;
    reg serial_pending_q;
	reg branch_retire_due_valid_q;
	producer_id_t branch_retire_due_id_q;

    // Recover the RAT from the surviving producer window rather than storing a
    // 32-entry checkpoint for every unresolved branch. Decode pauses for the
    // short rebuild, while producer/EX flush semantics remain unchanged.
    reg recovering_q;
    producer_slot_t rebuild_ptr_q;
    reg [QUEUE_COUNT_WIDTH-1:0] rebuild_remaining_q;
    localparam int PRODUCER_EXT_WIDTH = PRODUCER_SLOT_WIDTH + 1;
    localparam logic [PRODUCER_EXT_WIDTH-1:0] PRODUCER_NUM_EXT =
        PRODUCER_EXT_WIDTH'(PRODUCER_NUM);

    wire [PRODUCER_EXT_WIDTH-1:0] queue_head1_sum =
        {1'b0, queue_head_q} + PRODUCER_EXT_WIDTH'(1);
    wire producer_slot_t queue_head1 =
        (queue_head1_sum >= PRODUCER_NUM_EXT) ?
        producer_slot_t'(queue_head1_sum - PRODUCER_NUM_EXT) :
        producer_slot_t'(queue_head1_sum);
    wire [PRODUCER_EXT_WIDTH-1:0] queue_head2_sum =
        {1'b0, queue_head_q} + PRODUCER_EXT_WIDTH'(2);
    wire producer_slot_t queue_head2 =
        (queue_head2_sum >= PRODUCER_NUM_EXT) ?
        producer_slot_t'(queue_head2_sum - PRODUCER_NUM_EXT) :
        producer_slot_t'(queue_head2_sum);
	    wire producer_id_t queue_head_id =
	        {producer_epoch_q[queue_head_q], queue_head_q};
	    wire producer_id_t queue_head1_id =
	        {producer_epoch_q[queue_head1], queue_head1};
	    // This due token is already registered in Ctrl and reaches the head in
	    // the BRU resolve window. It is a one-entry retirement credit, not a
	    // global readiness lookup.
	    wire queue_head_branch_due = branch_retire_due_valid_q &&
	        producer_valid_q[queue_head_q] &&
	        (branch_retire_due_id_q == queue_head_id);
			    wire queue_commit0 = (queue_count_q != '0) &&
			        producer_valid_q[queue_head_q] &&
			        (producer_done_q[queue_head_q] || queue_head_branch_due);
			    wire queue_commit1 = queue_commit0 && !ex_branch_jump_i &&
			        (queue_count_q > QUEUE_COUNT_WIDTH'(1)) &&
			        producer_valid_q[queue_head1] &&
			        producer_done_q[queue_head1];
    wire [1:0] queue_commit_count = queue_commit1 ? 2'd2 :
        (queue_commit0 ? 2'd1 : 2'd0);
    wire producer_slot_t queue_head_after_commit =
        queue_commit1 ? queue_head2 :
        (queue_commit0 ? queue_head1 : queue_head_q);

    // Fence completion is an identity match against the producer file.  Make
    // the fixed producer comparisons explicit instead of placing a tag-selected
    // read and a tag-selected write on the same path.
    wire [PRODUCER_NUM-1:0] issue_fence_hit_mask;
    genvar fence_slot_idx;
    generate
        for (fence_slot_idx = 0; fence_slot_idx < PRODUCER_NUM;
             fence_slot_idx++) begin : g_issue_fence_hit
            assign issue_fence_hit_mask[fence_slot_idx] =
                producer_valid_q[fence_slot_idx] &&
                (issue_fence_tag_i[PRODUCER_SLOT_WIDTH-1:0] ==
                 producer_slot_t'(fence_slot_idx)) &&
                (producer_epoch_q[fence_slot_idx] ==
                 issue_fence_tag_i[PRODUCER_ID_WIDTH-1]);
        end
    endgenerate

    ydrasil_commit_pkt_t retire_commit_d;
    ydrasil_commit_pkt_t retire_commit1_d;
    ydrasil_commit_pkt_t retire_commit_q;
    ydrasil_commit_pkt_t retire_commit1_q;
    always_comb begin
        retire_commit_d = '0;
        retire_commit_d.valid = queue_commit0;
        retire_commit_d.producer_id = queue_head_id;
        retire_commit_d.writes_gpr = queue_commit0 &&
        producer_writes_gpr_q[queue_head_q];
        retire_commit_d.rd_addr = producer_rd_q[queue_head_q];
	        retire_commit_d.value = retire_value0_i;
        retire_commit_d.pc = producer_pc_q[queue_head_q];

        retire_commit1_d = '0;
        retire_commit1_d.valid = queue_commit1;
        retire_commit1_d.producer_id = queue_head1_id;
        retire_commit1_d.writes_gpr = queue_commit1 &&
        producer_writes_gpr_q[queue_head1];
        retire_commit1_d.rd_addr = producer_rd_q[queue_head1];
	        retire_commit1_d.value = retire_value1_i;
        retire_commit1_d.pc = producer_pc_q[queue_head1];
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retire_commit_q <= '0;
            retire_commit1_q <= '0;
        end else begin
            retire_commit_q <= retire_commit_d;
            retire_commit1_q <= retire_commit1_d;
        end
    end
    assign retire_commit_o = retire_commit_q;
    assign retire_commit1_o = retire_commit1_q;
    assign retire_valid_o = retire_commit_q.valid;
    assign retire_valid1_o = retire_commit1_q.valid;
    assign retire_value_id0_o = queue_head_id;
    assign retire_value_id1_o = queue_head1_id;

    wire producer_has_one_free = queue_count_q <=
        QUEUE_COUNT_WIDTH'(PRODUCER_NUM - 1);
    wire producer_has_two_free = queue_count_q <=
        QUEUE_COUNT_WIDTH'(PRODUCER_NUM - 2);
    // Dispatch credit is a registered-state contract. Branch/trap recovery has
    // priority in the sequential state update, while backend stalls are
    // absorbed by the four-entry Issue queue. Keeping those current-cycle
    // signals out of ready prevents execution feedback from reaching FetchQ.
    assign dispatch_ready_o = producer_has_one_free && !serial_pending_q &&
        !recovering_q;
    assign dispatch_two_ready_o = producer_has_two_free &&
        !serial_pending_q && !recovering_q;
    wire queue_alloc0 = dispatch_accept_i;
    wire queue_alloc1 = dispatch_accept1_i;
    wire [1:0] queue_alloc_count = {1'b0, queue_alloc0} +
        {1'b0, queue_alloc1};
`ifndef SYNTHESIS
    wire producer_full_stall = dispatch_pkt_i.valid && !producer_has_one_free;
`endif
    wire serial_alloc =
        (queue_alloc0 && dispatch_serial_i) ||
        (queue_alloc1 && dispatch_serial1_i);
    wire serial_accept = issue_fence_i || serial_complete_i;

    producer_slot_t alloc_slot0;
    producer_slot_t alloc_slot1;
    producer_id_t producer_alloc_id;
    producer_id_t producer_alloc_id1;
    wire [PRODUCER_EXT_WIDTH-1:0] queue_tail1_sum =
        {1'b0, queue_tail_q} + PRODUCER_EXT_WIDTH'(1);
    always_comb begin
        alloc_slot0 = queue_tail_q;
        alloc_slot1 = (queue_tail1_sum >= PRODUCER_NUM_EXT) ?
            producer_slot_t'(queue_tail1_sum - PRODUCER_NUM_EXT) :
            producer_slot_t'(queue_tail1_sum);
        producer_alloc_id = {
            ~producer_epoch_q[alloc_slot0], alloc_slot0};
        producer_alloc_id1 = {
            ~producer_epoch_q[alloc_slot1], alloc_slot1};
    end

    // Name each RAT read once.  Besides making the tag/class relationship
    // explicit, this gives synthesis one consumer per source instead of
    // duplicating an unpacked-array lookup in the packet assembly below.
	    wire producer_id_t dispatch_src0_latest_id =
	        latest_id_q[decode_src0_i.arch_addr];
	    wire producer_id_t dispatch_src1_latest_id =
	        latest_id_q[decode_src1_i.arch_addr];
	    wire producer_id_t dispatch1_src0_latest_id =
	        latest_id_q[decode_src2_i.arch_addr];
	    wire producer_id_t dispatch1_src1_latest_id =
	        latest_id_q[decode_src3_i.arch_addr];
	    wire ydrasil_result_class_t dispatch_src0_latest_class =
	        latest_class_q[decode_src0_i.arch_addr];
	    wire ydrasil_result_class_t dispatch_src1_latest_class =
	        latest_class_q[decode_src1_i.arch_addr];
	    wire ydrasil_result_class_t dispatch1_src0_latest_class =
	        latest_class_q[decode_src2_i.arch_addr];
	    wire ydrasil_result_class_t dispatch1_src1_latest_class =
	        latest_class_q[decode_src3_i.arch_addr];
    wire ydrasil_result_class_t dispatch_result_class =
        (dispatch_pkt_i.uop_class == UOP_CLASS_LOAD) ? RESULT_LSU :
		(dispatch_pkt_i.uop_class == UOP_CLASS_MUL) ?
        RESULT_MDU : RESULT_ALU;
    wire ydrasil_result_class_t dispatch1_result_class =
        (dispatch_pkt1_i.uop_class == UOP_CLASS_LOAD) ? RESULT_LSU :
		(dispatch_pkt1_i.uop_class == UOP_CLASS_MUL) ?
        RESULT_MDU : RESULT_ALU;
	    wire dispatch1_src0_from_slot0 = decode_src2_i.used &&
	        decode_dst0_writes_i &&
	        (decode_src2_i.arch_addr == decode_dst0_addr_i);
	    wire dispatch1_src1_from_slot0 = decode_src3_i.used &&
	        decode_dst0_writes_i &&
	        (decode_src3_i.arch_addr == decode_dst0_addr_i);

	    wire producer_id_t renamed_src0_tag = dispatch_src0_latest_id;
	    wire producer_id_t renamed_src1_tag = dispatch_src1_latest_id;
	    wire producer_id_t renamed_src2_tag = dispatch1_src0_from_slot0 ?
	        producer_alloc_id : dispatch1_src0_latest_id;
	    wire producer_id_t renamed_src3_tag = dispatch1_src1_from_slot0 ?
	        producer_alloc_id : dispatch1_src1_latest_id;
	    wire renamed_src0_tag_valid = decode_src0_i.used &&
	        (decode_src0_i.arch_addr != '0) &&
	        latest_valid_q[decode_src0_i.arch_addr];
	    wire renamed_src1_tag_valid = decode_src1_i.used &&
	        (decode_src1_i.arch_addr != '0) &&
	        latest_valid_q[decode_src1_i.arch_addr];
	    wire renamed_src2_tag_valid = dispatch1_src0_from_slot0 ||
	        (decode_src2_i.used && (decode_src2_i.arch_addr != '0) &&
	         latest_valid_q[decode_src2_i.arch_addr]);
	    wire renamed_src3_tag_valid = dispatch1_src1_from_slot0 ||
	        (decode_src3_i.used && (decode_src3_i.arch_addr != '0) &&
	         latest_valid_q[decode_src3_i.arch_addr]);
	    // RS readiness crosses the rename boundary as four narrow control bits.
	    // The complete source descriptors carry tags and data metadata only; they
	    // do not participate in the ready-bit write cone inside every RS entry.
	    assign renamed_src0_static_ready_o = !renamed_src0_tag_valid;
	    assign renamed_src1_static_ready_o = !renamed_src1_tag_valid;
	    assign renamed_src2_static_ready_o = !renamed_src2_tag_valid;
	    assign renamed_src3_static_ready_o = !renamed_src3_tag_valid;
	    always_comb begin
	        dispatch_pkt_o = dispatch_pkt_i;
	        dispatch_pkt1_o = dispatch_pkt1_i;

	        renamed_src0_o = decode_src0_i;
	        renamed_src0_o.tag_valid = renamed_src0_tag_valid;
	        renamed_src0_o.producer_tag = renamed_src0_tag;
	        renamed_src0_o.producer_class = dispatch_src0_latest_class;
	        renamed_src0_o.ready = !renamed_src0_tag_valid;
	        renamed_src1_o = decode_src1_i;
	        renamed_src1_o.tag_valid = renamed_src1_tag_valid;
	        renamed_src1_o.producer_tag = renamed_src1_tag;
	        renamed_src1_o.producer_class = dispatch_src1_latest_class;
	        renamed_src1_o.ready = !renamed_src1_tag_valid;
	        renamed_src2_o = decode_src2_i;
	        renamed_src2_o.tag_valid = renamed_src2_tag_valid;
	        renamed_src2_o.producer_tag = renamed_src2_tag;
	        renamed_src2_o.producer_class = dispatch1_src0_from_slot0 ?
	            dispatch_result_class : dispatch1_src0_latest_class;
	        renamed_src2_o.ready = !renamed_src2_tag_valid;
	        renamed_src3_o = decode_src3_i;
	        renamed_src3_o.tag_valid = renamed_src3_tag_valid;
	        renamed_src3_o.producer_tag = renamed_src3_tag;
	        renamed_src3_o.producer_class = dispatch1_src1_from_slot0 ?
	            dispatch_result_class : dispatch1_src1_latest_class;
	        renamed_src3_o.ready = !renamed_src3_tag_valid;

	        dispatch_pkt_o.src0 = renamed_src0_o;
	        dispatch_pkt_o.src1 = renamed_src1_o;
	        dispatch_pkt_o.dst.rob_tag = producer_alloc_id;
	        dispatch_pkt_o.dst.result_class = dispatch_result_class;
	        dispatch_pkt1_o.src0 = renamed_src2_o;
	        dispatch_pkt1_o.src1 = renamed_src3_o;
	        dispatch_pkt1_o.dst.rob_tag = producer_alloc_id1;
        dispatch_pkt1_o.dst.result_class = dispatch1_result_class;
    end

    wire issue_at_rob_head = issue_pkt_i.dst.rob_tag ==
        queue_head_id;
    assign issue_at_rob_head_o = issue_at_rob_head;
    assign rob_head_id_o = queue_head_id;
    wire decode_bubble_stall = trap_stall_i;

    assign ex_accept_valid_o = ex_hzd_i.valid && !ex_branch_jump_i &&
        !ex_mul_stall_i;
    assign ex_accept_valid1_o = ex_hzd1_i.valid && !ex_branch_jump_i &&
        !ex_mul_stall_i;
    // DIV admission is reserved in the P1 RS. A busy divider must not freeze
    // unrelated Operand and lane-A traffic through a global feedback path.
    assign stall_id_o = 1'b0;
    assign bubble_id_o = decode_bubble_stall;
    assign stall_if_o = 1'b0;
    assign branch_jump_o = ex_branch_jump_i;
    assign branch_target_o = ex_branch_target_i;
    assign flush_if_o = ex_branch_jump_i;
    assign flush_id_o = ex_branch_jump_i;
    assign flush_ex_o = ex_branch_jump_i;
    assign pipeline_flush_o = flush_id_o | issue_fence_i;

`ifndef SYNTHESIS
    wire rs1_has_producer = issue_pkt_i.src0.tag_valid;
    wire rs2_has_producer = issue_pkt_i.src1.tag_valid;
    producer_id_t rs1_producer_id;
    producer_id_t rs2_producer_id;
    producer_slot_t rs1_producer_slot;
    producer_slot_t rs2_producer_slot;
    assign rs1_producer_id = issue_pkt_i.src0.producer_tag;
    assign rs2_producer_id = issue_pkt_i.src1.producer_tag;
    assign rs1_producer_slot = rs1_producer_id[PRODUCER_SLOT_WIDTH-1:0];
    assign rs2_producer_slot = rs2_producer_id[PRODUCER_SLOT_WIDTH-1:0];
    localparam logic [2:0] DBG_PRODUCER_ALU = 3'd1;
    localparam logic [2:0] DBG_PRODUCER_LOAD = 3'd2;
    localparam logic [2:0] DBG_PRODUCER_MUL = 3'd3;
    localparam logic [2:0] DBG_PRODUCER_OTHER = 3'd4;
    logic [2:0] dbg_producer_kind_q [0:PRODUCER_NUM-1];
    wire [2:0] dbg_rs1_producer_kind = rs1_has_producer ?
        dbg_producer_kind_q[rs1_producer_slot] : 3'd0;
    wire [2:0] dbg_rs2_producer_kind = rs2_has_producer ?
        dbg_producer_kind_q[rs2_producer_slot] : 3'd0;
    wire rs1_producer_done = producer_done_q[rs1_producer_slot];
    wire rs2_producer_done = producer_done_q[rs2_producer_slot];
    wire producer_alloc_ex = queue_alloc0 && dispatch_pkt_i.dst.writes_gpr;
    wire producer_alloc_ex1 = queue_alloc1 && dispatch_pkt1_i.dst.writes_gpr;
`endif

    // Clear only the two retiring architectural mappings.  The old per-register
    // generate block compared every RAT entry against both commit tags and then
    // fanned a 32-bit mask into every valid bit.  Keep the stale-tag check local
    // to the two actual destination registers; the sequential block below uses
    // these predicates for indexed clears.
    wire [REGS_ADDR_WIDTH-1:0] retire_rd0 = producer_rd_q[queue_head_q];
    wire [REGS_ADDR_WIDTH-1:0] retire_rd1 = producer_rd_q[queue_head1];
    wire latest_retire_match0 = queue_commit0 &&
        producer_writes_gpr_q[queue_head_q] && (retire_rd0 != '0) &&
        latest_valid_q[retire_rd0] &&
        (latest_id_q[retire_rd0] == queue_head_id);
    wire latest_retire_match1 = queue_commit1 &&
        producer_writes_gpr_q[queue_head1] && (retire_rd1 != '0) &&
        latest_valid_q[retire_rd1] &&
        (latest_id_q[retire_rd1] == queue_head1_id);
    assign backend_empty_o = queue_count_q == '0;

	    producer_slot_t completion_slot0;
	    producer_slot_t completion_slot1;
	    producer_slot_t completion_slot2;
	    producer_slot_t completion_slot3;
	    assign completion_slot0 = completion_meta_i[COMPLETION_ALU].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];
	    assign completion_slot1 = completion_meta_i[COMPLETION_LSU].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];
	    assign completion_slot2 = completion_meta_i[COMPLETION_MUL].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];
	    assign completion_slot3 = completion_meta_i[COMPLETION_DUAL_ALU].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];
	    wire completion_write0 = completion_meta_i[COMPLETION_ALU].valid &&
	        completion_meta_i[COMPLETION_ALU].producer_tracked;
	    wire completion_write1 = completion_meta_i[COMPLETION_LSU].valid &&
	        completion_meta_i[COMPLETION_LSU].producer_tracked;
	    wire completion_write2 = completion_meta_i[COMPLETION_MUL].valid &&
	        completion_meta_i[COMPLETION_MUL].producer_tracked;
	    wire completion_write3 = completion_meta_i[COMPLETION_DUAL_ALU].valid &&
	        completion_meta_i[COMPLETION_DUAL_ALU].producer_tracked;
	    // ROB completion is qualified once at the producer boundary.  The
	    // generation check must not be repeated on the retirement read path.
	    wire completion_hit0 = completion_write0 &&
	        producer_valid_q[completion_slot0] &&
	        (producer_epoch_q[completion_slot0] ==
	         completion_meta_i[COMPLETION_ALU].producer_id[PRODUCER_ID_WIDTH-1]);
	    wire completion_hit1 = completion_write1 &&
	        producer_valid_q[completion_slot1] &&
	        (producer_epoch_q[completion_slot1] ==
	         completion_meta_i[COMPLETION_LSU].producer_id[PRODUCER_ID_WIDTH-1]);
	    wire completion_hit2 = completion_write2 &&
	        producer_valid_q[completion_slot2] &&
	        (producer_epoch_q[completion_slot2] ==
	         completion_meta_i[COMPLETION_MUL].producer_id[PRODUCER_ID_WIDTH-1]);
	    wire completion_hit3 = completion_write3 &&
	        producer_valid_q[completion_slot3] &&
	        (producer_epoch_q[completion_slot3] ==
	         completion_meta_i[COMPLETION_DUAL_ALU].producer_id[PRODUCER_ID_WIDTH-1]);
    wire producer_slot_t no_result_slot0 =
        ex_no_result_due0_id_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t no_result_slot1 =
        ex_no_result_due1_id_i[PRODUCER_SLOT_WIDTH-1:0];
    wire no_result_hit0 = ex_no_result_due0_valid_i &&
        producer_valid_q[no_result_slot0] &&
        (producer_epoch_q[no_result_slot0] ==
         ex_no_result_due0_id_i[PRODUCER_ID_WIDTH-1]);
    wire no_result_hit1 = ex_no_result_due1_valid_i &&
        producer_valid_q[no_result_slot1] &&
        (producer_epoch_q[no_result_slot1] ==
         ex_no_result_due1_id_i[PRODUCER_ID_WIDTH-1]);
	    wire producer_slot_t branch_due_slot =
	        branch_retire_due_id_q[PRODUCER_SLOT_WIDTH-1:0];
	    // Operand advertises a branch before BRU resolve becomes visible. Delay
	    // that token by one local cell so ROB done is exposed in the resolve
	    // window, not one retirement edge too early.
	    always_ff @(posedge clk or negedge rst_n) begin
	        if (!rst_n) begin
	            branch_retire_due_valid_q <= 1'b0;
	            branch_retire_due_id_q <= '0;
	        end else if (ex_hzd_i.interrupt_pending || ex_branch_jump_i ||
	                     issue_fence_i) begin
	            branch_retire_due_valid_q <= 1'b0;
	            branch_retire_due_id_q <= '0;
	        end else begin
	            branch_retire_due_valid_q <= ex_branch_due_valid_i;
	            branch_retire_due_id_q <= ex_branch_due_id_i;
	        end
	    end
	    wire branch_due_hit = branch_retire_due_valid_q &&
	        producer_valid_q[branch_due_slot] &&
	        (producer_epoch_q[branch_due_slot] ==
	         branch_retire_due_id_q[PRODUCER_ID_WIDTH-1]);
`ifndef SYNTHESIS
	    wire [PRODUCER_NUM-1:0] producer_complete_mask =
        (completion_hit0 ? (PRODUCER_NUM'(1) << completion_slot0) : '0) |
        (completion_hit1 ? (PRODUCER_NUM'(1) << completion_slot1) : '0) |
        (completion_hit2 ? (PRODUCER_NUM'(1) << completion_slot2) : '0) |
        (completion_hit3 ? (PRODUCER_NUM'(1) << completion_slot3) : '0);
    wire [PRODUCER_NUM-1:0] producer_retire_q =
        (queue_commit0 ? (PRODUCER_NUM'(1) << queue_head_q) : '0) |
        (queue_commit1 ? (PRODUCER_NUM'(1) << queue_head1) : '0);
	    always_ff @(posedge clk) begin
	        if (rst_n) begin
		            if (completion_hit0) begin
                assert (producer_rd_q[completion_slot0] ==
	                        completion_rd_i[COMPLETION_ALU])
                    else $fatal(1, "ALU completion rd/tag mismatch");
            end
	            if (completion_hit1) begin
                assert (producer_rd_q[completion_slot1] ==
	                        completion_rd_i[COMPLETION_LSU])
                    else $fatal(1, "LSU completion rd/tag mismatch");
            end
	            if (completion_hit2) begin
                assert (producer_rd_q[completion_slot2] ==
	                        completion_rd_i[COMPLETION_MUL])
                    else $fatal(1, "MUL completion rd/tag mismatch");
            end
	            if (completion_hit3) begin
                assert (producer_rd_q[completion_slot3] ==
	                        completion_rd_i[COMPLETION_DUAL_ALU])
                    else $fatal(1, "dual completion rd/tag mismatch");
            end
        end
    end
`endif
    wire producer_id_t resolved_branch_tag = ex_branch_producer_id_i;
    wire producer_slot_t resolved_branch_slot =
        resolved_branch_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire resolved_branch_live = ex_branch_resolve_i &&
        producer_valid_q[resolved_branch_slot] &&
        (producer_epoch_q[resolved_branch_slot] ==
         resolved_branch_tag[PRODUCER_ID_WIDTH-1]);
    wire producer_slot_t resolved_fence_slot =
        issue_fence_tag_i[PRODUCER_SLOT_WIDTH-1:0];
	    wire resolved_fence_live = issue_fence_i &&
	        producer_valid_q[resolved_fence_slot] &&
	        (producer_epoch_q[resolved_fence_slot] ==
	         issue_fence_tag_i[PRODUCER_ID_WIDTH-1]);
    wire recovery_event = (ex_branch_jump_i && resolved_branch_live) ||
        resolved_fence_live;
    wire producer_id_t recovery_tag = resolved_fence_live ?
        issue_fence_tag_i : resolved_branch_tag;
    wire producer_slot_t recovery_slot =
        recovery_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire [PRODUCER_EXT_WIDTH-1:0] recovery_next_sum =
        {1'b0, recovery_slot} + PRODUCER_EXT_WIDTH'(1);
    wire producer_slot_t recovery_next =
        (recovery_next_sum >= PRODUCER_NUM_EXT) ?
        producer_slot_t'(recovery_next_sum - PRODUCER_NUM_EXT) :
        producer_slot_t'(recovery_next_sum);
    wire [QUEUE_COUNT_WIDTH-1:0] recovery_count_before_commit =
        (recovery_next == queue_head_q) ?
        QUEUE_COUNT_WIDTH'(PRODUCER_NUM) :
        (recovery_next > queue_head_q) ?
        QUEUE_COUNT_WIDTH'(recovery_next) -
        QUEUE_COUNT_WIDTH'(queue_head_q) :
        QUEUE_COUNT_WIDTH'(PRODUCER_NUM) -
        QUEUE_COUNT_WIDTH'(queue_head_q) +
        QUEUE_COUNT_WIDTH'(recovery_next);
    wire [QUEUE_COUNT_WIDTH-1:0] recovery_count =
        recovery_count_before_commit -
        QUEUE_COUNT_WIDTH'(queue_commit_count);
    wire recovery_window_wrap = queue_head_q > recovery_slot;
    wire [PRODUCER_NUM-1:0] recovery_window_mask;
    wire [PRODUCER_NUM-1:0] recovery_live_mask;

    // Each slot independently checks the circular [head, branch] window.
    // Retiring entries are removed at the leaves, so commit never feeds a
    // distance-to-mask decoder or a barrel rotation on the recovery path.
    genvar recovery_slot_idx;
    generate
        for (recovery_slot_idx = 0; recovery_slot_idx < PRODUCER_NUM;
             recovery_slot_idx++) begin : g_recovery_live_mask
            wire slot_at_or_after_head =
                producer_slot_t'(recovery_slot_idx) >= queue_head_q;
            wire slot_at_or_before_branch;
            if (recovery_slot_idx == 0) begin : g_first_slot
                assign slot_at_or_before_branch = 1'b1;
            end else begin : g_later_slot
                assign slot_at_or_before_branch =
                    producer_slot_t'(recovery_slot_idx) <=
                    recovery_slot;
            end
            wire slot_in_window = recovery_window_wrap ?
                (slot_at_or_after_head || slot_at_or_before_branch) :
                (slot_at_or_after_head && slot_at_or_before_branch);
            wire slot_retires =
                (queue_commit0 &&
                 (queue_head_q == producer_slot_t'(recovery_slot_idx))) ||
                (queue_commit1 &&
                 (queue_head1 == producer_slot_t'(recovery_slot_idx)));
            assign recovery_window_mask[recovery_slot_idx] =
                recovery_event &&
                producer_valid_q[recovery_slot_idx] && slot_in_window;
            assign recovery_live_mask[recovery_slot_idx] =
                recovery_window_mask[recovery_slot_idx] && !slot_retires;
        end
    endgenerate
`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && ex_branch_jump_i && resolved_branch_live) begin
            assert (recovery_count_before_commit >=
                    QUEUE_COUNT_WIDTH'(queue_commit_count))
                else $fatal(1,
                    "branch recovery retirement count underflow");
        end
    end
`endif
    // Rebuild two producer slots per cycle, oldest first. A mapping written
    // by the second (younger) slot intentionally wins for same-register WAW.
    // A producer retiring in this cycle has already reached the ARF and must
    // not be reinserted into the RAT after the normal commit clear logic.
    wire rebuild_do0 = recovering_q;
    wire rebuild_do1 = recovering_q &&
        (rebuild_remaining_q > QUEUE_COUNT_WIDTH'(1));
    wire producer_slot_t rebuild_ptr0 = rebuild_ptr_q;
    wire [PRODUCER_EXT_WIDTH-1:0] rebuild_ptr1_sum =
        {1'b0, rebuild_ptr_q} + PRODUCER_EXT_WIDTH'(1);
    wire [PRODUCER_EXT_WIDTH-1:0] rebuild_ptr2_sum =
        {1'b0, rebuild_ptr_q} + PRODUCER_EXT_WIDTH'(2);
    wire producer_slot_t rebuild_ptr1 =
        (rebuild_ptr1_sum >= PRODUCER_NUM_EXT) ?
        producer_slot_t'(rebuild_ptr1_sum - PRODUCER_NUM_EXT) :
        producer_slot_t'(rebuild_ptr1_sum);
    wire producer_slot_t rebuild_ptr2 =
        (rebuild_ptr2_sum >= PRODUCER_NUM_EXT) ?
        producer_slot_t'(rebuild_ptr2_sum - PRODUCER_NUM_EXT) :
        producer_slot_t'(rebuild_ptr2_sum);
    wire producer_id_t rebuild_id0 =
        {producer_epoch_q[rebuild_ptr0], rebuild_ptr0};
    wire producer_id_t rebuild_id1 =
        {producer_epoch_q[rebuild_ptr1], rebuild_ptr1};
    wire [REGS_ADDR_WIDTH-1:0] rebuild_rd0 = producer_rd_q[rebuild_ptr0];
    wire [REGS_ADDR_WIDTH-1:0] rebuild_rd1 = producer_rd_q[rebuild_ptr1];
    wire rebuild_retiring0 =
        (queue_commit0 && (queue_head_q == rebuild_ptr0)) ||
        (queue_commit1 && (queue_head1 == rebuild_ptr0));
    wire rebuild_retiring1 =
        (queue_commit0 && (queue_head_q == rebuild_ptr1)) ||
        (queue_commit1 && (queue_head1 == rebuild_ptr1));
    wire rebuild_live0 = producer_valid_q[rebuild_ptr0] &&
        producer_writes_gpr_q[rebuild_ptr0] && (rebuild_rd0 != '0) &&
        !rebuild_retiring0;
    wire rebuild_live1 = producer_valid_q[rebuild_ptr1] &&
        producer_writes_gpr_q[rebuild_ptr1] && (rebuild_rd1 != '0) &&
        !rebuild_retiring1;

    integer slot_idx;
    integer reg_idx;
    integer fence_idx;
    wire [PRODUCER_EXT_WIDTH-1:0] queue_tail_alloc_sum =
        {1'b0, queue_tail_q} + PRODUCER_EXT_WIDTH'(queue_alloc_count);
    wire producer_slot_t queue_tail_after_alloc =
        (queue_tail_alloc_sum >= PRODUCER_NUM_EXT) ?
        producer_slot_t'(queue_tail_alloc_sum - PRODUCER_NUM_EXT) :
        producer_slot_t'(queue_tail_alloc_sum);
    always_ff @(posedge clk) begin
        if (!rst_n || ex_hzd_i.interrupt_pending) begin
            producer_valid_q <= '0;
            producer_done_q <= '0;
            producer_writes_gpr_q <= '0;
            producer_epoch_q <= '0;
            latest_valid_q <= '0;
            queue_head_q <= '0;
            queue_tail_q <= '0;
            queue_count_q <= '0;
            serial_pending_q <= 1'b0;
            recovering_q <= 1'b0;
            rebuild_ptr_q <= '0;
            rebuild_remaining_q <= '0;
            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                producer_rd_q[slot_idx] <= '0;
                producer_pc_q[slot_idx] <= '0;
                producer_result_class_q[slot_idx] <= RESULT_NONE;
`ifndef SYNTHESIS
                producer_op_class_q[slot_idx] <= '0;
                dbg_producer_kind_q[slot_idx] <= '0;
`endif
            end
            for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++) begin
                latest_id_q[reg_idx] <= '0;
                latest_class_q[reg_idx] <= RESULT_NONE;
            end
        end else begin
            if (ex_branch_jump_i || serial_accept)
                serial_pending_q <= 1'b0;
            else if (serial_alloc)
                serial_pending_q <= 1'b1;

            if (queue_commit_count != '0)
                queue_head_q <= queue_head_after_commit;
            if (queue_alloc_count != '0)
                queue_tail_q <= queue_tail_after_alloc;
            queue_count_q <= queue_count_q +
                QUEUE_COUNT_WIDTH'(queue_alloc_count) -
                QUEUE_COUNT_WIDTH'(queue_commit_count);

            if (latest_retire_match0)
                latest_valid_q[retire_rd0] <= 1'b0;
            if (latest_retire_match1)
                latest_valid_q[retire_rd1] <= 1'b0;

            if (queue_commit0) begin
                producer_valid_q[queue_head_q] <= 1'b0;
                producer_done_q[queue_head_q] <= 1'b0;
                producer_writes_gpr_q[queue_head_q] <= 1'b0;
            end
            if (queue_commit1) begin
                producer_valid_q[queue_head1] <= 1'b0;
                producer_done_q[queue_head1] <= 1'b0;
                producer_writes_gpr_q[queue_head1] <= 1'b0;
            end

            if (completion_hit0) begin
				producer_done_q[completion_slot0] <= 1'b1;
			end
	            if (completion_hit1) begin
	                producer_done_q[completion_slot1] <= 1'b1;
			end
	            if (completion_hit2) begin
	                producer_done_q[completion_slot2] <= 1'b1;
			end
	            if (completion_hit3) begin
				producer_done_q[completion_slot3] <= 1'b1;
			end

	            if (no_result_hit0)
	                producer_done_q[no_result_slot0] <= 1'b1;
	            if (no_result_hit1)
	                producer_done_q[no_result_slot1] <= 1'b1;
		            if (branch_due_hit && !queue_head_branch_due)
		                producer_done_q[branch_due_slot] <= 1'b1;
            if (ex_branch_resolve_i && resolved_branch_live)
                producer_done_q[resolved_branch_slot] <= 1'b1;
            for (fence_idx = 0; fence_idx < PRODUCER_NUM; fence_idx++) begin
                if (issue_fence_i && issue_fence_hit_mask[fence_idx])
                    producer_done_q[fence_idx] <= 1'b1;
            end

            if (queue_alloc0) begin
                producer_valid_q[alloc_slot0] <= 1'b1;
                producer_done_q[alloc_slot0] <= 1'b0;
                producer_writes_gpr_q[alloc_slot0] <=
                    dispatch_pkt_i.dst.writes_gpr;
                producer_rd_q[alloc_slot0] <= dispatch_pkt_i.dst.rd_addr;
                producer_epoch_q[alloc_slot0] <=
                    ~producer_epoch_q[alloc_slot0];
                producer_pc_q[alloc_slot0] <= dispatch_pkt_i.decode.pc;
                producer_result_class_q[alloc_slot0] <=
                    dispatch_result_class;
                if (dispatch_pkt_i.dst.writes_gpr) begin
                    latest_valid_q[dispatch_pkt_i.dst.rd_addr] <= 1'b1;
                    latest_id_q[dispatch_pkt_i.dst.rd_addr] <= producer_alloc_id;
                    latest_class_q[dispatch_pkt_i.dst.rd_addr] <=
                        dispatch_result_class;
                end
`ifndef SYNTHESIS
                producer_op_class_q[alloc_slot0] <= {
                    dispatch_pkt_i.uop_class == UOP_CLASS_BJP,
                    dispatch_pkt_i.uop_class == UOP_CLASS_STORE,
                    dispatch_pkt_i.uop_class == UOP_CLASS_LOAD};
                if (dispatch_pkt_i.uop_class == UOP_CLASS_LOAD)
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_LOAD;
                else if (dispatch_pkt_i.uop_class == UOP_CLASS_MUL)
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_MUL;
                else if (dispatch_pkt_i.uop_class == UOP_CLASS_ALU)
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_ALU;
                else
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_OTHER;
`endif
            end
            if (queue_alloc1) begin
                producer_valid_q[alloc_slot1] <= 1'b1;
                producer_done_q[alloc_slot1] <= 1'b0;
                producer_writes_gpr_q[alloc_slot1] <=
                    dispatch_pkt1_i.dst.writes_gpr;
                producer_rd_q[alloc_slot1] <= dispatch_pkt1_i.dst.rd_addr;
                producer_epoch_q[alloc_slot1] <=
                    ~producer_epoch_q[alloc_slot1];
                producer_pc_q[alloc_slot1] <= dispatch_pkt1_i.decode.pc;
                producer_result_class_q[alloc_slot1] <=
                    dispatch1_result_class;
                if (dispatch_pkt1_i.dst.writes_gpr) begin
                    latest_valid_q[dispatch_pkt1_i.dst.rd_addr] <= 1'b1;
                    latest_id_q[dispatch_pkt1_i.dst.rd_addr] <= producer_alloc_id1;
                    latest_class_q[dispatch_pkt1_i.dst.rd_addr] <=
                        dispatch1_result_class;
                end
`ifndef SYNTHESIS
                producer_op_class_q[alloc_slot1] <= {
                    dispatch_pkt1_i.uop_class == UOP_CLASS_BJP,
                    dispatch_pkt1_i.uop_class == UOP_CLASS_STORE,
                    dispatch_pkt1_i.uop_class == UOP_CLASS_LOAD};
                if (dispatch_pkt1_i.uop_class == UOP_CLASS_LOAD)
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_LOAD;
                else if (dispatch_pkt1_i.uop_class == UOP_CLASS_MUL)
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_MUL;
                else if (dispatch_pkt1_i.uop_class == UOP_CLASS_ALU)
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_ALU;
                else
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_OTHER;
`endif
            end

            if (recovery_event) begin
                producer_valid_q <= recovery_live_mask;
                queue_head_q <= queue_head_after_commit;
                queue_tail_q <= recovery_next;
                queue_count_q <= recovery_count;
                latest_valid_q <= '0;
                recovering_q <= (recovery_count != '0);
                rebuild_ptr_q <= queue_head_after_commit;
                rebuild_remaining_q <= recovery_count;
            end else if (recovering_q) begin
                if (rebuild_do0 && rebuild_live0) begin
                    latest_valid_q[rebuild_rd0] <= 1'b1;
                    latest_id_q[rebuild_rd0] <= rebuild_id0;
                    latest_class_q[rebuild_rd0] <=
                        producer_result_class_q[rebuild_ptr0];
                end
                if (rebuild_do1 && rebuild_live1) begin
                    latest_valid_q[rebuild_rd1] <= 1'b1;
                    latest_id_q[rebuild_rd1] <= rebuild_id1;
                    latest_class_q[rebuild_rd1] <=
                        producer_result_class_q[rebuild_ptr1];
                end
                if (rebuild_remaining_q <= QUEUE_COUNT_WIDTH'(2)) begin
                    recovering_q <= 1'b0;
                    rebuild_remaining_q <= '0;
                end else begin
                    rebuild_ptr_q <= rebuild_ptr2;
                    rebuild_remaining_q <= rebuild_remaining_q -
                        QUEUE_COUNT_WIDTH'(2);
                end
            end
        end
    end

endmodule
