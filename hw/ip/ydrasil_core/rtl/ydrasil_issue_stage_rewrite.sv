// FPGA-oriented issue window.
//
// The scheduler state is intentionally split into two planes:
//   * a small event/ready matrix in flip-flops (one bit per source), and
//   * one XPM distributed-RAM context store per bank.
//
// Four banks with four slots each bound the selector fanout.  A bank exports
// one winner for each execution side and the global selector only compares
// those eight winners.  There is no window-wide payload copy, age matrix, or
// completion CAM.
module ydrasil_issue_window
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        stall_id_i,
    input  wire                        bubble_id_i,
    input  wire                        flush_id_i,
    input  wire [PRODUCER_NUM-1:0]     redirect_keep_mask_i,
    input  wire [PRODUCER_NUM-1:0]     redirect_keep_epoch_i,
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
    // The completion bus is intentionally a one-cycle event.  This
    // directory supplies the rare recovery path for an event that completed
    // on the same boundary as an IQ allocation: once that producer retires,
    // its value is architecturally visible through the normal RF read port.
    input  wire [PRODUCER_NUM-1:0]      producer_live_mask_i,
    input  wire [PRODUCER_NUM-1:0]      producer_live_epoch_i,
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
    output wire                        issue_sys_complete_o,
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
    output ydrasil_lsu_reserve_pkt_t   lsu_reserve_o,
    // One-cycle token for the current Issue/EX contents.  The AGU uses it to
    // keep its reservation-to-request pipeline one-to-one when a long
    // latency unit holds the Issue/EX payload.
    output wire                        issue_ex_execute_o,
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
    localparam int N = ISSUE_WINDOW_DEPTH;
    localparam int BANKS = ISSUE_BANK_COUNT;
    localparam int BANK_DEPTH = N / BANKS;
    localparam int SLOT_W = $clog2(BANK_DEPTH);
    localparam int BANK_W = $clog2(BANKS);
    localparam int AGE_W = 8;
    localparam logic [AGE_W-1:0] AGE_HALF_RANGE =
        AGE_W'(1 << (AGE_W - 1));
    localparam int CTX_W = $bits(ydrasil_issue_pkt_t);

    // The only window-wide valid state is this bit matrix.  Payload and
    // decoder context live in the four distributed RAM instances below.
    logic [N-1:0] entry_valid_q;
    logic [N-1:0] entry_valid_d;
    logic [N-1:0] ready0_q, ready1_q;
    logic [N-1:0] ready0_d, ready1_d;
    ydrasil_source_desc_t src0_q [0:N-1];
    ydrasil_source_desc_t src1_q [0:N-1];
    ydrasil_dest_desc_t   dst_q  [0:N-1];
    logic [DATA_WIDTH-1:0] value0_q [0:N-1];
    logic [DATA_WIDTH-1:0] value1_q [0:N-1];
    logic [AGE_W-1:0] age_q [0:N-1];
    logic [AGE_W-1:0] age_d [0:N-1];
    logic [AGE_W-1:0] next_age_q;
    logic memory_q [0:N-1];
    logic store_q [0:N-1];
    logic serial_q [0:N-1];
    logic branch_q [0:N-1];
    logic can0_q [0:N-1];
    logic can1_q [0:N-1];
    logic [RESOURCE_WIDTH-1:0] resources_q [0:N-1];
    logic [OPERATOR_TYPE_WIDTH-1:0] op_type_q [0:N-1];

    logic [CTX_W-1:0] ctx_rdata [0:BANKS-1];
    logic [CTX_W-1:0] ctx_wdata [0:BANKS-1];
    logic [SLOT_W-1:0] ctx_raddr [0:BANKS-1];
    logic [SLOT_W-1:0] ctx_waddr [0:BANKS-1];
    logic ctx_wen [0:BANKS-1];
    ydrasil_issue_pkt_t ctx_pkt [0:BANKS-1];

    genvar gb;
    generate
        for (gb = 0; gb < BANKS; gb = gb + 1) begin : g_context_ram
            xpm_lutram_1r1w #(
                .DEPTH(BANK_DEPTH),
                .DATA_WIDTH(CTX_W),
                .ADDR_WIDTH(SLOT_W),
                .READ_LATENCY(0)
            ) u_context (
                .clk(clk), .ren_i(1'b1), .raddr_i(ctx_raddr[gb]),
                .rdata_o(ctx_rdata[gb]), .wen_i(ctx_wen[gb]),
                .waddr_i(ctx_waddr[gb]), .wdata_i(ctx_wdata[gb])
            );
            assign ctx_pkt[gb] = ctx_rdata[gb];
        end
    endgenerate

    // Completion is converted into a typed event matrix.  Each producer slot
    // is written once per class, then every source performs one indexed lookup
    // instead of comparing against all completion lanes.
    logic [N-1:0] event_alu_valid, event_lsu_valid, event_mul_valid;
    logic [N-1:0] event_alu_epoch, event_lsu_epoch, event_mul_epoch;
    logic [DATA_WIDTH-1:0] event_alu_data [0:N-1];
    logic [DATA_WIDTH-1:0] event_lsu_data [0:N-1];
    logic [DATA_WIDTH-1:0] event_mul_data [0:N-1];
    ydrasil_completion_bus_t completion_bus_q;
    integer ei, el;
    always_comb begin
        event_alu_valid = '0;
        event_lsu_valid = '0;
        event_mul_valid = '0;
        event_alu_epoch = '0;
        event_lsu_epoch = '0;
        event_mul_epoch = '0;
        for (ei = 0; ei < N; ei = ei + 1) begin
            event_alu_data[ei] = '0;
            event_lsu_data[ei] = '0;
            event_mul_data[ei] = '0;
        end
        for (el = 0; el < COMPLETION_LANES; el = el + 1) begin
            if (completion_bus_q[el].valid &&
                completion_bus_q[el].producer_tracked) begin
                if (el == COMPLETION_LSU) begin
                    event_lsu_valid[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
                    event_lsu_epoch[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = completion_bus_q[el].producer_id[PRODUCER_ID_WIDTH-1];
                    event_lsu_data[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = completion_bus_q[el].data;
                end else if (el == COMPLETION_MUL) begin
                    event_mul_valid[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
                    event_mul_epoch[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = completion_bus_q[el].producer_id[PRODUCER_ID_WIDTH-1];
                    event_mul_data[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = completion_bus_q[el].data;
                end else begin
                    event_alu_valid[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
                    event_alu_epoch[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = completion_bus_q[el].producer_id[PRODUCER_ID_WIDTH-1];
                    event_alu_data[completion_bus_q[el].producer_id[PRODUCER_SLOT_WIDTH-1:0]] = completion_bus_q[el].data;
                end
            end
        end
    end

    logic [N-1:0] ready0_now, ready1_now;
    logic [N-1:0] source0_architected, source1_architected;
    logic [N-1:0] eligible;
    logic [N-1:0] bank_best0_valid, bank_best1_valid;
    integer bank_best0_idx [0:BANKS-1];
    integer bank_best1_idx [0:BANKS-1];
    logic [BANKS-1:0] bank_oldest_memory_valid;
    integer bank_oldest_memory_idx [0:BANKS-1];
    logic oldest_memory_valid;
    integer oldest_memory_idx;
    integer bi, bj, si, sj;
    integer selected_idx0, selected_idx1;
    logic selected_a_valid, selected_b_valid, selected_valid;
    logic selected_pair;
    logic [N-1:0] select0, select1;
    logic [BANK_W-1:0] selected_bank0, selected_bank1;
    logic [N-1:0] selected_remove;
    logic pair_ok;
    wire issue_fire = selected_valid && !stall_id_i && !bubble_id_i &&
        !flush_id_i;

    // Source wakeup and bank-local eligibility.  Store/load ordering is
    // represented by the LSU's architectural head gate; no older-store x
    // load matrix is built in the issue stage.
    always_comb begin
        ready0_now = ready0_q;
        ready1_now = ready1_q;
        source0_architected = '0;
        source1_architected = '0;
        eligible = '0;

        // A memory uop cannot overtake an older memory uop that is still in
        // the window.  The LSU sees requests only after the Issue/EX and AGU
        // stages, so letting a younger load leave first would hide an older
        // unresolved store from the LSU's forwarding/order state.  This is a
        // banked oldest-entry reduction, not an N-by-N dependency matrix.
        bank_oldest_memory_valid = '0;
        for (bi = 0; bi < BANKS; bi = bi + 1) begin
            bank_oldest_memory_idx[bi] = bi * BANK_DEPTH;
            for (bj = 0; bj < BANK_DEPTH; bj = bj + 1) begin
                si = bi * BANK_DEPTH + bj;
                if (entry_valid_q[si] && memory_q[si] &&
                    (!bank_oldest_memory_valid[bi] ||
                     ((age_q[bank_oldest_memory_idx[bi]] - age_q[si]) <
                      AGE_HALF_RANGE))) begin
                    bank_oldest_memory_valid[bi] = 1'b1;
                    bank_oldest_memory_idx[bi] = si;
                end
            end
        end
        oldest_memory_valid = 1'b0;
        oldest_memory_idx = 0;
        for (bi = 0; bi < BANKS; bi = bi + 1) begin
            if (bank_oldest_memory_valid[bi] &&
                (!oldest_memory_valid ||
                 ((age_q[oldest_memory_idx] -
                   age_q[bank_oldest_memory_idx[bi]]) < AGE_HALF_RANGE))) begin
                oldest_memory_valid = 1'b1;
                oldest_memory_idx = bank_oldest_memory_idx[bi];
            end
        end

        for (si = 0; si < N; si = si + 1) begin
            source0_architected[si] = entry_valid_q[si] &&
                src0_q[si].used && src0_q[si].tag_valid &&
                (!producer_live_mask_i[
                    src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] ||
                 producer_live_epoch_i[
                    src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] !=
                    src0_q[si].producer_tag[PRODUCER_ID_WIDTH-1]);
            source1_architected[si] = entry_valid_q[si] &&
                src1_q[si].used && src1_q[si].tag_valid &&
                (!producer_live_mask_i[
                    src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] ||
                 producer_live_epoch_i[
                    src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] !=
                    src1_q[si].producer_tag[PRODUCER_ID_WIDTH-1]);
            if (entry_valid_q[si] && !ready0_q[si] && src0_q[si].used && src0_q[si].tag_valid) begin
                if (source0_architected[si])
                    ready0_now[si] = 1'b1;
                else if ((src0_q[si].producer_class == RESULT_LSU && event_lsu_valid[src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_lsu_epoch[src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src0_q[si].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src0_q[si].producer_class == RESULT_MDU && event_mul_valid[src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_mul_epoch[src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src0_q[si].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src0_q[si].producer_class != RESULT_LSU && src0_q[si].producer_class != RESULT_MDU && event_alu_valid[src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_alu_epoch[src0_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src0_q[si].producer_tag[PRODUCER_ID_WIDTH-1]))
                    ready0_now[si] = 1'b1;
            end
            if (entry_valid_q[si] && !ready1_q[si] && src1_q[si].used && src1_q[si].tag_valid) begin
                if (source1_architected[si])
                    ready1_now[si] = 1'b1;
                else if ((src1_q[si].producer_class == RESULT_LSU && event_lsu_valid[src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_lsu_epoch[src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src1_q[si].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src1_q[si].producer_class == RESULT_MDU && event_mul_valid[src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_mul_epoch[src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src1_q[si].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src1_q[si].producer_class != RESULT_LSU && src1_q[si].producer_class != RESULT_MDU && event_alu_valid[src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_alu_epoch[src1_q[si].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src1_q[si].producer_tag[PRODUCER_ID_WIDTH-1]))
                    ready1_now[si] = 1'b1;
            end
            if (entry_valid_q[si] && ready0_now[si] && ready1_now[si] &&
                (!memory_q[si] ||
                 (oldest_memory_valid && si == oldest_memory_idx)) &&
                (!memory_q[si] || lsu_status_i.accept_ready ||
                 (lsu_status_i.head_accept_ready &&
                  dst_q[si].rob_tag == rob_head_tag_i)) &&
                (!serial_q[si] || dst_q[si].rob_tag == rob_head_tag_i))
                eligible[si] = 1'b1;
        end

        bank_best0_valid = '0;
        bank_best1_valid = '0;
        for (bi = 0; bi < BANKS; bi = bi + 1) begin
            bank_best0_idx[bi] = bi * BANK_DEPTH;
            bank_best1_idx[bi] = bi * BANK_DEPTH;
            for (bj = 0; bj < BANK_DEPTH; bj = bj + 1) begin
                si = bi * BANK_DEPTH + bj;
                if (eligible[si] && can0_q[si] &&
                    (!bank_best0_valid[bi] ||
                     ((age_q[bank_best0_idx[bi]] - age_q[si]) <
                      AGE_HALF_RANGE))) begin
                    bank_best0_valid[bi] = 1'b1;
                    bank_best0_idx[bi] = si;
                end
                if (eligible[si] && can1_q[si] &&
                    (!bank_best1_valid[bi] ||
                     ((age_q[bank_best1_idx[bi]] - age_q[si]) <
                      AGE_HALF_RANGE))) begin
                    bank_best1_valid[bi] = 1'b1;
                    bank_best1_idx[bi] = si;
                end
            end
        end

        selected_idx0 = 0;
        selected_idx1 = 0;
        selected_bank0 = '0;
        selected_bank1 = '0;
        selected_a_valid = 1'b0;
        selected_b_valid = 1'b0;
        pair_ok = 1'b1;
        // ALU/MDU/CSR/bit side gets first choice.  If it is empty, a BRU/AGU
        // winner becomes lane A.  The second winner is always from another
        // bank, which is the single-read-port contract of the context RAM.
        for (bi = 0; bi < BANKS; bi = bi + 1) begin
            if (bank_best0_valid[bi] &&
                (!selected_a_valid ||
                 ((age_q[selected_idx0] - age_q[bank_best0_idx[bi]]) <
                  AGE_HALF_RANGE))) begin
                selected_a_valid = 1'b1;
                selected_idx0 = bank_best0_idx[bi];
            end
        end
        if (!selected_a_valid) begin
            for (bi = 0; bi < BANKS; bi = bi + 1) begin
                if (bank_best1_valid[bi] &&
                    (!selected_b_valid ||
                     ((age_q[selected_idx1] - age_q[bank_best1_idx[bi]]) <
                      AGE_HALF_RANGE))) begin
                    selected_b_valid = 1'b1;
                    selected_idx1 = bank_best1_idx[bi];
                end
            end
        end else begin
            selected_bank0 = selected_idx0 / BANK_DEPTH;
            for (bi = 0; bi < BANKS; bi = bi + 1) begin
                if (bank_best1_valid[bi] && bi != selected_bank0 &&
                    (!selected_b_valid ||
                     ((age_q[selected_idx1] - age_q[bank_best1_idx[bi]]) <
                      AGE_HALF_RANGE))) begin
                    selected_b_valid = 1'b1;
                    selected_idx1 = bank_best1_idx[bi];
                end
            end
        end
        if (selected_a_valid && selected_b_valid) begin
            pair_ok = !(dst_q[selected_idx0].writes_gpr && src0_q[selected_idx1].tag_valid && src0_q[selected_idx1].producer_tag == dst_q[selected_idx0].rob_tag) &&
                      !(dst_q[selected_idx0].writes_gpr && src1_q[selected_idx1].tag_valid && src1_q[selected_idx1].producer_tag == dst_q[selected_idx0].rob_tag) &&
                      !((resources_q[selected_idx0] & resources_q[selected_idx1] & RESOURCE_EXCLUSIVE_MASK) != 0) &&
                      !((branch_q[selected_idx0] && memory_q[selected_idx1]) || (branch_q[selected_idx1] && memory_q[selected_idx0]));
            if (!pair_ok)
                selected_b_valid = 1'b0;
        end
        selected_bank1 = selected_idx1 / BANK_DEPTH;
        selected_valid = selected_a_valid || selected_b_valid;
        selected_pair = selected_a_valid && selected_b_valid;
        selected_remove = '0;
        select0 = '0;
        select1 = '0;
        if (issue_fire && selected_a_valid) selected_remove[selected_idx0] = 1'b1;
        if (issue_fire && selected_b_valid) selected_remove[selected_idx1] = 1'b1;
        if (selected_a_valid) select0[selected_idx0] = 1'b1;
        if (selected_b_valid) select1[selected_idx1] = 1'b1;
    end

    // Context RAM read addresses are selected winners only.  At most one read
    // is requested from each bank because the two issue lanes are bank-distinct.
    integer ri;
    always_comb begin
        for (ri = 0; ri < BANKS; ri = ri + 1) begin
            ctx_raddr[ri] = '0;
            if (selected_a_valid && selected_bank0 == ri)
                ctx_raddr[ri] = selected_idx0 % BANK_DEPTH;
            else if (selected_b_valid && selected_bank1 == ri)
                ctx_raddr[ri] = selected_idx1 % BANK_DEPTH;
        end
    end

    ydrasil_issue_pkt_t selected_pkt0, selected_pkt1;
    logic [DATA_WIDTH-1:0] selected_v00, selected_v01, selected_v10, selected_v11;
    // A completion stored in completion_bus_q makes a dependent entry
    // eligible in this cycle.  Feed that same event to EX as well: waiting
    // for value*_q to capture it would issue a newly-ready dependent with
    // the old operand value.
    always_comb begin
        selected_pkt0 = '0;
        selected_pkt1 = '0;
        selected_v00 = '0; selected_v01 = '0;
        selected_v10 = '0; selected_v11 = '0;
        if (selected_a_valid) begin
            selected_pkt0 = ctx_pkt[selected_bank0];
            selected_pkt0.valid = 1'b1;
            selected_v00 = value0_q[selected_idx0];
            selected_v01 = value1_q[selected_idx0];
            if (source0_architected[selected_idx0]) begin
                selected_v00 = rf_rdata_rs1_i;
            end else if (!ready0_q[selected_idx0] && ready0_now[selected_idx0]) begin
                if (src0_q[selected_idx0].producer_class == RESULT_LSU)
                    selected_v00 = event_lsu_data[src0_q[selected_idx0].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else if (src0_q[selected_idx0].producer_class == RESULT_MDU)
                    selected_v00 = event_mul_data[src0_q[selected_idx0].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else
                    selected_v00 = event_alu_data[src0_q[selected_idx0].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
            end
            if (source1_architected[selected_idx0]) begin
                selected_v01 = rf_rdata_rs2_i;
            end else if (!ready1_q[selected_idx0] && ready1_now[selected_idx0]) begin
                if (src1_q[selected_idx0].producer_class == RESULT_LSU)
                    selected_v01 = event_lsu_data[src1_q[selected_idx0].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else if (src1_q[selected_idx0].producer_class == RESULT_MDU)
                    selected_v01 = event_mul_data[src1_q[selected_idx0].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else
                    selected_v01 = event_alu_data[src1_q[selected_idx0].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
            end
        end
        if (selected_b_valid) begin
            selected_pkt1 = ctx_pkt[selected_bank1];
            selected_pkt1.valid = 1'b1;
            selected_v10 = value0_q[selected_idx1];
            selected_v11 = value1_q[selected_idx1];
            if (source0_architected[selected_idx1]) begin
                selected_v10 = rf_rdata_rs3_i;
            end else if (!ready0_q[selected_idx1] && ready0_now[selected_idx1]) begin
                if (src0_q[selected_idx1].producer_class == RESULT_LSU)
                    selected_v10 = event_lsu_data[src0_q[selected_idx1].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else if (src0_q[selected_idx1].producer_class == RESULT_MDU)
                    selected_v10 = event_mul_data[src0_q[selected_idx1].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else
                    selected_v10 = event_alu_data[src0_q[selected_idx1].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
            end
            if (source1_architected[selected_idx1]) begin
                selected_v11 = rf_rdata_rs4_i;
            end else if (!ready1_q[selected_idx1] && ready1_now[selected_idx1]) begin
                if (src1_q[selected_idx1].producer_class == RESULT_LSU)
                    selected_v11 = event_lsu_data[src1_q[selected_idx1].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else if (src1_q[selected_idx1].producer_class == RESULT_MDU)
                    selected_v11 = event_mul_data[src1_q[selected_idx1].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                else
                    selected_v11 = event_alu_data[src1_q[selected_idx1].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
            end
        end
    end
    assign issue_pkt_o = selected_pkt0;
    assign issue_pkt1_o = selected_pkt1;
    assign issue_consume_two_o = issue_fire && selected_a_valid &&
        selected_b_valid;
    assign issue_slot1_replay_o = 1'b0;

    always_comb begin
        lsu_reserve_o = '0;
        lsu_reserve_o.valid = issue_fire && selected_b_valid &&
            selected_pkt1.memory_op;
        lsu_reserve_o.producer_id = selected_pkt1.dst.rob_tag;
        lsu_reserve_o.producer_tracked = lsu_reserve_o.valid;
    end

    integer free_count, free_banks, ai, aj;
    logic [2:0] ingress_count_q;
    wire issue_credit_reclaim = (free_count == 0) && selected_valid;
    wire issue_credit_backpressure = (free_count == 0) &&
        (dispatch_pkt_i.valid || dispatch_pkt1_i.valid) && !flush_id_i;
    integer alloc_idx0, alloc_idx1, alloc_bank0, alloc_bank1;
    logic alloc_valid0, alloc_valid1;
    always_comb begin
        free_count = 0;
        free_banks = 0;
        alloc_idx0 = 0; alloc_idx1 = 0;
        alloc_bank0 = 0; alloc_bank1 = 0;
        alloc_valid0 = 1'b0; alloc_valid1 = 1'b0;
        for (ai = 0; ai < BANKS; ai = ai + 1) begin
            if (!(&entry_valid_q[ai*BANK_DEPTH +: BANK_DEPTH]))
                free_banks = free_banks + 1;
            for (aj = 0; aj < BANK_DEPTH; aj = aj + 1)
                if (!entry_valid_q[ai*BANK_DEPTH+aj]) free_count = free_count + 1;
        end
        for (ai = 0; ai < N; ai = ai + 1) begin
            if (!entry_valid_q[ai] && !alloc_valid0) begin
                alloc_valid0 = 1'b1;
                alloc_idx0 = ai;
                alloc_bank0 = ai / BANK_DEPTH;
            end
        end
        for (ai = 0; ai < N; ai = ai + 1) begin
            if (!entry_valid_q[ai] && !alloc_valid1 && (ai / BANK_DEPTH) != alloc_bank0) begin
                alloc_valid1 = 1'b1;
                alloc_idx1 = ai;
                alloc_bank1 = ai / BANK_DEPTH;
            end
        end
        alloc_valid0 = alloc_valid0 && dispatch_accept_i && dispatch_pkt_i.valid && !flush_id_i;
        alloc_valid1 = alloc_valid1 && dispatch_accept1_i && dispatch_pkt1_i.valid && !flush_id_i && alloc_valid0;
    end

    assign issue_dispatch_ready_q_o = !flush_id_i && !bubble_id_i && (free_count != 0);
    assign issue_dispatch_two_ready_q_o = !flush_id_i && !bubble_id_i && (free_banks >= 2);
    assign issue_ready_o = issue_dispatch_ready_q_o;
    assign issue_dispatch_two_ready_o = issue_dispatch_two_ready_q_o;
    assign scoreboard_stall_o = selected_valid ? 1'b0 : (free_count == 0);
    assign scoreboard_stall1_o = 1'b0;
    assign lsu_struct_stall_o = 1'b0;
    assign lsu_struct_stall1_o = 1'b0;
    assign serialize_stall_o = 1'b0;
    assign src0_wait_o = selected_a_valid && !ready0_now[selected_idx0];
    assign src1_wait_o = selected_a_valid && !ready1_now[selected_idx0];
    assign src2_wait_o = selected_b_valid && !ready0_now[selected_idx1];
    assign src3_wait_o = selected_b_valid && !ready1_now[selected_idx1];

    assign rf_addr_rs1_o = selected_a_valid ? src0_q[selected_idx0].arch_addr : '0;
    assign rf_addr_rs2_o = selected_a_valid ? src1_q[selected_idx0].arch_addr : '0;
    assign rf_addr_rs3_o = selected_b_valid ? src0_q[selected_idx1].arch_addr : '0;
    assign rf_addr_rs4_o = selected_b_valid ? src1_q[selected_idx1].arch_addr : '0;
    assign dispatch_rf_addr_rs1_o = dispatch_pkt_i.src0.arch_addr;
    assign dispatch_rf_addr_rs2_o = dispatch_pkt_i.src1.arch_addr;
    assign dispatch_rf_addr_rs3_o = dispatch_pkt1_i.src0.arch_addr;
    assign dispatch_rf_addr_rs4_o = dispatch_pkt1_i.src1.arch_addr;
    assign fpr_addr_rs1_o = selected_a_valid ? selected_pkt0.decode.fp_rs1_addr : '0;
    assign fpr_addr_rs2_o = selected_a_valid ? selected_pkt0.decode.fp_rs2_addr : '0;
    assign fpr_addr_rs3_o = selected_a_valid ? selected_pkt0.decode.fp_rs3_addr : '0;

    logic [DATA_WIDTH-1:0] op_a0, op_b0, op_a1, op_b1;
    ydrasil_issue_ex_pkt_t issue_ex_d, issue_ex_q;
    logic issue_ex_execute_q;
    always_comb begin
        op_a0 = selected_pkt0.decode.operand_a_pc_sel ? selected_pkt0.decode.pc :
                selected_pkt0.decode.operand_a_imm_sel ? selected_pkt0.decode.imm : selected_v00;
        op_b0 = selected_pkt0.decode.operand_b_jump_sel ? 32'd4 :
                selected_pkt0.decode.operand_b_rs_sel ? selected_v01 : selected_pkt0.decode.imm;
        op_a1 = selected_pkt1.decode.operand_a_pc_sel ? selected_pkt1.decode.pc :
                selected_pkt1.decode.operand_a_imm_sel ? selected_pkt1.decode.imm : selected_v10;
        op_b1 = selected_pkt1.decode.operand_b_jump_sel ? 32'd4 :
                selected_pkt1.decode.operand_b_rs_sel ? selected_v11 : selected_pkt1.decode.imm;
        issue_ex_d = '0;
        issue_ex_d.valid = selected_a_valid && !selected_pkt0.decode.operator_type[OPERATOR_TYPE_SYS] && !selected_pkt0.decode.fence_i;
        issue_ex_d.operand_a = op_a0;
        issue_ex_d.operand_b = op_b0;
        issue_ex_d.operator_info = selected_pkt0.decode.operator_info;
        issue_ex_d.operator_type = selected_pkt0.decode.operator_type;
        issue_ex_d.jalr = selected_pkt0.decode.bt_a_rs_sel;
        issue_ex_d.branch_target = selected_pkt0.target;
        issue_ex_d.branch_next_pc = selected_pkt0.next_pc;
        issue_ex_d.bt_a_operand = selected_pkt0.decode.bt_a_rs_sel ? selected_v00 : selected_pkt0.decode.pc;
        issue_ex_d.bt_b_operand = selected_v01;
        issue_ex_d.pred_hit = selected_pkt0.decode.pred_hit;
        issue_ex_d.pred_taken = selected_pkt0.decode.pred_taken;
        issue_ex_d.pred_target = selected_pkt0.decode.pred_target;
        issue_ex_d.pred_counter = selected_pkt0.decode.pred_counter;
        issue_ex_d.pred_bht_index = selected_pkt0.decode.pred_bht_index;
        issue_ex_d.csr_raddr = selected_pkt0.decode.csr_raddr;
        issue_ex_d.csr_waddr = selected_pkt0.decode.csr_waddr;
        issue_ex_d.csr_op_info = selected_pkt0.decode.csr_op_info;
        issue_ex_d.sys_op_info = selected_pkt0.decode.sys_op_info;
        issue_ex_d.pc = selected_pkt0.decode.pc;
        issue_ex_d.rd_wen = selected_a_valid && selected_pkt0.dst.writes_gpr;
        issue_ex_d.rd_addr = selected_pkt0.dst.rd_addr;
        issue_ex_d.producer_id = selected_pkt0.dst.rob_tag;
        issue_ex_d.producer_tracked = selected_a_valid;
        issue_ex_d.lsu_req.valid = selected_a_valid && selected_pkt0.memory_op;
        issue_ex_d.lsu_req.is_load = selected_pkt0.decode.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.is_store = selected_pkt0.decode.operator_type[OPERATOR_TYPE_STORE];
        issue_ex_d.lsu_req.op = selected_pkt0.decode.operator_lsu;
        issue_ex_d.lsu_req.store_data = selected_v01;
        issue_ex_d.lsu_req.store_data_valid = selected_a_valid;
        issue_ex_d.lsu_req.rd_addr = selected_pkt0.dst.rd_addr;
        issue_ex_d.lsu_req.producer_id = selected_pkt0.dst.rob_tag;
        issue_ex_d.lsu_req.producer_tracked = selected_a_valid;
        issue_ex_d.lsu_req.fp_load = selected_pkt0.decode.fp_valid && selected_pkt0.decode.operator_type[OPERATOR_TYPE_LOAD];
        issue_ex_d.lsu_req.fp_rd_addr = selected_pkt0.decode.fp_rd_addr;
        issue_ex_d.fpu_req.valid = selected_a_valid && selected_pkt0.decode.fp_valid && !selected_pkt0.memory_op;
        issue_ex_d.fpu_req.illegal = selected_pkt0.decode.fp_illegal;
        issue_ex_d.fpu_req.op = selected_pkt0.decode.fp_op;
        issue_ex_d.fpu_req.rm = selected_pkt0.decode.fp_rm;
        issue_ex_d.fpu_req.operand_a = selected_pkt0.decode.fp_rs1_fpr ? fpr_rdata_rs1_i : selected_v00;
        issue_ex_d.fpu_req.operand_b = selected_pkt0.decode.fp_rs2_fpr ? fpr_rdata_rs2_i : selected_v01;
        issue_ex_d.fpu_req.operand_c = selected_pkt0.decode.fp_rs3_fpr ? fpr_rdata_rs3_i : '0;
        issue_ex_d.fpu_req.rd_addr = selected_pkt0.decode.fp_rd_addr;
        issue_ex_d.fpu_req.rd_fpr = selected_pkt0.decode.fp_rd_fpr;
        issue_ex_d.fpu_req.rd_gpr = selected_pkt0.decode.fp_rd_gpr;
        issue_ex_d.fpu_req.producer_id = selected_pkt0.dst.rob_tag;
        issue_ex_d.fpu_req.producer_tracked = selected_a_valid;
        issue_ex_d.fpu_req.pc = selected_pkt0.decode.pc;
        issue_ex_d.fpu_req.instr = selected_pkt0.decode.instr;
        issue_ex_d.lane1_valid = selected_b_valid;
        issue_ex_d.lane1_operand_a = op_a1;
        issue_ex_d.lane1_operand_b = op_b1;
        issue_ex_d.lane1_branch_operand_a = selected_v10;
        issue_ex_d.lane1_branch_operand_b = selected_v11;
        issue_ex_d.lane1_branch_imm = selected_pkt1.decode.imm;
        issue_ex_d.lane1_operator_info = selected_pkt1.decode.operator_info;
        issue_ex_d.lane1_operator_type = selected_pkt1.decode.operator_type;
        issue_ex_d.lane1_operator_lsu = selected_pkt1.decode.operator_lsu;
        issue_ex_d.lane1_store_data = selected_v11;
        issue_ex_d.lane1_store_data_valid = selected_b_valid;
        issue_ex_d.lane1_rd_addr = selected_pkt1.dst.rd_addr;
        issue_ex_d.lane1_rd_wen = selected_b_valid && selected_pkt1.dst.writes_gpr;
        issue_ex_d.lane1_producer_id = selected_pkt1.dst.rob_tag;
        issue_ex_d.lane1_producer_tracked = selected_b_valid;
        issue_ex_d.lane1_pc = selected_pkt1.decode.pc;
        issue_ex_d.lane1_instr = selected_pkt1.decode.instr;
        issue_ex_d.lane1_jalr = selected_pkt1.decode.bt_a_rs_sel;
        issue_ex_d.lane1_branch_target = selected_pkt1.target;
        issue_ex_d.lane1_branch_next_pc = selected_pkt1.next_pc;
        issue_ex_d.lane1_pred_hit = selected_pkt1.decode.pred_hit;
        issue_ex_d.lane1_pred_taken = selected_pkt1.decode.pred_taken;
        issue_ex_d.lane1_pred_target = selected_pkt1.decode.pred_target;
        issue_ex_d.lane1_pred_counter = selected_pkt1.decode.pred_counter;
        issue_ex_d.lane1_pred_bht_index = selected_pkt1.decode.pred_bht_index;
        if (selected_a_valid && !selected_pkt0.decode.operator_type[OPERATOR_TYPE_SYS]) begin
            if (selected_pkt0.decode.operator_type[OPERATOR_TYPE_ALU]) begin
                issue_ex_d.alu0_req.valid = 1'b1; issue_ex_d.alu0_req.operand_a = op_a0; issue_ex_d.alu0_req.operand_b = op_b0;
                issue_ex_d.alu0_req.operator_info = selected_pkt0.decode.operator_info; issue_ex_d.alu0_req.operator_type = selected_pkt0.decode.operator_type;
                issue_ex_d.alu0_req.rd_wen = selected_pkt0.dst.writes_gpr; issue_ex_d.alu0_req.rd_addr = selected_pkt0.dst.rd_addr; issue_ex_d.alu0_req.producer_id = selected_pkt0.dst.rob_tag; issue_ex_d.alu0_req.producer_tracked = 1'b1;
            end
            if (selected_pkt0.decode.operator_type[OPERATOR_TYPE_BITMANIP]) begin
                issue_ex_d.bit_req.valid = 1'b1; issue_ex_d.bit_req.operand_a = op_a0; issue_ex_d.bit_req.operand_b = op_b0;
                issue_ex_d.bit_req.operator_info = selected_pkt0.decode.operator_info; issue_ex_d.bit_req.operator_type = selected_pkt0.decode.operator_type;
                issue_ex_d.bit_req.rd_wen = selected_pkt0.dst.writes_gpr; issue_ex_d.bit_req.rd_addr = selected_pkt0.dst.rd_addr; issue_ex_d.bit_req.producer_id = selected_pkt0.dst.rob_tag; issue_ex_d.bit_req.producer_tracked = 1'b1;
            end
            if (selected_pkt0.decode.operator_type[OPERATOR_TYPE_MUL]) begin
                issue_ex_d.mdu_req.valid = 1'b1; issue_ex_d.mdu_req.operand_a = op_a0; issue_ex_d.mdu_req.operand_b = op_b0;
                issue_ex_d.mdu_req.operator_info = selected_pkt0.decode.operator_info; issue_ex_d.mdu_req.rd_wen = selected_pkt0.dst.writes_gpr; issue_ex_d.mdu_req.rd_addr = selected_pkt0.dst.rd_addr; issue_ex_d.mdu_req.producer_id = selected_pkt0.dst.rob_tag; issue_ex_d.mdu_req.producer_tracked = 1'b1;
            end
            if (selected_pkt0.decode.operator_type[OPERATOR_TYPE_CSR]) begin
                issue_ex_d.csr_req.valid = 1'b1; issue_ex_d.csr_req.operand_a = op_a0; issue_ex_d.csr_req.op_info = selected_pkt0.decode.csr_op_info; issue_ex_d.csr_req.waddr = selected_pkt0.decode.csr_waddr;
                issue_ex_d.csr_req.rd_wen = selected_pkt0.dst.writes_gpr; issue_ex_d.csr_req.rd_addr = selected_pkt0.dst.rd_addr; issue_ex_d.csr_req.producer_id = selected_pkt0.dst.rob_tag; issue_ex_d.csr_req.producer_tracked = 1'b1;
            end
        end
        if (selected_b_valid) begin
            if (selected_pkt1.decode.operator_type[OPERATOR_TYPE_ALU]) begin
                issue_ex_d.alu1_req.valid = 1'b1; issue_ex_d.alu1_req.operand_a = op_a1; issue_ex_d.alu1_req.operand_b = op_b1; issue_ex_d.alu1_req.operator_info = selected_pkt1.decode.operator_info; issue_ex_d.alu1_req.operator_type = selected_pkt1.decode.operator_type;
                issue_ex_d.alu1_req.rd_wen = selected_pkt1.dst.writes_gpr; issue_ex_d.alu1_req.rd_addr = selected_pkt1.dst.rd_addr; issue_ex_d.alu1_req.producer_id = selected_pkt1.dst.rob_tag; issue_ex_d.alu1_req.producer_tracked = 1'b1;
            end
            if (selected_pkt1.decode.operator_type[OPERATOR_TYPE_BJP]) begin
                issue_ex_d.bru_req.valid = 1'b1; issue_ex_d.bru_req.operand_a = selected_v10; issue_ex_d.bru_req.operand_b = selected_v11; issue_ex_d.bru_req.bt_a_operand = selected_pkt1.decode.bt_a_rs_sel ? selected_v10 : selected_pkt1.decode.pc; issue_ex_d.bru_req.bt_b_operand = selected_pkt1.decode.imm;
                issue_ex_d.bru_req.operator_info = selected_pkt1.decode.operator_info; issue_ex_d.bru_req.operator_type = selected_pkt1.decode.operator_type; issue_ex_d.bru_req.rd_wen = selected_pkt1.dst.writes_gpr; issue_ex_d.bru_req.rd_addr = selected_pkt1.dst.rd_addr; issue_ex_d.bru_req.jalr = selected_pkt1.decode.bt_a_rs_sel; issue_ex_d.bru_req.branch_target = selected_pkt1.target; issue_ex_d.bru_req.branch_next_pc = selected_pkt1.next_pc;
                issue_ex_d.bru_req.pred_hit = selected_pkt1.decode.pred_hit; issue_ex_d.bru_req.pred_taken = selected_pkt1.decode.pred_taken; issue_ex_d.bru_req.pred_target = selected_pkt1.decode.pred_target; issue_ex_d.bru_req.pred_counter = selected_pkt1.decode.pred_counter; issue_ex_d.bru_req.pred_bht_index = selected_pkt1.decode.pred_bht_index; issue_ex_d.bru_req.producer_id = selected_pkt1.dst.rob_tag; issue_ex_d.bru_req.producer_tracked = 1'b1;
            end
            if (selected_pkt1.decode.operator_type[OPERATOR_TYPE_LOAD] || selected_pkt1.decode.operator_type[OPERATOR_TYPE_STORE]) begin
                issue_ex_d.agu_req.valid = 1'b1; issue_ex_d.agu_req.is_load = selected_pkt1.decode.operator_type[OPERATOR_TYPE_LOAD]; issue_ex_d.agu_req.is_store = selected_pkt1.decode.operator_type[OPERATOR_TYPE_STORE]; issue_ex_d.agu_req.operand_a = op_a1; issue_ex_d.agu_req.operand_b = op_b1; issue_ex_d.agu_req.op = selected_pkt1.decode.operator_lsu; issue_ex_d.agu_req.store_data = selected_v11; issue_ex_d.agu_req.store_data_valid = 1'b1; issue_ex_d.agu_req.rd_addr = selected_pkt1.dst.rd_addr; issue_ex_d.agu_req.producer_id = selected_pkt1.dst.rob_tag; issue_ex_d.agu_req.producer_tracked = 1'b1;
            end
        end
    end

    // The context-to-EX boundary is registered.  ALU, BIT, BRU and AGU each
    // receive only their own request structure, so their operand cones do not
    // share a composite EX mux.
    assign issue_ex_o = issue_ex_q;
    assign issue_ex_execute_o = issue_ex_execute_q;
    logic issue_fence_q;
    producer_id_t issue_fence_tag_q;
    logic [INST_ADDR_WIDTH-1:0] issue_fence_next_pc_q;
    ydrasil_exception_req_pkt_t issue_sys_req_q;
    logic issue_sys_complete_q;
    producer_id_t issue_sys_tag_q;
    assign issue_fence_o = issue_fence_q;
    assign issue_fence_tag_o = issue_fence_tag_q;
    assign issue_fence_next_pc_o = issue_fence_next_pc_q;
    assign issue_sys_req_o = issue_sys_req_q;
    assign issue_sys_complete_o = issue_sys_complete_q;
    assign issue_sys_tag_o = issue_sys_tag_q;

    // Allocation is bank-aware: two dispatches are accepted only when two
    // different banks have a free slot, matching the one-write-port RAMs.
    integer ci, cj;
    always_comb begin
        entry_valid_d = entry_valid_q & ~selected_remove;
        ready0_d = ready0_q;
        ready1_d = ready1_q;
        for (ci = 0; ci < N; ci = ci + 1) begin
            age_d[ci] = age_q[ci];
            if (entry_valid_q[ci] && !ready0_q[ci] && src0_q[ci].used && src0_q[ci].tag_valid) begin
                if (source0_architected[ci] ||
                    (src0_q[ci].producer_class == RESULT_LSU && event_lsu_valid[src0_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_lsu_epoch[src0_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src0_q[ci].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src0_q[ci].producer_class == RESULT_MDU && event_mul_valid[src0_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_mul_epoch[src0_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src0_q[ci].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src0_q[ci].producer_class != RESULT_LSU && src0_q[ci].producer_class != RESULT_MDU && event_alu_valid[src0_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_alu_epoch[src0_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src0_q[ci].producer_tag[PRODUCER_ID_WIDTH-1])) ready0_d[ci] = 1'b1;
            end
            if (entry_valid_q[ci] && !ready1_q[ci] && src1_q[ci].used && src1_q[ci].tag_valid) begin
                if (source1_architected[ci] ||
                    (src1_q[ci].producer_class == RESULT_LSU && event_lsu_valid[src1_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_lsu_epoch[src1_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src1_q[ci].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src1_q[ci].producer_class == RESULT_MDU && event_mul_valid[src1_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_mul_epoch[src1_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src1_q[ci].producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    (src1_q[ci].producer_class != RESULT_LSU && src1_q[ci].producer_class != RESULT_MDU && event_alu_valid[src1_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] && event_alu_epoch[src1_q[ci].producer_tag[PRODUCER_SLOT_WIDTH-1:0]] == src1_q[ci].producer_tag[PRODUCER_ID_WIDTH-1])) ready1_d[ci] = 1'b1;
            end
            if (selected_remove[ci]) begin
                ready0_d[ci] = 1'b0;
                ready1_d[ci] = 1'b0;
            end
        end
        if (alloc_valid0) begin
            entry_valid_d[alloc_idx0] = 1'b1;
            ready0_d[alloc_idx0] = !dispatch_pkt_i.src0.used || !dispatch_pkt_i.src0.tag_valid || (dispatch_src0_state_i.live && dispatch_src0_state_i.done);
            ready1_d[alloc_idx0] = !dispatch_pkt_i.src1.used || !dispatch_pkt_i.src1.tag_valid || (dispatch_src1_state_i.live && dispatch_src1_state_i.done);
        end
        if (alloc_valid1) begin
            entry_valid_d[alloc_idx1] = 1'b1;
            ready0_d[alloc_idx1] = !dispatch_pkt1_i.src0.used || !dispatch_pkt1_i.src0.tag_valid || (dispatch_src2_state_i.live && dispatch_src2_state_i.done);
            ready1_d[alloc_idx1] = !dispatch_pkt1_i.src1.used || !dispatch_pkt1_i.src1.tag_valid || (dispatch_src3_state_i.live && dispatch_src3_state_i.done);
        end
    end

    always_comb begin
        for (ci = 0; ci < BANKS; ci = ci + 1) begin
            ctx_wen[ci] = 1'b0;
            ctx_waddr[ci] = '0;
            ctx_wdata[ci] = '0;
        end
        if (alloc_valid0) begin
            ctx_wen[alloc_bank0] = 1'b1;
            ctx_waddr[alloc_bank0] = alloc_idx0 % BANK_DEPTH;
            ctx_wdata[alloc_bank0] = dispatch_pkt_i;
        end
        if (alloc_valid1) begin
            ctx_wen[alloc_bank1] = 1'b1;
            ctx_waddr[alloc_bank1] = alloc_idx1 % BANK_DEPTH;
            ctx_wdata[alloc_bank1] = dispatch_pkt1_i;
        end
    end

    integer wi, wl;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            entry_valid_q <= '0;
            ready0_q <= '0;
            ready1_q <= '0;
            completion_bus_q <= '{default:'0};
            issue_ex_q <= '0;
            issue_ex_execute_q <= 1'b0;
            issue_fence_q <= 1'b0;
            issue_fence_tag_q <= '0;
            issue_fence_next_pc_q <= '0;
            issue_sys_req_q <= '0;
            issue_sys_complete_q <= 1'b0;
            issue_sys_tag_q <= '0;
            ingress_count_q <= '0;
            next_age_q <= '0;
            for (wi = 0; wi < N; wi = wi + 1) begin
                src0_q[wi] <= '0; src1_q[wi] <= '0; dst_q[wi] <= '0;
                value0_q[wi] <= '0; value1_q[wi] <= '0; age_q[wi] <= '0;
                memory_q[wi] <= 1'b0; store_q[wi] <= 1'b0; serial_q[wi] <= 1'b0; branch_q[wi] <= 1'b0;
                can0_q[wi] <= 1'b0; can1_q[wi] <= 1'b0; resources_q[wi] <= '0; op_type_q[wi] <= '0;
            end
        end else if (flush_id_i) begin
            // A redirect can coincide with a completion from an older
            // execution lane.  The surviving IQ entries must observe that
            // event after recovery; otherwise a same-bundle dependency can
            // remain asleep forever when its producer completes in the
            // redirect cycle.
            completion_bus_q <= completion_bus_i;
            for (wi = 0; wi < N; wi = wi + 1) begin
                // The recovery bitmap is indexed by ROB slot, never by the
                // physical IQ entry.  IQ entries are compactly allocated and
                // therefore have no stable positional relationship with a
                // producer tag across a redirect.
                if (entry_valid_q[wi] &&
                    redirect_keep_mask_i[
                        dst_q[wi].rob_tag[PRODUCER_SLOT_WIDTH-1:0]] &&
                    redirect_keep_epoch_i[
                        dst_q[wi].rob_tag[PRODUCER_SLOT_WIDTH-1:0]] ==
                        dst_q[wi].rob_tag[PRODUCER_ID_WIDTH-1]) begin
                    entry_valid_q[wi] <= 1'b1;
                end else begin
                    entry_valid_q[wi] <= 1'b0;
                    ready0_q[wi] <= 1'b0;
                    ready1_q[wi] <= 1'b0;
                end
            end
            issue_ex_q <= '0;
            issue_ex_execute_q <= 1'b0;
            issue_fence_q <= 1'b0;
            issue_sys_req_q <= '0;
            issue_sys_complete_q <= 1'b0;
            next_age_q <= next_age_q;
        end else begin
            entry_valid_q <= entry_valid_d;
            ready0_q <= ready0_d;
            ready1_q <= ready1_d;
            completion_bus_q <= completion_bus_i;
            issue_ex_execute_q <= issue_fire;
            if (!stall_id_i)
                issue_ex_q <= bubble_id_i ? '0 : issue_ex_d;
            issue_fence_q <= issue_fire && selected_a_valid &&
                selected_pkt0.decode.fence_i;
            issue_fence_tag_q <= selected_pkt0.dst.rob_tag;
            issue_fence_next_pc_q <= selected_pkt0.decode.pc + 32'd4;
            issue_sys_req_q <= '0;
            issue_sys_complete_q <= 1'b0;
            issue_sys_tag_q <= selected_pkt0.dst.rob_tag;
            next_age_q <= next_age_q + alloc_valid0 + alloc_valid1;
            if (issue_fire && selected_a_valid &&
                selected_pkt0.decode.operator_type[OPERATOR_TYPE_SYS]) begin
                issue_sys_complete_q <= selected_pkt0.decode.sys_op_info[OP_SYS_WFI];
                // WFI is a local completion in M-mode.  It must not enter
                // exception_ctrl, where a generic valid SYSTEM request would
                // otherwise be interpreted as an EBREAK-class trap.
                issue_sys_req_q.valid <=
                    !selected_pkt0.decode.sys_op_info[OP_SYS_WFI];
                issue_sys_req_q.ecall <= selected_pkt0.decode.sys_op_info[OP_SYS_ECALL];
                issue_sys_req_q.ebreak <= selected_pkt0.decode.sys_op_info[OP_SYS_EBREAK];
                issue_sys_req_q.mret <= selected_pkt0.decode.sys_op_info[OP_SYS_MRET];
                issue_sys_req_q.illegal <= !(selected_pkt0.decode.sys_op_info[OP_SYS_WFI] || selected_pkt0.decode.sys_op_info[OP_SYS_ECALL] || selected_pkt0.decode.sys_op_info[OP_SYS_EBREAK] || selected_pkt0.decode.sys_op_info[OP_SYS_MRET]);
                issue_sys_req_q.pc <= selected_pkt0.decode.pc;
                issue_sys_req_q.tval <= selected_pkt0.decode.instr;
            end
            for (wi = 0; wi < N; wi = wi + 1) begin
                if (alloc_valid0 && wi == alloc_idx0) begin
                    src0_q[wi] <= dispatch_pkt_i.src0; src1_q[wi] <= dispatch_pkt_i.src1; dst_q[wi] <= dispatch_pkt_i.dst;
                    value0_q[wi] <= (dispatch_src0_state_i.live && dispatch_src0_state_i.done) ? dispatch_src0_state_i.result : dispatch_rf_rdata_rs1_i;
                    value1_q[wi] <= (dispatch_src1_state_i.live && dispatch_src1_state_i.done) ? dispatch_src1_state_i.result : dispatch_rf_rdata_rs2_i;
                    age_q[wi] <= next_age_q;
                    memory_q[wi] <= dispatch_pkt_i.memory_op; store_q[wi] <= dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_STORE]; serial_q[wi] <= dispatch_pkt_i.ctrl.serialize_before; branch_q[wi] <= dispatch_pkt_i.decode.resources[RESOURCE_BRU];
                    can0_q[wi] <= !dispatch_pkt_i.decode.resources[RESOURCE_BRU] && !dispatch_pkt_i.decode.resources[RESOURCE_LSU];
                    can1_q[wi] <= !dispatch_pkt_i.decode.resources[RESOURCE_MULDIV] && !dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_BITMANIP] && !dispatch_pkt_i.decode.resources[RESOURCE_SERIAL] && !dispatch_pkt_i.decode.operator_type[OPERATOR_TYPE_FPU];
                    resources_q[wi] <= dispatch_pkt_i.decode.resources; op_type_q[wi] <= dispatch_pkt_i.decode.operator_type;
                end else if (alloc_valid1 && wi == alloc_idx1) begin
                    src0_q[wi] <= dispatch_pkt1_i.src0; src1_q[wi] <= dispatch_pkt1_i.src1; dst_q[wi] <= dispatch_pkt1_i.dst;
                    value0_q[wi] <= (dispatch_src2_state_i.live && dispatch_src2_state_i.done) ? dispatch_src2_state_i.result : dispatch_rf_rdata_rs3_i;
                    value1_q[wi] <= (dispatch_src3_state_i.live && dispatch_src3_state_i.done) ? dispatch_src3_state_i.result : dispatch_rf_rdata_rs4_i;
                    age_q[wi] <= next_age_q + 1'b1;
                    memory_q[wi] <= dispatch_pkt1_i.memory_op; store_q[wi] <= dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_STORE]; serial_q[wi] <= dispatch_pkt1_i.ctrl.serialize_before; branch_q[wi] <= dispatch_pkt1_i.decode.resources[RESOURCE_BRU];
                    can0_q[wi] <= !dispatch_pkt1_i.decode.resources[RESOURCE_BRU] && !dispatch_pkt1_i.decode.resources[RESOURCE_LSU];
                    can1_q[wi] <= !dispatch_pkt1_i.decode.resources[RESOURCE_MULDIV] && !dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_BITMANIP] && !dispatch_pkt1_i.decode.resources[RESOURCE_SERIAL] && !dispatch_pkt1_i.decode.operator_type[OPERATOR_TYPE_FPU];
                    resources_q[wi] <= dispatch_pkt1_i.decode.resources; op_type_q[wi] <= dispatch_pkt1_i.decode.operator_type;
                end else begin
                    age_q[wi] <= age_d[wi];
                    if (selected_remove[wi]) begin
                        src0_q[wi] <= '0; src1_q[wi] <= '0; dst_q[wi] <= '0; value0_q[wi] <= '0; value1_q[wi] <= '0;
                    end else if (entry_valid_q[wi]) begin
                        if (!ready0_q[wi] && ready0_d[wi] &&
                            !source0_architected[wi]) begin
                            if (src0_q[wi].producer_class == RESULT_LSU) value0_q[wi] <= event_lsu_data[src0_q[wi].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                            else if (src0_q[wi].producer_class == RESULT_MDU) value0_q[wi] <= event_mul_data[src0_q[wi].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                            else value0_q[wi] <= event_alu_data[src0_q[wi].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                        end
                        if (!ready1_q[wi] && ready1_d[wi] &&
                            !source1_architected[wi]) begin
                            if (src1_q[wi].producer_class == RESULT_LSU) value1_q[wi] <= event_lsu_data[src1_q[wi].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                            else if (src1_q[wi].producer_class == RESULT_MDU) value1_q[wi] <= event_mul_data[src1_q[wi].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                            else value1_q[wi] <= event_alu_data[src1_q[wi].producer_tag[PRODUCER_SLOT_WIDTH-1:0]];
                        end
                    end
                end
            end
        end
    end

    // Stable debug aliases used by the performance testbench.  They are
    // intentionally outside the scheduling equations.
    wire issue_valid_ff = selected_valid;
    wire issue_early_alu_valid_ff = 1'b0;
    wire [3:0] issue_early_kind_ff = '0;
    wire [REGS_ADDR_WIDTH-1:0] issue_early_alu_addr_ff = '0;
    wire rs1_issue_early_alu_fwd = 1'b0;
    wire rs2_issue_early_alu_fwd = 1'b0;
    wire issue_simple_alu_op = 1'b0;
    wire issue_plain_alu_op = selected_a_valid && selected_pkt0.decode.operator_type[OPERATOR_TYPE_ALU];
    wire [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff = selected_a_valid ? selected_pkt0.decode.operator_type : '0;
    wire rs1_completion_fwd = 1'b0;
    wire rs2_completion_fwd = 1'b0;
    wire id_advance = selected_valid && !stall_id_i && !bubble_id_i && !flush_id_i;
    wire completion_latency_event = |event_alu_valid | |event_lsu_valid | |event_mul_valid;
    wire scheduled_bypass_event = 1'b0;
    wire registered_alu_wakeup_event = |event_alu_valid;
    wire registered_lsu_wakeup_event = |event_lsu_valid;
    wire registered_mdu_wakeup_event = |event_mul_valid;
    wire reserved_bypass_plan_event = 1'b0;
    wire reserved_bypass_issue_event = 1'b0;
    wire reserved_bypass_cancel_event = 1'b0;
    ydrasil_issue_pkt_t selected_uop0, selected_uop1;
    assign selected_uop0 = selected_pkt0;
    assign selected_uop1 = selected_pkt1;
    wire bypass_consumed_event = 1'b0;
    wire registered_wakeup_event = |((ready0_d ^ ready0_q) | (ready1_d ^ ready1_q));
    wire issue_dispatch_two_ready = issue_dispatch_two_ready_q_o;
    wire issue_dispatch_ready_q = issue_dispatch_ready_q_o;
    wire issue_dispatch_two_ready_q = issue_dispatch_two_ready_q_o;

endmodule
