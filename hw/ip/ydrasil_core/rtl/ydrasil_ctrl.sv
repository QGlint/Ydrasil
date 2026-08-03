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
    input  wire                         wb_backpressure_i,
    input  wire                         rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd_i,
    input  wire [REGS_DATA_WIDTH-1:0]   rf_wdata_rd_i,
    input  producer_id_t                rf_producer_id_i,
    input  wire                         rf_producer_tracked_i,
    input  wire                         rf_wen_rd1_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd1_i,
    input  wire [REGS_DATA_WIDTH-1:0]   rf_wdata_rd1_i,
    input  producer_id_t                rf_producer_id1_i,
    input  wire                         rf_producer_tracked1_i,

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
    output wire                         rf_write_commit_o,
    output wire [REGS_NUM-1:0]          rf_write_wen_o,
    output wire                         rf_write_commit1_o,
    output wire [REGS_NUM-1:0]          rf_write_wen1_o,
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
    producer_id_t producer_tag_q [0:PRODUCER_NUM-1];
    reg [INST_ADDR_WIDTH-1:0] producer_pc_q [0:PRODUCER_NUM-1];
    reg [2:0] producer_op_class_q [0:PRODUCER_NUM-1];
    ydrasil_result_class_t producer_result_class_q [0:PRODUCER_NUM-1];

    reg [REGS_DATA_WIDTH-1:0] alu_result_q [0:PRODUCER_NUM-1];
    reg [REGS_DATA_WIDTH-1:0] lsu_result_q [0:PRODUCER_NUM-1];
    reg [REGS_DATA_WIDTH-1:0] mdu_result_q [0:PRODUCER_NUM-1];

    reg [REGS_NUM-1:0] latest_valid_q;
    producer_id_t latest_id_q [0:REGS_NUM-1];
    ydrasil_result_class_t latest_class_q [0:REGS_NUM-1];

    producer_slot_t queue_head_q;
    producer_slot_t queue_tail_q;
    reg [QUEUE_COUNT_WIDTH-1:0] queue_count_q;
    reg serial_pending_q;

    producer_id_t branch_tag_q [0:BRANCH_DEPTH-1];
    reg [BRANCH_PTR_WIDTH-1:0] branch_head_q;
    reg [BRANCH_PTR_WIDTH-1:0] branch_tail_q;
    reg [2:0] branch_count_q;
    reg [REGS_NUM-1:0] branch_rat_valid_q [0:BRANCH_DEPTH-1];
    producer_id_t branch_rat_id_q [0:BRANCH_DEPTH-1][0:REGS_NUM-1];
    ydrasil_result_class_t branch_rat_class_q [0:BRANCH_DEPTH-1][0:REGS_NUM-1];


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

    function automatic logic source_live(input ydrasil_source_desc_t src);
        producer_slot_t slot;
        begin
            slot = src.producer_tag[PRODUCER_SLOT_WIDTH-1:0];
            source_live = src.tag_valid && producer_valid_q[slot] &&
                (producer_tag_q[slot] == src.producer_tag);
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
            unique case (src.producer_class)
                RESULT_LSU: rob_source_state.result = lsu_result_q[slot];
                RESULT_MDU: rob_source_state.result = mdu_result_q[slot];
                default:    rob_source_state.result = alu_result_q[slot];
            endcase
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] result_for_slot(
        input producer_slot_t slot
    );
        begin
            unique case (producer_result_class_q[slot])
                RESULT_LSU: result_for_slot = lsu_result_q[slot];
                RESULT_MDU: result_for_slot = mdu_result_q[slot];
                default:    result_for_slot = alu_result_q[slot];
            endcase
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
        !serial_pending_q && !trap_stall_i && !ex_branch_jump_i;
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
            ~producer_tag_q[alloc_slot0][PRODUCER_ID_WIDTH-1], alloc_slot0};
        producer_alloc_id1 = {
            ~producer_tag_q[alloc_slot1][PRODUCER_ID_WIDTH-1], alloc_slot1};
    end

    always_comb begin
        dispatch_pkt_o = dispatch_pkt_i;
        dispatch_pkt1_o = dispatch_pkt1_i;

        dispatch_pkt_o.src0.tag_valid = dispatch_pkt_i.src0.used &&
            (dispatch_pkt_i.src0.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt_i.src0.arch_addr];
        dispatch_pkt_o.src0.producer_tag =
            latest_id_q[dispatch_pkt_i.src0.arch_addr];
        dispatch_pkt_o.src0.producer_class =
            latest_class_q[dispatch_pkt_i.src0.arch_addr];
        dispatch_pkt_o.src1.tag_valid = dispatch_pkt_i.src1.used &&
            (dispatch_pkt_i.src1.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt_i.src1.arch_addr];
        dispatch_pkt_o.src1.producer_tag =
            latest_id_q[dispatch_pkt_i.src1.arch_addr];
        dispatch_pkt_o.src1.producer_class =
            latest_class_q[dispatch_pkt_i.src1.arch_addr];
        dispatch_pkt_o.dst.rob_tag = producer_alloc_id;
        dispatch_pkt_o.dst.result_class =
            result_class_for(dispatch_pkt_i.decode);

        dispatch_pkt1_o.src0.tag_valid = dispatch_pkt1_i.src0.used &&
            (dispatch_pkt1_i.src0.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt1_i.src0.arch_addr];
        dispatch_pkt1_o.src0.producer_tag =
            latest_id_q[dispatch_pkt1_i.src0.arch_addr];
        dispatch_pkt1_o.src0.producer_class =
            latest_class_q[dispatch_pkt1_i.src0.arch_addr];
        dispatch_pkt1_o.src1.tag_valid = dispatch_pkt1_i.src1.used &&
            (dispatch_pkt1_i.src1.arch_addr != '0) &&
            latest_valid_q[dispatch_pkt1_i.src1.arch_addr];
        dispatch_pkt1_o.src1.producer_tag =
            latest_id_q[dispatch_pkt1_i.src1.arch_addr];
        dispatch_pkt1_o.src1.producer_class =
            latest_class_q[dispatch_pkt1_i.src1.arch_addr];
        dispatch_pkt1_o.dst.rob_tag = producer_alloc_id1;
        dispatch_pkt1_o.dst.result_class =
            result_class_for(dispatch_pkt1_i.decode);
    end

    wire issue_at_rob_head = issue_pkt_i.dst.rob_tag ==
        producer_tag_q[queue_head_q];
    assign issue_at_rob_head_o = issue_at_rob_head;
    assign issue_src0_state_o = rob_source_state(issue_pkt_i.src0);
    assign issue_src1_state_o = rob_source_state(issue_pkt_i.src1);
    assign issue_src2_state_o = rob_source_state(issue_pkt1_i.src0);
    assign issue_src3_state_o = rob_source_state(issue_pkt1_i.src1);
    wire decode_bubble_stall = trap_stall_i || wb_backpressure_i;

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

    wire [REGS_NUM-1:0] latest_retire_mask;
    genvar retire_reg;
    generate
        for (retire_reg = 0; retire_reg < REGS_NUM; retire_reg++) begin : g_retire_rmt
            assign latest_retire_mask[retire_reg] = latest_valid_q[retire_reg] &&
                ((queue_commit0 && producer_writes_gpr_q[queue_head_q] &&
                  (producer_rd_q[queue_head_q] == REGS_ADDR_WIDTH'(retire_reg)) &&
                  (latest_id_q[retire_reg] == producer_tag_q[queue_head_q])) ||
                 (queue_commit1 && producer_writes_gpr_q[queue_head1] &&
                  (producer_rd_q[queue_head1] == REGS_ADDR_WIDTH'(retire_reg)) &&
                  (latest_id_q[retire_reg] == producer_tag_q[queue_head1])));
        end
    endgenerate

    assign gpr_pending_o = latest_valid_q;
    assign rf_write_commit_o = 1'b1;
    assign rf_write_commit1_o = 1'b1;
    assign rf_write_wen_o = rf_wen_rd_i ?
        (REGS_NUM'(1) << rf_waddr_rd_i) : '0;
    assign rf_write_wen1_o = rf_wen_rd1_i ?
        (REGS_NUM'(1) << rf_waddr_rd1_i) : '0;

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
        (producer_tag_q[completion_slot0] ==
         completion_bus_i[COMPLETION_ALU].producer_id);
    wire completion_hit1 = completion_bus_i[COMPLETION_LSU].valid &&
        completion_bus_i[COMPLETION_LSU].producer_tracked &&
        producer_valid_q[completion_slot1] &&
        (producer_rd_q[completion_slot1] ==
         completion_bus_i[COMPLETION_LSU].addr) &&
        (producer_tag_q[completion_slot1] ==
         completion_bus_i[COMPLETION_LSU].producer_id);
    wire completion_hit2 = completion_bus_i[COMPLETION_MUL].valid &&
        completion_bus_i[COMPLETION_MUL].producer_tracked &&
        producer_valid_q[completion_slot2] &&
        (producer_rd_q[completion_slot2] ==
         completion_bus_i[COMPLETION_MUL].addr) &&
        (producer_tag_q[completion_slot2] ==
         completion_bus_i[COMPLETION_MUL].producer_id);
    wire completion_hit3 = completion_bus_i[COMPLETION_DUAL_ALU].valid &&
        completion_bus_i[COMPLETION_DUAL_ALU].producer_tracked &&
        producer_valid_q[completion_slot3] &&
        (producer_rd_q[completion_slot3] ==
         completion_bus_i[COMPLETION_DUAL_ALU].addr) &&
        (producer_tag_q[completion_slot3] ==
         completion_bus_i[COMPLETION_DUAL_ALU].producer_id);
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
        (producer_tag_q[resolved_branch_slot] == resolved_branch_tag);
    wire producer_slot_t resolved_branch_next =
        ptr_add(resolved_branch_slot, 2'd1);
    wire [QUEUE_COUNT_WIDTH-1:0] recovery_count =
        queue_distance(queue_head_after_commit, resolved_branch_next);
    reg [PRODUCER_NUM-1:0] recovery_live_mask;
    reg [REGS_NUM-1:0] recovery_rat_valid;
    integer recovery_idx;
    integer recovery_reg_idx;
    always_comb begin
        recovery_live_mask = '0;
        for (recovery_idx = 0; recovery_idx < PRODUCER_NUM; recovery_idx++) begin
            if (resolved_branch_live && producer_valid_q[recovery_idx] &&
                ((queue_head_after_commit <= resolved_branch_slot) ?
                 ((producer_slot_t'(recovery_idx) >= queue_head_after_commit) &&
                  (producer_slot_t'(recovery_idx) <= resolved_branch_slot)) :
                 ((producer_slot_t'(recovery_idx) >= queue_head_after_commit) ||
                  (producer_slot_t'(recovery_idx) <= resolved_branch_slot))))
                recovery_live_mask[recovery_idx] = 1'b1;
        end

        // A checkpoint can outlive producers that were older than its branch.
        // Do not resurrect those mappings, or a later slot/epoch reuse can
        // make the stale tag name an unrelated producer.
        recovery_rat_valid = '0;
        for (recovery_reg_idx = 1; recovery_reg_idx < REGS_NUM;
             recovery_reg_idx++) begin
            if (branch_rat_valid_q[branch_head_q][recovery_reg_idx] &&
                recovery_live_mask[branch_rat_id_q[branch_head_q]
                    [recovery_reg_idx][PRODUCER_SLOT_WIDTH-1:0]] &&
                (producer_tag_q[branch_rat_id_q[branch_head_q]
                    [recovery_reg_idx][PRODUCER_SLOT_WIDTH-1:0]] ==
                 branch_rat_id_q[branch_head_q][recovery_reg_idx]))
                recovery_rat_valid[recovery_reg_idx] = 1'b1;
        end
    end
    assign branch_recovery_keep_mask_o = recovery_live_mask;

    integer slot_idx;
    integer reg_idx;
    integer branch_idx;
    integer branch_reg_idx;
    always_ff @(posedge clk) begin
        if (!rst_n || ex_hzd_i.interrupt_pending) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            producer_writes_gpr_q <= '0;
            latest_valid_q <= '0;
            queue_head_q <= '0;
            queue_tail_q <= '0;
            queue_count_q <= '0;
            serial_pending_q <= 1'b0;
            branch_head_q <= '0;
            branch_tail_q <= '0;
            branch_count_q <= '0;
            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                producer_rd_q[slot_idx] <= '0;
                producer_tag_q[slot_idx] <= '0;
                producer_pc_q[slot_idx] <= '0;
                producer_op_class_q[slot_idx] <= '0;
                producer_result_class_q[slot_idx] <= RESULT_NONE;
                alu_result_q[slot_idx] <= '0;
                lsu_result_q[slot_idx] <= '0;
                mdu_result_q[slot_idx] <= '0;
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
                branch_rat_valid_q[branch_idx] <= '0;
                for (branch_reg_idx = 0; branch_reg_idx < REGS_NUM;
                     branch_reg_idx++) begin
                    branch_rat_id_q[branch_idx][branch_reg_idx] <= '0;
                    branch_rat_class_q[branch_idx][branch_reg_idx] <= RESULT_NONE;
                end
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

            for (reg_idx = 1; reg_idx < REGS_NUM; reg_idx++) begin
                if (latest_retire_mask[reg_idx])
                    latest_valid_q[reg_idx] <= 1'b0;
            end

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
                alu_result_q[completion_slot0] <=
                    completion_bus_i[COMPLETION_ALU].data;
                if (!producer_op_class_q[completion_slot0][2])
                    producer_ready_q[completion_slot0] <= 1'b1;
            end
            if (completion_hit1) begin
                lsu_result_q[completion_slot1] <=
                    completion_bus_i[COMPLETION_LSU].data;
                producer_ready_q[completion_slot1] <= 1'b1;
            end
            if (completion_hit2) begin
                mdu_result_q[completion_slot2] <=
                    completion_bus_i[COMPLETION_MUL].data;
                producer_ready_q[completion_slot2] <= 1'b1;
            end
            if (completion_hit3) begin
                alu_result_q[completion_slot3] <=
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
            if (issue_fence_i &&
                producer_valid_q[issue_fence_tag_i[PRODUCER_SLOT_WIDTH-1:0]] &&
                (producer_tag_q[issue_fence_tag_i[PRODUCER_SLOT_WIDTH-1:0]] ==
                 issue_fence_tag_i))
                producer_ready_q[issue_fence_tag_i[PRODUCER_SLOT_WIDTH-1:0]] <=
                    1'b1;

            if (queue_alloc0) begin
                producer_valid_q[alloc_slot0] <= 1'b1;
                producer_ready_q[alloc_slot0] <= 1'b0;
                producer_writes_gpr_q[alloc_slot0] <=
                    dispatch_pkt_i.dst.writes_gpr;
                producer_rd_q[alloc_slot0] <= dispatch_pkt_i.dst.rd_addr;
                producer_tag_q[alloc_slot0] <= producer_alloc_id;
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
                producer_tag_q[alloc_slot1] <= producer_alloc_id1;
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
                branch_rat_valid_q[branch_tail_q] <= latest_valid_q;
                for (branch_reg_idx = 0; branch_reg_idx < REGS_NUM;
                     branch_reg_idx++) begin
                    branch_rat_id_q[branch_tail_q][branch_reg_idx] <=
                        latest_id_q[branch_reg_idx];
                    branch_rat_class_q[branch_tail_q][branch_reg_idx] <=
                        latest_class_q[branch_reg_idx];
                end
                if (queue_alloc0 && dispatch_pkt_i.dst.writes_gpr) begin
                    branch_rat_valid_q[branch_tail_q]
                        [dispatch_pkt_i.dst.rd_addr] <= 1'b1;
                    branch_rat_id_q[branch_tail_q]
                        [dispatch_pkt_i.dst.rd_addr] <= producer_alloc_id;
                    branch_rat_class_q[branch_tail_q]
                        [dispatch_pkt_i.dst.rd_addr] <=
                        result_class_for(dispatch_pkt_i.decode);
                end
                if (branch_alloc1 && dispatch_pkt1_i.dst.writes_gpr) begin
                    branch_rat_valid_q[branch_tail_q]
                        [dispatch_pkt1_i.dst.rd_addr] <= 1'b1;
                    branch_rat_id_q[branch_tail_q]
                        [dispatch_pkt1_i.dst.rd_addr] <= producer_alloc_id1;
                    branch_rat_class_q[branch_tail_q]
                        [dispatch_pkt1_i.dst.rd_addr] <=
                        result_class_for(dispatch_pkt1_i.decode);
                end
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
                latest_valid_q <= recovery_rat_valid;
                for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++) begin
                    latest_id_q[reg_idx] <=
                        branch_rat_id_q[branch_head_q][reg_idx];
                    latest_class_q[reg_idx] <=
                        branch_rat_class_q[branch_head_q][reg_idx];
                end
                branch_head_q <= '0;
                branch_tail_q <= '0;
                branch_count_q <= '0;
            end
        end
    end

endmodule
