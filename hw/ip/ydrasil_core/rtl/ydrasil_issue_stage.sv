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
    input  wire                        branch_recovery_i,
    input  wire                        trap_flush_i,
    input  wire [PRODUCER_NUM-1:0]     recovery_keep_mask_i,
    input  ydrasil_issue_pkt_t         decode_pkt_i,
    input  ydrasil_issue_pkt_t         decode_pkt1_i,
    input  ydrasil_issue_pkt_t         dispatch_pkt_i,
    input  ydrasil_issue_pkt_t         dispatch_pkt1_i,
    input  wire                        dispatch_ready_i,
    input  ydrasil_completion_meta_t   completion_meta_i [COMPLETION_LANES],
    input  wire [REGS_DATA_WIDTH-1:0]  completion_data_i [COMPLETION_LANES],
    input  ydrasil_commit_pkt_t        commit_pkt_i,
    input  ydrasil_commit_pkt_t        commit_pkt1_i,
    input  producer_slot_t             retire_slot0_i,
    input  producer_slot_t             retire_slot1_i,
    input  wire [DATA_WIDTH-1:0]       early_main_bypass_data_i,
    input  wire [DATA_WIDTH-1:0]       early_dual_bypass_data_i,
    input  wire                        lsu_idle_i,
    input  wire [1:0]                  lsu_credit_i,
    input  ydrasil_reservation_pkt_t   dtcm_reservation_i,
    input  ydrasil_reservation_pkt_t   mdu_due_i,
    input  wire                        mdu_div_available_i,
    input  ydrasil_reservation_pkt_t   mdu_result_reservation_i,
    input  wire [DATA_WIDTH-1:0]       mdu_bypass_data_i,
    input  wire [DATA_WIDTH-1:0]       dtcm_resp_data_i,
    input  wire                        issue_at_rob_head_i,
    input  producer_id_t               rob_head_id_i,
    input  ydrasil_rob_source_state_t  issue_src1_state_i,
    output wire                        decode_ready_o,
    output wire                        decode_consume_two_o,
    output wire                        dispatch_accept_o,
    output wire                        dispatch_accept1_o,
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
    output wire                        dual_bru_valid_o,
    output ydrasil_lane_b_bru_payload_t dual_bru_payload_o,
    output wire [DATA_WIDTH-1:0]       dual_bru_operand_a_o,
    output wire [DATA_WIDTH-1:0]       dual_bru_operand_b_o
);
    localparam int ISSUE_WINDOW_DEPTH = 10;
    wire ydrasil_compact_uop_t issue_window_q [0:ISSUE_WINDOW_DEPTH-1];
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_window_valid_q;
    wire issue_window_src0_ready_q [0:ISSUE_WINDOW_DEPTH-1];
    wire issue_window_src1_ready_q [0:ISSUE_WINDOW_DEPTH-1];
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_order_mask_q
        [0:ISSUE_WINDOW_DEPTH-1];
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_memory_q;
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_mul_q;
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_serial_q;
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_store_q;
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_divrem_q;
    ydrasil_compact_uop_t dispatch_compact_uop;
    ydrasil_compact_uop_t dispatch_compact_uop1;
    ydrasil_compact_uop_t issue_pkt_i;
    ydrasil_compact_uop_t issue_pkt1_i;
    ydrasil_compact_uop_t select_bundle0_uop0_q;
    ydrasil_compact_uop_t select_bundle0_uop1_q;
    ydrasil_compact_uop_t select_bundle1_uop0_q;
    ydrasil_compact_uop_t select_bundle1_uop1_q;
    ydrasil_compact_uop_t serial_bundle_uop_q;
    reg select_bundle0_pair_q;
    reg select_bundle1_pair_q;
    reg select_buf_head_q;
    reg select_buf_tail_q;
    reg [1:0] select_buf_count_q;
    reg serial_bundle_valid_q;
    wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs1;
    wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs2;
    wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs3;
    wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs4;
    wire [DATA_WIDTH-1:0] rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] rf_rdata_rs2_i;
    wire [DATA_WIDTH-1:0] rf_rdata_rs3_i;
    wire [DATA_WIDTH-1:0] rf_rdata_rs4_i;
    wire [DATA_WIDTH-1:0] issue_src0_value_i;
    wire [DATA_WIDTH-1:0] issue_src1_value_i;
    wire [DATA_WIDTH-1:0] issue_src2_value_i;
    wire [DATA_WIDTH-1:0] issue_src3_value_i;
    wire issue_src0_epoch_i;
    wire issue_src1_epoch_i;
    wire issue_src2_epoch_i;
    wire issue_src3_epoch_i;

    wire issue_pair_execute = !serial_bundle_valid_q &&
        (select_buf_count_q != 2'd0) &&
        (select_buf_head_q ? select_bundle1_pair_q : select_bundle0_pair_q);
    wire serial_bundle_pop = issue_ready_o && serial_bundle_valid_q;
    wire select_buf_pop = issue_ready_o && !serial_bundle_valid_q &&
        (select_buf_count_q != 2'd0);

    // Capacity feedback depends only on registered occupancy. Selection does
    // not feed Fetch/Decode ready in the same cycle.
    wire dispatch_slots_available;
    wire issue_pipe_has_room = dispatch_ready_i && dispatch_slots_available;
    wire issue_pipe_push = !flush_id_i && issue_pipe_has_room &&
        decode_pkt_i.valid;
    wire issue_pipe_push_two = issue_pipe_push && decode_pkt1_i.valid;

    assign decode_ready_o = issue_pipe_has_room;
    assign decode_consume_two_o = issue_pipe_push_two;
    assign dispatch_accept_o = issue_pipe_push;
    assign dispatch_accept1_o = issue_pipe_push_two;
    assign issue_pkt_o = issue_pkt_i;
    assign issue_pkt1_o = issue_pkt1_i;

    always_comb begin
        if (serial_bundle_valid_q) begin
            issue_pkt_i = serial_bundle_uop_q;
            issue_pkt1_i = '0;
        end else if (select_buf_head_q) begin
            issue_pkt_i = select_bundle1_uop0_q;
            issue_pkt1_i = select_bundle1_uop1_q;
        end else begin
            issue_pkt_i = select_bundle0_uop0_q;
            issue_pkt1_i = select_bundle0_uop1_q;
        end
        issue_pkt_i.valid = serial_bundle_valid_q ||
            (select_buf_count_q != 2'd0);
        issue_pkt1_i.valid = issue_pkt_i.valid && issue_pair_execute;
    end

    ydrasil_issue_compactor u_issue_compactor0 (
        .issue_pkt_i   (dispatch_pkt_i),
        .compact_uop_o (dispatch_compact_uop)
    );

    ydrasil_issue_compactor u_issue_compactor1 (
        .issue_pkt_i   (dispatch_pkt1_i),
        .compact_uop_o (dispatch_compact_uop1)
    );

    wire selected0_early = (issue_pkt_i.op_class == UOP_CLASS_ALU) ||
        (issue_pkt_i.op_class == UOP_CLASS_BJP) ||
        ((issue_pkt_i.op_class == UOP_CLASS_BITMANIP) &&
         ((issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH1ADD)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH2ADD)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH3ADD)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_PACK)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_PACKH)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_REV8)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_B)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_H)) ||
          (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_ZEXT_H))));
    wire selected1_early = (issue_pkt1_i.op_class == UOP_CLASS_ALU) ||
        (issue_pkt1_i.op_class == UOP_CLASS_BJP);
    wire selected0_due_valid = issue_ready_o && issue_pkt_i.valid &&
        selected0_early && issue_pkt_i.dst.writes_gpr;
    wire selected1_due_valid = issue_ready_o && issue_pkt1_i.valid &&
        issue_pair_execute && selected1_early && issue_pkt1_i.dst.writes_gpr;
    producer_id_t rob_head_select_q;
    reg lsu_idle_select_q;
    reg [ISSUE_WINDOW_DEPTH-1:0] issued_slot_mask_q;
    reg mdu_div_available_q;
    reg div_select_reserved_q;
    reg div_busy_seen_q;
    reg [1:0] lsu_select_reserved_q;
    wire p0_select_valid, p1_select_valid;
    wire alu_select0_valid, alu_select1_valid;
    logic [ISSUE_WINDOW_DEPTH-1:0] issue_select_mask;
    ydrasil_compact_uop_t selected_uop0, selected_uop1;
    logic selected_valid0, selected_valid1;
    wire free_valid0, free_valid1;
    wire [3:0] alu_candidate_local;
    wire [3:0] alu_select0_local;
    wire [3:0] alu_after_first_local;
    wire [3:0] alu_select1_local;
    wire [2:0] p0_candidate_local;
    wire [2:0] p0_select_local;
    wire [2:0] p1_candidate_local;
    wire [2:0] p1_select_local;
    wire [2:0] p1_serial_candidate_local;
    wire [2:0] p1_serial_select_local;
    ydrasil_compact_uop_t alu_selected_uop0, alu_selected_uop1;
    ydrasil_compact_uop_t p0_selected_uop, p1_selected_uop;
    ydrasil_compact_uop_t p1_serial_selected_uop;
    logic p0_selected_src1_due;
    // RS payload and all class-local control must cross the same Dispatch
    // boundary. Using the live Decode packet here associates the following
    // instruction's serial/order metadata with the registered uop.
    wire dispatch0_memory =
        (dispatch_pkt_i.uop_class == UOP_CLASS_LOAD) ||
        (dispatch_pkt_i.uop_class == UOP_CLASS_STORE);
    wire dispatch1_memory =
        (dispatch_pkt1_i.uop_class == UOP_CLASS_LOAD) ||
        (dispatch_pkt1_i.uop_class == UOP_CLASS_STORE);
    wire dispatch0_store = dispatch_pkt_i.uop_class == UOP_CLASS_STORE;
    wire dispatch1_store = dispatch_pkt1_i.uop_class == UOP_CLASS_STORE;
    wire dispatch0_branch = dispatch_pkt_i.uop_class == UOP_CLASS_BJP;
    wire dispatch1_branch = dispatch_pkt1_i.uop_class == UOP_CLASS_BJP;
    wire dispatch0_mul = dispatch_pkt_i.uop_class == UOP_CLASS_MUL;
    wire dispatch1_mul = dispatch_pkt1_i.uop_class == UOP_CLASS_MUL;
    wire dispatch0_serial =
        (dispatch_pkt_i.uop_class == UOP_CLASS_CSR) ||
        (dispatch_pkt_i.uop_class == UOP_CLASS_SYS) ||
        dispatch_pkt_i.decode.fence_i ||
        dispatch_pkt_i.decode.illegal_instr;
    wire dispatch1_serial =
        (dispatch_pkt1_i.uop_class == UOP_CLASS_CSR) ||
        (dispatch_pkt1_i.uop_class == UOP_CLASS_SYS) ||
        dispatch_pkt1_i.decode.fence_i ||
        dispatch_pkt1_i.decode.illegal_instr;
    wire dispatch0_divrem = dispatch0_mul &&
        (dispatch_pkt_i.uop_subop >= UOP_SUBOP_WIDTH'(OP_MUL_DIV));
    wire dispatch1_divrem = dispatch1_mul &&
        (dispatch_pkt1_i.uop_subop >= UOP_SUBOP_WIDTH'(OP_MUL_DIV));
    // Fence and illegal encodings retain an ALU base class from Decode, but
    // their serial attribute owns the P1 path and must win RS-domain routing.
    wire dispatch0_alu =
        (dispatch_pkt_i.uop_class == UOP_CLASS_ALU) && !dispatch0_serial;
    wire dispatch1_alu =
        (dispatch_pkt1_i.uop_class == UOP_CLASS_ALU) && !dispatch1_serial;
    wire dispatch0_p0 = !dispatch0_alu &&
        (dispatch_pkt_i.lane_mask == 2'b01);
    wire dispatch1_p0 = !dispatch1_alu &&
        (dispatch_pkt1_i.lane_mask == 2'b01);
    wire [3:0] alu_free_local = ~issue_window_valid_q[3:0];
    wire [2:0] p0_free_local = ~issue_window_valid_q[6:4];
    wire [2:0] p1_free_local = ~issue_window_valid_q[9:7];
    wire [3:0] alu_alloc0_local;
    wire [2:0] p0_alloc0_local;
    wire [2:0] p1_alloc0_local;
    wire [3:0] alu_free1_local = alu_free_local &
        ~(dispatch0_alu ? alu_alloc0_local : '0);
    wire [2:0] p0_free1_local = p0_free_local &
        ~(dispatch0_p0 ? p0_alloc0_local : '0);
    wire [2:0] p1_free1_local = p1_free_local &
        ~((!dispatch0_alu && !dispatch0_p0) ? p1_alloc0_local : '0);
    wire [3:0] alu_alloc1_local;
    wire [2:0] p0_alloc1_local;
    wire [2:0] p1_alloc1_local;
    wire [ISSUE_WINDOW_DEPTH-1:0] free_select0_vec = dispatch0_alu ?
        {6'b0, alu_alloc0_local} : dispatch0_p0 ?
        {3'b0, p0_alloc0_local, 4'b0} : {p1_alloc0_local, 7'b0};
    wire [ISSUE_WINDOW_DEPTH-1:0] free_select1_vec = dispatch1_alu ?
        {6'b0, alu_alloc1_local} : dispatch1_p0 ?
        {3'b0, p0_alloc1_local, 4'b0} : {p1_alloc1_local, 7'b0};
    wire [ISSUE_WINDOW_DEPTH-1:0] dispatch0_order_mask =
        dispatch0_branch ? issue_window_valid_q :
        dispatch0_memory ? (issue_window_valid_q & issue_memory_q) :
        dispatch0_divrem ? (issue_window_valid_q & issue_mul_q) : '0;
    wire [ISSUE_WINDOW_DEPTH-1:0] dispatch1_prior_mask = free_select0_vec;
    wire [ISSUE_WINDOW_DEPTH-1:0] dispatch1_order_mask =
        dispatch1_branch ? (issue_window_valid_q | dispatch1_prior_mask) :
        dispatch1_memory ? ((issue_window_valid_q & issue_memory_q) |
                            (dispatch0_memory ? dispatch1_prior_mask : '0)) :
        dispatch1_divrem ? ((issue_window_valid_q & issue_mul_q) |
                            (dispatch0_mul ? dispatch1_prior_mask : '0)) : '0;

    // The three RS domains have physically separate candidate networks. The
    // ALU bank can provide both lanes; P0 and P1 each provide at most one.
    assign alu_candidate_local[0] = issue_window_valid_q[0] &&
        issue_window_src0_ready_q[0] && issue_window_src1_ready_q[0];
    assign alu_candidate_local[1] = issue_window_valid_q[1] &&
        issue_window_src0_ready_q[1] && issue_window_src1_ready_q[1];
    assign alu_candidate_local[2] = issue_window_valid_q[2] &&
        issue_window_src0_ready_q[2] && issue_window_src1_ready_q[2];
    assign alu_candidate_local[3] = issue_window_valid_q[3] &&
        issue_window_src0_ready_q[3] && issue_window_src1_ready_q[3];
    assign alu_select0_local[0] = alu_candidate_local[0];
    assign alu_select0_local[1] = alu_candidate_local[1] &&
        !alu_candidate_local[0];
    assign alu_select0_local[2] = alu_candidate_local[2] &&
        !(|alu_candidate_local[1:0]);
    assign alu_select0_local[3] = alu_candidate_local[3] &&
        !(|alu_candidate_local[2:0]);
    assign alu_after_first_local = alu_candidate_local & ~alu_select0_local;
    assign alu_select1_local[0] = alu_after_first_local[0];
    assign alu_select1_local[1] = alu_after_first_local[1] &&
        !alu_after_first_local[0];
    assign alu_select1_local[2] = alu_after_first_local[2] &&
        !(|alu_after_first_local[1:0]);
    assign alu_select1_local[3] = alu_after_first_local[3] &&
        !(|alu_after_first_local[2:0]);

    assign p0_candidate_local[0] = issue_window_valid_q[4] &&
        issue_window_src0_ready_q[4] &&
        (issue_window_src1_ready_q[4] || issue_store_q[4]) &&
        (!issue_memory_q[4] ||
         ({1'b0, lsu_credit_i} >
          ({1'b0, lsu_select_reserved_q} + agu_in_valid_q))) &&
        !(|issue_order_mask_q[4]);
    assign p0_candidate_local[1] = issue_window_valid_q[5] &&
        issue_window_src0_ready_q[5] &&
        (issue_window_src1_ready_q[5] || issue_store_q[5]) &&
        (!issue_memory_q[5] ||
         ({1'b0, lsu_credit_i} >
          ({1'b0, lsu_select_reserved_q} + agu_in_valid_q))) &&
        !(|issue_order_mask_q[5]);
    assign p0_candidate_local[2] = issue_window_valid_q[6] &&
        issue_window_src0_ready_q[6] &&
        (issue_window_src1_ready_q[6] || issue_store_q[6]) &&
        (!issue_memory_q[6] ||
         ({1'b0, lsu_credit_i} >
          ({1'b0, lsu_select_reserved_q} + agu_in_valid_q))) &&
        !(|issue_order_mask_q[6]);
    assign p0_select_local[0] = p0_candidate_local[0];
    assign p0_select_local[1] = p0_candidate_local[1] &&
        !p0_candidate_local[0];
    assign p0_select_local[2] = p0_candidate_local[2] &&
        !(|p0_candidate_local[1:0]);

    assign p1_candidate_local[0] = issue_window_valid_q[7] &&
        issue_window_src0_ready_q[7] && issue_window_src1_ready_q[7] &&
        !issue_serial_q[7] &&
        !(|issue_order_mask_q[7]) &&
        (!issue_divrem_q[7] ||
         (mdu_div_available_q && !div_select_reserved_q));
    assign p1_candidate_local[1] = issue_window_valid_q[8] &&
        issue_window_src0_ready_q[8] && issue_window_src1_ready_q[8] &&
        !issue_serial_q[8] &&
        !(|issue_order_mask_q[8]) &&
        (!issue_divrem_q[8] ||
         (mdu_div_available_q && !div_select_reserved_q));
    assign p1_candidate_local[2] = issue_window_valid_q[9] &&
        issue_window_src0_ready_q[9] && issue_window_src1_ready_q[9] &&
        !issue_serial_q[9] &&
        !(|issue_order_mask_q[9]) &&
        (!issue_divrem_q[9] ||
         (mdu_div_available_q && !div_select_reserved_q));
    assign p1_select_local[0] = p1_candidate_local[0];
    assign p1_select_local[1] = p1_candidate_local[1] &&
        !p1_candidate_local[0];
    assign p1_select_local[2] = p1_candidate_local[2] &&
        !(|p1_candidate_local[1:0]);

    assign p1_serial_candidate_local[0] = issue_window_valid_q[7] &&
        issue_window_src0_ready_q[7] && issue_window_src1_ready_q[7] &&
        issue_serial_q[7] && !(|issue_order_mask_q[7]) &&
        (issue_window_q[7].dst.rob_tag == rob_head_select_q) &&
        lsu_idle_select_q && !serial_bundle_valid_q;
    assign p1_serial_candidate_local[1] = issue_window_valid_q[8] &&
        issue_window_src0_ready_q[8] && issue_window_src1_ready_q[8] &&
        issue_serial_q[8] && !(|issue_order_mask_q[8]) &&
        (issue_window_q[8].dst.rob_tag == rob_head_select_q) &&
        lsu_idle_select_q && !serial_bundle_valid_q;
    assign p1_serial_candidate_local[2] = issue_window_valid_q[9] &&
        issue_window_src0_ready_q[9] && issue_window_src1_ready_q[9] &&
        issue_serial_q[9] && !(|issue_order_mask_q[9]) &&
        (issue_window_q[9].dst.rob_tag == rob_head_select_q) &&
        lsu_idle_select_q && !serial_bundle_valid_q;
    assign p1_serial_select_local[0] = p1_serial_candidate_local[0];
    assign p1_serial_select_local[1] = p1_serial_candidate_local[1] &&
        !p1_serial_candidate_local[0];
    assign p1_serial_select_local[2] = p1_serial_candidate_local[2] &&
        !(|p1_serial_candidate_local[1:0]);

    assign p0_select_valid = |p0_select_local;
    assign p1_select_valid = |p1_select_local;
    assign alu_select0_valid = |alu_select0_local;
    assign alu_select1_valid = |alu_select1_local;

    always_comb begin
        alu_selected_uop0 = issue_window_q[3];
        if (alu_select0_local[0])
            alu_selected_uop0 = issue_window_q[0];
        else if (alu_select0_local[1])
            alu_selected_uop0 = issue_window_q[1];
        else if (alu_select0_local[2])
            alu_selected_uop0 = issue_window_q[2];
        alu_selected_uop0.valid = alu_select0_valid;
        alu_selected_uop0.src0.ready = alu_select0_valid;
        alu_selected_uop0.src1.ready = alu_select0_valid;

        alu_selected_uop1 = issue_window_q[3];
        if (alu_select1_local[0])
            alu_selected_uop1 = issue_window_q[0];
        else if (alu_select1_local[1])
            alu_selected_uop1 = issue_window_q[1];
        else if (alu_select1_local[2])
            alu_selected_uop1 = issue_window_q[2];
        alu_selected_uop1.valid = alu_select1_valid;
        alu_selected_uop1.src0.ready = alu_select1_valid;
        alu_selected_uop1.src1.ready = alu_select1_valid;

        p0_selected_uop = issue_window_q[6];
        p0_selected_src1_due = issue_window_src1_ready_q[6];
        if (p0_select_local[0]) begin
            p0_selected_uop = issue_window_q[4];
            p0_selected_src1_due = issue_window_src1_ready_q[4];
        end else if (p0_select_local[1]) begin
            p0_selected_uop = issue_window_q[5];
            p0_selected_src1_due = issue_window_src1_ready_q[5];
        end
        p0_selected_uop.valid = p0_select_valid;
        p0_selected_uop.lane_mask = 2'b01;
        p0_selected_uop.src0.ready = p0_select_valid;
        p0_selected_uop.src1.ready = p0_select_valid &&
            p0_selected_src1_due;

        p1_selected_uop = issue_window_q[9];
        if (p1_select_local[0]) begin
            p1_selected_uop = issue_window_q[7];
        end else if (p1_select_local[1]) begin
            p1_selected_uop = issue_window_q[8];
        end
        p1_selected_uop.valid = p1_select_valid;
        p1_selected_uop.lane_mask = 2'b10;
        p1_selected_uop.src0.ready = p1_select_valid;
        p1_selected_uop.src1.ready = p1_select_valid;

        p1_serial_selected_uop = issue_window_q[9];
        if (p1_serial_select_local[0])
            p1_serial_selected_uop = issue_window_q[7];
        else if (p1_serial_select_local[1])
            p1_serial_selected_uop = issue_window_q[8];
        p1_serial_selected_uop.valid = |p1_serial_select_local;
        p1_serial_selected_uop.lane_mask = 2'b10;
        p1_serial_selected_uop.src0.ready = |p1_serial_select_local;
        p1_serial_selected_uop.src1.ready = |p1_serial_select_local;
    end

    assign alu_alloc0_local[0] = alu_free_local[0];
    assign alu_alloc0_local[1] = alu_free_local[1] && !alu_free_local[0];
    assign alu_alloc0_local[2] = alu_free_local[2] &&
        !(|alu_free_local[1:0]);
    assign alu_alloc0_local[3] = alu_free_local[3] &&
        !(|alu_free_local[2:0]);
    assign p0_alloc0_local[0] = p0_free_local[0];
    assign p0_alloc0_local[1] = p0_free_local[1] && !p0_free_local[0];
    assign p0_alloc0_local[2] = p0_free_local[2] &&
        !(|p0_free_local[1:0]);
    assign p1_alloc0_local[0] = p1_free_local[0];
    assign p1_alloc0_local[1] = p1_free_local[1] && !p1_free_local[0];
    assign p1_alloc0_local[2] = p1_free_local[2] &&
        !(|p1_free_local[1:0]);

    assign alu_alloc1_local[0] = alu_free1_local[0];
    assign alu_alloc1_local[1] = alu_free1_local[1] && !alu_free1_local[0];
    assign alu_alloc1_local[2] = alu_free1_local[2] &&
        !(|alu_free1_local[1:0]);
    assign alu_alloc1_local[3] = alu_free1_local[3] &&
        !(|alu_free1_local[2:0]);
    assign p0_alloc1_local[0] = p0_free1_local[0];
    assign p0_alloc1_local[1] = p0_free1_local[1] && !p0_free1_local[0];
    assign p0_alloc1_local[2] = p0_free1_local[2] &&
        !(|p0_free1_local[1:0]);
    assign p1_alloc1_local[0] = p1_free1_local[0];
    assign p1_alloc1_local[1] = p1_free1_local[1] && !p1_free1_local[0];
    assign p1_alloc1_local[2] = p1_free1_local[2] &&
        !(|p1_free1_local[1:0]);

    assign free_valid0 = |free_select0_vec;
    assign free_valid1 = |free_select1_vec;
    assign dispatch_slots_available =
        (!decode_pkt_i.valid || free_valid0) &&
        (!decode_pkt1_i.valid || free_valid1);

    always_comb begin
        selected_uop0 = '0;
        selected_uop1 = '0;
        selected_valid0 = 1'b0;
        selected_valid1 = 1'b0;
        issue_select_mask = '0;
        if (p0_select_valid) begin
            selected_uop0 = p0_selected_uop;
            selected_valid0 = 1'b1;
            issue_select_mask[6:4] = p0_select_local;
            if (p1_select_valid) begin
                selected_uop1 = p1_selected_uop;
                selected_valid1 = 1'b1;
                issue_select_mask[9:7] = p1_select_local;
            end else if (alu_select0_valid) begin
                selected_uop1 = alu_selected_uop0;
                selected_uop1.lane_mask = 2'b10;
                selected_valid1 = 1'b1;
                issue_select_mask[3:0] = alu_select0_local;
            end
        end else if (p1_select_valid) begin
            if (alu_select0_valid) begin
                selected_uop0 = alu_selected_uop0;
                selected_uop0.lane_mask = 2'b01;
                selected_valid0 = 1'b1;
                issue_select_mask[3:0] = alu_select0_local;
                selected_uop1 = p1_selected_uop;
                selected_valid1 = 1'b1;
                issue_select_mask[9:7] = p1_select_local;
            end else begin
                selected_uop0 = p1_selected_uop;
                selected_valid0 = 1'b1;
                issue_select_mask[9:7] = p1_select_local;
            end
        end else if (alu_select0_valid) begin
            selected_uop0 = alu_selected_uop0;
            selected_uop0.lane_mask = 2'b01;
            selected_valid0 = 1'b1;
            issue_select_mask[3:0] = alu_select0_local;
            if (alu_select1_valid) begin
                selected_uop1 = alu_selected_uop1;
                selected_uop1.lane_mask = 2'b10;
                selected_valid1 = 1'b1;
                issue_select_mask[3:0] =
                    alu_select0_local | alu_select1_local;
            end
        end
        selected_uop0.valid = selected_valid0;
        selected_uop1.valid = selected_valid1;
    end

    // The ring payload is written only by Select. Operand pop updates only the
    // narrow head/count state, so neither replay nor FU backpressure selects a
    // new value for a payload D pin.
    wire select_buf_has_room = select_buf_count_q != 2'd2;
    wire select_buf_push = select_buf_has_room && selected_valid0;
    wire serial_bundle_push = |p1_serial_select_local;
    wire [ISSUE_WINDOW_DEPTH-1:0] serial_select_mask =
        {p1_serial_select_local, 7'b0};
    wire div_select_pick = select_buf_push &&
        (|(issue_select_mask[9:7] & issue_divrem_q[9:7]));
    wire lsu_select_pick = select_buf_push &&
        (|(issue_select_mask[6:4] & issue_memory_q[6:4]));

    integer recovery_idx;
    logic [ISSUE_WINDOW_DEPTH-1:0] recovery_slot_mask;
    always_comb begin
        recovery_slot_mask = '0;
        for (recovery_idx = 0; recovery_idx < ISSUE_WINDOW_DEPTH;
             recovery_idx = recovery_idx + 1) begin
            if (issue_window_valid_q[recovery_idx] &&
                recovery_keep_mask_i[issue_window_q[recovery_idx].dst.rob_tag[
                    PRODUCER_SLOT_WIDTH-1:0]]) begin
                recovery_slot_mask[recovery_idx] = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || (flush_id_i && !branch_recovery_i) ||
            trap_flush_i || branch_recovery_i) begin
            rob_head_select_q <= '0;
            lsu_idle_select_q <= 1'b0;
            issued_slot_mask_q <= '0;
            mdu_div_available_q <= 1'b1;
            div_select_reserved_q <= 1'b0;
            div_busy_seen_q <= 1'b0;
        end else begin
            rob_head_select_q <= rob_head_id_i;
            lsu_idle_select_q <= lsu_idle_i;
            issued_slot_mask_q <=
                (select_buf_push ? issue_select_mask : '0) |
                (serial_bundle_push ? serial_select_mask : '0);
            mdu_div_available_q <= mdu_div_available_i;
            if (div_select_reserved_q && !mdu_div_available_q)
                div_busy_seen_q <= 1'b1;
            if (div_select_reserved_q && div_busy_seen_q &&
                mdu_div_available_q) begin
                div_select_reserved_q <= 1'b0;
                div_busy_seen_q <= 1'b0;
            end
            if (div_select_pick) begin
                div_select_reserved_q <= 1'b1;
                div_busy_seen_q <= 1'b0;
            end
        end
    end

    genvar rs_entry_idx;
    generate
        for (rs_entry_idx = 0; rs_entry_idx < ISSUE_WINDOW_DEPTH;
             rs_entry_idx = rs_entry_idx + 1) begin : g_rs_entry
            ydrasil_issue_rs_entry #(
                .SLOT_COUNT(ISSUE_WINDOW_DEPTH)
            ) u_entry (
                .clk(clk),
                .rst_n(rst_n),
                .hard_flush_i((flush_id_i && !branch_recovery_i) ||
                              trap_flush_i),
                .branch_recovery_i(branch_recovery_i),
                .recovery_keep_i(recovery_keep_mask_i[
                    issue_window_q[rs_entry_idx].dst.rob_tag[
                        PRODUCER_SLOT_WIDTH-1:0]]),
                .recovery_slot_mask_i(recovery_slot_mask),
                .issued_slot_mask_i(issued_slot_mask_q),
                .remove_i((select_buf_push &&
                           issue_select_mask[rs_entry_idx]) ||
                          (serial_bundle_push &&
                           serial_select_mask[rs_entry_idx])),
                .dispatch0_write_i(issue_pipe_push && free_valid0 &&
                                   free_select0_vec[rs_entry_idx]),
                .dispatch1_write_i(issue_pipe_push_two && free_valid1 &&
                                   free_select1_vec[rs_entry_idx]),
                .dispatch0_uop_i(dispatch_compact_uop),
                .dispatch1_uop_i(dispatch_compact_uop1),
                .dispatch0_order_mask_i(dispatch0_order_mask),
                .dispatch1_order_mask_i(dispatch1_order_mask),
                .dispatch0_memory_i(dispatch0_memory),
                .dispatch1_memory_i(dispatch1_memory),
                .dispatch0_store_i(dispatch0_store),
                .dispatch1_store_i(dispatch1_store),
                .dispatch0_mul_i(dispatch0_mul),
                .dispatch1_mul_i(dispatch1_mul),
                .dispatch0_divrem_i(dispatch0_divrem),
                .dispatch1_divrem_i(dispatch1_divrem),
                .dispatch0_serial_i(dispatch0_serial),
                .dispatch1_serial_i(dispatch1_serial),
                .wakeup0_valid_i(selected0_due_valid),
                .wakeup0_id_i(issue_pkt_i.dst.rob_tag),
                .wakeup1_valid_i(selected1_due_valid),
                .wakeup1_id_i(issue_pkt1_i.dst.rob_tag),
                .dtcm_wakeup_i(dtcm_reservation_i),
                .mdu_wakeup_i(mdu_due_i),
                .completion_meta_i(completion_meta_i),
                .uop_o(issue_window_q[rs_entry_idx]),
                .valid_o(issue_window_valid_q[rs_entry_idx]),
                .src0_ready_o(issue_window_src0_ready_q[rs_entry_idx]),
                .src1_ready_o(issue_window_src1_ready_q[rs_entry_idx]),
                .order_mask_o(issue_order_mask_q[rs_entry_idx]),
                .memory_o(issue_memory_q[rs_entry_idx]),
                .store_o(issue_store_q[rs_entry_idx]),
                .mul_o(issue_mul_q[rs_entry_idx]),
                .divrem_o(issue_divrem_q[rs_entry_idx]),
                .serial_o(issue_serial_q[rs_entry_idx])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            select_buf_head_q <= '0;
            select_buf_tail_q <= '0;
            select_buf_count_q <= '0;
            select_bundle0_uop0_q <= '0;
            select_bundle0_uop1_q <= '0;
            select_bundle1_uop0_q <= '0;
            select_bundle1_uop1_q <= '0;
            serial_bundle_uop_q <= '0;
            select_bundle0_pair_q <= 1'b0;
            select_bundle1_pair_q <= 1'b0;
            serial_bundle_valid_q <= 1'b0;
        end else if (flush_id_i || trap_flush_i || branch_recovery_i) begin
            select_buf_head_q <= '0;
            select_buf_tail_q <= '0;
            select_buf_count_q <= '0;
            select_bundle0_pair_q <= 1'b0;
            select_bundle1_pair_q <= 1'b0;
            serial_bundle_valid_q <= 1'b0;
        end else begin
            if (serial_bundle_pop)
                serial_bundle_valid_q <= 1'b0;
            if (serial_bundle_push) begin
                serial_bundle_uop_q <= p1_serial_selected_uop;
                serial_bundle_valid_q <= 1'b1;
            end
            if (select_buf_pop)
                select_buf_head_q <= ~select_buf_head_q;
            if (select_buf_push) begin
                if (select_buf_tail_q) begin
                    select_bundle1_uop0_q <= selected_uop0;
                    select_bundle1_uop1_q <= selected_uop1;
                    select_bundle1_pair_q <= selected_valid1;
                end else begin
                    select_bundle0_uop0_q <= selected_uop0;
                    select_bundle0_uop1_q <= selected_uop1;
                    select_bundle0_pair_q <= selected_valid1;
                end
                select_buf_tail_q <= ~select_buf_tail_q;
            end
            select_buf_count_q <= select_buf_count_q -
                {1'b0, select_buf_pop} + {1'b0, select_buf_push};
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n)
            assert (select_buf_count_q <= 2'd2)
                else $fatal(1, "Select/Operand queue overflow");
    end
`endif

    ydrasil_registers u_registers (
        .clk             (clk),
        .rst_n           (rst_n),
        .commit_pkt_i    (commit_pkt_i),
        .commit_pkt1_i   (commit_pkt1_i),
        .rf_raddr_rs1_i  (rf_addr_rs1),
        .rf_rdata_rs1_o  (rf_rdata_rs1_i),
        .rf_raddr_rs2_i  (rf_addr_rs2),
        .rf_rdata_rs2_o  (rf_rdata_rs2_i),
        .rf_raddr_rs3_i  (rf_addr_rs3),
        .rf_rdata_rs3_o  (rf_rdata_rs3_i),
        .rf_raddr_rs4_i  (rf_addr_rs4),
        .rf_rdata_rs4_o  (rf_rdata_rs4_i)
    );

    ydrasil_value_file u_value_file (
        .clk               (clk),
        .completion_meta_i (completion_meta_i),
        .completion_data_i (completion_data_i),
        .read_slot0_i      (issue_pkt_i.src0.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot1_i      (issue_pkt_i.src1.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot2_i      (issue_pkt1_i.src0.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot3_i      (issue_pkt1_i.src1.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .retire_slot0_i    (retire_slot0_i),
        .retire_slot1_i    (retire_slot1_i),
        .read_data0_o      (issue_src0_value_i),
        .read_data1_o      (issue_src1_value_i),
        .read_data2_o      (issue_src2_value_i),
        .read_data3_o      (issue_src3_value_i),
        .read_epoch0_o     (issue_src0_epoch_i),
        .read_epoch1_o     (issue_src1_epoch_i),
        .read_epoch2_o     (issue_src2_epoch_i),
        .read_epoch3_o     (issue_src3_epoch_i),
        .retire_data0_o    (retire_value0_o),
        .retire_data1_o    (retire_value1_o)
    );

    // Completion state is committed into the producer file on the same edge
    // that the global completion bus is observed. Early ALU data is available
    // at the Issue/EX capture edge. DTCM reservation arrives before its data,
    // so only its narrow selector crosses that edge.
    reg lsu_idle_q;
    reg issue_at_rob_head_q;
    reg early_wakeup_valid_q [0:1];
    producer_id_t early_wakeup_id_q [0:1];
    reg [REGS_ADDR_WIDTH-1:0] early_wakeup_rd_q [0:1];
    reg early_replay_valid_q [0:1];
    producer_id_t early_replay_id_q [0:1];
    reg [REGS_ADDR_WIDTH-1:0] early_replay_rd_q [0:1];
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
    reg [DATA_WIDTH-1:0] dtcm_stall_data_q;
    reg dtcm_stall_data_valid_q;
    ydrasil_reservation_pkt_t dtcm_operand_reservation_q;
    reg [DATA_WIDTH-1:0] dtcm_operand_data_q;
    wire dtcm_bypass_active_q =
        alu_in_operand_a_dtcm_q || alu_in_operand_b_dtcm_q ||
        agu_in_operand_a_dtcm_q || agu_in_store_data_dtcm_q ||
        csr_in_operand_a_dtcm_q || mul_in_operand_a_dtcm_q ||
        mul_in_operand_b_dtcm_q || dual_in_operand_a_dtcm_q ||
        dual_in_operand_b_dtcm_q || dual_in_branch_operand_a_dtcm_q ||
        dual_in_branch_operand_b_dtcm_q;
    wire [DATA_WIDTH-1:0] dtcm_bypass_data = dtcm_stall_data_valid_q ?
        dtcm_stall_data_q : dtcm_operand_data_q;
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
        .source_i(issue_pkt_i.src0),
        .value_i(issue_src0_value_i), .value_epoch_i(issue_src0_epoch_i),
        .arf_i(rf_rdata_rs1_i),
        .dtcm_reservation_i(dtcm_operand_reservation_q),
        .mdu_reservation_i(mdu_result_reservation_i),
        .mdu_bypass_data_i(mdu_bypass_data_i),
        .mdu_completion_i(completion_meta_i[COMPLETION_MUL]),
        .mdu_completion_data_i(completion_data_i[COMPLETION_MUL]),
        .early_main_valid_i(early_replay_valid_q[0]),
        .early_main_id_i(early_replay_id_q[0]),
        .early_main_rd_i(early_replay_rd_q[0]),
        .early_dual_valid_i(early_replay_valid_q[1]),
        .early_dual_id_i(early_replay_id_q[1]),
        .early_dual_rd_i(early_replay_rd_q[1]),
        .ready_o(src0_ready), .data_o(slot0_src0),
        .dtcm_hit_o(slot0_src0_dtcm_hit),
        .early_main_hit_o(slot0_src0_early_main_hit),
        .early_dual_hit_o(slot0_src0_early_dual_hit), .mdu_hit_o());
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source1 (
        .source_i(issue_pkt_i.src1),
        .value_i(issue_src1_value_i), .value_epoch_i(issue_src1_epoch_i),
        .arf_i(rf_rdata_rs2_i),
        .dtcm_reservation_i(dtcm_operand_reservation_q),
        .mdu_reservation_i(mdu_result_reservation_i),
        .mdu_bypass_data_i(mdu_bypass_data_i),
        .mdu_completion_i(completion_meta_i[COMPLETION_MUL]),
        .mdu_completion_data_i(completion_data_i[COMPLETION_MUL]),
        .early_main_valid_i(early_replay_valid_q[0]),
        .early_main_id_i(early_replay_id_q[0]),
        .early_main_rd_i(early_replay_rd_q[0]),
        .early_dual_valid_i(early_replay_valid_q[1]),
        .early_dual_id_i(early_replay_id_q[1]),
        .early_dual_rd_i(early_replay_rd_q[1]),
        .ready_o(src1_ready), .data_o(slot0_src1),
        .dtcm_hit_o(slot0_src1_dtcm_hit),
        .early_main_hit_o(slot0_src1_early_main_hit),
        .early_dual_hit_o(slot0_src1_early_dual_hit), .mdu_hit_o());
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source2 (
        .source_i(issue_pkt1_i.src0),
        .value_i(issue_src2_value_i), .value_epoch_i(issue_src2_epoch_i),
        .arf_i(rf_rdata_rs3_i),
        .dtcm_reservation_i(dtcm_operand_reservation_q),
        .mdu_reservation_i(mdu_result_reservation_i),
        .mdu_bypass_data_i(mdu_bypass_data_i),
        .mdu_completion_i(completion_meta_i[COMPLETION_MUL]),
        .mdu_completion_data_i(completion_data_i[COMPLETION_MUL]),
        .early_main_valid_i(early_replay_valid_q[0]),
        .early_main_id_i(early_replay_id_q[0]),
        .early_main_rd_i(early_replay_rd_q[0]),
        .early_dual_valid_i(early_replay_valid_q[1]),
        .early_dual_id_i(early_replay_id_q[1]),
        .early_dual_rd_i(early_replay_rd_q[1]),
        .ready_o(src2_ready), .data_o(slot1_src0),
        .dtcm_hit_o(slot1_src0_dtcm_hit),
        .early_main_hit_o(slot1_src0_early_main_hit),
        .early_dual_hit_o(slot1_src0_early_dual_hit), .mdu_hit_o());
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source3 (
        .source_i(issue_pkt1_i.src1),
        .value_i(issue_src3_value_i), .value_epoch_i(issue_src3_epoch_i),
        .arf_i(rf_rdata_rs4_i),
        .dtcm_reservation_i(dtcm_operand_reservation_q),
        .mdu_reservation_i(mdu_result_reservation_i),
        .mdu_bypass_data_i(mdu_bypass_data_i),
        .mdu_completion_i(completion_meta_i[COMPLETION_MUL]),
        .mdu_completion_data_i(completion_data_i[COMPLETION_MUL]),
        .early_main_valid_i(early_replay_valid_q[0]),
        .early_main_id_i(early_replay_id_q[0]),
        .early_main_rd_i(early_replay_rd_q[0]),
        .early_dual_valid_i(early_replay_valid_q[1]),
        .early_dual_id_i(early_replay_id_q[1]),
        .early_dual_rd_i(early_replay_rd_q[1]),
        .ready_o(src3_ready), .data_o(slot1_src1),
        .dtcm_hit_o(slot1_src1_dtcm_hit),
        .early_main_hit_o(slot1_src1_early_main_hit),
        .early_dual_hit_o(slot1_src1_early_dual_hit), .mdu_hit_o());
    wire slot0_store = issue_pkt_i.op_class == UOP_CLASS_STORE;
    wire slot0_scoreboard_stall = issue_pkt_i.valid &&
        (!src0_ready || (!src1_ready && !slot0_store));
    wire slot0_memory =
        (issue_pkt_i.op_class == UOP_CLASS_LOAD) ||
        (issue_pkt_i.op_class == UOP_CLASS_STORE);
    wire pair_eligible = issue_pair_execute;
    wire slot1_active = pair_eligible;
    wire slot1_store = issue_pkt1_i.op_class == UOP_CLASS_STORE;
    wire slot1_scoreboard_stall = slot1_active &&
        (!src2_ready || (!src3_ready && !slot1_store));
    wire serialize_stall = ((issue_pkt_i.op_class == UOP_CLASS_CSR) ||
        (issue_pkt_i.op_class == UOP_CLASS_SYS) || issue_pkt_i.fence_i) &&
        (!lsu_idle_q || !issue_at_rob_head_q);
    wire slot1_blocked = slot1_scoreboard_stall;
    wire local_issue_stall = slot0_scoreboard_stall ||
        serialize_stall || slot1_blocked;
    wire id_advance = !stall_id_i && !bubble_id_i && !local_issue_stall;
    wire pair_issue = pair_eligible && !slot1_blocked;
    wire head0_b_only = issue_pkt_i.lane_mask[1] &&
        !issue_pkt_i.lane_mask[0];

    assign issue_ready_o = id_advance;
    assign issue_consume_two_o = id_advance && pair_eligible;
    assign issue_slot1_replay_o = 1'b0;
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
    assign lsu_struct_stall_o = 1'b0;
    assign lsu_struct_stall1_o = 1'b0;
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
    logic [OPERATOR_WIDTH-1:0] lane_a_operator_info;
    logic [OPERATOR_WIDTH-1:0] lane_b_operator_info;
    logic [OPERATOR_TYPE_WIDTH-1:0] lane_a_operator_type;
    logic [OPERATOR_TYPE_WIDTH-1:0] lane_b_operator_type;
    always_comb begin
        lane_a_uop = issue_pkt_i;
        lane_b_uop = head0_b_only ? issue_pkt_i : issue_pkt1_i;
        lane_a_valid = issue_pkt_i.valid && !head0_b_only;
        lane_b_valid = head0_b_only ? issue_pkt_i.valid : pair_issue;
    end

    always_comb begin
        lane_a_operator_info = '0;
        lane_b_operator_info = '0;
        if (lane_a_uop.subop < UOP_SUBOP_WIDTH'(OPERATOR_WIDTH))
            lane_a_operator_info[lane_a_uop.subop] = 1'b1;
        if (lane_b_uop.subop < UOP_SUBOP_WIDTH'(OPERATOR_WIDTH))
            lane_b_operator_info[lane_b_uop.subop] = 1'b1;

        lane_a_operator_type = '0;
        unique case (lane_a_uop.op_class)
            UOP_CLASS_BJP:
                lane_a_operator_type[OPERATOR_TYPE_BJP] = 1'b1;
            UOP_CLASS_LOAD:
                lane_a_operator_type[OPERATOR_TYPE_LOAD] = 1'b1;
            UOP_CLASS_STORE:
                lane_a_operator_type[OPERATOR_TYPE_STORE] = 1'b1;
            UOP_CLASS_CSR:
                lane_a_operator_type[OPERATOR_TYPE_CSR] = 1'b1;
            UOP_CLASS_SYS: begin
                lane_a_operator_type[OPERATOR_TYPE_CSR] = 1'b1;
                lane_a_operator_type[OPERATOR_TYPE_SYS] = 1'b1;
            end
            UOP_CLASS_MUL:
                lane_a_operator_type[OPERATOR_TYPE_MUL] = 1'b1;
            UOP_CLASS_BITMANIP:
                lane_a_operator_type[OPERATOR_TYPE_BITMANIP] = 1'b1;
            default:
                lane_a_operator_type[OPERATOR_TYPE_ALU] = 1'b1;
        endcase

        lane_b_operator_type = '0;
        unique case (lane_b_uop.op_class)
            UOP_CLASS_BJP:
                lane_b_operator_type[OPERATOR_TYPE_BJP] = 1'b1;
            UOP_CLASS_LOAD:
                lane_b_operator_type[OPERATOR_TYPE_LOAD] = 1'b1;
            UOP_CLASS_STORE:
                lane_b_operator_type[OPERATOR_TYPE_STORE] = 1'b1;
            UOP_CLASS_CSR:
                lane_b_operator_type[OPERATOR_TYPE_CSR] = 1'b1;
            UOP_CLASS_SYS: begin
                lane_b_operator_type[OPERATOR_TYPE_CSR] = 1'b1;
                lane_b_operator_type[OPERATOR_TYPE_SYS] = 1'b1;
            end
            UOP_CLASS_MUL:
                lane_b_operator_type[OPERATOR_TYPE_MUL] = 1'b1;
            UOP_CLASS_BITMANIP:
                lane_b_operator_type[OPERATOR_TYPE_BITMANIP] = 1'b1;
            default:
                lane_b_operator_type[OPERATOR_TYPE_ALU] = 1'b1;
        endcase
    end

    wire [DATA_WIDTH-1:0] slot0_src0_local = slot0_src0_early_main_hit ?
        completion_data_i[COMPLETION_ALU] : slot0_src0_early_dual_hit ?
        completion_data_i[COMPLETION_DUAL_ALU] : slot0_src0;
    wire [DATA_WIDTH-1:0] slot0_src1_local = slot0_src1_early_main_hit ?
        completion_data_i[COMPLETION_ALU] : slot0_src1_early_dual_hit ?
        completion_data_i[COMPLETION_DUAL_ALU] : slot0_src1;
    wire [DATA_WIDTH-1:0] slot1_src0_local = slot1_src0_early_main_hit ?
        completion_data_i[COMPLETION_ALU] : slot1_src0_early_dual_hit ?
        completion_data_i[COMPLETION_DUAL_ALU] : slot1_src0;
    wire [DATA_WIDTH-1:0] slot1_src1_local = slot1_src1_early_main_hit ?
        completion_data_i[COMPLETION_ALU] : slot1_src1_early_dual_hit ?
        completion_data_i[COMPLETION_DUAL_ALU] : slot1_src1;
    wire lane_b_uses_slot0 = head0_b_only;
    wire lane_a_src1_ready = src1_ready;
    // A store may issue while its source scoreboard bit is stale, but the
    // Future File still contains a usable value when the producer generation
    // matches. Capture that value now so a retired store never carries a
    // recyclable producer tag into the LSU store buffer.
    wire lane_a_src1_epoch_match = lane_a_uop.src1.tag_valid &&
        issue_src1_state_i.done &&
        (issue_src1_epoch_i ==
         lane_a_uop.src1.producer_tag[PRODUCER_ID_WIDTH-1]);
    wire lane_b_src1_ready = lane_b_uses_slot0 ? src1_ready : src3_ready;
    wire [DATA_WIDTH-1:0] lane_a_src0_local = slot0_src0_local;
    wire [DATA_WIDTH-1:0] lane_a_src1_local = slot0_src1_local;
    wire [DATA_WIDTH-1:0] lane_b_src0_local = lane_b_uses_slot0 ?
        slot0_src0_local : slot1_src0_local;
    wire [DATA_WIDTH-1:0] lane_b_src1_local = lane_b_uses_slot0 ?
        slot0_src1_local : slot1_src1_local;
    wire lane_a_src0_dtcm_hit = slot0_src0_dtcm_hit;
    wire lane_a_src1_dtcm_hit = slot0_src1_dtcm_hit;
    wire lane_b_src0_dtcm_hit = lane_b_uses_slot0 ?
        slot0_src0_dtcm_hit : slot1_src0_dtcm_hit;
    wire lane_b_src1_dtcm_hit = lane_b_uses_slot0 ?
        slot0_src1_dtcm_hit : slot1_src1_dtcm_hit;
    wire selected_dtcm_hit = lane_a_src0_dtcm_hit || lane_a_src1_dtcm_hit ||
        lane_b_src0_dtcm_hit || lane_b_src1_dtcm_hit;

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
    assign rf_addr_rs1 = issue_pkt_i.src0.arch_addr;
    assign rf_addr_rs2 = issue_pkt_i.src1.arch_addr;
    assign rf_addr_rs3 = issue_pkt1_i.src0.arch_addr;
    assign rf_addr_rs4 = issue_pkt1_i.src1.arch_addr;

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
    wire slot0_early_bitmanip_supported =
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH1ADD)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH2ADD)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH3ADD)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_PACK)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_PACKH)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_REV8)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_B)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_H)) ||
        (issue_pkt_i.subop == UOP_SUBOP_WIDTH'(OP_B_ZEXT_H));
    wire slot1_early_bitmanip_supported =
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH1ADD)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH2ADD)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_SH3ADD)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_PACK)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_PACKH)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_REV8)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_B)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_SEXT_H)) ||
        (issue_pkt1_i.subop == UOP_SUBOP_WIDTH'(OP_B_ZEXT_H));
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
		!slot0_memory &&
        !issue_pkt_i.fence_i && slot0_early_exec;
	wire slot0_lane_b_early = issue_pkt_i.dst.writes_gpr && slot0_early_exec;
	wire slot1_lane_b_early = issue_pkt1_i.dst.writes_gpr && slot1_early_exec;
    wire lane_a_early_valid = lane_a_valid &&
        slot0_lane_a_early;
    wire lane_b_early_valid = lane_b_valid &&
        (lane_b_uses_slot0 ? slot0_lane_b_early : slot1_lane_b_early);
    wire producer_id_t lane_a_early_id = issue_pkt_i.dst.rob_tag;
    wire producer_id_t lane_b_early_id = lane_b_uses_slot0 ?
        issue_pkt_i.dst.rob_tag : issue_pkt1_i.dst.rob_tag;
    wire [REGS_ADDR_WIDTH-1:0] lane_a_early_rd = issue_pkt_i.dst.rd_addr;
    wire [REGS_ADDR_WIDTH-1:0] lane_b_early_rd = lane_b_uses_slot0 ?
        issue_pkt_i.dst.rd_addr : issue_pkt1_i.dst.rd_addr;

    wire lane_a_fu_valid = lane_a_accept && !lane_a_uop.fence_i;
    wire lane_a_alu_accept = lane_a_accept &&
        ((lane_a_uop.op_class == UOP_CLASS_ALU) ||
         (lane_a_uop.op_class == UOP_CLASS_BITMANIP));
    wire lane_a_agu_accept = lane_a_accept &&
        ((lane_a_uop.op_class == UOP_CLASS_LOAD) ||
         (lane_a_uop.op_class == UOP_CLASS_STORE));
    wire lane_b_alu_accept = lane_b_accept &&
        (lane_b_uop.op_class == UOP_CLASS_ALU);
    wire lane_b_bru_accept = lane_b_accept &&
        (lane_b_uop.op_class == UOP_CLASS_BJP);
    wire lane_b_mul_accept = lane_b_accept &&
        (lane_b_uop.op_class == UOP_CLASS_MUL);
    wire lane_b_csr_accept = lane_b_accept &&
        ((lane_b_uop.op_class == UOP_CLASS_CSR) ||
         (lane_b_uop.op_class == UOP_CLASS_SYS));

    always_ff @(posedge clk) begin
        if (!rst_n || flush_id_i || trap_flush_i || branch_recovery_i) begin
            lsu_select_reserved_q <= '0;
        end else begin
            unique case ({lsu_select_pick, lane_a_agu_accept})
                2'b10: lsu_select_reserved_q <= lsu_select_reserved_q + 1'b1;
                2'b01: begin
                    if (lsu_select_reserved_q != '0)
                        lsu_select_reserved_q <= lsu_select_reserved_q - 1'b1;
                end
                default: begin
                end
            endcase
        end
    end

    ydrasil_lsu_req_pkt_t shared_agu_req_d;
    ydrasil_lane_b_meta_t dual_meta_d;
    ydrasil_lane_b_alu_payload_t dual_alu_payload_d;
    ydrasil_lane_b_bru_payload_t dual_bru_payload_d;
    always_comb begin
        shared_agu_req_d = '0;
        shared_agu_req_d.valid = lane_a_agu_accept;
        shared_agu_req_d.is_load = lane_a_uop.op_class == UOP_CLASS_LOAD;
        shared_agu_req_d.is_store = lane_a_uop.op_class == UOP_CLASS_STORE;
        shared_agu_req_d.op[lane_a_uop.lsu_subop] = 1'b1;
        shared_agu_req_d.rd_addr = lane_a_uop.dst.rd_addr;
        shared_agu_req_d.producer_id = lane_a_uop.dst.rob_tag;
        shared_agu_req_d.producer_tracked = lane_a_agu_accept;
        shared_agu_req_d.store_data = lane_a_src1_local;
        shared_agu_req_d.store_data_valid = lane_a_agu_accept &&
            (!shared_agu_req_d.is_store || lane_a_src1_ready ||
             lane_a_src1_epoch_match);
        shared_agu_req_d.store_producer_id =
            lane_a_uop.src1.producer_tag;
        shared_agu_req_d.store_producer_tracked = lane_a_agu_accept &&
            shared_agu_req_d.is_store &&
            !lane_a_src1_ready && !lane_a_src1_epoch_match &&
            lane_a_uop.src1.tag_valid;
        shared_agu_req_d.retired = 1'b0;
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
        dual_alu_payload_d.bitmanip = 1'b0;
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

    // Preserve the fixed-latency DTCM identity/data for the following
    // Operand/Bypass stage. Selection consumes only the current narrow token.
    always_ff @(posedge clk) begin
        if (!rst_n || flush_id_i || trap_flush_i) begin
            dtcm_operand_reservation_q <= '0;
            dtcm_operand_data_q <= '0;
        end else begin
            dtcm_operand_reservation_q <= dtcm_reservation_i;
            dtcm_operand_data_q <= dtcm_resp_data_i;
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
            early_replay_valid_q[0] <= 1'b0;
            early_replay_valid_q[1] <= 1'b0;
            early_replay_id_q[0] <= '0;
            early_replay_id_q[1] <= '0;
            early_replay_rd_q[0] <= '0;
            early_replay_rd_q[1] <= '0;
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
            {alu_in_operand_a_dtcm_q, alu_in_operand_b_dtcm_q,
             agu_in_operand_a_dtcm_q, agu_in_store_data_dtcm_q,
             csr_in_operand_a_dtcm_q, mul_in_operand_a_dtcm_q,
             mul_in_operand_b_dtcm_q, dual_in_operand_a_dtcm_q,
             dual_in_operand_b_dtcm_q,
             dual_in_branch_operand_a_dtcm_q,
             dual_in_branch_operand_b_dtcm_q} <= '0;
            dtcm_stall_data_valid_q <= 1'b0;
        end else begin
            lsu_idle_q <= lsu_idle_i;
            issue_at_rob_head_q <= issue_at_rob_head_i;
            // Select wakes an entry when its producer enters EX. The selected
            // consumer reaches Operand one cycle later, so retain the matching
            // result locally across that boundary without extending the global
            // completion broadcast path.
            early_replay_valid_q[0] <= early_wakeup_valid_q[0];
            early_replay_valid_q[1] <= early_wakeup_valid_q[1];
            early_replay_id_q[0] <= early_wakeup_id_q[0];
            early_replay_id_q[1] <= early_wakeup_id_q[1];
            early_replay_rd_q[0] <= early_wakeup_rd_q[0];
            early_replay_rd_q[1] <= early_wakeup_rd_q[1];

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
                    {alu_in_operand_a_dtcm_q, alu_in_operand_b_dtcm_q,
                     agu_in_operand_a_dtcm_q, agu_in_store_data_dtcm_q,
                     csr_in_operand_a_dtcm_q, mul_in_operand_a_dtcm_q,
                     mul_in_operand_b_dtcm_q, dual_in_operand_a_dtcm_q,
                     dual_in_operand_b_dtcm_q,
                     dual_in_branch_operand_a_dtcm_q,
                     dual_in_branch_operand_b_dtcm_q} <= '0;
                    dtcm_stall_data_valid_q <= 1'b0;
                end else begin
					dtcm_stall_data_valid_q <= 1'b0;
                    illegal_instr_q <= lane_b_accept && lane_b_uop.illegal_instr;
                    alu_in_operand_a_dtcm_q <= lane_a_accept &&
                        lane_a_alu_exec && lane_a_op_a_src &&
                        lane_a_src0_dtcm_hit;
                    alu_in_operand_b_dtcm_q <= lane_a_accept &&
                        lane_a_alu_exec && lane_a_op_b_src &&
                        lane_a_src1_dtcm_hit;
                    agu_in_operand_a_dtcm_q <= lane_a_agu_accept &&
                        lane_a_op_a_src && lane_a_src0_dtcm_hit;
                    agu_in_store_data_dtcm_q <= lane_a_agu_accept &&
                        (lane_a_uop.op_class == UOP_CLASS_STORE) &&
                        lane_a_src1_dtcm_hit;
                    csr_in_operand_a_dtcm_q <= lane_b_csr_accept &&
                        lane_b_op_a_src && lane_b_src0_dtcm_hit;
                    mul_in_operand_a_dtcm_q <= lane_b_mul_accept &&
                        lane_b_op_a_src && lane_b_src0_dtcm_hit;
                    mul_in_operand_b_dtcm_q <= lane_b_mul_accept &&
                        lane_b_op_b_src && lane_b_src1_dtcm_hit;
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
                    if (id_advance && selected_dtcm_hit) begin
                        dtcm_stall_data_q <= dtcm_resp_data_i;
                        dtcm_stall_data_valid_q <= 1'b1;
                    end
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
                    agu_in_valid_q <= lane_a_agu_accept;
                    if (lane_a_agu_accept) begin
                        agu_in_operand_a_q <= lane_a_operand_a_local;
                        agu_in_operand_b_q <= lane_a_operand_b_local;
                        agu_in_req_q <= shared_agu_req_d;
                    end else begin
                        agu_in_req_q.valid <= 1'b0;
                    end
                    csr_in_valid_q <= lane_b_csr_accept;
                    csr_in_operand_a_q <= lane_b_operand_a_local;
                    csr_in_operator_type_q <= lane_b_operator_type;
                    csr_in_raddr_q <= lane_b_uop.csr_raddr;
                    csr_in_waddr_q <= lane_b_uop.csr_waddr;
                    csr_in_op_info_q <= lane_b_uop.csr_op_info;
                    csr_in_sys_info_q <= lane_b_uop.sys_op_info;
                    mul_in_valid_q <= lane_b_mul_accept;
                    mul_in_operand_a_q <= lane_b_operand_a_local;
                    mul_in_operand_b_q <= lane_b_operand_b_local;
                    mul_in_operator_q <= lane_b_operator_info;
                    mul_in_operator_type_q <= lane_b_operator_type;
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

	assign illegal_instr_o = illegal_instr_q;
	assign alu_in_valid_o = alu_in_valid_q;
	assign alu_in_operand_a_o = alu_in_operand_a_dtcm_q ?
        dtcm_bypass_data : alu_in_operand_a_q;
	assign alu_in_operand_b_o = alu_in_operand_b_dtcm_q ?
        dtcm_bypass_data : alu_in_operand_b_q;
    assign alu_in_operator_o = alu_in_operator_q;
    assign alu_in_operator_type_o = alu_in_operator_type_q;
    assign alu_in_rd_wen_o = alu_in_rd_wen_q;
    assign alu_in_rd_addr_o = alu_in_rd_addr_q;
    assign alu_in_producer_id_o = alu_in_producer_id_q;
	assign lane_a_pc_o = lane_a_pc_q;
    assign agu_in_valid_o = agu_in_valid_q;
	assign agu_in_operand_a_o = agu_in_operand_a_dtcm_q ?
        dtcm_bypass_data : agu_in_operand_a_q;
    assign agu_in_operand_b_o = agu_in_operand_b_q;
	assign agu_in_req_o = agu_in_req_q;
	assign agu_in_store_data_o = agu_in_store_data_dtcm_q ?
        dtcm_bypass_data : agu_in_req_q.store_data;
    assign csr_in_valid_o = csr_in_valid_q;
	assign csr_in_operand_a_o = csr_in_operand_a_dtcm_q ?
        dtcm_bypass_data : csr_in_operand_a_q;
    assign csr_in_operator_type_o = csr_in_operator_type_q;
    assign csr_in_raddr_o = csr_in_raddr_q;
    assign csr_in_waddr_o = csr_in_waddr_q;
    assign csr_in_op_info_o = csr_in_op_info_q;
    assign csr_in_sys_info_o = csr_in_sys_info_q;
    assign mul_in_valid_o = mul_in_valid_q;
	assign mul_in_operand_a_o = mul_in_operand_a_dtcm_q ?
        dtcm_bypass_data : mul_in_operand_a_q;
	assign mul_in_operand_b_o = mul_in_operand_b_dtcm_q ?
        dtcm_bypass_data : mul_in_operand_b_q;
    assign mul_in_operator_o = mul_in_operator_q;
    assign mul_in_operator_type_o = mul_in_operator_type_q;
	assign dual_meta_o = dual_meta_q;
	assign dual_alu_valid_o = dual_alu_valid_q;
	assign dual_alu_payload_o = dual_alu_payload_q;
	assign dual_alu_operand_a_o = dual_in_operand_a_dtcm_q ?
        dtcm_bypass_data : dual_alu_payload_q.operand_a;
	assign dual_alu_operand_b_o = dual_in_operand_b_dtcm_q ?
        dtcm_bypass_data : dual_alu_payload_q.operand_b;
	assign dual_bru_valid_o = dual_bru_valid_q;
	assign dual_bru_payload_o = dual_bru_payload_q;
	assign dual_bru_operand_a_o = dual_in_branch_operand_a_dtcm_q ?
        dtcm_bypass_data : dual_bru_payload_q.operand_a;
	assign dual_bru_operand_b_o = dual_in_branch_operand_b_dtcm_q ?
        dtcm_bypass_data : dual_bru_payload_q.operand_b;

`ifndef SYNTHESIS
    wire issue_valid_ff = issue_pkt_i.valid;
    logic [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff;
    always_comb begin
        issue_operator_type_ff = '0;
        unique case (issue_pkt_i.op_class)
            UOP_CLASS_BJP:
                issue_operator_type_ff[OPERATOR_TYPE_BJP] = 1'b1;
            UOP_CLASS_LOAD:
                issue_operator_type_ff[OPERATOR_TYPE_LOAD] = 1'b1;
            UOP_CLASS_STORE:
                issue_operator_type_ff[OPERATOR_TYPE_STORE] = 1'b1;
            UOP_CLASS_CSR:
                issue_operator_type_ff[OPERATOR_TYPE_CSR] = 1'b1;
            UOP_CLASS_SYS: begin
                issue_operator_type_ff[OPERATOR_TYPE_CSR] = 1'b1;
                issue_operator_type_ff[OPERATOR_TYPE_SYS] = 1'b1;
            end
            UOP_CLASS_MUL:
                issue_operator_type_ff[OPERATOR_TYPE_MUL] = 1'b1;
            UOP_CLASS_BITMANIP:
                issue_operator_type_ff[OPERATOR_TYPE_BITMANIP] = 1'b1;
            default:
                issue_operator_type_ff[OPERATOR_TYPE_ALU] = 1'b1;
        endcase
    end
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

module ydrasil_issue_rs_entry
import ydrasil_pkg::*;
#(
    parameter int SLOT_COUNT = 10
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         hard_flush_i,
    input  wire                         branch_recovery_i,
    input  wire                         recovery_keep_i,
    input  wire [SLOT_COUNT-1:0]        recovery_slot_mask_i,
    input  wire [SLOT_COUNT-1:0]        issued_slot_mask_i,
    input  wire                         remove_i,
    input  wire                         dispatch0_write_i,
    input  wire                         dispatch1_write_i,
    input  ydrasil_compact_uop_t        dispatch0_uop_i,
    input  ydrasil_compact_uop_t        dispatch1_uop_i,
    input  wire [SLOT_COUNT-1:0]        dispatch0_order_mask_i,
    input  wire [SLOT_COUNT-1:0]        dispatch1_order_mask_i,
    input  wire                         dispatch0_memory_i,
    input  wire                         dispatch1_memory_i,
    input  wire                         dispatch0_store_i,
    input  wire                         dispatch1_store_i,
    input  wire                         dispatch0_mul_i,
    input  wire                         dispatch1_mul_i,
    input  wire                         dispatch0_divrem_i,
    input  wire                         dispatch1_divrem_i,
    input  wire                         dispatch0_serial_i,
    input  wire                         dispatch1_serial_i,
    input  wire                         wakeup0_valid_i,
    input  producer_id_t                wakeup0_id_i,
    input  wire                         wakeup1_valid_i,
    input  producer_id_t                wakeup1_id_i,
    input  ydrasil_reservation_pkt_t    dtcm_wakeup_i,
    input  ydrasil_reservation_pkt_t    mdu_wakeup_i,
    input  ydrasil_completion_meta_t    completion_meta_i [COMPLETION_LANES],
    output ydrasil_compact_uop_t        uop_o,
    output wire                         valid_o,
    output wire                         src0_ready_o,
    output wire                         src1_ready_o,
    output wire [SLOT_COUNT-1:0]        order_mask_o,
    output wire                         memory_o,
    output wire                         store_o,
    output wire                         mul_o,
    output wire                         divrem_o,
    output wire                         serial_o
);
    ydrasil_compact_uop_t uop_q;
    reg valid_q;
    reg src0_ready_q;
    reg src1_ready_q;
    reg [SLOT_COUNT-1:0] order_mask_q;
    reg memory_q;
    reg store_q;
    reg mul_q;
    reg divrem_q;
    reg serial_q;
    wire [COMPLETION_LANES-1:0] current_src0_completion_hit;
    wire [COMPLETION_LANES-1:0] current_src1_completion_hit;
    wire [COMPLETION_LANES-1:0] dispatch0_src0_completion_hit;
    wire [COMPLETION_LANES-1:0] dispatch0_src1_completion_hit;
    wire [COMPLETION_LANES-1:0] dispatch1_src0_completion_hit;
    wire [COMPLETION_LANES-1:0] dispatch1_src1_completion_hit;
    genvar completion_hit_idx;
    generate
        for (completion_hit_idx = 0; completion_hit_idx < COMPLETION_LANES;
             completion_hit_idx = completion_hit_idx + 1) begin : g_completion_hit
            assign current_src0_completion_hit[completion_hit_idx] =
                completion_meta_i[completion_hit_idx].valid &&
                completion_meta_i[completion_hit_idx].producer_tracked &&
                (completion_meta_i[completion_hit_idx].producer_id ==
                 uop_q.src0.producer_tag);
            assign current_src1_completion_hit[completion_hit_idx] =
                completion_meta_i[completion_hit_idx].valid &&
                completion_meta_i[completion_hit_idx].producer_tracked &&
                (completion_meta_i[completion_hit_idx].producer_id ==
                 uop_q.src1.producer_tag);
            assign dispatch0_src0_completion_hit[completion_hit_idx] =
                completion_meta_i[completion_hit_idx].valid &&
                completion_meta_i[completion_hit_idx].producer_tracked &&
                (completion_meta_i[completion_hit_idx].producer_id ==
                 dispatch0_uop_i.src0.producer_tag);
            assign dispatch0_src1_completion_hit[completion_hit_idx] =
                completion_meta_i[completion_hit_idx].valid &&
                completion_meta_i[completion_hit_idx].producer_tracked &&
                (completion_meta_i[completion_hit_idx].producer_id ==
                 dispatch0_uop_i.src1.producer_tag);
            assign dispatch1_src0_completion_hit[completion_hit_idx] =
                completion_meta_i[completion_hit_idx].valid &&
                completion_meta_i[completion_hit_idx].producer_tracked &&
                (completion_meta_i[completion_hit_idx].producer_id ==
                 dispatch1_uop_i.src0.producer_tag);
            assign dispatch1_src1_completion_hit[completion_hit_idx] =
                completion_meta_i[completion_hit_idx].valid &&
                completion_meta_i[completion_hit_idx].producer_tracked &&
                (completion_meta_i[completion_hit_idx].producer_id ==
                 dispatch1_uop_i.src1.producer_tag);
        end
    endgenerate

    wire current_src0_wakeup =
        (wakeup0_valid_i && (wakeup0_id_i == uop_q.src0.producer_tag)) ||
        (wakeup1_valid_i && (wakeup1_id_i == uop_q.src0.producer_tag)) ||
        (dtcm_wakeup_i.valid &&
         (dtcm_wakeup_i.producer_id == uop_q.src0.producer_tag)) ||
        (mdu_wakeup_i.valid &&
         (mdu_wakeup_i.producer_id == uop_q.src0.producer_tag)) ||
        (|current_src0_completion_hit);
    wire current_src1_wakeup =
        (wakeup0_valid_i && (wakeup0_id_i == uop_q.src1.producer_tag)) ||
        (wakeup1_valid_i && (wakeup1_id_i == uop_q.src1.producer_tag)) ||
        (dtcm_wakeup_i.valid &&
         (dtcm_wakeup_i.producer_id == uop_q.src1.producer_tag)) ||
        (mdu_wakeup_i.valid &&
         (mdu_wakeup_i.producer_id == uop_q.src1.producer_tag)) ||
        (|current_src1_completion_hit);
    wire dispatch0_src0_wakeup =
        (wakeup0_valid_i &&
         (wakeup0_id_i == dispatch0_uop_i.src0.producer_tag)) ||
        (wakeup1_valid_i &&
         (wakeup1_id_i == dispatch0_uop_i.src0.producer_tag)) ||
        (dtcm_wakeup_i.valid &&
         (dtcm_wakeup_i.producer_id == dispatch0_uop_i.src0.producer_tag)) ||
        (mdu_wakeup_i.valid &&
         (mdu_wakeup_i.producer_id == dispatch0_uop_i.src0.producer_tag)) ||
        (|dispatch0_src0_completion_hit);
    wire dispatch0_src1_wakeup =
        (wakeup0_valid_i &&
         (wakeup0_id_i == dispatch0_uop_i.src1.producer_tag)) ||
        (wakeup1_valid_i &&
         (wakeup1_id_i == dispatch0_uop_i.src1.producer_tag)) ||
        (dtcm_wakeup_i.valid &&
         (dtcm_wakeup_i.producer_id == dispatch0_uop_i.src1.producer_tag)) ||
        (mdu_wakeup_i.valid &&
         (mdu_wakeup_i.producer_id == dispatch0_uop_i.src1.producer_tag)) ||
        (|dispatch0_src1_completion_hit);
    wire dispatch1_src0_wakeup =
        (wakeup0_valid_i &&
         (wakeup0_id_i == dispatch1_uop_i.src0.producer_tag)) ||
        (wakeup1_valid_i &&
         (wakeup1_id_i == dispatch1_uop_i.src0.producer_tag)) ||
        (dtcm_wakeup_i.valid &&
         (dtcm_wakeup_i.producer_id == dispatch1_uop_i.src0.producer_tag)) ||
        (mdu_wakeup_i.valid &&
         (mdu_wakeup_i.producer_id == dispatch1_uop_i.src0.producer_tag)) ||
        (|dispatch1_src0_completion_hit);
    wire dispatch1_src1_wakeup =
        (wakeup0_valid_i &&
         (wakeup0_id_i == dispatch1_uop_i.src1.producer_tag)) ||
        (wakeup1_valid_i &&
         (wakeup1_id_i == dispatch1_uop_i.src1.producer_tag)) ||
        (dtcm_wakeup_i.valid &&
         (dtcm_wakeup_i.producer_id == dispatch1_uop_i.src1.producer_tag)) ||
        (mdu_wakeup_i.valid &&
         (mdu_wakeup_i.producer_id == dispatch1_uop_i.src1.producer_tag)) ||
        (|dispatch1_src1_completion_hit);

    always_ff @(posedge clk) begin
        if (!rst_n || hard_flush_i) begin
            uop_q <= '0;
            valid_q <= 1'b0;
            src0_ready_q <= 1'b0;
            src1_ready_q <= 1'b0;
            order_mask_q <= '0;
            memory_q <= 1'b0;
            store_q <= 1'b0;
            mul_q <= 1'b0;
            divrem_q <= 1'b0;
            serial_q <= 1'b0;
        end else if (branch_recovery_i) begin
            if (valid_q && recovery_keep_i) begin
                order_mask_q <= order_mask_q & recovery_slot_mask_i;
            end else begin
                valid_q <= 1'b0;
                order_mask_q <= '0;
                memory_q <= 1'b0;
                store_q <= 1'b0;
                mul_q <= 1'b0;
                divrem_q <= 1'b0;
                serial_q <= 1'b0;
            end
        end else begin
            if (valid_q) begin
                order_mask_q <= order_mask_q & ~issued_slot_mask_i;
                if (current_src0_wakeup)
                    src0_ready_q <= 1'b1;
                if (current_src1_wakeup)
                    src1_ready_q <= 1'b1;
                if (remove_i)
                    valid_q <= 1'b0;
            end
            if (dispatch0_write_i) begin
                uop_q <= dispatch0_uop_i;
                valid_q <= 1'b1;
                src0_ready_q <= dispatch0_uop_i.src0.ready ||
                    dispatch0_src0_wakeup;
                src1_ready_q <= dispatch0_uop_i.src1.ready ||
                    dispatch0_src1_wakeup;
                order_mask_q <= dispatch0_order_mask_i;
                memory_q <= dispatch0_memory_i;
                store_q <= dispatch0_store_i;
                mul_q <= dispatch0_mul_i;
                divrem_q <= dispatch0_divrem_i;
                serial_q <= dispatch0_serial_i;
            end else if (dispatch1_write_i) begin
                uop_q <= dispatch1_uop_i;
                valid_q <= 1'b1;
                src0_ready_q <= dispatch1_uop_i.src0.ready ||
                    dispatch1_src0_wakeup;
                src1_ready_q <= dispatch1_uop_i.src1.ready ||
                    dispatch1_src1_wakeup;
                order_mask_q <= dispatch1_order_mask_i;
                memory_q <= dispatch1_memory_i;
                store_q <= dispatch1_store_i;
                mul_q <= dispatch1_mul_i;
                divrem_q <= dispatch1_divrem_i;
                serial_q <= dispatch1_serial_i;
            end
        end
    end

    assign uop_o = uop_q;
    assign valid_o = valid_q;
    assign src0_ready_o = src0_ready_q;
    assign src1_ready_o = src1_ready_q;
    assign order_mask_o = order_mask_q;
    assign memory_o = memory_q;
    assign store_o = store_q;
    assign mul_o = mul_q;
    assign divrem_o = divrem_q;
    assign serial_o = serial_q;
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
    output wire                           completion_valid_o,
    output producer_id_t                  completion_producer_id_o,
    output wire                           completion_producer_tracked_o,
    output wire [REGS_ADDR_WIDTH-1:0]     completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]     completion_data_o,
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
    assign completion_valid_o = valid_i && rd_wen_i && !interrupt_i &&
        (rd_addr_i != '0);
    assign completion_producer_id_o = producer_id_i;
    assign completion_producer_tracked_o = producer_tracked_i;
    assign completion_addr_o = rd_addr_i;
    assign completion_data_o = operator_type_i[OPERATOR_TYPE_BITMANIP] ?
        fast_bitmanip_result : alu_result;
    assign instret_valid_o = valid_q;
    assign commit_pc_o = pc_q;
    assign commit_instr_o = instr_q;
endmodule
