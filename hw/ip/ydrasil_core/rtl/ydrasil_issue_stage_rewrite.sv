// Elastic, compact issue stage.
//
// Architectural boundaries:
//   ID/dispatch -> four-entry station -> Issue/EX
//   selection -> registered local-bypass plan -> next-cycle Issue/EX
//   completion -> registered station wakeup -> following-cycle issue
//
// Front-end admission is determined only by registered station/ingress credit.
// A current selection can physically refill a slot from an already accepted
// ingress uop, but it never feeds ID/IF or RAT admission in the same cycle. A
// selected fixed-latency ALU producer may pre-arm an operand bypass for the
// next cycle. The bypass select is stored state; completion data never enters
// station arbitration.
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
    output wire                        issue_dispatch_ready_q_o,
    output wire                        issue_dispatch_two_ready_q_o,
    output wire                        issue_consume_two_o,
    output wire                        issue_slot1_replay_o,
    output wire                        issue_fence_o,
    output producer_id_t               issue_fence_tag_o,
    output wire [INST_ADDR_WIDTH-1:0] issue_fence_next_pc_o,
    output ydrasil_exception_req_pkt_t issue_sys_req_o,
    output wire                         issue_sys_complete_o,
    output producer_id_t               issue_sys_tag_o,
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

    // Station control excludes the duplicated ID-control packet, lane mask,
    // target, and next-PC fields.  Those are derived only after a slot is
    // selected for Issue/EX.
    typedef struct packed {
        logic                         memory_op;
        logic                         can_a;
        logic                         can_b;
        logic                         spec_safe;
        logic                         serial_before;
        logic                         branch;
        ydrasil_source_desc_t         src0;
        ydrasil_source_desc_t         src1;
        ydrasil_dest_desc_t           dst;
        ydrasil_decode_pkt_t          decode;
    } issue_station_t;

    typedef struct packed {
        issue_station_t               station;
        logic                         ready0;
        logic                         ready1;
        logic [DATA_WIDTH-1:0]        value0;
        logic [DATA_WIDTH-1:0]        value1;
    } station_admit_t;

    typedef struct packed {
        station_admit_t                admit;
        logic [31:0]                   age;
    } issue_ingress_t;

    issue_station_t station_q [0:N-1];
    issue_station_t station_d [0:N-1];
    reg [N-1:0] entry_valid_q, entry_valid_d;
    reg [31:0] age_q [0:N-1];
    reg [31:0] age_d [0:N-1];
    reg ready0_q [0:N-1];
    reg ready0_d [0:N-1];
    reg ready1_q [0:N-1];
    reg ready1_d [0:N-1];
    reg [DATA_WIDTH-1:0] value0_q [0:N-1];
    reg [DATA_WIDTH-1:0] value0_d [0:N-1];
    reg [DATA_WIDTH-1:0] value1_q [0:N-1];
    reg [DATA_WIDTH-1:0] value1_d [0:N-1];
    localparam logic [2:0] BYPASS_NONE  = 3'd0;
    localparam logic [2:0] BYPASS_ALU0  = 3'd1;
    localparam logic [2:0] BYPASS_ALU1  = 3'd2;
    localparam logic [2:0] BYPASS_MUL   = 3'd3;
    reg [2:0] bypass0_q [0:N-1];
    reg [2:0] bypass0_d [0:N-1];
    reg [2:0] bypass1_q [0:N-1];
    reg [2:0] bypass1_d [0:N-1];
    reg [31:0] next_age_q, next_age_d;

    // This is an elastic admission buffer, not an extra execute pipeline
    // stage. Its free count is registered and may therefore be reported to ID
    // without creating a select -> ID/RAT -> select feedback chain.
    localparam int INGRESS_N = 2;
    issue_ingress_t ingress_q [0:INGRESS_N-1];
    issue_ingress_t ingress_d [0:INGRESS_N-1];
    reg [INGRESS_N-1:0] ingress_valid_q, ingress_valid_d;
    station_admit_t arrival_admit [0:INGRESS_N+1];
    reg [31:0] arrival_age [0:INGRESS_N+1];
    reg [INGRESS_N+1:0] arrival_valid;

    // This mirrors the fixed four-stage MUL pipeline using only the producer
    // tag.  The selector sees a registered bypass control, never an MDU
    // completion match.  DIV/FPU retain normal registered wakeup semantics.
    typedef struct packed {
        logic         valid;
        producer_id_t tag;
    } mul_wake_plan_t;
    // The issue decision is registered into Issue/EX, then MUL captures it in
    // s0 on the following edge and advances through s1/s2/s3.  The plan's
    // final position is one edge before s3 becomes visible, so it can register
    // the local data-mux control on the same edge that produces s3.
    mul_wake_plan_t mul_wake_plan_q [0:3];

    // A reservation is a one-cycle, lane-0 execution grant for a known
    // integer consumer.  It is created while its producer is selected and is
    // consumed on the producer's EX cycle.  The completion data then crosses
    // only the local operand mux; it never returns through global arbitration.
    typedef struct packed {
        logic       valid;
        logic [1:0] slot;
    } local_reservation_t;
    local_reservation_t local_reservation_q, local_reservation_d;

    reg control_barrier_q, serial_barrier_q;
    producer_id_t rob_head_tag_q;

    function automatic logic completion_hit(
        input ydrasil_source_desc_t src, input integer lane
    );
        completion_hit = src.used && src.tag_valid &&
            completion_bus_i[lane].valid &&
            completion_bus_i[lane].producer_tracked &&
            (completion_bus_i[lane].producer_id == src.producer_tag);
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

    function automatic [DATA_WIDTH-1:0] typed_completion_value(
        input ydrasil_source_desc_t src
    );
        case (src.producer_class)
            RESULT_LSU: typed_completion_value = completion_bus_i[COMPLETION_LSU].data;
            RESULT_MDU: typed_completion_value = completion_bus_i[COMPLETION_MUL].data;
            default: typed_completion_value = completion_hit(src, COMPLETION_ALU) ?
                completion_bus_i[COMPLETION_ALU].data :
                completion_bus_i[COMPLETION_DUAL_ALU].data;
        endcase
    endfunction

    function automatic logic bypassable_alu(input issue_station_t s);
        // Only one-cycle integer results use the local data path.  Branch,
        // load/store, CSR and long-latency results must arrive through the
        // registered completion state.
        bypassable_alu = s.dst.writes_gpr && !s.memory_op && !s.branch &&
            !s.serial_before && !s.decode.operator_type[OPERATOR_TYPE_MUL] &&
            !s.decode.operator_type[OPERATOR_TYPE_FPU];
    endfunction

    function automatic logic bypassable_mul(input issue_station_t s);
        bypassable_mul = s.dst.writes_gpr &&
            s.decode.operator_type[OPERATOR_TYPE_MUL] &&
            (s.decode.operator_info[OP_MUL_MUL] ||
             s.decode.operator_info[OP_MUL_MULH] ||
             s.decode.operator_info[OP_MUL_MULHSU] ||
             s.decode.operator_info[OP_MUL_MULHU]);
    endfunction

    function automatic logic source_matches(
        input ydrasil_source_desc_t src, input issue_station_t producer
    );
        source_matches = src.used && src.tag_valid &&
            (src.producer_class == RESULT_ALU) && producer.dst.writes_gpr &&
            (src.producer_tag == producer.dst.rob_tag);
    endfunction

    function automatic logic source_matches_mul_plan(
        input ydrasil_source_desc_t src,
        input mul_wake_plan_t plan
    );
        source_matches_mul_plan = plan.valid && src.used && src.tag_valid &&
            (src.producer_class == RESULT_MDU) &&
            (src.producer_tag == plan.tag);
    endfunction

    function automatic logic source_from_selected_alu(
        input ydrasil_source_desc_t src,
        input logic selected_a,
        input issue_station_t selected_a_station,
        input logic selected_b,
        input issue_station_t selected_b_station
    );
        source_from_selected_alu =
            (selected_a && bypassable_alu(selected_a_station) &&
             source_matches(src, selected_a_station)) ||
            (selected_b && bypassable_alu(selected_b_station) &&
             source_matches(src, selected_b_station));
    endfunction

    function automatic logic source_ready_after_selected_alu(
        input ydrasil_source_desc_t src,
        input logic ready,
        input logic selected_a,
        input issue_station_t selected_a_station,
        input logic selected_b,
        input issue_station_t selected_b_station
    );
        source_ready_after_selected_alu = !src.used || ready ||
            source_from_selected_alu(src, selected_a, selected_a_station,
                                     selected_b, selected_b_station);
    endfunction

    function automatic logic reservable_alu_consumer(input issue_station_t s);
        // Keep the local forwarding path to a simple integer ALU operation.
        // Branch, AGU, bitmanip and serial consumers retain registered wakeup
        // semantics so their longer execution paths cannot become part of the
        // producer-to-consumer local timing arc.
        reservable_alu_consumer = s.can_a && s.spec_safe &&
            s.decode.operator_type[OPERATOR_TYPE_ALU] &&
            !s.decode.operator_type[OPERATOR_TYPE_BITMANIP];
    endfunction

    function automatic [DATA_WIDTH-1:0] bypass_value(input logic [2:0] sel);
        case (sel)
            BYPASS_ALU0: bypass_value = completion_bus_i[COMPLETION_ALU].data;
            BYPASS_ALU1: bypass_value = completion_bus_i[COMPLETION_DUAL_ALU].data;
            BYPASS_MUL:  bypass_value = completion_bus_i[COMPLETION_MUL].data;
            default:     bypass_value = '0;
        endcase
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

    function automatic logic spec_safe(input ydrasil_issue_pkt_t p);
        spec_safe = p.valid && !p.memory_op &&
            !p.decode.resources[RESOURCE_BRU] &&
            !p.ctrl.serialize_before &&
            !p.decode.operator_type[OPERATOR_TYPE_FPU] &&
            !(p.decode.operator_type[OPERATOR_TYPE_MUL] &&
              (p.decode.operator_info[OP_MUL_DIV] ||
               p.decode.operator_info[OP_MUL_DIVU] ||
               p.decode.operator_info[OP_MUL_REM] ||
               p.decode.operator_info[OP_MUL_REMU]));
    endfunction

    function automatic issue_station_t station_from_pkt(
        input ydrasil_issue_pkt_t p
    );
        issue_station_t s;
        s = '0;
        s.memory_op = p.memory_op;
        s.can_a = a_capable(p);
        s.can_b = b_capable(p);
        s.spec_safe = spec_safe(p);
        s.serial_before = p.ctrl.serialize_before;
        s.branch = p.decode.resources[RESOURCE_BRU];
        s.src0 = p.src0;
        s.src1 = p.src1;
        s.dst = p.dst;
        s.decode = p.decode;
        station_from_pkt = s;
    endfunction

    function automatic ydrasil_issue_pkt_t pkt_from_station(
        input issue_station_t s, input logic valid
    );
        ydrasil_issue_pkt_t p;
        p = '0;
        p.valid = valid;
        p.memory_op = s.memory_op;
        p.lane_mask = {s.can_b, s.can_a};
        p.src0 = s.src0;
        p.src1 = s.src1;
        p.dst = s.dst;
        p.target = s.decode.pc + s.decode.imm;
        p.next_pc = s.decode.pc + 32'd4;
        p.decode = s.decode;
        p.ctrl.valid = valid;
        p.ctrl.rs1_addr = s.src0.arch_addr;
        p.ctrl.rs2_addr = s.src1.arch_addr;
        p.ctrl.rd_addr = s.dst.rd_addr;
        p.ctrl.rs1_ren = s.src0.used;
        p.ctrl.rs2_ren = s.src1.used;
        p.ctrl.rd_wen = s.dst.writes_gpr;
        p.ctrl.lsu_req = s.memory_op;
        p.ctrl.store_req = s.decode.operator_type[OPERATOR_TYPE_STORE];
        p.ctrl.serialize_before = s.serial_before;
        p.ctrl.checkpoint_req = s.branch;
        pkt_from_station = p;
    endfunction

    function automatic logic raw_dep(
        input issue_station_t older, input issue_station_t younger
    );
        raw_dep = older.dst.writes_gpr &&
            ((younger.src0.used && younger.src0.tag_valid &&
              (older.dst.rob_tag == younger.src0.producer_tag)) ||
             (younger.src1.used && younger.src1.tag_valid &&
              (older.dst.rob_tag == younger.src1.producer_tag)));
    endfunction

    function automatic logic pair_ok(
        input issue_station_t older, input issue_station_t younger
    );
        logic resource_conflict;
        logic branch_memory;
        resource_conflict = |(older.decode.resources & younger.decode.resources &
            RESOURCE_EXCLUSIVE_MASK);
        branch_memory = (older.branch && younger.memory_op) ||
            (younger.branch && older.memory_op);
        pair_ok = !raw_dep(older, younger) && !resource_conflict &&
            !older.serial_before && !younger.serial_before && !branch_memory;
    endfunction

    function automatic logic cross_ok(
        input issue_station_t older, input issue_station_t younger
    );
        cross_ok = younger.spec_safe && !older.serial_before &&
            !raw_dep(older, younger);
    endfunction

    function automatic logic age_older(
        input logic [31:0] a, input logic [31:0] b
    );
        age_older = a < b;
    endfunction

    function automatic logic dispatch_ready(
        input ydrasil_source_desc_t src,
        input ydrasil_rob_source_state_t state
    );
        dispatch_ready = !src.used || !src.tag_valid ||
            (state.live && state.done) || typed_completion_hit(src);
    endfunction

    function automatic [DATA_WIDTH-1:0] dispatch_value(
        input ydrasil_source_desc_t src,
        input ydrasil_rob_source_state_t state,
        input logic [DATA_WIDTH-1:0] rf_value
    );
        dispatch_value = rf_value;
        if (src.used && src.tag_valid && state.live && state.done)
            dispatch_value = state.result;
        if (src.used && src.tag_valid && typed_completion_hit(src))
            dispatch_value = typed_completion_value(src);
    endfunction

    function automatic station_admit_t station_admit_from_dispatch(
        input ydrasil_issue_pkt_t p,
        input ydrasil_rob_source_state_t state0,
        input ydrasil_rob_source_state_t state1,
        input logic [DATA_WIDTH-1:0] rf0,
        input logic [DATA_WIDTH-1:0] rf1
    );
        station_admit_t e;
        e = '0;
        e.station = station_from_pkt(p);
        e.ready0 = dispatch_ready(p.src0, state0);
        e.ready1 = dispatch_ready(p.src1, state1);
        e.value0 = dispatch_value(p.src0, state0, rf0);
        e.value1 = dispatch_value(p.src1, state1, rf1);
        station_admit_from_dispatch = e;
    endfunction

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

    // Exposed age relation is also used by the performance harness.  It is a
    // derived view, not a stored NxN dependency matrix.
    reg [N-1:0] older_q [0:N-1];
    integer age_i, age_j;
    always_comb begin
        for (age_i = 0; age_i < N; age_i = age_i + 1)
            for (age_j = 0; age_j < N; age_j = age_j + 1)
                older_q[age_i][age_j] = entry_valid_q[age_i] &&
                    entry_valid_q[age_j] && age_older(age_q[age_i], age_q[age_j]);
    end

    wire select_enable = !stall_id_i && !bubble_id_i && !flush_id_i;
    reg [N-1:0] oldest_any;
    reg [N-1:0] blocked;
    reg [N-1:0] eligible;
    reg [N-1:0] cand_a, cand_b;
    reg [N-1:0] select0, select1;
    reg [N-1:0] pair_legal [0:N-1];
    reg [N-1:0] ready0_now, ready1_now;
    reg pair_found;
    integer pair_a_idx, pair_b_idx;
    logic [31:0] pair_oldest_age, pair_youngest_age;
    integer single_a_idx, single_b_idx;
    integer reservation_pair_b_idx;
    integer si, sj;

    // All terms here originate in station or reservation registers.  In
    // particular, `eligible` excludes completion data and the reservation has
    // already captured the producer/consumer tag relation in the prior cycle.
    wire local_reservation_active = local_reservation_q.valid &&
        entry_valid_q[local_reservation_q.slot] &&
        eligible[local_reservation_q.slot] &&
        station_q[local_reservation_q.slot].can_a &&
        ((bypass0_q[local_reservation_q.slot] != BYPASS_NONE) ||
         (bypass1_q[local_reservation_q.slot] != BYPASS_NONE));

    always_comb begin
        oldest_any = '0;
        blocked = '0;
        eligible = '0;
        cand_a = '0;
        cand_b = '0;
        select0 = '0;
        select1 = '0;
        ready0_now = '0;
        ready1_now = '0;
        pair_found = 1'b0;
        pair_a_idx = -1;
        pair_b_idx = -1;
        pair_oldest_age = '0;
        pair_youngest_age = '0;
        single_a_idx = -1;
        single_b_idx = -1;
        reservation_pair_b_idx = -1;
        for (si = 0; si < N; si = si + 1)
            pair_legal[si] = '0;

        for (si = 0; si < N; si = si + 1) begin
            if (entry_valid_q[si]) begin
                // Bypass controls were computed when the producer was
                // selected in the preceding cycle.  Completion is absent
                // from this ready path.
                ready0_now[si] = ready0_q[si] ||
                    (bypass0_q[si] != BYPASS_NONE);
                ready1_now[si] = ready1_q[si] ||
                    (bypass1_q[si] != BYPASS_NONE);
                oldest_any[si] = 1'b1;
                for (sj = 0; sj < N; sj = sj + 1) begin
                    if (older_q[sj][si])
                        oldest_any[si] = 1'b0;
                    if (older_q[sj][si] && !cross_ok(station_q[sj], station_q[si]))
                        blocked[si] = 1'b1;
                end
                if (ready0_now[si] && ready1_now[si] && !blocked[si] &&
                    !serial_barrier_q &&
                    !(control_barrier_q && !station_q[si].spec_safe) &&
                    !(station_q[si].memory_op && lsu_status_i.busy) &&
                    !(station_q[si].serial_before &&
                      ((station_q[si].dst.rob_tag != rob_head_tag_q) ||
                       !lsu_status_i.idle))) begin
                    eligible[si] = 1'b1;
                    cand_a[si] = station_q[si].can_a;
                    cand_b[si] = station_q[si].can_b;
                end
            end
        end

        // Compute all physically legal pairs from state captured before this
        // cycle.  Pair selection has no lane-to-lane operand dependency: the
        // final mapping is simply one compatible A lane and one compatible B
        // lane.  Age gives a deterministic, program-order preserving choice.
        for (si = 0; si < N; si = si + 1) begin
            for (sj = si + 1; sj < N; sj = sj + 1) begin
                if (eligible[si] && eligible[sj] &&
                    ((cand_a[si] && cand_b[sj]) ||
                     (cand_b[si] && cand_a[sj])) &&
                    (age_older(age_q[si], age_q[sj]) ?
                     pair_ok(station_q[si], station_q[sj]) :
                     pair_ok(station_q[sj], station_q[si]))) begin
                    pair_legal[si][sj] = 1'b1;
                    if (!pair_found ||
                        age_older(age_q[si], pair_oldest_age) ||
                        age_older(age_q[sj], pair_oldest_age) ||
                        ((age_q[si] == pair_oldest_age || age_q[sj] == pair_oldest_age) &&
                         ((age_older(age_q[si], age_q[sj]) ? age_q[sj] : age_q[si]) <
                          pair_youngest_age))) begin
                        pair_found = 1'b1;
                        if (cand_a[si] && cand_b[sj]) begin
                            pair_a_idx = si;
                            pair_b_idx = sj;
                        end else begin
                            pair_a_idx = sj;
                            pair_b_idx = si;
                        end
                        pair_oldest_age = age_older(age_q[si], age_q[sj]) ?
                            age_q[si] : age_q[sj];
                        pair_youngest_age = age_older(age_q[si], age_q[sj]) ?
                            age_q[sj] : age_q[si];
                    end
                end
            end
        end
        if (pair_found) begin
            select0[pair_a_idx] = 1'b1;
            select1[pair_b_idx] = 1'b1;
        end else begin
            // No legal pair exists.  Choose independently-derived A and B
            // candidates by age, so a B-only instruction is never held
            // behind an unrelated A candidate.
            for (si = 0; si < N; si = si + 1) begin
                if (cand_a[si] &&
                    (single_a_idx < 0 || age_older(age_q[si], age_q[single_a_idx])))
                    single_a_idx = si;
                if (cand_b[si] &&
                    (single_b_idx < 0 || age_older(age_q[si], age_q[single_b_idx])))
                    single_b_idx = si;
            end
            if (single_a_idx >= 0 &&
                (single_b_idx < 0 || single_a_idx == single_b_idx ||
                 age_older(age_q[single_a_idx], age_q[single_b_idx])))
                select0[single_a_idx] = 1'b1;
            else if (single_b_idx >= 0)
                select1[single_b_idx] = 1'b1;
        end

        // The reservation wins Lane 0 without re-running the consumer through
        // the general oldest/pair chooser.  Lane 1 remains independently
        // selectable, but only when it forms a legal pair with the reserved
        // consumer.  This preserves the ordinary resource and program-order
        // rules while keeping the bypass timing path local.
        if (local_reservation_active) begin
            for (si = 0; si < N; si = si + 1) begin
                if (cand_b[si] && (si != local_reservation_q.slot) &&
                    (reservation_pair_b_idx < 0 ||
                     age_older(age_q[si], age_q[reservation_pair_b_idx])) &&
                    (age_older(age_q[local_reservation_q.slot], age_q[si]) ?
                     pair_ok(station_q[local_reservation_q.slot], station_q[si]) :
                     pair_ok(station_q[si], station_q[local_reservation_q.slot])))
                    reservation_pair_b_idx = si;
            end
            // A reservation must not displace an otherwise available pair.
            // It wins a singleton cycle, or replaces a pair with another
            // legal pair that consumes the local ALU bypass.
            if (!pair_found || reservation_pair_b_idx >= 0) begin
                select0 = '0;
                select1 = '0;
                select0[local_reservation_q.slot] = 1'b1;
                if (reservation_pair_b_idx >= 0)
                    select1[reservation_pair_b_idx] = 1'b1;
            end
        end

        if (!select_enable) begin
            select0 = '0;
            select1 = '0;
        end
    end

    wire selected_a_valid = |select0;
    wire selected_b_valid = |select1;
    wire selected_valid = selected_a_valid || selected_b_valid;
    wire selected_pair = selected_a_valid && selected_b_valid;
    wire [N-1:0] selected_remove = select0 | select1;

    // Reserve a direct dependent simple-ALU consumer for the next issue/EX
    // transfer.  The order check treats the selected producer(s) as removed;
    // every other older station entry must still permit the consumer to cross.
    integer reservation_i, reservation_j;
    reg reservation_order_safe;
    always_comb begin
        local_reservation_d = '0;
        for (reservation_i = 0; reservation_i < N;
             reservation_i = reservation_i + 1) begin
            reservation_order_safe = 1'b1;
            for (reservation_j = 0; reservation_j < N;
                 reservation_j = reservation_j + 1)
                if (entry_valid_q[reservation_j] &&
                    !selected_remove[reservation_j] &&
                    older_q[reservation_j][reservation_i] &&
                    !cross_ok(station_q[reservation_j],
                              station_q[reservation_i]))
                    reservation_order_safe = 1'b0;
            if (!local_reservation_d.valid &&
                entry_valid_q[reservation_i] &&
                !selected_remove[reservation_i] &&
                reservable_alu_consumer(station_q[reservation_i]) &&
                source_ready_after_selected_alu(station_q[reservation_i].src0,
                    ready0_q[reservation_i], selected_a_valid, selected_station0,
                    selected_b_valid, selected_station1) &&
                source_ready_after_selected_alu(station_q[reservation_i].src1,
                    ready1_q[reservation_i], selected_a_valid, selected_station0,
                    selected_b_valid, selected_station1) &&
                ((!ready0_q[reservation_i] && source_from_selected_alu(
                    station_q[reservation_i].src0, selected_a_valid,
                    selected_station0, selected_b_valid, selected_station1)) ||
                 (!ready1_q[reservation_i] && source_from_selected_alu(
                    station_q[reservation_i].src1, selected_a_valid,
                    selected_station0, selected_b_valid, selected_station1))) &&
                reservation_order_safe) begin
                local_reservation_d.valid = 1'b1;
                local_reservation_d.slot = reservation_i[1:0];
            end
        end
    end

    issue_station_t selected_station0, selected_station1;
    ydrasil_issue_pkt_t selected_uop0, selected_uop1;
    reg [DATA_WIDTH-1:0] selected_src00, selected_src01;
    reg [DATA_WIDTH-1:0] selected_src10, selected_src11;
    reg [2:0] selected_bypass00, selected_bypass01;
    reg [2:0] selected_bypass10, selected_bypass11;
    integer oi;
    always_comb begin
        selected_station0 = '0;
        selected_station1 = '0;
        selected_src00 = '0;
        selected_src01 = '0;
        selected_src10 = '0;
        selected_src11 = '0;
        selected_bypass00 = BYPASS_NONE;
        selected_bypass01 = BYPASS_NONE;
        selected_bypass10 = BYPASS_NONE;
        selected_bypass11 = BYPASS_NONE;
        for (oi = 0; oi < N; oi = oi + 1) begin
            if (select0[oi]) begin
                selected_station0 = station_q[oi];
                selected_src00 = value0_q[oi];
                selected_src01 = value1_q[oi];
                selected_bypass00 = bypass0_q[oi];
                selected_bypass01 = bypass1_q[oi];
                if (bypass0_q[oi] != BYPASS_NONE)
                    selected_src00 = bypass_value(bypass0_q[oi]);
                if (bypass1_q[oi] != BYPASS_NONE)
                    selected_src01 = bypass_value(bypass1_q[oi]);
            end
            if (select1[oi]) begin
                selected_station1 = station_q[oi];
                selected_src10 = value0_q[oi];
                selected_src11 = value1_q[oi];
                selected_bypass10 = bypass0_q[oi];
                selected_bypass11 = bypass1_q[oi];
                if (bypass0_q[oi] != BYPASS_NONE)
                    selected_src10 = bypass_value(bypass0_q[oi]);
                if (bypass1_q[oi] != BYPASS_NONE)
                    selected_src11 = bypass_value(bypass1_q[oi]);
            end
        end
        selected_uop0 = pkt_from_station(selected_station0, selected_a_valid);
        selected_uop1 = pkt_from_station(selected_station1, selected_b_valid);
    end

    // Dispatch capacity is a pure registered station/ingress-credit property.
    // In particular, selected_remove is deliberately absent: a selection may
    // refill only a uop that was already admitted by a prior credit, so station
    // selection cannot form an issue -> ID/RAT -> issue combinational loop.
    reg [2:0] station_free_count;
    reg [1:0] ingress_free_count;
    integer capacity_i;
    always_comb begin
        station_free_count = '0;
        ingress_free_count = '0;
        for (capacity_i = 0; capacity_i < N; capacity_i = capacity_i + 1)
            if (!entry_valid_q[capacity_i])
                station_free_count = station_free_count + 1'b1;
        for (capacity_i = 0; capacity_i < INGRESS_N; capacity_i = capacity_i + 1)
            if (!ingress_valid_q[capacity_i])
                ingress_free_count = ingress_free_count + 1'b1;
    end
    wire [2:0] registered_admit_credits = station_free_count + ingress_free_count;
    wire [2:0] station_admit_slots = (registered_admit_credits > 3'd2) ?
        3'd2 : registered_admit_credits;
    assign issue_ready_o = !flush_id_i && !bubble_id_i &&
        (station_admit_slots != 0);
    assign issue_dispatch_two_ready_o = !flush_id_i && !bubble_id_i &&
        (station_admit_slots == 3'd2);
    assign issue_dispatch_ready_q_o = issue_ready_o;
    assign issue_dispatch_two_ready_q_o = issue_dispatch_two_ready_o;

    assign issue_pkt_o = selected_uop0;
    assign issue_pkt1_o = selected_uop1;
    assign issue_consume_two_o = selected_pair;
    assign issue_slot1_replay_o = 1'b0;

    reg [1:0] oldest_idx;
    reg oldest_found;
    integer oldest_i;
    integer di;
    always_comb begin
        oldest_idx = '0;
        oldest_found = 1'b0;
        for (oldest_i = 0; oldest_i < N; oldest_i = oldest_i + 1)
            if (oldest_any[oldest_i] && !oldest_found) begin
                oldest_idx = oldest_i[1:0];
                oldest_found = 1'b1;
            end
    end

    wire oldest_local_ready = oldest_found &&
        (ready0_now[oldest_idx] && ready1_now[oldest_idx]);
    assign scoreboard_stall_o = oldest_found && !oldest_local_ready;
    assign scoreboard_stall1_o = 1'b0;
    assign src0_wait_o = oldest_found && station_q[oldest_idx].src0.used &&
        !ready0_now[oldest_idx];
    assign src1_wait_o = oldest_found && station_q[oldest_idx].src1.used &&
        !ready1_now[oldest_idx];
    assign src2_wait_o = 1'b0;
    assign src3_wait_o = 1'b0;
    assign lsu_struct_stall_o = oldest_found && station_q[oldest_idx].memory_op &&
        lsu_status_i.busy;
    assign lsu_struct_stall1_o = 1'b0;
    assign serialize_stall_o = oldest_found && station_q[oldest_idx].serial_before &&
        ((station_q[oldest_idx].dst.rob_tag != rob_head_tag_q) || !lsu_status_i.idle);

    assign rf_addr_rs1_o = selected_uop0.src0.arch_addr;
    assign rf_addr_rs2_o = selected_uop0.src1.arch_addr;
    assign rf_addr_rs3_o = selected_uop1.src0.arch_addr;
    assign rf_addr_rs4_o = selected_uop1.src1.arch_addr;
    assign dispatch_rf_addr_rs1_o = dispatch_pkt_i.src0.arch_addr;
    assign dispatch_rf_addr_rs2_o = dispatch_pkt_i.src1.arch_addr;
    assign dispatch_rf_addr_rs3_o = dispatch_pkt1_i.src0.arch_addr;
    assign dispatch_rf_addr_rs4_o = dispatch_pkt1_i.src1.arch_addr;
    assign fpr_addr_rs1_o = selected_uop0.decode.fp_rs1_addr;
    assign fpr_addr_rs2_o = selected_uop0.decode.fp_rs2_addr;
    assign fpr_addr_rs3_o = selected_uop0.decode.fp_rs3_addr;

    // System operations have no EX data path.  The issue station has already
    // established their serial/head/LSU-idle preconditions, so hand them to
    // trap control through a registered sideband request instead of placing
    // a no-op packet in Issue/EX.
    wire selected_sys = selected_a_valid &&
        selected_uop0.decode.operator_type[OPERATOR_TYPE_SYS];
    wire selected_wfi = selected_sys &&
        selected_uop0.decode.sys_op_info[OP_SYS_WFI];
    wire selected_sys_trap = selected_sys && !selected_wfi;
    ydrasil_issue_ex_pkt_t issue_ex_d, issue_ex_q;
    always_comb begin
        issue_ex_d = '0;
        // SYSTEM instructions terminate at the registered issue-side trap
        // request below.  They must not also occupy EX: otherwise EX would
        // observe a data-less uop and account/retire it through its ordinary
        // execution path before trap control owns the serialization point.
        issue_ex_d.valid = selected_a_valid && !selected_sys;
        issue_ex_d.operand_a = operand_a_for(selected_uop0, selected_src00);
        issue_ex_d.operand_b = operand_b_for(selected_uop0, selected_src01);
        issue_ex_d.operator_info = selected_uop0.decode.operator_info;
        issue_ex_d.operator_type = selected_uop0.decode.operator_type;
        issue_ex_d.jalr = selected_uop0.decode.bt_a_rs_sel;
        issue_ex_d.branch_target = selected_uop0.target;
        issue_ex_d.branch_next_pc = selected_uop0.next_pc;
        issue_ex_d.bt_a_operand = selected_uop0.decode.bt_a_rs_sel ?
            selected_src00 : selected_uop0.decode.pc;
        issue_ex_d.bt_b_operand = selected_src01;
        issue_ex_d.pred_hit = selected_uop0.decode.pred_hit;
        issue_ex_d.pred_taken = selected_uop0.decode.pred_taken;
        issue_ex_d.pred_target = selected_uop0.decode.pred_target;
        issue_ex_d.pred_counter = selected_uop0.decode.pred_counter;
        issue_ex_d.pred_bht_index = selected_uop0.decode.pred_bht_index;
        issue_ex_d.csr_raddr = selected_uop0.decode.csr_raddr;
        issue_ex_d.csr_waddr = selected_uop0.decode.csr_waddr;
        issue_ex_d.csr_op_info = selected_uop0.decode.csr_op_info;
        issue_ex_d.sys_op_info = selected_uop0.decode.sys_op_info;
        issue_ex_d.pc = selected_uop0.decode.pc;
        issue_ex_d.rd_wen = selected_a_valid && selected_uop0.dst.writes_gpr;
        issue_ex_d.rd_addr = selected_uop0.dst.rd_addr;
        issue_ex_d.producer_id = selected_uop0.dst.rob_tag;
        issue_ex_d.producer_tracked = selected_a_valid;
        issue_ex_d.lsu_req.valid = selected_a_valid && selected_uop0.memory_op;
        issue_ex_d.lsu_req.is_load = selected_uop0.decode.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.is_store = selected_uop0.decode.operator_type[OPERATOR_TYPE_STORE];
        issue_ex_d.lsu_req.op = selected_uop0.decode.operator_lsu;
        issue_ex_d.lsu_req.rd_addr = selected_uop0.dst.rd_addr;
        issue_ex_d.lsu_req.producer_id = selected_uop0.dst.rob_tag;
        issue_ex_d.lsu_req.producer_tracked = selected_a_valid;
        issue_ex_d.lsu_req.store_data = selected_src01;
        issue_ex_d.lsu_req.store_data_valid = 1'b1;
        issue_ex_d.lsu_req.fp_load = selected_uop0.decode.fp_valid &&
            selected_uop0.decode.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.fp_rd_addr = selected_uop0.decode.fp_rd_addr;
        issue_ex_d.fpu_req.valid = selected_a_valid && selected_uop0.decode.fp_valid &&
            !selected_uop0.decode.operator_type[OPERATOR_TYPE_LOAD] &&
            !selected_uop0.decode.operator_type[OPERATOR_TYPE_STORE];
        issue_ex_d.fpu_req.illegal = selected_uop0.decode.fp_illegal;
        issue_ex_d.fpu_req.op = selected_uop0.decode.fp_op;
        issue_ex_d.fpu_req.rm = selected_uop0.decode.fp_rm;
        issue_ex_d.fpu_req.operand_a = selected_uop0.decode.fp_rs1_fpr ?
            fpr_rdata_rs1_i : selected_src00;
        issue_ex_d.fpu_req.operand_b = fpr_rdata_rs2_i;
        issue_ex_d.fpu_req.operand_c = fpr_rdata_rs3_i;
        issue_ex_d.fpu_req.rd_addr = selected_uop0.dst.rd_addr;
        issue_ex_d.fpu_req.rd_fpr = selected_uop0.decode.fp_rd_fpr;
        issue_ex_d.fpu_req.rd_gpr = selected_uop0.decode.fp_rd_gpr;
        issue_ex_d.fpu_req.producer_id = selected_uop0.dst.rob_tag;
        issue_ex_d.fpu_req.producer_tracked = selected_a_valid;
        issue_ex_d.fpu_req.pc = selected_uop0.decode.pc;
        issue_ex_d.fpu_req.instr = selected_uop0.decode.instr;
        issue_ex_d.lane1_valid = selected_b_valid;
        issue_ex_d.lane1_operand_a = operand_a_for(selected_uop1, selected_src10);
        issue_ex_d.lane1_operand_b = operand_b_for(selected_uop1, selected_src11);
        issue_ex_d.lane1_branch_operand_a = selected_src10;
        issue_ex_d.lane1_branch_operand_b = selected_src11;
        issue_ex_d.lane1_branch_imm = selected_uop1.decode.imm;
        issue_ex_d.lane1_operator_info = selected_uop1.decode.operator_info;
        issue_ex_d.lane1_operator_type = selected_uop1.decode.operator_type;
        issue_ex_d.lane1_operator_lsu = selected_uop1.decode.operator_lsu;
        issue_ex_d.lane1_store_data = selected_src11;
        issue_ex_d.lane1_store_data_valid = 1'b1;
        issue_ex_d.lane1_rd_addr = selected_uop1.dst.rd_addr;
        issue_ex_d.lane1_rd_wen = selected_b_valid && selected_uop1.dst.writes_gpr;
        issue_ex_d.lane1_producer_id = selected_uop1.dst.rob_tag;
        issue_ex_d.lane1_producer_tracked = selected_b_valid;
        issue_ex_d.lane1_pc = selected_uop1.decode.pc;
        issue_ex_d.lane1_instr = selected_uop1.decode.instr;
        issue_ex_d.lane1_jalr = selected_uop1.decode.bt_a_rs_sel;
        issue_ex_d.lane1_branch_target = selected_uop1.target;
        issue_ex_d.lane1_branch_next_pc = selected_uop1.next_pc;
        issue_ex_d.lane1_pred_hit = selected_uop1.decode.pred_hit;
        issue_ex_d.lane1_pred_taken = selected_uop1.decode.pred_taken;
        issue_ex_d.lane1_pred_target = selected_uop1.decode.pred_target;
        issue_ex_d.lane1_pred_counter = selected_uop1.decode.pred_counter;
        issue_ex_d.lane1_pred_bht_index = selected_uop1.decode.pred_bht_index;
        if (selected_a_valid && (selected_uop0.decode.fence_i || selected_sys))
            issue_ex_d = '0;
        if (!select_enable)
            issue_ex_d = '0;
    end

    reg issue_fence_q;
    producer_id_t issue_fence_tag_q;
    reg [INST_ADDR_WIDTH-1:0] issue_fence_next_pc_q;
    ydrasil_exception_req_pkt_t issue_sys_req_q;
    reg issue_sys_complete_q;
    producer_id_t issue_sys_tag_q;
    assign issue_fence_o = issue_fence_q;
    assign issue_fence_tag_o = issue_fence_tag_q;
    assign issue_fence_next_pc_o = issue_fence_next_pc_q;
    assign issue_sys_req_o = issue_sys_req_q;
    assign issue_sys_complete_o = issue_sys_complete_q;
    assign issue_sys_tag_o = issue_sys_tag_q;

    // Wakeup and dispatch admission both terminate at station registers.
    // Completion has no combinational consumer in station selection; the only
    // data bypass uses a control bit armed by the preceding select. Dispatch
    // may enter the registered ingress under a pre-existing credit and be
    // physically placed into a selected slot at this edge, but selection never
    // affects the front-end credit that admitted it.
    station_admit_t admit0, admit1;
    reg accept0, accept1;
    integer k, arrival_i, arrival_tail, arrival_slot, ingress_tail;
    always_comb begin
        admit0 = station_admit_from_dispatch(dispatch_pkt_i,
            dispatch_src0_state_i, dispatch_src1_state_i,
            dispatch_rf_rdata_rs1_i, dispatch_rf_rdata_rs2_i);
        admit1 = station_admit_from_dispatch(dispatch_pkt1_i,
            dispatch_src2_state_i, dispatch_src3_state_i,
            dispatch_rf_rdata_rs3_i, dispatch_rf_rdata_rs4_i);
        accept0 = dispatch_accept_i && dispatch_pkt_i.valid &&
            (station_admit_slots != 0);
        accept1 = dispatch_accept1_i && dispatch_pkt1_i.valid && accept0 &&
            (station_admit_slots == 3'd2);

        entry_valid_d = entry_valid_q;
        next_age_d = next_age_q;
        arrival_valid = '0;
        for (arrival_i = 0; arrival_i < INGRESS_N + 2;
             arrival_i = arrival_i + 1) begin
            arrival_admit[arrival_i] = '0;
            arrival_age[arrival_i] = '0;
        end
        ingress_valid_d = '0;
        for (k = 0; k < INGRESS_N; k = k + 1)
            ingress_d[k] = '0;
        for (di = 0; di < N; di = di + 1) begin
            station_d[di] = station_q[di];
            age_d[di] = age_q[di];
            ready0_d[di] = ready0_q[di];
            ready1_d[di] = ready1_q[di];
            value0_d[di] = value0_q[di];
            value1_d[di] = value1_q[di];
            // A local bypass is valid for one execute cycle only.  If that
            // cycle cannot issue, the completion capture below supplies the
            // registered value for a later retry.
            bypass0_d[di] = BYPASS_NONE;
            bypass1_d[di] = BYPASS_NONE;
            if (entry_valid_q[di]) begin
                if (typed_completion_hit(station_q[di].src0)) begin
                    ready0_d[di] = 1'b1;
                    value0_d[di] = typed_completion_value(station_q[di].src0);
                end
                if (typed_completion_hit(station_q[di].src1)) begin
                    ready1_d[di] = 1'b1;
                    value1_d[di] = typed_completion_value(station_q[di].src1);
                end
            end
            if (selected_remove[di]) begin
                entry_valid_d[di] = 1'b0;
                station_d[di] = '0;
                age_d[di] = '0;
                ready0_d[di] = 1'b0;
                ready1_d[di] = 1'b0;
                value0_d[di] = '0;
                value1_d[di] = '0;
                bypass0_d[di] = BYPASS_NONE;
                bypass1_d[di] = BYPASS_NONE;
            end
        end

        // Precompute the next-cycle ALU forwarding controls while the
        // producer is selected.  At the next cycle these controls select only
        // a local data mux; there is no completion/tag/ready path into the
        // global station selector.
        for (di = 0; di < N; di = di + 1) begin
            if (entry_valid_q[di] && !selected_remove[di]) begin
                if (!ready0_q[di]) begin
                    if (selected_a_valid && bypassable_alu(selected_station0) &&
                        source_matches(station_q[di].src0, selected_station0))
                        bypass0_d[di] = BYPASS_ALU0;
                    else if (selected_b_valid && bypassable_alu(selected_station1) &&
                             source_matches(station_q[di].src0, selected_station1))
                        bypass0_d[di] = BYPASS_ALU1;
                    else if (source_matches_mul_plan(station_q[di].src0,
                        mul_wake_plan_q[3]))
                        bypass0_d[di] = BYPASS_MUL;
                end
                if (!ready1_q[di]) begin
                    if (selected_a_valid && bypassable_alu(selected_station0) &&
                        source_matches(station_q[di].src1, selected_station0))
                        bypass1_d[di] = BYPASS_ALU0;
                    else if (selected_b_valid && bypassable_alu(selected_station1) &&
                             source_matches(station_q[di].src1, selected_station1))
                        bypass1_d[di] = BYPASS_ALU1;
                    else if (source_matches_mul_plan(station_q[di].src1,
                        mul_wake_plan_q[3]))
                        bypass1_d[di] = BYPASS_MUL;
                end
            end
        end

        // Preserve architectural order across the elastic boundary. Existing
        // ingress entries are older than this cycle's dispatch pair; selected
        // station entries are removed before allocation, but never influence
        // whether either new dispatch was accepted.
        arrival_tail = 0;
        for (arrival_i = 0; arrival_i < INGRESS_N;
             arrival_i = arrival_i + 1)
            if (ingress_valid_q[arrival_i]) begin
                arrival_valid[arrival_tail] = 1'b1;
                arrival_admit[arrival_tail] = ingress_q[arrival_i].admit;
                // An ingress entry is part of the registered wakeup domain.
                // Capture completion data here as well as in the station so a
                // producer cannot complete while its consumer waits to enter
                // the station.
                if (!ingress_q[arrival_i].admit.ready0 &&
                    typed_completion_hit(ingress_q[arrival_i].admit.station.src0)) begin
                    arrival_admit[arrival_tail].ready0 = 1'b1;
                    arrival_admit[arrival_tail].value0 =
                        typed_completion_value(ingress_q[arrival_i].admit.station.src0);
                end
                if (!ingress_q[arrival_i].admit.ready1 &&
                    typed_completion_hit(ingress_q[arrival_i].admit.station.src1)) begin
                    arrival_admit[arrival_tail].ready1 = 1'b1;
                    arrival_admit[arrival_tail].value1 =
                        typed_completion_value(ingress_q[arrival_i].admit.station.src1);
                end
                arrival_age[arrival_tail] = ingress_q[arrival_i].age;
                arrival_tail = arrival_tail + 1;
            end
        if (accept0) begin
            arrival_valid[arrival_tail] = 1'b1;
            arrival_admit[arrival_tail] = admit0;
            arrival_age[arrival_tail] = next_age_q;
            arrival_tail = arrival_tail + 1;
        end
        if (accept1) begin
            arrival_valid[arrival_tail] = 1'b1;
            arrival_admit[arrival_tail] = admit1;
            arrival_age[arrival_tail] = next_age_q + 1'b1;
        end
        next_age_d = next_age_q + accept0 + accept1;

        // Allocation is edge-local: packets accepted under old credit may use
        // a slot selected in this same cycle, while front-end ready remains a
        // function of q-state only. This restores bypass planning for a full
        // station without a combinational path back into ID/RAT.
        for (arrival_i = 0; arrival_i < INGRESS_N + 2;
             arrival_i = arrival_i + 1) begin
            arrival_slot = -1;
            for (k = 0; k < N; k = k + 1)
                if (arrival_valid[arrival_i] && !entry_valid_d[k] &&
                    arrival_slot < 0)
                    arrival_slot = k;
            if (arrival_valid[arrival_i] && (arrival_slot >= 0)) begin
                entry_valid_d[arrival_slot] = 1'b1;
                station_d[arrival_slot] = arrival_admit[arrival_i].station;
                ready0_d[arrival_slot] = arrival_admit[arrival_i].ready0;
                ready1_d[arrival_slot] = arrival_admit[arrival_i].ready1;
                value0_d[arrival_slot] = arrival_admit[arrival_i].value0;
                value1_d[arrival_slot] = arrival_admit[arrival_i].value1;
                age_d[arrival_slot] = arrival_age[arrival_i];
                bypass0_d[arrival_slot] = BYPASS_NONE;
                bypass1_d[arrival_slot] = BYPASS_NONE;
                if (!arrival_admit[arrival_i].ready0) begin
                    if (selected_a_valid && bypassable_alu(selected_station0) &&
                        source_matches(arrival_admit[arrival_i].station.src0,
                                       selected_station0))
                        bypass0_d[arrival_slot] = BYPASS_ALU0;
                    else if (selected_b_valid && bypassable_alu(selected_station1) &&
                             source_matches(arrival_admit[arrival_i].station.src0,
                                            selected_station1))
                        bypass0_d[arrival_slot] = BYPASS_ALU1;
                    else if (source_matches_mul_plan(
                        arrival_admit[arrival_i].station.src0, mul_wake_plan_q[3]))
                        bypass0_d[arrival_slot] = BYPASS_MUL;
                end
                if (!arrival_admit[arrival_i].ready1) begin
                    if (selected_a_valid && bypassable_alu(selected_station0) &&
                        source_matches(arrival_admit[arrival_i].station.src1,
                                       selected_station0))
                        bypass1_d[arrival_slot] = BYPASS_ALU0;
                    else if (selected_b_valid && bypassable_alu(selected_station1) &&
                             source_matches(arrival_admit[arrival_i].station.src1,
                                            selected_station1))
                        bypass1_d[arrival_slot] = BYPASS_ALU1;
                    else if (source_matches_mul_plan(
                        arrival_admit[arrival_i].station.src1, mul_wake_plan_q[3]))
                        bypass1_d[arrival_slot] = BYPASS_MUL;
                end
                arrival_valid[arrival_i] = 1'b0;
            end
        end

        ingress_tail = 0;
        for (arrival_i = 0; arrival_i < INGRESS_N + 2;
             arrival_i = arrival_i + 1)
            if (arrival_valid[arrival_i] && (ingress_tail < INGRESS_N)) begin
                ingress_valid_d[ingress_tail] = 1'b1;
                ingress_d[ingress_tail].admit = arrival_admit[arrival_i];
                ingress_d[ingress_tail].age = arrival_age[arrival_i];
                ingress_tail = ingress_tail + 1;
            end

    end

    integer qi, pi;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_id_i) begin
            entry_valid_q <= '0;
            control_barrier_q <= 1'b0;
            serial_barrier_q <= 1'b0;
            rob_head_tag_q <= '0;
            next_age_q <= '0;
            issue_fence_q <= 1'b0;
            issue_fence_tag_q <= '0;
            issue_fence_next_pc_q <= '0;
            issue_sys_req_q <= '0;
            issue_sys_complete_q <= 1'b0;
            issue_sys_tag_q <= '0;
            local_reservation_q <= '0;
            issue_ex_q <= '0;
            ingress_valid_q <= '0;
            for (qi = 0; qi < N; qi = qi + 1) begin
                station_q[qi] <= '0;
                age_q[qi] <= '0;
                ready0_q[qi] <= 1'b0;
                ready1_q[qi] <= 1'b0;
                value0_q[qi] <= '0;
                value1_q[qi] <= '0;
                bypass0_q[qi] <= BYPASS_NONE;
                bypass1_q[qi] <= BYPASS_NONE;
            end
            for (qi = 0; qi < INGRESS_N; qi = qi + 1)
                ingress_q[qi] <= '0;
            for (pi = 0; pi < 4; pi = pi + 1)
                mul_wake_plan_q[pi] <= '0;
        end else begin
            entry_valid_q <= entry_valid_d;
            ingress_valid_q <= ingress_valid_d;
            next_age_q <= next_age_d;
            rob_head_tag_q <= rob_head_tag_i;
            for (qi = 0; qi < N; qi = qi + 1) begin
                station_q[qi] <= station_d[qi];
                age_q[qi] <= age_d[qi];
                ready0_q[qi] <= ready0_d[qi];
                ready1_q[qi] <= ready1_d[qi];
                value0_q[qi] <= value0_d[qi];
                value1_q[qi] <= value1_d[qi];
                bypass0_q[qi] <= bypass0_d[qi];
                bypass1_q[qi] <= bypass1_d[qi];
            end
            for (qi = 0; qi < INGRESS_N; qi = qi + 1)
                ingress_q[qi] <= ingress_d[qi];
            // The plan follows the fixed MUL latency, independently of the
            // global completion bus.  Tag matching happens here at selection
            // time; the only later dependency is the already-known local data
            // mux input from MUL s3.
            mul_wake_plan_q[0].valid <= selected_a_valid &&
                bypassable_mul(selected_station0);
            mul_wake_plan_q[0].tag <= selected_station0.dst.rob_tag;
            for (pi = 1; pi < 4; pi = pi + 1)
                mul_wake_plan_q[pi] <= mul_wake_plan_q[pi-1];
            local_reservation_q <= local_reservation_d;
            control_barrier_q <= selected_valid &&
                (selected_station0.branch || selected_station1.branch);
            serial_barrier_q <= selected_valid &&
                (selected_station0.serial_before || selected_station1.serial_before);
            issue_fence_q <= selected_a_valid && selected_uop0.decode.fence_i;
            issue_sys_req_q <= '0;
            issue_sys_complete_q <= 1'b0;
            issue_sys_tag_q <= '0;
            if (selected_a_valid && selected_uop0.decode.fence_i) begin
                issue_fence_tag_q <= selected_uop0.dst.rob_tag;
                issue_fence_next_pc_q <= selected_uop0.next_pc;
            end
            if (selected_wfi) begin
                issue_sys_complete_q <= 1'b1;
                issue_sys_tag_q <= selected_uop0.dst.rob_tag;
            end
            if (selected_sys_trap) begin
                issue_sys_req_q.valid <= 1'b1;
                issue_sys_req_q.ecall <= selected_uop0.decode.sys_op_info[OP_SYS_ECALL];
                issue_sys_req_q.ebreak <= selected_uop0.decode.sys_op_info[OP_SYS_EBREAK];
                issue_sys_req_q.mret <= selected_uop0.decode.sys_op_info[OP_SYS_MRET];
                // Trap-causing SYSTEM encodings are serialized in issue. WFI
                // is a local no-sleep completion; unsupported forms reach the
                // same trap boundary as an illegal instruction.
                issue_sys_req_q.illegal <= !(selected_uop0.decode.sys_op_info[OP_SYS_ECALL] ||
                    selected_uop0.decode.sys_op_info[OP_SYS_EBREAK] ||
                    selected_uop0.decode.sys_op_info[OP_SYS_MRET]);
                issue_sys_req_q.pc <= selected_uop0.decode.pc;
                issue_sys_req_q.tval <= selected_uop0.decode.instr;
                issue_sys_tag_q <= selected_uop0.dst.rob_tag;
            end
            if (!stall_id_i)
                issue_ex_q <= bubble_id_i ? '0 : issue_ex_d;
        end
    end
    assign issue_ex_o = issue_ex_q;

`ifndef SYNTHESIS
    integer ingress_inv_station_q;
    integer ingress_inv_ingress_q;
    integer ingress_inv_station_d;
    integer ingress_inv_ingress_d;
    integer ingress_inv_i;
    always_ff @(posedge clk) begin
        if (rst_n && !flush_id_i) begin
            ingress_inv_station_q = 0;
            ingress_inv_ingress_q = 0;
            ingress_inv_station_d = 0;
            ingress_inv_ingress_d = 0;
            for (ingress_inv_i = 0; ingress_inv_i < N;
                 ingress_inv_i = ingress_inv_i + 1) begin
                ingress_inv_station_q = ingress_inv_station_q + entry_valid_q[ingress_inv_i];
                ingress_inv_station_d = ingress_inv_station_d + entry_valid_d[ingress_inv_i];
            end
            for (ingress_inv_i = 0; ingress_inv_i < INGRESS_N;
                 ingress_inv_i = ingress_inv_i + 1) begin
                ingress_inv_ingress_q = ingress_inv_ingress_q + ingress_valid_q[ingress_inv_i];
                ingress_inv_ingress_d = ingress_inv_ingress_d + ingress_valid_d[ingress_inv_i];
            end
            assert ((ingress_inv_station_d + ingress_inv_ingress_d) ==
                (ingress_inv_station_q + ingress_inv_ingress_q +
                 accept0 + accept1 - selected_a_valid - selected_b_valid))
                else $fatal(1,
                    "issue ingress conservation failed: accepted uop lost or duplicated");
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (!(issue_ex_q.valid &&
                issue_ex_q.operator_type[OPERATOR_TYPE_SYS]))
                else $fatal(1,
                    "SYSTEM must terminate at the issue-side control boundary");
            assert (!(issue_sys_req_q.valid && issue_sys_complete_q))
                else $fatal(1,
                    "SYSTEM cannot be both a local completion and a trap request");
        end
    end

    wire issue_valid_ff = selected_valid;
    wire id_advance = selected_valid && select_enable;
    wire [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff = selected_a_valid ?
        selected_uop0.decode.operator_type : selected_uop1.decode.operator_type;
    wire rs1_completion_fwd =
        (selected_a_valid && (selected_bypass00 != BYPASS_NONE)) ||
        (selected_b_valid && (selected_bypass10 != BYPASS_NONE));
    wire rs2_completion_fwd =
        (selected_a_valid && (selected_bypass01 != BYPASS_NONE)) ||
        (selected_b_valid && (selected_bypass11 != BYPASS_NONE));
    wire scheduled_bypass_event = (bypass0_d[0] != BYPASS_NONE) ||
        (bypass1_d[0] != BYPASS_NONE) || (bypass0_d[1] != BYPASS_NONE) ||
        (bypass1_d[1] != BYPASS_NONE) || (bypass0_d[2] != BYPASS_NONE) ||
        (bypass1_d[2] != BYPASS_NONE) || (bypass0_d[3] != BYPASS_NONE) ||
        (bypass1_d[3] != BYPASS_NONE);
    wire reserved_bypass_plan_event = local_reservation_d.valid;
    wire reserved_bypass_issue_event = local_reservation_active &&
        select0[local_reservation_q.slot];
    wire reserved_bypass_cancel_event = local_reservation_q.valid &&
        !reserved_bypass_issue_event;
    wire registered_wakeup_event =
        (entry_valid_q[0] && (!ready0_q[0] && typed_completion_hit(station_q[0].src0) ||
                              !ready1_q[0] && typed_completion_hit(station_q[0].src1))) ||
        (entry_valid_q[1] && (!ready0_q[1] && typed_completion_hit(station_q[1].src0) ||
                              !ready1_q[1] && typed_completion_hit(station_q[1].src1))) ||
        (entry_valid_q[2] && (!ready0_q[2] && typed_completion_hit(station_q[2].src0) ||
                              !ready1_q[2] && typed_completion_hit(station_q[2].src1))) ||
        (entry_valid_q[3] && (!ready0_q[3] && typed_completion_hit(station_q[3].src0) ||
                              !ready1_q[3] && typed_completion_hit(station_q[3].src1)));
    function automatic logic registered_wakeup_class_event(
        input ydrasil_result_class_t result_class
    );
        integer wake_i;
        begin
            registered_wakeup_class_event = 1'b0;
            for (wake_i = 0; wake_i < N; wake_i = wake_i + 1)
                if (entry_valid_q[wake_i] &&
                    ((!ready0_q[wake_i] &&
                      station_q[wake_i].src0.producer_class == result_class &&
                      typed_completion_hit(station_q[wake_i].src0)) ||
                     (!ready1_q[wake_i] &&
                      station_q[wake_i].src1.producer_class == result_class &&
                      typed_completion_hit(station_q[wake_i].src1))))
                    registered_wakeup_class_event = 1'b1;
        end
    endfunction
    wire registered_alu_wakeup_event = registered_wakeup_class_event(RESULT_ALU);
    wire registered_lsu_wakeup_event = registered_wakeup_class_event(RESULT_LSU);
    wire registered_mdu_wakeup_event = registered_wakeup_class_event(RESULT_MDU);
    wire completion_latency_event = oldest_found && !oldest_local_ready &&
        (typed_completion_hit(station_q[oldest_idx].src0) ||
         typed_completion_hit(station_q[oldest_idx].src1));
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
