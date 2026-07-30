// Compact, FPGA-oriented issue stage.
//
// Timing ownership is deliberately explicit:
//   * completion writes station/FIFO wakeup state at the clock edge;
//   * selection reads only registered station state and fixed lane metadata;
//   * selection terminates at Issue/EX;
//   * admission writes directly into a released station slot through a fixed
//     one-hot allocator.
//
// There is no completion -> select combinational path, no dynamic packet
// compaction loop, and no selected-producer reservation path.
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
    // Dispatch is captured before it mutates station state.  Four compact
    // records sustain two-wide dispatch while a full station is draining,
    // without making ID readiness depend on this cycle's selection result.
    localparam int INGRESS_N = 4;
    localparam logic [1:0] BYPASS_NONE = 2'd0;
    localparam logic [1:0] BYPASS_ALU0 = 2'd1;
    localparam logic [1:0] BYPASS_ALU1 = 2'd2;
    // `age_q` remains a monotonically increasing trace tag for simulation
    // diagnostics.  Scheduling uses a dense rank instead: rank zero is the
    // oldest resident uop.  This keeps the issue-critical selector out of
    // the modulo age-comparison network.
    localparam int SEQ_WIDTH = 4;

    // Metadata is the only data consumed by the scheduler.  In particular it
    // carries no full decoder packet and no ID control packet.
    typedef struct packed {
        logic                         memory_op;
        logic                         can_lane0;
        logic                         can_lane1;
        logic                         spec_safe;
        logic                         serial_before;
        logic                         branch;
        ydrasil_source_desc_t         src0;
        ydrasil_source_desc_t         src1;
        ydrasil_dest_desc_t           dst;
    } issue_meta_t;

    // This is the execution contract, not a copy of ydrasil_decode_pkt_t.
    // Decode fields used only in ID/RAT have been intentionally omitted.
    typedef struct packed {
        logic [INST_ADDR_WIDTH-1:0]   pc;
        logic [INST_DATA_WIDTH-1:0]   instr;
        logic [INST_ADDR_WIDTH-1:0]   pred_target;
        logic [1:0]                   pred_counter;
        logic [INST_ADDR_WIDTH-1:0]   pred_bht_index;
        logic                         pred_hit;
        logic                         pred_taken;
        logic [DATA_WIDTH-1:0]        imm;
        logic                         operand_b_rs_sel;
        logic                         operand_a_pc_sel;
        logic                         operand_a_imm_sel;
        logic                         bt_a_rs_sel;
        logic                         operand_b_jump_sel;
        logic [OPERATOR_WIDTH-1:0]    operator_info;
        logic [OPERATOR_TYPE_WIDTH-1:0] operator_type;
        logic [OP_LSU_INFO_WIDTH-1:0] operator_lsu;
        logic [CSR_ADDR_WIDTH-1:0]    csr_raddr;
        logic [CSR_ADDR_WIDTH-1:0]    csr_waddr;
        logic [OP_CSR_INFO_WIDTH-1:0] csr_op_info;
        logic [OP_SYS_INFO_WIDTH-1:0] sys_op_info;
        logic                         fence_i;
        logic                         fp_valid;
        logic                         fp_illegal;
        ydrasil_fpu_op_t              fp_op;
        logic [2:0]                   fp_rm;
        logic [REGS_ADDR_WIDTH-1:0]   fp_rs1_addr;
        logic [REGS_ADDR_WIDTH-1:0]   fp_rs2_addr;
        logic [REGS_ADDR_WIDTH-1:0]   fp_rs3_addr;
        logic [REGS_ADDR_WIDTH-1:0]   fp_rd_addr;
        logic                         fp_rs1_fpr;
        logic                         fp_rs2_fpr;
        logic                         fp_rs3_fpr;
        logic                         fp_rd_fpr;
        logic                         fp_rd_gpr;
    } issue_exec_t;

    typedef struct packed {
        issue_meta_t                   meta;
        issue_exec_t                   exec;
        logic                          ready0;
        logic                          ready1;
        logic [DATA_WIDTH-1:0]         value0;
        logic [DATA_WIDTH-1:0]         value1;
        logic [SEQ_WIDTH-1:0]          seq;
    } issue_admit_t;

    issue_meta_t station_meta_q [0:N-1];
    issue_meta_t station_meta_d [0:N-1];
    issue_exec_t station_exec_q [0:N-1];
    issue_exec_t station_exec_d [0:N-1];
    reg [N-1:0] entry_valid_q, entry_valid_d;
    reg [SEQ_WIDTH-1:0] age_q [0:N-1];
    reg [SEQ_WIDTH-1:0] age_d [0:N-1];
    reg [1:0] order_rank_q [0:N-1];
    reg [1:0] order_rank_d [0:N-1];
    reg ready0_q [0:N-1];
    reg ready0_d [0:N-1];
    reg ready1_q [0:N-1];
    reg ready1_d [0:N-1];
    reg [DATA_WIDTH-1:0] value0_q [0:N-1];
    reg [DATA_WIDTH-1:0] value0_d [0:N-1];
    reg [DATA_WIDTH-1:0] value1_q [0:N-1];
    reg [DATA_WIDTH-1:0] value1_d [0:N-1];

    // Local ALU forwarding is represented by the two producer tags that are
    // in EX during the following cycle.  Storing a bypass bit per consumer
    // creates a selected-producer -> scan-all-stations -> station-D feedback
    // path.  The tags below are the sole registered forwarding contract.
    reg bypass_lane0_valid_q;
    reg bypass_lane0_valid_d;
    producer_id_t bypass_lane0_tag_q;
    producer_id_t bypass_lane0_tag_d;
    reg bypass_lane1_valid_q;
    reg bypass_lane1_valid_d;
    producer_id_t bypass_lane1_tag_q;
    producer_id_t bypass_lane1_tag_d;

    // A compact ingress ring separates the registered ID/rename snapshot
    // from station mutation.  It is not a second issue window: only the
    // compact execution record and captured operand state are retained.
    issue_admit_t ingress_q [0:INGRESS_N-1];
    reg [2:0] ingress_count_q;
    reg [1:0] ingress_head_q;
    reg [1:0] ingress_tail_q;

    reg [SEQ_WIDTH-1:0] next_seq_q, next_seq_d;

    producer_id_t rob_head_tag_q;
    // Completion is a writeback event, not an issue-stage combinational
    // input.  In particular, an LSU completion can begin at a DTCM BRAM
    // output.  Register the whole bus before it is allowed to wake a
    // station or update a captured operand.
    ydrasil_completion_bus_t completion_bus_q;
    // LSU state is sampled at the issue boundary. Selection never reads a
    // live LSU queue/store-buffer signal in the same cycle.
    reg lsu_busy_q;
    reg lsu_idle_q;

    function automatic issue_meta_t meta_from_pkt(input ydrasil_issue_pkt_t p);
        issue_meta_t m;
        begin
            m = '0;
            m.memory_op = p.memory_op;
            m.can_lane0 = !p.decode.resources[RESOURCE_BRU] &&
                !p.decode.resources[RESOURCE_LSU];
            m.can_lane1 = !p.decode.resources[RESOURCE_MULDIV] &&
                !p.decode.resources[RESOURCE_FULL_BITMANIP] &&
                !p.decode.resources[RESOURCE_SERIAL] &&
                !p.decode.operator_type[OPERATOR_TYPE_FPU];
            m.spec_safe = p.valid && !p.memory_op &&
                !p.decode.resources[RESOURCE_BRU] &&
                !p.ctrl.serialize_before &&
                !p.decode.operator_type[OPERATOR_TYPE_FPU] &&
                !(p.decode.operator_type[OPERATOR_TYPE_MUL] &&
                  (p.decode.operator_info[OP_MUL_DIV] ||
                   p.decode.operator_info[OP_MUL_DIVU] ||
                   p.decode.operator_info[OP_MUL_REM] ||
                   p.decode.operator_info[OP_MUL_REMU]));
            m.serial_before = p.ctrl.serialize_before;
            m.branch = p.decode.resources[RESOURCE_BRU];
            m.src0 = p.src0;
            m.src1 = p.src1;
            m.dst = p.dst;
            meta_from_pkt = m;
        end
    endfunction

    function automatic issue_exec_t exec_from_pkt(input ydrasil_issue_pkt_t p);
        issue_exec_t e;
        begin
            e = '0;
            e.pc = p.decode.pc;
            e.instr = p.decode.instr;
            e.pred_hit = p.decode.pred_hit;
            e.pred_taken = p.decode.pred_taken;
            e.pred_target = p.decode.pred_target;
            e.pred_counter = p.decode.pred_counter;
            e.pred_bht_index = p.decode.pred_bht_index;
            e.imm = p.decode.imm;
            e.operand_b_rs_sel = p.decode.operand_b_rs_sel;
            e.operand_a_pc_sel = p.decode.operand_a_pc_sel;
            e.operand_a_imm_sel = p.decode.operand_a_imm_sel;
            e.bt_a_rs_sel = p.decode.bt_a_rs_sel;
            e.operand_b_jump_sel = p.decode.operand_b_jump_sel;
            e.operator_info = p.decode.operator_info;
            e.operator_type = p.decode.operator_type;
            e.operator_lsu = p.decode.operator_lsu;
            e.csr_raddr = p.decode.csr_raddr;
            e.csr_waddr = p.decode.csr_waddr;
            e.csr_op_info = p.decode.csr_op_info;
            e.sys_op_info = p.decode.sys_op_info;
            e.fence_i = p.decode.fence_i;
            e.fp_valid = p.decode.fp_valid;
            e.fp_illegal = p.decode.fp_illegal;
            e.fp_op = p.decode.fp_op;
            e.fp_rm = p.decode.fp_rm;
            e.fp_rs1_addr = p.decode.fp_rs1_addr;
            e.fp_rs2_addr = p.decode.fp_rs2_addr;
            e.fp_rs3_addr = p.decode.fp_rs3_addr;
            e.fp_rd_addr = p.decode.fp_rd_addr;
            e.fp_rs1_fpr = p.decode.fp_rs1_fpr;
            e.fp_rs2_fpr = p.decode.fp_rs2_fpr;
            e.fp_rs3_fpr = p.decode.fp_rs3_fpr;
            e.fp_rd_fpr = p.decode.fp_rd_fpr;
            e.fp_rd_gpr = p.decode.fp_rd_gpr;
            exec_from_pkt = e;
        end
    endfunction

    function automatic ydrasil_issue_pkt_t pkt_from_station(
        input issue_meta_t m, input issue_exec_t e, input logic valid
    );
        ydrasil_issue_pkt_t p;
        begin
            p = '0;
            p.valid = valid;
            p.memory_op = m.memory_op;
            p.lane_mask = {m.can_lane1, m.can_lane0};
            p.src0 = m.src0;
            p.src1 = m.src1;
            p.dst = m.dst;
            // Branch target arithmetic belongs to the BRU in EX.  These
            // legacy observability fields are not consumed by control.
            p.target = '0;
            p.next_pc = '0;
            p.ctrl.valid = valid;
            p.ctrl.rs1_addr = m.src0.arch_addr;
            p.ctrl.rs2_addr = m.src1.arch_addr;
            p.ctrl.rd_addr = m.dst.rd_addr;
            p.ctrl.rs1_ren = m.src0.used;
            p.ctrl.rs2_ren = m.src1.used;
            p.ctrl.rd_wen = m.dst.writes_gpr;
            p.ctrl.lsu_req = m.memory_op;
            p.ctrl.store_req = e.operator_type[OPERATOR_TYPE_STORE];
            p.ctrl.serialize_before = m.serial_before;
            p.ctrl.checkpoint_req = m.branch;
            p.decode.pc = e.pc;
            p.decode.instr = e.instr;
            p.decode.pred_hit = e.pred_hit;
            p.decode.pred_taken = e.pred_taken;
            p.decode.pred_target = e.pred_target;
            p.decode.pred_counter = e.pred_counter;
            p.decode.pred_bht_index = e.pred_bht_index;
            p.decode.imm = e.imm;
            p.decode.operand_b_rs_sel = e.operand_b_rs_sel;
            p.decode.operand_a_pc_sel = e.operand_a_pc_sel;
            p.decode.operand_a_imm_sel = e.operand_a_imm_sel;
            p.decode.bt_a_rs_sel = e.bt_a_rs_sel;
            p.decode.operand_b_jump_sel = e.operand_b_jump_sel;
            p.decode.operator_info = e.operator_info;
            p.decode.operator_type = e.operator_type;
            p.decode.operator_lsu = e.operator_lsu;
            p.decode.csr_raddr = e.csr_raddr;
            p.decode.csr_waddr = e.csr_waddr;
            p.decode.csr_op_info = e.csr_op_info;
            p.decode.sys_op_info = e.sys_op_info;
            p.decode.fence_i = e.fence_i;
            p.decode.fp_valid = e.fp_valid;
            p.decode.fp_illegal = e.fp_illegal;
            p.decode.fp_op = e.fp_op;
            p.decode.fp_rm = e.fp_rm;
            p.decode.fp_rs1_addr = e.fp_rs1_addr;
            p.decode.fp_rs2_addr = e.fp_rs2_addr;
            p.decode.fp_rs3_addr = e.fp_rs3_addr;
            p.decode.fp_rd_addr = e.fp_rd_addr;
            p.decode.fp_rs1_fpr = e.fp_rs1_fpr;
            p.decode.fp_rs2_fpr = e.fp_rs2_fpr;
            p.decode.fp_rs3_fpr = e.fp_rs3_fpr;
            p.decode.fp_rd_fpr = e.fp_rd_fpr;
            p.decode.fp_rd_gpr = e.fp_rd_gpr;
            pkt_from_station = p;
        end
    endfunction

    function automatic logic seq_before(
        input logic [SEQ_WIDTH-1:0] a, input logic [SEQ_WIDTH-1:0] b
    );
        logic [SEQ_WIDTH-1:0] distance;
        begin
            distance = b - a;
            seq_before = (a != b) && (distance < (1 << (SEQ_WIDTH - 1)));
        end
    endfunction

    function automatic logic bypassable_alu(
        input issue_meta_t m, input issue_exec_t e
    );
        begin
            // Keep the local path confined to the two single-cycle ALUs.
            // CSR, branch, LSU, MDU, bitmanip and FPU results retain their
            // normal registered completion semantics.
            bypassable_alu = m.dst.writes_gpr && !m.memory_op && !m.branch &&
                !m.serial_before && !e.fence_i &&
                e.operator_type[OPERATOR_TYPE_ALU] &&
                !e.operator_type[OPERATOR_TYPE_MUL] &&
                !e.operator_type[OPERATOR_TYPE_BITMANIP] &&
                !e.operator_type[OPERATOR_TYPE_FPU];
        end
    endfunction

    function automatic logic [1:0] forward_select_for(
        input ydrasil_source_desc_t src,
        input logic lane0_valid,
        input producer_id_t lane0_tag,
        input logic lane1_valid,
        input producer_id_t lane1_tag
    );
        begin
            forward_select_for = BYPASS_NONE;
            if (src.used && src.tag_valid &&
                (src.producer_class == RESULT_ALU)) begin
                if (lane0_valid && (src.producer_tag == lane0_tag))
                    forward_select_for = BYPASS_ALU0;
                else if (lane1_valid && (src.producer_tag == lane1_tag))
                    forward_select_for = BYPASS_ALU1;
            end
        end
    endfunction

    function automatic logic completion_hit(
        input ydrasil_source_desc_t src, input integer lane
    );
        begin
            completion_hit = src.used && src.tag_valid &&
                completion_bus_q[lane].valid &&
                completion_bus_q[lane].producer_tracked &&
                (completion_bus_q[lane].producer_id == src.producer_tag);
        end
    endfunction

    function automatic logic typed_completion_hit(input ydrasil_source_desc_t src);
        begin
            case (src.producer_class)
                RESULT_LSU: typed_completion_hit = completion_hit(src, COMPLETION_LSU);
                RESULT_MDU: typed_completion_hit = completion_hit(src, COMPLETION_MUL);
                default: typed_completion_hit = completion_hit(src, COMPLETION_ALU) ||
                    completion_hit(src, COMPLETION_DUAL_ALU);
            endcase
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] typed_completion_value(
        input ydrasil_source_desc_t src
    );
        begin
            case (src.producer_class)
                RESULT_LSU: typed_completion_value = completion_bus_q[COMPLETION_LSU].data;
                RESULT_MDU: typed_completion_value = completion_bus_q[COMPLETION_MUL].data;
                default: typed_completion_value = completion_hit(src, COMPLETION_ALU) ?
                    completion_bus_q[COMPLETION_ALU].data :
                    completion_bus_q[COMPLETION_DUAL_ALU].data;
            endcase
        end
    endfunction

    function automatic issue_admit_t admit_from_dispatch(
        input ydrasil_issue_pkt_t p,
        input ydrasil_rob_source_state_t state0,
        input ydrasil_rob_source_state_t state1,
        input logic [DATA_WIDTH-1:0] rf0,
        input logic [DATA_WIDTH-1:0] rf1,
        input logic [SEQ_WIDTH-1:0] seq
    );
        issue_admit_t a;
        begin
            a = '0;
            a.meta = meta_from_pkt(p);
            a.exec = exec_from_pkt(p);
            a.seq = seq;
            // Admission is a pure registered-state operation.  A completion
            // arriving this cycle is captured by the station at the edge,
            // rather than becoming an ID/RAT-to-issue combinational bypass.
            // Ctrl normalizes a token retiring at this boundary into an ARF
            // source. A remaining tag is therefore either a live completed
            // token or an unfinished dependency (including a same-bundle
            // producer which is allocated at this edge).
            a.ready0 = !p.src0.used || !p.src0.tag_valid ||
                (state0.live && state0.done);
            a.ready1 = !p.src1.used || !p.src1.tag_valid ||
                (state1.live && state1.done);
            a.value0 = rf0;
            a.value1 = rf1;
            if (p.src0.used && p.src0.tag_valid && state0.live && state0.done)
                a.value0 = state0.result;
            if (p.src1.used && p.src1.tag_valid && state1.live && state1.done)
                a.value1 = state1.result;
            // A newly admitted station is not in entry_valid_q yet, so the
            // resident-station wakeup loop cannot see a completion arriving
            // at this edge.  Capture that completion here into the same
            // station flops.  It influences only a later scheduler pass.
            if (typed_completion_hit(p.src0)) begin
                a.ready0 = 1'b1;
                a.value0 = typed_completion_value(p.src0);
            end
            if (typed_completion_hit(p.src1)) begin
                a.ready1 = 1'b1;
                a.value1 = typed_completion_value(p.src1);
            end
            admit_from_dispatch = a;
        end
    endfunction

    function automatic [N-1:0] first_one(input logic [N-1:0] bits);
        integer fi;
        logic found;
        begin
            first_one = '0;
            found = 1'b0;
            for (fi = 0; fi < N; fi = fi + 1)
                if (bits[fi] && !found) begin
                    first_one[fi] = 1'b1;
                    found = 1'b1;
                end
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] operand_a_for(
        input issue_exec_t e, input logic [DATA_WIDTH-1:0] src0
    );
        begin
            operand_a_for = e.operand_a_pc_sel ? e.pc :
                e.operand_a_imm_sel ? e.imm : src0;
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] operand_b_for(
        input issue_exec_t e, input logic [DATA_WIDTH-1:0] src1
    );
        begin
            operand_b_for = e.operand_b_jump_sel ? 32'd4 :
                e.operand_b_rs_sel ? src1 : e.imm;
        end
    endfunction

    reg [N-1:0] ready0_now, ready1_now;
    reg [N-1:0] oldest_any, issue_ok, strict_eligible, spec_eligible;
    reg [N-1:0] cand_lane0, cand_lane1;
    reg [N-1:0] select0, select1;
    integer si;
    wire select_enable = !stall_id_i && !bubble_id_i && !flush_id_i;

    // Scheduling reads only registered station state.  The age tag is not a
    // selector input: rank zero is registered when the station changes, then
    // a pair of fixed priority encoders chooses the two execution lanes.
    // Lane1 merely excludes lane0's selected slot; it has no slot0 data or
    // dependency input.
    always_comb begin
        oldest_any = '0;
        issue_ok = '0;
        strict_eligible = '0;
        spec_eligible = '0;
        cand_lane0 = '0;
        cand_lane1 = '0;
        ready0_now = '0;
        ready1_now = '0;
        select0 = '0;
        select1 = '0;

        for (si = 0; si < N; si = si + 1) begin
            if (entry_valid_q[si]) begin
                ready0_now[si] = ready0_q[si] ||
                    (station_meta_q[si].spec_safe &&
                     (forward_select_for(station_meta_q[si].src0,
                         bypass_lane0_valid_q, bypass_lane0_tag_q,
                         bypass_lane1_valid_q, bypass_lane1_tag_q) !=
                      BYPASS_NONE));
                ready1_now[si] = ready1_q[si] ||
                    (station_meta_q[si].spec_safe &&
                     (forward_select_for(station_meta_q[si].src1,
                         bypass_lane0_valid_q, bypass_lane0_tag_q,
                         bypass_lane1_valid_q, bypass_lane1_tag_q) !=
                      BYPASS_NONE));
                oldest_any[si] = (order_rank_q[si] == 2'd0);
                if (ready0_now[si] && ready1_now[si] &&
                    !(station_meta_q[si].memory_op && lsu_busy_q) &&
                    !(station_meta_q[si].serial_before &&
                      ((station_meta_q[si].dst.rob_tag != rob_head_tag_q) ||
                       !lsu_idle_q))) begin
                    issue_ok[si] = 1'b1;
                    strict_eligible[si] = oldest_any[si];
                    spec_eligible[si] = station_meta_q[si].spec_safe;
                    cand_lane0[si] = station_meta_q[si].can_lane0;
                    cand_lane1[si] = station_meta_q[si].can_lane1;
                end
            end
        end

        select0 = first_one(strict_eligible & cand_lane0);
        if (select0 == '0)
            select0 = first_one(spec_eligible & cand_lane0);

        select1 = first_one((strict_eligible & cand_lane1) & ~select0);
        if (select1 == '0)
            select1 = first_one((spec_eligible & cand_lane1) & ~select0);

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

    issue_meta_t selected_meta0, selected_meta1;
    issue_exec_t selected_exec0, selected_exec1;
    ydrasil_issue_pkt_t selected_uop0, selected_uop1;
    reg [DATA_WIDTH-1:0] selected_src00, selected_src01;
    reg [DATA_WIDTH-1:0] selected_src10, selected_src11;
    reg [1:0] selected_bypass00, selected_bypass01;
    reg [1:0] selected_bypass10, selected_bypass11;
    integer oi;
    always_comb begin
        selected_meta0 = '0;
        selected_meta1 = '0;
        selected_exec0 = '0;
        selected_exec1 = '0;
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
                selected_meta0 = station_meta_q[oi];
                selected_exec0 = station_exec_q[oi];
                selected_src00 = value0_q[oi];
                selected_src01 = value1_q[oi];
            end
            if (select1[oi]) begin
                selected_meta1 = station_meta_q[oi];
                selected_exec1 = station_exec_q[oi];
                selected_src10 = value0_q[oi];
                selected_src11 = value1_q[oi];
            end
        end
        selected_bypass00 = forward_select_for(selected_meta0.src0,
            bypass_lane0_valid_q, bypass_lane0_tag_q,
            bypass_lane1_valid_q, bypass_lane1_tag_q);
        selected_bypass01 = forward_select_for(selected_meta0.src1,
            bypass_lane0_valid_q, bypass_lane0_tag_q,
            bypass_lane1_valid_q, bypass_lane1_tag_q);
        selected_bypass10 = forward_select_for(selected_meta1.src0,
            bypass_lane0_valid_q, bypass_lane0_tag_q,
            bypass_lane1_valid_q, bypass_lane1_tag_q);
        selected_bypass11 = forward_select_for(selected_meta1.src1,
            bypass_lane0_valid_q, bypass_lane0_tag_q,
            bypass_lane1_valid_q, bypass_lane1_tag_q);
        selected_uop0 = pkt_from_station(selected_meta0, selected_exec0,
                                         selected_a_valid);
        selected_uop1 = pkt_from_station(selected_meta1, selected_exec1,
                                         selected_b_valid);
    end

    assign issue_pkt_o = selected_uop0;
    assign issue_pkt1_o = selected_uop1;
    assign issue_consume_two_o = selected_pair;
    assign issue_slot1_replay_o = 1'b0;

    reg [2:0] station_free_count;
    reg [2:0] recycle_free_count;
    integer capacity_i;
    always_comb begin
        station_free_count = '0;
        recycle_free_count = '0;
        for (capacity_i = 0; capacity_i < N; capacity_i = capacity_i + 1) begin
            if (!entry_valid_q[capacity_i])
                station_free_count = station_free_count + 1'b1;
            if (!entry_valid_q[capacity_i] || selected_remove[capacity_i])
                recycle_free_count = recycle_free_count + 1'b1;
        end
    end
    // `station_admit_slots` reports the local physical capacity after this
    // cycle's select. It is consumed only by the ingress-to-station transfer.
    // It must never drive upstream ID/RAT readiness in the same cycle.
    wire [1:0] station_admit_slots = (recycle_free_count > 3'd2) ?
        2'd2 : recycle_free_count[1:0];
    wire ingress_has_one_free = ingress_count_q < INGRESS_N;
    wire ingress_has_two_free = ingress_count_q <= (INGRESS_N - 2);
    wire issue_credit_reclaim = (station_free_count == 0) &&
        (station_admit_slots != 0);
    wire issue_credit_backpressure = !flush_id_i && !bubble_id_i &&
        (dispatch_pkt_i.valid || dispatch_pkt1_i.valid) &&
        !ingress_has_one_free;
    assign issue_ready_o = !flush_id_i && !bubble_id_i &&
        ingress_has_one_free;
    assign issue_dispatch_two_ready_o = !flush_id_i && !bubble_id_i &&
        ingress_has_two_free;
    assign issue_dispatch_ready_q_o = !flush_id_i && !bubble_id_i &&
        ingress_has_one_free;
    assign issue_dispatch_two_ready_q_o = !flush_id_i && !bubble_id_i &&
        ingress_has_two_free;

    reg [1:0] oldest_idx;
    reg oldest_found;
    integer oldest_i;
    always_comb begin
        oldest_idx = '0;
        oldest_found = 1'b0;
        for (oldest_i = 0; oldest_i < N; oldest_i = oldest_i + 1)
            if (oldest_any[oldest_i] && !oldest_found) begin
                oldest_idx = oldest_i[1:0];
                oldest_found = 1'b1;
            end
    end
    assign scoreboard_stall_o = oldest_found &&
        !(ready0_now[oldest_idx] && ready1_now[oldest_idx]);
    assign scoreboard_stall1_o = 1'b0;
    assign src0_wait_o = oldest_found && station_meta_q[oldest_idx].src0.used &&
        !ready0_now[oldest_idx];
    assign src1_wait_o = oldest_found && station_meta_q[oldest_idx].src1.used &&
        !ready1_now[oldest_idx];
    assign src2_wait_o = 1'b0;
    assign src3_wait_o = 1'b0;
    assign lsu_struct_stall_o = oldest_found && station_meta_q[oldest_idx].memory_op &&
        lsu_busy_q;
    assign lsu_struct_stall1_o = 1'b0;
    assign serialize_stall_o = oldest_found && station_meta_q[oldest_idx].serial_before &&
        ((station_meta_q[oldest_idx].dst.rob_tag != rob_head_tag_q) ||
         !lsu_idle_q);

    assign rf_addr_rs1_o = selected_meta0.src0.arch_addr;
    assign rf_addr_rs2_o = selected_meta0.src1.arch_addr;
    assign rf_addr_rs3_o = selected_meta1.src0.arch_addr;
    assign rf_addr_rs4_o = selected_meta1.src1.arch_addr;
    assign dispatch_rf_addr_rs1_o = dispatch_pkt_i.src0.arch_addr;
    assign dispatch_rf_addr_rs2_o = dispatch_pkt_i.src1.arch_addr;
    assign dispatch_rf_addr_rs3_o = dispatch_pkt1_i.src0.arch_addr;
    assign dispatch_rf_addr_rs4_o = dispatch_pkt1_i.src1.arch_addr;
    assign fpr_addr_rs1_o = selected_exec0.fp_rs1_addr;
    assign fpr_addr_rs2_o = selected_exec0.fp_rs2_addr;
    assign fpr_addr_rs3_o = selected_exec0.fp_rs3_addr;

    wire selected_sys = selected_a_valid &&
        selected_exec0.operator_type[OPERATOR_TYPE_SYS];
    wire selected_wfi = selected_sys && selected_exec0.sys_op_info[OP_SYS_WFI];
    wire selected_sys_trap = selected_sys && !selected_wfi;

    ydrasil_issue_ex_pkt_t issue_ex_d, issue_ex_q;
    always_comb begin
        issue_ex_d = '0;
        issue_ex_d.valid = selected_a_valid && !selected_sys;
        issue_ex_d.operand_a = operand_a_for(selected_exec0, selected_src00);
        issue_ex_d.operand_b = operand_b_for(selected_exec0, selected_src01);
        issue_ex_d.operand_a_forward_sel =
            (selected_exec0.operand_a_pc_sel || selected_exec0.operand_a_imm_sel) ?
            BYPASS_NONE : selected_bypass00;
        issue_ex_d.operand_b_forward_sel = selected_exec0.operand_b_rs_sel ?
            selected_bypass01 : BYPASS_NONE;
        issue_ex_d.operator_info = selected_exec0.operator_info;
        issue_ex_d.operator_type = selected_exec0.operator_type;
        issue_ex_d.jalr = selected_exec0.bt_a_rs_sel;
        // Lane 0 never owns BRU work. Keep branch arithmetic out of the
        // Issue/EX input mux rather than evaluating it for every lane-0 uop.
        issue_ex_d.branch_target = '0;
        issue_ex_d.branch_next_pc = '0;
        issue_ex_d.bt_a_operand = selected_exec0.bt_a_rs_sel ?
            selected_src00 : selected_exec0.pc;
        issue_ex_d.bt_b_operand = selected_src01;
        issue_ex_d.pred_hit = selected_exec0.pred_hit;
        issue_ex_d.pred_taken = selected_exec0.pred_taken;
        issue_ex_d.pred_target = selected_exec0.pred_target;
        issue_ex_d.pred_counter = selected_exec0.pred_counter;
        issue_ex_d.pred_bht_index = selected_exec0.pred_bht_index;
        issue_ex_d.csr_raddr = selected_exec0.csr_raddr;
        issue_ex_d.csr_waddr = selected_exec0.csr_waddr;
        issue_ex_d.csr_op_info = selected_exec0.csr_op_info;
        issue_ex_d.sys_op_info = selected_exec0.sys_op_info;
        issue_ex_d.pc = selected_exec0.pc;
        issue_ex_d.rd_wen = selected_a_valid && selected_meta0.dst.writes_gpr;
        issue_ex_d.rd_addr = selected_meta0.dst.rd_addr;
        issue_ex_d.producer_id = selected_meta0.dst.rob_tag;
        issue_ex_d.producer_tracked = selected_a_valid;
        issue_ex_d.lsu_req.valid = selected_a_valid && selected_meta0.memory_op;
        issue_ex_d.lsu_req.is_load = selected_exec0.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.is_store = selected_exec0.operator_type[OPERATOR_TYPE_STORE];
        issue_ex_d.lsu_req.op = selected_exec0.operator_lsu;
        issue_ex_d.lsu_req.rd_addr = selected_meta0.dst.rd_addr;
        issue_ex_d.lsu_req.producer_id = selected_meta0.dst.rob_tag;
        issue_ex_d.lsu_req.producer_tracked = selected_a_valid;
        issue_ex_d.lsu_req.store_data = selected_src01;
        issue_ex_d.lsu_req.store_data_valid = 1'b1;
        issue_ex_d.lsu_req.fp_load = selected_exec0.fp_valid &&
            selected_exec0.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.fp_rd_addr = selected_exec0.fp_rd_addr;
        issue_ex_d.fpu_req.valid = selected_a_valid && selected_exec0.fp_valid &&
            !selected_exec0.operator_type[OPERATOR_TYPE_LOAD] &&
            !selected_exec0.operator_type[OPERATOR_TYPE_STORE];
        issue_ex_d.fpu_req.illegal = selected_exec0.fp_illegal;
        issue_ex_d.fpu_req.op = selected_exec0.fp_op;
        issue_ex_d.fpu_req.rm = selected_exec0.fp_rm;
        issue_ex_d.fpu_req.operand_a = selected_exec0.fp_rs1_fpr ?
            fpr_rdata_rs1_i : selected_src00;
        issue_ex_d.fpu_req.operand_b = fpr_rdata_rs2_i;
        issue_ex_d.fpu_req.operand_c = fpr_rdata_rs3_i;
        issue_ex_d.fpu_req.rd_addr = selected_meta0.dst.rd_addr;
        issue_ex_d.fpu_req.rd_fpr = selected_exec0.fp_rd_fpr;
        issue_ex_d.fpu_req.rd_gpr = selected_exec0.fp_rd_gpr;
        issue_ex_d.fpu_req.producer_id = selected_meta0.dst.rob_tag;
        issue_ex_d.fpu_req.producer_tracked = selected_a_valid;
        issue_ex_d.fpu_req.pc = selected_exec0.pc;
        issue_ex_d.fpu_req.instr = selected_exec0.instr;
        issue_ex_d.lane1_valid = selected_b_valid;
        issue_ex_d.lane1_operand_a = operand_a_for(selected_exec1, selected_src10);
        issue_ex_d.lane1_operand_b = operand_b_for(selected_exec1, selected_src11);
        issue_ex_d.lane1_operand_a_forward_sel =
            (selected_exec1.operand_a_pc_sel || selected_exec1.operand_a_imm_sel) ?
            BYPASS_NONE : selected_bypass10;
        issue_ex_d.lane1_operand_b_forward_sel = selected_exec1.operand_b_rs_sel ?
            selected_bypass11 : BYPASS_NONE;
        issue_ex_d.lane1_branch_operand_a = selected_src10;
        issue_ex_d.lane1_branch_operand_b = selected_src11;
        issue_ex_d.lane1_branch_imm = selected_exec1.imm;
        issue_ex_d.lane1_operator_info = selected_exec1.operator_info;
        issue_ex_d.lane1_operator_type = selected_exec1.operator_type;
        issue_ex_d.lane1_operator_lsu = selected_exec1.operator_lsu;
        issue_ex_d.lane1_store_data = selected_src11;
        issue_ex_d.lane1_store_data_valid = 1'b1;
        issue_ex_d.lane1_rd_addr = selected_meta1.dst.rd_addr;
        issue_ex_d.lane1_rd_wen = selected_b_valid && selected_meta1.dst.writes_gpr;
        issue_ex_d.lane1_producer_id = selected_meta1.dst.rob_tag;
        issue_ex_d.lane1_producer_tracked = selected_b_valid;
        issue_ex_d.lane1_pc = selected_exec1.pc;
        issue_ex_d.lane1_instr = selected_exec1.instr;
        issue_ex_d.lane1_jalr = selected_exec1.bt_a_rs_sel;
        // Lane 1 transports PC and immediate separately; EX/BRU computes
        // target and fall-through inside its own timing boundary.
        issue_ex_d.lane1_branch_target = '0;
        issue_ex_d.lane1_branch_next_pc = '0;
        issue_ex_d.lane1_pred_hit = selected_exec1.pred_hit;
        issue_ex_d.lane1_pred_taken = selected_exec1.pred_taken;
        issue_ex_d.lane1_pred_target = selected_exec1.pred_target;
        issue_ex_d.lane1_pred_counter = selected_exec1.pred_counter;
        issue_ex_d.lane1_pred_bht_index = selected_exec1.pred_bht_index;
        if (selected_a_valid && (selected_exec0.fence_i || selected_sys))
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

    issue_admit_t admit0, admit1;
    issue_admit_t ingress_admit0, ingress_admit1;
    reg [N-1:0] free_work;
    reg [N-1:0] allocate0, allocate1;
    reg registered_wakeup_event_r;
    reg registered_alu_wakeup_event_r;
    reg registered_lsu_wakeup_event_r;
    reg registered_mdu_wakeup_event_r;
    reg [2:0] survivor_count;
    reg [1:0] removed_before_rank;
    integer ai, ci, rank_i;
    reg accept0, accept1;
    reg ingress_pop0, ingress_pop1;

    // Station allocation consumes only a registered ingress record.  This is
    // the issue-side timing boundary: ID/rename/RF capture cannot enter the
    // station wakeup, rank, forwarding, or select equations in the same
    // cycle.
    always_comb begin
        // Defaults are explicit because this block owns several independent
        // state updates (station, ingress, forwarding and diagnostics).
        removed_before_rank = '0;
        bypass_lane0_valid_d = 1'b0;
        bypass_lane0_tag_d = '0;
        bypass_lane1_valid_d = 1'b0;
        bypass_lane1_tag_d = '0;
        free_work = '0;
        allocate0 = '0;
        allocate1 = '0;
        registered_wakeup_event_r = 1'b0;
        registered_alu_wakeup_event_r = 1'b0;
        registered_lsu_wakeup_event_r = 1'b0;
        registered_mdu_wakeup_event_r = 1'b0;
        next_seq_d = next_seq_q;
        admit0 = admit_from_dispatch(dispatch_pkt_i, dispatch_src0_state_i,
            dispatch_src1_state_i, dispatch_rf_rdata_rs1_i,
            dispatch_rf_rdata_rs2_i, next_seq_q);
        admit1 = admit_from_dispatch(dispatch_pkt1_i, dispatch_src2_state_i,
            dispatch_src3_state_i, dispatch_rf_rdata_rs3_i,
            dispatch_rf_rdata_rs4_i, next_seq_q + 1'b1);
        accept0 = dispatch_accept_i && dispatch_pkt_i.valid &&
            ingress_has_one_free && !flush_id_i;
        accept1 = dispatch_accept1_i && dispatch_pkt1_i.valid && accept0 &&
            ingress_has_two_free;
        ingress_admit0 = ingress_q[ingress_head_q];
        ingress_admit1 = ingress_q[ingress_head_q + 1'b1];
        ingress_pop0 = (ingress_count_q != 0) &&
            (station_admit_slots != 0);
        ingress_pop1 = (ingress_count_q > 1) &&
            (station_admit_slots == 2'd2);

        entry_valid_d = entry_valid_q & ~selected_remove;
        survivor_count = '0;
        for (ai = 0; ai < N; ai = ai + 1) begin
            station_meta_d[ai] = station_meta_q[ai];
            station_exec_d[ai] = station_exec_q[ai];
            age_d[ai] = age_q[ai];
            order_rank_d[ai] = order_rank_q[ai];
            ready0_d[ai] = ready0_q[ai];
            ready1_d[ai] = ready1_q[ai];
            value0_d[ai] = value0_q[ai];
            value1_d[ai] = value1_q[ai];
            if (entry_valid_q[ai] && !selected_remove[ai]) begin
                // Compact the resident order at the clock edge.  This logic
                // ends at rank flops; issue selection sees only rank_q==0.
                removed_before_rank = '0;
                for (rank_i = 0; rank_i < N; rank_i = rank_i + 1)
                    if (selected_remove[rank_i] &&
                        (order_rank_q[rank_i] < order_rank_q[ai]))
                        removed_before_rank = removed_before_rank + 1'b1;
                order_rank_d[ai] = order_rank_q[ai] - removed_before_rank;
                survivor_count = survivor_count + 1'b1;
            end
            if (entry_valid_q[ai] && !ready0_q[ai] &&
                typed_completion_hit(station_meta_q[ai].src0)) begin
                ready0_d[ai] = 1'b1;
                value0_d[ai] = typed_completion_value(station_meta_q[ai].src0);
            end
            if (entry_valid_q[ai] && !ready1_q[ai] &&
                typed_completion_hit(station_meta_q[ai].src1)) begin
                ready1_d[ai] = 1'b1;
                value1_d[ai] = typed_completion_value(station_meta_q[ai].src1);
            end
            if (selected_remove[ai]) begin
                station_meta_d[ai] = '0;
                station_exec_d[ai] = '0;
                age_d[ai] = '0;
                order_rank_d[ai] = '0;
                ready0_d[ai] = 1'b0;
                ready1_d[ai] = 1'b0;
                value0_d[ai] = '0;
                value1_d[ai] = '0;
            end
        end

        // One tag per EX ALU lane replaces the old fanout scan that wrote a
        // bypass bit into every resident station.  Consumers compare against
        // these registered tags in the following scheduler pass.
        bypass_lane0_valid_d = selected_a_valid &&
            bypassable_alu(selected_meta0, selected_exec0);
        bypass_lane0_tag_d = selected_meta0.dst.rob_tag;
        bypass_lane1_valid_d = selected_b_valid &&
            bypassable_alu(selected_meta1, selected_exec1);
        bypass_lane1_tag_d = selected_meta1.dst.rob_tag;

        free_work = ~entry_valid_q | selected_remove;
        allocate0 = '0;
        allocate1 = '0;
        if (ingress_pop0) begin
            allocate0 = first_one(free_work);
            free_work = free_work & ~allocate0;
        end
        if (ingress_pop1)
            allocate1 = first_one(free_work);

        for (ai = 0; ai < N; ai = ai + 1) begin
            if (allocate0[ai]) begin
                entry_valid_d[ai] = 1'b1;
                station_meta_d[ai] = ingress_admit0.meta;
                station_exec_d[ai] = ingress_admit0.exec;
                age_d[ai] = ingress_admit0.seq;
                order_rank_d[ai] = survivor_count[1:0];
                ready0_d[ai] = ingress_admit0.ready0 ||
                    typed_completion_hit(ingress_admit0.meta.src0);
                ready1_d[ai] = ingress_admit0.ready1 ||
                    typed_completion_hit(ingress_admit0.meta.src1);
                value0_d[ai] = typed_completion_hit(ingress_admit0.meta.src0) ?
                    typed_completion_value(ingress_admit0.meta.src0) :
                    ingress_admit0.value0;
                value1_d[ai] = typed_completion_hit(ingress_admit0.meta.src1) ?
                    typed_completion_value(ingress_admit0.meta.src1) :
                    ingress_admit0.value1;
            end
            if (allocate1[ai]) begin
                entry_valid_d[ai] = 1'b1;
                station_meta_d[ai] = ingress_admit1.meta;
                station_exec_d[ai] = ingress_admit1.exec;
                age_d[ai] = ingress_admit1.seq;
                order_rank_d[ai] = survivor_count[1:0] + 1'b1;
                ready0_d[ai] = ingress_admit1.ready0 ||
                    typed_completion_hit(ingress_admit1.meta.src0);
                ready1_d[ai] = ingress_admit1.ready1 ||
                    typed_completion_hit(ingress_admit1.meta.src1);
                value0_d[ai] = typed_completion_hit(ingress_admit1.meta.src0) ?
                    typed_completion_value(ingress_admit1.meta.src0) :
                    ingress_admit1.value0;
                value1_d[ai] = typed_completion_hit(ingress_admit1.meta.src1) ?
                    typed_completion_value(ingress_admit1.meta.src1) :
                    ingress_admit1.value1;
            end
        end

        registered_wakeup_event_r = 1'b0;
        registered_alu_wakeup_event_r = 1'b0;
        registered_lsu_wakeup_event_r = 1'b0;
        registered_mdu_wakeup_event_r = 1'b0;
        for (ci = 0; ci < N; ci = ci + 1) begin
            if (entry_valid_q[ci] &&
                ((!ready0_q[ci] && typed_completion_hit(station_meta_q[ci].src0)) ||
                 (!ready1_q[ci] && typed_completion_hit(station_meta_q[ci].src1)))) begin
                registered_wakeup_event_r = 1'b1;
                if ((station_meta_q[ci].src0.producer_class == RESULT_LSU &&
                     typed_completion_hit(station_meta_q[ci].src0)) ||
                    (station_meta_q[ci].src1.producer_class == RESULT_LSU &&
                     typed_completion_hit(station_meta_q[ci].src1)))
                    registered_lsu_wakeup_event_r = 1'b1;
                else if ((station_meta_q[ci].src0.producer_class == RESULT_MDU &&
                          typed_completion_hit(station_meta_q[ci].src0)) ||
                         (station_meta_q[ci].src1.producer_class == RESULT_MDU &&
                          typed_completion_hit(station_meta_q[ci].src1)))
                    registered_mdu_wakeup_event_r = 1'b1;
                else
                    registered_alu_wakeup_event_r = 1'b1;
            end
        end
        next_seq_d = next_seq_q + accept0 + accept1;
    end

    integer qi;
    integer completion_lane_i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_id_i) begin
            entry_valid_q <= '0;
            next_seq_q <= '0;
            rob_head_tag_q <= '0;
            lsu_busy_q <= 1'b0;
            lsu_idle_q <= 1'b1;
            ingress_count_q <= '0;
            ingress_head_q <= '0;
            ingress_tail_q <= '0;
            bypass_lane0_valid_q <= 1'b0;
            bypass_lane0_tag_q <= '0;
            bypass_lane1_valid_q <= 1'b0;
            bypass_lane1_tag_q <= '0;
            issue_ex_q <= '0;
            issue_fence_q <= 1'b0;
            issue_fence_tag_q <= '0;
            issue_fence_next_pc_q <= '0;
            issue_sys_req_q <= '0;
            issue_sys_complete_q <= 1'b0;
            issue_sys_tag_q <= '0;
            for (completion_lane_i = 0;
                 completion_lane_i < COMPLETION_LANES;
                 completion_lane_i = completion_lane_i + 1)
                completion_bus_q[completion_lane_i] <= '0;
            for (qi = 0; qi < N; qi = qi + 1) begin
                station_meta_q[qi] <= '0;
                station_exec_q[qi] <= '0;
                age_q[qi] <= '0;
                order_rank_q[qi] <= '0;
                ready0_q[qi] <= 1'b0;
                ready1_q[qi] <= 1'b0;
                value0_q[qi] <= '0;
                value1_q[qi] <= '0;
                ingress_q[qi] <= '0;
            end
        end else begin
            entry_valid_q <= entry_valid_d;
            next_seq_q <= next_seq_d;
            rob_head_tag_q <= rob_head_tag_i;
            // This FF is the LSU-to-issue admission boundary.  The LSU has
            // queue headroom for requests already travelling through
            // Issue/EX and AGU while this status sample returns.
            lsu_busy_q <= lsu_status_i.busy;
            lsu_idle_q <= lsu_status_i.idle;
            for (completion_lane_i = 0;
                 completion_lane_i < COMPLETION_LANES;
                 completion_lane_i = completion_lane_i + 1)
                completion_bus_q[completion_lane_i] <=
                    completion_bus_i[completion_lane_i];
            if (ingress_pop1)
                ingress_head_q <= ingress_head_q + 2'd2;
            else if (ingress_pop0)
                ingress_head_q <= ingress_head_q + 1'b1;
            // An ingress record can wait while older station work drains.
            // Keep its dynamic operands live by capturing completion into the
            // ring itself; otherwise a producer that completes before this
            // record reaches the station would leave a stale wait bit.
            for (qi = 0; qi < INGRESS_N; qi = qi + 1) begin
                if (!ingress_q[qi].ready0 &&
                    typed_completion_hit(ingress_q[qi].meta.src0)) begin
                    ingress_q[qi].ready0 <= 1'b1;
                    ingress_q[qi].value0 <=
                        typed_completion_value(ingress_q[qi].meta.src0);
                end
                if (!ingress_q[qi].ready1 &&
                    typed_completion_hit(ingress_q[qi].meta.src1)) begin
                    ingress_q[qi].ready1 <= 1'b1;
                    ingress_q[qi].value1 <=
                        typed_completion_value(ingress_q[qi].meta.src1);
                end
            end
            if (accept0)
                ingress_q[ingress_tail_q] <= admit0;
            if (accept1)
                ingress_q[ingress_tail_q + 1'b1] <= admit1;
            if (accept1)
                ingress_tail_q <= ingress_tail_q + 2'd2;
            else if (accept0)
                ingress_tail_q <= ingress_tail_q + 1'b1;
            ingress_count_q <= ingress_count_q + accept0 + accept1 -
                ingress_pop0 - ingress_pop1;
            bypass_lane0_valid_q <= bypass_lane0_valid_d;
            bypass_lane0_tag_q <= bypass_lane0_tag_d;
            bypass_lane1_valid_q <= bypass_lane1_valid_d;
            bypass_lane1_tag_q <= bypass_lane1_tag_d;
            for (qi = 0; qi < N; qi = qi + 1) begin
                station_meta_q[qi] <= station_meta_d[qi];
                station_exec_q[qi] <= station_exec_d[qi];
                age_q[qi] <= age_d[qi];
                order_rank_q[qi] <= order_rank_d[qi];
                ready0_q[qi] <= ready0_d[qi];
                ready1_q[qi] <= ready1_d[qi];
                value0_q[qi] <= value0_d[qi];
                value1_q[qi] <= value1_d[qi];
            end

            issue_fence_q <= selected_a_valid && selected_exec0.fence_i;
            issue_sys_req_q <= '0;
            issue_sys_complete_q <= 1'b0;
            issue_sys_tag_q <= '0;
            if (selected_a_valid && selected_exec0.fence_i) begin
                issue_fence_tag_q <= selected_meta0.dst.rob_tag;
                issue_fence_next_pc_q <= selected_exec0.pc + 32'd4;
            end
            if (selected_wfi) begin
                issue_sys_complete_q <= 1'b1;
                issue_sys_tag_q <= selected_meta0.dst.rob_tag;
            end
            if (selected_sys_trap) begin
                issue_sys_req_q.valid <= 1'b1;
                issue_sys_req_q.ecall <= selected_exec0.sys_op_info[OP_SYS_ECALL];
                issue_sys_req_q.ebreak <= selected_exec0.sys_op_info[OP_SYS_EBREAK];
                issue_sys_req_q.mret <= selected_exec0.sys_op_info[OP_SYS_MRET];
                issue_sys_req_q.illegal <= !(selected_exec0.sys_op_info[OP_SYS_ECALL] ||
                    selected_exec0.sys_op_info[OP_SYS_EBREAK] ||
                    selected_exec0.sys_op_info[OP_SYS_MRET]);
                issue_sys_req_q.pc <= selected_exec0.pc;
                issue_sys_req_q.tval <= selected_exec0.instr;
                issue_sys_tag_q <= selected_meta0.dst.rob_tag;
            end
            if (!stall_id_i)
                issue_ex_q <= bubble_id_i ? '0 : issue_ex_d;
        end
    end
    assign issue_ex_o = issue_ex_q;

`ifndef SYNTHESIS
    integer inv_i;
    integer inv_q_count, inv_d_count;
    always_ff @(posedge clk) begin
        if (rst_n && !flush_id_i) begin
            inv_q_count = 0;
            inv_d_count = 0;
            for (inv_i = 0; inv_i < N; inv_i = inv_i + 1) begin
                inv_q_count = inv_q_count + entry_valid_q[inv_i];
                inv_d_count = inv_d_count + entry_valid_d[inv_i];
            end
            assert (inv_d_count == inv_q_count + ingress_pop0 + ingress_pop1 -
                    selected_a_valid - selected_b_valid)
                else $fatal(1, "compact issue conservation failed");
            assert (!(issue_ex_q.valid && issue_ex_q.operator_type[OPERATOR_TYPE_SYS]))
                else $fatal(1, "SYSTEM must terminate in issue");
        end
    end

    // These names are sampled only by the simulation performance harness.
    // They retain a stable diagnostic contract without changing synthesized
    // behavior.
    wire issue_valid_ff = selected_valid;
    wire id_advance = selected_valid && select_enable;
    wire [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff = selected_a_valid ?
        selected_exec0.operator_type : selected_exec1.operator_type;
    wire rs1_completion_fwd = selected_a_valid &&
        (selected_bypass00 != BYPASS_NONE);
    wire rs2_completion_fwd = selected_a_valid &&
        (selected_bypass01 != BYPASS_NONE);
    wire rs1_issue_early_alu_fwd = 1'b0;
    wire rs2_issue_early_alu_fwd = 1'b0;
    wire issue_early_alu_valid_ff = 1'b0;
    wire [3:0] issue_early_kind_ff = '0;
    wire [REGS_ADDR_WIDTH-1:0] issue_early_alu_addr_ff = '0;
    wire issue_simple_alu_op = 1'b0;
    wire issue_plain_alu_op = selected_valid &&
        issue_operator_type_ff[OPERATOR_TYPE_ALU];
    wire bypass_consumed_event = (selected_a_valid &&
        ((selected_bypass00 != BYPASS_NONE) ||
         (selected_bypass01 != BYPASS_NONE))) ||
        (selected_b_valid &&
        ((selected_bypass10 != BYPASS_NONE) ||
         (selected_bypass11 != BYPASS_NONE)));
    wire scheduled_bypass_event = bypass_lane0_valid_d ||
        bypass_lane1_valid_d;
    wire reserved_bypass_plan_event = 1'b0;
    wire reserved_bypass_issue_event = 1'b0;
    wire reserved_bypass_cancel_event = 1'b0;
    wire registered_wakeup_event = registered_wakeup_event_r;
    wire registered_alu_wakeup_event = registered_alu_wakeup_event_r;
    wire registered_lsu_wakeup_event = registered_lsu_wakeup_event_r;
    wire registered_mdu_wakeup_event = registered_mdu_wakeup_event_r;
    wire completion_latency_event = registered_wakeup_event_r;
`endif
endmodule
