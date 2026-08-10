module ydrasil_issue_stage
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        flush_id_i,
    input  wire                        branch_recovery_i,
    input  wire                        trap_flush_i,
    input  producer_slot_t             recovery_head_slot_i,
    input  producer_slot_t             recovery_branch_slot_i,
    // Queue entries are already renamed and hold their ROB/LSQ allocation.
    // Scheduler admission is therefore a dequeue handshake only.
    input  ydrasil_issue_pkt_t         queue_pkt_i,
    input  ydrasil_issue_pkt_t         queue_pkt1_i,
    input  wire                        queue_valid_i,
    input  wire                        queue_valid1_i,
    input  wire                        value_alloc0_valid_i,
    input  producer_id_t               value_alloc0_id_i,
    input  wire                        value_alloc1_valid_i,
    input  producer_id_t               value_alloc1_id_i,
    input  ydrasil_completion_meta_t   completion_meta_i [COMPLETION_LANES],
    input  wire [REGS_DATA_WIDTH-1:0]  completion_data_i [COMPLETION_LANES],
    input  ydrasil_commit_pkt_t        commit_pkt_i,
    input  ydrasil_commit_pkt_t        commit_pkt1_i,
    input  producer_id_t               retire_id0_i,
    input  producer_id_t               retire_id1_i,
    input  wire                        lsu_idle_i,
    input  producer_id_t               rob_head_id_i,
    output wire                        queue_consume0_o,
    output wire                        queue_consume1_o,
    output ydrasil_compact_uop_t       issue_pkt_o,
    output ydrasil_compact_uop_t       issue_pkt1_o,
    output wire [REGS_DATA_WIDTH-1:0]  retire_value0_o,
    output wire [REGS_DATA_WIDTH-1:0]  retire_value1_o,
    output wire                        issue_ready_o,
    output wire                        issue_consume_two_o,
    output wire                        issue_slot1_replay_o,
    output wire                        issue_fence_o,
    output producer_id_t               issue_fence_tag_o,
    output wire [INST_ADDR_WIDTH-1:0]  issue_fence_next_pc_o,
    output wire                        dependency_wait_o,
    output wire                        dependency_wait1_o,
    output wire                        lsu_struct_stall_o,
    output wire                        lsu_struct_stall1_o,
    output wire                        serialize_stall_o,
    output wire                        src0_wait_o,
    output wire                        src1_wait_o,
    output wire                        src2_wait_o,
    output wire                        src3_wait_o,
    output wire                        illegal_instr_o,
    output wire                        alu_in_valid_o,
    output wire [DATA_WIDTH-1:0]       alu_in_operand_a_o,
    output wire [DATA_WIDTH-1:0]       alu_in_operand_b_o,
    output wire [OPERATOR_WIDTH-1:0]   alu_in_operator_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0] alu_in_operator_type_o,
    output wire                        alu_in_rd_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0]  alu_in_rd_addr_o,
    output producer_id_t               alu_in_producer_id_o,
    output wire [DATA_WIDTH-1:0]       lane_a_pc_o,
    output wire                        agu_in_valid_o,
    output wire [DATA_WIDTH-1:0]       agu_in_operand_a_o,
    output wire [DATA_WIDTH-1:0]       agu_in_operand_b_o,
    output ydrasil_lsu_req_pkt_t       agu_in_req_o,
    output wire [DATA_WIDTH-1:0]       agu_in_store_data_o,
    output wire                        csr_in_valid_o,
    output wire [DATA_WIDTH-1:0]       csr_in_operand_a_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0] csr_in_operator_type_o,
    output wire [CSR_ADDR_WIDTH-1:0]   csr_in_raddr_o,
    output wire [CSR_ADDR_WIDTH-1:0]   csr_in_waddr_o,
    output wire [OP_CSR_INFO_WIDTH-1:0] csr_in_op_info_o,
    output wire [OP_SYS_INFO_WIDTH-1:0] csr_in_sys_info_o,
    output wire                        mul_in_valid_o,
    output wire [DATA_WIDTH-1:0]       mul_in_operand_a_o,
    output wire [DATA_WIDTH-1:0]       mul_in_operand_b_o,
    output wire [OPERATOR_WIDTH-1:0]   mul_in_operator_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0] mul_in_operator_type_o,
    output ydrasil_lane_b_meta_t       dual_meta_o,
    output wire                        dual_alu_valid_o,
    output ydrasil_lane_b_alu_payload_t dual_alu_payload_o,
    output wire [DATA_WIDTH-1:0]       dual_alu_operand_a_o,
    output wire [DATA_WIDTH-1:0]       dual_alu_operand_b_o,
    output wire                        dual_bit_valid_o,
    output ydrasil_lane_b_bit_payload_t dual_bit_payload_o,
    output wire [DATA_WIDTH-1:0]       dual_bit_operand_a_o,
    output wire [DATA_WIDTH-1:0]       dual_bit_operand_b_o,
    output wire                        dual_bru_valid_o,
    output ydrasil_lane_b_bru_payload_t dual_bru_payload_o,
    output wire [DATA_WIDTH-1:0]       dual_bru_operand_a_o,
    output wire [DATA_WIDTH-1:0]       dual_bru_operand_b_o
);
    ydrasil_compact_uop_t dispatch_compact0;
    ydrasil_compact_uop_t dispatch_compact1;
    ydrasil_compact_uop_t dispatch_compact0_raw;
    ydrasil_compact_uop_t dispatch_compact1_raw;
    ydrasil_compact_uop_t lane_a_uop;
    ydrasil_compact_uop_t lane_b_uop;
    wire lane_a_valid;
    wire lane_b_valid;
    wire [PRODUCER_NUM-1:0] issue_remove_mask;
    wire lookup_valid;
    producer_id_t lookup_tag0;
    producer_id_t lookup_tag1;
    producer_id_t lookup_tag2;
    producer_id_t lookup_tag3;
    wire lookup_resident0;
    wire lookup_resident1;
    wire lookup_resident2;
    wire lookup_resident3;
    wire lookup_reallocated0;
    wire lookup_reallocated1;
    wire lookup_reallocated2;
    wire lookup_reallocated3;

    ydrasil_issue_compactor u_compact0(
        .issue_pkt_i(queue_pkt_i), .compact_uop_o(dispatch_compact0_raw));
    ydrasil_issue_compactor u_compact1(
        .issue_pkt_i(queue_pkt1_i), .compact_uop_o(dispatch_compact1_raw));
    always_comb begin
        dispatch_compact0 = dispatch_compact0_raw;
        dispatch_compact1 = dispatch_compact1_raw;
        // Queue occupancy owns admission validity. Do not let the packed
        // payload's stale valid bit feed scheduler credit or ingress state.
        dispatch_compact0.valid = queue_valid_i;
        dispatch_compact1.valid = queue_valid1_i;
    end

    ydrasil_banked_scheduler u_scheduler(
        .clk(clk), .rst_n(rst_n),
        // A redirect presents both flush_id_i and branch_recovery_i. Keep the
        // latter distinct so an older in-flight DIV is not discarded.
        .hard_flush_i(trap_flush_i || (flush_id_i && !branch_recovery_i)),
        .branch_recovery_i(branch_recovery_i),
        .recovery_head_slot_i(recovery_head_slot_i),
        .recovery_branch_slot_i(recovery_branch_slot_i),
        .queue0_i(dispatch_compact0), .queue1_i(dispatch_compact1),
        .queue_valid0_i(queue_valid_i), .queue_valid1_i(queue_valid1_i),
        .completion_meta_i(completion_meta_i),
        .lookup_resident0_i(lookup_resident0),
        .lookup_resident1_i(lookup_resident1),
        .lookup_resident2_i(lookup_resident2),
        .lookup_resident3_i(lookup_resident3),
        .lookup_reallocated0_i(lookup_reallocated0),
        .lookup_reallocated1_i(lookup_reallocated1),
        .lookup_reallocated2_i(lookup_reallocated2),
        .lookup_reallocated3_i(lookup_reallocated3),
        .lsu_idle_i(lsu_idle_i),
        .rob_head_id_i(rob_head_id_i),
        .queue_consume0_o(queue_consume0_o),
        .queue_consume1_o(queue_consume1_o),
        .lane_a_uop_o(lane_a_uop), .lane_a_valid_o(lane_a_valid),
        .lane_b_uop_o(lane_b_uop), .lane_b_valid_o(lane_b_valid),
        .issue_remove_mask_o(issue_remove_mask),
        .lookup_valid_o(lookup_valid),
        .lookup_tag0_o(lookup_tag0), .lookup_tag1_o(lookup_tag1),
        .lookup_tag2_o(lookup_tag2), .lookup_tag3_o(lookup_tag3));

    assign issue_pkt_o = lane_a_uop;
    assign issue_pkt1_o = lane_b_uop;
    assign issue_ready_o = 1'b1;
    assign issue_consume_two_o = lane_a_valid && lane_b_valid;
    assign issue_slot1_replay_o = 1'b0;

    wire [REGS_ADDR_WIDTH-1:0] rf_addr0 = lane_a_uop.src0.arch_addr;
    wire [REGS_ADDR_WIDTH-1:0] rf_addr1 = lane_a_uop.src1.arch_addr;
    wire [REGS_ADDR_WIDTH-1:0] rf_addr2 = lane_b_uop.src0.arch_addr;
    wire [REGS_ADDR_WIDTH-1:0] rf_addr3 = lane_b_uop.src1.arch_addr;
    wire [DATA_WIDTH-1:0] rf_data0;
    wire [DATA_WIDTH-1:0] rf_data1;
    wire [DATA_WIDTH-1:0] rf_data2;
    wire [DATA_WIDTH-1:0] rf_data3;
    ydrasil_registers u_registers(
        .clk(clk), .rst_n(rst_n), .commit_pkt_i(commit_pkt_i),
        .commit_pkt1_i(commit_pkt1_i), .rf_raddr_rs1_i(rf_addr0),
        .rf_rdata_rs1_o(rf_data0), .rf_raddr_rs2_i(rf_addr1),
        .rf_rdata_rs2_o(rf_data1), .rf_raddr_rs3_i(rf_addr2),
        .rf_rdata_rs3_o(rf_data2), .rf_raddr_rs4_i(rf_addr3),
        .rf_rdata_rs4_o(rf_data3));

    wire [DATA_WIDTH-1:0] value_data0;
    wire [DATA_WIDTH-1:0] value_data1;
    wire [DATA_WIDTH-1:0] value_data2;
    wire [DATA_WIDTH-1:0] value_data3;
    wire value_epoch0, value_epoch1, value_epoch2, value_epoch3;
    wire value_valid0, value_valid1, value_valid2, value_valid3;
    wire src0_ready, src1_ready, src2_ready, src3_ready;
    wire [DATA_WIDTH-1:0] src0_data, src1_data, src2_data, src3_data;
    wire src0_data_valid, src1_data_valid, src2_data_valid, src3_data_valid;
    ydrasil_value_file u_value_file(
        .clk(clk), .rst_n(rst_n),
        .alloc0_valid_i(value_alloc0_valid_i),
        .alloc0_id_i(value_alloc0_id_i),
        .alloc1_valid_i(value_alloc1_valid_i),
        .alloc1_id_i(value_alloc1_id_i),
        .completion_meta_i(completion_meta_i),
        .completion_data_i(completion_data_i),
        .lookup_tag0_i(lookup_tag0), .lookup_tag1_i(lookup_tag1),
        .lookup_tag2_i(lookup_tag2), .lookup_tag3_i(lookup_tag3),
        .read_slot0_i(lane_a_uop.src0.producer_tag[PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot1_i(lane_a_uop.src1.producer_tag[PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot2_i(lane_b_uop.src0.producer_tag[PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot3_i(lane_b_uop.src1.producer_tag[PRODUCER_SLOT_WIDTH-1:0]),
        .retire_id0_i(retire_id0_i), .retire_id1_i(retire_id1_i),
        .read_data0_o(value_data0), .read_data1_o(value_data1),
        .read_data2_o(value_data2), .read_data3_o(value_data3),
        .read_epoch0_o(value_epoch0), .read_epoch1_o(value_epoch1),
        .read_epoch2_o(value_epoch2), .read_epoch3_o(value_epoch3),
        .read_valid0_o(value_valid0), .read_valid1_o(value_valid1),
        .read_valid2_o(value_valid2), .read_valid3_o(value_valid3),
        .lookup_resident0_o(lookup_resident0),
        .lookup_resident1_o(lookup_resident1),
        .lookup_resident2_o(lookup_resident2),
        .lookup_resident3_o(lookup_resident3),
        .lookup_reallocated0_o(lookup_reallocated0),
        .lookup_reallocated1_o(lookup_reallocated1),
        .lookup_reallocated2_o(lookup_reallocated2),
        .lookup_reallocated3_o(lookup_reallocated3),
        .retire_data0_o(retire_value0_o), .retire_data1_o(retire_value1_o));

    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_src0(
        .source_i(lane_a_uop.src0), .value_i(value_data0),
        .value_epoch_i(value_epoch0), .value_valid_i(value_valid0),
        .arf_i(rf_data0), .commit_pkt_i(commit_pkt_i),
        .commit_pkt1_i(commit_pkt1_i), .completion_meta_i(completion_meta_i),
        .completion_data_i(completion_data_i),
        .ready_o(src0_ready), .data_o(src0_data),
        .data_valid_o(src0_data_valid));
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_src1(
        .source_i(lane_a_uop.src1), .value_i(value_data1),
        .value_epoch_i(value_epoch1), .value_valid_i(value_valid1),
        .arf_i(rf_data1), .commit_pkt_i(commit_pkt_i),
        .commit_pkt1_i(commit_pkt1_i), .completion_meta_i(completion_meta_i),
        .completion_data_i(completion_data_i),
        .ready_o(src1_ready), .data_o(src1_data),
        .data_valid_o(src1_data_valid));
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_src2(
        .source_i(lane_b_uop.src0), .value_i(value_data2),
        .value_epoch_i(value_epoch2), .value_valid_i(value_valid2),
        .arf_i(rf_data2), .commit_pkt_i(commit_pkt_i),
        .commit_pkt1_i(commit_pkt1_i), .completion_meta_i(completion_meta_i),
        .completion_data_i(completion_data_i),
        .ready_o(src2_ready), .data_o(src2_data),
        .data_valid_o(src2_data_valid));
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_src3(
        .source_i(lane_b_uop.src1), .value_i(value_data3),
        .value_epoch_i(value_epoch3), .value_valid_i(value_valid3),
        .arf_i(rf_data3), .commit_pkt_i(commit_pkt_i),
        .commit_pkt1_i(commit_pkt1_i), .completion_meta_i(completion_meta_i),
        .completion_data_i(completion_data_i),
        .ready_o(src3_ready), .data_o(src3_data),
        .data_valid_o(src3_data_valid));

    assign src0_wait_o = lane_a_valid && lane_a_uop.src0.used && !src0_ready;
    assign src1_wait_o = lane_a_valid && lane_a_uop.src1.used && !src1_ready;
    assign src2_wait_o = lane_b_valid && lane_b_uop.src0.used && !src2_ready;
    assign src3_wait_o = lane_b_valid && lane_b_uop.src1.used && !src3_ready;
    assign dependency_wait_o = src0_wait_o ||
        (lane_a_uop.op_class != UOP_CLASS_STORE && src1_wait_o);
    assign dependency_wait1_o = src2_wait_o || src3_wait_o;
    assign lsu_struct_stall_o = 1'b0;
    assign lsu_struct_stall1_o = 1'b0;
    assign serialize_stall_o = 1'b0;

    function automatic [OPERATOR_WIDTH-1:0] op_onehot(
        input [UOP_SUBOP_WIDTH-1:0] subop
    );
        reg [OPERATOR_WIDTH-1:0] value;
        begin
            value = '0;
            if (subop < UOP_SUBOP_WIDTH'(OPERATOR_WIDTH))
                value[subop] = 1'b1;
            op_onehot = value;
        end
    endfunction

    wire lane_a_alu_valid = lane_a_valid &&
        (lane_a_uop.op_class == UOP_CLASS_ALU);
    wire lane_a_mem_valid = lane_a_valid &&
        ((lane_a_uop.op_class == UOP_CLASS_LOAD) ||
         (lane_a_uop.op_class == UOP_CLASS_STORE));
    wire lane_b_alu_valid = lane_b_valid &&
        (lane_b_uop.op_class == UOP_CLASS_ALU);
    wire lane_b_bit_valid = lane_b_valid &&
        (lane_b_uop.op_class == UOP_CLASS_BITMANIP);
    wire lane_b_bru_valid = lane_b_valid &&
        (lane_b_uop.op_class == UOP_CLASS_BJP);
    wire lane_b_mul_valid = lane_b_valid &&
        (lane_b_uop.op_class == UOP_CLASS_MUL);
    wire lane_b_csr_valid = lane_b_valid &&
        ((lane_b_uop.op_class == UOP_CLASS_CSR) ||
         (lane_b_uop.op_class == UOP_CLASS_SYS));

    wire [DATA_WIDTH-1:0] lane_a_op_a = lane_a_uop.operand_a_pc_sel ?
        lane_a_uop.pc : lane_a_uop.operand_a_imm_sel ? lane_a_uop.imm : src0_data;
    wire [DATA_WIDTH-1:0] lane_a_op_b = lane_a_uop.operand_b_jump_sel ? 32'd4 :
        lane_a_uop.operand_b_rs_sel ? src1_data : lane_a_uop.imm;
    wire [DATA_WIDTH-1:0] lane_b_op_a = lane_b_uop.operand_a_pc_sel ?
        lane_b_uop.pc : lane_b_uop.operand_a_imm_sel ? lane_b_uop.imm : src2_data;
    wire [DATA_WIDTH-1:0] lane_b_op_b = lane_b_uop.operand_b_jump_sel ? 32'd4 :
        lane_b_uop.operand_b_rs_sel ? src3_data : lane_b_uop.imm;

    wire [OPERATOR_TYPE_WIDTH-1:0] main_operator_type =
        lane_a_alu_valid ? ({{(OPERATOR_TYPE_WIDTH-1){1'b0}}, 1'b1} << OPERATOR_TYPE_ALU) : '0;
    wire [OPERATOR_TYPE_WIDTH-1:0] dual_alu_type =
        lane_b_alu_valid ? ({{(OPERATOR_TYPE_WIDTH-1){1'b0}}, 1'b1} << OPERATOR_TYPE_ALU) : '0;
    wire [OPERATOR_TYPE_WIDTH-1:0] dual_bit_type =
        lane_b_bit_valid ? ({{(OPERATOR_TYPE_WIDTH-1){1'b0}}, 1'b1} << OPERATOR_TYPE_BITMANIP) : '0;
    wire [OPERATOR_TYPE_WIDTH-1:0] dual_bru_type =
        lane_b_bru_valid ? ({{(OPERATOR_TYPE_WIDTH-1){1'b0}}, 1'b1} << OPERATOR_TYPE_BJP) : '0;
    wire [OPERATOR_TYPE_WIDTH-1:0] dual_mul_type =
        lane_b_mul_valid ? ({{(OPERATOR_TYPE_WIDTH-1){1'b0}}, 1'b1} << OPERATOR_TYPE_MUL) : '0;
    // CSR and SYS share the lane-B adapter but are distinct execution
    // operators.  Keep the type one-hot and mutually exclusive: ex_block
    // treats the CSR bit as a real CSR read/modify/write operation, while the
    // SYS bit is consumed by the precise exception controller.
    wire [OPERATOR_TYPE_WIDTH-1:0] dual_csr_type =
        lane_b_uop.op_class == UOP_CLASS_SYS ?
            ({{(OPERATOR_TYPE_WIDTH-1){1'b0}}, 1'b1} << OPERATOR_TYPE_SYS) :
        lane_b_uop.op_class == UOP_CLASS_CSR ?
            ({{(OPERATOR_TYPE_WIDTH-1){1'b0}}, 1'b1} << OPERATOR_TYPE_CSR) : '0;

    wire [REGS_DATA_WIDTH-1:0] lane_a_store_data = src1_data;
    ydrasil_lsu_req_pkt_t agu_req_d;
    always_comb begin
        agu_req_d = '0;
        agu_req_d.valid = lane_a_mem_valid;
        agu_req_d.is_load = lane_a_uop.op_class == UOP_CLASS_LOAD;
        agu_req_d.is_store = lane_a_uop.op_class == UOP_CLASS_STORE;
        agu_req_d.op[lane_a_uop.lsu_subop] = lane_a_mem_valid;
        agu_req_d.rd_addr = lane_a_uop.dst.rd_addr;
        agu_req_d.producer_id = lane_a_uop.dst.rob_tag;
        agu_req_d.lsq_index = lane_a_uop.lsq_index;
        agu_req_d.producer_tracked = lane_a_mem_valid;
        agu_req_d.store_data = lane_a_store_data;
        agu_req_d.store_data_valid = !agu_req_d.is_store || src1_data_valid;
        agu_req_d.store_producer_id = lane_a_uop.src1.producer_tag;
        agu_req_d.store_producer_tracked = agu_req_d.is_store &&
            lane_a_uop.src1.tag_valid && !src1_data_valid;
    end
    assign agu_in_req_o = agu_req_q;
    assign agu_in_store_data_o = agu_store_data_q;

    ydrasil_lane_b_meta_t dual_meta_d;
    ydrasil_lane_b_alu_payload_t dual_alu_payload_d;
    ydrasil_lane_b_bit_payload_t dual_bit_payload_d;
    ydrasil_lane_b_bru_payload_t dual_bru_payload_d;
    always_comb begin
        dual_meta_d = '0;
        dual_meta_d.rd_addr = lane_b_uop.dst.rd_addr;
        dual_meta_d.rd_wen = lane_b_valid && lane_b_uop.dst.writes_gpr;
        dual_meta_d.producer_id = lane_b_uop.dst.rob_tag;
        dual_meta_d.producer_tracked = lane_b_valid;
        dual_meta_d.pc = lane_b_uop.pc;
        dual_meta_d.instr = lane_b_uop.instr;
        dual_alu_payload_d = '0;
        dual_alu_payload_d.subop = lane_b_uop.subop;
        dual_alu_payload_d.operand_a = lane_b_op_a;
        dual_alu_payload_d.operand_b = lane_b_op_b;
        dual_bit_payload_d = '0;
        dual_bit_payload_d.subop = lane_b_uop.subop;
        dual_bit_payload_d.operand_a = lane_b_op_a;
        dual_bit_payload_d.operand_b = lane_b_op_b;
        dual_bru_payload_d = '0;
        dual_bru_payload_d.subop = lane_b_uop.subop;
        dual_bru_payload_d.operand_a = src2_data;
        dual_bru_payload_d.operand_b = src3_data;
        dual_bru_payload_d.imm = lane_b_uop.imm;
        dual_bru_payload_d.jalr = lane_b_uop.bt_a_rs_sel;
        dual_bru_payload_d.pred_hit = lane_b_uop.pred_hit;
        dual_bru_payload_d.pred_taken = lane_b_uop.pred_taken;
        dual_bru_payload_d.pred_target = lane_b_uop.pred_target;
        dual_bru_payload_d.pred_counter = lane_b_uop.pred_counter;
        dual_bru_payload_d.pred_bht_index = lane_b_uop.pred_bht_index;
    end

    reg alu_valid_q;
    reg [DATA_WIDTH-1:0] alu_a_q, alu_b_q;
    reg [OPERATOR_WIDTH-1:0] alu_op_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] alu_type_q;
    reg alu_rd_wen_q;
    reg [REGS_ADDR_WIDTH-1:0] alu_rd_addr_q;
    producer_id_t alu_producer_q;
    reg [DATA_WIDTH-1:0] lane_a_pc_q;
    reg agu_valid_q;
    reg [DATA_WIDTH-1:0] agu_a_q, agu_b_q;
    ydrasil_lsu_req_pkt_t agu_req_q;
    reg [DATA_WIDTH-1:0] agu_store_data_q;
    reg csr_valid_q;
    reg [DATA_WIDTH-1:0] csr_a_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] csr_type_q;
    reg [CSR_ADDR_WIDTH-1:0] csr_raddr_q, csr_waddr_q;
    reg [OP_CSR_INFO_WIDTH-1:0] csr_op_info_q;
    reg [OP_SYS_INFO_WIDTH-1:0] csr_sys_info_q;
    reg mul_valid_q;
    reg [DATA_WIDTH-1:0] mul_a_q, mul_b_q;
    reg [OPERATOR_WIDTH-1:0] mul_op_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] mul_type_q;
    reg dual_alu_valid_q, dual_bit_valid_q, dual_bru_valid_q;
    ydrasil_lane_b_meta_t dual_meta_q;
    ydrasil_lane_b_alu_payload_t dual_alu_payload_q;
    ydrasil_lane_b_bit_payload_t dual_bit_payload_q;
    ydrasil_lane_b_bru_payload_t dual_bru_payload_q;
    reg illegal_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_id_i || trap_flush_i || branch_recovery_i) begin
            alu_valid_q <= 1'b0;
            agu_valid_q <= 1'b0;
            csr_valid_q <= 1'b0;
            mul_valid_q <= 1'b0;
            dual_alu_valid_q <= 1'b0;
            dual_bit_valid_q <= 1'b0;
            dual_bru_valid_q <= 1'b0;
            dual_meta_q <= '0;
            agu_req_q <= '0;
            agu_store_data_q <= '0;
            illegal_q <= 1'b0;
        end else begin
            alu_valid_q <= lane_a_alu_valid;
            alu_a_q <= lane_a_op_a;
            alu_b_q <= lane_a_op_b;
            alu_op_q <= op_onehot(lane_a_uop.subop);
            alu_type_q <= main_operator_type;
            alu_rd_wen_q <= lane_a_valid && lane_a_uop.dst.writes_gpr;
            alu_rd_addr_q <= lane_a_uop.dst.rd_addr;
            alu_producer_q <= lane_a_uop.dst.rob_tag;
            lane_a_pc_q <= lane_a_uop.pc;
            agu_valid_q <= lane_a_mem_valid;
            agu_a_q <= lane_a_op_a;
            agu_b_q <= lane_a_op_b;
            agu_req_q <= agu_req_d;
            agu_store_data_q <= lane_a_store_data;
            csr_valid_q <= lane_b_csr_valid;
            csr_a_q <= lane_b_op_a;
            csr_type_q <= dual_csr_type;
            csr_raddr_q <= lane_b_uop.csr_raddr;
            csr_waddr_q <= lane_b_uop.csr_waddr;
            csr_op_info_q <= lane_b_uop.csr_op_info;
            csr_sys_info_q <= lane_b_uop.sys_op_info;
            mul_valid_q <= lane_b_mul_valid;
            mul_a_q <= lane_b_op_a;
            mul_b_q <= lane_b_op_b;
            mul_op_q <= op_onehot(lane_b_uop.subop);
            mul_type_q <= dual_mul_type;
            dual_alu_valid_q <= lane_b_alu_valid;
            dual_bit_valid_q <= lane_b_bit_valid;
            dual_bru_valid_q <= lane_b_bru_valid;
            dual_meta_q <= dual_meta_d;
            dual_alu_payload_q <= dual_alu_payload_d;
            dual_bit_payload_q <= dual_bit_payload_d;
            dual_bru_payload_q <= dual_bru_payload_d;
            // Illegal encodings retain SYS/lane-B classification through the
            // scheduler, so capture the exception identity with that token.
            illegal_q <= lane_b_valid && lane_b_uop.illegal_instr;
        end
    end

    reg issue_fence_q;
    producer_id_t issue_fence_tag_q;
    reg [INST_ADDR_WIDTH-1:0] issue_fence_next_pc_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_id_i || trap_flush_i || branch_recovery_i) begin
            issue_fence_q <= 1'b0;
            issue_fence_tag_q <= '0;
            issue_fence_next_pc_q <= '0;
        end else begin
            issue_fence_q <= (lane_a_valid && lane_a_uop.fence_i) ||
                (lane_b_valid && lane_b_uop.fence_i);
            if (lane_a_valid && lane_a_uop.fence_i) begin
                issue_fence_tag_q <= lane_a_uop.dst.rob_tag;
                issue_fence_next_pc_q <= lane_a_uop.pc + 32'd4;
            end else if (lane_b_valid && lane_b_uop.fence_i) begin
                issue_fence_tag_q <= lane_b_uop.dst.rob_tag;
                issue_fence_next_pc_q <= lane_b_uop.pc + 32'd4;
            end
        end
    end

    assign issue_fence_o = issue_fence_q;
    assign issue_fence_tag_o = issue_fence_tag_q;
    assign issue_fence_next_pc_o = issue_fence_next_pc_q;
    assign illegal_instr_o = illegal_q;
    assign alu_in_valid_o = alu_valid_q;
    assign alu_in_operand_a_o = alu_a_q;
    assign alu_in_operand_b_o = alu_b_q;
    assign alu_in_operator_o = alu_op_q;
    assign alu_in_operator_type_o = alu_type_q;
    assign alu_in_rd_wen_o = alu_rd_wen_q;
    assign alu_in_rd_addr_o = alu_rd_addr_q;
    assign alu_in_producer_id_o = alu_producer_q;
    assign lane_a_pc_o = lane_a_pc_q;
    assign agu_in_valid_o = agu_valid_q;
    assign agu_in_operand_a_o = agu_a_q;
    assign agu_in_operand_b_o = agu_b_q;
    assign csr_in_valid_o = csr_valid_q;
    assign csr_in_operand_a_o = csr_a_q;
    assign csr_in_operator_type_o = csr_type_q;
    assign csr_in_raddr_o = csr_raddr_q;
    assign csr_in_waddr_o = csr_waddr_q;
    assign csr_in_op_info_o = csr_op_info_q;
    assign csr_in_sys_info_o = csr_sys_info_q;
    assign mul_in_valid_o = mul_valid_q;
    assign mul_in_operand_a_o = mul_a_q;
    assign mul_in_operand_b_o = mul_b_q;
    assign mul_in_operator_o = mul_op_q;
    assign mul_in_operator_type_o = mul_type_q;
    assign dual_meta_o = dual_meta_q;
    assign dual_alu_valid_o = dual_alu_valid_q;
    assign dual_alu_payload_o = dual_alu_payload_q;
    assign dual_alu_operand_a_o = dual_alu_payload_q.operand_a;
    assign dual_alu_operand_b_o = dual_alu_payload_q.operand_b;
    assign dual_bit_valid_o = dual_bit_valid_q;
    assign dual_bit_payload_o = dual_bit_payload_q;
    assign dual_bit_operand_a_o = dual_bit_payload_q.operand_a;
    assign dual_bit_operand_b_o = dual_bit_payload_q.operand_b;
    assign dual_bru_valid_o = dual_bru_valid_q;
    assign dual_bru_payload_o = dual_bru_payload_q;
    assign dual_bru_operand_a_o = dual_bru_payload_q.operand_a;
    assign dual_bru_operand_b_o = dual_bru_payload_q.operand_b;

    // ------------------------------------------------------------------
endmodule

// Two physical scheduler banks.  Bank membership is storage-only: operation
// class selects a lane candidate, never a reservation-store domain.  The
// registered ingress is deliberately independent of issue removal, so no
// queue intake and scheduler selection have separate registered boundaries.
module ydrasil_banked_scheduler
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         hard_flush_i,
    input  wire                         branch_recovery_i,
    input  producer_slot_t              recovery_head_slot_i,
    input  producer_slot_t              recovery_branch_slot_i,
    input  ydrasil_compact_uop_t        queue0_i,
    input  ydrasil_compact_uop_t        queue1_i,
    input  wire                         queue_valid0_i,
    input  wire                         queue_valid1_i,
    input  ydrasil_completion_meta_t    completion_meta_i [COMPLETION_LANES],
    input  wire                         lookup_resident0_i,
    input  wire                         lookup_resident1_i,
    input  wire                         lookup_resident2_i,
    input  wire                         lookup_resident3_i,
    input  wire                         lookup_reallocated0_i,
    input  wire                         lookup_reallocated1_i,
    input  wire                         lookup_reallocated2_i,
    input  wire                         lookup_reallocated3_i,
    input  wire                         lsu_idle_i,
    input  producer_id_t                rob_head_id_i,
    output wire                         queue_consume0_o,
    output wire                         queue_consume1_o,
    output ydrasil_compact_uop_t        lane_a_uop_o,
    output wire                         lane_a_valid_o,
    output ydrasil_compact_uop_t        lane_b_uop_o,
    output wire                         lane_b_valid_o,
    output wire [PRODUCER_NUM-1:0]      issue_remove_mask_o,
    output wire                         lookup_valid_o,
    output producer_id_t                lookup_tag0_o,
    output producer_id_t                lookup_tag1_o,
    output producer_id_t                lookup_tag2_o,
    output producer_id_t                lookup_tag3_o
);
    localparam int ENTRY_DEPTH = PRODUCER_NUM;
    localparam int BANK_DEPTH = PRODUCER_NUM / 2;
    localparam int INGRESS_COUNT_WIDTH = $clog2(3);
    localparam int AGE_WIDTH = PRODUCER_SLOT_WIDTH + 1;

    ydrasil_compact_uop_t ingress_q [0:1];
    reg [INGRESS_COUNT_WIDTH-1:0] ingress_count_q;
    ydrasil_compact_uop_t entry_uop_q [0:ENTRY_DEPTH-1];
    reg [ENTRY_DEPTH-1:0] entry_valid_q;
    reg entry_src0_ready_q [0:ENTRY_DEPTH-1];
    reg entry_src1_ready_q [0:ENTRY_DEPTH-1];
    reg [ENTRY_DEPTH-1:0] entry_order_q [0:ENTRY_DEPTH-1];
    // Candidate qualification is registered before the bank compare network.
    // This keeps completion/ready and cross-block control inputs off the
    // selected-mask D path while retaining the registered wakeup contract.
    reg [ENTRY_DEPTH-1:0] entry_candidate_q;
    reg                    div_issue_q;
    producer_id_t          div_issue_id_q;
    reg                    div_inflight_q;
    producer_id_t          div_inflight_id_q;

    function automatic producer_slot_t ptr_add(
        input producer_slot_t base,
        input integer amount
    );
        integer value;
        begin
            value = integer'(base) + amount;
            if (value >= ENTRY_DEPTH)
                value = value - ENTRY_DEPTH;
            if (value >= ENTRY_DEPTH)
                value = value - ENTRY_DEPTH;
            ptr_add = producer_slot_t'(value);
        end
    endfunction

    function automatic [AGE_WIDTH-1:0] producer_age(
        input producer_id_t id,
        input producer_id_t head
    );
        integer value;
        begin
            value = integer'(id[PRODUCER_SLOT_WIDTH-1:0]) -
                integer'(head[PRODUCER_SLOT_WIDTH-1:0]);
            if (value < 0)
                value = value + ENTRY_DEPTH;
            producer_age = AGE_WIDTH'(value);
        end
    endfunction

    function automatic logic uop_memory(input ydrasil_compact_uop_t uop);
        uop_memory = (uop.op_class == UOP_CLASS_LOAD) ||
            (uop.op_class == UOP_CLASS_STORE);
    endfunction
    function automatic logic uop_store(input ydrasil_compact_uop_t uop);
        uop_store = uop.op_class == UOP_CLASS_STORE;
    endfunction
    function automatic logic uop_branch(input ydrasil_compact_uop_t uop);
        uop_branch = uop.op_class == UOP_CLASS_BJP;
    endfunction
    function automatic logic uop_serial(input ydrasil_compact_uop_t uop);
        uop_serial = uop.fence_i || (uop.op_class == UOP_CLASS_CSR) ||
            (uop.op_class == UOP_CLASS_SYS);
    endfunction
    function automatic logic uop_lane_b_only(input ydrasil_compact_uop_t uop);
        uop_lane_b_only = uop_branch(uop) || uop_serial(uop) ||
            (uop.op_class == UOP_CLASS_MUL) ||
            (uop.op_class == UOP_CLASS_BITMANIP);
    endfunction
    function automatic logic uop_divrem(input ydrasil_compact_uop_t uop);
        uop_divrem = (uop.op_class == UOP_CLASS_MUL) &&
            (uop.instr[14:12] != 3'b000) && uop.instr[25];
    endfunction

    wire incoming0 = queue_valid0_i;
    wire incoming1_raw = queue_valid1_i;
    wire ingress_has_room0 = ingress_count_q < 2;
    wire ingress_has_room1 = ingress_count_q == 0;
    // Queue ownership includes ROB, RAT, checkpoint, and LSQ allocation.
    // Scheduler admission only consumes already-reserved ingress tokens.
    // Flush/recovery owns the next-state boundary below.  Do not let that
    // synchronous priority signal reach the upstream queue-consume credit:
    // any same-edge accept is discarded with ingress_q in the flush branch.
    wire accept0 = incoming0 && ingress_has_room0;
    wire accept1 = accept0 && incoming1_raw && !uop_serial(queue0_i) &&
        ingress_has_room1;
    assign queue_consume0_o = accept0;
    assign queue_consume1_o = accept1;

    wire [ENTRY_DEPTH-1:0] entry_branch_mask;
    wire [ENTRY_DEPTH-1:0] entry_serial_mask;
    genvar entry_idx;
    generate
        for (entry_idx = 0; entry_idx < ENTRY_DEPTH; entry_idx = entry_idx + 1) begin : g_entry_class
            assign entry_branch_mask[entry_idx] = entry_valid_q[entry_idx] &&
                uop_branch(entry_uop_q[entry_idx]);
            assign entry_serial_mask[entry_idx] = entry_valid_q[entry_idx] &&
                uop_serial(entry_uop_q[entry_idx]);
        end
    endgenerate
    wire [ENTRY_DEPTH-1:0] unresolved_control_mask =
        entry_branch_mask | entry_serial_mask;

    // Performance/DV state is expressed in scheduler terms. These masks
    // describe the live ready window and its operation classes.
    wire [ENTRY_DEPTH-1:0] entry_memory_mask;
    wire [ENTRY_DEPTH-1:0] entry_store_mask;
    wire [ENTRY_DEPTH-1:0] entry_lane_b_only_mask;
    wire [ENTRY_DEPTH-1:0] entry_divrem_mask;
    genvar class_idx;
    generate
        for (class_idx = 0; class_idx < ENTRY_DEPTH; class_idx = class_idx + 1) begin : g_entry_perf_class
            assign entry_memory_mask[class_idx] = entry_valid_q[class_idx] &&
                uop_memory(entry_uop_q[class_idx]);
            assign entry_store_mask[class_idx] = entry_valid_q[class_idx] &&
                uop_store(entry_uop_q[class_idx]);
            assign entry_lane_b_only_mask[class_idx] = entry_valid_q[class_idx] &&
                uop_lane_b_only(entry_uop_q[class_idx]);
            assign entry_divrem_mask[class_idx] = entry_valid_q[class_idx] &&
                uop_divrem(entry_uop_q[class_idx]);
        end
    endgenerate

    wire [ENTRY_DEPTH-1:0] entry_wakeup0;
    wire [ENTRY_DEPTH-1:0] entry_wakeup1;
    generate
        for (entry_idx = 0; entry_idx < ENTRY_DEPTH; entry_idx = entry_idx + 1) begin : g_entry_wakeup
            assign entry_wakeup0[entry_idx] = entry_valid_q[entry_idx] &&
                entry_uop_q[entry_idx].src0.tag_valid &&
                ((completion_meta_i[COMPLETION_ALU].valid &&
                  completion_meta_i[COMPLETION_ALU].producer_tracked &&
                  completion_meta_i[COMPLETION_ALU].producer_id ==
                  entry_uop_q[entry_idx].src0.producer_tag) ||
                 (completion_meta_i[COMPLETION_LSU].valid &&
                  completion_meta_i[COMPLETION_LSU].producer_tracked &&
                  completion_meta_i[COMPLETION_LSU].producer_id ==
                  entry_uop_q[entry_idx].src0.producer_tag) ||
                 (completion_meta_i[COMPLETION_MUL].valid &&
                  completion_meta_i[COMPLETION_MUL].producer_tracked &&
                  completion_meta_i[COMPLETION_MUL].producer_id ==
                  entry_uop_q[entry_idx].src0.producer_tag) ||
                 (completion_meta_i[COMPLETION_DUAL_ALU].valid &&
                  completion_meta_i[COMPLETION_DUAL_ALU].producer_tracked &&
                  completion_meta_i[COMPLETION_DUAL_ALU].producer_id ==
                  entry_uop_q[entry_idx].src0.producer_tag));
            assign entry_wakeup1[entry_idx] = entry_valid_q[entry_idx] &&
                entry_uop_q[entry_idx].src1.tag_valid &&
                ((completion_meta_i[COMPLETION_ALU].valid &&
                  completion_meta_i[COMPLETION_ALU].producer_tracked &&
                  completion_meta_i[COMPLETION_ALU].producer_id ==
                  entry_uop_q[entry_idx].src1.producer_tag) ||
                 (completion_meta_i[COMPLETION_LSU].valid &&
                  completion_meta_i[COMPLETION_LSU].producer_tracked &&
                  completion_meta_i[COMPLETION_LSU].producer_id ==
                  entry_uop_q[entry_idx].src1.producer_tag) ||
                 (completion_meta_i[COMPLETION_MUL].valid &&
                  completion_meta_i[COMPLETION_MUL].producer_tracked &&
                  completion_meta_i[COMPLETION_MUL].producer_id ==
                  entry_uop_q[entry_idx].src1.producer_tag) ||
                 (completion_meta_i[COMPLETION_DUAL_ALU].valid &&
                  completion_meta_i[COMPLETION_DUAL_ALU].producer_tracked &&
                  completion_meta_i[COMPLETION_DUAL_ALU].producer_id ==
                  entry_uop_q[entry_idx].src1.producer_tag));
        end
    endgenerate

    wire [ENTRY_DEPTH-1:0] entry_ready_mask;
    wire [ENTRY_DEPTH-1:0] entry_candidate_mask;
    generate
        for (entry_idx = 0; entry_idx < ENTRY_DEPTH; entry_idx = entry_idx + 1) begin : g_entry_ready
            assign entry_ready_mask[entry_idx] = entry_valid_q[entry_idx] &&
                entry_src0_ready_q[entry_idx] &&
                (entry_src1_ready_q[entry_idx] ||
                 uop_store(entry_uop_q[entry_idx]));
            assign entry_candidate_mask[entry_idx] = entry_candidate_q[entry_idx] &&
                // The registered candidate is invalidated alongside its
                // entry. Bank tokens add a producer-ID check below, so this
                // qualification does not read the remove token combinationally
                // and cannot recreate a selected-mask feedback path.
                entry_valid_q[entry_idx] &&
                (!uop_divrem(entry_uop_q[entry_idx]) ||
                 (!div_issue_q && !div_inflight_q));
        end
    endgenerate

    // Capture all current-cycle qualification one register before select.
    // Divider occupancy is local scheduler state; completion clears it and a
    // selected divide sets it, so no EX reservation/bypass token is needed.
    wire [ENTRY_DEPTH-1:0] entry_candidate_now;
    generate
        for (entry_idx = 0; entry_idx < ENTRY_DEPTH; entry_idx = entry_idx + 1) begin : g_entry_candidate_now
            assign entry_candidate_now[entry_idx] = entry_ready_mask[entry_idx] &&
                !(|(entry_order_q[entry_idx] & entry_valid_q)) &&
                (!uop_divrem(entry_uop_q[entry_idx]) ||
                 (!div_inflight_q && !div_issue_q)) &&
                (!uop_serial(entry_uop_q[entry_idx]) ||
                 ((entry_uop_q[entry_idx].dst.rob_tag == rob_head_id_i) &&
                  lsu_idle_i));
        end
    endgenerate

    // Fixed compare network for each six-entry physical bank.  Every rank is
    // computed from the registered entry state; no found/best accumulator is
    // read after being assigned in the same always_comb block.
    wire [AGE_WIDTH-1:0] bank_age [0:1][0:BANK_DEPTH-1];
    wire [BANK_DEPTH-1:0] bank_mem_candidate [0:1];
    wire [BANK_DEPTH-1:0] bank_alu_candidate [0:1];
    wire [BANK_DEPTH-1:0] bank_bonly_candidate [0:1];
    wire [BANK_DEPTH-1:0] bank_mem_older [0:1][0:BANK_DEPTH-1];
    wire [BANK_DEPTH-1:0] bank_alu_older [0:1][0:BANK_DEPTH-1];
    wire [BANK_DEPTH-1:0] bank_bonly_older [0:1][0:BANK_DEPTH-1];
    wire [BANK_DEPTH-1:0] bank_mem_best [0:1];
    wire [BANK_DEPTH-1:0] bank_alu_best [0:1];
    wire [BANK_DEPTH-1:0] bank_alu_second [0:1];
    wire [BANK_DEPTH-1:0] bank_bonly_best [0:1];
    wire [3:0] bank_alu_rank [0:1][0:BANK_DEPTH-1];
    genvar bank_g, local_g, cmp_g;
    generate
        for (bank_g = 0; bank_g < 2; bank_g = bank_g + 1) begin : g_bank_compare
            for (local_g = 0; local_g < BANK_DEPTH; local_g = local_g + 1) begin : g_bank_entry
                localparam int ENTRY_INDEX = bank_g * BANK_DEPTH + local_g;
                assign bank_age[bank_g][local_g] = producer_age(
                    entry_uop_q[ENTRY_INDEX].dst.rob_tag, rob_head_id_i);
                assign bank_mem_candidate[bank_g][local_g] =
                    entry_candidate_mask[ENTRY_INDEX] &&
                    uop_memory(entry_uop_q[ENTRY_INDEX]);
                assign bank_alu_candidate[bank_g][local_g] =
                    entry_candidate_mask[ENTRY_INDEX] &&
                    !uop_memory(entry_uop_q[ENTRY_INDEX]) &&
                    !uop_lane_b_only(entry_uop_q[ENTRY_INDEX]);
                assign bank_bonly_candidate[bank_g][local_g] =
                    entry_candidate_mask[ENTRY_INDEX] &&
                    uop_lane_b_only(entry_uop_q[ENTRY_INDEX]);
                assign bank_alu_rank[bank_g][local_g] =
                    4'($countones(bank_alu_older[bank_g][local_g]));
                assign bank_mem_best[bank_g][local_g] =
                    bank_mem_candidate[bank_g][local_g] &&
                    !(|bank_mem_older[bank_g][local_g]);
                assign bank_alu_best[bank_g][local_g] =
                    bank_alu_candidate[bank_g][local_g] &&
                    (bank_alu_rank[bank_g][local_g] == 4'd0);
                assign bank_alu_second[bank_g][local_g] =
                    bank_alu_candidate[bank_g][local_g] &&
                    (bank_alu_rank[bank_g][local_g] == 4'd1);
                assign bank_bonly_best[bank_g][local_g] =
                    bank_bonly_candidate[bank_g][local_g] &&
                    !(|bank_bonly_older[bank_g][local_g]);
                for (cmp_g = 0; cmp_g < BANK_DEPTH; cmp_g = cmp_g + 1) begin : g_bank_cmp
                    if (cmp_g == local_g) begin : g_self_compare
                        assign bank_mem_older[bank_g][local_g][cmp_g] = 1'b0;
                        assign bank_alu_older[bank_g][local_g][cmp_g] = 1'b0;
                        assign bank_bonly_older[bank_g][local_g][cmp_g] = 1'b0;
                    end else begin : g_other_compare
                        assign bank_mem_older[bank_g][local_g][cmp_g] =
                            bank_mem_candidate[bank_g][cmp_g] &&
                            ((bank_age[bank_g][cmp_g] < bank_age[bank_g][local_g]) ||
                             ((bank_age[bank_g][cmp_g] == bank_age[bank_g][local_g]) &&
                              (cmp_g < local_g)));
                        assign bank_alu_older[bank_g][local_g][cmp_g] =
                            bank_alu_candidate[bank_g][cmp_g] &&
                            ((bank_age[bank_g][cmp_g] < bank_age[bank_g][local_g]) ||
                             ((bank_age[bank_g][cmp_g] == bank_age[bank_g][local_g]) &&
                              (cmp_g < local_g)));
                        assign bank_bonly_older[bank_g][local_g][cmp_g] =
                            bank_bonly_candidate[bank_g][cmp_g] &&
                            ((bank_age[bank_g][cmp_g] < bank_age[bank_g][local_g]) ||
                             ((bank_age[bank_g][cmp_g] == bank_age[bank_g][local_g]) &&
                              (cmp_g < local_g)));
                    end
                end
            end
        end
    endgenerate
    wire bank_mem_valid_d [0:1];
    wire bank_alu0_valid_d [0:1];
    wire bank_alu1_valid_d [0:1];
    wire bank_bonly_valid_d [0:1];
    producer_slot_t bank_mem_slot_d [0:1];
    producer_slot_t bank_alu0_slot_d [0:1];
    producer_slot_t bank_alu1_slot_d [0:1];
    producer_slot_t bank_bonly_slot_d [0:1];
    producer_id_t bank_mem_id_d [0:1];
    producer_id_t bank_alu0_id_d [0:1];
    producer_id_t bank_alu1_id_d [0:1];
    producer_id_t bank_bonly_id_d [0:1];
    generate
        for (bank_g = 0; bank_g < 2; bank_g = bank_g + 1) begin : g_bank_pick
            assign bank_mem_valid_d[bank_g] = |bank_mem_best[bank_g];
            assign bank_alu0_valid_d[bank_g] = |bank_alu_best[bank_g];
            assign bank_alu1_valid_d[bank_g] = |bank_alu_second[bank_g];
            assign bank_bonly_valid_d[bank_g] = |bank_bonly_best[bank_g];
            assign bank_mem_slot_d[bank_g] = bank_mem_best[bank_g][0] ?
                producer_slot_t'(bank_g * BANK_DEPTH + 0) :
                bank_mem_best[bank_g][1] ? producer_slot_t'(bank_g * BANK_DEPTH + 1) :
                bank_mem_best[bank_g][2] ? producer_slot_t'(bank_g * BANK_DEPTH + 2) :
                bank_mem_best[bank_g][3] ? producer_slot_t'(bank_g * BANK_DEPTH + 3) :
                bank_mem_best[bank_g][4] ? producer_slot_t'(bank_g * BANK_DEPTH + 4) :
                producer_slot_t'(bank_g * BANK_DEPTH + 5);
            assign bank_alu0_slot_d[bank_g] = bank_alu_best[bank_g][0] ?
                producer_slot_t'(bank_g * BANK_DEPTH + 0) :
                bank_alu_best[bank_g][1] ? producer_slot_t'(bank_g * BANK_DEPTH + 1) :
                bank_alu_best[bank_g][2] ? producer_slot_t'(bank_g * BANK_DEPTH + 2) :
                bank_alu_best[bank_g][3] ? producer_slot_t'(bank_g * BANK_DEPTH + 3) :
                bank_alu_best[bank_g][4] ? producer_slot_t'(bank_g * BANK_DEPTH + 4) :
                producer_slot_t'(bank_g * BANK_DEPTH + 5);
            assign bank_alu1_slot_d[bank_g] = bank_alu_second[bank_g][0] ?
                producer_slot_t'(bank_g * BANK_DEPTH + 0) :
                bank_alu_second[bank_g][1] ? producer_slot_t'(bank_g * BANK_DEPTH + 1) :
                bank_alu_second[bank_g][2] ? producer_slot_t'(bank_g * BANK_DEPTH + 2) :
                bank_alu_second[bank_g][3] ? producer_slot_t'(bank_g * BANK_DEPTH + 3) :
                bank_alu_second[bank_g][4] ? producer_slot_t'(bank_g * BANK_DEPTH + 4) :
                producer_slot_t'(bank_g * BANK_DEPTH + 5);
            assign bank_bonly_slot_d[bank_g] = bank_bonly_best[bank_g][0] ?
                producer_slot_t'(bank_g * BANK_DEPTH + 0) :
                bank_bonly_best[bank_g][1] ? producer_slot_t'(bank_g * BANK_DEPTH + 1) :
                bank_bonly_best[bank_g][2] ? producer_slot_t'(bank_g * BANK_DEPTH + 2) :
                bank_bonly_best[bank_g][3] ? producer_slot_t'(bank_g * BANK_DEPTH + 3) :
                bank_bonly_best[bank_g][4] ? producer_slot_t'(bank_g * BANK_DEPTH + 4) :
                producer_slot_t'(bank_g * BANK_DEPTH + 5);
            assign bank_mem_id_d[bank_g] =
                entry_uop_q[bank_mem_slot_d[bank_g]].dst.rob_tag;
            assign bank_alu0_id_d[bank_g] =
                entry_uop_q[bank_alu0_slot_d[bank_g]].dst.rob_tag;
            assign bank_alu1_id_d[bank_g] =
                entry_uop_q[bank_alu1_slot_d[bank_g]].dst.rob_tag;
            assign bank_bonly_id_d[bank_g] =
                entry_uop_q[bank_bonly_slot_d[bank_g]].dst.rob_tag;
        end
    endgenerate

    // Bank-local picks cross an explicit registered boundary before the pair
    // arbiter. A token is live only while its referenced entry remains a
    // current qualified candidate; removal or same-slot reallocation kills
    // stale picks before they can be selected again.
    reg bank_mem_valid_q [0:1];
    reg bank_alu0_valid_q [0:1];
    reg bank_alu1_valid_q [0:1];
    reg bank_bonly_valid_q [0:1];
    producer_slot_t bank_mem_slot_q [0:1];
    producer_slot_t bank_alu0_slot_q [0:1];
    producer_slot_t bank_alu1_slot_q [0:1];
    producer_slot_t bank_bonly_slot_q [0:1];
    producer_id_t bank_mem_id_q [0:1];
    producer_id_t bank_alu0_id_q [0:1];
    producer_id_t bank_alu1_id_q [0:1];
    producer_id_t bank_bonly_id_q [0:1];
    reg bank_mem_live_q [0:1];
    reg bank_alu0_live_q [0:1];
    reg bank_alu1_live_q [0:1];
    reg bank_bonly_live_q [0:1];
    wire bank_mem_live_d [0:1];
    wire bank_alu0_live_d [0:1];
    wire bank_alu1_live_d [0:1];
    wire bank_bonly_live_d [0:1];
    reg [AGE_WIDTH-1:0] bank_mem_age_q [0:1];
    reg [AGE_WIDTH-1:0] bank_alu0_age_q [0:1];
    reg [AGE_WIDTH-1:0] bank_alu1_age_q [0:1];
    reg [AGE_WIDTH-1:0] bank_bonly_age_q [0:1];
    wire [AGE_WIDTH-1:0] bank_mem_age_d [0:1];
    wire [AGE_WIDTH-1:0] bank_alu0_age_d [0:1];
    wire [AGE_WIDTH-1:0] bank_alu1_age_d [0:1];
    wire [AGE_WIDTH-1:0] bank_bonly_age_d [0:1];
    wire bank_mem_valid [0:1];
    wire bank_alu0_valid [0:1];
    wire bank_alu1_valid [0:1];
    wire bank_bonly_valid [0:1];
    producer_slot_t bank_mem_slot [0:1];
    producer_slot_t bank_alu0_slot [0:1];
    producer_slot_t bank_alu1_slot [0:1];
    producer_slot_t bank_bonly_slot [0:1];
    generate
        for (bank_g = 0; bank_g < 2; bank_g = bank_g + 1) begin : g_bank_token
            assign bank_mem_age_d[bank_g] = producer_age(
                entry_uop_q[bank_mem_slot_d[bank_g]].dst.rob_tag, rob_head_id_i);
            assign bank_alu0_age_d[bank_g] = producer_age(
                entry_uop_q[bank_alu0_slot_d[bank_g]].dst.rob_tag, rob_head_id_i);
            assign bank_alu1_age_d[bank_g] = producer_age(
                entry_uop_q[bank_alu1_slot_d[bank_g]].dst.rob_tag, rob_head_id_i);
            assign bank_bonly_age_d[bank_g] = producer_age(
                entry_uop_q[bank_bonly_slot_d[bank_g]].dst.rob_tag, rob_head_id_i);
            // Live is a registered copy of the bank pick. Entry validity and
            // producer identity are checked only when the token is consumed
            // below, keeping the candidate/rank network off this D path.
            assign bank_mem_live_d[bank_g] = bank_mem_valid_d[bank_g];
            assign bank_alu0_live_d[bank_g] = bank_alu0_valid_d[bank_g];
            assign bank_alu1_live_d[bank_g] = bank_alu1_valid_d[bank_g];
            assign bank_bonly_live_d[bank_g] = bank_bonly_valid_d[bank_g];
            assign bank_mem_valid[bank_g] = bank_mem_valid_q[bank_g] &&
                bank_mem_live_q[bank_g] &&
                entry_valid_q[bank_mem_slot_q[bank_g]] &&
                (entry_uop_q[bank_mem_slot_q[bank_g]].dst.rob_tag ==
                 bank_mem_id_q[bank_g]);
            assign bank_alu0_valid[bank_g] = bank_alu0_valid_q[bank_g] &&
                bank_alu0_live_q[bank_g] &&
                entry_valid_q[bank_alu0_slot_q[bank_g]] &&
                (entry_uop_q[bank_alu0_slot_q[bank_g]].dst.rob_tag ==
                 bank_alu0_id_q[bank_g]);
            assign bank_alu1_valid[bank_g] = bank_alu1_valid_q[bank_g] &&
                bank_alu1_live_q[bank_g] &&
                entry_valid_q[bank_alu1_slot_q[bank_g]] &&
                (entry_uop_q[bank_alu1_slot_q[bank_g]].dst.rob_tag ==
                 bank_alu1_id_q[bank_g]);
            assign bank_bonly_valid[bank_g] = bank_bonly_valid_q[bank_g] &&
                bank_bonly_live_q[bank_g] &&
                entry_valid_q[bank_bonly_slot_q[bank_g]] &&
                (entry_uop_q[bank_bonly_slot_q[bank_g]].dst.rob_tag ==
                 bank_bonly_id_q[bank_g]);
            assign bank_mem_slot[bank_g] = bank_mem_slot_q[bank_g];
            assign bank_alu0_slot[bank_g] = bank_alu0_slot_q[bank_g];
            assign bank_alu1_slot[bank_g] = bank_alu1_slot_q[bank_g];
            assign bank_bonly_slot[bank_g] = bank_bonly_slot_q[bank_g];
        end
    endgenerate

    wire [AGE_WIDTH-1:0] bank_mem_age0 = bank_mem_age_q[0];
    wire [AGE_WIDTH-1:0] bank_mem_age1 = bank_mem_age_q[1];
    wire [AGE_WIDTH-1:0] bank_alu0_age0 = bank_alu0_age_q[0];
    wire [AGE_WIDTH-1:0] bank_alu0_age1 = bank_alu0_age_q[1];
    wire any_mem_candidate = bank_mem_valid[0] || bank_mem_valid[1];
    wire any_alu_a_candidate = bank_alu0_valid[0] || bank_alu0_valid[1];
    wire mem_bank0_wins = bank_mem_valid[0] &&
        (!bank_mem_valid[1] || (bank_mem_age0 <= bank_mem_age1));
    wire alu_bank0_wins = bank_alu0_valid[0] &&
        (!bank_alu0_valid[1] || (bank_alu0_age0 <= bank_alu0_age1));
    wire selected_a_valid = any_mem_candidate || any_alu_a_candidate;
    wire producer_slot_t selected_a_slot = any_mem_candidate ?
        (mem_bank0_wins ? bank_mem_slot[0] : bank_mem_slot[1]) :
        (alu_bank0_wins ? bank_alu0_slot[0] : bank_alu0_slot[1]);
    wire producer_id_t selected_a_id;
    assign selected_a_id = entry_uop_q[selected_a_slot].dst.rob_tag;

    // Bank A arbitration is its own registered decision. The B arbiter only
    // consumes this identity-qualified token, so a cross-bank A age compare
    // cannot extend into the B rank/selection path.
    reg pair_a_valid_q;
    producer_slot_t pair_a_slot_q;
    producer_id_t pair_a_id_q;
    wire pair_a_live_q = pair_a_valid_q &&
        entry_valid_q[pair_a_slot_q] &&
        (entry_uop_q[pair_a_slot_q].dst.rob_tag == pair_a_id_q);

    wire b_bonly0_valid = bank_bonly_valid[0] &&
        (!pair_a_live_q || (bank_bonly_slot[0] != pair_a_slot_q));
    wire b_bonly1_valid = bank_bonly_valid[1] &&
        (!pair_a_live_q || (bank_bonly_slot[1] != pair_a_slot_q));
    wire [AGE_WIDTH-1:0] b_bonly_age0 = bank_bonly_age_q[0];
    wire [AGE_WIDTH-1:0] b_bonly_age1 = bank_bonly_age_q[1];
    wire b_bonly_any = b_bonly0_valid || b_bonly1_valid;
    wire b_bonly0_wins = b_bonly0_valid &&
        (!b_bonly1_valid || (b_bonly_age0 <= b_bonly_age1));
    wire producer_slot_t b_bonly_slot_winner = b_bonly0_wins ?
        bank_bonly_slot[0] : bank_bonly_slot[1];

    wire [3:0] b_alu_valid;
    wire producer_slot_t b_alu_slot [0:3];
    wire [AGE_WIDTH-1:0] b_alu_age [0:3];
    assign b_alu_valid[0] = bank_alu0_valid[0] &&
        (!pair_a_live_q || (bank_alu0_slot[0] != pair_a_slot_q));
    assign b_alu_valid[1] = bank_alu1_valid[0] &&
        (!pair_a_live_q || (bank_alu1_slot[0] != pair_a_slot_q));
    assign b_alu_valid[2] = bank_alu0_valid[1] &&
        (!pair_a_live_q || (bank_alu0_slot[1] != pair_a_slot_q));
    assign b_alu_valid[3] = bank_alu1_valid[1] &&
        (!pair_a_live_q || (bank_alu1_slot[1] != pair_a_slot_q));
    assign b_alu_slot[0] = bank_alu0_slot[0];
    assign b_alu_slot[1] = bank_alu1_slot[0];
    assign b_alu_slot[2] = bank_alu0_slot[1];
    assign b_alu_slot[3] = bank_alu1_slot[1];
    assign b_alu_age[0] = bank_alu0_age_q[0];
    assign b_alu_age[1] = bank_alu1_age_q[0];
    assign b_alu_age[2] = bank_alu0_age_q[1];
    assign b_alu_age[3] = bank_alu1_age_q[1];
    wire [3:0] b_alu_best;
    assign b_alu_best[0] = b_alu_valid[0] &&
        !( (b_alu_valid[1] && (b_alu_age[1] < b_alu_age[0])) ||
           (b_alu_valid[2] && (b_alu_age[2] < b_alu_age[0])) ||
           (b_alu_valid[3] && (b_alu_age[3] < b_alu_age[0])) );
    assign b_alu_best[1] = b_alu_valid[1] &&
        !( (b_alu_valid[0] && (b_alu_age[0] <= b_alu_age[1])) ||
           (b_alu_valid[2] && (b_alu_age[2] < b_alu_age[1])) ||
           (b_alu_valid[3] && (b_alu_age[3] < b_alu_age[1])) );
    assign b_alu_best[2] = b_alu_valid[2] &&
        !( (b_alu_valid[0] && (b_alu_age[0] <= b_alu_age[2])) ||
           (b_alu_valid[1] && (b_alu_age[1] <= b_alu_age[2])) ||
           (b_alu_valid[3] && (b_alu_age[3] < b_alu_age[2])) );
    assign b_alu_best[3] = b_alu_valid[3] &&
        !( (b_alu_valid[0] && (b_alu_age[0] <= b_alu_age[3])) ||
           (b_alu_valid[1] && (b_alu_age[1] <= b_alu_age[3])) ||
           (b_alu_valid[2] && (b_alu_age[2] <= b_alu_age[3])) );
    wire b_alu_any = |b_alu_best;
    wire producer_slot_t b_alu_slot_winner = b_alu_best[0] ? b_alu_slot[0] :
        b_alu_best[1] ? b_alu_slot[1] : b_alu_best[2] ? b_alu_slot[2] :
        b_alu_slot[3];
    wire selected_b_valid = b_bonly_any || b_alu_any;
    wire producer_slot_t selected_b_slot = b_bonly_any ?
        b_bonly_slot_winner : b_alu_slot_winner;
    wire producer_id_t selected_b_id;
    assign selected_b_id = entry_uop_q[selected_b_slot].dst.rob_tag;
    // Registered selection tokens feed the independent lane input cells.
    // Their producer identities remain separate from the later release tokens:
    // a physical slot can be reallocated before another bank/pair selection
    // reaches this stage.
    reg selected_a_valid_q;
    reg selected_b_valid_q;
    producer_slot_t selected_a_slot_q;
    producer_slot_t selected_b_slot_q;
    producer_id_t selected_a_id_q;
    producer_id_t selected_b_id_q;

    // Pair tokens are identity-qualified until their lane input register
    // captures the uop. This rejects a stale slot after a remove/reallocate
    // edge without making the lane input depend on scheduler selection.
    wire selected_a_token_live_q = selected_a_valid_q &&
        entry_valid_q[selected_a_slot_q] &&
        (entry_uop_q[selected_a_slot_q].dst.rob_tag == selected_a_id_q);
    wire selected_b_token_live_q = selected_b_valid_q &&
        entry_valid_q[selected_b_slot_q] &&
        (entry_uop_q[selected_b_slot_q].dst.rob_tag == selected_b_id_q);
    // A release token is created only when its lane input register captures a
    // selected uop.  Keep the producer ID alongside the physical slot so a
    // same-edge release/reallocate cannot remove the new occupant on the next
    // cycle.  The identity-qualified mask is the sole source of scheduler
    // free credit, state removal, and the externally visible remove event.
    reg release_a_valid_q;
    reg release_b_valid_q;
    producer_slot_t release_a_slot_q;
    producer_slot_t release_b_slot_q;
    producer_id_t release_a_id_q;
    producer_id_t release_b_id_q;
    wire release_a_live_q = release_a_valid_q &&
        entry_valid_q[release_a_slot_q] &&
        (entry_uop_q[release_a_slot_q].dst.rob_tag == release_a_id_q);
    wire release_b_live_q = release_b_valid_q &&
        entry_valid_q[release_b_slot_q] &&
        (entry_uop_q[release_b_slot_q].dst.rob_tag == release_b_id_q);
    wire selected_a_release_pending_q =
        ((release_a_valid_q && (release_a_slot_q == selected_a_slot_q) &&
          (release_a_id_q == selected_a_id_q)) ||
         (release_b_valid_q && (release_b_slot_q == selected_a_slot_q) &&
          (release_b_id_q == selected_a_id_q)));
    wire selected_b_release_pending_q =
        ((release_a_valid_q && (release_a_slot_q == selected_b_slot_q) &&
          (release_a_id_q == selected_b_id_q)) ||
         (release_b_valid_q && (release_b_slot_q == selected_b_slot_q) &&
          (release_b_id_q == selected_b_id_q)));
    // A pair token can remain resident in a bank token register until the
    // release edge reaches the entry array. Fire it once, when the lane input
    // captures it. The B guard is defensive: pair arbitration should already
    // avoid an A/B alias, but a staged token must never duplicate execution.
    wire selected_a_token_fire_q = selected_a_token_live_q &&
        !selected_a_release_pending_q;
    wire selected_b_token_fire_q = selected_b_token_live_q &&
        !selected_b_release_pending_q &&
        !(selected_a_token_fire_q &&
          (selected_a_slot_q == selected_b_slot_q));
    wire [ENTRY_DEPTH-1:0] selected_mask_q =
        (release_a_live_q ? (ENTRY_DEPTH'(1) << release_a_slot_q) : '0) |
        (release_b_live_q ? (ENTRY_DEPTH'(1) << release_b_slot_q) : '0);

    // Recovery is a simultaneous survivor filter for the scheduler window.
    // Build the post-recovery control set from producer identity and the
    // selected/release mask, rather than from the pre-edge entry_valid_q.  An
    // order token may only point at a control uop that remains live after the
    // redirect; otherwise a stale dependency bit can permanently suppress a
    // ready survivor from the bank candidate network.
    wire [ENTRY_DEPTH-1:0] recovery_survivor_mask;
    wire [ENTRY_DEPTH-1:0] recovery_live_control_mask;
    genvar recovery_entry_idx;
    generate
        for (recovery_entry_idx = 0; recovery_entry_idx < ENTRY_DEPTH;
             recovery_entry_idx = recovery_entry_idx + 1) begin : g_recovery_order_mask
            wire recovery_entry_in_window =
                producer_slot_in_window(
                    entry_uop_q[recovery_entry_idx].dst.rob_tag[
                        PRODUCER_SLOT_WIDTH-1:0],
                    recovery_head_slot_i, recovery_branch_slot_i);
            assign recovery_survivor_mask[recovery_entry_idx] =
                entry_valid_q[recovery_entry_idx] &&
                recovery_entry_in_window &&
                (entry_uop_q[recovery_entry_idx].dst.rob_tag[
                    PRODUCER_SLOT_WIDTH-1:0] != recovery_branch_slot_i) &&
                !selected_mask_q[recovery_entry_idx];
            assign recovery_live_control_mask[recovery_entry_idx] =
                recovery_survivor_mask[recovery_entry_idx] &&
                (uop_branch(entry_uop_q[recovery_entry_idx]) ||
                 uop_serial(entry_uop_q[recovery_entry_idx]));
        end
    endgenerate

    wire [ENTRY_DEPTH-1:0] issue_remove_mask = selected_mask_q;
    assign issue_remove_mask_o = issue_remove_mask;
    // Downstream Issue/EX registers have synchronous flush priority. Keep
    // redirect control out of the lane data-valid cone; recovery clears the
    // registered lane tokens at the edge instead of gating their outputs.
    assign lane_a_valid_o = lane_a_valid_q;
    assign lane_b_valid_o = lane_b_valid_q;
    // Keep the compact payload's valid bit aligned with the independent lane
    // token. Without this boundary an idle lane could expose a stale
    // producer tag while lane_*_valid_o=0.
    assign lane_a_uop_o = lane_a_valid_o ? lane_a_uop_q : '0;
    assign lane_b_uop_o = lane_b_valid_o ? lane_b_uop_q : '0;

    assign lookup_valid_o = ({2'b0, ingress_count_q} != '0);
    assign lookup_tag0_o = ingress_q[0].src0.producer_tag;
    assign lookup_tag1_o = ingress_q[0].src1.producer_tag;
    assign lookup_tag2_o = ingress_q[1].src0.producer_tag;
    assign lookup_tag3_o = ingress_q[1].src1.producer_tag;

    // A lane register is a real elastic handoff.  The current six-stage
    // execute adapter consumes both registers every cycle, but the valid bits
    // remain independent and recovery can discard either lane without a
    // independent lane registers.
    reg lane_a_valid_q;
    reg lane_b_valid_q;
    ydrasil_compact_uop_t lane_a_uop_q;
    ydrasil_compact_uop_t lane_b_uop_q;
    // Divider reservation is derived only from the registered lane-B input
    // cell.  This keeps the long bank-age/pair compare network out of the
    // divider control path while preserving the issue-to-inflight identity.
    wire lane_b_div_valid = lane_b_valid_q && uop_divrem(lane_b_uop_q);
    wire producer_id_t lane_b_div_id = lane_b_uop_q.dst.rob_tag;
    // During the one-cycle handoff from lane token to issue token, either
    // token can be the only visible reservation. Recovery must classify that
    // token by producer identity before deciding whether the physical MDU
    // state may survive the redirect.
    wire div_reservation_valid = div_inflight_q || div_issue_q ||
        lane_b_div_valid;
    wire producer_id_t div_reservation_id = div_inflight_q ? div_inflight_id_q :
        div_issue_q ? div_issue_id_q : lane_b_div_id;
    wire div_reservation_survives_recovery = div_reservation_valid &&
        producer_slot_in_window(
            div_reservation_id[PRODUCER_SLOT_WIDTH-1:0],
            recovery_head_slot_i, recovery_branch_slot_i) &&
        (div_reservation_id[PRODUCER_SLOT_WIDTH-1:0] !=
         recovery_branch_slot_i);
    wire free_any = |(~entry_valid_q | selected_mask_q);
    wire free_two = ($countones(~entry_valid_q | selected_mask_q) >= 2);
    reg [PRODUCER_SLOT_WIDTH-1:0] alloc_slot0_d;
    reg [PRODUCER_SLOT_WIDTH-1:0] alloc_slot1_d;
    reg alloc_slot0_valid_d;
    reg alloc_slot1_valid_d;
    integer free_scan;
    always_comb begin
        alloc_slot0_d = '0;
        alloc_slot1_d = '0;
        alloc_slot0_valid_d = 1'b0;
        alloc_slot1_valid_d = 1'b0;
        for (free_scan = 0; free_scan < ENTRY_DEPTH; free_scan = free_scan + 1) begin
            if ((!entry_valid_q[free_scan] || selected_mask_q[free_scan]) &&
                !alloc_slot0_valid_d) begin
                alloc_slot0_d = producer_slot_t'(free_scan);
                alloc_slot0_valid_d = 1'b1;
            end else if ((!entry_valid_q[free_scan] || selected_mask_q[free_scan]) &&
                         !alloc_slot1_valid_d) begin
                alloc_slot1_d = producer_slot_t'(free_scan);
                alloc_slot1_valid_d = 1'b1;
            end
        end
    end
    // As with queue acceptance, recovery discards this edge's drain in the
    // synchronous priority branch.  Keeping it local removes redirect/trap
    // control from the bank-free credit and allocation-select cone.
    wire drain0 = ingress_count_q != '0 && alloc_slot0_valid_d;
    wire drain1 = ingress_count_q > 1 && alloc_slot1_valid_d;
    reg [INGRESS_COUNT_WIDTH-1:0] ingress_count_d;
    ydrasil_compact_uop_t ingress0_d;
    ydrasil_compact_uop_t ingress1_d;
    always_comb begin
        ingress_count_d = ingress_count_q;
        ingress0_d = ingress_q[0];
        ingress1_d = ingress_q[1];
        if (drain1) begin
            ingress_count_d = ingress_count_d - 2'd2;
            ingress0_d = '0;
            ingress1_d = '0;
        end else if (drain0) begin
            ingress_count_d = ingress_count_d - 1'b1;
            ingress0_d = ingress_count_q > 1 ? ingress_q[1] : '0;
            ingress1_d = '0;
        end
        if (accept0) begin
            if (ingress_count_d == 0)
                ingress0_d = queue0_i;
            else
                ingress1_d = queue0_i;
            ingress_count_d = ingress_count_d + 1'b1;
        end
        if (accept1) begin
            if (ingress_count_d == 0)
                ingress0_d = queue1_i;
            else
                ingress1_d = queue1_i;
            ingress_count_d = ingress_count_d + 1'b1;
        end
    end

    reg new_src0_ready0;
    reg new_src1_ready0;
    reg new_src0_ready1;
    reg new_src1_ready1;
    integer wake_scan;
    always_comb begin
        new_src0_ready0 = !ingress_q[0].src0.tag_valid ||
            ingress_q[0].src0.ready || lookup_resident0_i ||
            (ingress_q[0].src0.tag_valid && lookup_reallocated0_i);
        new_src1_ready0 = !ingress_q[0].src1.tag_valid ||
            ingress_q[0].src1.ready || lookup_resident1_i ||
            (ingress_q[0].src1.tag_valid && lookup_reallocated1_i);
        new_src0_ready1 = !ingress_q[1].src0.tag_valid ||
            ingress_q[1].src0.ready || lookup_resident2_i ||
            (ingress_q[1].src0.tag_valid && lookup_reallocated2_i);
        new_src1_ready1 = !ingress_q[1].src1.tag_valid ||
            ingress_q[1].src1.ready || lookup_resident3_i ||
            (ingress_q[1].src1.tag_valid && lookup_reallocated3_i);
        for (wake_scan = 0; wake_scan < COMPLETION_LANES; wake_scan = wake_scan + 1) begin
            if (completion_meta_i[wake_scan].valid &&
                completion_meta_i[wake_scan].producer_tracked) begin
                new_src0_ready0 = new_src0_ready0 ||
                    (ingress_q[0].src0.producer_tag ==
                     completion_meta_i[wake_scan].producer_id);
                new_src1_ready0 = new_src1_ready0 ||
                    (ingress_q[0].src1.producer_tag ==
                     completion_meta_i[wake_scan].producer_id);
                new_src0_ready1 = new_src0_ready1 ||
                    (ingress_q[1].src0.producer_tag ==
                     completion_meta_i[wake_scan].producer_id);
                new_src1_ready1 = new_src1_ready1 ||
                    (ingress_q[1].src1.producer_tag ==
                     completion_meta_i[wake_scan].producer_id);
            end
        end
    end

    wire [ENTRY_DEPTH-1:0] order_base_mask =
        unresolved_control_mask & ~selected_mask_q;
    integer state_idx;
    integer bank_state_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ingress_count_q <= '0;
            ingress_q[0] <= '0;
            ingress_q[1] <= '0;
            entry_valid_q <= '0;
            lane_a_valid_q <= 1'b0;
            lane_b_valid_q <= 1'b0;
            lane_a_uop_q <= '0;
            lane_b_uop_q <= '0;
            pair_a_valid_q <= 1'b0;
            pair_a_slot_q <= '0;
            pair_a_id_q <= '0;
            selected_a_valid_q <= 1'b0;
            selected_b_valid_q <= 1'b0;
            selected_a_slot_q <= '0;
            selected_b_slot_q <= '0;
            selected_a_id_q <= '0;
            selected_b_id_q <= '0;
            release_a_valid_q <= 1'b0;
            release_b_valid_q <= 1'b0;
            release_a_slot_q <= '0;
            release_b_slot_q <= '0;
            release_a_id_q <= '0;
            release_b_id_q <= '0;
            entry_candidate_q <= '0;
            div_issue_q <= 1'b0;
            div_issue_id_q <= '0;
            div_inflight_q <= 1'b0;
            div_inflight_id_q <= '0;
            for (bank_state_idx = 0; bank_state_idx < 2;
                 bank_state_idx = bank_state_idx + 1) begin
                bank_mem_valid_q[bank_state_idx] <= 1'b0;
                bank_alu0_valid_q[bank_state_idx] <= 1'b0;
                bank_alu1_valid_q[bank_state_idx] <= 1'b0;
                bank_bonly_valid_q[bank_state_idx] <= 1'b0;
                bank_mem_slot_q[bank_state_idx] <= '0;
                bank_alu0_slot_q[bank_state_idx] <= '0;
                bank_alu1_slot_q[bank_state_idx] <= '0;
                bank_bonly_slot_q[bank_state_idx] <= '0;
                bank_mem_id_q[bank_state_idx] <= '0;
                bank_alu0_id_q[bank_state_idx] <= '0;
                bank_alu1_id_q[bank_state_idx] <= '0;
                bank_bonly_id_q[bank_state_idx] <= '0;
                bank_mem_live_q[bank_state_idx] <= 1'b0;
                bank_alu0_live_q[bank_state_idx] <= 1'b0;
                bank_alu1_live_q[bank_state_idx] <= 1'b0;
                bank_bonly_live_q[bank_state_idx] <= 1'b0;
                bank_mem_age_q[bank_state_idx] <= '0;
                bank_alu0_age_q[bank_state_idx] <= '0;
                bank_alu1_age_q[bank_state_idx] <= '0;
                bank_bonly_age_q[bank_state_idx] <= '0;
            end
            for (state_idx = 0; state_idx < ENTRY_DEPTH; state_idx = state_idx + 1) begin
                entry_uop_q[state_idx] <= '0;
                entry_src0_ready_q[state_idx] <= 1'b0;
                entry_src1_ready_q[state_idx] <= 1'b0;
                entry_order_q[state_idx] <= '0;
            end
        end else if (hard_flush_i || branch_recovery_i) begin
            ingress_count_q <= '0;
            ingress_q[0] <= '0;
            ingress_q[1] <= '0;
            lane_a_valid_q <= 1'b0;
            lane_b_valid_q <= 1'b0;
            pair_a_valid_q <= 1'b0;
            pair_a_slot_q <= '0;
            pair_a_id_q <= '0;
            selected_a_valid_q <= 1'b0;
            selected_b_valid_q <= 1'b0;
            selected_a_slot_q <= '0;
            selected_b_slot_q <= '0;
            selected_a_id_q <= '0;
            selected_b_id_q <= '0;
            release_a_valid_q <= 1'b0;
            release_b_valid_q <= 1'b0;
            release_a_slot_q <= '0;
            release_b_slot_q <= '0;
            release_a_id_q <= '0;
            release_b_id_q <= '0;
            entry_candidate_q <= '0;
            div_issue_q <= 1'b0;
            div_issue_id_q <= '0;
            if (hard_flush_i || !div_reservation_survives_recovery) begin
                div_inflight_q <= 1'b0;
                div_inflight_id_q <= '0;
            end else if (completion_meta_i[COMPLETION_MUL].valid &&
                         div_reservation_valid &&
                         (completion_meta_i[COMPLETION_MUL].producer_id ==
                          div_reservation_id)) begin
                // A completion concurrent with redirect still retires the
                // older divide; producer_tracked is intentionally ignored so
                // rd=x0 DIV cannot leave occupancy stuck.
                div_inflight_q <= 1'b0;
                div_inflight_id_q <= '0;
            end else begin
                // Carry a survivor forward even when recovery occurs during
                // the registered lane-to-issue handoff. Without this update
                // the physical MDU may remain live while scheduler occupancy
                // is cleared for one cycle.
                div_inflight_q <= 1'b1;
                div_inflight_id_q <= div_reservation_id;
            end
            for (bank_state_idx = 0; bank_state_idx < 2;
                 bank_state_idx = bank_state_idx + 1) begin
                bank_mem_valid_q[bank_state_idx] <= 1'b0;
                bank_alu0_valid_q[bank_state_idx] <= 1'b0;
                bank_alu1_valid_q[bank_state_idx] <= 1'b0;
                bank_bonly_valid_q[bank_state_idx] <= 1'b0;
                bank_mem_slot_q[bank_state_idx] <= '0;
                bank_alu0_slot_q[bank_state_idx] <= '0;
                bank_alu1_slot_q[bank_state_idx] <= '0;
                bank_bonly_slot_q[bank_state_idx] <= '0;
                bank_mem_id_q[bank_state_idx] <= '0;
                bank_alu0_id_q[bank_state_idx] <= '0;
                bank_alu1_id_q[bank_state_idx] <= '0;
                bank_bonly_id_q[bank_state_idx] <= '0;
                bank_mem_live_q[bank_state_idx] <= 1'b0;
                bank_alu0_live_q[bank_state_idx] <= 1'b0;
                bank_alu1_live_q[bank_state_idx] <= 1'b0;
                bank_bonly_live_q[bank_state_idx] <= 1'b0;
                bank_mem_age_q[bank_state_idx] <= '0;
                bank_alu0_age_q[bank_state_idx] <= '0;
                bank_alu1_age_q[bank_state_idx] <= '0;
                bank_bonly_age_q[bank_state_idx] <= '0;
            end
            for (state_idx = 0; state_idx < ENTRY_DEPTH; state_idx = state_idx + 1) begin
                // The redirecting branch is already executed and remains in
                // the ROB for precise in-order retirement, but it must not be
                // reinserted into the scheduler.  producer_slot_in_window is
                // intentionally inclusive for ROB/LSQ recovery, so exclude
                // the branch slot explicitly at this scheduler boundary.
                // selected_mask_q is identity-qualified and denotes a uop
                // already captured by a lane cell; recovery leaves that uop
                // to the downstream recovery path rather than reinserting it.
                if (entry_valid_q[state_idx] &&
                    producer_slot_in_window(
                        entry_uop_q[state_idx].dst.rob_tag[
                            PRODUCER_SLOT_WIDTH-1:0],
                        recovery_head_slot_i, recovery_branch_slot_i) &&
                    (entry_uop_q[state_idx].dst.rob_tag[
                        PRODUCER_SLOT_WIDTH-1:0] != recovery_branch_slot_i) &&
                    !selected_mask_q[state_idx]) begin
                    entry_order_q[state_idx] <= entry_order_q[state_idx] &
                        recovery_live_control_mask;
                end else begin
                    entry_valid_q[state_idx] <= 1'b0;
                    entry_order_q[state_idx] <= '0;
                end
            end
        end else begin
            pair_a_valid_q <= selected_a_valid;
            pair_a_slot_q <= selected_a_slot;
            pair_a_id_q <= selected_a_valid ? selected_a_id : '0;
            selected_a_valid_q <= pair_a_live_q;
            selected_b_valid_q <= selected_b_valid;
            selected_a_slot_q <= pair_a_slot_q;
            selected_b_slot_q <= selected_b_slot;
            selected_a_id_q <= pair_a_live_q ? pair_a_id_q : '0;
            selected_b_id_q <= selected_b_valid ? selected_b_id : '0;
            release_a_valid_q <= selected_a_token_fire_q;
            release_b_valid_q <= selected_b_token_fire_q;
            release_a_slot_q <= selected_a_slot_q;
            release_b_slot_q <= selected_b_slot_q;
            release_a_id_q <= selected_a_token_fire_q ? selected_a_id_q : '0;
            release_b_id_q <= selected_b_token_fire_q ? selected_b_id_q : '0;
            div_issue_q <= lane_b_div_valid;
            div_issue_id_q <= lane_b_div_valid ? lane_b_div_id : '0;
            if (completion_meta_i[COMPLETION_MUL].valid &&
                div_inflight_q &&
                (completion_meta_i[COMPLETION_MUL].producer_id ==
                 div_inflight_id_q)) begin
                div_inflight_q <= div_issue_q;
                div_inflight_id_q <= div_issue_q ? div_issue_id_q : '0;
            end else if (div_issue_q || lane_b_div_valid) begin
                div_inflight_q <= 1'b1;
                div_inflight_id_q <= div_issue_q ? div_issue_id_q :
                    lane_b_div_id;
            end
            for (bank_state_idx = 0; bank_state_idx < 2;
                 bank_state_idx = bank_state_idx + 1) begin
                bank_mem_valid_q[bank_state_idx] <= bank_mem_valid_d[bank_state_idx];
                bank_alu0_valid_q[bank_state_idx] <= bank_alu0_valid_d[bank_state_idx];
                bank_alu1_valid_q[bank_state_idx] <= bank_alu1_valid_d[bank_state_idx];
                bank_bonly_valid_q[bank_state_idx] <= bank_bonly_valid_d[bank_state_idx];
                bank_mem_slot_q[bank_state_idx] <= bank_mem_slot_d[bank_state_idx];
                bank_alu0_slot_q[bank_state_idx] <= bank_alu0_slot_d[bank_state_idx];
                bank_alu1_slot_q[bank_state_idx] <= bank_alu1_slot_d[bank_state_idx];
                bank_bonly_slot_q[bank_state_idx] <= bank_bonly_slot_d[bank_state_idx];
                bank_mem_id_q[bank_state_idx] <= bank_mem_id_d[bank_state_idx];
                bank_alu0_id_q[bank_state_idx] <= bank_alu0_id_d[bank_state_idx];
                bank_alu1_id_q[bank_state_idx] <= bank_alu1_id_d[bank_state_idx];
                bank_bonly_id_q[bank_state_idx] <= bank_bonly_id_d[bank_state_idx];
                bank_mem_live_q[bank_state_idx] <= bank_mem_live_d[bank_state_idx];
                bank_alu0_live_q[bank_state_idx] <= bank_alu0_live_d[bank_state_idx];
                bank_alu1_live_q[bank_state_idx] <= bank_alu1_live_d[bank_state_idx];
                bank_bonly_live_q[bank_state_idx] <= bank_bonly_live_d[bank_state_idx];
                bank_mem_age_q[bank_state_idx] <= bank_mem_age_d[bank_state_idx];
                bank_alu0_age_q[bank_state_idx] <= bank_alu0_age_d[bank_state_idx];
                bank_alu1_age_q[bank_state_idx] <= bank_alu1_age_d[bank_state_idx];
                bank_bonly_age_q[bank_state_idx] <= bank_bonly_age_d[bank_state_idx];
            end
            ingress_count_q <= ingress_count_d;
            ingress_q[0] <= ingress0_d;
            ingress_q[1] <= ingress1_d;
            if (selected_a_token_fire_q) begin
                lane_a_uop_q <= entry_uop_q[selected_a_slot_q];
                lane_a_uop_q.valid <= 1'b1;
                lane_a_uop_q.lane_mask <= 2'b01;
                lane_a_valid_q <= 1'b1;
            end else
                lane_a_valid_q <= 1'b0;
            if (selected_b_token_fire_q) begin
                lane_b_uop_q <= entry_uop_q[selected_b_slot_q];
                lane_b_uop_q.valid <= 1'b1;
                lane_b_uop_q.lane_mask <= 2'b10;
                lane_b_valid_q <= 1'b1;
            end else
                lane_b_valid_q <= 1'b0;

            for (state_idx = 0; state_idx < ENTRY_DEPTH; state_idx = state_idx + 1) begin
                if (entry_valid_q[state_idx]) begin
                    if (entry_wakeup0[state_idx])
                        entry_src0_ready_q[state_idx] <= 1'b1;
                    if (entry_wakeup1[state_idx])
                        entry_src1_ready_q[state_idx] <= 1'b1;
                    entry_order_q[state_idx] <= entry_order_q[state_idx] &
                        ~selected_mask_q;
                    if (selected_mask_q[state_idx])
                        entry_valid_q[state_idx] <= 1'b0;
                    if (selected_mask_q[state_idx])
                        entry_candidate_q[state_idx] <= 1'b0;
                    else
                        entry_candidate_q[state_idx] <= entry_candidate_now[state_idx];
                end else begin
                    entry_candidate_q[state_idx] <= 1'b0;
                end
                if (drain0 && producer_slot_t'(state_idx) == alloc_slot0_d) begin
                    entry_uop_q[state_idx] <= ingress_q[0];
                    entry_valid_q[state_idx] <= 1'b1;
                    entry_src0_ready_q[state_idx] <= new_src0_ready0;
                    entry_src1_ready_q[state_idx] <= new_src1_ready0;
                    entry_candidate_q[state_idx] <= 1'b0;
                    entry_order_q[state_idx] <=
                        (uop_branch(ingress_q[0]) || uop_serial(ingress_q[0])) ?
                        order_base_mask : order_base_mask;
                end
                if (drain1 && producer_slot_t'(state_idx) == alloc_slot1_d) begin
                    entry_uop_q[state_idx] <= ingress_q[1];
                    entry_valid_q[state_idx] <= 1'b1;
                    entry_src0_ready_q[state_idx] <= new_src0_ready1;
                    entry_src1_ready_q[state_idx] <= new_src1_ready1;
                    entry_candidate_q[state_idx] <= 1'b0;
                    entry_order_q[state_idx] <= order_base_mask;
                end
            end
        end
    end
endmodule

module ydrasil_dual_alu
import ydrasil_pkg::*;
(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           flush_i,
    input  wire                           interrupt_i,
    input  wire                           alu_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0]     alu_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]     alu_operand_b_i,
    input  wire [UOP_SUBOP_WIDTH-1:0]     alu_subop_i,
    input  wire                           bit_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0]     bit_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]     bit_operand_b_i,
    input  wire [UOP_SUBOP_WIDTH-1:0]     bit_subop_i,
    input  wire                           bru_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0]     branch_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]     branch_operand_b_i,
    input  wire [REGS_DATA_WIDTH-1:0]     branch_imm_i,
    input  wire [UOP_SUBOP_WIDTH-1:0]     bru_subop_i,
    input  wire [REGS_ADDR_WIDTH-1:0]     rd_addr_i,
    input  wire                           rd_wen_i,
    input  producer_id_t                  producer_id_i,
    input  wire                           producer_tracked_i,
    input  wire [INST_ADDR_WIDTH-1:0]     pc_i,
    input  wire [INST_DATA_WIDTH-1:0]     instr_i,
    input  wire                           jalr_i,
    input  wire [INST_ADDR_WIDTH-1:0]     branch_target_i,
    input  wire [INST_ADDR_WIDTH-1:0]     branch_next_pc_i,
    input  wire                           pred_hit_i,
    input  wire                           pred_taken_i,
    input  wire [INST_ADDR_WIDTH-1:0]     pred_target_i,
    input  wire [1:0]                     pred_counter_i,
    input  bp_bht_index_t                 pred_bht_index_i,
    input  wire [INST_ADDR_WIDTH-1:0]     trap_redirect_addr_i,
    output wire                           completion_valid_o,
    output producer_id_t                  completion_producer_id_o,
    output wire                           completion_producer_tracked_o,
    output wire [REGS_ADDR_WIDTH-1:0]     completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]     completion_data_o,
    output wire                           ex_branch_jump_o,
    output wire [INST_ADDR_WIDTH-1:0]     ex_branch_target_o,
    output wire                           ex_pc_redirect_o,
    output wire [INST_ADDR_WIDTH-1:0]     ex_pc_redirect_target_o,
    output ydrasil_bp_train_pkt_t         ex_bp_train_o,
    output wire                           ex_branch_mispredict_o,
    output wire                           instret_valid_o,
    output wire [INST_ADDR_WIDTH-1:0]     commit_pc_o,
    output wire [INST_DATA_WIDTH-1:0]     commit_instr_o
`ifndef SYNTHESIS
    ,output wire                          dbg_bp_resolve_valid_o
    ,output wire [INST_ADDR_WIDTH-1:0]    dbg_bp_resolve_pc_o
    ,output wire                          dbg_bp_actual_taken_o
    ,output wire [INST_ADDR_WIDTH-1:0]    dbg_bp_actual_target_o
    ,output wire [INST_ADDR_WIDTH-1:0]    dbg_bp_actual_next_pc_o
    ,output wire                          dbg_bp_pred_hit_o
    ,output wire                          dbg_bp_pred_taken_o
    ,output wire [INST_ADDR_WIDTH-1:0]    dbg_bp_pred_target_o
    ,output wire [1:0]                    dbg_bp_pred_counter_o
    ,output wire [INST_ADDR_WIDTH-1:0]    dbg_bp_pred_next_pc_o
    ,output wire                          dbg_bp_mispredict_o
`endif
);
    reg valid_q;
    reg [INST_ADDR_WIDTH-1:0] pc_q;
    reg [INST_DATA_WIDTH-1:0] instr_q;
    logic [OPERATOR_WIDTH-1:0] alu_operator;
    logic [OPERATOR_WIDTH-1:0] bit_operator;
    logic [OPERATOR_WIDTH-1:0] bru_operator;
    logic [OPERATOR_TYPE_WIDTH-1:0] alu_operator_type;
    logic [OPERATOR_TYPE_WIDTH-1:0] bit_operator_type;
    logic [OPERATOR_TYPE_WIDTH-1:0] bru_operator_type;
    wire [REGS_DATA_WIDTH-1:0] alu_result;
    wire [REGS_DATA_WIDTH-1:0] fast_b_shadd_result =
        ({REGS_DATA_WIDTH{bit_operator[OP_B_SH1ADD]}} &
         ((bit_operand_a_i << 1) + bit_operand_b_i)) |
        ({REGS_DATA_WIDTH{bit_operator[OP_B_SH2ADD]}} &
         ((bit_operand_a_i << 2) + bit_operand_b_i)) |
        ({REGS_DATA_WIDTH{bit_operator[OP_B_SH3ADD]}} &
         ((bit_operand_a_i << 3) + bit_operand_b_i));
    wire [REGS_DATA_WIDTH-1:0] fast_b_extend_result =
        ({REGS_DATA_WIDTH{bit_operator[OP_B_REV8]}} &
         {bit_operand_a_i[7:0], bit_operand_a_i[15:8],
          bit_operand_a_i[23:16], bit_operand_a_i[31:24]}) |
        ({REGS_DATA_WIDTH{bit_operator[OP_B_SEXT_B]}} &
         {{24{bit_operand_a_i[7]}}, bit_operand_a_i[7:0]}) |
        ({REGS_DATA_WIDTH{bit_operator[OP_B_SEXT_H]}} &
         {{16{bit_operand_a_i[15]}}, bit_operand_a_i[15:0]}) |
        ({REGS_DATA_WIDTH{bit_operator[OP_B_ZEXT_H]}} &
         {16'b0, bit_operand_a_i[15:0]});
    wire [REGS_DATA_WIDTH-1:0] early_b_pack_result =
        ({REGS_DATA_WIDTH{bit_operator[OP_B_PACK]}} &
         {bit_operand_b_i[15:0], bit_operand_a_i[15:0]}) |
        ({REGS_DATA_WIDTH{bit_operator[OP_B_PACKH]}} &
         {16'b0, bit_operand_b_i[7:0], bit_operand_a_i[7:0]});
    wire [REGS_DATA_WIDTH-1:0] bitmanip_result;
    wire [REGS_DATA_WIDTH-1:0] branch_link_result = pc_i + 32'd4;

    always_comb begin
        alu_operator = '0;
        bit_operator = '0;
        bru_operator = '0;
        alu_operator_type = '0;
        bit_operator_type = '0;
        bru_operator_type = '0;
        alu_operator[alu_subop_i] = alu_valid_i;
        bit_operator[bit_subop_i] = bit_valid_i;
        bru_operator[bru_subop_i] = bru_valid_i;
        alu_operator_type[OPERATOR_TYPE_ALU] = alu_valid_i;
        bit_operator_type[OPERATOR_TYPE_BITMANIP] = bit_valid_i;
        bru_operator_type[OPERATOR_TYPE_BJP] = bru_valid_i;
    end

    wire alu_unused_comp;
    wire alu_unused_wen;
    wire [REGS_ADDR_WIDTH-1:0] alu_unused_waddr;
    ydrasil_alu u_dual_alu (
        .operand_a_i(alu_operand_a_i), .operand_b_i(alu_operand_b_i),
        .operator_i(alu_operator), .operator_type_i(alu_operator_type),
        .id_rf_waddr_rd_i(rd_addr_i),
        .id_alu_rf_wen_rd_i(rd_wen_i && alu_valid_i),
        .interrupt_i(interrupt_i), .comp_result_o(alu_unused_comp),
        .alu_result_o(alu_result), .alu_rf_wen_rd_o(alu_unused_wen),
        .alu_rf_waddr_rd_o(alu_unused_waddr)
    );

    // Zb owns a dedicated execution cone. It shares only the typed lane-B
    // completion port with ALU/BRU; no Zb operand or result traverses the ALU.
    ydrasil_bitmanip u_dual_bitmanip (
        .operand_a_i     (bit_operand_a_i),
        .operand_b_i     (bit_operand_b_i),
        .operator_i      (bit_operator),
        .operator_type_i (bit_operator_type),
        .result_o        (bitmanip_result)
    );

    ydrasil_bru u_lane_b_bru (
        .clk(clk),
        .rst_n(rst_n),
        .flush_i(flush_i),
        .operand_a_i(branch_operand_a_i),
        .operand_b_i(branch_operand_b_i),
        .bt_a_operand_i(jalr_i ? branch_operand_a_i : pc_i),
        .bt_b_operand_i(branch_imm_i),
        .operator_i(bru_operator),
        .operator_type_i(bru_operator_type),
        .id_ex_valid_i(bru_valid_i),
        .id_ex_jalr_i(jalr_i),
        .id_ex_branch_target_i(branch_target_i),
        .id_ex_branch_next_pc_i(branch_next_pc_i),
        .id_ex_pred_hit_i(pred_hit_i),
        .id_ex_pred_taken_i(pred_taken_i),
        .id_ex_pred_target_i(pred_target_i),
        .id_ex_pred_counter_i(pred_counter_i),
        .id_ex_pred_bht_index_i(pred_bht_index_i),
        .id_ex_producer_id_i(producer_id_i),
        .trap_redirect_i(interrupt_i),
        .trap_redirect_addr_i(trap_redirect_addr_i),
        .ex_branch_jump_o(ex_branch_jump_o),
        .ex_branch_target_o(ex_branch_target_o),
        .ex_pc_redirect_o(ex_pc_redirect_o),
        .ex_pc_redirect_target_o(ex_pc_redirect_target_o),
        .ex_bp_train_o(ex_bp_train_o),
        .ex_branch_mispredict_o(ex_branch_mispredict_o)
`ifndef SYNTHESIS
        ,.dbg_bp_resolve_valid_o(dbg_bp_resolve_valid_o)
        ,.dbg_bp_resolve_pc_o(dbg_bp_resolve_pc_o)
        ,.dbg_bp_actual_taken_o(dbg_bp_actual_taken_o)
        ,.dbg_bp_actual_target_o(dbg_bp_actual_target_o)
        ,.dbg_bp_actual_next_pc_o(dbg_bp_actual_next_pc_o)
        ,.dbg_bp_pred_hit_o(dbg_bp_pred_hit_o)
        ,.dbg_bp_pred_taken_o(dbg_bp_pred_taken_o)
        ,.dbg_bp_pred_target_o(dbg_bp_pred_target_o)
        ,.dbg_bp_pred_counter_o(dbg_bp_pred_counter_o)
        ,.dbg_bp_pred_next_pc_o(dbg_bp_pred_next_pc_o)
        ,.dbg_bp_mispredict_o(dbg_bp_mispredict_o)
`endif
    );
    always_ff @(posedge clk) begin
        if (!rst_n || flush_i) begin
            valid_q <= 1'b0;
            pc_q <= '0;
            instr_q <= RV32I_INS_NOP;
        end else begin
            valid_q <= (alu_valid_i || bit_valid_i || bru_valid_i) &&
                !interrupt_i;
            pc_q <= pc_i;
            instr_q <= instr_i;
        end
    end

    // Lane B completion is captured by the typed ALU result array at WB. The
    // remaining q state is commit trace metadata, not an execution bypass.
    assign completion_valid_o =
        (alu_valid_i || bit_valid_i || bru_valid_i) && rd_wen_i &&
        !interrupt_i &&
        (rd_addr_i != '0);
    assign completion_producer_id_o = producer_id_i;
    assign completion_producer_tracked_o = producer_tracked_i;
    assign completion_addr_o = rd_addr_i;
    assign completion_data_o = bit_valid_i ? bitmanip_result :
        bru_valid_i ? branch_link_result : alu_result;
    assign instret_valid_o = valid_q;
    assign commit_pc_o = pc_q;
    assign commit_instr_o = instr_q;
endmodule
