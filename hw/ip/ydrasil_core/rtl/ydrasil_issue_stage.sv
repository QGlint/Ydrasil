// Four-entry, operand-capturing issue window.  The window is the existing
// Issue stage boundary; issue_ex_q below remains the only register before EX.
module ydrasil_issue_stage_legacy
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        stall_id_i,
    input  wire                        bubble_id_i,
    input  wire                        flush_id_i,
    input  ydrasil_issue_pkt_t         dispatch_pkt_i,
    input  ydrasil_issue_pkt_t         dispatch_pkt1_i,
    input  ydrasil_rob_source_state_t  dispatch_src0_state_i,
    input  ydrasil_rob_source_state_t  dispatch_src1_state_i,
    input  ydrasil_rob_source_state_t  dispatch_src2_state_i,
    input  ydrasil_rob_source_state_t  dispatch_src3_state_i,
    input  wire                        dispatch_accept_i,
    input  wire                        dispatch_accept1_i,
    input  ydrasil_completion_bus_t    completion_bus_i,
    input  ydrasil_lsu_status_pkt_t    lsu_status_i,
    input  producer_id_t               rob_head_tag_i,
    output ydrasil_issue_pkt_t         issue_pkt_o,
    output ydrasil_issue_pkt_t         issue_pkt1_o,
    output wire                        issue_ready_o,
    output wire                        issue_dispatch_two_ready_o,
    output wire                        issue_consume_two_o,
    output wire                        issue_slot1_replay_o,
    output wire                        issue_fence_o,
    output producer_id_t               issue_fence_tag_o,
    output wire [INST_ADDR_WIDTH-1:0] issue_fence_next_pc_o,
    output wire                        scoreboard_stall_o,
    output wire                        scoreboard_stall1_o,
    output wire                        lsu_struct_stall_o,
    output wire                        lsu_struct_stall1_o,
    output wire                        serialize_stall_o,
    output wire                        src0_wait_o,
    output wire                        src1_wait_o,
    output wire                        src2_wait_o,
    output wire                        src3_wait_o,
    output ydrasil_issue_ex_pkt_t     issue_ex_o,
    output wire [4:0]                 rf_addr_rs1_o,
    output wire [4:0]                 rf_addr_rs2_o,
    output wire [4:0]                 rf_addr_rs3_o,
    output wire [4:0]                 rf_addr_rs4_o,
    input  wire [DATA_WIDTH-1:0]      rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]      rf_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]      rf_rdata_rs3_i,
    input  wire [DATA_WIDTH-1:0]      rf_rdata_rs4_i,
    output wire [4:0]                 dispatch_rf_addr_rs1_o,
    output wire [4:0]                 dispatch_rf_addr_rs2_o,
    output wire [4:0]                 dispatch_rf_addr_rs3_o,
    output wire [4:0]                 dispatch_rf_addr_rs4_o,
    input  wire [DATA_WIDTH-1:0]      dispatch_rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]      dispatch_rf_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]      dispatch_rf_rdata_rs3_i,
    input  wire [DATA_WIDTH-1:0]      dispatch_rf_rdata_rs4_i,
    output wire [4:0]                 fpr_addr_rs1_o,
    output wire [4:0]                 fpr_addr_rs2_o,
    output wire [4:0]                 fpr_addr_rs3_o,
    input  wire [DATA_WIDTH-1:0]      fpr_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]      fpr_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]      fpr_rdata_rs3_i
);
    localparam int N = 4;

    // Completion is an event from EX/WB, not a same-cycle issue select input.
    // Registering it here removes the EX -> completion -> wakeup -> issue_ex
    // combinational feedback loop.  The station still wakes in one issue
    // cycle; only the unsafe same-cycle visibility is removed.
    ydrasil_completion_bus_t completion_bus_q;
    integer completion_lane_i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_id_i) begin
            for (completion_lane_i = 0;
                 completion_lane_i < COMPLETION_LANES;
                 completion_lane_i = completion_lane_i + 1)
                completion_bus_q[completion_lane_i] <= '0;
        end else begin
            for (completion_lane_i = 0;
                 completion_lane_i < COMPLETION_LANES;
                 completion_lane_i = completion_lane_i + 1)
                completion_bus_q[completion_lane_i] <=
                    completion_bus_i[completion_lane_i];
        end
    end

    function automatic logic completion_hit(
        input ydrasil_source_desc_t src, input integer lane
    );
        completion_hit = src.used && src.tag_valid &&
            completion_bus_q[lane].valid &&
            completion_bus_q[lane].producer_tracked &&
            (completion_bus_q[lane].producer_id == src.producer_tag);
    endfunction

    function automatic logic typed_completion_hit(
        input ydrasil_source_desc_t src
    );
        case (src.producer_class)
            RESULT_LSU: typed_completion_hit = completion_hit(src, COMPLETION_LSU);
            RESULT_MDU: typed_completion_hit = completion_hit(src, COMPLETION_MUL);
            default: typed_completion_hit = completion_hit(src, COMPLETION_ALU) ||
                completion_hit(src, COMPLETION_DUAL_ALU);
        endcase
    endfunction

    function automatic logic completion_current_hit(
        input ydrasil_source_desc_t src, input integer lane
    );
        completion_current_hit = src.used && src.tag_valid &&
            completion_bus_i[lane].valid &&
            completion_bus_i[lane].producer_tracked &&
            (completion_bus_i[lane].producer_id == src.producer_tag);
    endfunction

    function automatic logic typed_completion_current_hit(
        input ydrasil_source_desc_t src
    );
        case (src.producer_class)
            RESULT_LSU: typed_completion_current_hit =
                completion_current_hit(src, COMPLETION_LSU);
            RESULT_MDU: typed_completion_current_hit =
                completion_current_hit(src, COMPLETION_MUL);
            default: typed_completion_current_hit =
                completion_current_hit(src, COMPLETION_ALU) ||
                completion_current_hit(src, COMPLETION_DUAL_ALU);
        endcase
    endfunction

    function automatic [DATA_WIDTH-1:0] typed_completion_current_data(
        input ydrasil_source_desc_t src
    );
        case (src.producer_class)
            RESULT_LSU: typed_completion_current_data =
                completion_bus_i[COMPLETION_LSU].data;
            RESULT_MDU: typed_completion_current_data =
                completion_bus_i[COMPLETION_MUL].data;
            default: typed_completion_current_data =
                completion_current_hit(src, COMPLETION_ALU) ?
                    completion_bus_i[COMPLETION_ALU].data :
                    completion_bus_i[COMPLETION_DUAL_ALU].data;
        endcase
    endfunction

    function automatic [DATA_WIDTH-1:0] typed_completion_data(
        input ydrasil_source_desc_t src
    );
        case (src.producer_class)
            RESULT_LSU: typed_completion_data = completion_bus_q[COMPLETION_LSU].data;
            RESULT_MDU: typed_completion_data = completion_bus_q[COMPLETION_MUL].data;
            default: typed_completion_data = completion_hit(src, COMPLETION_ALU) ?
                completion_bus_q[COMPLETION_ALU].data :
                completion_bus_q[COMPLETION_DUAL_ALU].data;
        endcase
    endfunction

    // A deliberately narrow local bypass is retained for single-cycle ALU
    // producers.  LSU/MUL/FPU completion still uses completion_bus_q and can
    // never create a wide EX -> window -> EX feedback path.
    function automatic logic fast_alu_consumer(input ydrasil_issue_pkt_t p);
        fast_alu_consumer = p.valid &&
            !p.decode.resources[RESOURCE_MULDIV] &&
            !p.decode.resources[RESOURCE_SERIAL] &&
            !p.decode.operator_type[OPERATOR_TYPE_FPU];
    endfunction

    function automatic logic fast_alu_completion_hit(
        input ydrasil_source_desc_t src
    );
        fast_alu_completion_hit = src.used && src.tag_valid &&
            ((completion_bus_i[COMPLETION_ALU].valid &&
              completion_bus_i[COMPLETION_ALU].producer_tracked &&
              completion_bus_i[COMPLETION_ALU].producer_id == src.producer_tag) ||
             (completion_bus_i[COMPLETION_DUAL_ALU].valid &&
              completion_bus_i[COMPLETION_DUAL_ALU].producer_tracked &&
              completion_bus_i[COMPLETION_DUAL_ALU].producer_id == src.producer_tag));
    endfunction

    function automatic [DATA_WIDTH-1:0] fast_alu_completion_data(
        input ydrasil_source_desc_t src
    );
        fast_alu_completion_data =
            (completion_bus_i[COMPLETION_ALU].valid &&
             completion_bus_i[COMPLETION_ALU].producer_tracked &&
             completion_bus_i[COMPLETION_ALU].producer_id == src.producer_tag) ?
                completion_bus_i[COMPLETION_ALU].data :
                completion_bus_i[COMPLETION_DUAL_ALU].data;
    endfunction

    function automatic logic init_ready(
        input ydrasil_source_desc_t src,
        input ydrasil_rob_source_state_t state
    );
        // A valid tag with state.live=0 is the intra-bundle producer allocated
        // by slot0, which is not visible in the ROB until this clock edge.
        // It must remain asleep rather than being mistaken for an architectural
        // register with no pending producer.
        init_ready = !src.used || !src.tag_valid ||
            (state.live && state.done) || typed_completion_hit(src) ||
            typed_completion_current_hit(src);
    endfunction

    function automatic [DATA_WIDTH-1:0] init_value(
        input ydrasil_source_desc_t src,
        input ydrasil_rob_source_state_t state,
        input logic [DATA_WIDTH-1:0] rf_value
    );
        init_value = rf_value;
        if (src.used && src.tag_valid && state.live && state.done)
            init_value = state.result;
        if (src.used && src.tag_valid && typed_completion_hit(src))
            init_value = typed_completion_data(src);
        if (src.used && src.tag_valid && typed_completion_current_hit(src))
            init_value = typed_completion_current_data(src);
    endfunction

    function automatic logic a_capable(input ydrasil_issue_pkt_t p);
        a_capable = !p.decode.resources[RESOURCE_BRU] &&
            !p.decode.resources[RESOURCE_LSU];
    endfunction

    function automatic logic b_capable(input ydrasil_issue_pkt_t p);
        b_capable = !p.decode.resources[RESOURCE_MULDIV] &&
            !p.decode.resources[RESOURCE_FULL_BITMANIP] &&
            !p.decode.resources[RESOURCE_SERIAL] &&
            !p.decode.operator_type[OPERATOR_TYPE_FPU];
    endfunction

    function automatic logic raw_dep(
        input ydrasil_issue_pkt_t older,
        input ydrasil_issue_pkt_t younger
    );
        raw_dep = older.dst.writes_gpr && younger.valid &&
            ((younger.src0.used && younger.src0.tag_valid &&
              older.dst.rob_tag == younger.src0.producer_tag) ||
             (younger.src1.used && younger.src1.tag_valid &&
              older.dst.rob_tag == younger.src1.producer_tag));
    endfunction

    function automatic logic pair_compatible(
        input ydrasil_issue_pkt_t older,
        input ydrasil_issue_pkt_t younger
    );
        logic resource_conflict;
        logic branch_memory;
        resource_conflict = |(older.decode.resources & younger.decode.resources &
            RESOURCE_EXCLUSIVE_MASK);
        branch_memory = (older.decode.resources[RESOURCE_BRU] &&
            younger.decode.resources[RESOURCE_LSU]) ||
            (younger.decode.resources[RESOURCE_BRU] &&
             older.decode.resources[RESOURCE_LSU]);
        pair_compatible = older.valid && younger.valid &&
            !raw_dep(older, younger) && !resource_conflict &&
            !older.ctrl.serialize_before && !younger.ctrl.serialize_before &&
            !branch_memory && (a_capable(older) && b_capable(younger) ||
                               b_capable(older) && a_capable(younger));
    endfunction

    function automatic logic pair_swap(
        input ydrasil_issue_pkt_t older,
        input ydrasil_issue_pkt_t younger
    );
        pair_swap = !(a_capable(older) && b_capable(younger));
    endfunction

    // Only side-effect-free operations may cross an older unissued entry.
    // Branches may be crossed by such operations because the producer/branch
    // recovery mask discards them on a redirect.
    function automatic logic spec_safe(input ydrasil_issue_pkt_t p);
        spec_safe = p.valid && !p.memory_op &&
            !p.decode.resources[RESOURCE_BRU] &&
            !p.decode.resources[RESOURCE_SERIAL] &&
            !p.decode.operator_type[OPERATOR_TYPE_FPU] &&
            !(p.decode.operator_type[OPERATOR_TYPE_MUL] &&
              (p.decode.operator_info[OP_MUL_DIV] ||
               p.decode.operator_info[OP_MUL_DIVU] ||
               p.decode.operator_info[OP_MUL_REM] ||
               p.decode.operator_info[OP_MUL_REMU]));
    endfunction

    function automatic logic cross_allowed(
        input ydrasil_issue_pkt_t older,
        input ydrasil_issue_pkt_t younger
    );
        cross_allowed = spec_safe(younger) && !older.ctrl.serialize_before &&
            !raw_dep(older, younger);
    endfunction

    function automatic logic runtime_legal(input ydrasil_issue_pkt_t p);
        runtime_legal = !(p.memory_op && lsu_status_i.busy);
    endfunction

    // The window stores only the execution station payload.  ctrl is derived
    // from decode/source/destination fields at the output boundary instead of
    // being replicated in every slot.  This removes the four full packet
    // register banks from the issue critical cone.
    typedef struct packed {
        logic                         valid;
        logic                         memory_op;
        logic [1:0]                   lane_mask;
        ydrasil_source_desc_t         src0;
        ydrasil_source_desc_t         src1;
        ydrasil_dest_desc_t           dst;
        logic [INST_ADDR_WIDTH-1:0]   target;
        logic [INST_ADDR_WIDTH-1:0]   next_pc;
        ydrasil_decode_pkt_t          decode;
    } issue_station_t;
    issue_station_t entry_station_q [0:N-1];
    issue_station_t entry_station_d [0:N-1];
    // Combinational views exist only at the selected/output boundary and are
    // not stored per slot.
    ydrasil_issue_pkt_t entry_pkt_q [0:N-1];

    function automatic issue_station_t station_from_pkt(
        input ydrasil_issue_pkt_t p
    );
        station_from_pkt.valid = p.valid;
        station_from_pkt.memory_op = p.memory_op;
        station_from_pkt.lane_mask = p.lane_mask;
        station_from_pkt.src0 = p.src0;
        station_from_pkt.src1 = p.src1;
        station_from_pkt.dst = p.dst;
        station_from_pkt.target = p.target;
        station_from_pkt.next_pc = p.next_pc;
        station_from_pkt.decode = p.decode;
    endfunction

    function automatic ydrasil_issue_pkt_t pkt_from_station(
        input issue_station_t s
    );
        ydrasil_issue_pkt_t p;
        p = '0;
        p.valid = s.valid;
        p.memory_op = s.memory_op;
        p.lane_mask = s.lane_mask;
        p.src0 = s.src0;
        p.src1 = s.src1;
        p.dst = s.dst;
        p.target = s.target;
        p.next_pc = s.next_pc;
        p.decode = s.decode;
        p.ctrl.valid = s.valid;
        p.ctrl.rs1_addr = s.decode.rs1_addr;
        p.ctrl.rs2_addr = s.decode.rs2_addr;
        p.ctrl.rd_addr = s.dst.rd_addr;
        p.ctrl.rs1_ren = s.src0.used;
        p.ctrl.rs2_ren = s.src1.used;
        p.ctrl.rd_wen = s.dst.writes_gpr;
        p.ctrl.lsu_req = s.memory_op;
        p.ctrl.store_req = s.decode.operator_type[OPERATOR_TYPE_STORE];
        p.ctrl.serialize_before = s.decode.operator_type[OPERATOR_TYPE_CSR] ||
            s.decode.operator_type[OPERATOR_TYPE_SYS] || s.decode.fence_i;
        p.ctrl.checkpoint_req = s.decode.operator_type[OPERATOR_TYPE_BJP];
        pkt_from_station = p;
    endfunction

    integer station_view_i;
    always_comb begin
        for (station_view_i = 0; station_view_i < N;
             station_view_i = station_view_i + 1)
            entry_pkt_q[station_view_i] =
                pkt_from_station(entry_station_q[station_view_i]);
    end
    reg [N-1:0] entry_valid_q, entry_valid_d;
    reg [1:0] entry_ready_q [0:N-1];
    reg [1:0] entry_ready_d [0:N-1];
    reg [DATA_WIDTH-1:0] entry_value_q [0:N-1][0:1];
    reg [DATA_WIDTH-1:0] entry_value_d [0:N-1][0:1];
    reg [N-1:0] older_q [0:N-1];
    reg [N-1:0] older_d [0:N-1];
    reg [N-1:0] pair_q [0:N-1];
    reg [N-1:0] pair_d [0:N-1];
    reg [N-1:0] swap_q [0:N-1];
    reg [N-1:0] swap_d [0:N-1];
    reg [N-1:0] cross_q [0:N-1];
    reg [N-1:0] cross_d [0:N-1];
    // A control instruction is removed from the window when it is selected,
    // while BRU produces its redirect one cycle later.  Retain that fact for
    // exactly the intervening cycle so younger side-effecting operations
    // cannot enter LSU/CSR before the control decision is known.
    reg control_barrier_q;
    // Serial/system instructions need a stricter one-cycle handoff barrier:
    // no younger producer may execute before trap/CSR control takes over.
    reg serial_barrier_q;

    // A selected slot is free for same-cycle dispatch.  This is deliberately
    // derived from the issue decision, not only from the registered valid bit.
    wire [N-1:0] free_vec = ~entry_valid_q | selected_remove;
    reg [N-1:0] alloc_sel0, alloc_sel1;
    integer ai;
    always_comb begin
        alloc_sel0 = '0;
        alloc_sel1 = '0;
        if (dispatch_accept_i && dispatch_pkt_i.valid) begin
            for (ai = 0; ai < N; ai = ai + 1)
                if ((!entry_valid_q[ai] || selected_remove[ai]) &&
                    (alloc_sel0 == '0))
                    alloc_sel0[ai] = 1'b1;
        end
        if (dispatch_accept1_i && dispatch_pkt1_i.valid) begin
            for (ai = 0; ai < N; ai = ai + 1)
                if ((!entry_valid_q[ai] || selected_remove[ai]) &&
                    (alloc_sel0[ai] == 1'b0) &&
                    (alloc_sel1 == '0))
                    alloc_sel1[ai] = 1'b1;
        end
    end

    integer wi;
    reg [N-1:0] src_ready0_now, src_ready1_now;
    reg [DATA_WIDTH-1:0] src_value0_now [0:N-1];
    reg [DATA_WIDTH-1:0] src_value1_now [0:N-1];
    always_comb begin
        for (wi = 0; wi < N; wi = wi + 1) begin
            src_ready0_now[wi] = entry_ready_q[wi][0] ||
                typed_completion_hit(entry_pkt_q[wi].src0) ||
                (fast_alu_consumer(entry_pkt_q[wi]) &&
                 fast_alu_completion_hit(entry_pkt_q[wi].src0));
            src_ready1_now[wi] = entry_ready_q[wi][1] ||
                typed_completion_hit(entry_pkt_q[wi].src1) ||
                (fast_alu_consumer(entry_pkt_q[wi]) &&
                 fast_alu_completion_hit(entry_pkt_q[wi].src1));
            src_value0_now[wi] = entry_value_q[wi][0];
            src_value1_now[wi] = entry_value_q[wi][1];
            if (typed_completion_hit(entry_pkt_q[wi].src0))
                src_value0_now[wi] = typed_completion_data(entry_pkt_q[wi].src0);
            else if (fast_alu_consumer(entry_pkt_q[wi]) &&
                     fast_alu_completion_hit(entry_pkt_q[wi].src0))
                src_value0_now[wi] = fast_alu_completion_data(entry_pkt_q[wi].src0);
            if (typed_completion_hit(entry_pkt_q[wi].src1))
                src_value1_now[wi] = typed_completion_data(entry_pkt_q[wi].src1);
            else if (fast_alu_consumer(entry_pkt_q[wi]) &&
                     fast_alu_completion_hit(entry_pkt_q[wi].src1))
                src_value1_now[wi] = fast_alu_completion_data(entry_pkt_q[wi].src1);
        end
    end

    reg [N-1:0] eligible0, select0, eligible1, select1;
    reg [N-1:0] hard_block0, hard_block1;
    reg [N-1:0] lane_a_eligible, lane_b_eligible;
    reg [N-1:0] lane_a_pick, lane_b_pick;
    reg independent_pair;
    reg pair_accept;
    integer sel_i, sel_j;
    wire select_enable = !stall_id_i && !bubble_id_i && !flush_id_i;
    always_comb begin
        eligible0 = '0;
        select0 = '0;
        eligible1 = '0;
        select1 = '0;
        hard_block0 = '0;
        hard_block1 = '0;
        lane_a_eligible = '0;
        lane_b_eligible = '0;
        lane_a_pick = '0;
        lane_b_pick = '0;
        independent_pair = 1'b0;
        pair_accept = 1'b0;

        // Candidate 0 is the oldest independently executable station entry.
        // No lane assignment or pair dependency participates in this pass.
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1) begin
            for (sel_j = 0; sel_j < N; sel_j = sel_j + 1) begin
                if (entry_valid_q[sel_j] && older_q[sel_j][sel_i] &&
                    !cross_q[sel_j][sel_i])
                    hard_block0[sel_i] = 1'b1;
            end
            if (entry_valid_q[sel_i] && src_ready0_now[sel_i] && src_ready1_now[sel_i] &&
                !hard_block0[sel_i] &&
                !serial_barrier_q &&
                !(control_barrier_q && !spec_safe(entry_pkt_q[sel_i])) &&
                runtime_legal(entry_pkt_q[sel_i]) &&
                !(entry_pkt_q[sel_i].ctrl.serialize_before &&
                  ((entry_pkt_q[sel_i].dst.rob_tag != rob_head_tag_i) ||
                   !lsu_status_i.idle)))
                eligible0[sel_i] = 1'b1;
        end
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1) begin
            if (eligible0[sel_i]) begin
                select0[sel_i] = 1'b1;
                for (sel_j = 0; sel_j < N; sel_j = sel_j + 1)
                    if (eligible0[sel_j] && older_q[sel_j][sel_i])
                        select0[sel_i] = 1'b0;
            end
        end

        // Candidate 1 is selected from the remaining executable entries.  It
        // has its own ready/runtime/age decision.  Candidate 0 only releases
        // an older-order barrier; pair compatibility is checked afterwards.
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1) begin
            for (sel_j = 0; sel_j < N; sel_j = sel_j + 1) begin
                if (entry_valid_q[sel_j] && older_q[sel_j][sel_i] &&
                    !cross_q[sel_j][sel_i] &&
                    !select0[sel_j])
                    hard_block1[sel_i] = 1'b1;
            end
            eligible1[sel_i] = entry_valid_q[sel_i] &&
                !select0[sel_i] && src_ready0_now[sel_i] && src_ready1_now[sel_i] &&
                !hard_block1[sel_i] &&
                !serial_barrier_q &&
                !(control_barrier_q && !spec_safe(entry_pkt_q[sel_i])) &&
                runtime_legal(entry_pkt_q[sel_i]);
        end
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1) begin
            if (eligible1[sel_i]) begin
                select1[sel_i] = 1'b1;
                for (sel_j = 0; sel_j < N; sel_j = sel_j + 1)
                    if (eligible1[sel_j] && older_q[sel_j][sel_i])
                        select1[sel_i] = 1'b0;
            end
        end

        // Physical lanes choose independently.  The common issue window is
        // only consulted for the final pair legality check; lane B does not
        // consume lane A's operand state or producer id.
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1) begin
            lane_a_eligible[sel_i] = eligible0[sel_i] &&
                a_capable(entry_pkt_q[sel_i]);
            lane_b_eligible[sel_i] = eligible0[sel_i] &&
                b_capable(entry_pkt_q[sel_i]);
        end
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1) begin
            if (lane_a_eligible[sel_i]) begin
                lane_a_pick[sel_i] = 1'b1;
                for (sel_j = 0; sel_j < N; sel_j = sel_j + 1)
                    if (lane_a_eligible[sel_j] && older_q[sel_j][sel_i])
                        lane_a_pick[sel_i] = 1'b0;
            end
            if (lane_b_eligible[sel_i]) begin
                lane_b_pick[sel_i] = 1'b1;
                for (sel_j = 0; sel_j < N; sel_j = sel_j + 1)
                    if (lane_b_eligible[sel_j] && older_q[sel_j][sel_i])
                        lane_b_pick[sel_i] = 1'b0;
            end
        end
        // If both lane classes point at the same entry, choose the next B
        // candidate independently rather than making slot1 a child of slot0.
        lane_b_pick = '0;
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1)
            if (lane_b_eligible[sel_i] && !lane_a_pick[sel_i] &&
                (lane_b_pick == '0)) begin
                lane_b_pick[sel_i] = 1'b1;
                for (sel_j = 0; sel_j < N; sel_j = sel_j + 1)
                    if (lane_b_eligible[sel_j] && !lane_a_pick[sel_j] &&
                        older_q[sel_j][sel_i])
                        lane_b_pick[sel_i] = 1'b0;
            end
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1)
            for (sel_j = 0; sel_j < N; sel_j = sel_j + 1)
                if (lane_a_pick[sel_i] && lane_b_pick[sel_j] &&
                    (pair_compatible(entry_pkt_q[sel_i], entry_pkt_q[sel_j]) ||
                     pair_compatible(entry_pkt_q[sel_j], entry_pkt_q[sel_i])))
                    independent_pair = 1'b1;
        if (independent_pair) begin
            select0 = lane_a_pick;
            select1 = lane_b_pick;
        end

        // The two independently chosen program entries may execute together
        // only when their static resource/RAW relation permits it.  This is a
        // final accept gate; lane B does not inherit lane A's source state.
        for (sel_i = 0; sel_i < N; sel_i = sel_i + 1)
            for (sel_j = 0; sel_j < N; sel_j = sel_j + 1)
                if (select0[sel_i] && select1[sel_j] && pair_q[sel_i][sel_j])
                    pair_accept = 1'b1;
        if (!pair_accept)
            select1 = '0;

        if (!select_enable) begin
            select0 = '0;
            select1 = '0;
        end
    end

    wire selected_valid = |select0;
    wire selected_pair = |select1;
    wire [N-1:0] selected_remove = select0 | select1;
    ydrasil_issue_pkt_t selected_uop0, selected_uop1;
    reg [DATA_WIDTH-1:0] selected_src00, selected_src01;
    reg [DATA_WIDTH-1:0] selected_src10, selected_src11;
    reg selected_ready00, selected_ready01;
    reg selected_ready10, selected_ready11;
    reg [1:0] selected_idx0, selected_idx1;
    reg selected_swap;
    integer chosen_i, chosen_j;
    always_comb begin
        selected_uop0 = '0;
        selected_uop1 = '0;
        selected_src00 = '0;
        selected_src01 = '0;
        selected_src10 = '0;
        selected_src11 = '0;
        selected_ready00 = 1'b0;
        selected_ready01 = 1'b0;
        selected_ready10 = 1'b0;
        selected_ready11 = 1'b0;
        selected_idx0 = '0;
        selected_idx1 = '0;
        selected_swap = 1'b0;
        for (chosen_i = 0; chosen_i < N; chosen_i = chosen_i + 1) begin
            if (select0[chosen_i]) begin
                selected_idx0 = chosen_i[1:0];
                selected_uop0 = entry_pkt_q[chosen_i];
                selected_src00 = src_value0_now[chosen_i];
                selected_src01 = src_value1_now[chosen_i];
                selected_ready00 = src_ready0_now[chosen_i];
                selected_ready01 = src_ready1_now[chosen_i];
            end
            if (select1[chosen_i]) begin
                selected_idx1 = chosen_i[1:0];
                selected_uop1 = entry_pkt_q[chosen_i];
                selected_src10 = src_value0_now[chosen_i];
                selected_src11 = src_value1_now[chosen_i];
                selected_ready10 = src_ready0_now[chosen_i];
                selected_ready11 = src_ready1_now[chosen_i];
            end
        end
        if (!independent_pair)
            for (chosen_i = 0; chosen_i < N; chosen_i = chosen_i + 1)
                for (chosen_j = 0; chosen_j < N; chosen_j = chosen_j + 1)
                    if (select0[chosen_i] && select1[chosen_j])
                        selected_swap = swap_q[chosen_i][chosen_j];
    end

    assign issue_pkt_o = selected_uop0;
    assign issue_pkt1_o = selected_uop1;
    assign issue_ready_o = !flush_id_i && !bubble_id_i &&
        (|free_vec);
    assign issue_dispatch_two_ready_o = !flush_id_i && !bubble_id_i &&
        (free_vec != '0) && ((free_vec & (free_vec - 1'b1)) != '0);
    assign issue_consume_two_o = selected_pair;
    assign issue_slot1_replay_o = 1'b0;
    assign lsu_struct_stall_o = selected_uop0.memory_op && lsu_status_i.busy;
    assign lsu_struct_stall1_o = selected_uop1.memory_op && lsu_status_i.busy;
    assign serialize_stall_o = selected_uop0.ctrl.serialize_before &&
        ((selected_uop0.dst.rob_tag != rob_head_tag_i) || !lsu_status_i.idle);

    // Diagnostics describe the oldest live entry; selection itself may bypass
    // it when it is a dependency-blocked non-serial operation.
    reg [1:0] oldest_idx;
    reg oldest_found;
    integer oldest_i, oldest_j;
    always_comb begin
        oldest_idx = '0;
        oldest_found = 1'b0;
        for (oldest_i = 0; oldest_i < N; oldest_i = oldest_i + 1) begin
            if (entry_valid_q[oldest_i] && !oldest_found) begin
                oldest_found = 1'b1;
                for (oldest_j = 0; oldest_j < N; oldest_j = oldest_j + 1)
                    if (entry_valid_q[oldest_j] && older_q[oldest_j][oldest_i])
                        oldest_found = 1'b0;
                if (oldest_found)
                    oldest_idx = oldest_i[1:0];
            end
        end
    end
    assign scoreboard_stall_o = entry_valid_q[oldest_idx] &&
        (!src_ready0_now[oldest_idx] || !src_ready1_now[oldest_idx]);
    assign scoreboard_stall1_o = selected_pair &&
        (!selected_ready10 || !selected_ready11);
    assign src0_wait_o = entry_valid_q[oldest_idx] &&
        entry_pkt_q[oldest_idx].src0.used && !src_ready0_now[oldest_idx];
    assign src1_wait_o = entry_valid_q[oldest_idx] &&
        entry_pkt_q[oldest_idx].src1.used && !src_ready1_now[oldest_idx];
    assign src2_wait_o = selected_pair && !selected_ready10;
    assign src3_wait_o = selected_pair && !selected_ready11;

    assign rf_addr_rs1_o = selected_uop0.src0.arch_addr;
    assign rf_addr_rs2_o = selected_uop0.src1.arch_addr;
    assign rf_addr_rs3_o = selected_uop1.src0.arch_addr;
    assign rf_addr_rs4_o = selected_uop1.src1.arch_addr;
    assign dispatch_rf_addr_rs1_o = dispatch_pkt_i.src0.arch_addr;
    assign dispatch_rf_addr_rs2_o = dispatch_pkt_i.src1.arch_addr;
    assign dispatch_rf_addr_rs3_o = dispatch_pkt1_i.src0.arch_addr;
    assign dispatch_rf_addr_rs4_o = dispatch_pkt1_i.src1.arch_addr;

    function automatic [DATA_WIDTH-1:0] operand_a_for(
        input ydrasil_issue_pkt_t uop, input logic [DATA_WIDTH-1:0] src0
    );
        operand_a_for = uop.decode.operand_a_pc_sel ? uop.decode.pc :
            uop.decode.operand_a_imm_sel ? uop.decode.imm : src0;
    endfunction
    function automatic [DATA_WIDTH-1:0] operand_b_for(
        input ydrasil_issue_pkt_t uop, input logic [DATA_WIDTH-1:0] src1
    );
        operand_b_for = uop.decode.operand_b_jump_sel ? 32'd4 :
            uop.decode.operand_b_rs_sel ? src1 : uop.decode.imm;
    endfunction

    ydrasil_issue_pkt_t lane_a_uop, lane_b_uop;
    reg lane_a_valid, lane_b_valid;
    reg [DATA_WIDTH-1:0] lane_a_src0, lane_a_src1;
    reg [DATA_WIDTH-1:0] lane_b_src0, lane_b_src1;
    always_comb begin
        lane_a_uop = selected_uop0;
        lane_b_uop = selected_uop1;
        lane_a_src0 = selected_src00;
        lane_a_src1 = selected_src01;
        lane_b_src0 = selected_src10;
        lane_b_src1 = selected_src11;
        lane_a_valid = selected_valid;
        lane_b_valid = selected_pair;
        if (selected_pair) begin
            lane_b_valid = 1'b1;
            if (selected_swap) begin
                lane_a_uop = selected_uop1;
                lane_b_uop = selected_uop0;
                lane_a_src0 = selected_src10;
                lane_a_src1 = selected_src11;
                lane_b_src0 = selected_src00;
                lane_b_src1 = selected_src01;
            end
        end else if (selected_valid && !a_capable(selected_uop0)) begin
            lane_a_valid = 1'b0;
            lane_b_valid = 1'b1;
            lane_b_uop = selected_uop0;
            lane_b_src0 = selected_src00;
            lane_b_src1 = selected_src01;
        end
    end

    ydrasil_issue_ex_pkt_t issue_ex_d, issue_ex_q;
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
        if (lane_a_uop.decode.fence_i) begin
            issue_ex_d.valid = 1'b0;
            issue_ex_d.producer_tracked = 1'b0;
        end
        issue_ex_d.rd_wen = lane_a_valid && lane_a_uop.dst.writes_gpr;
        issue_ex_d.rd_addr = lane_a_uop.dst.rd_addr;
        issue_ex_d.producer_id = lane_a_uop.dst.rob_tag;
        issue_ex_d.producer_tracked = lane_a_valid;
        issue_ex_d.lsu_req.valid = lane_a_valid && lane_a_uop.memory_op;
        issue_ex_d.lsu_req.is_load = lane_a_uop.decode.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.is_store = lane_a_uop.decode.operator_type[OPERATOR_TYPE_STORE];
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
        if (!select_enable)
            issue_ex_d = '0;
    end

    assign rf_addr_rs1_o = selected_uop0.src0.arch_addr;
    assign rf_addr_rs2_o = selected_uop0.src1.arch_addr;
    assign rf_addr_rs3_o = selected_uop1.src0.arch_addr;
    assign rf_addr_rs4_o = selected_uop1.src1.arch_addr;
    assign fpr_addr_rs1_o = lane_a_uop.decode.fp_rs1_addr;
    assign fpr_addr_rs2_o = lane_a_uop.decode.fp_rs2_addr;
    assign fpr_addr_rs3_o = lane_a_uop.decode.fp_rs3_addr;

    reg issue_fence_q;
    producer_id_t issue_fence_tag_q;
    reg [INST_ADDR_WIDTH-1:0] issue_fence_next_pc_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_id_i) begin
            issue_fence_q <= 1'b0;
            issue_fence_tag_q <= '0;
            issue_fence_next_pc_q <= '0;
        end else begin
            issue_fence_q <= selected_valid && select_enable &&
                selected_uop0.decode.fence_i;
            if (selected_valid && select_enable && selected_uop0.decode.fence_i) begin
                issue_fence_tag_q <= selected_uop0.dst.rob_tag;
                issue_fence_next_pc_q <= selected_uop0.next_pc;
            end
        end
    end
    assign issue_fence_o = issue_fence_q;
    assign issue_fence_tag_o = issue_fence_tag_q;
    assign issue_fence_next_pc_o = issue_fence_next_pc_q;

    integer di, dj;
    always_comb begin
        entry_valid_d = entry_valid_q;
        for (di = 0; di < N; di = di + 1) begin
            entry_station_d[di] = entry_station_q[di];
            entry_ready_d[di] = entry_ready_q[di];
            entry_value_d[di][0] = entry_value_q[di][0];
            entry_value_d[di][1] = entry_value_q[di][1];
            older_d[di] = older_q[di];
            pair_d[di] = pair_q[di];
            swap_d[di] = swap_q[di];
            cross_d[di] = cross_q[di];
            if (entry_valid_q[di]) begin
                if (typed_completion_hit(entry_pkt_q[di].src0)) begin
                    entry_ready_d[di][0] = 1'b1;
                    entry_value_d[di][0] = typed_completion_data(entry_pkt_q[di].src0);
                end
                if (typed_completion_hit(entry_pkt_q[di].src1)) begin
                    entry_ready_d[di][1] = 1'b1;
                    entry_value_d[di][1] = typed_completion_data(entry_pkt_q[di].src1);
                end
            end
            if (selected_remove[di]) begin
                entry_valid_d[di] = 1'b0;
                older_d[di] = '0;
                pair_d[di] = '0;
                swap_d[di] = '0;
                cross_d[di] = '0;
            end
            for (dj = 0; dj < N; dj = dj + 1)
                if (selected_remove[di] || selected_remove[dj]) begin
                    older_d[di][dj] = 1'b0;
                    pair_d[di][dj] = 1'b0;
                    swap_d[di][dj] = 1'b0;
                    cross_d[di][dj] = 1'b0;
                end
        end
        for (di = 0; di < N; di = di + 1) begin
            if (alloc_sel0[di]) begin
                entry_valid_d[di] = 1'b1;
                entry_station_d[di] = station_from_pkt(dispatch_pkt_i);
                entry_ready_d[di][0] = init_ready(dispatch_pkt_i.src0, dispatch_src0_state_i);
                entry_ready_d[di][1] = init_ready(dispatch_pkt_i.src1, dispatch_src1_state_i);
                entry_value_d[di][0] = init_value(dispatch_pkt_i.src0, dispatch_src0_state_i, dispatch_rf_rdata_rs1_i);
                entry_value_d[di][1] = init_value(dispatch_pkt_i.src1, dispatch_src1_state_i, dispatch_rf_rdata_rs2_i);
            end
            if (alloc_sel1[di]) begin
                entry_valid_d[di] = 1'b1;
                entry_station_d[di] = station_from_pkt(dispatch_pkt1_i);
                entry_ready_d[di][0] = init_ready(dispatch_pkt1_i.src0, dispatch_src2_state_i);
                entry_ready_d[di][1] = init_ready(dispatch_pkt1_i.src1, dispatch_src3_state_i);
                entry_value_d[di][0] = init_value(dispatch_pkt1_i.src0, dispatch_src2_state_i, dispatch_rf_rdata_rs3_i);
                entry_value_d[di][1] = init_value(dispatch_pkt1_i.src1, dispatch_src3_state_i, dispatch_rf_rdata_rs4_i);
            end
        end
        for (di = 0; di < N; di = di + 1) begin
            for (dj = 0; dj < N; dj = dj + 1) begin
                if (entry_valid_q[di] && !selected_remove[di] && alloc_sel0[dj]) begin
                    older_d[di][dj] = 1'b1;
                    pair_d[di][dj] = pair_compatible(entry_pkt_q[di], dispatch_pkt_i);
                    swap_d[di][dj] = pair_swap(entry_pkt_q[di], dispatch_pkt_i);
                    cross_d[di][dj] = cross_allowed(entry_pkt_q[di], dispatch_pkt_i);
                end
                if (entry_valid_q[di] && !selected_remove[di] && alloc_sel1[dj]) begin
                    older_d[di][dj] = 1'b1;
                    pair_d[di][dj] = pair_compatible(entry_pkt_q[di], dispatch_pkt1_i);
                    swap_d[di][dj] = pair_swap(entry_pkt_q[di], dispatch_pkt1_i);
                    cross_d[di][dj] = cross_allowed(entry_pkt_q[di], dispatch_pkt1_i);
                end
            end
        end
        for (di = 0; di < N; di = di + 1)
            for (dj = 0; dj < N; dj = dj + 1)
                if (alloc_sel0[di] && alloc_sel1[dj]) begin
                    older_d[di][dj] = 1'b1;
                    pair_d[di][dj] = pair_compatible(dispatch_pkt_i, dispatch_pkt1_i);
                    swap_d[di][dj] = pair_swap(dispatch_pkt_i, dispatch_pkt1_i);
                    cross_d[di][dj] = cross_allowed(dispatch_pkt_i, dispatch_pkt1_i);
                end
    end

    integer qi;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_id_i) begin
            entry_valid_q <= '0;
            for (qi = 0; qi < N; qi = qi + 1) begin
                entry_station_q[qi] <= '0;
                entry_ready_q[qi] <= '0;
                entry_value_q[qi][0] <= '0;
                entry_value_q[qi][1] <= '0;
                older_q[qi] <= '0;
                pair_q[qi] <= '0;
                swap_q[qi] <= '0;
                cross_q[qi] <= '0;
            end
            control_barrier_q <= 1'b0;
            serial_barrier_q <= 1'b0;
        end else begin
            entry_valid_q <= entry_valid_d;
            for (qi = 0; qi < N; qi = qi + 1) begin
                entry_station_q[qi] <= entry_station_d[qi];
                entry_ready_q[qi] <= entry_ready_d[qi];
                entry_value_q[qi][0] <= entry_value_d[qi][0];
                entry_value_q[qi][1] <= entry_value_d[qi][1];
                older_q[qi] <= older_d[qi];
                pair_q[qi] <= pair_d[qi];
                swap_q[qi] <= swap_d[qi];
                cross_q[qi] <= cross_d[qi];
            end
            control_barrier_q <= select_enable && selected_valid &&
                (selected_uop0.decode.resources[RESOURCE_BRU] ||
                 (selected_pair && selected_uop1.decode.resources[RESOURCE_BRU]));
            serial_barrier_q <= select_enable && selected_valid &&
                (selected_uop0.ctrl.serialize_before ||
                 (selected_pair && selected_uop1.ctrl.serialize_before));
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || flush_id_i)
            issue_ex_q <= '0;
        else if (!stall_id_i)
            issue_ex_q <= bubble_id_i ? '0 : issue_ex_d;
    end
    assign issue_ex_o = issue_ex_q;

