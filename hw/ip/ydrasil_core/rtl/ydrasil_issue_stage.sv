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
    input  wire                        decode_valid_i,
    input  wire                        decode_valid1_i,
    input  ydrasil_dispatch_domain_t   decode_domain_i,
    input  ydrasil_dispatch_domain_t   decode_domain1_i,
    input  wire [31:0]                 decode_instr_i,
    input  wire [31:0]                 decode_instr1_i,
    input  wire                        decode_serial_i,
    input  wire                        decode_serial1_i,
    input  wire                        decode_dst_writes_i,
    input  wire                        decode_dst_writes1_i,
    input  ydrasil_issue_pkt_t         dispatch_pkt_i,
    input  ydrasil_issue_pkt_t         dispatch_pkt1_i,
    input  ydrasil_source_desc_t       renamed_src0_i,
    input  ydrasil_source_desc_t       renamed_src1_i,
    input  ydrasil_source_desc_t       renamed_src2_i,
    input  ydrasil_source_desc_t       renamed_src3_i,
    input  producer_id_t               renamed_src0_tag_i,
    input  producer_id_t               renamed_src1_tag_i,
    input  producer_id_t               renamed_src2_tag_i,
    input  producer_id_t               renamed_src3_tag_i,
    input  wire                        renamed_src0_ready_i,
    input  wire                        renamed_src1_ready_i,
    input  wire                        renamed_src2_ready_i,
    input  wire                        renamed_src3_ready_i,
    input  wire                        dispatch_ready_i,
    input  ydrasil_completion_meta_t   completion_meta_i [COMPLETION_LANES],
    input  wire [REGS_DATA_WIDTH-1:0]  completion_data_i [COMPLETION_LANES],
    input  ydrasil_commit_pkt_t        commit_pkt_i,
    input  ydrasil_commit_pkt_t        commit_pkt1_i,
    input  producer_id_t               retire_id0_i,
    input  producer_id_t               retire_id1_i,
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
    output wire                        dual_bit_valid_o,
    output ydrasil_lane_b_bit_payload_t dual_bit_payload_o,
    output wire [DATA_WIDTH-1:0]       dual_bit_operand_a_o,
    output wire [DATA_WIDTH-1:0]       dual_bit_operand_b_o,
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
    wire [ISSUE_WINDOW_DEPTH-1:0] issue_early_writes_q;
    ydrasil_compact_uop_t dispatch_compact_uop;
    ydrasil_compact_uop_t dispatch_compact_uop1;
    ydrasil_compact_uop_t issue_pkt_i;
    ydrasil_compact_uop_t issue_pkt1_i;
    ydrasil_compact_uop_t select_head_uop0_q;
    ydrasil_compact_uop_t select_head_uop1_q;
    ydrasil_compact_uop_t select_skid_uop0_q;
    ydrasil_compact_uop_t select_skid_uop1_q;
    ydrasil_compact_uop_t select_head_uop1;
    reg select_head_pair_q;
    reg select_skid_pair_q;
    reg select_head_valid_q;
    reg select_skid_valid_q;
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
	    wire issue_src0_value_valid_i;
	    wire issue_src1_value_valid_i;
	    wire issue_src2_value_valid_i;
	    wire issue_src3_value_valid_i;

    wire issue_pair_execute = select_head_valid_q && select_head_pair_q;
    wire select_buf_replay = issue_ready_o && issue_pair_execute &&
        slot1_blocked;
    wire select_buf_pop = issue_ready_o && select_head_valid_q &&
        !select_buf_replay;

    // Capacity feedback depends only on registered occupancy. Selection does
    // not feed Fetch/Decode ready in the same cycle.
    wire dispatch_slots_available;
    wire issue_pipe_has_room = dispatch_ready_i && dispatch_slots_available;
    wire issue_pipe_push = !flush_id_i && issue_pipe_has_room &&
        decode_valid_i;
    wire issue_pipe_push_two = issue_pipe_push && decode_valid1_i;

    assign decode_ready_o = issue_pipe_has_room;
    assign decode_consume_two_o = issue_pipe_push_two;
    assign dispatch_accept_o = issue_pipe_push;
    assign dispatch_accept1_o = issue_pipe_push_two;
    assign issue_pkt_o = issue_pkt_i;
    assign issue_pkt1_o = issue_pkt1_i;

    always_comb begin
        issue_pkt_i = select_head_uop0_q;
        issue_pkt1_i = select_head_uop1_q;
        issue_pkt_i.valid = select_head_valid_q;
        issue_pkt1_i.valid = issue_pkt_i.valid && issue_pair_execute;
    end

    // Operand reads only the fixed head cell.  Skid movement and replay are
    // completed at the preceding clock edge, so neither a pointer nor tail
    // occupancy can select an RF or value-file address.
    always_comb begin
        select_head_uop1 = select_head_uop1_q;
        select_head_uop1.valid = issue_pair_execute;
    end

    ydrasil_issue_compactor u_issue_compactor0 (
        .issue_pkt_i   (dispatch_pkt_i),
        .compact_uop_o (dispatch_compact_uop)
    );

    ydrasil_issue_compactor u_issue_compactor1 (
        .issue_pkt_i   (dispatch_pkt1_i),
        .compact_uop_o (dispatch_compact_uop1)
    );

    producer_id_t rob_head_select_q;
    reg lsu_idle_select_q;
    reg [ISSUE_WINDOW_DEPTH-1:0] issued_slot_mask_q;
    reg select_wakeup_valid_q [0:1];
    producer_id_t select_wakeup_id_q [0:1];
    ydrasil_reservation_pkt_t dtcm_select_wakeup_q;
    ydrasil_reservation_pkt_t mdu_select_wakeup_q;
    reg mdu_div_available_q;
    reg div_select_reserved_q;
    reg div_busy_seen_q;
    reg [1:0] lsu_select_reserved_q;
    reg recovery_pending_q;
    reg [PRODUCER_NUM-1:0] recovery_keep_mask_q;
    reg [2:0] alu_free_credit_q;
    reg [1:0] p0_free_credit_q;
    reg [1:0] p1_free_credit_q;
    reg [1:0] credit_resync_q;
    wire p0_select_valid, p1_select_valid;
    wire alu_select0_valid, alu_select1_valid;
    logic [ISSUE_WINDOW_DEPTH-1:0] issue_select_mask;
    logic [ISSUE_WINDOW_DEPTH-1:0] selected0_mask;
    logic [ISSUE_WINDOW_DEPTH-1:0] selected1_mask;
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
    wire [COMPLETION_LANES-1:0] dispatch0_src0_completion_hit;
    wire [COMPLETION_LANES-1:0] dispatch0_src1_completion_hit;
    wire [COMPLETION_LANES-1:0] dispatch1_src0_completion_hit;
    wire [COMPLETION_LANES-1:0] dispatch1_src1_completion_hit;
    // RS control is predecoded from narrow instruction fields.  The complete
    // execution packet crosses the same edge as data only; its long Zb decode
    // cone is not allowed to drive RS valid/order/resource control.
    wire [6:0] dispatch0_opcode = decode_instr_i[6:0];
    wire [6:0] dispatch1_opcode = decode_instr1_i[6:0];
    wire [2:0] dispatch0_funct3 = decode_instr_i[14:12];
    wire [2:0] dispatch1_funct3 = decode_instr1_i[14:12];
    wire [6:0] dispatch0_funct7 = decode_instr_i[31:25];
    wire [6:0] dispatch1_funct7 = decode_instr1_i[31:25];
    wire dispatch0_memory = decode_domain_i == DISPATCH_DOMAIN_P0;
    wire dispatch1_memory = decode_domain1_i == DISPATCH_DOMAIN_P0;
    wire dispatch0_store = dispatch0_opcode == RV32I_INS_TYPE_S;
    wire dispatch1_store = dispatch1_opcode == RV32I_INS_TYPE_S;
    wire dispatch0_branch = (dispatch0_opcode == RV32I_INS_TYPE_B) ||
        (dispatch0_opcode == RV32I_INS_JAL) ||
        (dispatch0_opcode == RV32I_INS_JALR);
    wire dispatch1_branch = (dispatch1_opcode == RV32I_INS_TYPE_B) ||
        (dispatch1_opcode == RV32I_INS_JAL) ||
        (dispatch1_opcode == RV32I_INS_JALR);
    wire dispatch0_mul = (dispatch0_opcode == RV32I_INS_TYPE_R_M) &&
        (dispatch0_funct7 == 7'b0000001);
    wire dispatch1_mul = (dispatch1_opcode == RV32I_INS_TYPE_R_M) &&
        (dispatch1_funct7 == 7'b0000001);
    wire dispatch0_serial = decode_serial_i;
    wire dispatch1_serial = decode_serial1_i;
    wire dispatch0_divrem = dispatch0_mul && dispatch0_funct3[2];
    wire dispatch1_divrem = dispatch1_mul && dispatch1_funct3[2];
    wire dispatch0_early_bit_group0 =
        (dispatch0_opcode == RV32I_INS_TYPE_R_M) &&
        (dispatch0_funct7 == 7'b0010000) &&
        ((dispatch0_funct3 == 3'b010) ||
         (dispatch0_funct3 == 3'b100) ||
         (dispatch0_funct3 == 3'b110));
    wire dispatch1_early_bit_group0 =
        (dispatch1_opcode == RV32I_INS_TYPE_R_M) &&
        (dispatch1_funct7 == 7'b0010000) &&
        ((dispatch1_funct3 == 3'b010) ||
         (dispatch1_funct3 == 3'b100) ||
         (dispatch1_funct3 == 3'b110));
    wire dispatch0_early_bit_group1 =
        (dispatch0_opcode == RV32I_INS_TYPE_R_M) &&
        (dispatch0_funct7 == 7'b0000100) &&
        ((dispatch0_funct3 == 3'b100) ||
         (dispatch0_funct3 == 3'b111));
    wire dispatch1_early_bit_group1 =
        (dispatch1_opcode == RV32I_INS_TYPE_R_M) &&
        (dispatch1_funct7 == 7'b0000100) &&
        ((dispatch1_funct3 == 3'b100) ||
         (dispatch1_funct3 == 3'b111));
    wire dispatch0_early_bit_group2 =
        (dispatch0_opcode == RV32I_INS_TYPE_I) &&
        (((dispatch0_funct7 == 7'b0110000) &&
          (dispatch0_funct3 == 3'b001) &&
          ((decode_instr_i[24:20] == 5'b00100) ||
           (decode_instr_i[24:20] == 5'b00101))) ||
         ((dispatch0_funct7 == 7'b0110100) &&
          (dispatch0_funct3 == 3'b101) &&
          (decode_instr_i[24:20] == 5'b11000)));
    wire dispatch1_early_bit_group2 =
        (dispatch1_opcode == RV32I_INS_TYPE_I) &&
        (((dispatch1_funct7 == 7'b0110000) &&
          (dispatch1_funct3 == 3'b001) &&
          ((decode_instr1_i[24:20] == 5'b00100) ||
           (decode_instr1_i[24:20] == 5'b00101))) ||
         ((dispatch1_funct7 == 7'b0110100) &&
          (dispatch1_funct3 == 3'b101) &&
          (decode_instr1_i[24:20] == 5'b11000)));
    wire dispatch0_early = (decode_domain_i == DISPATCH_DOMAIN_ALU) ||
        dispatch0_branch || dispatch0_early_bit_group0 ||
        dispatch0_early_bit_group1 || dispatch0_early_bit_group2;
    wire dispatch1_early = (decode_domain1_i == DISPATCH_DOMAIN_ALU) ||
        dispatch1_branch || dispatch1_early_bit_group0 ||
        dispatch1_early_bit_group1 || dispatch1_early_bit_group2;
    wire dispatch0_early_writes = dispatch0_early && decode_dst_writes_i;
    wire dispatch1_early_writes = dispatch1_early && decode_dst_writes1_i;
    // Fence and illegal encodings retain an ALU base class from Decode, but
    // their serial attribute owns the P1 path and must win RS-domain routing.
    wire dispatch0_alu = decode_domain_i == DISPATCH_DOMAIN_ALU;
    wire dispatch1_alu = decode_domain1_i == DISPATCH_DOMAIN_ALU;
    wire dispatch0_p0 = decode_domain_i == DISPATCH_DOMAIN_P0;
    wire dispatch1_p0 = decode_domain1_i == DISPATCH_DOMAIN_P0;
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

    // A new source needs same-cycle completion qualification only once per
    // dispatch lane. Replicating these comparisons in every RS entry makes the
    // completion broadcast part of all ready D cones and multiplies its fanout.
    genvar dispatch_completion_idx;
    generate
        for (dispatch_completion_idx = 0;
             dispatch_completion_idx < COMPLETION_LANES;
             dispatch_completion_idx = dispatch_completion_idx + 1) begin :
                g_dispatch_completion_hit
            assign dispatch0_src0_completion_hit[dispatch_completion_idx] =
                completion_meta_i[dispatch_completion_idx].valid &&
                completion_meta_i[dispatch_completion_idx].producer_tracked &&
                (completion_meta_i[dispatch_completion_idx].producer_id ==
                 renamed_src0_tag_i);
            assign dispatch0_src1_completion_hit[dispatch_completion_idx] =
                completion_meta_i[dispatch_completion_idx].valid &&
                completion_meta_i[dispatch_completion_idx].producer_tracked &&
                (completion_meta_i[dispatch_completion_idx].producer_id ==
                 renamed_src1_tag_i);
            assign dispatch1_src0_completion_hit[dispatch_completion_idx] =
                completion_meta_i[dispatch_completion_idx].valid &&
                completion_meta_i[dispatch_completion_idx].producer_tracked &&
                (completion_meta_i[dispatch_completion_idx].producer_id ==
                 renamed_src2_tag_i);
            assign dispatch1_src1_completion_hit[dispatch_completion_idx] =
                completion_meta_i[dispatch_completion_idx].valid &&
                completion_meta_i[dispatch_completion_idx].producer_tracked &&
                (completion_meta_i[dispatch_completion_idx].producer_id ==
                 renamed_src3_tag_i);
        end
    endgenerate
    wire dispatch0_src0_ready = renamed_src0_ready_i ||
        (select_wakeup_valid_q[0] &&
         (select_wakeup_id_q[0] == renamed_src0_tag_i)) ||
        (select_wakeup_valid_q[1] &&
         (select_wakeup_id_q[1] == renamed_src0_tag_i)) ||
        (dtcm_select_wakeup_q.valid &&
         (dtcm_select_wakeup_q.producer_id ==
          renamed_src0_tag_i)) ||
        (mdu_select_wakeup_q.valid &&
         (mdu_select_wakeup_q.producer_id ==
          renamed_src0_tag_i)) ||
        (|dispatch0_src0_completion_hit);
    wire dispatch0_src1_ready = renamed_src1_ready_i ||
        (select_wakeup_valid_q[0] &&
         (select_wakeup_id_q[0] == renamed_src1_tag_i)) ||
        (select_wakeup_valid_q[1] &&
         (select_wakeup_id_q[1] == renamed_src1_tag_i)) ||
        (dtcm_select_wakeup_q.valid &&
         (dtcm_select_wakeup_q.producer_id ==
          renamed_src1_tag_i)) ||
        (mdu_select_wakeup_q.valid &&
         (mdu_select_wakeup_q.producer_id ==
          renamed_src1_tag_i)) ||
        (|dispatch0_src1_completion_hit);
    wire dispatch1_src0_ready = renamed_src2_ready_i ||
        (select_wakeup_valid_q[0] &&
         (select_wakeup_id_q[0] == renamed_src2_tag_i)) ||
        (select_wakeup_valid_q[1] &&
         (select_wakeup_id_q[1] == renamed_src2_tag_i)) ||
        (dtcm_select_wakeup_q.valid &&
         (dtcm_select_wakeup_q.producer_id ==
          renamed_src2_tag_i)) ||
        (mdu_select_wakeup_q.valid &&
         (mdu_select_wakeup_q.producer_id ==
          renamed_src2_tag_i)) ||
        (|dispatch1_src0_completion_hit);
    wire dispatch1_src1_ready = renamed_src3_ready_i ||
        (select_wakeup_valid_q[0] &&
         (select_wakeup_id_q[0] == renamed_src3_tag_i)) ||
        (select_wakeup_valid_q[1] &&
         (select_wakeup_id_q[1] == renamed_src3_tag_i)) ||
        (dtcm_select_wakeup_q.valid &&
         (dtcm_select_wakeup_q.producer_id ==
          renamed_src3_tag_i)) ||
        (mdu_select_wakeup_q.valid &&
         (mdu_select_wakeup_q.producer_id ==
          renamed_src3_tag_i)) ||
        (|dispatch1_src1_completion_hit);

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
         ({1'b0, lsu_credit_i} > {1'b0, lsu_select_reserved_q})) &&
        !(|issue_order_mask_q[4]);
    assign p0_candidate_local[1] = issue_window_valid_q[5] &&
        issue_window_src0_ready_q[5] &&
        (issue_window_src1_ready_q[5] || issue_store_q[5]) &&
        (!issue_memory_q[5] ||
         ({1'b0, lsu_credit_i} > {1'b0, lsu_select_reserved_q})) &&
        !(|issue_order_mask_q[5]);
    assign p0_candidate_local[2] = issue_window_valid_q[6] &&
        issue_window_src0_ready_q[6] &&
        (issue_window_src1_ready_q[6] || issue_store_q[6]) &&
        (!issue_memory_q[6] ||
         ({1'b0, lsu_credit_i} > {1'b0, lsu_select_reserved_q})) &&
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
        lsu_idle_select_q;
    assign p1_serial_candidate_local[1] = issue_window_valid_q[8] &&
        issue_window_src0_ready_q[8] && issue_window_src1_ready_q[8] &&
        issue_serial_q[8] && !(|issue_order_mask_q[8]) &&
        (issue_window_q[8].dst.rob_tag == rob_head_select_q) &&
        lsu_idle_select_q;
    assign p1_serial_candidate_local[2] = issue_window_valid_q[9] &&
        issue_window_src0_ready_q[9] && issue_window_src1_ready_q[9] &&
        issue_serial_q[9] && !(|issue_order_mask_q[9]) &&
        (issue_window_q[9].dst.rob_tag == rob_head_select_q) &&
        lsu_idle_select_q;
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
    wire [2:0] alu_free_count =
        3'(alu_free_local[0]) + 3'(alu_free_local[1]) +
        3'(alu_free_local[2]) + 3'(alu_free_local[3]);
    wire [1:0] p0_free_count =
        2'(p0_free_local[0]) + 2'(p0_free_local[1]) +
        2'(p0_free_local[2]);
    wire [1:0] p1_free_count =
        2'(p1_free_local[0]) + 2'(p1_free_local[1]) +
        2'(p1_free_local[2]);
    wire [1:0] alu_dispatch_demand =
        {1'b0, decode_valid_i && dispatch0_alu} +
        {1'b0, decode_valid1_i && dispatch1_alu};
    wire [1:0] p0_dispatch_demand =
        {1'b0, decode_valid_i && !dispatch0_alu && dispatch0_p0} +
        {1'b0, decode_valid1_i && !dispatch1_alu && dispatch1_p0};
    wire [1:0] p1_dispatch_demand =
        {1'b0, decode_valid_i && !dispatch0_alu && !dispatch0_p0} +
        {1'b0, decode_valid1_i && !dispatch1_alu && !dispatch1_p0};
    assign dispatch_slots_available =
        (alu_free_credit_q >= {1'b0, alu_dispatch_demand}) &&
        (p0_free_credit_q >= p0_dispatch_demand) &&
        (p1_free_credit_q >= p1_dispatch_demand) &&
        (credit_resync_q == '0);

    always_comb begin
        selected_uop0 = '0;
        selected_uop1 = '0;
        selected_valid0 = 1'b0;
        selected_valid1 = 1'b0;
        selected0_mask = '0;
        selected1_mask = '0;
        if (|p1_serial_select_local) begin
            selected_uop0 = p1_serial_selected_uop;
            selected_valid0 = 1'b1;
            selected0_mask[9:7] = p1_serial_select_local;
        end else if (p0_select_valid) begin
            selected_uop0 = p0_selected_uop;
            selected_valid0 = 1'b1;
            selected0_mask[6:4] = p0_select_local;
            if (p1_select_valid) begin
                selected_uop1 = p1_selected_uop;
                selected_valid1 = 1'b1;
                selected1_mask[9:7] = p1_select_local;
            end else if (alu_select0_valid) begin
                selected_uop1 = alu_selected_uop0;
                selected_uop1.lane_mask = 2'b10;
                selected_valid1 = 1'b1;
                selected1_mask[3:0] = alu_select0_local;
            end
        end else if (p1_select_valid) begin
            if (alu_select0_valid) begin
                selected_uop0 = alu_selected_uop0;
                selected_uop0.lane_mask = 2'b01;
                selected_valid0 = 1'b1;
                selected0_mask[3:0] = alu_select0_local;
                selected_uop1 = p1_selected_uop;
                selected_valid1 = 1'b1;
                selected1_mask[9:7] = p1_select_local;
            end else begin
                selected_uop0 = p1_selected_uop;
                selected_valid0 = 1'b1;
                selected0_mask[9:7] = p1_select_local;
            end
        end else if (alu_select0_valid) begin
            selected_uop0 = alu_selected_uop0;
            selected_uop0.lane_mask = 2'b01;
            selected_valid0 = 1'b1;
            selected0_mask[3:0] = alu_select0_local;
            if (alu_select1_valid) begin
                selected_uop1 = alu_selected_uop1;
                selected_uop1.lane_mask = 2'b10;
                selected_valid1 = 1'b1;
                selected1_mask[3:0] = alu_select1_local;
            end
        end
        selected_uop0.valid = selected_valid0;
        selected_uop1.valid = selected_valid1;
        issue_select_mask = selected0_mask | selected1_mask;
    end

    // The ring payload is written only by Select. Operand pop updates only the
    // narrow head/count state, so neither replay nor FU backpressure selects a
    // new value for a payload D pin.
    wire select_buf_has_room = !select_skid_valid_q;
    wire select_buf_push = select_buf_has_room && selected_valid0 &&
        !branch_recovery_i && !recovery_pending_q;

    // Wake dependents when Select has committed the producer to the local
    // Operand queue. A dependent selected on the next cycle is ordered behind
    // that producer by the queue, while the global completion/resolver cone no
    // longer feeds back into every RS entry's ready D/CE pins.
    wire selected0_due_valid = select_buf_push &&
        (|(selected0_mask & issue_early_writes_q));
    wire selected1_due_valid = select_buf_push && selected_valid1 &&
        (|(selected1_mask & issue_early_writes_q));
    wire div_select_pick = select_buf_push &&
        (|(issue_select_mask[9:7] & issue_divrem_q[9:7]));
    // Every P0 entry is an LSU operation.  Its credit reservation is local to
    // the P0 pick and must not depend on the combined P0/P1/ALU select mask.
    wire lsu_select_pick = select_buf_push &&
        (|issue_select_mask[6:4]);

    // Release credits from the prior cycle's registered removal mask.  This is
    // deliberately one cycle pessimistic; current LSU/DIV/Select decisions do
    // not cross back into the Dispatch credit register D pins.
    wire [2:0] alu_remove_count =
        3'(issued_slot_mask_q[0]) + 3'(issued_slot_mask_q[1]) +
        3'(issued_slot_mask_q[2]) + 3'(issued_slot_mask_q[3]);
    wire [1:0] p0_remove_count =
        2'(issued_slot_mask_q[4]) + 2'(issued_slot_mask_q[5]) +
        2'(issued_slot_mask_q[6]);
    wire [1:0] p1_remove_count =
        2'(issued_slot_mask_q[7]) + 2'(issued_slot_mask_q[8]) +
        2'(issued_slot_mask_q[9]);
    wire [2:0] alu_alloc_count =
        3'(issue_pipe_push && dispatch0_alu) +
        3'(issue_pipe_push_two && dispatch1_alu);
    wire [1:0] p0_alloc_count =
        2'(issue_pipe_push && dispatch0_p0) +
        2'(issue_pipe_push_two && dispatch1_p0);
    wire [1:0] p1_alloc_count =
        2'(issue_pipe_push && !dispatch0_alu && !dispatch0_p0) +
        2'(issue_pipe_push_two && !dispatch1_alu && !dispatch1_p0);

    // Dispatch sees only registered per-domain credits.  Select removes and ID
    // allocations update the mirror on the same edge as the RS entries, so
    // live RS valid bits never form a combinational ready path back to FetchQ.
    always_ff @(posedge clk) begin
        if (!rst_n || trap_flush_i ||
            (flush_id_i && !branch_recovery_i)) begin
            alu_free_credit_q <= 3'd4;
            p0_free_credit_q <= 2'd3;
            p1_free_credit_q <= 2'd3;
            credit_resync_q <= '0;
        end else if (branch_recovery_i) begin
            alu_free_credit_q <= '0;
            p0_free_credit_q <= '0;
            p1_free_credit_q <= '0;
            credit_resync_q <= 2'd2;
        end else if (credit_resync_q != '0) begin
            credit_resync_q <= credit_resync_q - 1'b1;
            if (credit_resync_q == 2'd1) begin
                alu_free_credit_q <= alu_free_count;
                p0_free_credit_q <= p0_free_count;
                p1_free_credit_q <= p1_free_count;
            end
        end else begin
            alu_free_credit_q <= alu_free_credit_q + alu_remove_count -
                alu_alloc_count;
            p0_free_credit_q <= p0_free_credit_q + p0_remove_count -
                p0_alloc_count;
            p1_free_credit_q <= p1_free_credit_q + p1_remove_count -
                p1_alloc_count;
        end
    end

    integer recovery_idx;
    logic [ISSUE_WINDOW_DEPTH-1:0] recovery_slot_mask;
    always_comb begin
        recovery_slot_mask = '0;
        for (recovery_idx = 0; recovery_idx < ISSUE_WINDOW_DEPTH;
             recovery_idx = recovery_idx + 1) begin
            if (issue_window_valid_q[recovery_idx] &&
                recovery_keep_mask_q[issue_window_q[recovery_idx].dst.rob_tag[
                    PRODUCER_SLOT_WIDTH-1:0]]) begin
                recovery_slot_mask[recovery_idx] = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || trap_flush_i ||
            (flush_id_i && !branch_recovery_i)) begin
            recovery_pending_q <= 1'b0;
            recovery_keep_mask_q <= '0;
        end else begin
            recovery_pending_q <= branch_recovery_i;
            if (branch_recovery_i)
                recovery_keep_mask_q <= recovery_keep_mask_i;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || (flush_id_i && !branch_recovery_i) ||
            trap_flush_i || branch_recovery_i) begin
            rob_head_select_q <= '0;
            lsu_idle_select_q <= 1'b0;
            issued_slot_mask_q <= '0;
            select_wakeup_valid_q[0] <= 1'b0;
            select_wakeup_valid_q[1] <= 1'b0;
            select_wakeup_id_q[0] <= '0;
            select_wakeup_id_q[1] <= '0;
            dtcm_select_wakeup_q <= '0;
            mdu_select_wakeup_q <= '0;
            mdu_div_available_q <= 1'b1;
            div_select_reserved_q <= 1'b0;
            div_busy_seen_q <= 1'b0;
        end else begin
            rob_head_select_q <= rob_head_id_i;
            lsu_idle_select_q <= lsu_idle_i;
            issued_slot_mask_q <=
                select_buf_push ? issue_select_mask : '0;
            select_wakeup_valid_q[0] <= selected0_due_valid;
            select_wakeup_valid_q[1] <= selected1_due_valid;
            select_wakeup_id_q[0] <= selected_uop0.dst.rob_tag;
            select_wakeup_id_q[1] <= selected_uop1.dst.rob_tag;
            dtcm_select_wakeup_q <= dtcm_reservation_i;
            mdu_select_wakeup_q <= mdu_due_i;
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
                .branch_recovery_i(recovery_pending_q),
                .recovery_keep_i(recovery_keep_mask_q[
                    issue_window_q[rs_entry_idx].dst.rob_tag[
                        PRODUCER_SLOT_WIDTH-1:0]]),
                .recovery_slot_mask_i(recovery_slot_mask),
                .issued_slot_mask_i(issued_slot_mask_q),
                .remove_i(select_buf_push &&
                          issue_select_mask[rs_entry_idx]),
                .dispatch0_write_i(issue_pipe_push && free_valid0 &&
                                   free_select0_vec[rs_entry_idx]),
                .dispatch1_write_i(issue_pipe_push_two && free_valid1 &&
                                   free_select1_vec[rs_entry_idx]),
                .dispatch0_uop_i(dispatch_compact_uop),
                .dispatch1_uop_i(dispatch_compact_uop1),
                .dispatch0_src0_ready_i(dispatch0_src0_ready),
                .dispatch0_src1_ready_i(dispatch0_src1_ready),
                .dispatch1_src0_ready_i(dispatch1_src0_ready),
                .dispatch1_src1_ready_i(dispatch1_src1_ready),
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
                .dispatch0_early_writes_i(dispatch0_early_writes),
                .dispatch1_early_writes_i(dispatch1_early_writes),
                .wakeup0_valid_i(select_wakeup_valid_q[0]),
                .wakeup0_id_i(select_wakeup_id_q[0]),
                .wakeup1_valid_i(select_wakeup_valid_q[1]),
                .wakeup1_id_i(select_wakeup_id_q[1]),
                .dtcm_wakeup_i(dtcm_select_wakeup_q),
                .mdu_wakeup_i(mdu_select_wakeup_q),
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
                .serial_o(issue_serial_q[rs_entry_idx]),
                .early_writes_o(issue_early_writes_q[rs_entry_idx])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            select_head_uop0_q <= '0;
            select_head_uop1_q <= '0;
            select_skid_uop0_q <= '0;
            select_skid_uop1_q <= '0;
            select_head_pair_q <= 1'b0;
            select_skid_pair_q <= 1'b0;
            select_head_valid_q <= 1'b0;
            select_skid_valid_q <= 1'b0;
        end else if (flush_id_i || trap_flush_i || branch_recovery_i) begin
            select_head_pair_q <= 1'b0;
            select_skid_pair_q <= 1'b0;
            select_head_valid_q <= 1'b0;
            select_skid_valid_q <= 1'b0;
        end else begin
            if (select_buf_pop) begin
                if (select_skid_valid_q) begin
                    select_head_uop0_q <= select_skid_uop0_q;
                    select_head_uop1_q <= select_skid_uop1_q;
                    select_head_pair_q <= select_skid_pair_q;
                    select_head_valid_q <= 1'b1;
                    select_skid_pair_q <= 1'b0;
                    select_skid_valid_q <= 1'b0;
                end else if (select_buf_push) begin
                    select_head_uop0_q <= selected_uop0;
                    select_head_uop1_q <= selected_uop1;
                    select_head_pair_q <= selected_valid1;
                    select_head_valid_q <= 1'b1;
                end else begin
                    select_head_pair_q <= 1'b0;
                    select_head_valid_q <= 1'b0;
                end
            end else begin
                if (select_buf_replay) begin
                    select_head_uop0_q <= select_head_uop1_q;
                    select_head_pair_q <= 1'b0;
                end
                if (select_buf_push) begin
                    if (!select_head_valid_q) begin
                        select_head_uop0_q <= selected_uop0;
                        select_head_uop1_q <= selected_uop1;
                        select_head_pair_q <= selected_valid1;
                        select_head_valid_q <= 1'b1;
                    end else begin
                        select_skid_uop0_q <= selected_uop0;
                        select_skid_uop1_q <= selected_uop1;
                        select_skid_pair_q <= selected_valid1;
                        select_skid_valid_q <= 1'b1;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n)
            assert (!(select_skid_valid_q && !select_head_valid_q))
                else $fatal(1, "Select/Operand skid without head");
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
	        .rst_n             (rst_n),
	        .alloc0_valid_i    (issue_pipe_push),
	        .alloc0_id_i       (dispatch_compact_uop.dst.rob_tag),
	        .alloc1_valid_i    (issue_pipe_push_two),
	        .alloc1_id_i       (dispatch_compact_uop1.dst.rob_tag),
        .completion_meta_i (completion_meta_i),
        .completion_data_i (completion_data_i),
        .read_slot0_i      (issue_pkt_i.src0.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot1_i      (issue_pkt_i.src1.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot2_i      (select_head_uop1.src0.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .read_slot3_i      (select_head_uop1.src1.producer_tag[
            PRODUCER_SLOT_WIDTH-1:0]),
        .retire_id0_i      (retire_id0_i),
        .retire_id1_i      (retire_id1_i),
        .read_data0_o      (issue_src0_value_i),
        .read_data1_o      (issue_src1_value_i),
        .read_data2_o      (issue_src2_value_i),
        .read_data3_o      (issue_src3_value_i),
        .read_epoch0_o     (issue_src0_epoch_i),
        .read_epoch1_o     (issue_src1_epoch_i),
        .read_epoch2_o     (issue_src2_epoch_i),
        .read_epoch3_o     (issue_src3_epoch_i),
	        .read_valid0_o     (issue_src0_value_valid_i),
	        .read_valid1_o     (issue_src1_value_valid_i),
	        .read_valid2_o     (issue_src2_value_valid_i),
	        .read_valid3_o     (issue_src3_value_valid_i),
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
    reg [DATA_WIDTH-1:0] early_replay_data_q [0:1];
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
    reg dual_alu_valid_q, dual_bit_valid_q, dual_bru_valid_q;
    ydrasil_lane_b_alu_payload_t dual_alu_payload_q;
    ydrasil_lane_b_bit_payload_t dual_bit_payload_q;
    ydrasil_lane_b_bru_payload_t dual_bru_payload_q;
    ydrasil_reservation_pkt_t dtcm_operand_reservation_q;
    ydrasil_reservation_pkt_t mdu_operand_reservation_q;
    reg [DATA_WIDTH-1:0] mdu_operand_data_q;
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
	    wire slot0_src1_mdu_hit;

    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source0 (
        .source_i(issue_pkt_i.src0),
        .value_i(issue_src0_value_i), .value_epoch_i(issue_src0_epoch_i),
        .arf_i(rf_rdata_rs1_i),
        .dtcm_reservation_i(dtcm_operand_reservation_q),
        .mdu_reservation_i(mdu_operand_reservation_q),
        .mdu_bypass_data_i(mdu_operand_data_q),
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
        .mdu_reservation_i(mdu_operand_reservation_q),
        .mdu_bypass_data_i(mdu_operand_data_q),
        .early_main_valid_i(early_replay_valid_q[0]),
        .early_main_id_i(early_replay_id_q[0]),
        .early_main_rd_i(early_replay_rd_q[0]),
        .early_dual_valid_i(early_replay_valid_q[1]),
        .early_dual_id_i(early_replay_id_q[1]),
        .early_dual_rd_i(early_replay_rd_q[1]),
        .ready_o(src1_ready), .data_o(slot0_src1),
        .dtcm_hit_o(slot0_src1_dtcm_hit),
        .early_main_hit_o(slot0_src1_early_main_hit),
        .early_dual_hit_o(slot0_src1_early_dual_hit),
	        .mdu_hit_o(slot0_src1_mdu_hit));
    ydrasil_issue_source_resolver #(.DATA_WIDTH(DATA_WIDTH)) u_source2 (
        .source_i(select_head_uop1.src0),
        .value_i(issue_src2_value_i), .value_epoch_i(issue_src2_epoch_i),
        .arf_i(rf_rdata_rs3_i),
        .dtcm_reservation_i(dtcm_operand_reservation_q),
        .mdu_reservation_i(mdu_operand_reservation_q),
        .mdu_bypass_data_i(mdu_operand_data_q),
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
        .source_i(select_head_uop1.src1),
        .value_i(issue_src3_value_i), .value_epoch_i(issue_src3_epoch_i),
        .arf_i(rf_rdata_rs4_i),
        .dtcm_reservation_i(dtcm_operand_reservation_q),
        .mdu_reservation_i(mdu_operand_reservation_q),
        .mdu_bypass_data_i(mdu_operand_data_q),
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
    wire local_issue_stall = slot0_scoreboard_stall || serialize_stall;
    wire id_advance = !local_issue_stall;
    wire pair_issue = pair_eligible && !slot1_blocked;
    wire head0_b_only = issue_pkt_i.lane_mask[1] &&
        !issue_pkt_i.lane_mask[0];

    assign issue_ready_o = id_advance;
    assign issue_consume_two_o = id_advance && pair_eligible &&
        !slot1_blocked;
    assign issue_slot1_replay_o = id_advance && pair_eligible &&
        slot1_blocked;
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
        early_replay_data_q[0] : slot0_src0_early_dual_hit ?
        early_replay_data_q[1] : slot0_src0;
    wire [DATA_WIDTH-1:0] slot0_src1_local = slot0_src1_early_main_hit ?
        early_replay_data_q[0] : slot0_src1_early_dual_hit ?
        early_replay_data_q[1] : slot0_src1;
    wire [DATA_WIDTH-1:0] slot1_src0_local = slot1_src0_early_main_hit ?
        early_replay_data_q[0] : slot1_src0_early_dual_hit ?
        early_replay_data_q[1] : slot1_src0;
    wire [DATA_WIDTH-1:0] slot1_src1_local = slot1_src1_early_main_hit ?
        early_replay_data_q[0] : slot1_src1_early_dual_hit ?
        early_replay_data_q[1] : slot1_src1;
    wire lane_b_uses_slot0 = head0_b_only;
    wire lane_a_src1_ready = src1_ready;
	    // Once the tagged producer is no longer live, in-order retirement has
	    // made its value architectural.  Read the ARF and stop carrying the
	    // recyclable producer tag into the LSU.
	    wire lane_a_src1_arf_ready = lane_a_uop.src1.used &&
	        (lane_a_uop.src1.arch_addr != '0) &&
	        lane_a_uop.src1.tag_valid && !issue_src1_state_i.live;
	    wire lane_a_src1_value_ready = !lane_a_uop.src1.used ||
	        (lane_a_uop.src1.arch_addr == '0) ||
	        !lane_a_uop.src1.tag_valid ||
	        (issue_src1_value_valid_i &&
	         (issue_src1_epoch_i ==
	          lane_a_uop.src1.producer_tag[PRODUCER_ID_WIDTH-1])) ||
	        lane_a_src1_arf_ready || lane_a_src1_dtcm_hit ||
	        slot0_src1_mdu_hit ||
	        slot0_src1_early_main_hit || slot0_src1_early_dual_hit;
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
    assign rf_addr_rs1 = issue_pkt_i.src0.arch_addr;
    assign rf_addr_rs2 = issue_pkt_i.src1.arch_addr;
    assign rf_addr_rs3 = select_head_uop1.src0.arch_addr;
    assign rf_addr_rs4 = select_head_uop1.src1.arch_addr;

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
    // DTCM identity is resolved in Operand. Select the matching registered LSU
    // response on the FU input D side so no data or selector bypasses the
    // Operand/EX register boundary.
    wire [DATA_WIDTH-1:0] lane_a_operand_a_capture =
        (lane_a_op_a_src && lane_a_src0_dtcm_hit) ?
        dtcm_resp_data_i : lane_a_operand_a_local;
    wire [DATA_WIDTH-1:0] lane_a_operand_b_capture =
        (lane_a_op_b_src && lane_a_src1_dtcm_hit) ?
        dtcm_resp_data_i : lane_a_operand_b_local;
    wire [DATA_WIDTH-1:0] lane_b_operand_a_capture =
        (lane_b_op_a_src && lane_b_src0_dtcm_hit) ?
        dtcm_resp_data_i : lane_b_operand_a_local;
    wire [DATA_WIDTH-1:0] lane_b_operand_b_capture =
        (lane_b_op_b_src && lane_b_src1_dtcm_hit) ?
        dtcm_resp_data_i : lane_b_operand_b_local;
    wire [DATA_WIDTH-1:0] lane_b_src0_capture = lane_b_src0_dtcm_hit ?
        dtcm_resp_data_i : lane_b_src0_local;
    wire [DATA_WIDTH-1:0] lane_b_src1_capture = lane_b_src1_dtcm_hit ?
        dtcm_resp_data_i : lane_b_src1_local;
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
    wire lane_b_bit_accept = lane_b_accept &&
        (lane_b_uop.op_class == UOP_CLASS_BITMANIP);
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
            unique case ({lsu_select_pick, agu_in_valid_q})
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
    ydrasil_lane_b_bit_payload_t dual_bit_payload_d;
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
        shared_agu_req_d.store_data = lane_a_src1_arf_ready ?
            rf_rdata_rs2_i : lane_a_src1_dtcm_hit ?
            dtcm_resp_data_i : lane_a_src1_local;
        shared_agu_req_d.store_data_valid = lane_a_agu_accept &&
            (!shared_agu_req_d.is_store || lane_a_src1_value_ready);
        shared_agu_req_d.store_producer_id =
            lane_a_uop.src1.producer_tag;
        shared_agu_req_d.store_producer_tracked = lane_a_agu_accept &&
            shared_agu_req_d.is_store &&
	        !lane_a_src1_value_ready && lane_a_uop.src1.tag_valid;
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
        dual_alu_payload_d.subop = lane_b_uop.subop;
        dual_alu_payload_d.operand_a = lane_b_operand_a_capture;
        dual_alu_payload_d.operand_b = lane_b_operand_b_capture;

        dual_bit_payload_d = '0;
        dual_bit_payload_d.subop = lane_b_uop.subop;
        dual_bit_payload_d.operand_a = lane_b_operand_a_capture;
        dual_bit_payload_d.operand_b = lane_b_operand_b_capture;

        dual_bru_payload_d = '0;
        dual_bru_payload_d.subop = lane_b_uop.subop;
        dual_bru_payload_d.operand_a = lane_b_src0_capture;
        dual_bru_payload_d.operand_b = lane_b_src1_capture;
        dual_bru_payload_d.imm = lane_b_uop.imm;
        dual_bru_payload_d.jalr = lane_b_uop.bt_a_rs_sel;
        dual_bru_payload_d.pred_hit = lane_b_uop.pred_hit;
        dual_bru_payload_d.pred_taken = lane_b_uop.pred_taken;
        dual_bru_payload_d.pred_target = lane_b_uop.pred_target;
        dual_bru_payload_d.pred_counter = lane_b_uop.pred_counter;
        dual_bru_payload_d.pred_bht_index = lane_b_uop.pred_bht_index;
    end

    // Return-channel identity and data cross into Operand together. No live
    // EX result qualification is allowed to feed Operand control or FU D pins.
    always_ff @(posedge clk) begin
        if (!rst_n || flush_id_i || trap_flush_i) begin
            dtcm_operand_reservation_q <= '0;
            mdu_operand_reservation_q <= '0;
            mdu_operand_data_q <= '0;
        end else begin
            dtcm_operand_reservation_q <= dtcm_reservation_i;
            mdu_operand_reservation_q <= mdu_result_reservation_i;
            mdu_operand_data_q <= mdu_bypass_data_i;
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
            early_replay_data_q[0] <= '0;
            early_replay_data_q[1] <= '0;
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
            dual_bit_valid_q <= 1'b0;
            dual_bit_payload_q <= '0;
            dual_bru_valid_q <= 1'b0;
            dual_bru_payload_q <= '0;
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
            early_replay_data_q[0] <= early_main_bypass_data_i;
            early_replay_data_q[1] <= early_dual_bypass_data_i;

                    illegal_instr_q <= lane_b_accept && lane_b_uop.illegal_instr;
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
                    alu_in_operand_a_q <= lane_a_operand_a_capture;
                    alu_in_operand_b_q <= lane_a_operand_b_capture;
                    alu_in_operator_q <= lane_a_operator_info;
                    alu_in_operator_type_q <= lane_a_operator_type;
                    alu_in_rd_wen_q <= lane_a_fu_valid &&
                        lane_a_uop.dst.writes_gpr;
                    alu_in_rd_addr_q <= lane_a_uop.dst.rd_addr;
                    alu_in_producer_id_q <= lane_a_uop.dst.rob_tag;
                    lane_a_pc_q <= lane_a_uop.pc;
                    agu_in_valid_q <= lane_a_agu_accept;
                    if (lane_a_agu_accept) begin
                        agu_in_operand_a_q <= lane_a_operand_a_capture;
                        agu_in_operand_b_q <= lane_a_operand_b_capture;
                        agu_in_req_q <= shared_agu_req_d;
                    end else begin
                        agu_in_req_q.valid <= 1'b0;
                    end
                    csr_in_valid_q <= lane_b_csr_accept;
                    if (lane_b_csr_accept) begin
                        csr_in_operand_a_q <= lane_b_operand_a_capture;
                        csr_in_operator_type_q <= lane_b_operator_type;
                        csr_in_raddr_q <= lane_b_uop.csr_raddr;
                        csr_in_waddr_q <= lane_b_uop.csr_waddr;
                        csr_in_op_info_q <= lane_b_uop.csr_op_info;
                        csr_in_sys_info_q <= lane_b_uop.sys_op_info;
                    end
                    mul_in_valid_q <= lane_b_mul_accept;
                    if (lane_b_mul_accept) begin
                        mul_in_operand_a_q <= lane_b_operand_a_capture;
                        mul_in_operand_b_q <= lane_b_operand_b_capture;
                        mul_in_operator_q <= lane_b_operator_info;
                        mul_in_operator_type_q <= lane_b_operator_type;
                    end
                    dual_alu_valid_q <= lane_b_alu_accept;
                    dual_bit_valid_q <= lane_b_bit_accept;
                    dual_bru_valid_q <= lane_b_bru_accept;
                    if (lane_b_accept)
                        dual_meta_q <= dual_meta_d;
                    if (lane_b_alu_accept)
                        dual_alu_payload_q <= dual_alu_payload_d;
                    if (lane_b_bit_accept)
                        dual_bit_payload_q <= dual_bit_payload_d;
                    if (lane_b_bru_accept)
                        dual_bru_payload_q <= dual_bru_payload_d;
        end
    end

	assign illegal_instr_o = illegal_instr_q;
	assign alu_in_valid_o = alu_in_valid_q;
	assign alu_in_operand_a_o = alu_in_operand_a_q;
	assign alu_in_operand_b_o = alu_in_operand_b_q;
    assign alu_in_operator_o = alu_in_operator_q;
    assign alu_in_operator_type_o = alu_in_operator_type_q;
    assign alu_in_rd_wen_o = alu_in_rd_wen_q;
    assign alu_in_rd_addr_o = alu_in_rd_addr_q;
    assign alu_in_producer_id_o = alu_in_producer_id_q;
	assign lane_a_pc_o = lane_a_pc_q;
    assign agu_in_valid_o = agu_in_valid_q;
	assign agu_in_operand_a_o = agu_in_operand_a_q;
    assign agu_in_operand_b_o = agu_in_operand_b_q;
	assign agu_in_req_o = agu_in_req_q;
	assign agu_in_store_data_o = agu_in_req_q.store_data;
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
    input  wire                         dispatch0_src0_ready_i,
    input  wire                         dispatch0_src1_ready_i,
    input  wire                         dispatch1_src0_ready_i,
    input  wire                         dispatch1_src1_ready_i,
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
    input  wire                         dispatch0_early_writes_i,
    input  wire                         dispatch1_early_writes_i,
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
    output wire                         serial_o,
    output wire                         early_writes_o
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
    reg early_writes_q;
    wire [COMPLETION_LANES-1:0] current_src0_completion_hit;
    wire [COMPLETION_LANES-1:0] current_src1_completion_hit;
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
            early_writes_q <= 1'b0;
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
                early_writes_q <= 1'b0;
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
                src0_ready_q <= dispatch0_src0_ready_i;
                src1_ready_q <= dispatch0_src1_ready_i;
                order_mask_q <= dispatch0_order_mask_i;
                memory_q <= dispatch0_memory_i;
                store_q <= dispatch0_store_i;
                mul_q <= dispatch0_mul_i;
                divrem_q <= dispatch0_divrem_i;
                serial_q <= dispatch0_serial_i;
                early_writes_q <= dispatch0_early_writes_i;
            end else if (dispatch1_write_i) begin
                uop_q <= dispatch1_uop_i;
                valid_q <= 1'b1;
                src0_ready_q <= dispatch1_src0_ready_i;
                src1_ready_q <= dispatch1_src1_ready_i;
                order_mask_q <= dispatch1_order_mask_i;
                memory_q <= dispatch1_memory_i;
                store_q <= dispatch1_store_i;
                mul_q <= dispatch1_mul_i;
                divrem_q <= dispatch1_divrem_i;
                serial_q <= dispatch1_serial_i;
                early_writes_q <= dispatch1_early_writes_i;
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
    assign early_writes_o = early_writes_q;
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

    // Keep the early-return data cone separate from min/max and other
    // expensive bitmanip operations. The matching token is captured in
    // Issue, and this value is selected only at the consumer FU input.
    wire early_lite_bitmanip_op =
        bit_valid_i &&
        (bit_operator[OP_B_SH1ADD] | bit_operator[OP_B_SH2ADD] |
         bit_operator[OP_B_SH3ADD] | bit_operator[OP_B_PACK] |
         bit_operator[OP_B_PACKH]  | bit_operator[OP_B_REV8] |
         bit_operator[OP_B_SEXT_B] | bit_operator[OP_B_SEXT_H] |
         bit_operator[OP_B_ZEXT_H]);
    wire [REGS_DATA_WIDTH-1:0] early_lite_bitmanip_result =
        fast_b_shadd_result | early_b_pack_result | fast_b_extend_result;
    assign early_bypass_data_o = early_lite_bitmanip_op ?
        early_lite_bitmanip_result :
        alu_valid_i ? alu_result :
        bru_valid_i ? branch_link_result : '0;

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
