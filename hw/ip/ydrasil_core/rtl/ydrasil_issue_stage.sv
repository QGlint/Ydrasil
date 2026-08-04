module ydrasil_issue_stage
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        stall_id_i,
    input  wire                        bubble_id_i,
    input  wire                        flush_id_i,
    input  ydrasil_issue_pkt_t         issue_pkt_i,
    input  ydrasil_issue_pkt_t         issue_pkt1_i,
    input  ydrasil_rob_source_state_t  issue_src0_state_i,
    input  ydrasil_rob_source_state_t  issue_src1_state_i,
    input  ydrasil_rob_source_state_t  issue_src2_state_i,
    input  ydrasil_rob_source_state_t  issue_src3_state_i,
    input  ydrasil_completion_bus_t    completion_bus_i,
    input  wire                        lsu_idle_i,
    input  wire [1:0]                  lsu_credit_i,
    input  ydrasil_reservation_pkt_t   dtcm_reservation_i,
    input  wire                        issue_at_rob_head_i,
    output wire                        issue_ready_o,
    output wire                        issue_consume_two_o,
    output wire                        issue_slot1_replay_o,
    output wire                        issue_fence_o,
    output producer_id_t               issue_fence_tag_o,
    output wire [INST_ADDR_WIDTH-1:0]  issue_fence_next_pc_o,
    output wire                        scoreboard_stall_o,
    output wire                        scoreboard_stall1_o,
    output wire                        lsu_struct_stall_o,
    output wire                        lsu_struct_stall1_o,
    output wire                        serialize_stall_o,
    output wire                        src0_wait_o,
    output wire                        src1_wait_o,
    output wire                        src2_wait_o,
    output wire                        src3_wait_o,
    output ydrasil_issue_ex_pkt_t      issue_ex_o,
    output wire                        alu_in_valid_o,
    output wire [DATA_WIDTH-1:0]       alu_in_operand_a_o,
    output wire [DATA_WIDTH-1:0]       alu_in_operand_b_o,
    output wire [OPERATOR_WIDTH-1:0]   alu_in_operator_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0] alu_in_operator_type_o,
    output wire                        alu_in_rd_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0]  alu_in_rd_addr_o,
    output producer_id_t               alu_in_producer_id_o,
    output wire                        bru_in_valid_o,
    output wire [DATA_WIDTH-1:0]       bru_in_operand_a_o,
    output wire [DATA_WIDTH-1:0]       bru_in_operand_b_o,
    output wire [DATA_WIDTH-1:0]       bru_in_bt_operand_a_o,
    output wire [DATA_WIDTH-1:0]       bru_in_bt_operand_b_o,
    output wire [OPERATOR_WIDTH-1:0]   bru_in_operator_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0] bru_in_operator_type_o,
    output wire                        bru_in_jalr_o,
    output wire [DATA_WIDTH-1:0]       bru_in_branch_target_o,
    output wire [DATA_WIDTH-1:0]       bru_in_branch_next_pc_o,
    output wire [DATA_WIDTH-1:0]       bru_in_pc_o,
    output wire                        bru_in_pred_hit_o,
    output wire                        bru_in_pred_taken_o,
    output wire [DATA_WIDTH-1:0]       bru_in_pred_target_o,
    output wire [1:0]                  bru_in_pred_counter_o,
    output wire [DATA_WIDTH-1:0]       bru_in_pred_bht_index_o,
    output wire                        agu_in_valid_o,
    output wire [DATA_WIDTH-1:0]       agu_in_operand_a_o,
    output wire [DATA_WIDTH-1:0]       agu_in_operand_b_o,
    output ydrasil_lsu_req_pkt_t       agu_in_req_o,
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
    output ydrasil_dual_issue_pkt_t    dual_in_o,
    output wire [4:0]                  rf_addr_rs1_o,
    output wire [4:0]                  rf_addr_rs2_o,
    output wire [4:0]                  rf_addr_rs3_o,
    output wire [4:0]                  rf_addr_rs4_o,
    input  wire [DATA_WIDTH-1:0]       rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]       rf_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]       rf_rdata_rs3_i,
    input  wire [DATA_WIDTH-1:0]       rf_rdata_rs4_i,
    output wire [4:0]                  fpr_addr_rs1_o,
    output wire [4:0]                  fpr_addr_rs2_o,
    output wire [4:0]                  fpr_addr_rs3_o,
    input  wire [DATA_WIDTH-1:0]       fpr_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]       fpr_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]       fpr_rdata_rs3_i
);
    // Completion state is committed into the producer file on the same edge
    // that the global completion bus is observed.  Consumers therefore use
    // the registered ROB result on the next Issue cycle; retaining a second
    // copy here created a wide, high-fanout bypass cone with no earlier
    // visibility.  The only zero-latency path is the tagged ALU reservation
    // below, whose raw result is needed for the immediately following issue.
    reg lsu_idle_q;
    reg issue_at_rob_head_q;
    reg early_wakeup_valid_q [0:1];
    producer_id_t early_wakeup_id_q [0:1];
    reg [REGS_ADDR_WIDTH-1:0] early_wakeup_rd_q [0:1];
    // Token identity is registered here. Its data already lives in the
    // execution units' registered input cells, exposed by completion_bus_i
    // during the following Issue cycle.

    reg alu_in_valid_q;
    reg [DATA_WIDTH-1:0] alu_in_operand_a_q, alu_in_operand_b_q;
    reg [OPERATOR_WIDTH-1:0] alu_in_operator_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] alu_in_operator_type_q;
    reg alu_in_rd_wen_q;
    reg [REGS_ADDR_WIDTH-1:0] alu_in_rd_addr_q;
    producer_id_t alu_in_producer_id_q;
    reg bru_in_valid_q;
    reg [DATA_WIDTH-1:0] bru_in_operand_a_q, bru_in_operand_b_q;
    reg [DATA_WIDTH-1:0] bru_in_bt_operand_a_q, bru_in_bt_operand_b_q;
    reg [OPERATOR_WIDTH-1:0] bru_in_operator_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] bru_in_operator_type_q;
    reg bru_in_jalr_q;
    reg [DATA_WIDTH-1:0] bru_in_branch_target_q, bru_in_branch_next_pc_q;
    reg [DATA_WIDTH-1:0] bru_in_pc_q, bru_in_pred_target_q;
    reg bru_in_pred_hit_q, bru_in_pred_taken_q;
    reg [1:0] bru_in_pred_counter_q;
    reg [DATA_WIDTH-1:0] bru_in_pred_bht_index_q;
    reg agu_in_valid_q;
    reg [DATA_WIDTH-1:0] agu_in_operand_a_q, agu_in_operand_b_q;
    ydrasil_lsu_req_pkt_t agu_in_req_q;
    reg csr_in_valid_q;
    reg [DATA_WIDTH-1:0] csr_in_operand_a_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] csr_in_operator_type_q;
    reg [CSR_ADDR_WIDTH-1:0] csr_in_raddr_q, csr_in_waddr_q;
    reg [OP_CSR_INFO_WIDTH-1:0] csr_in_op_info_q;
    reg [OP_SYS_INFO_WIDTH-1:0] csr_in_sys_info_q;
    reg mul_in_valid_q;
    reg [DATA_WIDTH-1:0] mul_in_operand_a_q, mul_in_operand_b_q;
    reg [OPERATOR_WIDTH-1:0] mul_in_operator_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] mul_in_operator_type_q;
    ydrasil_dual_issue_pkt_t dual_in_q;
    function automatic logic source_ready(
        input ydrasil_source_desc_t src,
        input ydrasil_rob_source_state_t state
    );
        begin
            source_ready = !src.used || (src.arch_addr == '0) ||
                !state.live || state.done ||
                early_wakeup_hit(src) || dtcm_reservation_hit(src);
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] source_data(
        input ydrasil_source_desc_t src,
        input ydrasil_rob_source_state_t state,
        input logic [DATA_WIDTH-1:0] arf_data
    );
        begin
            source_data = arf_data;
            if (src.used && (src.arch_addr != '0) && state.live)
                source_data = state.result;
            // A fixed-latency ALU reservation carries the value alongside
            // its generation-tagged identity.  It is a data-only local
            // bypass; source_ready still requires the same reservation hit.
            if (early_wakeup_hit(src))
                source_data = early_wakeup_data(src);
            if (dtcm_reservation_hit(src))
                source_data = dtcm_reservation_i.predicted_data;
        end
    endfunction

    function automatic logic dtcm_reservation_hit(
        input ydrasil_source_desc_t src
    );
        begin
            dtcm_reservation_hit = src.used && (src.arch_addr != '0) &&
                src.tag_valid && (src.producer_class == RESULT_LSU) &&
                dtcm_reservation_i.valid &&
                dtcm_reservation_i.producer_tracked &&
                (dtcm_reservation_i.result_class == RESULT_LSU) &&
                (dtcm_reservation_i.arch_addr == src.arch_addr) &&
                (dtcm_reservation_i.producer_id == src.producer_tag);
        end
    endfunction

    function automatic logic early_wakeup_hit(
        input ydrasil_source_desc_t src
    );
        begin
            early_wakeup_hit = src.used && (src.arch_addr != '0) &&
                src.tag_valid && (src.producer_class == RESULT_ALU) &&
                ((early_wakeup_valid_q[0] &&
                  (early_wakeup_rd_q[0] == src.arch_addr) &&
                  (early_wakeup_id_q[0] == src.producer_tag)) ||
                 (early_wakeup_valid_q[1] &&
                  (early_wakeup_rd_q[1] == src.arch_addr) &&
                  (early_wakeup_id_q[1] == src.producer_tag)));
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] early_wakeup_data(
        input ydrasil_source_desc_t src
    );
        begin
            early_wakeup_data = '0;
            if (early_wakeup_valid_q[0] &&
                (early_wakeup_rd_q[0] == src.arch_addr) &&
                (early_wakeup_id_q[0] == src.producer_tag))
                early_wakeup_data = completion_bus_i[COMPLETION_ALU].data;
            else if (early_wakeup_valid_q[1] &&
                     (early_wakeup_rd_q[1] == src.arch_addr) &&
                     (early_wakeup_id_q[1] == src.producer_tag))
                early_wakeup_data =
                    completion_bus_i[COMPLETION_DUAL_ALU].data;
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] source_data_local_bypass(
        input ydrasil_source_desc_t src,
        input ydrasil_rob_source_state_t state,
        input logic [DATA_WIDTH-1:0] arf_data
    );
        begin
            source_data_local_bypass = source_data(src, state, arf_data);
            // Fixed-latency ALU/BRU/bit results use the tagged reservation;
            // all other completions are read from the producer file above.
            if (dtcm_reservation_hit(src))
                source_data_local_bypass = dtcm_reservation_i.predicted_data;
        end
    endfunction

    wire src0_ready = source_ready(issue_pkt_i.src0, issue_src0_state_i);
    wire src1_ready = source_ready(issue_pkt_i.src1, issue_src1_state_i);
    wire src2_ready = source_ready(issue_pkt1_i.src0, issue_src2_state_i);
    wire src3_ready = source_ready(issue_pkt1_i.src1, issue_src3_state_i);
    wire slot0_scoreboard_stall = issue_pkt_i.valid &&
        (!src0_ready || !src1_ready);
    wire slot1_active = issue_pkt_i.pair_eligible && issue_pkt1_i.valid;
    wire slot1_scoreboard_stall = slot1_active &&
        (!src2_ready || !src3_ready);
    wire slot0_lsu_stall = issue_pkt_i.ctrl.lsu_req && (lsu_credit_i == 2'd0);
    wire slot1_lsu_stall = slot1_active && issue_pkt1_i.ctrl.lsu_req &&
        (lsu_credit_i == 2'd0);
    wire serialize_stall = issue_pkt_i.ctrl.serialize_before &&
        (!lsu_idle_q || !issue_at_rob_head_q);
    wire local_issue_stall = slot0_scoreboard_stall || slot0_lsu_stall ||
        serialize_stall;
    wire id_advance = !stall_id_i && !bubble_id_i && !local_issue_stall;
    wire pair_eligible = slot1_active;
    wire slot1_blocked = slot1_scoreboard_stall || slot1_lsu_stall;
    wire pair_issue = pair_eligible && !slot1_blocked;
    wire swap_pair = pair_issue &&
        !(issue_pkt_i.lane_mask[0] && issue_pkt1_i.lane_mask[1]);
    wire head0_b_only = issue_pkt_i.lane_mask[1] &&
        !issue_pkt_i.lane_mask[0];

    assign issue_ready_o = id_advance;
    assign issue_consume_two_o = id_advance && pair_eligible;
    assign issue_slot1_replay_o = id_advance && pair_eligible && slot1_blocked;
    reg issue_fence_q;
    producer_id_t issue_fence_tag_q;
    reg [INST_ADDR_WIDTH-1:0] issue_fence_next_pc_q;
    wire issue_fence_accept = id_advance && issue_pkt_i.valid &&
        issue_pkt_i.decode.fence_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_fence_q <= 1'b0;
            issue_fence_tag_q <= '0;
            issue_fence_next_pc_q <= '0;
        end else if (flush_id_i) begin
            issue_fence_q <= 1'b0;
            issue_fence_tag_q <= '0;
            issue_fence_next_pc_q <= '0;
        end else begin
            issue_fence_q <= issue_fence_accept;
            if (issue_fence_accept) begin
                issue_fence_tag_q <= issue_pkt_i.dst.rob_tag;
                issue_fence_next_pc_q <= issue_pkt_i.next_pc;
            end
        end
    end

    assign issue_fence_o = issue_fence_q;
    assign issue_fence_tag_o = issue_fence_tag_q;
    assign issue_fence_next_pc_o = issue_fence_next_pc_q;
    assign scoreboard_stall_o = slot0_scoreboard_stall;
    assign scoreboard_stall1_o = slot1_scoreboard_stall;
    assign lsu_struct_stall_o = slot0_lsu_stall;
    assign lsu_struct_stall1_o = slot1_lsu_stall;
    assign serialize_stall_o = serialize_stall;
    assign src0_wait_o = issue_pkt_i.valid && issue_pkt_i.src0.used &&
        !src0_ready;
    assign src1_wait_o = issue_pkt_i.valid && issue_pkt_i.src1.used &&
        !src1_ready;
    assign src2_wait_o = issue_pkt1_i.valid && issue_pkt1_i.src0.used &&
        !src2_ready;
    assign src3_wait_o = issue_pkt1_i.valid && issue_pkt1_i.src1.used &&
        !src3_ready;
    ydrasil_issue_pkt_t lane_a_uop;
    ydrasil_issue_pkt_t lane_b_uop;
    reg lane_a_valid;
    reg lane_b_valid;
    always_comb begin
        lane_a_uop = issue_pkt_i;
        lane_b_uop = issue_pkt1_i;
        lane_a_valid = issue_pkt_i.valid && !head0_b_only;
        lane_b_valid = issue_pkt_i.valid && head0_b_only;
        if (pair_issue) begin
            lane_a_valid = 1'b1;
            lane_b_valid = 1'b1;
            if (swap_pair) begin
                lane_a_uop = issue_pkt1_i;
                lane_b_uop = issue_pkt_i;
            end
        end else if (head0_b_only) begin
            lane_b_uop = issue_pkt_i;
        end
    end

    wire [DATA_WIDTH-1:0] slot0_src0 = source_data(
        issue_pkt_i.src0, issue_src0_state_i, rf_rdata_rs1_i);
    wire [DATA_WIDTH-1:0] slot0_src1 = source_data(
        issue_pkt_i.src1, issue_src1_state_i, rf_rdata_rs2_i);
    wire [DATA_WIDTH-1:0] slot1_src0 = source_data(
        issue_pkt1_i.src0, issue_src2_state_i, rf_rdata_rs3_i);
    wire [DATA_WIDTH-1:0] slot1_src1 = source_data(
        issue_pkt1_i.src1, issue_src3_state_i, rf_rdata_rs4_i);
    wire [DATA_WIDTH-1:0] slot0_src0_local = source_data_local_bypass(
        issue_pkt_i.src0, issue_src0_state_i, rf_rdata_rs1_i);
    wire [DATA_WIDTH-1:0] slot0_src1_local = source_data_local_bypass(
        issue_pkt_i.src1, issue_src1_state_i, rf_rdata_rs2_i);
    wire [DATA_WIDTH-1:0] slot1_src0_local = source_data_local_bypass(
        issue_pkt1_i.src0, issue_src2_state_i, rf_rdata_rs3_i);
    wire [DATA_WIDTH-1:0] slot1_src1_local = source_data_local_bypass(
        issue_pkt1_i.src1, issue_src3_state_i, rf_rdata_rs4_i);
    wire [DATA_WIDTH-1:0] lane_a_src0 = swap_pair ? slot1_src0 : slot0_src0;
    wire [DATA_WIDTH-1:0] lane_a_src1 = swap_pair ? slot1_src1 : slot0_src1;
    wire lane_b_uses_slot0 = head0_b_only || swap_pair;
    wire [DATA_WIDTH-1:0] lane_b_src0 = lane_b_uses_slot0 ?
        slot0_src0 : slot1_src0;
    wire [DATA_WIDTH-1:0] lane_b_src1 = lane_b_uses_slot0 ?
        slot0_src1 : slot1_src1;
    wire [DATA_WIDTH-1:0] lane_a_src0_local = swap_pair ?
        slot1_src0_local : slot0_src0_local;
    wire [DATA_WIDTH-1:0] lane_a_src1_local = swap_pair ?
        slot1_src1_local : slot0_src1_local;
    wire [DATA_WIDTH-1:0] lane_b_src0_local = lane_b_uses_slot0 ?
        slot0_src0_local : slot1_src0_local;
    wire [DATA_WIDTH-1:0] lane_b_src1_local = lane_b_uses_slot0 ?
        slot0_src1_local : slot1_src1_local;

    assign rf_addr_rs1_o = issue_pkt_i.src0.arch_addr;
    assign rf_addr_rs2_o = issue_pkt_i.src1.arch_addr;
    assign rf_addr_rs3_o = issue_pkt1_i.src0.arch_addr;
    assign rf_addr_rs4_o = issue_pkt1_i.src1.arch_addr;
    assign fpr_addr_rs1_o = lane_a_uop.decode.fp_rs1_addr;
    assign fpr_addr_rs2_o = lane_a_uop.decode.fp_rs2_addr;
    assign fpr_addr_rs3_o = lane_a_uop.decode.fp_rs3_addr;

    function automatic [DATA_WIDTH-1:0] operand_a_for(
        input ydrasil_issue_pkt_t uop,
        input logic [DATA_WIDTH-1:0] src0
    );
        begin
            operand_a_for = uop.decode.operand_a_pc_sel ? uop.decode.pc :
                uop.decode.operand_a_imm_sel ? uop.decode.imm : src0;
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] operand_b_for(
        input ydrasil_issue_pkt_t uop,
        input logic [DATA_WIDTH-1:0] src1
    );
        begin
            operand_b_for = uop.decode.operand_b_jump_sel ? 32'd4 :
                uop.decode.operand_b_rs_sel ? src1 : uop.decode.imm;
        end
    endfunction

    function automatic logic early_bitmanip_lite_supported(
        input logic [OPERATOR_WIDTH-1:0] op
    );
        begin
            early_bitmanip_lite_supported =
                op[OP_B_SH1ADD] | op[OP_B_SH2ADD] | op[OP_B_SH3ADD] |
                op[OP_B_PACK] | op[OP_B_PACKH] | op[OP_B_REV8] |
                op[OP_B_SEXT_B] | op[OP_B_SEXT_H] | op[OP_B_ZEXT_H];
        end
    endfunction

    wire lane_a_early_plain_alu =
        lane_a_uop.decode.operator_type[OPERATOR_TYPE_ALU] &&
        !lane_a_uop.decode.operator_type[OPERATOR_TYPE_BITMANIP];
    wire lane_b_early_plain_alu =
        lane_b_uop.decode.operator_type[OPERATOR_TYPE_ALU] &&
        !lane_b_uop.decode.operator_type[OPERATOR_TYPE_BITMANIP];
    wire lane_a_early_bjp =
        lane_a_uop.decode.operator_type[OPERATOR_TYPE_BJP];
    wire lane_b_early_bjp =
        lane_b_uop.decode.operator_type[OPERATOR_TYPE_BJP];
    wire lane_a_early_bitmanip =
        lane_a_uop.decode.operator_type[OPERATOR_TYPE_BITMANIP] &&
        early_bitmanip_lite_supported(lane_a_uop.decode.operator_info);
    wire lane_b_early_bitmanip =
        lane_b_uop.decode.operator_type[OPERATOR_TYPE_BITMANIP] &&
        early_bitmanip_lite_supported(lane_b_uop.decode.operator_info);
    wire lane_a_early_valid = lane_a_valid &&
        lane_a_uop.dst.writes_gpr && !lane_a_uop.memory_op &&
        !lane_a_uop.decode.fp_valid && !lane_a_uop.decode.fence_i &&
        (lane_a_early_plain_alu || lane_a_early_bjp ||
         lane_a_early_bitmanip);
    wire lane_b_early_valid = lane_b_valid &&
        lane_b_uop.dst.writes_gpr && !lane_b_uop.decode.fp_valid &&
        (lane_b_early_plain_alu || lane_b_early_bjp ||
         lane_b_early_bitmanip);

    ydrasil_issue_ex_pkt_t issue_ex_d;
    ydrasil_issue_ex_pkt_t issue_ex_q;
    always_comb begin
        issue_ex_d = '0;
        issue_ex_d.valid = lane_a_valid;
        issue_ex_d.operand_a = operand_a_for(lane_a_uop, lane_a_src0);
        issue_ex_d.operand_b = operand_b_for(lane_a_uop, lane_a_src1);
        issue_ex_d.operator_info = lane_a_uop.decode.operator_info;
        issue_ex_d.operator_type = lane_a_uop.decode.operator_type;
        issue_ex_d.jalr = lane_a_uop.decode.bt_a_rs_sel;
        issue_ex_d.branch_target = lane_a_uop.target;
        issue_ex_d.branch_next_pc = lane_a_uop.next_pc;
        issue_ex_d.bt_a_operand = lane_a_uop.decode.bt_a_rs_sel ?
            lane_a_src0 : lane_a_uop.decode.pc;
        issue_ex_d.bt_b_operand = lane_a_src1;
        issue_ex_d.pred_hit = lane_a_uop.decode.pred_hit;
        issue_ex_d.pred_taken = lane_a_uop.decode.pred_taken;
        issue_ex_d.pred_target = lane_a_uop.decode.pred_target;
        issue_ex_d.pred_counter = lane_a_uop.decode.pred_counter;
        issue_ex_d.pred_bht_index = lane_a_uop.decode.pred_bht_index;
        issue_ex_d.csr_raddr = lane_a_uop.decode.csr_raddr;
        issue_ex_d.csr_waddr = lane_a_uop.decode.csr_waddr;
        issue_ex_d.csr_op_info = lane_a_uop.decode.csr_op_info;
        issue_ex_d.sys_op_info = lane_a_uop.decode.sys_op_info;
        issue_ex_d.pc = lane_a_uop.decode.pc;
        // fence.i completes at the Issue boundary and never occupies Lane A.
        if (lane_a_uop.decode.fence_i) begin
            issue_ex_d.valid = 1'b0;
            issue_ex_d.producer_tracked = 1'b0;
        end
        issue_ex_d.rd_wen = lane_a_valid && lane_a_uop.dst.writes_gpr;
        issue_ex_d.rd_addr = lane_a_uop.dst.rd_addr;
        issue_ex_d.producer_id = lane_a_uop.dst.rob_tag;
        issue_ex_d.producer_tracked = lane_a_valid;
        issue_ex_d.lsu_req.valid = lane_a_valid && lane_a_uop.memory_op;
        issue_ex_d.lsu_req.is_load =
            lane_a_uop.decode.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.is_store =
            lane_a_uop.decode.operator_type[OPERATOR_TYPE_STORE];
        issue_ex_d.lsu_req.op = lane_a_uop.decode.operator_lsu;
        issue_ex_d.lsu_req.rd_addr = lane_a_uop.dst.rd_addr;
        issue_ex_d.lsu_req.producer_id = lane_a_uop.dst.rob_tag;
        issue_ex_d.lsu_req.producer_tracked = lane_a_valid;
        issue_ex_d.lsu_req.store_data = lane_a_src1;
        issue_ex_d.lsu_req.store_data_valid = 1'b1;
        issue_ex_d.lsu_req.fp_load = lane_a_uop.decode.fp_valid &&
            lane_a_uop.decode.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.fp_rd_addr = lane_a_uop.decode.fp_rd_addr;
        issue_ex_d.fpu_req.valid = lane_a_valid && lane_a_uop.decode.fp_valid &&
            !lane_a_uop.decode.operator_type[OPERATOR_TYPE_LOAD] &&
            !lane_a_uop.decode.operator_type[OPERATOR_TYPE_STORE];
        issue_ex_d.fpu_req.illegal = lane_a_uop.decode.fp_illegal;
        issue_ex_d.fpu_req.op = lane_a_uop.decode.fp_op;
        issue_ex_d.fpu_req.rm = lane_a_uop.decode.fp_rm;
        issue_ex_d.fpu_req.operand_a = lane_a_uop.decode.fp_rs1_fpr ?
            fpr_rdata_rs1_i : lane_a_src0;
        issue_ex_d.fpu_req.operand_b = fpr_rdata_rs2_i;
        issue_ex_d.fpu_req.operand_c = fpr_rdata_rs3_i;
        issue_ex_d.fpu_req.rd_addr = lane_a_uop.dst.rd_addr;
        issue_ex_d.fpu_req.rd_fpr = lane_a_uop.decode.fp_rd_fpr;
        issue_ex_d.fpu_req.rd_gpr = lane_a_uop.decode.fp_rd_gpr;
        issue_ex_d.fpu_req.producer_id = lane_a_uop.dst.rob_tag;
        issue_ex_d.fpu_req.producer_tracked = lane_a_valid;
        issue_ex_d.fpu_req.pc = lane_a_uop.decode.pc;
        issue_ex_d.fpu_req.instr = lane_a_uop.decode.instr;

        issue_ex_d.lane1_valid = lane_b_valid;
        issue_ex_d.lane1_operand_a = operand_a_for(lane_b_uop, lane_b_src0);
        issue_ex_d.lane1_operand_b = operand_b_for(lane_b_uop, lane_b_src1);
        issue_ex_d.lane1_branch_operand_a = lane_b_src0;
        issue_ex_d.lane1_branch_operand_b = lane_b_src1;
        issue_ex_d.lane1_branch_imm = lane_b_uop.decode.imm;
        issue_ex_d.lane1_operator_info = lane_b_uop.decode.operator_info;
        issue_ex_d.lane1_operator_type = lane_b_uop.decode.operator_type;
        issue_ex_d.lane1_operator_lsu = lane_b_uop.decode.operator_lsu;
        issue_ex_d.lane1_store_data = lane_b_src1;
        issue_ex_d.lane1_store_data_valid = 1'b1;
        issue_ex_d.lane1_rd_addr = lane_b_uop.dst.rd_addr;
        issue_ex_d.lane1_rd_wen = lane_b_valid && lane_b_uop.dst.writes_gpr;
        issue_ex_d.lane1_producer_id = lane_b_uop.dst.rob_tag;
        issue_ex_d.lane1_producer_tracked = lane_b_valid;
        issue_ex_d.lane1_pc = lane_b_uop.decode.pc;
        issue_ex_d.lane1_instr = lane_b_uop.decode.instr;
        issue_ex_d.lane1_jalr = lane_b_uop.decode.bt_a_rs_sel;
        issue_ex_d.lane1_branch_target = lane_b_uop.target;
        issue_ex_d.lane1_branch_next_pc = lane_b_uop.next_pc;
        issue_ex_d.lane1_pred_hit = lane_b_uop.decode.pred_hit;
        issue_ex_d.lane1_pred_taken = lane_b_uop.decode.pred_taken;
        issue_ex_d.lane1_pred_target = lane_b_uop.decode.pred_target;
        issue_ex_d.lane1_pred_counter = lane_b_uop.decode.pred_counter;
        issue_ex_d.lane1_pred_bht_index = lane_b_uop.decode.pred_bht_index;

        // Keep the payload independent from the grant/occupancy decision.
        // Only valid bits cross the issue/EX ownership boundary.  Clearing the
        // entire packed payload here made issue_pipe_count/pair_eligible fan
        // out through every operand and metadata bit, reopening a long timing
        // cone into the early-wakeup data cells.  Invalid payload is ignored
        // by every execution unit and is overwritten on the next accepted
        // issue, while the valid bits still enforce the exact handshake.
        if (!id_advance) begin
            issue_ex_d.valid = 1'b0;
            issue_ex_d.producer_tracked = 1'b0;
            issue_ex_d.lsu_req.valid = 1'b0;
            issue_ex_d.lsu_req.producer_tracked = 1'b0;
            issue_ex_d.fpu_req.valid = 1'b0;
            issue_ex_d.fpu_req.producer_tracked = 1'b0;
            issue_ex_d.lane1_valid = 1'b0;
            issue_ex_d.lane1_producer_tracked = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || flush_id_i) begin
            lsu_idle_q <= 1'b1;
            issue_at_rob_head_q <= 1'b0;
            early_wakeup_valid_q[0] <= 1'b0;
            early_wakeup_valid_q[1] <= 1'b0;
            early_wakeup_id_q[0] <= '0;
            early_wakeup_id_q[1] <= '0;
            early_wakeup_rd_q[0] <= '0;
            early_wakeup_rd_q[1] <= '0;
            issue_ex_q <= '0;
            alu_in_valid_q <= 1'b0;
            alu_in_operand_a_q <= '0;
            alu_in_operand_b_q <= '0;
            alu_in_operator_q <= '0;
            alu_in_operator_type_q <= '0;
            alu_in_rd_wen_q <= 1'b0;
            alu_in_rd_addr_q <= '0;
            alu_in_producer_id_q <= '0;
            bru_in_valid_q <= 1'b0;
            bru_in_operand_a_q <= '0;
            bru_in_operand_b_q <= '0;
            bru_in_bt_operand_a_q <= '0;
            bru_in_bt_operand_b_q <= '0;
            bru_in_operator_q <= '0;
            bru_in_operator_type_q <= '0;
            bru_in_jalr_q <= 1'b0;
            bru_in_branch_target_q <= '0;
            bru_in_branch_next_pc_q <= '0;
            bru_in_pc_q <= '0;
            bru_in_pred_hit_q <= 1'b0;
            bru_in_pred_taken_q <= 1'b0;
            bru_in_pred_target_q <= '0;
            bru_in_pred_counter_q <= '0;
            bru_in_pred_bht_index_q <= '0;
            agu_in_valid_q <= 1'b0;
            agu_in_operand_a_q <= '0;
            agu_in_operand_b_q <= '0;
            agu_in_req_q <= '0;
            csr_in_valid_q <= 1'b0;
            csr_in_operand_a_q <= '0;
            csr_in_operator_type_q <= '0;
            csr_in_raddr_q <= '0;
            csr_in_waddr_q <= '0;
            csr_in_op_info_q <= '0;
            csr_in_sys_info_q <= '0;
            mul_in_valid_q <= 1'b0;
            mul_in_operand_a_q <= '0;
            mul_in_operand_b_q <= '0;
            mul_in_operator_q <= '0;
            mul_in_operator_type_q <= '0;
            dual_in_q <= '0;
        end else begin
            lsu_idle_q <= lsu_idle_i;
            issue_at_rob_head_q <= issue_at_rob_head_i;

            if (stall_id_i) begin
                // A token is a one-cycle reservation. Holding it across an
                // unrelated front-end stall could alias a recycled producer
                // tag after the circular ROB wraps.
                early_wakeup_valid_q[0] <= 1'b0;
                early_wakeup_valid_q[1] <= 1'b0;
                early_wakeup_id_q[0] <= '0;
                early_wakeup_id_q[1] <= '0;
                early_wakeup_rd_q[0] <= '0;
                early_wakeup_rd_q[1] <= '0;
            end else begin
                if (bubble_id_i) begin
                    issue_ex_q <= '0;
                    early_wakeup_valid_q[0] <= 1'b0;
                    early_wakeup_valid_q[1] <= 1'b0;
                    early_wakeup_id_q[0] <= '0;
                    early_wakeup_id_q[1] <= '0;
                    early_wakeup_rd_q[0] <= '0;
                    early_wakeup_rd_q[1] <= '0;
                    alu_in_valid_q <= 1'b0;
                    bru_in_valid_q <= 1'b0;
                    agu_in_valid_q <= 1'b0;
                    agu_in_req_q <= '0;
                    csr_in_valid_q <= 1'b0;
                    mul_in_valid_q <= 1'b0;
                    dual_in_q <= '0;
                end else begin
                    issue_ex_q <= issue_ex_d;
                    // Wakeup qualification is a control token, not execution
                    // payload.  Derive it directly from the selected lane so
                    // the LSU request/credit fields in issue_ex_d cannot
                    // re-enter this D cone through struct packing.
                    if (id_advance) begin
                        early_wakeup_valid_q[0] <= lane_a_early_valid;
                        early_wakeup_valid_q[1] <= lane_b_early_valid;
                        early_wakeup_id_q[0] <= lane_a_uop.dst.rob_tag;
                        early_wakeup_id_q[1] <= lane_b_uop.dst.rob_tag;
                        early_wakeup_rd_q[0] <= lane_a_uop.dst.rd_addr;
                        early_wakeup_rd_q[1] <= lane_b_uop.dst.rd_addr;
                    end else begin
                        early_wakeup_valid_q[0] <= 1'b0;
                        early_wakeup_valid_q[1] <= 1'b0;
                        early_wakeup_id_q[0] <= '0;
                        early_wakeup_id_q[1] <= '0;
                        early_wakeup_rd_q[0] <= '0;
                        early_wakeup_rd_q[1] <= '0;
                    end
                    // Each execution class has its own input cell.  The
                    // values are captured at the same architectural boundary
                    // as issue_ex_q. Their local completion result supplies
                    // the matching registered early token in the next cycle.
                    alu_in_valid_q <= issue_ex_d.valid;
                    alu_in_operand_a_q <= operand_a_for(lane_a_uop, lane_a_src0_local);
                    alu_in_operand_b_q <= operand_b_for(lane_a_uop, lane_a_src1_local);
                    alu_in_operator_q <= issue_ex_d.operator_info;
                    alu_in_operator_type_q <= issue_ex_d.operator_type;
                    alu_in_rd_wen_q <= issue_ex_d.rd_wen;
                    alu_in_rd_addr_q <= issue_ex_d.rd_addr;
                    alu_in_producer_id_q <= issue_ex_d.producer_id;
                    bru_in_valid_q <= issue_ex_d.valid;
                    bru_in_operand_a_q <= operand_a_for(lane_a_uop, lane_a_src0_local);
                    bru_in_operand_b_q <= operand_b_for(lane_a_uop, lane_a_src1_local);
                    bru_in_bt_operand_a_q <= lane_a_uop.decode.bt_a_rs_sel ?
                        lane_a_src0_local : lane_a_uop.decode.pc;
                    bru_in_bt_operand_b_q <= lane_a_src1_local;
                    bru_in_operator_q <= issue_ex_d.operator_info;
                    bru_in_operator_type_q <= issue_ex_d.operator_type;
                    bru_in_jalr_q <= issue_ex_d.jalr;
                    bru_in_branch_target_q <= issue_ex_d.branch_target;
                    bru_in_branch_next_pc_q <= issue_ex_d.branch_next_pc;
                    bru_in_pc_q <= issue_ex_d.pc;
                    bru_in_pred_hit_q <= issue_ex_d.pred_hit;
                    bru_in_pred_taken_q <= issue_ex_d.pred_taken;
                    bru_in_pred_target_q <= issue_ex_d.pred_target;
                    bru_in_pred_counter_q <= issue_ex_d.pred_counter;
                    bru_in_pred_bht_index_q <= issue_ex_d.pred_bht_index;
                    agu_in_valid_q <= issue_ex_d.lsu_req.valid;
                    agu_in_operand_a_q <= operand_a_for(lane_a_uop, lane_a_src0_local);
                    agu_in_operand_b_q <= operand_b_for(lane_a_uop, lane_a_src1_local);
                    agu_in_req_q <= issue_ex_d.lsu_req;
                    agu_in_req_q.store_data <= lane_a_src1_local;
                    agu_in_req_q.store_data_valid <= issue_ex_d.lsu_req.valid;
                    csr_in_valid_q <= issue_ex_d.valid;
                    csr_in_operand_a_q <= operand_a_for(lane_a_uop, lane_a_src0_local);
                    csr_in_operator_type_q <= issue_ex_d.operator_type;
                    csr_in_raddr_q <= issue_ex_d.csr_raddr;
                    csr_in_waddr_q <= issue_ex_d.csr_waddr;
                    csr_in_op_info_q <= issue_ex_d.csr_op_info;
                    csr_in_sys_info_q <= issue_ex_d.sys_op_info;
                    mul_in_valid_q <= issue_ex_d.valid;
                    mul_in_operand_a_q <= operand_a_for(lane_a_uop, lane_a_src0_local);
                    mul_in_operand_b_q <= operand_b_for(lane_a_uop, lane_a_src1_local);
                    mul_in_operator_q <= issue_ex_d.operator_info;
                    mul_in_operator_type_q <= issue_ex_d.operator_type;
                    dual_in_q <= '0;
                    dual_in_q.operand_a <= operand_a_for(lane_b_uop, lane_b_src0_local);
                    dual_in_q.operand_b <= operand_b_for(lane_b_uop, lane_b_src1_local);
                    dual_in_q.branch_operand_a <= lane_b_src0_local;
                    dual_in_q.branch_operand_b <= lane_b_src1_local;
                    dual_in_q.branch_imm <= issue_ex_d.lane1_branch_imm;
                    dual_in_q.operator_info <= issue_ex_d.lane1_operator_info;
                    dual_in_q.operator_type <= issue_ex_d.lane1_operator_type;
                    dual_in_q.operator_lsu <= issue_ex_d.lane1_operator_lsu;
                    dual_in_q.store_data <= issue_ex_d.lane1_store_data;
                    dual_in_q.store_data_valid <= issue_ex_d.lane1_store_data_valid;
                    dual_in_q.rd_addr <= issue_ex_d.lane1_rd_addr;
                    dual_in_q.rd_wen <= issue_ex_d.lane1_rd_wen;
                    dual_in_q.producer_id <= issue_ex_d.lane1_producer_id;
                    dual_in_q.producer_tracked <= issue_ex_d.lane1_producer_tracked;
                    dual_in_q.valid <= issue_ex_d.lane1_valid;
                    dual_in_q.pc <= issue_ex_d.lane1_pc;
                    dual_in_q.instr <= issue_ex_d.lane1_instr;
                    dual_in_q.jalr <= issue_ex_d.lane1_jalr;
                    dual_in_q.branch_target <= issue_ex_d.lane1_branch_target;
                    dual_in_q.branch_next_pc <= issue_ex_d.lane1_branch_next_pc;
                    dual_in_q.pred_hit <= issue_ex_d.lane1_pred_hit;
                    dual_in_q.pred_taken <= issue_ex_d.lane1_pred_taken;
                    dual_in_q.pred_target <= issue_ex_d.lane1_pred_target;
                    dual_in_q.pred_counter <= issue_ex_d.lane1_pred_counter;
                    dual_in_q.pred_bht_index <= issue_ex_d.lane1_pred_bht_index;
                end
            end
        end
    end
    assign issue_ex_o = issue_ex_q;
    assign alu_in_valid_o = alu_in_valid_q;
    assign alu_in_operand_a_o = alu_in_operand_a_q;
    assign alu_in_operand_b_o = alu_in_operand_b_q;
    assign alu_in_operator_o = alu_in_operator_q;
    assign alu_in_operator_type_o = alu_in_operator_type_q;
    assign alu_in_rd_wen_o = alu_in_rd_wen_q;
    assign alu_in_rd_addr_o = alu_in_rd_addr_q;
    assign alu_in_producer_id_o = alu_in_producer_id_q;
    assign bru_in_valid_o = bru_in_valid_q;
    assign bru_in_operand_a_o = bru_in_operand_a_q;
    assign bru_in_operand_b_o = bru_in_operand_b_q;
    assign bru_in_bt_operand_a_o = bru_in_bt_operand_a_q;
    assign bru_in_bt_operand_b_o = bru_in_bt_operand_b_q;
    assign bru_in_operator_o = bru_in_operator_q;
    assign bru_in_operator_type_o = bru_in_operator_type_q;
    assign bru_in_jalr_o = bru_in_jalr_q;
    assign bru_in_branch_target_o = bru_in_branch_target_q;
    assign bru_in_branch_next_pc_o = bru_in_branch_next_pc_q;
    assign bru_in_pc_o = bru_in_pc_q;
    assign bru_in_pred_hit_o = bru_in_pred_hit_q;
    assign bru_in_pred_taken_o = bru_in_pred_taken_q;
    assign bru_in_pred_target_o = bru_in_pred_target_q;
    assign bru_in_pred_counter_o = bru_in_pred_counter_q;
    assign bru_in_pred_bht_index_o = bru_in_pred_bht_index_q;
    assign agu_in_valid_o = agu_in_valid_q;
    assign agu_in_operand_a_o = agu_in_operand_a_q;
    assign agu_in_operand_b_o = agu_in_operand_b_q;
    assign agu_in_req_o = agu_in_req_q;
    assign csr_in_valid_o = csr_in_valid_q;
    assign csr_in_operand_a_o = csr_in_operand_a_q;
    assign csr_in_operator_type_o = csr_in_operator_type_q;
    assign csr_in_raddr_o = csr_in_raddr_q;
    assign csr_in_waddr_o = csr_in_waddr_q;
    assign csr_in_op_info_o = csr_in_op_info_q;
    assign csr_in_sys_info_o = csr_in_sys_info_q;
    assign mul_in_valid_o = mul_in_valid_q;
    assign mul_in_operand_a_o = mul_in_operand_a_q;
    assign mul_in_operand_b_o = mul_in_operand_b_q;
    assign mul_in_operator_o = mul_in_operator_q;
    assign mul_in_operator_type_o = mul_in_operator_type_q;
    assign dual_in_o = dual_in_q;

`ifndef SYNTHESIS
    wire issue_valid_ff = issue_pkt_i.valid;
    wire [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff =
        issue_pkt_i.decode.operator_type;
    wire rs1_completion_fwd = 1'b0;
    wire rs2_completion_fwd = 1'b0;
    wire issue_plain_alu_op =
        issue_operator_type_ff[OPERATOR_TYPE_ALU] &&
        !issue_operator_type_ff[OPERATOR_TYPE_BITMANIP];
    wire issue_early_alu_valid_ff = 1'b0;
    wire [5:0] issue_early_kind_ff = '0;
    wire [REGS_ADDR_WIDTH-1:0] issue_early_alu_addr_ff = '0;
    wire rs1_issue_early_alu_fwd = 1'b0;
    wire rs2_issue_early_alu_fwd = 1'b0;
    wire issue_simple_alu_op = issue_plain_alu_op;
`endif
endmodule


// 第二槽位仅执行无异常的单周期整数/位操作。输入与输出各打一拍，
// 使其完成时序与主 ALU 完成总线保持一致。
module ydrasil_dual_alu
import ydrasil_pkg::*;
(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           flush_i,
    input  wire                           interrupt_i,
    input  wire                           valid_i,
    input  wire [REGS_DATA_WIDTH-1:0]     operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]     operand_b_i,
    input  wire [REGS_DATA_WIDTH-1:0]     branch_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]     branch_operand_b_i,
    input  wire [REGS_DATA_WIDTH-1:0]     branch_imm_i,
    input  wire [OPERATOR_WIDTH-1:0]      operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] operator_type_i,
    input  wire [OP_LSU_INFO_WIDTH-1:0]   operator_lsu_i,
    input  wire [REGS_DATA_WIDTH-1:0]     store_data_i,
    input  wire                           store_data_valid_i,
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
    input  wire [INST_ADDR_WIDTH-1:0]     pred_bht_index_i,
    input  wire [INST_ADDR_WIDTH-1:0]     trap_redirect_addr_i,
    output ydrasil_gpr_fwd_pkt_t          completion_o,
    output ydrasil_lsu_req_pkt_t          lsu_req_o,
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
    reg load_q;
    wire [REGS_DATA_WIDTH-1:0] exec_operand_a = operand_a_i;
    wire [REGS_DATA_WIDTH-1:0] exec_operand_b = operand_b_i;
    wire [REGS_DATA_WIDTH-1:0] alu_result;
    wire [REGS_DATA_WIDTH-1:0] fast_b_shadd_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_SH1ADD]}} &
         ((exec_operand_a << 1) + exec_operand_b)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SH2ADD]}} &
         ((exec_operand_a << 2) + exec_operand_b)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SH3ADD]}} &
         ((exec_operand_a << 3) + exec_operand_b));
    wire [REGS_DATA_WIDTH-1:0] fast_b_logic_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_ANDN]}} &
         (exec_operand_a & ~exec_operand_b)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_ORN]}} &
         (exec_operand_a | ~exec_operand_b)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_XNOR]}} &
         ~(exec_operand_a ^ exec_operand_b));
    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_a = exec_operand_a;
    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_b = exec_operand_b;
    wire [REGS_DATA_WIDTH-1:0] fast_b_minmax_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_MIN]}} &
         ((signed_operand_a <= signed_operand_b) ? exec_operand_a : exec_operand_b)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_MAX]}} &
         ((signed_operand_a >= signed_operand_b) ? exec_operand_a : exec_operand_b)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_MINU]}} &
         ((exec_operand_a <= exec_operand_b) ? exec_operand_a : exec_operand_b)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_MAXU]}} &
         ((exec_operand_a >= exec_operand_b) ? exec_operand_a : exec_operand_b));
    wire [REGS_DATA_WIDTH-1:0] fast_b_extend_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_REV8]}} &
         {exec_operand_a[7:0], exec_operand_a[15:8],
          exec_operand_a[23:16], exec_operand_a[31:24]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SEXT_B]}} &
         {{24{exec_operand_a[7]}}, exec_operand_a[7:0]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SEXT_H]}} &
         {{16{exec_operand_a[15]}}, exec_operand_a[15:0]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_ZEXT_H]}} &
         {16'b0, exec_operand_a[15:0]});
    wire [REGS_DATA_WIDTH-1:0] fast_bitmanip_result =
        fast_b_shadd_result | fast_b_logic_result | fast_b_minmax_result |
        fast_b_extend_result;

    wire alu_unused_comp;
    wire alu_unused_wen;
    wire [REGS_ADDR_WIDTH-1:0] alu_unused_waddr;
    wire memory_op = operator_type_i[OPERATOR_TYPE_LOAD] ||
        operator_type_i[OPERATOR_TYPE_STORE];
    // Memory operand_b is the decoded immediate.  rs2 bypass supplies store
    // data and must not replace the immediate on the AGU carry chain.
    wire [BUS_ADDR_WIDTH-1:0] agu_addr = exec_operand_a + operand_b_i;

    always_comb begin
        lsu_req_o = '0;
        lsu_req_o.valid = valid_i && memory_op && !interrupt_i;
        lsu_req_o.is_load = operator_type_i[OPERATOR_TYPE_LOAD];
        lsu_req_o.is_store = operator_type_i[OPERATOR_TYPE_STORE];
        lsu_req_o.op = operator_lsu_i;
        lsu_req_o.addr = agu_addr;
        lsu_req_o.addr_is_dtcm =
            (agu_addr[31:DTCM_ADDR_WIDTH+2] ==
             DTCM_BASE_ADDR[31:DTCM_ADDR_WIDTH+2]);
        lsu_req_o.rd_addr = rd_addr_i;
        lsu_req_o.producer_id = producer_id_i;
        lsu_req_o.producer_tracked = producer_tracked_i;
        lsu_req_o.store_data = store_data_i;
        lsu_req_o.store_data_valid = store_data_valid_i;
        lsu_req_o.fp_load = 1'b0;
        lsu_req_o.fp_rd_addr = '0;
        if (operator_lsu_i[OP_LSU_SB])
            lsu_req_o.store_mask = 4'b0001 << agu_addr[1:0];
        else if (operator_lsu_i[OP_LSU_SH])
            lsu_req_o.store_mask = agu_addr[1] ? 4'b1100 : 4'b0011;
        else if (operator_lsu_i[OP_LSU_SW])
            lsu_req_o.store_mask = 4'b1111;
    end

    ydrasil_alu u_dual_alu (
        .operand_a_i(exec_operand_a), .operand_b_i(exec_operand_b),
        .operator_i(operator_i), .operator_type_i(operator_type_i),
        .id_rf_waddr_rd_i(rd_addr_i), .id_alu_rf_wen_rd_i(rd_wen_i),
        .interrupt_i(interrupt_i), .comp_result_o(alu_unused_comp),
        .alu_result_o(alu_result), .alu_rf_wen_rd_o(alu_unused_wen),
        .alu_rf_waddr_rd_o(alu_unused_waddr)
    );

    ydrasil_bru u_lane_b_bru (
        .clk(clk),
        .rst_n(rst_n),
        .flush_i(flush_i),
        .operand_a_i(branch_operand_a_i),
        .operand_b_i(branch_operand_b_i),
        .bt_a_operand_i(jalr_i ? branch_operand_a_i : pc_i),
        .bt_b_operand_i(branch_imm_i),
        .operator_i(operator_i),
        .operator_type_i(operator_type_i),
        .id_ex_valid_i(valid_i),
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
            load_q <= 1'b0;
        end else begin
            valid_q <= valid_i && !interrupt_i;
            pc_q <= pc_i;
            instr_q <= instr_i;
            load_q <= operator_type_i[OPERATOR_TYPE_LOAD];
        end
    end

    // Lane B completion is captured by the typed ALU result array at WB. The
    // remaining q state is commit trace metadata, not an execution bypass.
    assign completion_o.valid = valid_i && rd_wen_i && !memory_op &&
        !interrupt_i && (rd_addr_i != '0);
    assign completion_o.producer_id = producer_id_i;
    assign completion_o.producer_tracked = producer_tracked_i;
    assign completion_o.addr = rd_addr_i;
    assign completion_o.data = operator_type_i[OPERATOR_TYPE_BITMANIP] ?
        fast_bitmanip_result : alu_result;
    assign instret_valid_o = valid_q && !load_q;
    assign commit_pc_o = pc_q;
    assign commit_instr_o = instr_q;
endmodule
