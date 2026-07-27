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
    input ydrasil_id_ctrl_pkt_t id_ctrl_i,
    input ydrasil_id_ctrl_pkt_t id_ctrl1_i,
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

    output ydrasil_hzd_status_pkt_t hzd_status_o,
    output ydrasil_hzd_status_pkt_t hzd_status1_o,
    output ydrasil_gpr_fwd_pkt_t wb_fwd_o,
    output ydrasil_gpr_fwd_pkt_t wb_fwd1_o,
    output ydrasil_gpr_fwd_pkt_t producer_rs1_fwd_o,
    output ydrasil_gpr_fwd_pkt_t producer_rs2_fwd_o,
    output ydrasil_gpr_fwd_pkt_t producer_rs3_fwd_o,
    output ydrasil_gpr_fwd_pkt_t producer_rs4_fwd_o,
    output wire [REGS_NUM-1:0] gpr_pending_o,
    output wire ex_accept_valid_o,
    output wire ex_accept_valid1_o,
    output producer_id_t producer_alloc_id_o,
    output wire producer_alloc_tracked_o,
    output producer_id_t producer_alloc_id1_o,
    output wire producer_alloc_tracked1_o,
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

    reg [PRODUCER_NUM-1:0] producer_valid_q;
    reg [PRODUCER_NUM-1:0] producer_ready_q;
    reg [REGS_ADDR_WIDTH-1:0] producer_rd_q [0:PRODUCER_NUM-1];
    (* max_fanout = 8 *) reg [REGS_DATA_WIDTH-1:0] producer_value_q [0:PRODUCER_NUM-1];
    producer_id_t producer_tag_q [0:PRODUCER_NUM-1];
    (* max_fanout = 16 *) reg [REGS_NUM-1:0] latest_valid_q;
    (* max_fanout = 16 *) reg [REGS_NUM-1:0] latest_ready_q;
    (* max_fanout = 16 *) producer_id_t latest_id_q [0:REGS_NUM-1];
    ydrasil_gpr_fwd_pkt_t wb_fwd_q;
    ydrasil_gpr_fwd_pkt_t wb_fwd1_q;

    localparam int ROB_DEPTH = 24;
    localparam int ROB_PTR_WIDTH = $clog2(ROB_DEPTH);
    localparam int ROB_COUNT_WIDTH = $clog2(ROB_DEPTH + 1);
    reg [ROB_DEPTH-1:0] rob_valid_q;
    reg [ROB_DEPTH-1:0] rob_done_q;
    reg [ROB_DEPTH-1:0] rob_writes_gpr_q;
    reg [REGS_ADDR_WIDTH-1:0] rob_rd_addr_q [0:ROB_DEPTH-1];
    producer_id_t rob_ftag_q [0:ROB_DEPTH-1];
    reg [2:0] rob_op_class_q [0:ROB_DEPTH-1];
    reg [2:0] rob_exc_code_q [0:ROB_DEPTH-1];
    reg [INST_ADDR_WIDTH-1:0] rob_pc_q [0:ROB_DEPTH-1];
    reg [ROB_PTR_WIDTH-1:0] rob_head_q;
    reg [ROB_PTR_WIDTH-1:0] rob_tail_q;
    reg [ROB_COUNT_WIDTH-1:0] rob_count_q;

    localparam int CHECKPOINT_DEPTH = 4;
    localparam int CHECKPOINT_PTR_WIDTH = $clog2(CHECKPOINT_DEPTH);
    reg [REGS_NUM-1:0] checkpoint_rat_valid_q [0:CHECKPOINT_DEPTH-1];
    producer_id_t checkpoint_rat_id_q
        [0:CHECKPOINT_DEPTH-1][0:REGS_NUM-1];
    reg [CHECKPOINT_PTR_WIDTH-1:0] checkpoint_head_q;
    reg [CHECKPOINT_PTR_WIDTH-1:0] checkpoint_tail_q;
    reg [2:0] checkpoint_count_q;
    wire [REGS_NUM-1:0] latest_retire_mask;

    function automatic [ROB_PTR_WIDTH-1:0] rob_ptr_add(
        input [ROB_PTR_WIDTH-1:0] ptr,
        input [1:0] amount
    );
        reg [ROB_PTR_WIDTH:0] sum;
        begin
            sum = ptr + amount;
            rob_ptr_add = (sum >= ROB_DEPTH) ? sum - ROB_DEPTH : sum;
        end
    endfunction

    wire [ROB_PTR_WIDTH-1:0] rob_head1 = rob_ptr_add(rob_head_q, 2'd1);
    wire [ROB_PTR_WIDTH-1:0] rob_tail1 = rob_ptr_add(rob_tail_q, 2'd1);
    wire rob_commit0 = (rob_count_q != '0) && rob_valid_q[rob_head_q] &&
        rob_done_q[rob_head_q];
    wire rob_commit1 = rob_commit0 &&
        (rob_count_q > ROB_COUNT_WIDTH'(1)) && rob_valid_q[rob_head1] &&
        rob_done_q[rob_head1];
    wire [1:0] rob_commit_count = {1'b0, rob_commit0} +
        {1'b0, rob_commit1};

    assign retire_commit_o.valid = rob_commit0;
    assign retire_commit_o.writes_gpr = rob_commit0 &&
        rob_writes_gpr_q[rob_head_q];
    assign retire_commit_o.rd_addr = rob_rd_addr_q[rob_head_q];
    assign retire_commit_o.value =
        producer_value_q[rob_ftag_q[rob_head_q][PRODUCER_SLOT_WIDTH-1:0]];
    assign retire_commit_o.pc = rob_pc_q[rob_head_q];
    assign retire_commit1_o.valid = rob_commit1;
    assign retire_commit1_o.writes_gpr = rob_commit1 &&
        rob_writes_gpr_q[rob_head1];
    assign retire_commit1_o.rd_addr = rob_rd_addr_q[rob_head1];
    assign retire_commit1_o.value =
        producer_value_q[rob_ftag_q[rob_head1][PRODUCER_SLOT_WIDTH-1:0]];
    assign retire_commit1_o.pc = rob_pc_q[rob_head1];

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

    wire id_ex_prev_alu_bypassable = ex_accept_valid_o && ex_hzd_i.alu_rf_wen &&
        (ex_hzd_i.rd_addr != '0) && !ex_hzd_i.interrupt && ex_is_alu &&
        !ex_is_bitmanip &&
        (ex_hzd_i.operator_info[OP_ALU_ADD]  |
         ex_hzd_i.operator_info[OP_ALU_SUB]  |
         ex_hzd_i.operator_info[OP_ALU_SLT]  |
         ex_hzd_i.operator_info[OP_ALU_SLTU] |
         ex_hzd_i.operator_info[OP_ALU_XOR]  |
         ex_hzd_i.operator_info[OP_ALU_OR]   |
         ex_hzd_i.operator_info[OP_ALU_AND]  |
         ex_hzd_i.operator_info[OP_ALU_SLL]  |
         ex_hzd_i.operator_info[OP_ALU_SRL]  |
         ex_hzd_i.operator_info[OP_ALU_SRA]  |
         ex_hzd_i.operator_info[OP_ALU_LUI]  |
         ex_hzd_i.operator_info[OP_ALU_AUIPC]);
    wire id_ex_prev_alu_lsu_bypassable = id_ex_prev_alu_bypassable &&
        (ex_hzd_i.operator_info[OP_ALU_ADD]  |
         ex_hzd_i.operator_info[OP_ALU_SUB]  |
         ex_hzd_i.operator_info[OP_ALU_SLT]  |
         ex_hzd_i.operator_info[OP_ALU_SLTU] |
         ex_hzd_i.operator_info[OP_ALU_XOR]  |
         ex_hzd_i.operator_info[OP_ALU_OR]   |
         ex_hzd_i.operator_info[OP_ALU_AND]  |
         ex_hzd_i.operator_info[OP_ALU_LUI]  |
         ex_hzd_i.operator_info[OP_ALU_AUIPC]);
    wire id_ex_prev_alu_consumer_bypassable = id_ctrl_i.lsu_req ?
        id_ex_prev_alu_lsu_bypassable : id_ex_prev_alu_bypassable;
    wire prev_alu_bypass_rs1 = id_ex_prev_alu_consumer_bypassable &&
        id_ctrl_i.prev_alu_bypass_ok && id_ctrl_i.rs1_ren &&
        (id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr);
    wire prev_alu_bypass_rs2 = id_ex_prev_alu_consumer_bypassable &&
        id_ctrl_i.prev_alu_bypass_ok && id_ctrl_i.rs2_ren &&
        (id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr);
    wire [PRODUCER_NUM-1:0] producer_complete_mask;
    wire [REGS_DATA_WIDTH-1:0] producer_completion_data [0:PRODUCER_NUM-1];
    wire [PRODUCER_NUM-1:0] producer_wb_retire_mask;
    wire [PRODUCER_NUM-1:0] producer_wb_retire0_mask;
    wire [PRODUCER_NUM-1:0] producer_wb_retire1_mask;
    wire producer_alloc_ex;
    wire producer_alloc_ex1;
    wire producer_slot_t rf_producer_slot =
        rf_producer_id_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t rf_producer_slot1 =
        rf_producer_id1_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t ex_producer_slot =
        ex_hzd_i.producer_id[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t ex_producer_slot1 =
        ex_hzd1_i.producer_id[PRODUCER_SLOT_WIDTH-1:0];
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
            assign producer_wb_retire0_mask[complete_idx] = rob_commit0 &&
                rob_writes_gpr_q[rob_head_q] &&
                producer_valid_q[complete_idx] &&
                (rob_ftag_q[rob_head_q][PRODUCER_SLOT_WIDTH-1:0] ==
                 producer_slot_t'(complete_idx)) &&
                (producer_tag_q[complete_idx] == rob_ftag_q[rob_head_q]);
            assign producer_wb_retire1_mask[complete_idx] = rob_commit1 &&
                rob_writes_gpr_q[rob_head1] &&
                producer_valid_q[complete_idx] &&
                (rob_ftag_q[rob_head1][PRODUCER_SLOT_WIDTH-1:0] ==
                 producer_slot_t'(complete_idx)) &&
                (producer_tag_q[complete_idx] == rob_ftag_q[rob_head1]);
            assign producer_wb_retire_mask[complete_idx] =
                producer_wb_retire0_mask[complete_idx] |
                producer_wb_retire1_mask[complete_idx];
        end
    endgenerate

    wire [PRODUCER_NUM-1:0] producer_retire_q = producer_wb_retire_mask;
    wire [REGS_NUM-1:0] checkpoint_restore_valid;
    wire [REGS_NUM-1:0] checkpoint_restore_ready;
    genvar checkpoint_restore_idx;
    generate
        for (checkpoint_restore_idx = 0; checkpoint_restore_idx < REGS_NUM;
             checkpoint_restore_idx++) begin : g_checkpoint_restore
            wire producer_id_t restore_id =
                checkpoint_rat_id_q[checkpoint_head_q][checkpoint_restore_idx];
            wire producer_slot_t restore_slot =
                restore_id[PRODUCER_SLOT_WIDTH-1:0];
            // A checkpoint can outlive an older producer that it references.
            // In that case the architectural register file already contains
            // the value, so restoring the stale RAT entry would resurrect an
            // invalid dependency.  Same-cycle retirement is treated as dead.
            wire restore_live =
                checkpoint_rat_valid_q[checkpoint_head_q][checkpoint_restore_idx] &&
                producer_valid_q[restore_slot] &&
                !producer_wb_retire_mask[restore_slot] &&
                (producer_tag_q[restore_slot] == restore_id);

            assign checkpoint_restore_valid[checkpoint_restore_idx] = restore_live;
            assign checkpoint_restore_ready[checkpoint_restore_idx] = restore_live &&
                (producer_ready_q[restore_slot] |
                 producer_complete_mask[restore_slot]);
        end
    endgenerate
    // 退休槽位从下一周期起再参与分配。避免把写回 FIFO、退休匹配、
    // 空闲优先编码和发射允许串成一条组合路径；6 项生产者表可吸收
    // 这一周期的保守复用延迟。
    wire [PRODUCER_NUM-1:0] producer_occupied = producer_valid_q;
    assign producer_alloc_ex = id_ex_rd_issue && ex_hzd_i.producer_tracked;
    assign producer_alloc_ex1 = id_ex1_rd_issue && ex_hzd1_i.producer_tracked;
    wire rob_alloc0 = ex_accept_valid_o &&
        (!ex_hzd_i.producer_tracked ||
         !producer_valid_q[ex_producer_slot] ||
         (producer_tag_q[ex_producer_slot] != ex_hzd_i.producer_id));
    wire rob_alloc1 = ex_accept_valid1_o &&
        (!ex_hzd1_i.producer_tracked ||
         !producer_valid_q[ex_producer_slot1] ||
         (producer_tag_q[ex_producer_slot1] != ex_hzd1_i.producer_id));
    wire [1:0] rob_alloc_count = {1'b0, rob_alloc0} +
        {1'b0, rob_alloc1};
    wire [PRODUCER_NUM-1:0] producer_occupied_after_ex = producer_occupied |
        (producer_alloc_ex ?
         (PRODUCER_NUM'(1) << ex_producer_slot) : '0) |
        (producer_alloc_ex1 ?
         (PRODUCER_NUM'(1) << ex_producer_slot1) : '0);
    wire [PRODUCER_NUM-1:0] producer_free_mask = ~producer_occupied_after_ex;
    wire producer_has_free = |producer_free_mask;
    wire producer_has_two_free = |(producer_free_mask & (producer_free_mask - PRODUCER_NUM'(1)));
    // 槽位 0 是较老指令，只有它自身无法分配生产者时才阻塞整个发射。
    // 槽位 1 缺少第二个槽位时只取消成对发射，不能反向阻塞槽位 0。
    wire producer_full_stall = id_ctrl_i.rd_wen && !producer_has_free;
    wire producer_pair_stall = id_ctrl1_i.rd_wen &&
        ((!id_ctrl_i.rd_wen && !producer_has_free) ||
         (id_ctrl_i.rd_wen && !producer_has_two_free));
    wire [ROB_COUNT_WIDTH-1:0] rob_free_count =
        ROB_COUNT_WIDTH'(ROB_DEPTH) - rob_count_q;
    wire [ROB_COUNT_WIDTH-1:0] rob_free_after_ex = rob_free_count -
        ROB_COUNT_WIDTH'(rob_alloc_count);
    wire rob_full_stall = id_ctrl_i.valid && (rob_free_after_ex == '0);
    wire rob_pair_stall = id_ctrl1_i.valid &&
        (rob_free_after_ex < ROB_COUNT_WIDTH'(2));
    wire checkpoint_full =
        checkpoint_count_q == 3'd4;
    wire checkpoint_full_stall = id_ctrl_i.checkpoint_req &&
        checkpoint_full && !ex_branch_resolve_i;

    reg [PRODUCER_ID_WIDTH-1:0] producer_alloc_id;
    reg [PRODUCER_ID_WIDTH-1:0] producer_alloc_id1;
    reg [PRODUCER_NUM-1:0] producer_alloc_taken;
    integer alloc_idx;
    always_comb begin
        producer_alloc_id = '0;
        producer_alloc_id1 = '0;
        producer_alloc_taken = producer_occupied_after_ex;
        for (alloc_idx = PRODUCER_NUM-1; alloc_idx >= 0; alloc_idx = alloc_idx - 1)
            if (!producer_alloc_taken[alloc_idx])
                producer_alloc_id = {
                    ~producer_tag_q[alloc_idx][PRODUCER_ID_WIDTH-1],
                    producer_slot_t'(alloc_idx)};
        if (id_ctrl_i.rd_wen)
            producer_alloc_taken[producer_alloc_id[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
        for (alloc_idx = PRODUCER_NUM-1; alloc_idx >= 0; alloc_idx = alloc_idx - 1)
            if (!producer_alloc_taken[alloc_idx])
                producer_alloc_id1 = {
                    ~producer_tag_q[alloc_idx][PRODUCER_ID_WIDTH-1],
                    producer_slot_t'(alloc_idx)};
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
    wire [REGS_DATA_WIDTH-1:0] ex_completion_data =
        (completion_bus_i[0].valid && completion_bus_i[0].producer_tracked &&
         (completion_bus_i[0].producer_id == ex_hzd_i.producer_id)) ?
            completion_bus_i[0].data :
        (completion_bus_i[1].valid && completion_bus_i[1].producer_tracked &&
         (completion_bus_i[1].producer_id == ex_hzd_i.producer_id)) ?
            completion_bus_i[1].data :
        (completion_bus_i[2].valid && completion_bus_i[2].producer_tracked &&
         (completion_bus_i[2].producer_id == ex_hzd_i.producer_id)) ?
            completion_bus_i[2].data :
        (completion_bus_i[3].valid && completion_bus_i[3].producer_tracked &&
         (completion_bus_i[3].producer_id == ex_hzd_i.producer_id)) ?
            completion_bus_i[3].data : '0;
    wire [REGS_DATA_WIDTH-1:0] ex1_completion_data =
        (completion_bus_i[0].valid && completion_bus_i[0].producer_tracked &&
         (completion_bus_i[0].producer_id == ex_hzd1_i.producer_id)) ? completion_bus_i[0].data :
        (completion_bus_i[1].valid && completion_bus_i[1].producer_tracked &&
         (completion_bus_i[1].producer_id == ex_hzd1_i.producer_id)) ? completion_bus_i[1].data :
        (completion_bus_i[2].valid && completion_bus_i[2].producer_tracked &&
         (completion_bus_i[2].producer_id == ex_hzd1_i.producer_id)) ? completion_bus_i[2].data :
        (completion_bus_i[3].valid && completion_bus_i[3].producer_tracked &&
         (completion_bus_i[3].producer_id == ex_hzd1_i.producer_id)) ? completion_bus_i[3].data : '0;
    wire ex_completion_hit =
        (completion_bus_i[0].valid && completion_bus_i[0].producer_tracked &&
         (completion_bus_i[0].producer_id == ex_hzd_i.producer_id)) |
        (completion_bus_i[1].valid && completion_bus_i[1].producer_tracked &&
         (completion_bus_i[1].producer_id == ex_hzd_i.producer_id)) |
        (completion_bus_i[2].valid && completion_bus_i[2].producer_tracked &&
         (completion_bus_i[2].producer_id == ex_hzd_i.producer_id)) |
        (completion_bus_i[3].valid && completion_bus_i[3].producer_tracked &&
         (completion_bus_i[3].producer_id == ex_hzd_i.producer_id));
    wire ex1_completion_hit =
        (completion_bus_i[0].valid && completion_bus_i[0].producer_tracked &&
         (completion_bus_i[0].producer_id == ex_hzd1_i.producer_id)) |
        (completion_bus_i[1].valid && completion_bus_i[1].producer_tracked &&
         (completion_bus_i[1].producer_id == ex_hzd1_i.producer_id)) |
        (completion_bus_i[2].valid && completion_bus_i[2].producer_tracked &&
         (completion_bus_i[2].producer_id == ex_hzd1_i.producer_id)) |
        (completion_bus_i[3].valid && completion_bus_i[3].producer_tracked &&
         (completion_bus_i[3].producer_id == ex_hzd1_i.producer_id));
`ifndef SYNTHESIS
    wire [2:0] dbg_rs1_producer_kind = rs1_has_producer ?
        dbg_producer_kind_q[rs1_producer_slot] : 3'd0;
    wire [2:0] dbg_rs2_producer_kind = rs2_has_producer ?
        dbg_producer_kind_q[rs2_producer_slot] : 3'd0;
`endif
    // Completion broadcasts terminate at the Future File registers. Dispatch
    // observes them on the following cycle; there is no completion-to-issue
    // wake/select path in the same cycle.
    wire rs1_producer_ready = rs1_has_producer &&
        latest_ready_q[id_ctrl_i.rs1_addr];
    wire rs2_producer_ready = rs2_has_producer &&
        latest_ready_q[id_ctrl_i.rs2_addr];

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
    wire rs3_producer_ready = rs3_has_producer &&
        latest_ready_q[id_ctrl1_i.rs1_addr];
    wire rs4_producer_ready = rs4_has_producer &&
        latest_ready_q[id_ctrl1_i.rs2_addr];

	wire rs1_issue_hzd0 = id_ex_rd_issue && id_ctrl_i.rs1_ren &&
		(id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr) &&
		!prev_alu_bypass_rs1;
	wire rs2_issue_hzd0 = id_ex_rd_issue && id_ctrl_i.rs2_ren &&
		(id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr) &&
		!prev_alu_bypass_rs2;
    wire rs1_issue_hzd1 = id_ex1_rd_issue && id_ctrl_i.rs1_ren &&
        (id_ctrl_i.rs1_addr == ex_hzd1_i.rd_addr);
    wire rs2_issue_hzd1 = id_ex1_rd_issue && id_ctrl_i.rs2_ren &&
        (id_ctrl_i.rs2_addr == ex_hzd1_i.rd_addr);
    wire rs1_issue_hzd = rs1_issue_hzd0 | rs1_issue_hzd1;
    wire rs2_issue_hzd = rs2_issue_hzd0 | rs2_issue_hzd1;
    wire rd_issue_hzd = 1'b0;
    // A bypassable EX writer is newer than any producer already recorded for
    // the same GPR. Do not let that older WAW entry block or wake the consumer.
	wire rs1_pending_stall = rs1_has_producer && !rs1_producer_ready &&
		!prev_alu_bypass_rs1;
	wire rs2_pending_stall = rs2_has_producer && !rs2_producer_ready &&
		!prev_alu_bypass_rs2;
	wire rd_waw_stall = 1'b0;
	wire store_data_wait = id_ctrl_i.store_req &&
		rs2_blocking_hzd;
	// Store data follows the same Future File boundary as every other source.
	// A store reaches the LSU only after both its address and data are ready.
	wire rs2_blocking_hzd = rs2_issue_hzd | rs2_pending_stall;
    wire scoreboard_stall = rs1_issue_hzd | rs1_pending_stall |
        rs2_blocking_hzd;
    wire rs3_issue_hzd = id_ctrl1_i.rs1_ren &&
        ((id_ex_rd_issue && (id_ctrl1_i.rs1_addr == ex_hzd_i.rd_addr)) ||
         (id_ex1_rd_issue && (id_ctrl1_i.rs1_addr == ex_hzd1_i.rd_addr)));
    wire rs4_issue_hzd = id_ctrl1_i.rs2_ren &&
        ((id_ex_rd_issue && (id_ctrl1_i.rs2_addr == ex_hzd_i.rd_addr)) ||
         (id_ex1_rd_issue && (id_ctrl1_i.rs2_addr == ex_hzd1_i.rd_addr)));
    wire rs3_pending_stall = rs3_has_producer && !rs3_producer_ready;
    wire rs4_pending_stall = rs4_has_producer && !rs4_producer_ready;
    wire scoreboard_stall1 = rs3_issue_hzd | rs4_issue_hzd |
        rs3_pending_stall | rs4_pending_stall;
    wire lsu_struct_stall = id_ctrl_i.lsu_req && lsu_status_i.busy;
    wire lsu_serialize_stall = id_ctrl_i.serialize_before && !lsu_status_i.idle;
    wire decode_bubble_stall = scoreboard_stall | lsu_struct_stall |
        lsu_serialize_stall |
        producer_full_stall | rob_full_stall | checkpoint_full_stall |
        trap_stall_i |
        wb_backpressure_i;
    wire checkpoint_alloc = id_ctrl_i.checkpoint_req &&
        !decode_bubble_stall && !ex_mul_stall_i && !ex_branch_jump_i;

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
    assign producer_alloc_id_o = producer_alloc_id;
    assign producer_alloc_tracked_o = id_ctrl_i.rd_wen;
    assign producer_alloc_id1_o = producer_alloc_id1;
    assign producer_alloc_tracked1_o = id_ctrl1_i.rd_wen;
    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;
    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o;
    assign flush_ex_o = branch_jump_o;
    assign stall_id_o = ex_mul_stall_i;
    assign stall_if_o = decode_bubble_stall | ex_mul_stall_i;
    assign stall_pc_o = decode_bubble_stall | ex_mul_stall_i;
    assign bubble_id_o = decode_bubble_stall;

    // Operand packets only expose values retained in the registered Future
    // File. Completion matching and data capture terminate at that boundary.
    assign producer_rs1_fwd_o.valid = rs1_has_producer &&
        latest_ready_q[id_ctrl_i.rs1_addr];
    assign producer_rs1_fwd_o.producer_id = rs1_producer_id;
    assign producer_rs1_fwd_o.producer_tracked = rs1_has_producer;
    assign producer_rs1_fwd_o.addr = id_ctrl_i.rs1_addr;
    assign producer_rs1_fwd_o.data = producer_value_q[rs1_producer_slot];
    assign producer_rs2_fwd_o.valid = rs2_has_producer &&
        latest_ready_q[id_ctrl_i.rs2_addr];
    assign producer_rs2_fwd_o.producer_id = rs2_producer_id;
    assign producer_rs2_fwd_o.producer_tracked = rs2_has_producer;
    assign producer_rs2_fwd_o.addr = id_ctrl_i.rs2_addr;
    assign producer_rs2_fwd_o.data = producer_value_q[rs2_producer_slot];
    assign producer_rs3_fwd_o.valid = rs3_has_producer &&
        latest_ready_q[id_ctrl1_i.rs1_addr];
    assign producer_rs3_fwd_o.producer_id = rs3_producer_id;
    assign producer_rs3_fwd_o.producer_tracked = rs3_has_producer;
    assign producer_rs3_fwd_o.addr = id_ctrl1_i.rs1_addr;
    assign producer_rs3_fwd_o.data = producer_value_q[rs3_producer_slot];
    assign producer_rs4_fwd_o.valid = rs4_has_producer &&
        latest_ready_q[id_ctrl1_i.rs2_addr];
    assign producer_rs4_fwd_o.producer_id = rs4_producer_id;
    assign producer_rs4_fwd_o.producer_tracked = rs4_has_producer;
    assign producer_rs4_fwd_o.addr = id_ctrl1_i.rs2_addr;
    assign producer_rs4_fwd_o.data = producer_value_q[rs4_producer_slot];
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
    assign wb_fwd_o = wb_fwd_q;
    always_comb begin
        hzd_status1_o = '0;
        hzd_status1_o.scoreboard_stall = scoreboard_stall1 |
            producer_pair_stall |
            rob_pair_stall |
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
    assign wb_fwd1_o = wb_fwd1_q;

    integer slot_idx;
    integer reg_idx;
    wire [REGS_NUM-1:0] completion_ready_mask;
    wire [REGS_NUM-1:0] latest_ready_next;
    wire [REGS_NUM-1:0] latest_valid_next;
    genvar ready_idx;
    generate
        for (ready_idx = 0; ready_idx < REGS_NUM; ready_idx++) begin : g_ready_next
            wire completion_match0 = completion_bus_i[0].valid &&
                completion_bus_i[0].producer_tracked &&
                (completion_bus_i[0].addr == REGS_ADDR_WIDTH'(ready_idx)) &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == completion_bus_i[0].producer_id);
            wire completion_match1 = completion_bus_i[1].valid &&
                completion_bus_i[1].producer_tracked &&
                (completion_bus_i[1].addr == REGS_ADDR_WIDTH'(ready_idx)) &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == completion_bus_i[1].producer_id);
            wire completion_match2 = completion_bus_i[2].valid &&
                completion_bus_i[2].producer_tracked &&
                (completion_bus_i[2].addr == REGS_ADDR_WIDTH'(ready_idx)) &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == completion_bus_i[2].producer_id);
            wire completion_match3 = completion_bus_i[3].valid &&
                completion_bus_i[3].producer_tracked &&
                (completion_bus_i[3].addr == REGS_ADDR_WIDTH'(ready_idx)) &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == completion_bus_i[3].producer_id);
            wire alloc0_here = producer_alloc_ex &&
                (ex_hzd_i.rd_addr == REGS_ADDR_WIDTH'(ready_idx));
            wire alloc1_here = producer_alloc_ex1 &&
                (ex_hzd1_i.rd_addr == REGS_ADDR_WIDTH'(ready_idx));
            wire retire0_here = rob_commit0 &&
                rob_writes_gpr_q[rob_head_q] &&
                (rob_rd_addr_q[rob_head_q] == REGS_ADDR_WIDTH'(ready_idx)) &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == rob_ftag_q[rob_head_q]);
            wire retire1_here = rob_commit1 &&
                rob_writes_gpr_q[rob_head1] &&
                (rob_rd_addr_q[rob_head1] == REGS_ADDR_WIDTH'(ready_idx)) &&
                latest_valid_q[ready_idx] &&
                (latest_id_q[ready_idx] == rob_ftag_q[rob_head1]);

            assign latest_retire_mask[ready_idx] = retire0_here | retire1_here;
            assign latest_valid_next[ready_idx] = (alloc1_here | alloc0_here) ?
                1'b1 : (retire0_here | retire1_here) ?
                1'b0 : latest_valid_q[ready_idx];
            assign completion_ready_mask[ready_idx] = completion_match0 |
                completion_match1 | completion_match2 | completion_match3;
            assign latest_ready_next[ready_idx] = alloc1_here ?
                ex1_completion_hit : alloc0_here ? ex_completion_hit :
                (latest_ready_q[ready_idx] | completion_ready_mask[ready_idx]);
        end
    endgenerate

    wire [ROB_PTR_WIDTH-1:0] rob_alloc1_index = rob_alloc0 ?
        rob_tail1 : rob_tail_q;
    integer rob_idx;
    integer rob_lane;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || ex_hzd_i.interrupt) begin
            rob_valid_q <= '0;
            rob_done_q <= '0;
            rob_writes_gpr_q <= '0;
            rob_head_q <= '0;
            rob_tail_q <= '0;
            rob_count_q <= '0;
            for (rob_idx = 0; rob_idx < ROB_DEPTH; rob_idx++) begin
                rob_rd_addr_q[rob_idx] <= '0;
                rob_ftag_q[rob_idx] <= '0;
                rob_op_class_q[rob_idx] <= '0;
                rob_exc_code_q[rob_idx] <= '0;
                rob_pc_q[rob_idx] <= '0;
            end
        end else begin
            for (rob_idx = 0; rob_idx < ROB_DEPTH; rob_idx++) begin
                if (rob_valid_q[rob_idx] && rob_writes_gpr_q[rob_idx]) begin
                    for (rob_lane = 0; rob_lane < COMPLETION_LANES; rob_lane++) begin
                        if (completion_bus_i[rob_lane].valid &&
                            completion_bus_i[rob_lane].producer_tracked &&
                            (completion_bus_i[rob_lane].producer_id ==
                             rob_ftag_q[rob_idx]))
                            rob_done_q[rob_idx] <= 1'b1;
                    end
                end
            end

            if (rob_commit0) begin
                rob_valid_q[rob_head_q] <= 1'b0;
                rob_done_q[rob_head_q] <= 1'b0;
            end
            if (rob_commit1) begin
                rob_valid_q[rob_head1] <= 1'b0;
                rob_done_q[rob_head1] <= 1'b0;
            end

            if (rob_alloc0) begin
                rob_valid_q[rob_tail_q] <= 1'b1;
                rob_done_q[rob_tail_q] <= !ex_hzd_i.producer_tracked ||
                    ex_completion_hit;
                rob_writes_gpr_q[rob_tail_q] <= ex_hzd_i.producer_tracked;
                rob_rd_addr_q[rob_tail_q] <= ex_hzd_i.rd_addr;
                rob_ftag_q[rob_tail_q] <= ex_hzd_i.producer_id;
                rob_op_class_q[rob_tail_q] <= {
                    ex_hzd_i.operator_type[OPERATOR_TYPE_BJP],
                    ex_hzd_i.operator_type[OPERATOR_TYPE_STORE],
                    ex_hzd_i.operator_type[OPERATOR_TYPE_LOAD]};
                rob_exc_code_q[rob_tail_q] <= '0;
                rob_pc_q[rob_tail_q] <= ex_pc_i;
            end
            if (rob_alloc1) begin
                rob_valid_q[rob_alloc1_index] <= 1'b1;
                rob_done_q[rob_alloc1_index] <=
                    !ex_hzd1_i.producer_tracked || ex1_completion_hit;
                rob_writes_gpr_q[rob_alloc1_index] <=
                    ex_hzd1_i.producer_tracked;
                rob_rd_addr_q[rob_alloc1_index] <= ex_hzd1_i.rd_addr;
                rob_ftag_q[rob_alloc1_index] <= ex_hzd1_i.producer_id;
                rob_op_class_q[rob_alloc1_index] <= {
                    ex_hzd1_i.operator_type[OPERATOR_TYPE_BJP],
                    ex_hzd1_i.operator_type[OPERATOR_TYPE_STORE],
                    ex_hzd1_i.operator_type[OPERATOR_TYPE_LOAD]};
                rob_exc_code_q[rob_alloc1_index] <= '0;
                rob_pc_q[rob_alloc1_index] <= ex_pc1_i;
            end

            if (rob_commit_count != '0)
                rob_head_q <= rob_ptr_add(rob_head_q, rob_commit_count);
            if (rob_alloc_count != '0)
                rob_tail_q <= rob_ptr_add(rob_tail_q, rob_alloc_count);
            rob_count_q <= rob_count_q + ROB_COUNT_WIDTH'(rob_alloc_count) -
                ROB_COUNT_WIDTH'(rob_commit_count);
        end
    end

    integer checkpoint_idx;
    integer checkpoint_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || ex_hzd_i.interrupt) begin
            checkpoint_head_q <= '0;
            checkpoint_tail_q <= '0;
            checkpoint_count_q <= '0;
            for (checkpoint_idx = 0; checkpoint_idx < CHECKPOINT_DEPTH;
                 checkpoint_idx++) begin
                checkpoint_rat_valid_q[checkpoint_idx] <= '0;
                for (checkpoint_reg = 0; checkpoint_reg < REGS_NUM;
                     checkpoint_reg++)
                    checkpoint_rat_id_q[checkpoint_idx][checkpoint_reg] <= '0;
            end
        end else if (ex_branch_jump_i && (checkpoint_count_q != '0)) begin
            // Every redirect invalidates younger branch checkpoints, including
            // checkpoints allocated behind a direct JAL/JALR. Conditional
            // mispredicts restore the head RAT separately below; direct jumps
            // only discard their younger speculative state.
            checkpoint_head_q <= checkpoint_head_q + 1'b1;
            checkpoint_tail_q <= checkpoint_head_q + 1'b1;
            checkpoint_count_q <= '0;
            for (checkpoint_idx = 0; checkpoint_idx < CHECKPOINT_DEPTH;
                 checkpoint_idx++)
                checkpoint_rat_valid_q[checkpoint_idx] <= '0;
        end else begin
            // Keep the next free checkpoint slot mirrored to the current RAT.
            // Branch acceptance then only advances the tail pointer instead of
            // driving every checkpoint register enable through ID hazards.
            if (checkpoint_count_q < 3'(CHECKPOINT_DEPTH)) begin
                checkpoint_rat_valid_q[checkpoint_tail_q] <= latest_valid_next;
                for (checkpoint_reg = 0; checkpoint_reg < REGS_NUM;
                     checkpoint_reg++) begin
                    checkpoint_rat_id_q[checkpoint_tail_q][checkpoint_reg] <=
                        (producer_alloc_ex1 &&
                         (ex_hzd1_i.rd_addr == REGS_ADDR_WIDTH'(checkpoint_reg))) ?
                        ex_hzd1_i.producer_id :
                        (producer_alloc_ex &&
                         (ex_hzd_i.rd_addr == REGS_ADDR_WIDTH'(checkpoint_reg))) ?
                        ex_hzd_i.producer_id : latest_id_q[checkpoint_reg];
                end
            end
            if (checkpoint_alloc) begin
                checkpoint_tail_q <= checkpoint_tail_q + 1'b1;
            end
            if (ex_branch_resolve_i && (checkpoint_count_q != '0)) begin
                checkpoint_head_q <= checkpoint_head_q + 1'b1;
                checkpoint_rat_valid_q[checkpoint_head_q] <= '0;
            end
            unique case ({checkpoint_alloc,
                          ex_branch_resolve_i && (checkpoint_count_q != '0)})
                2'b10: checkpoint_count_q <= checkpoint_count_q + 1'b1;
                2'b01: checkpoint_count_q <= checkpoint_count_q - 1'b1;
                default: checkpoint_count_q <= checkpoint_count_q;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            latest_valid_q <= '0;
            latest_ready_q <= '0;
            wb_fwd_q <= '0;
            wb_fwd1_q <= '0;
            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                producer_rd_q[slot_idx] <= '0;
                producer_value_q[slot_idx] <= '0;
                producer_tag_q[slot_idx] <= '0;
`ifndef SYNTHESIS
                dbg_producer_kind_q[slot_idx] <= '0;
`endif
            end
            for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++) begin
                latest_id_q[reg_idx] <= '0;
            end
        end else if (ex_hzd_i.interrupt) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            latest_valid_q <= '0;
            latest_ready_q <= '0;
            wb_fwd_q <= '0;
            wb_fwd1_q <= '0;
        end else begin
            latest_valid_q <= latest_valid_next;
            latest_ready_q <= latest_ready_next;
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
                if (producer_wb_retire_mask[slot_idx]) begin
                    producer_valid_q[slot_idx] <= 1'b0;
                    producer_ready_q[slot_idx] <= 1'b0;
                end
                if (producer_complete_mask[slot_idx]) begin
                    producer_ready_q[slot_idx] <= 1'b1;
                    producer_value_q[slot_idx] <= producer_completion_data[slot_idx];
                end
            end

            if (producer_alloc_ex) begin
                producer_valid_q[ex_producer_slot] <= 1'b1;
                producer_ready_q[ex_producer_slot] <=
                    ex_completion_hit;
                producer_rd_q[ex_producer_slot] <= ex_hzd_i.rd_addr;
                producer_tag_q[ex_producer_slot] <= ex_hzd_i.producer_id;
`ifndef SYNTHESIS
                if (ex_is_load)
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_LOAD;
                else if (ex_hzd_i.operator_type[OPERATOR_TYPE_MUL])
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_MUL;
                else if (ex_is_alu)
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_ALU;
                else
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_OTHER;
`endif
                if (ex_completion_hit)
                    producer_value_q[ex_producer_slot] <= ex_completion_data;
                latest_id_q[ex_hzd_i.rd_addr] <= ex_hzd_i.producer_id;
            end
            if (producer_alloc_ex1) begin
                producer_valid_q[ex_producer_slot1] <= 1'b1;
                producer_ready_q[ex_producer_slot1] <=
                    ex1_completion_hit;
                producer_rd_q[ex_producer_slot1] <= ex_hzd1_i.rd_addr;
                producer_tag_q[ex_producer_slot1] <= ex_hzd1_i.producer_id;
`ifndef SYNTHESIS
                dbg_producer_kind_q[ex_producer_slot1] <= DBG_PRODUCER_ALU;
`endif
                if (ex1_completion_hit)
                    producer_value_q[ex_producer_slot1] <= ex1_completion_data;
                latest_id_q[ex_hzd1_i.rd_addr] <= ex_hzd1_i.producer_id;
            end
            if (ex_branch_jump_i && ex_branch_resolve_i &&
                (checkpoint_count_q != '0)) begin
                latest_valid_q <= checkpoint_restore_valid;
                latest_ready_q <= checkpoint_restore_ready;
                for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++)
                    latest_id_q[reg_idx] <=
                        checkpoint_rat_id_q[checkpoint_head_q][reg_idx];
            end
        end
    end
endmodule
