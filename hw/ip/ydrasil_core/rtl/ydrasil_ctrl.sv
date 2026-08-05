module ydrasil_ctrl
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         ex_branch_jump_i,
    input  wire                         ex_branch_resolve_i,
    input  wire [INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    input  wire [INST_ADDR_WIDTH-1:0]   ex_pc_i,
    input  wire [INST_ADDR_WIDTH-1:0]   ex_pc1_i,
    input  ydrasil_ex_hzd_pkt_t         ex_hzd_i,
    input  ydrasil_ex_hzd_pkt_t         ex_hzd1_i,
    input  ydrasil_issue_pkt_t          dispatch_pkt_i,
    input  ydrasil_issue_pkt_t          dispatch_pkt1_i,
    input  wire                         dispatch_accept_i,
    input  wire                         dispatch_accept1_i,
    input  ydrasil_issue_pkt_t          issue_pkt_i,
    input  ydrasil_issue_pkt_t          issue_pkt1_i,
    input  wire                         issue_fence_i,
    input  producer_id_t                issue_fence_tag_i,
    input  ydrasil_completion_bus_t     completion_bus_i,
    input  wire                         trap_stall_i,
    input  wire                         ex_mul_stall_i,

    output ydrasil_issue_pkt_t          dispatch_pkt_o,
    output ydrasil_issue_pkt_t          dispatch_pkt1_o,
    output wire                         dispatch_ready_o,
    output ydrasil_rob_source_state_t   issue_src0_state_o,
    output ydrasil_rob_source_state_t   issue_src1_state_o,
    output ydrasil_rob_source_state_t   issue_src2_state_o,
    output ydrasil_rob_source_state_t   issue_src3_state_o,
    output wire                         issue_at_rob_head_o,
    output wire [REGS_NUM-1:0]          gpr_pending_o,
    output wire                         ex_accept_valid_o,
    output wire                         ex_accept_valid1_o,
    output ydrasil_commit_pkt_t         retire_commit_o,
    output ydrasil_commit_pkt_t         retire_commit1_o,
    output wire                         stall_if_o,
    output wire                         stall_id_o,
    output wire                         bubble_id_o,
    output wire                         flush_if_o,
    output wire                         flush_id_o,
    output wire                         flush_ex_o,
    output wire                         branch_jump_o,
    output wire [INST_ADDR_WIDTH-1:0]   branch_target_o,
    output wire [PRODUCER_NUM-1:0]      branch_recovery_keep_mask_o
);
    localparam int QUEUE_COUNT_WIDTH = $clog2(PRODUCER_NUM + 1);
    localparam int BRANCH_DEPTH = 4;
    localparam int BRANCH_PTR_WIDTH = $clog2(BRANCH_DEPTH);

    reg [PRODUCER_NUM-1:0] producer_valid_q;
    reg [PRODUCER_NUM-1:0] producer_ready_q;
    reg [PRODUCER_NUM-1:0] producer_writes_gpr_q;
    reg [REGS_ADDR_WIDTH-1:0] producer_rd_q [0:PRODUCER_NUM-1];
    // A producer ID is the physical slot plus one generation bit.  The slot
    // is implicit when indexing this table, so only store the generation bit
    // rather than replicating a full tag in every producer entry.
    reg [PRODUCER_NUM-1:0] producer_epoch_q;
    reg [INST_ADDR_WIDTH-1:0] producer_pc_q [0:PRODUCER_NUM-1];
    reg [2:0] producer_op_class_q [0:PRODUCER_NUM-1];
    ydrasil_result_class_t producer_result_class_q [0:PRODUCER_NUM-1];

    // A producer completes through exactly one result class. Keep one result
    // payload per slot; result class remains metadata for typed wakeup only.
    reg [REGS_DATA_WIDTH-1:0] producer_result_q [0:PRODUCER_NUM-1];

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

    producer_id_t branch_tag_q [0:BRANCH_DEPTH-1];
    reg [BRANCH_PTR_WIDTH-1:0] branch_head_q;
    reg [BRANCH_PTR_WIDTH-1:0] branch_tail_q;
    reg [2:0] branch_count_q;

    // Recover the RAT from the surviving producer window rather than storing a
    // 32-entry checkpoint for every unresolved branch. Decode pauses for the
    // short rebuild, while producer/EX flush semantics remain unchanged.
    reg recovering_q;
    producer_slot_t rebuild_ptr_q;
    reg [QUEUE_COUNT_WIDTH-1:0] rebuild_remaining_q;


    function automatic producer_slot_t ptr_add(
        input producer_slot_t ptr,
        input logic [1:0] amount
    );
        localparam int PRODUCER_EXT_WIDTH = PRODUCER_SLOT_WIDTH + 1;
        logic [PRODUCER_EXT_WIDTH-1:0] sum;
        localparam logic [PRODUCER_EXT_WIDTH-1:0] PRODUCER_NUM_EXT =
            PRODUCER_EXT_WIDTH'(PRODUCER_NUM);
        begin
            sum = {1'b0, ptr} +
                {{(PRODUCER_SLOT_WIDTH-1){1'b0}}, amount};
            ptr_add = (sum >= PRODUCER_NUM_EXT) ?
                producer_slot_t'(sum - PRODUCER_NUM_EXT) :
                producer_slot_t'(sum);
        end
    endfunction

    function automatic [QUEUE_COUNT_WIDTH-1:0] queue_distance(
        input producer_slot_t first,
        input producer_slot_t last
    );
        begin
            queue_distance = (last == first) ? QUEUE_COUNT_WIDTH'(PRODUCER_NUM) :
                (last > first) ?
                    QUEUE_COUNT_WIDTH'(last) - QUEUE_COUNT_WIDTH'(first) :
                    QUEUE_COUNT_WIDTH'(PRODUCER_NUM) -
                    QUEUE_COUNT_WIDTH'(first) + QUEUE_COUNT_WIDTH'(last);
        end
    endfunction

    function automatic ydrasil_result_class_t result_class_for(
        input ydrasil_decode_pkt_t pkt
    );
        begin
            if (pkt.operator_type[OPERATOR_TYPE_LOAD])
                result_class_for = RESULT_LSU;
            else if (pkt.operator_type[OPERATOR_TYPE_MUL] ||
                     pkt.operator_type[OPERATOR_TYPE_FPU])
                result_class_for = RESULT_MDU;
            else
                result_class_for = RESULT_ALU;
        end
    endfunction

    function automatic producer_id_t producer_id_for_slot(
        input producer_slot_t slot
    );
        begin
            producer_id_for_slot = {producer_epoch_q[slot], slot};
        end
    endfunction

    function automatic logic source_live(input ydrasil_source_desc_t src);
        producer_slot_t slot;
        begin
            slot = src.producer_tag[PRODUCER_SLOT_WIDTH-1:0];
            source_live = src.tag_valid && producer_valid_q[slot] &&
                (producer_epoch_q[slot] ==
                 src.producer_tag[PRODUCER_ID_WIDTH-1]);
        end
    endfunction

    function automatic ydrasil_rob_source_state_t rob_source_state(
        input ydrasil_source_desc_t src
    );
        producer_slot_t slot;
        begin
            slot = src.producer_tag[PRODUCER_SLOT_WIDTH-1:0];
            rob_source_state = '0;
            rob_source_state.live = source_live(src);
            rob_source_state.done = producer_ready_q[slot];
            rob_source_state.result = producer_result_q[slot];
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] result_for_slot(
        input producer_slot_t slot
    );
        begin
            result_for_slot = producer_result_q[slot];
        end
    endfunction

    wire producer_slot_t queue_head1 = ptr_add(queue_head_q, 2'd1);
    wire queue_commit0 = (queue_count_q != '0) &&
        producer_valid_q[queue_head_q] && producer_ready_q[queue_head_q];
    wire queue_commit1 = queue_commit0 &&
        (queue_count_q > QUEUE_COUNT_WIDTH'(1)) &&
        producer_valid_q[queue_head1] && producer_ready_q[queue_head1];
    wire [1:0] queue_commit_count = {1'b0, queue_commit0} +
        {1'b0, queue_commit1};
    wire producer_slot_t queue_head_after_commit =
        ptr_add(queue_head_q, queue_commit_count);

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

    assign retire_commit_o.valid = queue_commit0;
    assign retire_commit_o.writes_gpr = queue_commit0 &&
        producer_writes_gpr_q[queue_head_q];
    assign retire_commit_o.rd_addr = producer_rd_q[queue_head_q];
    assign retire_commit_o.value = result_for_slot(queue_head_q);
    assign retire_commit_o.pc = producer_pc_q[queue_head_q];
    assign retire_commit1_o.valid = queue_commit1;
    assign retire_commit1_o.writes_gpr = queue_commit1 &&
        producer_writes_gpr_q[queue_head1];
    assign retire_commit1_o.rd_addr = producer_rd_q[queue_head1];
    assign retire_commit1_o.value = result_for_slot(queue_head1);
    assign retire_commit1_o.pc = producer_pc_q[queue_head1];

    wire producer_has_two_free = queue_count_q <=
        QUEUE_COUNT_WIDTH'(PRODUCER_NUM - 2);
    wire branch_has_room = branch_count_q < 3'(BRANCH_DEPTH);
    assign dispatch_ready_o = producer_has_two_free && branch_has_room &&
        !serial_pending_q && !trap_stall_i && !ex_branch_jump_i &&
        !recovering_q;
    wire queue_alloc0 = dispatch_accept_i && dispatch_pkt_i.valid;
    wire queue_alloc1 = dispatch_accept1_i && dispatch_pkt1_i.valid;
    wire [1:0] queue_alloc_count = {1'b0, queue_alloc0} +
        {1'b0, queue_alloc1};
`ifndef SYNTHESIS
    wire producer_full_stall = dispatch_pkt_i.valid && !producer_has_two_free;
`endif
    wire producer_pair_stall = dispatch_pkt1_i.valid && !producer_has_two_free;
    wire serial_alloc = queue_alloc0 &&
        dispatch_pkt_i.ctrl.serialize_before;
    wire serial_accept = issue_fence_i ||
        (ex_accept_valid_o &&
         (ex_hzd_i.operator_type[OPERATOR_TYPE_CSR] &&
          !ex_hzd_i.operator_type[OPERATOR_TYPE_SYS]));

    producer_slot_t alloc_slot0;
    producer_slot_t alloc_slot1;
    producer_id_t producer_alloc_id;
    producer_id_t producer_alloc_id1;
    always_comb begin
        alloc_slot0 = queue_tail_q;
        alloc_slot1 = ptr_add(queue_tail_q, 2'd1);
        producer_alloc_id = {
            ~producer_epoch_q[alloc_slot0], alloc_slot0};
        producer_alloc_id1 = {
            ~producer_epoch_q[alloc_slot1], alloc_slot1};
    end

    // Name each RAT read once.  Besides making the tag/class relationship
    // explicit, this gives synthesis one consumer per source instead of
    // duplicating an unpacked-array lookup in the packet assembly below.
    wire producer_id_t dispatch_src0_latest_id =
        latest_id_q[dispatch_pkt_i.src0.arch_addr];
    wire producer_id_t dispatch_src1_latest_id =
        latest_id_q[dispatch_pkt_i.src1.arch_addr];
    wire producer_id_t dispatch1_src0_latest_id =
        latest_id_q[dispatch_pkt1_i.src0.arch_addr];
    wire producer_id_t dispatch1_src1_latest_id =
        latest_id_q[dispatch_pkt1_i.src1.arch_addr];
    wire ydrasil_result_class_t dispatch_src0_latest_class =
        latest_class_q[dispatch_pkt_i.src0.arch_addr];
    wire ydrasil_result_class_t dispatch_src1_latest_class =
        latest_class_q[dispatch_pkt_i.src1.arch_addr];
    wire ydrasil_result_class_t dispatch1_src0_latest_class =
        latest_class_q[dispatch_pkt1_i.src0.arch_addr];
    wire ydrasil_result_class_t dispatch1_src1_latest_class =
        latest_class_q[dispatch_pkt1_i.src1.arch_addr];

    always_comb begin
        dispatch_pkt_o = dispatch_pkt_i;
        dispatch_pkt1_o = dispatch_pkt1_i;

        dispatch_pkt_o.src0.tag_valid = dispatch_pkt_i.src0.used &&
            (dispatch_pkt_i.src0.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt_i.src0.arch_addr];
        dispatch_pkt_o.src0.producer_tag = dispatch_src0_latest_id;
        dispatch_pkt_o.src0.producer_class = dispatch_src0_latest_class;
        dispatch_pkt_o.src1.tag_valid = dispatch_pkt_i.src1.used &&
            (dispatch_pkt_i.src1.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt_i.src1.arch_addr];
        dispatch_pkt_o.src1.producer_tag = dispatch_src1_latest_id;
        dispatch_pkt_o.src1.producer_class = dispatch_src1_latest_class;
        dispatch_pkt_o.dst.rob_tag = producer_alloc_id;
        dispatch_pkt_o.dst.result_class =
            result_class_for(dispatch_pkt_i.decode);

        dispatch_pkt1_o.src0.tag_valid = dispatch_pkt1_i.src0.used &&
            (dispatch_pkt1_i.src0.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt1_i.src0.arch_addr];
        dispatch_pkt1_o.src0.producer_tag = dispatch1_src0_latest_id;
        dispatch_pkt1_o.src0.producer_class = dispatch1_src0_latest_class;
        dispatch_pkt1_o.src1.tag_valid = dispatch_pkt1_i.src1.used &&
            (dispatch_pkt1_i.src1.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt1_i.src1.arch_addr];
        dispatch_pkt1_o.src1.producer_tag = dispatch1_src1_latest_id;
        dispatch_pkt1_o.src1.producer_class = dispatch1_src1_latest_class;
        dispatch_pkt1_o.dst.rob_tag = producer_alloc_id1;
        dispatch_pkt1_o.dst.result_class =
            result_class_for(dispatch_pkt1_i.decode);
    end

    wire issue_at_rob_head = issue_pkt_i.dst.rob_tag ==
        producer_id_for_slot(queue_head_q);
    assign issue_at_rob_head_o = issue_at_rob_head;
    assign issue_src0_state_o = rob_source_state(issue_pkt_i.src0);
    assign issue_src1_state_o = rob_source_state(issue_pkt_i.src1);
    assign issue_src2_state_o = rob_source_state(issue_pkt1_i.src0);
    assign issue_src3_state_o = rob_source_state(issue_pkt1_i.src1);
    wire decode_bubble_stall = trap_stall_i;

    assign ex_accept_valid_o = ex_hzd_i.valid && !ex_branch_jump_i &&
        !ex_mul_stall_i;
    assign ex_accept_valid1_o = ex_hzd1_i.valid && !ex_branch_jump_i &&
        !ex_mul_stall_i;
    assign stall_id_o = ex_mul_stall_i;
    assign bubble_id_o = decode_bubble_stall;
    assign stall_if_o = 1'b0;
    assign branch_jump_o = ex_branch_jump_i;
    assign branch_target_o = ex_branch_target_i;
    assign flush_if_o = ex_branch_jump_i;
    assign flush_id_o = ex_branch_jump_i;
    assign flush_ex_o = ex_branch_jump_i;

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
    wire rs1_producer_ready = issue_src0_state_o.done;
    wire rs2_producer_ready = issue_src1_state_o.done;
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
        (latest_id_q[retire_rd0] == producer_id_for_slot(queue_head_q));
    wire latest_retire_match1 = queue_commit1 &&
        producer_writes_gpr_q[queue_head1] && (retire_rd1 != '0) &&
        latest_valid_q[retire_rd1] &&
        (latest_id_q[retire_rd1] == producer_id_for_slot(queue_head1));
    assign gpr_pending_o = latest_valid_q;

    producer_slot_t completion_slot0;
    producer_slot_t completion_slot1;
    producer_slot_t completion_slot2;
    producer_slot_t completion_slot3;
    assign completion_slot0 = completion_bus_i[COMPLETION_ALU].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];
    assign completion_slot1 = completion_bus_i[COMPLETION_LSU].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];
    assign completion_slot2 = completion_bus_i[COMPLETION_MUL].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];
    assign completion_slot3 = completion_bus_i[COMPLETION_DUAL_ALU].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];
    wire completion_hit0 = completion_bus_i[COMPLETION_ALU].valid &&
        completion_bus_i[COMPLETION_ALU].producer_tracked &&
        producer_valid_q[completion_slot0] &&
        (producer_rd_q[completion_slot0] ==
         completion_bus_i[COMPLETION_ALU].addr) &&
        (producer_epoch_q[completion_slot0] ==
         completion_bus_i[COMPLETION_ALU].producer_id[PRODUCER_ID_WIDTH-1]);
    wire completion_hit1 = completion_bus_i[COMPLETION_LSU].valid &&
        completion_bus_i[COMPLETION_LSU].producer_tracked &&
        producer_valid_q[completion_slot1] &&
        (producer_rd_q[completion_slot1] ==
         completion_bus_i[COMPLETION_LSU].addr) &&
        (producer_epoch_q[completion_slot1] ==
         completion_bus_i[COMPLETION_LSU].producer_id[PRODUCER_ID_WIDTH-1]);
    wire completion_hit2 = completion_bus_i[COMPLETION_MUL].valid &&
        completion_bus_i[COMPLETION_MUL].producer_tracked &&
        producer_valid_q[completion_slot2] &&
        (producer_rd_q[completion_slot2] ==
         completion_bus_i[COMPLETION_MUL].addr) &&
        (producer_epoch_q[completion_slot2] ==
         completion_bus_i[COMPLETION_MUL].producer_id[PRODUCER_ID_WIDTH-1]);
    wire completion_hit3 = completion_bus_i[COMPLETION_DUAL_ALU].valid &&
        completion_bus_i[COMPLETION_DUAL_ALU].producer_tracked &&
        producer_valid_q[completion_slot3] &&
        (producer_rd_q[completion_slot3] ==
         completion_bus_i[COMPLETION_DUAL_ALU].addr) &&
        (producer_epoch_q[completion_slot3] ==
         completion_bus_i[COMPLETION_DUAL_ALU].producer_id[PRODUCER_ID_WIDTH-1]);
`ifndef SYNTHESIS
    wire [PRODUCER_NUM-1:0] producer_complete_mask =
        (completion_hit0 ? (PRODUCER_NUM'(1) << completion_slot0) : '0) |
        (completion_hit1 ? (PRODUCER_NUM'(1) << completion_slot1) : '0) |
        (completion_hit2 ? (PRODUCER_NUM'(1) << completion_slot2) : '0) |
        (completion_hit3 ? (PRODUCER_NUM'(1) << completion_slot3) : '0);
    wire [PRODUCER_NUM-1:0] producer_retire_q =
        (queue_commit0 ? (PRODUCER_NUM'(1) << queue_head_q) : '0) |
        (queue_commit1 ? (PRODUCER_NUM'(1) << queue_head1) : '0);
`endif
    wire branch_alloc0 = queue_alloc0 && dispatch_pkt_i.ctrl.checkpoint_req;
    wire branch_alloc1 = queue_alloc1 && dispatch_pkt1_i.ctrl.checkpoint_req;
    wire branch_alloc = branch_alloc0 || branch_alloc1;
    wire producer_id_t branch_alloc_tag = branch_alloc0 ?
        producer_alloc_id : producer_alloc_id1;
    wire producer_id_t resolved_branch_tag = branch_tag_q[branch_head_q];
    wire producer_slot_t resolved_branch_slot =
        resolved_branch_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire resolved_branch_live = (branch_count_q != '0) &&
        producer_valid_q[resolved_branch_slot] &&
        (producer_epoch_q[resolved_branch_slot] ==
         resolved_branch_tag[PRODUCER_ID_WIDTH-1]);
    wire producer_slot_t resolved_branch_next =
        ptr_add(resolved_branch_slot, 2'd1);
    wire [QUEUE_COUNT_WIDTH-1:0] recovery_count =
        queue_distance(queue_head_after_commit, resolved_branch_next);
    reg [PRODUCER_NUM-1:0] recovery_live_mask;
    reg [PRODUCER_NUM-1:0] recovery_range_mask;
    reg [PRODUCER_NUM-1:0] recovery_base_mask;
    reg [(2*PRODUCER_NUM)-1:0] recovery_range_doubled;
    // Keep the recovery rotation as a constant-index mux.  The producer-file
    // depth is a build-time knob; separate fixed-width implementations avoid
    // inferring a variable barrel shifter on the branch-recovery path.
    generate
        if (PRODUCER_NUM == 12) begin : g_recovery_mask_12
            always_comb begin
                recovery_base_mask = '0;
                case (recovery_count)
                    4'd1:  recovery_base_mask = 12'h001;
                    4'd2:  recovery_base_mask = 12'h003;
                    4'd3:  recovery_base_mask = 12'h007;
                    4'd4:  recovery_base_mask = 12'h00f;
                    4'd5:  recovery_base_mask = 12'h01f;
                    4'd6:  recovery_base_mask = 12'h03f;
                    4'd7:  recovery_base_mask = 12'h07f;
                    4'd8:  recovery_base_mask = 12'h0ff;
                    4'd9:  recovery_base_mask = 12'h1ff;
                    4'd10: recovery_base_mask = 12'h3ff;
                    4'd11: recovery_base_mask = 12'h7ff;
                    4'd12: recovery_base_mask = 12'hfff;
                    default: recovery_base_mask = '0;
                endcase
                recovery_range_doubled = {recovery_base_mask, recovery_base_mask};
                case (queue_head_after_commit)
                    4'd0:  recovery_range_mask = recovery_range_doubled[12 +: 12];
                    4'd1:  recovery_range_mask = recovery_range_doubled[11 +: 12];
                    4'd2:  recovery_range_mask = recovery_range_doubled[10 +: 12];
                    4'd3:  recovery_range_mask = recovery_range_doubled[9  +: 12];
                    4'd4:  recovery_range_mask = recovery_range_doubled[8  +: 12];
                    4'd5:  recovery_range_mask = recovery_range_doubled[7  +: 12];
                    4'd6:  recovery_range_mask = recovery_range_doubled[6  +: 12];
                    4'd7:  recovery_range_mask = recovery_range_doubled[5  +: 12];
                    4'd8:  recovery_range_mask = recovery_range_doubled[4  +: 12];
                    4'd9:  recovery_range_mask = recovery_range_doubled[3  +: 12];
                    4'd10: recovery_range_mask = recovery_range_doubled[2  +: 12];
                    4'd11: recovery_range_mask = recovery_range_doubled[1  +: 12];
                    default: recovery_range_mask = '0;
                endcase
                recovery_live_mask = resolved_branch_live ?
                    (producer_valid_q & recovery_range_mask) : '0;
            end
        end else if (PRODUCER_NUM == 8) begin : g_recovery_mask_8
            always_comb begin
                recovery_base_mask = '0;
                case (recovery_count)
                    4'd1: recovery_base_mask = 8'h01;
                    4'd2: recovery_base_mask = 8'h03;
                    4'd3: recovery_base_mask = 8'h07;
                    4'd4: recovery_base_mask = 8'h0f;
                    4'd5: recovery_base_mask = 8'h1f;
                    4'd6: recovery_base_mask = 8'h3f;
                    4'd7: recovery_base_mask = 8'h7f;
                    4'd8: recovery_base_mask = 8'hff;
                    default: recovery_base_mask = '0;
                endcase
                recovery_range_doubled = {recovery_base_mask, recovery_base_mask};
                case (queue_head_after_commit)
                    3'd0: recovery_range_mask = recovery_range_doubled[8 +: 8];
                    3'd1: recovery_range_mask = recovery_range_doubled[7 +: 8];
                    3'd2: recovery_range_mask = recovery_range_doubled[6 +: 8];
                    3'd3: recovery_range_mask = recovery_range_doubled[5 +: 8];
                    3'd4: recovery_range_mask = recovery_range_doubled[4 +: 8];
                    3'd5: recovery_range_mask = recovery_range_doubled[3 +: 8];
                    3'd6: recovery_range_mask = recovery_range_doubled[2 +: 8];
                    default: recovery_range_mask = recovery_range_doubled[1 +: 8];
                endcase
                recovery_live_mask = resolved_branch_live ?
                    (producer_valid_q & recovery_range_mask) : '0;
            end
        end else if (PRODUCER_NUM == 6) begin : g_recovery_mask_6
            always_comb begin
                recovery_base_mask = '0;
                case (recovery_count)
                    3'd1: recovery_base_mask = 6'b00_0001;
                    3'd2: recovery_base_mask = 6'b00_0011;
                    3'd3: recovery_base_mask = 6'b00_0111;
                    3'd4: recovery_base_mask = 6'b00_1111;
                    3'd5: recovery_base_mask = 6'b01_1111;
                    3'd6: recovery_base_mask = 6'b11_1111;
                    default: recovery_base_mask = '0;
                endcase
                recovery_range_doubled = {recovery_base_mask, recovery_base_mask};
                case (queue_head_after_commit)
                    3'd0: recovery_range_mask = recovery_range_doubled[6 +: 6];
                    3'd1: recovery_range_mask = recovery_range_doubled[5 +: 6];
                    3'd2: recovery_range_mask = recovery_range_doubled[4 +: 6];
                    3'd3: recovery_range_mask = recovery_range_doubled[3 +: 6];
                    3'd4: recovery_range_mask = recovery_range_doubled[2 +: 6];
                    default: recovery_range_mask = recovery_range_doubled[1 +: 6];
                endcase
                recovery_live_mask = resolved_branch_live ?
                    (producer_valid_q & recovery_range_mask) : '0;
            end
        end else if (PRODUCER_NUM == 4) begin : g_recovery_mask_4
            always_comb begin
                recovery_base_mask = '0;
                case (recovery_count)
                    3'd1: recovery_base_mask = 4'b0001;
                    3'd2: recovery_base_mask = 4'b0011;
                    3'd3: recovery_base_mask = 4'b0111;
                    3'd4: recovery_base_mask = 4'b1111;
                    default: recovery_base_mask = '0;
                endcase
                recovery_range_doubled = {recovery_base_mask, recovery_base_mask};
                case (queue_head_after_commit)
                    2'd0: recovery_range_mask = recovery_range_doubled[4 +: 4];
                    2'd1: recovery_range_mask = recovery_range_doubled[3 +: 4];
                    2'd2: recovery_range_mask = recovery_range_doubled[2 +: 4];
                    default: recovery_range_mask = recovery_range_doubled[1 +: 4];
                endcase
                recovery_live_mask = resolved_branch_live ?
                    (producer_valid_q & recovery_range_mask) : '0;
            end
        end else begin : g_recovery_mask_unsupported
            always_comb begin
                recovery_base_mask = '0;
                recovery_range_doubled = '0;
                recovery_range_mask = '0;
                recovery_live_mask = '0;
            end
        end
    endgenerate
    assign branch_recovery_keep_mask_o = recovery_live_mask;

    // Rebuild two producer slots per cycle, oldest first. A mapping written
    // by the second (younger) slot intentionally wins for same-register WAW.
    // A producer retiring in this cycle has already reached the ARF and must
    // not be reinserted into the RAT after the normal commit clear logic.
    wire rebuild_do0 = recovering_q;
    wire rebuild_do1 = recovering_q &&
        (rebuild_remaining_q > QUEUE_COUNT_WIDTH'(1));
    wire producer_slot_t rebuild_ptr0 = rebuild_ptr_q;
    wire producer_slot_t rebuild_ptr1 = ptr_add(rebuild_ptr_q, 2'd1);
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
    integer branch_idx;
    integer fence_idx;
    always_ff @(posedge clk) begin
        if (!rst_n || ex_hzd_i.interrupt_pending) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            producer_writes_gpr_q <= '0;
            producer_epoch_q <= '0;
            latest_valid_q <= '0;
            queue_head_q <= '0;
            queue_tail_q <= '0;
            queue_count_q <= '0;
            serial_pending_q <= 1'b0;
            branch_head_q <= '0;
            branch_tail_q <= '0;
            branch_count_q <= '0;
            recovering_q <= 1'b0;
            rebuild_ptr_q <= '0;
            rebuild_remaining_q <= '0;
            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                producer_rd_q[slot_idx] <= '0;
                producer_pc_q[slot_idx] <= '0;
                producer_op_class_q[slot_idx] <= '0;
                producer_result_class_q[slot_idx] <= RESULT_NONE;
                producer_result_q[slot_idx] <= '0;
`ifndef SYNTHESIS
                dbg_producer_kind_q[slot_idx] <= '0;
`endif
            end
            for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++) begin
                latest_id_q[reg_idx] <= '0;
                latest_class_q[reg_idx] <= RESULT_NONE;
            end
            for (branch_idx = 0; branch_idx < BRANCH_DEPTH; branch_idx++) begin
                branch_tag_q[branch_idx] <= '0;
            end
        end else begin
            if (ex_branch_jump_i || serial_accept)
                serial_pending_q <= 1'b0;
            else if (serial_alloc)
                serial_pending_q <= 1'b1;

            if (queue_commit_count != '0)
                queue_head_q <= ptr_add(queue_head_q, queue_commit_count);
            if (queue_alloc_count != '0)
                queue_tail_q <= ptr_add(queue_tail_q, queue_alloc_count);
            queue_count_q <= queue_count_q +
                QUEUE_COUNT_WIDTH'(queue_alloc_count) -
                QUEUE_COUNT_WIDTH'(queue_commit_count);

            if (latest_retire_match0)
                latest_valid_q[retire_rd0] <= 1'b0;
            if (latest_retire_match1)
                latest_valid_q[retire_rd1] <= 1'b0;

            if (queue_commit0) begin
                producer_valid_q[queue_head_q] <= 1'b0;
                producer_ready_q[queue_head_q] <= 1'b0;
                producer_writes_gpr_q[queue_head_q] <= 1'b0;
            end
            if (queue_commit1) begin
                producer_valid_q[queue_head1] <= 1'b0;
                producer_ready_q[queue_head1] <= 1'b0;
                producer_writes_gpr_q[queue_head1] <= 1'b0;
            end

            if (completion_hit0) begin
                producer_result_q[completion_slot0] <=
                    completion_bus_i[COMPLETION_ALU].data;
                if (!producer_op_class_q[completion_slot0][2])
                    producer_ready_q[completion_slot0] <= 1'b1;
            end
            if (completion_hit1) begin
                producer_result_q[completion_slot1] <=
                    completion_bus_i[COMPLETION_LSU].data;
                producer_ready_q[completion_slot1] <= 1'b1;
            end
            if (completion_hit2) begin
                producer_result_q[completion_slot2] <=
                    completion_bus_i[COMPLETION_MUL].data;
                producer_ready_q[completion_slot2] <= 1'b1;
            end
            if (completion_hit3) begin
                producer_result_q[completion_slot3] <=
                    completion_bus_i[COMPLETION_DUAL_ALU].data;
                if (!producer_op_class_q[completion_slot3][2])
                    producer_ready_q[completion_slot3] <= 1'b1;
            end

            if (ex_accept_valid_o && ex_hzd_i.producer_tracked &&
                !ex_hzd_i.alu_rf_wen &&
                !ex_hzd_i.operator_type[OPERATOR_TYPE_BJP])
                producer_ready_q[ex_hzd_i.producer_id[
                    PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
            if (ex_accept_valid1_o && ex_hzd1_i.producer_tracked &&
                !ex_hzd1_i.alu_rf_wen &&
                !ex_hzd1_i.operator_type[OPERATOR_TYPE_BJP])
                producer_ready_q[ex_hzd1_i.producer_id[
                    PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
            if (ex_branch_resolve_i && resolved_branch_live)
                producer_ready_q[resolved_branch_slot] <= 1'b1;
            for (fence_idx = 0; fence_idx < PRODUCER_NUM; fence_idx++) begin
                if (issue_fence_i && issue_fence_hit_mask[fence_idx])
                    producer_ready_q[fence_idx] <= 1'b1;
            end

            if (queue_alloc0) begin
                producer_valid_q[alloc_slot0] <= 1'b1;
                producer_ready_q[alloc_slot0] <= 1'b0;
                producer_writes_gpr_q[alloc_slot0] <=
                    dispatch_pkt_i.dst.writes_gpr;
                producer_rd_q[alloc_slot0] <= dispatch_pkt_i.dst.rd_addr;
                producer_epoch_q[alloc_slot0] <=
                    ~producer_epoch_q[alloc_slot0];
                producer_pc_q[alloc_slot0] <= dispatch_pkt_i.decode.pc;
                producer_op_class_q[alloc_slot0] <= {
                    dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_BJP],
                    dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_STORE],
                    dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_LOAD]};
                producer_result_class_q[alloc_slot0] <=
                    result_class_for(dispatch_pkt_i.decode);
                if (dispatch_pkt_i.dst.writes_gpr) begin
                    latest_valid_q[dispatch_pkt_i.dst.rd_addr] <= 1'b1;
                    latest_id_q[dispatch_pkt_i.dst.rd_addr] <= producer_alloc_id;
                    latest_class_q[dispatch_pkt_i.dst.rd_addr] <=
                        result_class_for(dispatch_pkt_i.decode);
                end
`ifndef SYNTHESIS
                if (dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_LOAD])
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_LOAD;
                else if (dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_MUL])
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_MUL;
                else if (dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_ALU])
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_ALU;
                else
                    dbg_producer_kind_q[alloc_slot0] <= DBG_PRODUCER_OTHER;
`endif
            end
            if (queue_alloc1) begin
                producer_valid_q[alloc_slot1] <= 1'b1;
                producer_ready_q[alloc_slot1] <= 1'b0;
                producer_writes_gpr_q[alloc_slot1] <=
                    dispatch_pkt1_i.dst.writes_gpr;
                producer_rd_q[alloc_slot1] <= dispatch_pkt1_i.dst.rd_addr;
                producer_epoch_q[alloc_slot1] <=
                    ~producer_epoch_q[alloc_slot1];
                producer_pc_q[alloc_slot1] <= dispatch_pkt1_i.decode.pc;
                producer_op_class_q[alloc_slot1] <= {
                    dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_BJP],
                    dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_STORE],
                    dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_LOAD]};
                producer_result_class_q[alloc_slot1] <=
                    result_class_for(dispatch_pkt1_i.decode);
                if (dispatch_pkt1_i.dst.writes_gpr) begin
                    latest_valid_q[dispatch_pkt1_i.dst.rd_addr] <= 1'b1;
                    latest_id_q[dispatch_pkt1_i.dst.rd_addr] <= producer_alloc_id1;
                    latest_class_q[dispatch_pkt1_i.dst.rd_addr] <=
                        result_class_for(dispatch_pkt1_i.decode);
                end
`ifndef SYNTHESIS
                if (dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_LOAD])
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_LOAD;
                else if (dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_MUL])
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_MUL;
                else if (dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_ALU])
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_ALU;
                else
                    dbg_producer_kind_q[alloc_slot1] <= DBG_PRODUCER_OTHER;
`endif
            end

            if (branch_alloc) begin
                branch_tag_q[branch_tail_q] <= branch_alloc_tag;
                branch_tail_q <= branch_tail_q + 1'b1;
            end
            if (ex_branch_resolve_i && (branch_count_q != '0))
                branch_head_q <= branch_head_q + 1'b1;
            unique case ({branch_alloc,
                          ex_branch_resolve_i && (branch_count_q != '0)})
                2'b10: branch_count_q <= branch_count_q + 1'b1;
                2'b01: branch_count_q <= branch_count_q - 1'b1;
                default: branch_count_q <= branch_count_q;
            endcase

            if (ex_branch_jump_i && ex_branch_resolve_i &&
                resolved_branch_live) begin
                producer_valid_q <= recovery_live_mask;
                queue_head_q <= queue_head_after_commit;
                queue_tail_q <= resolved_branch_next;
                queue_count_q <= recovery_count;
                latest_valid_q <= '0;
                branch_head_q <= '0;
                branch_tail_q <= '0;
                branch_count_q <= '0;
                recovering_q <= (recovery_count != '0);
                rebuild_ptr_q <= queue_head_after_commit;
                rebuild_remaining_q <= recovery_count;
            end else if (recovering_q) begin
                if (rebuild_do0 && rebuild_live0) begin
                    latest_valid_q[rebuild_rd0] <= 1'b1;
                    latest_id_q[rebuild_rd0] <=
                        producer_id_for_slot(rebuild_ptr0);
                    latest_class_q[rebuild_rd0] <=
                        producer_result_class_q[rebuild_ptr0];
                end
                if (rebuild_do1 && rebuild_live1) begin
                    latest_valid_q[rebuild_rd1] <= 1'b1;
                    latest_id_q[rebuild_rd1] <=
                        producer_id_for_slot(rebuild_ptr1);
                    latest_class_q[rebuild_rd1] <=
                        producer_result_class_q[rebuild_ptr1];
                end
                if (rebuild_remaining_q <= QUEUE_COUNT_WIDTH'(2)) begin
                    recovering_q <= 1'b0;
                    rebuild_remaining_q <= '0;
                end else begin
                    rebuild_ptr_q <= ptr_add(rebuild_ptr_q, 2'd2);
                    rebuild_remaining_q <= rebuild_remaining_q -
                        QUEUE_COUNT_WIDTH'(2);
                end
            end
        end
    end

endmodule
