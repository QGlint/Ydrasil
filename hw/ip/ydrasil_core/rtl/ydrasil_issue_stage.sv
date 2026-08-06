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
    input  ydrasil_compact_uop_t       issue_pkt_i,
    input  ydrasil_compact_uop_t       issue_pkt1_i,
    input  ydrasil_rob_source_state_t  issue_src0_state_i,
    input  ydrasil_rob_source_state_t  issue_src1_state_i,
    input  ydrasil_rob_source_state_t  issue_src2_state_i,
    input  ydrasil_rob_source_state_t  issue_src3_state_i,
    input  wire [DATA_WIDTH-1:0]       issue_src0_value_i,
    input  wire [DATA_WIDTH-1:0]       issue_src1_value_i,
    input  wire [DATA_WIDTH-1:0]       issue_src2_value_i,
    input  wire [DATA_WIDTH-1:0]       issue_src3_value_i,
    input  wire [DATA_WIDTH-1:0]       early_main_bypass_data_i,
    input  wire [DATA_WIDTH-1:0]       early_dual_bypass_data_i,
    input  wire                        lsu_idle_i,
    input  wire [1:0]                  lsu_credit_i,
    input  ydrasil_reservation_pkt_t   dtcm_reservation_i,
    input  wire [DATA_WIDTH-1:0]       dtcm_resp_data_i,
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
    output wire                        dual_bru_valid_o,
    output ydrasil_lane_b_bru_payload_t dual_bru_payload_o,
    output wire [4:0]                  rf_addr_rs1_o,
    output wire [4:0]                  rf_addr_rs2_o,
    output wire [4:0]                  rf_addr_rs3_o,
    output wire [4:0]                  rf_addr_rs4_o,
    input  wire [DATA_WIDTH-1:0]       rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]       rf_rdata_rs2_i,
	input  wire [DATA_WIDTH-1:0]       rf_rdata_rs3_i,
	input  wire [DATA_WIDTH-1:0]       rf_rdata_rs4_i
);
    function automatic [OPERATOR_TYPE_WIDTH-1:0] uop_operator_type(
        input ydrasil_compact_uop_t uop
    );
        begin
            uop_operator_type = '0;
            unique case (uop.op_class)
                UOP_CLASS_BJP:
                    uop_operator_type[OPERATOR_TYPE_BJP] = 1'b1;
                UOP_CLASS_LOAD:
                    uop_operator_type[OPERATOR_TYPE_LOAD] = 1'b1;
                UOP_CLASS_STORE:
                    uop_operator_type[OPERATOR_TYPE_STORE] = 1'b1;
                UOP_CLASS_CSR:
                    uop_operator_type[OPERATOR_TYPE_CSR] = 1'b1;
                UOP_CLASS_SYS: begin
                    uop_operator_type[OPERATOR_TYPE_CSR] = 1'b1;
                    uop_operator_type[OPERATOR_TYPE_SYS] = 1'b1;
                end
                UOP_CLASS_MUL:
                    uop_operator_type[OPERATOR_TYPE_MUL] = 1'b1;
                UOP_CLASS_BITMANIP:
                    uop_operator_type[OPERATOR_TYPE_BITMANIP] = 1'b1;
                default:
                    uop_operator_type[OPERATOR_TYPE_ALU] = 1'b1;
            endcase
        end
    endfunction

    function automatic [OPERATOR_WIDTH-1:0] uop_operator_info(
        input ydrasil_compact_uop_t uop
    );
        begin
            uop_operator_info = '0;
            if (uop.subop < UOP_SUBOP_WIDTH'(OPERATOR_WIDTH))
                uop_operator_info[uop.subop] = 1'b1;
        end
    endfunction

    function automatic [OP_LSU_INFO_WIDTH-1:0] uop_operator_lsu(
        input ydrasil_compact_uop_t uop
    );
        begin
            uop_operator_lsu = '0;
            uop_operator_lsu[uop.lsu_subop] = 1'b1;
        end
    endfunction

    function automatic logic uop_memory(input ydrasil_compact_uop_t uop);
        uop_memory = (uop.op_class == UOP_CLASS_LOAD) ||
            (uop.op_class == UOP_CLASS_STORE);
    endfunction

    function automatic logic uop_early_bitmanip(
        input ydrasil_compact_uop_t uop
    );
        uop_early_bitmanip =
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_SH1ADD)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_SH2ADD)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_SH3ADD)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_PACK)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_PACKH)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_REV8)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_B)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_H)) ||
            (uop.subop == UOP_SUBOP_WIDTH'(OP_B_ZEXT_H));
    endfunction

    // Completion state is committed into the producer file on the same edge
    // that the global completion bus is observed. Early ALU wakeup carries
    // only a producer token through Issue; the corresponding safe result is
    // selected after each FU input cell. This keeps the full completion bus
    // and its slow bitmanip paths out of the Issue operand cone. DTCM wakeup
    // remains a narrow tagged reservation with the same local-data pattern.
    reg lsu_idle_q;
    reg issue_at_rob_head_q;
    reg early_wakeup_valid_q [0:1];
    producer_id_t early_wakeup_id_q [0:1];
    reg [REGS_ADDR_WIDTH-1:0] early_wakeup_rd_q [0:1];
    // Token identity is registered here. Its data is reconstructed from the
    // producer's registered FU input cell through a restricted result cone
    // during the following Issue cycle.

    reg alu_in_valid_q;
    reg [DATA_WIDTH-1:0] alu_in_operand_a_q, alu_in_operand_b_q;
    reg [OPERATOR_WIDTH-1:0] alu_in_operator_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] alu_in_operator_type_q;
    reg alu_in_rd_wen_q;
    reg [REGS_ADDR_WIDTH-1:0] alu_in_rd_addr_q;
    producer_id_t alu_in_producer_id_q;
    reg [DATA_WIDTH-1:0] lane_a_pc_q;
    reg agu_in_valid_q;
    reg [DATA_WIDTH-1:0] agu_in_operand_a_q, agu_in_operand_b_q;
    ydrasil_lsu_req_pkt_t agu_in_req_q;
    reg csr_in_valid_q;
    reg [DATA_WIDTH-1:0] csr_in_operand_a_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] csr_in_operator_type_q;
    reg [CSR_ADDR_WIDTH-1:0] csr_in_raddr_q, csr_in_waddr_q;
    reg [OP_CSR_INFO_WIDTH-1:0] csr_in_op_info_q;
	reg [OP_SYS_INFO_WIDTH-1:0] csr_in_sys_info_q;
	reg illegal_instr_q;
    reg mul_in_valid_q;
    reg [DATA_WIDTH-1:0] mul_in_operand_a_q, mul_in_operand_b_q;
    reg [OPERATOR_WIDTH-1:0] mul_in_operator_q;
    reg [OPERATOR_TYPE_WIDTH-1:0] mul_in_operator_type_q;
    ydrasil_lane_b_meta_t dual_meta_q;
    reg dual_alu_valid_q, dual_bru_valid_q;
    ydrasil_lane_b_alu_payload_t dual_alu_payload_q;
    ydrasil_lane_b_bru_payload_t dual_bru_payload_q;
    reg alu_in_operand_a_dtcm_q, alu_in_operand_b_dtcm_q;
    reg agu_in_operand_a_dtcm_q, agu_in_store_data_dtcm_q;
    reg csr_in_operand_a_dtcm_q;
    reg mul_in_operand_a_dtcm_q, mul_in_operand_b_dtcm_q;
    reg dual_in_operand_a_dtcm_q, dual_in_operand_b_dtcm_q;
    reg dual_in_branch_operand_a_dtcm_q, dual_in_branch_operand_b_dtcm_q;
    reg alu_in_operand_a_early_main_q, alu_in_operand_a_early_dual_q;
    reg alu_in_operand_b_early_main_q, alu_in_operand_b_early_dual_q;
    reg agu_in_operand_a_early_main_q, agu_in_operand_a_early_dual_q;
    reg agu_in_store_data_early_main_q, agu_in_store_data_early_dual_q;
    reg csr_in_operand_a_early_main_q, csr_in_operand_a_early_dual_q;
    reg mul_in_operand_a_early_main_q, mul_in_operand_a_early_dual_q;
    reg mul_in_operand_b_early_main_q, mul_in_operand_b_early_dual_q;
    reg dual_in_operand_a_early_main_q, dual_in_operand_a_early_dual_q;
    reg dual_in_operand_b_early_main_q, dual_in_operand_b_early_dual_q;
    reg dual_in_branch_operand_a_early_main_q;
    reg dual_in_branch_operand_a_early_dual_q;
    reg dual_in_branch_operand_b_early_main_q;
    reg dual_in_branch_operand_b_early_dual_q;
    // DTCM data normally comes straight from the LSU response FF.  The Issue
    // cells can be held for backend backpressure, however, while a later load
    // replaces that response. Snapshot the selected response on the first
    // held edge so an accepted request keeps its original load data.
    reg [DATA_WIDTH-1:0] dtcm_stall_data_q;
    reg dtcm_stall_data_valid_q;
    // Each bank captures the result associated with the prior-cycle wakeup
    // token on the same edge that its consumer selector is accepted. The
    // bank then stays stable while Issue is stalled.
    reg [DATA_WIDTH-1:0] early_main_data_q;
    reg [DATA_WIDTH-1:0] early_dual_data_q;
    wire dtcm_bypass_active_q =
        alu_in_operand_a_dtcm_q || alu_in_operand_b_dtcm_q ||
        agu_in_operand_a_dtcm_q ||
        agu_in_store_data_dtcm_q || csr_in_operand_a_dtcm_q ||
		mul_in_operand_a_dtcm_q || mul_in_operand_b_dtcm_q ||
		dual_in_operand_a_dtcm_q ||
		dual_in_operand_b_dtcm_q || dual_in_branch_operand_a_dtcm_q ||
		dual_in_branch_operand_b_dtcm_q;
    wire [DATA_WIDTH-1:0] dtcm_bypass_data = dtcm_stall_data_valid_q ?
        dtcm_stall_data_q : dtcm_resp_data_i;
    wire [DATA_WIDTH-1:0] early_main_bypass_data = early_main_data_q;
    wire [DATA_WIDTH-1:0] early_dual_bypass_data = early_dual_data_q;
    wire src0_ready;
    wire src1_ready;
    wire src2_ready;
    wire src3_ready;
    wire [DATA_WIDTH-1:0] slot0_src0;
    wire [DATA_WIDTH-1:0] slot0_src1;
    wire [DATA_WIDTH-1:0] slot1_src0;
    wire [DATA_WIDTH-1:0] slot1_src1;
    wire slot0_src0_dtcm_hit;
    wire slot0_src1_dtcm_hit;
    wire slot1_src0_dtcm_hit;
    wire slot1_src1_dtcm_hit;
    wire slot0_src0_early_main_hit;
    wire slot0_src1_early_main_hit;
    wire slot1_src0_early_main_hit;
    wire slot1_src1_early_main_hit;
    wire slot0_src0_early_dual_hit;
    wire slot0_src1_early_dual_hit;
    wire slot1_src0_early_dual_hit;
    wire slot1_src1_early_dual_hit;

    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source0 (
        .source_i(issue_pkt_i.src0), .state_i(issue_src0_state_i),
        .value_i(issue_src0_value_i), .arf_i(rf_rdata_rs1_i),
        .dtcm_reservation_i(dtcm_reservation_i),
        .early_main_valid_i(early_wakeup_valid_q[0]),
        .early_main_id_i(early_wakeup_id_q[0]),
        .early_main_rd_i(early_wakeup_rd_q[0]),
        .early_dual_valid_i(early_wakeup_valid_q[1]),
        .early_dual_id_i(early_wakeup_id_q[1]),
        .early_dual_rd_i(early_wakeup_rd_q[1]),
        .ready_o(src0_ready), .data_o(slot0_src0),
        .dtcm_hit_o(slot0_src0_dtcm_hit),
        .early_main_hit_o(slot0_src0_early_main_hit),
        .early_dual_hit_o(slot0_src0_early_dual_hit));
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source1 (
        .source_i(issue_pkt_i.src1), .state_i(issue_src1_state_i),
        .value_i(issue_src1_value_i), .arf_i(rf_rdata_rs2_i),
        .dtcm_reservation_i(dtcm_reservation_i),
        .early_main_valid_i(early_wakeup_valid_q[0]),
        .early_main_id_i(early_wakeup_id_q[0]),
        .early_main_rd_i(early_wakeup_rd_q[0]),
        .early_dual_valid_i(early_wakeup_valid_q[1]),
        .early_dual_id_i(early_wakeup_id_q[1]),
        .early_dual_rd_i(early_wakeup_rd_q[1]),
        .ready_o(src1_ready), .data_o(slot0_src1),
        .dtcm_hit_o(slot0_src1_dtcm_hit),
        .early_main_hit_o(slot0_src1_early_main_hit),
        .early_dual_hit_o(slot0_src1_early_dual_hit));
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source2 (
        .source_i(issue_pkt1_i.src0), .state_i(issue_src2_state_i),
        .value_i(issue_src2_value_i), .arf_i(rf_rdata_rs3_i),
        .dtcm_reservation_i(dtcm_reservation_i),
        .early_main_valid_i(early_wakeup_valid_q[0]),
        .early_main_id_i(early_wakeup_id_q[0]),
        .early_main_rd_i(early_wakeup_rd_q[0]),
        .early_dual_valid_i(early_wakeup_valid_q[1]),
        .early_dual_id_i(early_wakeup_id_q[1]),
        .early_dual_rd_i(early_wakeup_rd_q[1]),
        .ready_o(src2_ready), .data_o(slot1_src0),
        .dtcm_hit_o(slot1_src0_dtcm_hit),
        .early_main_hit_o(slot1_src0_early_main_hit),
        .early_dual_hit_o(slot1_src0_early_dual_hit));
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source3 (
        .source_i(issue_pkt1_i.src1), .state_i(issue_src3_state_i),
        .value_i(issue_src3_value_i), .arf_i(rf_rdata_rs4_i),
        .dtcm_reservation_i(dtcm_reservation_i),
        .early_main_valid_i(early_wakeup_valid_q[0]),
        .early_main_id_i(early_wakeup_id_q[0]),
        .early_main_rd_i(early_wakeup_rd_q[0]),
        .early_dual_valid_i(early_wakeup_valid_q[1]),
        .early_dual_id_i(early_wakeup_id_q[1]),
        .early_dual_rd_i(early_wakeup_rd_q[1]),
        .ready_o(src3_ready), .data_o(slot1_src1),
        .dtcm_hit_o(slot1_src1_dtcm_hit),
        .early_main_hit_o(slot1_src1_early_main_hit),
        .early_dual_hit_o(slot1_src1_early_dual_hit));
    wire slot0_store = issue_pkt_i.op_class == UOP_CLASS_STORE;
    wire slot0_scoreboard_stall = issue_pkt_i.valid &&
        (!src0_ready || (!src1_ready && !slot0_store));
    wire slot1_active = issue_pkt_i.pair_eligible && issue_pkt1_i.valid;
    wire slot1_store = issue_pkt1_i.op_class == UOP_CLASS_STORE;
    wire slot1_scoreboard_stall = slot1_active &&
        (!src2_ready || (!src3_ready && !slot1_store));
    wire slot0_lsu_stall = uop_memory(issue_pkt_i) &&
        (lsu_credit_i == 2'd0);
    wire slot1_lsu_stall = slot1_active && uop_memory(issue_pkt1_i) &&
        (lsu_credit_i == 2'd0);
    wire serialize_stall = ((issue_pkt_i.op_class == UOP_CLASS_CSR) ||
        (issue_pkt_i.op_class == UOP_CLASS_SYS) || issue_pkt_i.fence_i) &&
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
        issue_pkt_i.fence_i;

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
                issue_fence_next_pc_q <= issue_pkt_i.pc + 32'd4;
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
    ydrasil_compact_uop_t lane_a_uop;
    ydrasil_compact_uop_t lane_b_uop;
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

    wire [DATA_WIDTH-1:0] slot0_src0_local = slot0_src0;
    wire [DATA_WIDTH-1:0] slot0_src1_local = slot0_src1;
    wire [DATA_WIDTH-1:0] slot1_src0_local = slot1_src0;
    wire [DATA_WIDTH-1:0] slot1_src1_local = slot1_src1;
    wire [DATA_WIDTH-1:0] lane_a_src0 = swap_pair ? slot1_src0 : slot0_src0;
    wire [DATA_WIDTH-1:0] lane_a_src1 = swap_pair ? slot1_src1 : slot0_src1;
    wire lane_b_uses_slot0 = head0_b_only || swap_pair;
    wire lane_b_src1_ready = lane_b_uses_slot0 ? src1_ready : src3_ready;
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

    // DTCM data is deliberately not substituted into the source table above.
    // Capture only these compact, generation-qualified selectors on the Issue
    // edge, then use the LSU response FF after each execution input cell.
    wire lane_a_src0_dtcm_hit = swap_pair ?
        slot1_src0_dtcm_hit : slot0_src0_dtcm_hit;
    wire lane_a_src1_dtcm_hit = swap_pair ?
        slot1_src1_dtcm_hit : slot0_src1_dtcm_hit;
    wire lane_b_src0_dtcm_hit = lane_b_uses_slot0 ?
        slot0_src0_dtcm_hit : slot1_src0_dtcm_hit;
    wire lane_b_src1_dtcm_hit = lane_b_uses_slot0 ?
        slot0_src1_dtcm_hit : slot1_src1_dtcm_hit;
    wire lane_a_src0_early_main_hit = swap_pair ?
        slot1_src0_early_main_hit : slot0_src0_early_main_hit;
    wire lane_a_src1_early_main_hit = swap_pair ?
        slot1_src1_early_main_hit : slot0_src1_early_main_hit;
    wire lane_b_src0_early_main_hit = lane_b_uses_slot0 ?
        slot0_src0_early_main_hit : slot1_src0_early_main_hit;
    wire lane_b_src1_early_main_hit = lane_b_uses_slot0 ?
        slot0_src1_early_main_hit : slot1_src1_early_main_hit;
    wire lane_a_src0_early_dual_hit = swap_pair ?
        slot1_src0_early_dual_hit : slot0_src0_early_dual_hit;
    wire lane_a_src1_early_dual_hit = swap_pair ?
        slot1_src1_early_dual_hit : slot0_src1_early_dual_hit;
    wire lane_b_src0_early_dual_hit = lane_b_uses_slot0 ?
        slot0_src0_early_dual_hit : slot1_src0_early_dual_hit;
    wire lane_b_src1_early_dual_hit = lane_b_uses_slot0 ?
        slot0_src1_early_dual_hit : slot1_src1_early_dual_hit;
    wire lane_a_accept = id_advance && lane_a_valid;
    wire lane_b_accept = id_advance && lane_b_valid;
    wire lane_a_op_a_src = !lane_a_uop.operand_a_pc_sel &&
        !lane_a_uop.operand_a_imm_sel;
    wire lane_a_op_b_src = !lane_a_uop.operand_b_jump_sel &&
        lane_a_uop.operand_b_rs_sel;
    wire lane_b_op_a_src = !lane_b_uop.operand_a_pc_sel &&
        !lane_b_uop.operand_a_imm_sel;
    wire lane_b_op_b_src = !lane_b_uop.operand_b_jump_sel &&
        lane_b_uop.operand_b_rs_sel;
    wire lane_a_alu_exec =
        (lane_a_uop.op_class == UOP_CLASS_ALU) ||
        (lane_a_uop.op_class == UOP_CLASS_BITMANIP);

    wire [OPERATOR_WIDTH-1:0] lane_a_operator_info =
        uop_operator_info(lane_a_uop);
    wire [OPERATOR_TYPE_WIDTH-1:0] lane_a_operator_type =
        uop_operator_type(lane_a_uop);
    assign rf_addr_rs1_o = issue_pkt_i.src0.arch_addr;
    assign rf_addr_rs2_o = issue_pkt_i.src1.arch_addr;
    assign rf_addr_rs3_o = issue_pkt1_i.src0.arch_addr;
    assign rf_addr_rs4_o = issue_pkt1_i.src1.arch_addr;

    wire [DATA_WIDTH-1:0] lane_b_operand_a_local =
        lane_b_uop.operand_a_pc_sel ? lane_b_uop.pc :
        lane_b_uop.operand_a_imm_sel ? lane_b_uop.imm :
        lane_b_src0_local;
    wire [DATA_WIDTH-1:0] lane_b_operand_b_local =
        lane_b_uop.operand_b_jump_sel ? 32'd4 :
        lane_b_uop.operand_b_rs_sel ? lane_b_src1_local :
        lane_b_uop.imm;
    wire [DATA_WIDTH-1:0] lane_a_operand_a_local =
        lane_a_uop.operand_a_pc_sel ? lane_a_uop.pc :
        lane_a_uop.operand_a_imm_sel ? lane_a_uop.imm :
        lane_a_src0_local;
    wire [DATA_WIDTH-1:0] lane_a_operand_b_local =
        lane_a_uop.operand_b_jump_sel ? 32'd4 :
        lane_a_uop.operand_b_rs_sel ? lane_a_src1_local :
        lane_a_uop.imm;
    wire slot0_early_bitmanip_supported = uop_early_bitmanip(issue_pkt_i);
    wire slot1_early_bitmanip_supported = uop_early_bitmanip(issue_pkt1_i);
    wire slot0_early_exec =
        (issue_pkt_i.op_class == UOP_CLASS_ALU) ||
        (issue_pkt_i.op_class == UOP_CLASS_BJP) ||
        ((issue_pkt_i.op_class == UOP_CLASS_BITMANIP) &&
         slot0_early_bitmanip_supported);
    wire slot1_early_exec =
        (issue_pkt1_i.op_class == UOP_CLASS_ALU) ||
        (issue_pkt1_i.op_class == UOP_CLASS_BJP) ||
        ((issue_pkt1_i.op_class == UOP_CLASS_BITMANIP) &&
         slot1_early_bitmanip_supported);
	wire slot0_lane_a_early = issue_pkt_i.dst.writes_gpr &&
		!uop_memory(issue_pkt_i) &&
        !issue_pkt_i.fence_i && slot0_early_exec;
	wire slot1_lane_a_early = issue_pkt1_i.dst.writes_gpr &&
		!uop_memory(issue_pkt1_i) &&
        !issue_pkt1_i.fence_i && slot1_early_exec;
	wire slot0_lane_b_early = issue_pkt_i.dst.writes_gpr && slot0_early_exec;
	wire slot1_lane_b_early = issue_pkt1_i.dst.writes_gpr && slot1_early_exec;
    wire lane_a_early_valid = lane_a_valid &&
        (swap_pair ? slot1_lane_a_early : slot0_lane_a_early);
    wire lane_b_early_valid = lane_b_valid &&
        (lane_b_uses_slot0 ? slot0_lane_b_early : slot1_lane_b_early);
    wire producer_id_t lane_a_early_id = swap_pair ?
        issue_pkt1_i.dst.rob_tag : issue_pkt_i.dst.rob_tag;
    wire producer_id_t lane_b_early_id = lane_b_uses_slot0 ?
        issue_pkt_i.dst.rob_tag : issue_pkt1_i.dst.rob_tag;
    wire [REGS_ADDR_WIDTH-1:0] lane_a_early_rd = swap_pair ?
        issue_pkt1_i.dst.rd_addr : issue_pkt_i.dst.rd_addr;
    wire [REGS_ADDR_WIDTH-1:0] lane_b_early_rd = lane_b_uses_slot0 ?
        issue_pkt_i.dst.rd_addr : issue_pkt1_i.dst.rd_addr;

    wire lane_a_fu_valid = lane_a_accept && !lane_a_uop.fence_i;
    wire lane_b_alu_accept = lane_b_accept &&
        ((lane_b_uop.op_class == UOP_CLASS_ALU) ||
         (lane_b_uop.op_class == UOP_CLASS_BITMANIP));
    wire lane_b_bru_accept = lane_b_accept &&
        (lane_b_uop.op_class == UOP_CLASS_BJP);
    wire lane_b_agu_accept = lane_b_accept && uop_memory(lane_b_uop);
    ydrasil_lsu_req_pkt_t shared_agu_req_d;
    ydrasil_lane_b_meta_t dual_meta_d;
    ydrasil_lane_b_alu_payload_t dual_alu_payload_d;
    ydrasil_lane_b_bru_payload_t dual_bru_payload_d;
    always_comb begin
        shared_agu_req_d = '0;
        shared_agu_req_d.valid = lane_b_agu_accept;
        shared_agu_req_d.is_load = lane_b_uop.op_class == UOP_CLASS_LOAD;
        shared_agu_req_d.is_store = lane_b_uop.op_class == UOP_CLASS_STORE;
        shared_agu_req_d.op = uop_operator_lsu(lane_b_uop);
        shared_agu_req_d.rd_addr = lane_b_uop.dst.rd_addr;
        shared_agu_req_d.producer_id = lane_b_uop.dst.rob_tag;
        shared_agu_req_d.producer_tracked = lane_b_agu_accept;
        shared_agu_req_d.store_data = lane_b_src1_local;
        shared_agu_req_d.store_data_valid = lane_b_agu_accept &&
            (!shared_agu_req_d.is_store || lane_b_src1_ready);
        shared_agu_req_d.store_producer_id =
            lane_b_uop.src1.producer_tag;
        shared_agu_req_d.store_producer_tracked = lane_b_agu_accept &&
            shared_agu_req_d.is_store && !lane_b_src1_ready &&
            lane_b_uop.src1.tag_valid;
    end

    always_comb begin
        dual_meta_d = '0;
        dual_meta_d.rd_addr = lane_b_uop.dst.rd_addr;
        dual_meta_d.rd_wen = lane_b_accept && lane_b_uop.dst.writes_gpr;
        dual_meta_d.producer_id = lane_b_uop.dst.rob_tag;
        dual_meta_d.producer_tracked = lane_b_accept;
        dual_meta_d.pc = lane_b_uop.pc;
        dual_meta_d.instr = lane_b_uop.instr;

        dual_alu_payload_d = '0;
        dual_alu_payload_d.bitmanip =
            lane_b_uop.op_class == UOP_CLASS_BITMANIP;
        dual_alu_payload_d.subop = lane_b_uop.subop;
        dual_alu_payload_d.operand_a = lane_b_operand_a_local;
        dual_alu_payload_d.operand_b = lane_b_operand_b_local;

        dual_bru_payload_d = '0;
        dual_bru_payload_d.subop = lane_b_uop.subop;
        dual_bru_payload_d.operand_a = lane_b_src0_local;
        dual_bru_payload_d.operand_b = lane_b_src1_local;
        dual_bru_payload_d.imm = lane_b_uop.imm;
        dual_bru_payload_d.jalr = lane_b_uop.bt_a_rs_sel;
        dual_bru_payload_d.pred_hit = lane_b_uop.pred_hit;
        dual_bru_payload_d.pred_taken = lane_b_uop.pred_taken;
        dual_bru_payload_d.pred_target = lane_b_uop.pred_target;
        dual_bru_payload_d.pred_counter = lane_b_uop.pred_counter;
        dual_bru_payload_d.pred_bht_index = lane_b_uop.pred_bht_index;
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
			illegal_instr_q <= 1'b0;
            alu_in_valid_q <= 1'b0;
            alu_in_operand_a_q <= '0;
            alu_in_operand_b_q <= '0;
            alu_in_operator_q <= '0;
            alu_in_operator_type_q <= '0;
            alu_in_rd_wen_q <= 1'b0;
            alu_in_rd_addr_q <= '0;
            alu_in_producer_id_q <= '0;
            lane_a_pc_q <= '0;
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
            dual_meta_q <= '0;
            dual_alu_valid_q <= 1'b0;
            dual_alu_payload_q <= '0;
            dual_bru_valid_q <= 1'b0;
            dual_bru_payload_q <= '0;
            alu_in_operand_a_dtcm_q <= 1'b0;
            alu_in_operand_b_dtcm_q <= 1'b0;
            agu_in_operand_a_dtcm_q <= 1'b0;
            agu_in_store_data_dtcm_q <= 1'b0;
            csr_in_operand_a_dtcm_q <= 1'b0;
            mul_in_operand_a_dtcm_q <= 1'b0;
            mul_in_operand_b_dtcm_q <= 1'b0;
            dual_in_operand_a_dtcm_q <= 1'b0;
            dual_in_operand_b_dtcm_q <= 1'b0;
            dual_in_branch_operand_a_dtcm_q <= 1'b0;
            dual_in_branch_operand_b_dtcm_q <= 1'b0;
            {alu_in_operand_a_early_main_q, alu_in_operand_a_early_dual_q,
             alu_in_operand_b_early_main_q, alu_in_operand_b_early_dual_q,
             agu_in_operand_a_early_main_q, agu_in_operand_a_early_dual_q,
             agu_in_store_data_early_main_q,
             agu_in_store_data_early_dual_q,
             csr_in_operand_a_early_main_q, csr_in_operand_a_early_dual_q,
             mul_in_operand_a_early_main_q, mul_in_operand_a_early_dual_q,
			 mul_in_operand_b_early_main_q, mul_in_operand_b_early_dual_q,
             dual_in_operand_a_early_main_q,
             dual_in_operand_a_early_dual_q,
             dual_in_operand_b_early_main_q,
             dual_in_operand_b_early_dual_q,
             dual_in_branch_operand_a_early_main_q,
             dual_in_branch_operand_a_early_dual_q,
             dual_in_branch_operand_b_early_main_q,
             dual_in_branch_operand_b_early_dual_q} <= '0;
            dtcm_stall_data_valid_q <= 1'b0;
        end else begin
            lsu_idle_q <= lsu_idle_i;
            issue_at_rob_head_q <= issue_at_rob_head_i;

            if (stall_id_i) begin
                if (!dtcm_stall_data_valid_q && dtcm_bypass_active_q) begin
                    dtcm_stall_data_q <= dtcm_resp_data_i;
                    dtcm_stall_data_valid_q <= 1'b1;
                end
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
                    dtcm_stall_data_valid_q <= 1'b0;
					illegal_instr_q <= 1'b0;
                    early_wakeup_valid_q[0] <= 1'b0;
                    early_wakeup_valid_q[1] <= 1'b0;
                    early_wakeup_id_q[0] <= '0;
                    early_wakeup_id_q[1] <= '0;
                    early_wakeup_rd_q[0] <= '0;
                    early_wakeup_rd_q[1] <= '0;
                    alu_in_valid_q <= 1'b0;
                    agu_in_valid_q <= 1'b0;
                    agu_in_req_q <= '0;
                    csr_in_valid_q <= 1'b0;
                    mul_in_valid_q <= 1'b0;
                    dual_alu_valid_q <= 1'b0;
                    dual_bru_valid_q <= 1'b0;
                    alu_in_operand_a_dtcm_q <= 1'b0;
                    alu_in_operand_b_dtcm_q <= 1'b0;
                    agu_in_operand_a_dtcm_q <= 1'b0;
                    agu_in_store_data_dtcm_q <= 1'b0;
                    csr_in_operand_a_dtcm_q <= 1'b0;
                    mul_in_operand_a_dtcm_q <= 1'b0;
                    mul_in_operand_b_dtcm_q <= 1'b0;
                    dual_in_operand_a_dtcm_q <= 1'b0;
                    dual_in_operand_b_dtcm_q <= 1'b0;
                    dual_in_branch_operand_a_dtcm_q <= 1'b0;
                    dual_in_branch_operand_b_dtcm_q <= 1'b0;
                    {alu_in_operand_a_early_main_q, alu_in_operand_a_early_dual_q,
                     alu_in_operand_b_early_main_q, alu_in_operand_b_early_dual_q,
                     agu_in_operand_a_early_main_q,
                     agu_in_operand_a_early_dual_q,
                     agu_in_store_data_early_main_q,
                     agu_in_store_data_early_dual_q,
                     csr_in_operand_a_early_main_q,
                     csr_in_operand_a_early_dual_q,
                     mul_in_operand_a_early_main_q,
                     mul_in_operand_a_early_dual_q,
					 mul_in_operand_b_early_main_q,
					 mul_in_operand_b_early_dual_q,
                     dual_in_operand_a_early_main_q,
                     dual_in_operand_a_early_dual_q,
                     dual_in_operand_b_early_main_q,
                     dual_in_operand_b_early_dual_q,
                     dual_in_branch_operand_a_early_main_q,
                     dual_in_branch_operand_a_early_dual_q,
                     dual_in_branch_operand_b_early_main_q,
                     dual_in_branch_operand_b_early_dual_q} <= '0;
                end else begin
                    dtcm_stall_data_valid_q <= 1'b0;
                    if (early_wakeup_valid_q[0])
                        early_main_data_q <= early_main_bypass_data_i;
                    if (early_wakeup_valid_q[1])
                        early_dual_data_q <= early_dual_bypass_data_i;
					illegal_instr_q <= lane_a_accept && lane_a_uop.illegal_instr;
                    alu_in_operand_a_dtcm_q <= lane_a_accept &&
                        lane_a_alu_exec && lane_a_op_a_src &&
                        lane_a_src0_dtcm_hit;
                    alu_in_operand_b_dtcm_q <= lane_a_accept &&
                        lane_a_alu_exec && lane_a_op_b_src &&
                        lane_a_src1_dtcm_hit;
                    agu_in_operand_a_dtcm_q <= lane_b_agu_accept &&
                        lane_b_op_a_src && lane_b_src0_dtcm_hit;
                    agu_in_store_data_dtcm_q <= lane_b_agu_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_STORE) &&
                        lane_b_src1_dtcm_hit;
                    csr_in_operand_a_dtcm_q <= lane_a_accept &&
                        ((lane_a_uop.op_class == UOP_CLASS_CSR) ||
                         (lane_a_uop.op_class == UOP_CLASS_SYS)) &&
                        lane_a_op_a_src && lane_a_src0_dtcm_hit;
                    mul_in_operand_a_dtcm_q <= lane_a_accept &&
                        (lane_a_uop.op_class == UOP_CLASS_MUL) &&
                        lane_a_op_a_src && lane_a_src0_dtcm_hit;
                    mul_in_operand_b_dtcm_q <= lane_a_accept &&
                        (lane_a_uop.op_class == UOP_CLASS_MUL) &&
                        lane_a_op_b_src && lane_a_src1_dtcm_hit;
                    dual_in_operand_a_dtcm_q <= lane_b_alu_accept &&
                        lane_b_op_a_src && lane_b_src0_dtcm_hit;
                    dual_in_operand_b_dtcm_q <= lane_b_alu_accept &&
                        lane_b_op_b_src && lane_b_src1_dtcm_hit;
                    dual_in_branch_operand_a_dtcm_q <= lane_b_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_BJP) &&
                        lane_b_src0_dtcm_hit;
                    dual_in_branch_operand_b_dtcm_q <= lane_b_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_BJP) &&
                        lane_b_src1_dtcm_hit;
                    {alu_in_operand_a_early_main_q,
                     alu_in_operand_a_early_dual_q} <= {
                        lane_a_accept && lane_a_alu_exec && lane_a_op_a_src &&
                        lane_a_src0_early_main_hit,
                        lane_a_accept && lane_a_alu_exec && lane_a_op_a_src &&
                        lane_a_src0_early_dual_hit};
                    {alu_in_operand_b_early_main_q,
                     alu_in_operand_b_early_dual_q} <= {
                        lane_a_accept && lane_a_alu_exec && lane_a_op_b_src &&
                        lane_a_src1_early_main_hit,
                        lane_a_accept && lane_a_alu_exec && lane_a_op_b_src &&
                        lane_a_src1_early_dual_hit};
                    {agu_in_operand_a_early_main_q,
                     agu_in_operand_a_early_dual_q} <= {
                        lane_b_agu_accept && lane_b_op_a_src &&
                        lane_b_src0_early_main_hit,
                        lane_b_agu_accept && lane_b_op_a_src &&
                        lane_b_src0_early_dual_hit};
                    {agu_in_store_data_early_main_q,
                     agu_in_store_data_early_dual_q} <= {
                        lane_b_agu_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_STORE) &&
                        lane_b_src1_early_main_hit,
                        lane_b_agu_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_STORE) &&
                        lane_b_src1_early_dual_hit};
                    {csr_in_operand_a_early_main_q,
                     csr_in_operand_a_early_dual_q} <= {
                        lane_a_accept &&
                        ((lane_a_uop.op_class == UOP_CLASS_CSR) ||
                         (lane_a_uop.op_class == UOP_CLASS_SYS)) &&
                        lane_a_op_a_src && lane_a_src0_early_main_hit,
                        lane_a_accept &&
                        ((lane_a_uop.op_class == UOP_CLASS_CSR) ||
                         (lane_a_uop.op_class == UOP_CLASS_SYS)) &&
                        lane_a_op_a_src && lane_a_src0_early_dual_hit};
                    {mul_in_operand_a_early_main_q,
                     mul_in_operand_a_early_dual_q} <= {
                        lane_a_accept &&
                        (lane_a_uop.op_class == UOP_CLASS_MUL) &&
                        lane_a_op_a_src && lane_a_src0_early_main_hit,
                        lane_a_accept &&
                        (lane_a_uop.op_class == UOP_CLASS_MUL) &&
                        lane_a_op_a_src && lane_a_src0_early_dual_hit};
                    {mul_in_operand_b_early_main_q,
                     mul_in_operand_b_early_dual_q} <= {
                        lane_a_accept &&
                        (lane_a_uop.op_class == UOP_CLASS_MUL) &&
                        lane_a_op_b_src && lane_a_src1_early_main_hit,
                        lane_a_accept &&
                        (lane_a_uop.op_class == UOP_CLASS_MUL) &&
                        lane_a_op_b_src && lane_a_src1_early_dual_hit};
                    {dual_in_operand_a_early_main_q,
                     dual_in_operand_a_early_dual_q} <= {
                        lane_b_alu_accept && lane_b_op_a_src &&
                        lane_b_src0_early_main_hit,
                        lane_b_alu_accept && lane_b_op_a_src &&
                        lane_b_src0_early_dual_hit};
                    {dual_in_operand_b_early_main_q,
                     dual_in_operand_b_early_dual_q} <= {
                        lane_b_alu_accept && lane_b_op_b_src &&
                        lane_b_src1_early_main_hit,
                        lane_b_alu_accept && lane_b_op_b_src &&
                        lane_b_src1_early_dual_hit};
                    {dual_in_branch_operand_a_early_main_q,
                     dual_in_branch_operand_a_early_dual_q} <= {
                        lane_b_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_BJP) &&
                        lane_b_src0_early_main_hit,
                        lane_b_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_BJP) &&
                        lane_b_src0_early_dual_hit};
                    {dual_in_branch_operand_b_early_main_q,
                     dual_in_branch_operand_b_early_dual_q} <= {
                        lane_b_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_BJP) &&
                        lane_b_src1_early_main_hit,
                        lane_b_accept &&
                        (lane_b_uop.op_class == UOP_CLASS_BJP) &&
                        lane_b_src1_early_dual_hit};
                    // Wakeup qualification is a control token, not execution
                    // payload.  Derive it directly from the selected lane so
                    // LSU request/credit fields cannot re-enter this D cone.
                    if (id_advance) begin
                        early_wakeup_valid_q[0] <= lane_a_early_valid;
                        early_wakeup_valid_q[1] <= lane_b_early_valid;
                        early_wakeup_id_q[0] <= lane_a_early_id;
                        early_wakeup_id_q[1] <= lane_b_early_id;
                        early_wakeup_rd_q[0] <= lane_a_early_rd;
                        early_wakeup_rd_q[1] <= lane_b_early_rd;
                    end else begin
                        early_wakeup_valid_q[0] <= 1'b0;
                        early_wakeup_valid_q[1] <= 1'b0;
                        early_wakeup_id_q[0] <= '0;
                        early_wakeup_id_q[1] <= '0;
                        early_wakeup_rd_q[0] <= '0;
                        early_wakeup_rd_q[1] <= '0;
                    end
                    // Each execution class has its own input cell.  The
					// values are captured at the same architectural boundary.
					// Their local completion result supplies
                    // the matching registered early token in the next cycle.
                    alu_in_valid_q <= lane_a_fu_valid;
                    alu_in_operand_a_q <= lane_a_operand_a_local;
                    alu_in_operand_b_q <= lane_a_operand_b_local;
                    alu_in_operator_q <= lane_a_operator_info;
                    alu_in_operator_type_q <= lane_a_operator_type;
                    alu_in_rd_wen_q <= lane_a_fu_valid &&
                        lane_a_uop.dst.writes_gpr;
                    alu_in_rd_addr_q <= lane_a_uop.dst.rd_addr;
                    alu_in_producer_id_q <= lane_a_uop.dst.rob_tag;
                    lane_a_pc_q <= lane_a_uop.pc;
                    agu_in_valid_q <= lane_b_agu_accept;
                    if (lane_b_agu_accept) begin
                        agu_in_operand_a_q <= lane_b_operand_a_local;
                        agu_in_operand_b_q <= lane_b_operand_b_local;
                        agu_in_req_q <= shared_agu_req_d;
                    end else begin
                        agu_in_req_q.valid <= 1'b0;
                    end
                    csr_in_valid_q <= lane_a_fu_valid;
                    csr_in_operand_a_q <= lane_a_operand_a_local;
                    csr_in_operator_type_q <= lane_a_operator_type;
                    csr_in_raddr_q <= lane_a_uop.csr_raddr;
                    csr_in_waddr_q <= lane_a_uop.csr_waddr;
                    csr_in_op_info_q <= lane_a_uop.csr_op_info;
                    csr_in_sys_info_q <= lane_a_uop.sys_op_info;
                    mul_in_valid_q <= lane_a_fu_valid;
                    mul_in_operand_a_q <= lane_a_operand_a_local;
                    mul_in_operand_b_q <= lane_a_operand_b_local;
                    mul_in_operator_q <= lane_a_operator_info;
                    mul_in_operator_type_q <= lane_a_operator_type;
                    dual_alu_valid_q <= lane_b_alu_accept;
                    dual_bru_valid_q <= lane_b_bru_accept;
                    if (lane_b_accept)
                        dual_meta_q <= dual_meta_d;
                    if (lane_b_alu_accept)
                        dual_alu_payload_q <= dual_alu_payload_d;
                    if (lane_b_bru_accept)
                        dual_bru_payload_q <= dual_bru_payload_d;
                end
            end
        end
    end

    // DTCM data starts at the LSU response FF, not at the BRAM. Early ALU
    // data comes from the token-aligned safe result banks above. Every mux
    // sits after its matching Issue/FU input cell, preserving zero-bubble
	// wakeup without placing wide completion data in the Issue operand cone.
	ydrasil_lsu_req_pkt_t agu_in_req_mux;
	ydrasil_lane_b_alu_payload_t dual_alu_payload_mux;
	ydrasil_lane_b_bru_payload_t dual_bru_payload_mux;
	wire [DATA_WIDTH-1:0] bypass_base [0:10];
	wire [DATA_WIDTH-1:0] bypass_result [0:10];
	wire [10:0] bypass_dtcm_select;
	wire [10:0] bypass_main_select;
	wire [10:0] bypass_dual_select;
	assign bypass_base[0] = agu_in_req_q.store_data;
	assign bypass_base[1] = dual_bru_payload_q.operand_a;
	assign bypass_base[2] = dual_bru_payload_q.operand_b;
	assign bypass_base[3] = dual_alu_payload_q.operand_a;
	assign bypass_base[4] = dual_alu_payload_q.operand_b;
	assign bypass_base[5] = alu_in_operand_a_q;
	assign bypass_base[6] = alu_in_operand_b_q;
	assign bypass_base[7] = agu_in_operand_a_q;
	assign bypass_base[8] = csr_in_operand_a_q;
	assign bypass_base[9] = mul_in_operand_a_q;
	assign bypass_base[10] = mul_in_operand_b_q;
	assign bypass_dtcm_select = {
		mul_in_operand_b_dtcm_q, mul_in_operand_a_dtcm_q,
		csr_in_operand_a_dtcm_q, agu_in_operand_a_dtcm_q,
		alu_in_operand_b_dtcm_q,
		alu_in_operand_a_dtcm_q, dual_in_operand_b_dtcm_q,
		dual_in_operand_a_dtcm_q, dual_in_branch_operand_b_dtcm_q,
		dual_in_branch_operand_a_dtcm_q, agu_in_store_data_dtcm_q};
	assign bypass_main_select = {
        mul_in_operand_b_early_main_q, mul_in_operand_a_early_main_q,
        csr_in_operand_a_early_main_q, agu_in_operand_a_early_main_q,
		alu_in_operand_b_early_main_q,
		alu_in_operand_a_early_main_q, dual_in_operand_b_early_main_q,
		dual_in_operand_a_early_main_q,
		dual_in_branch_operand_b_early_main_q,
		dual_in_branch_operand_a_early_main_q,
		agu_in_store_data_early_main_q};
	assign bypass_dual_select = {
        mul_in_operand_b_early_dual_q, mul_in_operand_a_early_dual_q,
        csr_in_operand_a_early_dual_q, agu_in_operand_a_early_dual_q,
		alu_in_operand_b_early_dual_q,
		alu_in_operand_a_early_dual_q, dual_in_operand_b_early_dual_q,
		dual_in_operand_a_early_dual_q,
		dual_in_branch_operand_b_early_dual_q,
		dual_in_branch_operand_a_early_dual_q,
		agu_in_store_data_early_dual_q};
	genvar bypass_index;
	generate
		for (bypass_index = 0; bypass_index < 11; bypass_index++) begin : g_bypass
            assign bypass_result[bypass_index] =
                bypass_dtcm_select[bypass_index] ? dtcm_bypass_data :
                bypass_main_select[bypass_index] ? early_main_bypass_data :
                bypass_dual_select[bypass_index] ? early_dual_bypass_data :
                bypass_base[bypass_index];
        end
    endgenerate

	always_comb begin
		agu_in_req_mux = agu_in_req_q;
		agu_in_req_mux.store_data = bypass_result[0];
		dual_alu_payload_mux = dual_alu_payload_q;
		dual_alu_payload_mux.operand_a = bypass_result[3];
		dual_alu_payload_mux.operand_b = bypass_result[4];
		dual_bru_payload_mux = dual_bru_payload_q;
		dual_bru_payload_mux.operand_a = bypass_result[1];
		dual_bru_payload_mux.operand_b = bypass_result[2];
	end

	assign illegal_instr_o = illegal_instr_q;
	assign alu_in_valid_o = alu_in_valid_q;
	assign alu_in_operand_a_o = bypass_result[5];
	assign alu_in_operand_b_o = bypass_result[6];
    assign alu_in_operator_o = alu_in_operator_q;
    assign alu_in_operator_type_o = alu_in_operator_type_q;
    assign alu_in_rd_wen_o = alu_in_rd_wen_q;
    assign alu_in_rd_addr_o = alu_in_rd_addr_q;
    assign alu_in_producer_id_o = alu_in_producer_id_q;
	assign lane_a_pc_o = lane_a_pc_q;
    assign agu_in_valid_o = agu_in_valid_q;
	assign agu_in_operand_a_o = bypass_result[7];
    assign agu_in_operand_b_o = agu_in_operand_b_q;
    assign agu_in_req_o = agu_in_req_mux;
    assign csr_in_valid_o = csr_in_valid_q;
	assign csr_in_operand_a_o = bypass_result[8];
    assign csr_in_operator_type_o = csr_in_operator_type_q;
    assign csr_in_raddr_o = csr_in_raddr_q;
    assign csr_in_waddr_o = csr_in_waddr_q;
    assign csr_in_op_info_o = csr_in_op_info_q;
    assign csr_in_sys_info_o = csr_in_sys_info_q;
    assign mul_in_valid_o = mul_in_valid_q;
	assign mul_in_operand_a_o = bypass_result[9];
	assign mul_in_operand_b_o = bypass_result[10];
    assign mul_in_operator_o = mul_in_operator_q;
    assign mul_in_operator_type_o = mul_in_operator_type_q;
	assign dual_meta_o = dual_meta_q;
	assign dual_alu_valid_o = dual_alu_valid_q;
	assign dual_alu_payload_o = dual_alu_payload_mux;
	assign dual_bru_valid_o = dual_bru_valid_q;
	assign dual_bru_payload_o = dual_bru_payload_mux;