`ifndef SYNTHESIS
    wire issue_valid_ff = selected_valid;
    wire id_advance = selected_valid && select_enable;
    wire [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff =
        selected_uop0.decode.operator_type;
    wire rs1_completion_fwd = typed_completion_hit(selected_uop0.src0);
    wire rs2_completion_fwd = typed_completion_hit(selected_uop0.src1);
    function automatic logic completion_input_hit(
        input ydrasil_source_desc_t src, input integer lane
    );
        completion_input_hit = src.used && src.tag_valid &&
            completion_bus_i[lane].valid &&
            completion_bus_i[lane].producer_tracked &&
            (completion_bus_i[lane].producer_id == src.producer_tag);
    endfunction
    function automatic logic typed_completion_input_hit(
        input ydrasil_source_desc_t src
    );
        case (src.producer_class)
            RESULT_LSU: typed_completion_input_hit =
                completion_input_hit(src, COMPLETION_LSU);
            RESULT_MDU: typed_completion_input_hit =
                completion_input_hit(src, COMPLETION_MUL);
            default: typed_completion_input_hit =
                completion_input_hit(src, COMPLETION_ALU) ||
                completion_input_hit(src, COMPLETION_DUAL_ALU);
        endcase
    endfunction
    reg completion_direct_event;
    reg completion_registered_event;
    integer completion_obs_i;
    always_comb begin
        completion_direct_event = 1'b0;
        completion_registered_event = 1'b0;
        for (completion_obs_i = 0; completion_obs_i < N;
             completion_obs_i = completion_obs_i + 1) begin
            if (entry_valid_q[completion_obs_i]) begin
                completion_direct_event = completion_direct_event ||
                    typed_completion_input_hit(entry_pkt_q[completion_obs_i].src0) ||
                    typed_completion_input_hit(entry_pkt_q[completion_obs_i].src1);
                completion_registered_event = completion_registered_event ||
                    typed_completion_hit(entry_pkt_q[completion_obs_i].src0) ||
                    typed_completion_hit(entry_pkt_q[completion_obs_i].src1);
            end
        end
    end
    wire completion_latency_event = completion_direct_event &&
        !completion_registered_event;
    wire issue_plain_alu_op = issue_operator_type_ff[OPERATOR_TYPE_ALU] &&
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
    wire fast_bitmanip_op = operator_type_i[OPERATOR_TYPE_BITMANIP] &&
        (operator_i[OP_B_SH1ADD] | operator_i[OP_B_SH2ADD] | operator_i[OP_B_SH3ADD] |
         operator_i[OP_B_ANDN]   | operator_i[OP_B_ORN]    | operator_i[OP_B_XNOR]   |
         operator_i[OP_B_MIN]    | operator_i[OP_B_MAX]    | operator_i[OP_B_MINU]   |
         operator_i[OP_B_MAXU]   | operator_i[OP_B_REV8]   | operator_i[OP_B_SEXT_B] |
         operator_i[OP_B_SEXT_H] | operator_i[OP_B_ZEXT_H]);
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
        .id_ex_branch_eq_i(1'b0),
        .id_ex_branch_ge_signed_i(1'b0),
        .id_ex_branch_ge_unsigned_i(1'b0),
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
