module ydrasil_rename_rob
import ydrasil_pkg::*;
(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         ex_branch_jump_i,
    input  logic                         ex_branch_resolve_i,
    input  producer_id_t                 ex_branch_producer_id_i,
    input  logic [INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    input  logic [INST_ADDR_WIDTH-1:0]   ex_pc_i,
    input  logic [INST_ADDR_WIDTH-1:0]   ex_pc1_i,
    input  ydrasil_ex_hzd_pkt_t          ex_hzd_i,
    input  ydrasil_ex_hzd_pkt_t          ex_hzd1_i,
    input  ydrasil_issue_pkt_t           dispatch_pkt_i,
    input  ydrasil_issue_pkt_t           dispatch_pkt1_i,
    input  logic                         dispatch_accept_i,
    input  logic                         dispatch_accept1_i,
    input  ydrasil_issue_pkt_t           issue_pkt_i,
    input  ydrasil_issue_pkt_t           issue_pkt1_i,
    input  logic                         issue_fence_i,
    input  producer_id_t                 issue_fence_tag_i,
    input  logic                         issue_sys_i,
    input  logic                         issue_sys_complete_i,
    input  producer_id_t                 issue_sys_tag_i,
    input  ydrasil_completion_bus_t      completion_bus_i,
    input  logic                         trap_stall_i,
    input  logic                         ex_mul_stall_i,
    input  logic                         wb_backpressure_i,
    input  logic                         rf_wen_rd_i,
    input  logic [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd_i,
    input  logic [REGS_DATA_WIDTH-1:0]   rf_wdata_rd_i,
    input  producer_id_t                 rf_producer_id_i,
    input  logic                         rf_producer_tracked_i,
    input  logic                         rf_wen_rd1_i,
    input  logic [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd1_i,
    input  logic [REGS_DATA_WIDTH-1:0]   rf_wdata_rd1_i,
    input  producer_id_t                 rf_producer_id1_i,
    input  logic                         rf_producer_tracked1_i,

    output ydrasil_issue_pkt_t           dispatch_pkt_o,
    output ydrasil_issue_pkt_t           dispatch_pkt1_o,
    output logic                         dispatch_ready_o,
    output logic                         dispatch_two_ready_o,
    output ydrasil_rob_source_state_t    issue_src0_state_o,
    output ydrasil_rob_source_state_t    issue_src1_state_o,
    output ydrasil_rob_source_state_t    issue_src2_state_o,
    output ydrasil_rob_source_state_t    issue_src3_state_o,
    output ydrasil_rob_source_state_t    dispatch_src0_state_o,
    output ydrasil_rob_source_state_t    dispatch_src1_state_o,
    output ydrasil_rob_source_state_t    dispatch_src2_state_o,
    output ydrasil_rob_source_state_t    dispatch_src3_state_o,
    output logic                         issue_at_rob_head_o,
    output producer_id_t                 rob_head_tag_o,
    output logic [REGS_NUM-1:0]          gpr_pending_o,
    output logic                         ex_accept_valid_o,
    output logic                         ex_accept_valid1_o,
    output logic                         rf_write_commit_o,
    output logic [REGS_NUM-1:0]          rf_write_wen_o,
    output logic                         rf_write_commit1_o,
    output logic [REGS_NUM-1:0]          rf_write_wen1_o,
    output ydrasil_commit_pkt_t          retire_commit_o,
    output ydrasil_commit_pkt_t          retire_commit1_o,
    output logic                         stall_if_o,
    output logic                         stall_id_o,
    output logic                         stall_pc_o,
    output logic                         bubble_id_o,
    output logic                         flush_if_o,
    output logic                         flush_id_o,
    output logic                         flush_ex_o,
    output logic                         branch_jump_o,
    output logic [INST_ADDR_WIDTH-1:0]   branch_target_o,
    output logic [PRODUCER_NUM-1:0]      branch_recovery_keep_mask_o,
    output logic [PRODUCER_NUM-1:0]      branch_recovery_keep_epoch_o,
    // The producer directory is intentionally independent of the one-cycle
    // recovery result. Delayed execution and writeback use this directory to
    // reject a squashed tag after the redirect cycle has passed.
    output logic [PRODUCER_NUM-1:0]      producer_live_mask_o,
    output logic [PRODUCER_NUM-1:0]      producer_live_epoch_o
);
    localparam int COUNT_WIDTH = $clog2(PRODUCER_NUM + 1);

    // ROB control is kept in flops.  Payload arrays deliberately have no reset
    // and are observed only when the corresponding valid bit and epoch match.
    logic [PRODUCER_NUM-1:0] producer_valid_q;
    logic [PRODUCER_NUM-1:0] producer_ready_q;
    logic [PRODUCER_NUM-1:0] producer_value_ready_q;
    logic [PRODUCER_NUM-1:0] producer_writes_gpr_q;
    logic [REGS_ADDR_WIDTH-1:0] producer_rd_q [0:PRODUCER_NUM-1];
    producer_id_t producer_tag_q [0:PRODUCER_NUM-1];
    logic [INST_ADDR_WIDTH-1:0] producer_pc_q [0:PRODUCER_NUM-1];
    logic [INST_DATA_WIDTH-1:0] producer_instr_q [0:PRODUCER_NUM-1];
    logic [2:0] producer_op_class_q [0:PRODUCER_NUM-1];
    ydrasil_result_class_t producer_result_class_q [0:PRODUCER_NUM-1];
    (* ram_style = "distributed" *)
    logic [REGS_DATA_WIDTH-1:0] producer_value_q [0:PRODUCER_NUM-1];

    logic [REGS_NUM-1:0] latest_valid_q;
    (* ram_style = "distributed" *)
    producer_id_t latest_id_q [0:REGS_NUM-1];
    ydrasil_result_class_t latest_class_q [0:REGS_NUM-1];

    producer_slot_t queue_head_q;
    producer_slot_t queue_tail_q;
    logic [COUNT_WIDTH-1:0] queue_count_q;
    logic serial_pending_q;
    logic dispatch_credit_q;
    logic dispatch_two_credit_q;

    function automatic producer_slot_t ptr_add(
        input producer_slot_t ptr,
        input logic [PRODUCER_SLOT_WIDTH:0] amount
    );
        logic [PRODUCER_SLOT_WIDTH:0] sum;
        begin
            sum = {1'b0, ptr} + amount;
            ptr_add = (sum >= PRODUCER_NUM) ?
                producer_slot_t'(sum - PRODUCER_NUM) : producer_slot_t'(sum);
        end
    endfunction

    function automatic logic slot_between(
        input producer_slot_t first,
        input producer_slot_t last,
        input producer_slot_t candidate
    );
        begin
            if (first <= last)
                slot_between = candidate >= first && candidate <= last;
            else
                slot_between = candidate >= first || candidate <= last;
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
                producer_tag_q[slot] == src.producer_tag;
        end
    endfunction

    function automatic ydrasil_rob_source_state_t source_state(
        input ydrasil_source_desc_t src
    );
        producer_slot_t slot;
        begin
            source_state = '0;
            slot = src.producer_tag[PRODUCER_SLOT_WIDTH-1:0];
            if (source_live(src)) begin
                source_state.live = 1'b1;
                source_state.done = producer_value_ready_q[slot];
                source_state.result = producer_value_q[slot];
            end
        end
    endfunction

    producer_slot_t queue_head1;
    logic queue_commit0, queue_commit1;
    logic [1:0] queue_commit_count;
    producer_slot_t queue_head_after_commit;
    always_comb begin
        queue_head1 = ptr_add(queue_head_q, 1);
        queue_commit0 = queue_count_q != 0 &&
            producer_valid_q[queue_head_q] && producer_ready_q[queue_head_q];
        queue_commit1 = queue_commit0 && queue_count_q > 1 &&
            producer_valid_q[queue_head1] && producer_ready_q[queue_head1];
        queue_commit_count = {1'b0, queue_commit0} + {1'b0, queue_commit1};
        queue_head_after_commit = ptr_add(queue_head_q, queue_commit_count);
    end

    always_comb begin
        retire_commit_o = '0;
        retire_commit1_o = '0;
        retire_commit_o.valid = queue_commit0;
        retire_commit_o.writes_gpr = queue_commit0 &&
            producer_writes_gpr_q[queue_head_q];
        retire_commit_o.rd_addr = producer_rd_q[queue_head_q];
        retire_commit_o.value = producer_value_q[queue_head_q];
        retire_commit_o.pc = producer_pc_q[queue_head_q];
        retire_commit1_o.valid = queue_commit1;
        retire_commit1_o.writes_gpr = queue_commit1 &&
            producer_writes_gpr_q[queue_head1];
        retire_commit1_o.rd_addr = producer_rd_q[queue_head1];
        retire_commit1_o.value = producer_value_q[queue_head1];
        retire_commit1_o.pc = producer_pc_q[queue_head1];
    end

    logic producer_has_one_free, producer_has_two_free;
    logic producer_single_block, producer_pair_degrade, producer_full_stall;
    logic order_head_wait;
    always_comb begin
        producer_has_one_free = queue_count_q < PRODUCER_NUM;
        producer_has_two_free = queue_count_q <= PRODUCER_NUM - 2;
        // Credits isolate the frontend from retire/complete fanout, but they
        // are intentionally one cycle old.  Capacity is the architectural
        // admission invariant and must still be checked against the current
        // registered occupancy: otherwise a one-slot ROB can accept a pair,
        // letting lane 1 enter the issue window with an unallocated tag.
        dispatch_ready_o = dispatch_credit_q && producer_has_one_free &&
            !serial_pending_q && !trap_stall_i && !ex_branch_jump_i;
        dispatch_two_ready_o = dispatch_two_credit_q && producer_has_two_free &&
            !serial_pending_q && !trap_stall_i && !ex_branch_jump_i;
        producer_single_block = dispatch_pkt_i.valid && !producer_has_one_free;
        producer_pair_degrade = dispatch_pkt_i.valid && dispatch_pkt1_i.valid &&
            producer_has_one_free && !producer_has_two_free;
        producer_full_stall = producer_single_block;
        order_head_wait = queue_count_q != 0 &&
            producer_valid_q[queue_head_q] && !producer_ready_q[queue_head_q];
    end

    logic queue_alloc0, queue_alloc1;
    logic [1:0] queue_alloc_count;
    producer_slot_t alloc_slot0, alloc_slot1;
    producer_id_t producer_alloc_id, producer_alloc_id1;
    always_comb begin
        queue_alloc0 = dispatch_accept_i && dispatch_pkt_i.valid &&
            producer_has_one_free;
        queue_alloc1 = dispatch_accept1_i && dispatch_pkt1_i.valid &&
            queue_alloc0 && producer_has_two_free;
        queue_alloc_count = {1'b0, queue_alloc0} + {1'b0, queue_alloc1};
        alloc_slot0 = queue_tail_q;
        alloc_slot1 = ptr_add(queue_tail_q, 1);
        producer_alloc_id = {
            ~producer_tag_q[alloc_slot0][PRODUCER_ID_WIDTH-1], alloc_slot0};
        producer_alloc_id1 = {
            ~producer_tag_q[alloc_slot1][PRODUCER_ID_WIDTH-1], alloc_slot1};
    end

    logic src00_pending, src01_pending, src10_pending, src11_pending;
    always_comb begin
        dispatch_pkt_o = dispatch_pkt_i;
        dispatch_pkt1_o = dispatch_pkt1_i;

        src00_pending = dispatch_pkt_i.src0.used &&
            dispatch_pkt_i.src0.arch_addr != 0 &&
            latest_valid_q[dispatch_pkt_i.src0.arch_addr];
        src01_pending = dispatch_pkt_i.src1.used &&
            dispatch_pkt_i.src1.arch_addr != 0 &&
            latest_valid_q[dispatch_pkt_i.src1.arch_addr];
        src10_pending = dispatch_pkt1_i.src0.used &&
            dispatch_pkt1_i.src0.arch_addr != 0 &&
            latest_valid_q[dispatch_pkt1_i.src0.arch_addr];
        src11_pending = dispatch_pkt1_i.src1.used &&
            dispatch_pkt1_i.src1.arch_addr != 0 &&
            latest_valid_q[dispatch_pkt1_i.src1.arch_addr];

        dispatch_pkt_o.src0.tag_valid = src00_pending;
        dispatch_pkt_o.src0.producer_tag = src00_pending ?
            latest_id_q[dispatch_pkt_i.src0.arch_addr] : '0;
        dispatch_pkt_o.src0.producer_class = src00_pending ?
            latest_class_q[dispatch_pkt_i.src0.arch_addr] : RESULT_NONE;
        dispatch_pkt_o.src1.tag_valid = src01_pending;
        dispatch_pkt_o.src1.producer_tag = src01_pending ?
            latest_id_q[dispatch_pkt_i.src1.arch_addr] : '0;
        dispatch_pkt_o.src1.producer_class = src01_pending ?
            latest_class_q[dispatch_pkt_i.src1.arch_addr] : RESULT_NONE;
        dispatch_pkt_o.dst.rob_tag = producer_alloc_id;
        dispatch_pkt_o.dst.result_class = result_class_for(dispatch_pkt_i.decode);

        dispatch_pkt1_o.src0.tag_valid = src10_pending;
        dispatch_pkt1_o.src0.producer_tag = src10_pending ?
            latest_id_q[dispatch_pkt1_i.src0.arch_addr] : '0;
        dispatch_pkt1_o.src0.producer_class = src10_pending ?
            latest_class_q[dispatch_pkt1_i.src0.arch_addr] : RESULT_NONE;
        dispatch_pkt1_o.src1.tag_valid = src11_pending;
        dispatch_pkt1_o.src1.producer_tag = src11_pending ?
            latest_id_q[dispatch_pkt1_i.src1.arch_addr] : '0;
        dispatch_pkt1_o.src1.producer_class = src11_pending ?
            latest_class_q[dispatch_pkt1_i.src1.arch_addr] : RESULT_NONE;

        // Slot 1 observes slot 0's rename in the same two-wide transaction.
        if (dispatch_pkt_i.valid && dispatch_pkt_i.dst.writes_gpr &&
            dispatch_pkt_i.dst.rd_addr != 0 && dispatch_pkt1_i.src0.used &&
            dispatch_pkt1_i.src0.arch_addr == dispatch_pkt_i.dst.rd_addr) begin
            dispatch_pkt1_o.src0.tag_valid = 1'b1;
            dispatch_pkt1_o.src0.producer_tag = producer_alloc_id;
            dispatch_pkt1_o.src0.producer_class =
                result_class_for(dispatch_pkt_i.decode);
        end
        if (dispatch_pkt_i.valid && dispatch_pkt_i.dst.writes_gpr &&
            dispatch_pkt_i.dst.rd_addr != 0 && dispatch_pkt1_i.src1.used &&
            dispatch_pkt1_i.src1.arch_addr == dispatch_pkt_i.dst.rd_addr) begin
            dispatch_pkt1_o.src1.tag_valid = 1'b1;
            dispatch_pkt1_o.src1.producer_tag = producer_alloc_id;
            dispatch_pkt1_o.src1.producer_class =
                result_class_for(dispatch_pkt_i.decode);
        end
        dispatch_pkt1_o.dst.rob_tag = producer_alloc_id1;
        dispatch_pkt1_o.dst.result_class = result_class_for(dispatch_pkt1_i.decode);
    end

    always_comb begin
        issue_src0_state_o = source_state(issue_pkt_i.src0);
        issue_src1_state_o = source_state(issue_pkt_i.src1);
        issue_src2_state_o = source_state(issue_pkt1_i.src0);
        issue_src3_state_o = source_state(issue_pkt1_i.src1);
        dispatch_src0_state_o = source_state(dispatch_pkt_o.src0);
        dispatch_src1_state_o = source_state(dispatch_pkt_o.src1);
        dispatch_src2_state_o = source_state(dispatch_pkt1_o.src0);
        dispatch_src3_state_o = source_state(dispatch_pkt1_o.src1);
        rob_head_tag_o = producer_tag_q[queue_head_q];
        issue_at_rob_head_o = queue_count_q != 0 &&
            issue_pkt_i.dst.rob_tag == rob_head_tag_o;
        gpr_pending_o = latest_valid_q;
    end

    always_comb begin
        // A redirect is not a whole-pipeline kill in an OoO backend.  Work
        // issued before an older branch resolved can itself be older than the
        // branch, so it must be allowed to complete when the recovery mask
        // retains its ROB slot.
        ex_accept_valid_o = ex_hzd_i.valid && !ex_mul_stall_i &&
            (!ex_branch_jump_i ||
             (ex_hzd_i.producer_tracked &&
              recovery_live_mask[ex_hzd_i.producer_id[
                  PRODUCER_SLOT_WIDTH-1:0]] &&
              recovery_live_epoch[ex_hzd_i.producer_id[
                  PRODUCER_SLOT_WIDTH-1:0]] ==
                  ex_hzd_i.producer_id[PRODUCER_ID_WIDTH-1]));
        ex_accept_valid1_o = ex_hzd1_i.valid && !ex_mul_stall_i &&
            (!ex_branch_jump_i ||
             (ex_hzd1_i.producer_tracked &&
              recovery_live_mask[ex_hzd1_i.producer_id[
                  PRODUCER_SLOT_WIDTH-1:0]] &&
              recovery_live_epoch[ex_hzd1_i.producer_id[
                  PRODUCER_SLOT_WIDTH-1:0]] ==
                  ex_hzd1_i.producer_id[PRODUCER_ID_WIDTH-1]));
        stall_if_o = 1'b0;
        stall_pc_o = 1'b0;
        stall_id_o = ex_mul_stall_i;
        bubble_id_o = trap_stall_i || wb_backpressure_i;
        branch_jump_o = ex_branch_jump_i;
        branch_target_o = ex_branch_target_i;
        flush_if_o = ex_branch_jump_i;
        flush_id_o = ex_branch_jump_i;
        flush_ex_o = ex_branch_jump_i;
        rf_write_commit_o = 1'b1;
        rf_write_commit1_o = 1'b1;
        rf_write_wen_o = rf_wen_rd_i ?
            (REGS_NUM'(1) << rf_waddr_rd_i) : '0;
        rf_write_wen1_o = rf_wen_rd1_i ?
            (REGS_NUM'(1) << rf_waddr_rd1_i) : '0;
    end

    producer_id_t resolved_branch_tag;
    producer_slot_t resolved_branch_slot;
    logic resolved_branch_live;
    always_comb begin
        resolved_branch_tag = ex_branch_producer_id_i;
        resolved_branch_slot =
            resolved_branch_tag[PRODUCER_SLOT_WIDTH-1:0];
        resolved_branch_live = ex_branch_resolve_i &&
            producer_valid_q[resolved_branch_slot] &&
            producer_tag_q[resolved_branch_slot] == resolved_branch_tag;
    end

    logic [PRODUCER_NUM-1:0] recovery_live_mask;
    logic [PRODUCER_NUM-1:0] recovery_live_epoch;
    logic [PRODUCER_NUM-1:0] producer_live_epoch;
    logic [REGS_NUM-1:0] recovery_rat_valid;
    producer_id_t recovery_rat_id [0:REGS_NUM-1];
    ydrasil_result_class_t recovery_rat_class [0:REGS_NUM-1];
    logic [COUNT_WIDTH-1:0] recovery_count;
    producer_slot_t recovery_tail;
    integer recovery_slot_i, recovery_reg_i, recovery_offset_i;
    producer_slot_t recovery_scan_slot;
    always_comb begin
        recovery_live_mask = '0;
        recovery_live_epoch = '0;
        producer_live_epoch = '0;
        recovery_rat_valid = '0;
        recovery_count = '0;
        recovery_tail = ptr_add(resolved_branch_slot, 1);
        for (recovery_reg_i = 0; recovery_reg_i < REGS_NUM;
             recovery_reg_i = recovery_reg_i + 1) begin
            recovery_rat_id[recovery_reg_i] = '0;
            recovery_rat_class[recovery_reg_i] = RESULT_NONE;
        end
        for (recovery_slot_i = 0; recovery_slot_i < PRODUCER_NUM;
             recovery_slot_i = recovery_slot_i + 1)
            producer_live_epoch[recovery_slot_i] =
                producer_tag_q[recovery_slot_i][PRODUCER_ID_WIDTH-1];

        if (resolved_branch_live) begin
            for (recovery_slot_i = 0; recovery_slot_i < PRODUCER_NUM;
                 recovery_slot_i = recovery_slot_i + 1) begin
                if (producer_valid_q[recovery_slot_i] &&
                    slot_between(queue_head_after_commit, resolved_branch_slot,
                        producer_slot_t'(recovery_slot_i))) begin
                    recovery_live_mask[recovery_slot_i] = 1'b1;
                    recovery_live_epoch[recovery_slot_i] =
                        producer_tag_q[recovery_slot_i][PRODUCER_ID_WIDTH-1];
                    recovery_count = recovery_count + 1'b1;
                end
            end

            // Rebuild in program order.  Later surviving writers overwrite
            // earlier mappings for the same architectural register.
            for (recovery_offset_i = 0; recovery_offset_i < PRODUCER_NUM;
                 recovery_offset_i = recovery_offset_i + 1) begin
                recovery_scan_slot = ptr_add(queue_head_after_commit,
                    recovery_offset_i);
                if (recovery_live_mask[recovery_scan_slot] &&
                    producer_writes_gpr_q[recovery_scan_slot] &&
                    producer_rd_q[recovery_scan_slot] != 0) begin
                    recovery_rat_valid[producer_rd_q[recovery_scan_slot]] = 1'b1;
                    recovery_rat_id[producer_rd_q[recovery_scan_slot]] =
                        producer_tag_q[recovery_scan_slot];
                    recovery_rat_class[producer_rd_q[recovery_scan_slot]] =
                        producer_result_class_q[recovery_scan_slot];
                end
            end
        end
    end
    always_comb begin
        producer_live_mask_o = producer_valid_q;
        producer_live_epoch_o = producer_live_epoch;
        branch_recovery_keep_mask_o = '0;
        branch_recovery_keep_epoch_o = '0;
        if (ex_branch_jump_i && resolved_branch_live) begin
            branch_recovery_keep_mask_o = recovery_live_mask;
            branch_recovery_keep_epoch_o = recovery_live_epoch;
        end
    end

    producer_slot_t completion_slot [0:COMPLETION_LANES-1];
    logic [COMPLETION_LANES-1:0] completion_hit;
    logic [PRODUCER_NUM-1:0] producer_complete_mask;
    integer completion_i;
    always_comb begin
        producer_complete_mask = '0;
        for (completion_i = 0; completion_i < COMPLETION_LANES;
             completion_i = completion_i + 1) begin
            completion_slot[completion_i] = completion_bus_i[completion_i]
                .producer_id[PRODUCER_SLOT_WIDTH-1:0];
            completion_hit[completion_i] =
                completion_bus_i[completion_i].valid &&
                completion_bus_i[completion_i].producer_tracked &&
                producer_valid_q[completion_slot[completion_i]] &&
                producer_tag_q[completion_slot[completion_i]] ==
                    completion_bus_i[completion_i].producer_id;
            if (completion_hit[completion_i])
                producer_complete_mask[completion_slot[completion_i]] = 1'b1;
        end
    end

    logic [PRODUCER_NUM-1:0] producer_retire_q;
    always_comb begin
        producer_retire_q = '0;
        if (queue_commit0)
            producer_retire_q[queue_head_q] = 1'b1;
        if (queue_commit1)
            producer_retire_q[queue_head1] = 1'b1;
    end

    // Completion and no-result execution events can coincide with a branch
    // redirect.  Keep their effects in one mask so recovery cannot overwrite
    // an older producer becoming ready on that same edge.
    logic [PRODUCER_NUM-1:0] producer_ready_set_mask;
    producer_slot_t ex_ready_slot, ex_ready_slot1;
    always_comb begin
        producer_ready_set_mask = producer_complete_mask;
        ex_ready_slot = ex_hzd_i.producer_id[PRODUCER_SLOT_WIDTH-1:0];
        ex_ready_slot1 = ex_hzd1_i.producer_id[PRODUCER_SLOT_WIDTH-1:0];
        if (ex_accept_valid_o && ex_hzd_i.producer_tracked &&
            !ex_hzd_i.alu_rf_wen &&
            !ex_hzd_i.operator_type[OPERATOR_TYPE_BJP] &&
            !ex_hzd_i.operator_type[OPERATOR_TYPE_STORE] &&
            producer_valid_q[ex_ready_slot] &&
            producer_tag_q[ex_ready_slot] == ex_hzd_i.producer_id)
            producer_ready_set_mask[ex_ready_slot] = 1'b1;
        if (ex_accept_valid1_o && ex_hzd1_i.producer_tracked &&
            !ex_hzd1_i.alu_rf_wen &&
            !ex_hzd1_i.operator_type[OPERATOR_TYPE_BJP] &&
            !ex_hzd1_i.operator_type[OPERATOR_TYPE_STORE] &&
            producer_valid_q[ex_ready_slot1] &&
            producer_tag_q[ex_ready_slot1] == ex_hzd1_i.producer_id)
            producer_ready_set_mask[ex_ready_slot1] = 1'b1;
        if (resolved_branch_live)
            producer_ready_set_mask[resolved_branch_slot] = 1'b1;
    end

    logic [REGS_NUM-1:0] latest_retire_mask;
    integer latest_reg_i;
    always_comb begin
        latest_retire_mask = '0;
        for (latest_reg_i = 1; latest_reg_i < REGS_NUM;
             latest_reg_i = latest_reg_i + 1) begin
            if (latest_valid_q[latest_reg_i] &&
                ((queue_commit0 && producer_writes_gpr_q[queue_head_q] &&
                  producer_rd_q[queue_head_q] == latest_reg_i &&
                  latest_id_q[latest_reg_i] == producer_tag_q[queue_head_q]) ||
                 (queue_commit1 && producer_writes_gpr_q[queue_head1] &&
                  producer_rd_q[queue_head1] == latest_reg_i &&
                  latest_id_q[latest_reg_i] == producer_tag_q[queue_head1])))
                latest_retire_mask[latest_reg_i] = 1'b1;
        end
    end

    logic serial_alloc, serial_accept;
    always_comb begin
        serial_alloc = (queue_alloc0 && dispatch_pkt_i.ctrl.serialize_before) ||
            (queue_alloc1 && dispatch_pkt1_i.ctrl.serialize_before);
        serial_accept = issue_fence_i || issue_sys_i || issue_sys_complete_i ||
            (ex_accept_valid_o &&
             ex_hzd_i.operator_type[OPERATOR_TYPE_CSR] &&
             !ex_hzd_i.operator_type[OPERATOR_TYPE_SYS]);
    end

    integer slot_i, rat_i;
    always_ff @(posedge clk) begin
        if (!rst_n || ex_hzd_i.interrupt || ex_hzd1_i.interrupt) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            producer_value_ready_q <= '0;
            producer_writes_gpr_q <= '0;
            latest_valid_q <= '0;
            queue_head_q <= '0;
            queue_tail_q <= '0;
            queue_count_q <= '0;
            serial_pending_q <= 1'b0;
            dispatch_credit_q <= 1'b1;
            dispatch_two_credit_q <= 1'b1;
            for (slot_i = 0; slot_i < PRODUCER_NUM; slot_i = slot_i + 1)
                producer_tag_q[slot_i] <= producer_id_t'(slot_i);
        end else begin
            // Registered credits terminate the frontend ready path. A one
            // cycle conservative bubble after retirement is intentional;
            // exact capacity is still enforced by the internal alloc gates.
            dispatch_credit_q <= (queue_count_q <= PRODUCER_NUM - 1);
            dispatch_two_credit_q <= (queue_count_q <= PRODUCER_NUM - 2);
            if (ex_branch_jump_i || serial_accept)
                serial_pending_q <= 1'b0;
            else if (serial_alloc)
                serial_pending_q <= 1'b1;

            if (queue_commit_count != 0)
                queue_head_q <= ptr_add(queue_head_q, queue_commit_count);
            if (queue_alloc_count != 0)
                queue_tail_q <= ptr_add(queue_tail_q, queue_alloc_count);
            queue_count_q <= queue_count_q + queue_alloc_count -
                queue_commit_count;

            latest_valid_q <= latest_valid_q & ~latest_retire_mask;
            if (queue_commit0) begin
                producer_valid_q[queue_head_q] <= 1'b0;
                producer_ready_q[queue_head_q] <= 1'b0;
                producer_value_ready_q[queue_head_q] <= 1'b0;
                producer_writes_gpr_q[queue_head_q] <= 1'b0;
            end
            if (queue_commit1) begin
                producer_valid_q[queue_head1] <= 1'b0;
                producer_ready_q[queue_head1] <= 1'b0;
                producer_value_ready_q[queue_head1] <= 1'b0;
                producer_writes_gpr_q[queue_head1] <= 1'b0;
            end

            for (completion_i = 0; completion_i < COMPLETION_LANES;
                 completion_i = completion_i + 1) begin
                if (completion_hit[completion_i]) begin
                    producer_value_q[completion_slot[completion_i]] <=
                        completion_bus_i[completion_i].data;
                    producer_value_ready_q[completion_slot[completion_i]] <= 1'b1;
                    if (!producer_op_class_q[completion_slot[completion_i]][2])
                        producer_ready_q[completion_slot[completion_i]] <= 1'b1;
                end
            end

            producer_ready_q <= producer_ready_q | producer_ready_set_mask;
            if (issue_fence_i &&
                producer_valid_q[issue_fence_tag_i[PRODUCER_SLOT_WIDTH-1:0]] &&
                producer_tag_q[issue_fence_tag_i[PRODUCER_SLOT_WIDTH-1:0]] ==
                    issue_fence_tag_i)
                producer_ready_q[issue_fence_tag_i[
                    PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
            if (issue_sys_complete_i &&
                producer_valid_q[issue_sys_tag_i[PRODUCER_SLOT_WIDTH-1:0]] &&
                producer_tag_q[issue_sys_tag_i[PRODUCER_SLOT_WIDTH-1:0]] ==
                    issue_sys_tag_i)
                producer_ready_q[issue_sys_tag_i[
                    PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;

            if (queue_alloc0) begin
                producer_valid_q[alloc_slot0] <= 1'b1;
                producer_ready_q[alloc_slot0] <= 1'b0;
                producer_value_ready_q[alloc_slot0] <= 1'b0;
                producer_writes_gpr_q[alloc_slot0] <=
                    dispatch_pkt_i.dst.writes_gpr;
                producer_rd_q[alloc_slot0] <= dispatch_pkt_i.dst.rd_addr;
                producer_tag_q[alloc_slot0] <= producer_alloc_id;
                producer_pc_q[alloc_slot0] <= dispatch_pkt_i.decode.pc;
                producer_instr_q[alloc_slot0] <= dispatch_pkt_i.decode.instr;
                producer_op_class_q[alloc_slot0] <= {
                    dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_BJP],
                    dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_STORE],
                    dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_LOAD]};
                producer_result_class_q[alloc_slot0] <=
                    result_class_for(dispatch_pkt_i.decode);
                if (dispatch_pkt_i.dst.writes_gpr &&
                    dispatch_pkt_i.dst.rd_addr != 0) begin
                    latest_valid_q[dispatch_pkt_i.dst.rd_addr] <= 1'b1;
                    latest_id_q[dispatch_pkt_i.dst.rd_addr] <= producer_alloc_id;
                    latest_class_q[dispatch_pkt_i.dst.rd_addr] <=
                        result_class_for(dispatch_pkt_i.decode);
                end
            end
            if (queue_alloc1) begin
                producer_valid_q[alloc_slot1] <= 1'b1;
                producer_ready_q[alloc_slot1] <= 1'b0;
                producer_value_ready_q[alloc_slot1] <= 1'b0;
                producer_writes_gpr_q[alloc_slot1] <=
                    dispatch_pkt1_i.dst.writes_gpr;
                producer_rd_q[alloc_slot1] <= dispatch_pkt1_i.dst.rd_addr;
                producer_tag_q[alloc_slot1] <= producer_alloc_id1;
                producer_pc_q[alloc_slot1] <= dispatch_pkt1_i.decode.pc;
                producer_instr_q[alloc_slot1] <= dispatch_pkt1_i.decode.instr;
                producer_op_class_q[alloc_slot1] <= {
                    dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_BJP],
                    dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_STORE],
                    dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_LOAD]};
                producer_result_class_q[alloc_slot1] <=
                    result_class_for(dispatch_pkt1_i.decode);
                if (dispatch_pkt1_i.dst.writes_gpr &&
                    dispatch_pkt1_i.dst.rd_addr != 0) begin
                    latest_valid_q[dispatch_pkt1_i.dst.rd_addr] <= 1'b1;
                    latest_id_q[dispatch_pkt1_i.dst.rd_addr] <= producer_alloc_id1;
                    latest_class_q[dispatch_pkt1_i.dst.rd_addr] <=
                        result_class_for(dispatch_pkt1_i.decode);
                end
            end

            if (ex_branch_jump_i && resolved_branch_live) begin
                producer_valid_q <= recovery_live_mask;
                // Recovery is a vector write. Preserve every older result
                // that completes at this edge, not only the resolving branch.
                producer_ready_q <= (producer_ready_q |
                    producer_ready_set_mask) & recovery_live_mask;
                producer_value_ready_q <= (producer_value_ready_q |
                    producer_complete_mask) & recovery_live_mask;
                producer_writes_gpr_q <= producer_writes_gpr_q &
                    recovery_live_mask;
                queue_head_q <= queue_head_after_commit;
                queue_tail_q <= recovery_tail;
                queue_count_q <= recovery_count;
                latest_valid_q <= recovery_rat_valid;
                for (rat_i = 0; rat_i < REGS_NUM; rat_i = rat_i + 1) begin
                    latest_id_q[rat_i] <= recovery_rat_id[rat_i];
                    latest_class_q[rat_i] <= recovery_rat_class[rat_i];
                end
                serial_pending_q <= 1'b0;
            end
        end
    end

    logic producer_alloc_ex, producer_alloc_ex1;
    assign producer_alloc_ex = queue_alloc0 && dispatch_pkt_i.dst.writes_gpr;
    assign producer_alloc_ex1 = queue_alloc1 && dispatch_pkt1_i.dst.writes_gpr;

`ifndef SYNTHESIS
    logic rs1_has_producer, rs2_has_producer;
    producer_slot_t rs1_producer_slot, rs2_producer_slot;
    logic rs1_producer_ready, rs2_producer_ready;
    always_comb begin
        rs1_has_producer = issue_pkt_i.src0.tag_valid;
        rs2_has_producer = issue_pkt_i.src1.tag_valid;
        rs1_producer_slot = issue_pkt_i.src0.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0];
        rs2_producer_slot = issue_pkt_i.src1.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0];
        rs1_producer_ready = issue_src0_state_o.done;
        rs2_producer_ready = issue_src1_state_o.done;
    end
`endif

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (!(queue_alloc1 && !queue_alloc0))
                else $fatal(1, "rename lane1 allocation without lane0");
            assert (!(dispatch_accept1_i && dispatch_pkt1_i.valid &&
                      !queue_alloc1))
                else $fatal(1, "rename accepted lane1 without a producer token");
            assert (queue_count_q <= PRODUCER_NUM)
                else $fatal(1, "ROB occupancy overflow");
            if (issue_sys_i)
                assert (!queue_commit0 && !queue_commit1)
                    else $fatal(1, "trap SYSTEM instruction retired");
        end
    end
`endif

    logic unused;
    assign unused = &{1'b0, ex_pc_i, ex_pc1_i, rf_wdata_rd_i,
        rf_producer_id_i, rf_producer_tracked_i, rf_wdata_rd1_i,
        rf_producer_id1_i, rf_producer_tracked1_i, producer_pair_degrade,
        order_head_wait, producer_alloc_ex1, producer_instr_q[0]};
endmodule