`ifndef SYNTHESIS
    wire issue_valid_ff = issue_pkt_i.valid;
    wire [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff =
        uop_operator_type(issue_pkt_i);
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
    output ydrasil_gpr_fwd_pkt_t          completion_o,
    output wire [REGS_DATA_WIDTH-1:0]     early_bypass_data_o,
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
    wire [REGS_DATA_WIDTH-1:0] early_b_pack_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_PACK]}} &
         {exec_operand_b[15:0], exec_operand_a[15:0]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_PACKH]}} &
         {16'b0, exec_operand_b[7:0], exec_operand_a[7:0]});
    wire [REGS_DATA_WIDTH-1:0] fast_bitmanip_result =
        fast_b_shadd_result | fast_b_logic_result | fast_b_minmax_result |
        fast_b_extend_result;

    wire alu_unused_comp;
    wire alu_unused_wen;
    wire [REGS_ADDR_WIDTH-1:0] alu_unused_waddr;
    ydrasil_alu u_dual_alu (
        .operand_a_i(exec_operand_a), .operand_b_i(exec_operand_b),
        .operator_i(operator_i), .operator_type_i(operator_type_i),
        .id_rf_waddr_rd_i(rd_addr_i), .id_alu_rf_wen_rd_i(rd_wen_i),
        .interrupt_i(interrupt_i), .comp_result_o(alu_unused_comp),
        .alu_result_o(alu_result), .alu_rf_wen_rd_o(alu_unused_wen),
        .alu_rf_waddr_rd_o(alu_unused_waddr)
    );

    // Keep the early-return data cone separate from min/max and other
    // expensive bitmanip operations. The matching token is captured in
    // Issue, and this value is selected only at the consumer FU input.
    wire early_lite_bitmanip_op =
        operator_type_i[OPERATOR_TYPE_BITMANIP] &&
        (operator_i[OP_B_SH1ADD] | operator_i[OP_B_SH2ADD] |
         operator_i[OP_B_SH3ADD] | operator_i[OP_B_PACK] |
         operator_i[OP_B_PACKH]  | operator_i[OP_B_REV8] |
         operator_i[OP_B_SEXT_B] | operator_i[OP_B_SEXT_H] |
         operator_i[OP_B_ZEXT_H]);
    wire [REGS_DATA_WIDTH-1:0] early_lite_bitmanip_result =
        fast_b_shadd_result | early_b_pack_result | fast_b_extend_result;
    assign early_bypass_data_o = early_lite_bitmanip_op ?
        early_lite_bitmanip_result :
        (operator_type_i[OPERATOR_TYPE_ALU] &&
         !operator_type_i[OPERATOR_TYPE_BITMANIP]) ? alu_result :
        operator_type_i[OPERATOR_TYPE_BJP] ?
        (exec_operand_a + exec_operand_b) : '0;

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
        end else begin
            valid_q <= valid_i && !interrupt_i;
            pc_q <= pc_i;
            instr_q <= instr_i;
        end
    end

    // Lane B completion is captured by the typed ALU result array at WB. The
    // remaining q state is commit trace metadata, not an execution bypass.
    assign completion_o.valid = valid_i && rd_wen_i && !interrupt_i &&
        (rd_addr_i != '0);
    assign completion_o.producer_id = producer_id_i;
    assign completion_o.producer_tracked = producer_tracked_i;
    assign completion_o.addr = rd_addr_i;
    assign completion_o.data = operator_type_i[OPERATOR_TYPE_BITMANIP] ?
        fast_bitmanip_result : alu_result;
    assign instret_valid_o = valid_q;
    assign commit_pc_o = pc_q;
    assign commit_instr_o = instr_q;
endmodule
