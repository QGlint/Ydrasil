// LSU request station.
//
// Issue reserves a concrete queue credit before the request crosses the two
// registered Issue/EX and AGU stages.  The request FIFO therefore accepts an
// AGU result whenever its earlier reservation exists; execution latency,
// MMIO waits and the store write buffer do not feed back into Issue.  This is
// the Nax-style separation between queue allocation and address execution,
// adapted to Ydrasil's one-cycle fixed-latency DTCM.
module ydrasil_load_store_unit
import ydrasil_pkg::*;
(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            redirect_i,
    input  wire                            kill_i,
    // One-cycle redirect survivor set used only to rebuild local state.
    input  wire [PRODUCER_NUM-1:0]         redirect_keep_mask_i,
    input  wire [PRODUCER_NUM-1:0]         redirect_keep_epoch_i,
    // Persistent ROB directory used by delayed AGU, DTCM and MMIO state.
    input  wire [PRODUCER_NUM-1:0]         producer_live_mask_i,
    input  wire [PRODUCER_NUM-1:0]         producer_live_epoch_i,
    input  producer_id_t                    rob_head_tag_i,
    input  ydrasil_lsu_reserve_pkt_t       reserve_i,
    input  ydrasil_lsu_req_pkt_t           req_i,
    input  wire [BUS_DATA_WIDTH-1:0]       dtcm_rdata_i,
    output ydrasil_dtcm_req_pkt_t          dtcm_req_o,
    input  ydrasil_mem_rsp_pkt_t           mmio_rsp_i,
    output ydrasil_mem_req_pkt_t           mmio_req_o,
    output ydrasil_lsu_status_pkt_t        status_o,
    output ydrasil_gpr_fwd_pkt_t           completion_o,
    output wire                            fp_completion_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0]      fp_completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]      fp_completion_data_o
);
    localparam int REQUEST_DEPTH = 8;
    localparam int STORE_BUFFER_DEPTH = 8;
    localparam int REQUEST_COUNT_WIDTH = $clog2(REQUEST_DEPTH + 1);
    localparam int STORE_COUNT_WIDTH = $clog2(STORE_BUFFER_DEPTH + 1);
    localparam logic [4:0] REQUEST_DEPTH_EXT = 5'd8;

    // Reservation stage zero is sampled with Issue/EX.  It advances once
    // while AGU computes and registers the address, then stage one is
    // consumed when req_i reaches this module.
    ydrasil_lsu_reserve_pkt_t reserve_s0_q;
    ydrasil_lsu_reserve_pkt_t reserve_s1_q;
    wire reserve_s0_live_dir = reserve_s0_q.producer_tracked &&
        producer_live_mask_i[reserve_s0_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[reserve_s0_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            reserve_s0_q.producer_id[PRODUCER_ID_WIDTH-1];
    wire reserve_s0_recovery_kept =
        redirect_keep_mask_i[reserve_s0_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[reserve_s0_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            reserve_s0_q.producer_id[PRODUCER_ID_WIDTH-1];
    wire reserve_s0_live = reserve_s0_q.valid && reserve_s0_live_dir &&
        (!redirect_i || reserve_s0_recovery_kept);
    wire reserve_s1_live_dir = reserve_s1_q.producer_tracked &&
        producer_live_mask_i[reserve_s1_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[reserve_s1_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            reserve_s1_q.producer_id[PRODUCER_ID_WIDTH-1];
    wire reserve_s1_recovery_kept =
        redirect_keep_mask_i[reserve_s1_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[reserve_s1_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            reserve_s1_q.producer_id[PRODUCER_ID_WIDTH-1];
    wire reserve_s1_live = reserve_s1_q.valid && reserve_s1_live_dir &&
        (!redirect_i || reserve_s1_recovery_kept);
    wire reserve_i_live_dir = reserve_i.producer_tracked &&
        producer_live_mask_i[reserve_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[reserve_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            reserve_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire reserve_i_recovery_kept =
        redirect_keep_mask_i[reserve_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[reserve_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            reserve_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire reserve_i_live = reserve_i.valid && reserve_i_live_dir &&
        (!redirect_i || reserve_i_recovery_kept);
    wire [1:0] reservation_count_q =
        {1'b0, reserve_s0_live} + {1'b0, reserve_s1_live};

    ydrasil_lsu_req_pkt_t request_q [0:REQUEST_DEPTH-1];
    logic [REQUEST_DEPTH-1:0] request_valid_q;
    reg [REQUEST_COUNT_WIDTH-1:0] request_count_q;

    // Requests reach this unit two cycles after Issue.  If younger memory
    // operations have consumed every speculative station slot, the current
    // ROB-head memory operation must still be able to cross that gap.  Nax's
    // LSQ gets this guarantee by allocating entries in program order; this
    // compact request-station implementation carries one explicit head
    // ingress entry instead.  It is not a speculative overflow queue: only
    // the exact ROB-head producer can occupy it.
    ydrasil_lsu_req_pkt_t head_request_q;
    reg head_request_valid_q;
    wire head_request_live_dir = head_request_valid_q &&
        head_request_q.producer_tracked &&
        producer_live_mask_i[head_request_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[head_request_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            head_request_q.producer_id[PRODUCER_ID_WIDTH-1];
    wire head_request_recovery_kept =
        redirect_keep_mask_i[head_request_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[head_request_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            head_request_q.producer_id[PRODUCER_ID_WIDTH-1];
    wire head_request_survives_redirect = head_request_live_dir &&
        (!redirect_i || head_request_recovery_kept);

    // DTCM stores become irrevocable after their address/data request has
    // entered this local write buffer.  The buffer drains independently of
    // load issue, allowing one fixed-latency load and one store write per
    // clock without a mixed request-data critical path.
    ydrasil_lsu_req_pkt_t store_buffer_q [0:STORE_BUFFER_DEPTH-1];
    reg [STORE_COUNT_WIDTH-1:0] store_buffer_count_q;
    reg [$clog2(STORE_BUFFER_DEPTH)-1:0] store_head_q;
    reg [$clog2(STORE_BUFFER_DEPTH)-1:0] store_tail_q;

    wire request_empty = request_count_q == '0;
    wire request_full = request_count_q == REQUEST_COUNT_WIDTH'(REQUEST_DEPTH);
    wire store_buffer_empty = store_buffer_count_q == '0;
    wire store_buffer_full =
        store_buffer_count_q == STORE_COUNT_WIDTH'(STORE_BUFFER_DEPTH);

    // The request station is deliberately not an AGU-arrival FIFO.  An OoO
    // AGU can produce a younger store before an older one; a FIFO would then
    // deadlock once the older store reaches the ROB head.  This 8-entry
    // selector keeps load progress local while selecting commit-sensitive
    // store/MMIO work by its ROB tag.
    logic [REQUEST_DEPTH-1:0] load_blocked_by_older_ordered_req;
    logic active_selected;
    logic active_from_head_ingress;
    logic [$clog2(REQUEST_DEPTH)-1:0] active_idx;
    // producer_id_t carries a ROB slot plus a per-slot epoch.  The epoch is
    // only a lifetime check, not a monotonically increasing sequence number:
    // adjacent live entries can legitimately have tags 3, 20, 21, 6 after
    // individual slots have been recycled.  Memory age therefore comes from
    // the ring distance between ROB slots, relative to the current head.
    logic [PRODUCER_SLOT_WIDTH-1:0] active_age;
    logic [PRODUCER_SLOT_WIDTH-1:0] scan_age;
    integer request_select_i;
    integer request_store_i;
    ydrasil_lsu_req_pkt_t active_pkt;
    always_comb begin
        load_blocked_by_older_ordered_req = '0;
        for (request_select_i = 0; request_select_i < REQUEST_DEPTH;
             request_select_i = request_select_i + 1) begin
            if (request_valid_q[request_select_i] &&
                request_q[request_select_i].is_load &&
                request_q[request_select_i].addr_is_dtcm) begin
                for (request_store_i = 0; request_store_i < REQUEST_DEPTH;
                     request_store_i = request_store_i + 1) begin
                    // An old store needs forwarding or an architectural
                    // write before a younger DTCM load may execute.  An old
                    // MMIO transaction is ordered as well, including reads:
                    // it is externally visible and can wait indefinitely.
                    if (request_valid_q[request_store_i] &&
                        (request_q[request_store_i].is_store ||
                         !request_q[request_store_i].addr_is_dtcm) &&
                        ((request_q[request_store_i].producer_id[PRODUCER_SLOT_WIDTH-1:0] -
                          rob_head_tag_i[PRODUCER_SLOT_WIDTH-1:0]) <
                         (request_q[request_select_i].producer_id[PRODUCER_SLOT_WIDTH-1:0] -
                          rob_head_tag_i[PRODUCER_SLOT_WIDTH-1:0])))
                        load_blocked_by_older_ordered_req[request_select_i] = 1'b1;
                end
            end
        end

        active_pkt = '0;
        active_selected = 1'b0;
        active_from_head_ingress = 1'b0;
        active_idx = '0;
        active_age = {PRODUCER_SLOT_WIDTH{1'b1}};

        // The head ingress has priority over speculative station work.  It
        // exists specifically to break a full-station / head-store cycle.
        if (head_request_valid_q && head_request_survives_redirect &&
            head_request_q.producer_id == rob_head_tag_i) begin
            active_selected = 1'b1;
            active_from_head_ingress = 1'b1;
            active_pkt = head_request_q;
        end else begin
            // Exact ROB-head work is always eligible.  This is required for
            // non-speculative stores and arbitrary-latency MMIO transactions.
            for (request_select_i = 0; request_select_i < REQUEST_DEPTH;
                 request_select_i = request_select_i + 1) begin
                if (request_valid_q[request_select_i] &&
                    request_q[request_select_i].producer_tracked &&
                    request_q[request_select_i].producer_id == rob_head_tag_i) begin
                    active_selected = 1'b1;
                    active_idx = request_select_i[$clog2(REQUEST_DEPTH)-1:0];
                    active_pkt = request_q[request_select_i];
                end
            end
        end

        // A fixed-latency DTCM load can bypass unrelated younger work, but
        // never a known older store still resident in this station.
        if (!active_selected) begin
            for (request_select_i = 0; request_select_i < REQUEST_DEPTH;
                 request_select_i = request_select_i + 1) begin
                scan_age = request_q[request_select_i]
                    .producer_id[PRODUCER_SLOT_WIDTH-1:0] -
                    rob_head_tag_i[PRODUCER_SLOT_WIDTH-1:0];
                if (request_valid_q[request_select_i] &&
                    request_q[request_select_i].is_load &&
                    request_q[request_select_i].addr_is_dtcm &&
                    !load_blocked_by_older_ordered_req[request_select_i] &&
                    (!active_selected || scan_age < active_age)) begin
                    active_selected = 1'b1;
                    active_idx = request_select_i[$clog2(REQUEST_DEPTH)-1:0];
                    active_age = scan_age;
                    active_pkt = request_q[request_select_i];
                end
            end
        end
    end

    wire active_live_dir = active_pkt.producer_tracked &&
        producer_live_mask_i[active_pkt.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[active_pkt.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            active_pkt.producer_id[PRODUCER_ID_WIDTH-1];
    wire active_recovery_kept =
        redirect_keep_mask_i[active_pkt.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[active_pkt.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            active_pkt.producer_id[PRODUCER_ID_WIDTH-1];
    // The live directory remains valid after recovery, so a request delayed
    // in AGU or this station cannot execute after its producer is squashed.
    wire active_survives_redirect = active_live_dir &&
        (!redirect_i || active_recovery_kept);
    wire active_valid = active_selected && active_pkt.valid &&
        active_survives_redirect;
    wire active_at_rob_head = active_pkt.producer_tracked &&
        active_pkt.producer_id == rob_head_tag_i;

    // Issue sends memory uops in program order.  A younger request may reach
    // this station before an older one has crossed the Issue/EX and AGU
    // pipeline, so use the reservation tags to preserve that ordering across
    // the gap.  Epochs establish liveness; slot distance establishes age.
    wire active_waits_for_older_reservation = active_valid &&
        ((reserve_s0_live &&
          ((reserve_s0_q.producer_id[PRODUCER_SLOT_WIDTH-1:0] -
            rob_head_tag_i[PRODUCER_SLOT_WIDTH-1:0]) <
           (active_pkt.producer_id[PRODUCER_SLOT_WIDTH-1:0] -
            rob_head_tag_i[PRODUCER_SLOT_WIDTH-1:0]))) ||
         (reserve_s1_live &&
          ((reserve_s1_q.producer_id[PRODUCER_SLOT_WIDTH-1:0] -
            rob_head_tag_i[PRODUCER_SLOT_WIDTH-1:0]) <
           (active_pkt.producer_id[PRODUCER_SLOT_WIDTH-1:0] -
            rob_head_tag_i[PRODUCER_SLOT_WIDTH-1:0]))));

    wire active_dtcm_load = active_valid && active_pkt.addr_is_dtcm &&
        active_pkt.is_load;
    wire active_dtcm_store = active_valid && active_pkt.addr_is_dtcm &&
        active_pkt.is_store;
    wire active_mmio = active_valid && !active_pkt.addr_is_dtcm;

    reg [31:0] active_store_aligned_data;
    always_comb begin
        active_store_aligned_data = active_pkt.store_data;
        if (active_pkt.op[OP_LSU_SB]) begin
            unique case (active_pkt.addr[1:0])
                2'b00: active_store_aligned_data = {24'b0, active_pkt.store_data[7:0]};
                2'b01: active_store_aligned_data = {16'b0, active_pkt.store_data[7:0], 8'b0};
                2'b10: active_store_aligned_data = {8'b0, active_pkt.store_data[7:0], 16'b0};
                default: active_store_aligned_data = {active_pkt.store_data[7:0], 24'b0};
            endcase
        end else if (active_pkt.op[OP_LSU_SH]) begin
            if (active_pkt.addr[1])
                active_store_aligned_data = {active_pkt.store_data[15:0], 16'b0};
            else
                active_store_aligned_data = {16'b0, active_pkt.store_data[15:0]};
        end
    end

    wire store_head_data_valid = !store_buffer_empty &&
        store_buffer_q[store_head_q].store_data_valid;
    wire store_head_live_dir = store_buffer_q[store_head_q].producer_tracked &&
        producer_live_mask_i[store_buffer_q[store_head_q].producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[store_buffer_q[store_head_q].producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            store_buffer_q[store_head_q].producer_id[PRODUCER_ID_WIDTH-1];
    wire store_head_recovery_kept =
        redirect_keep_mask_i[store_buffer_q[store_head_q].producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[store_buffer_q[store_head_q].producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            store_buffer_q[store_head_q].producer_id[PRODUCER_ID_WIDTH-1];
    wire store_head_survives_redirect = store_head_live_dir &&
        (!redirect_i || store_head_recovery_kept);
    wire [BUS_DATA_WIDTH-1:0] store_head_wdata =
        store_buffer_q[store_head_q].store_data;

    reg mmio_req_valid_q;
    reg mmio_is_load_q;
    reg [BUS_ADDR_WIDTH-1:0] mmio_addr_q;
    reg [BUS_DATA_WIDTH-1:0] mmio_wdata_q;
    reg [3:0] mmio_wmask_q;
    reg [1:0] mmio_addr_index_q;
    reg [OP_LSU_INFO_WIDTH-1:0] mmio_op_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_rd_addr_q;
    producer_id_t mmio_producer_id_q;
    reg mmio_producer_tracked_q;
    reg mmio_fp_load_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_fp_rd_addr_q;

    reg mmio_wb_valid_q;
    reg [REGS_DATA_WIDTH-1:0] mmio_wb_result_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_rd_addr_q;
    producer_id_t mmio_wb_producer_id_q;
    reg mmio_wb_producer_tracked_q;
    reg mmio_wb_fp_load_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_fp_rd_addr_q;
    wire mmio_busy = mmio_req_valid_q || mmio_wb_valid_q;

    // A DTCM store is acknowledged only when its buffered write actually
    // reaches the fixed-latency port.  This prevents a store from retiring
    // ahead of a write that can still be cancelled by recovery.
    reg dtcm_store_wb_valid_q;
    producer_id_t dtcm_store_wb_producer_id_q;
    reg dtcm_store_wb_producer_tracked_q;

    // DTCM has a deterministic one-cycle response.  Only its metadata needs
    // to be held; data comes from the fixed-latency DTCM port next cycle.
    reg load_rsp_valid_q;
    reg [REGS_ADDR_WIDTH-1:0] load_rsp_rd_addr_q;
    producer_id_t load_rsp_producer_id_q;
    reg load_rsp_producer_tracked_q;
    reg [OP_LSU_INFO_WIDTH-1:0] load_rsp_op_q;
    reg [1:0] load_rsp_addr_index_q;
    reg [3:0] load_rsp_forward_mask_q;
    reg [BUS_DATA_WIDTH-1:0] load_rsp_forward_data_q;
    reg load_rsp_fp_load_q;
    reg [REGS_ADDR_WIDTH-1:0] load_rsp_fp_rd_addr_q;

    reg [3:0] load_forward_mask;
    reg [BUS_DATA_WIDTH-1:0] load_forward_data;
    integer store_scan;
    integer byte_scan;
    integer store_scan_slot;
    always_comb begin
        load_forward_mask = '0;
        load_forward_data = '0;
        for (store_scan = 0; store_scan < STORE_BUFFER_DEPTH;
             store_scan = store_scan + 1) begin
            store_scan_slot = store_head_q + store_scan;
            if (store_scan_slot >= STORE_BUFFER_DEPTH)
                store_scan_slot = store_scan_slot - STORE_BUFFER_DEPTH;
            if ((store_scan < store_buffer_count_q) &&
                store_buffer_q[store_scan_slot].valid &&
                (store_buffer_q[store_scan_slot].addr[BUS_ADDR_WIDTH-1:2] ==
                 active_pkt.addr[BUS_ADDR_WIDTH-1:2])) begin
                for (byte_scan = 0; byte_scan < 4; byte_scan = byte_scan + 1) begin
                    if (store_buffer_q[store_scan_slot].store_mask[byte_scan]) begin
                        load_forward_mask[byte_scan] = 1'b1;
                        load_forward_data[byte_scan*8 +: 8] =
                            store_buffer_q[store_scan_slot].store_data[byte_scan*8 +: 8];
                    end
                end
            end
        end
    end

    wire load_issue_hold = mmio_wb_valid_q ||
        (mmio_req_valid_q && mmio_rsp_i.valid && mmio_is_load_q);
    wire dtcm_store_wb_live_dir = dtcm_store_wb_producer_tracked_q &&
        producer_live_mask_i[dtcm_store_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[dtcm_store_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            dtcm_store_wb_producer_id_q[PRODUCER_ID_WIDTH-1];
    wire dtcm_store_wb_recovery_kept =
        redirect_keep_mask_i[dtcm_store_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[dtcm_store_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            dtcm_store_wb_producer_id_q[PRODUCER_ID_WIDTH-1];
    wire dtcm_store_wb_survives_redirect = dtcm_store_wb_live_dir &&
        (!redirect_i || dtcm_store_wb_recovery_kept);
    wire store_buffer_dequeue = store_head_data_valid &&
        store_head_survives_redirect && !dtcm_store_wb_valid_q;
    wire store_buffer_has_room = !store_buffer_full || store_buffer_dequeue;
    wire dtcm_load_fire = active_dtcm_load && !load_issue_hold &&
        !active_waits_for_older_reservation && !mmio_busy;
    wire dtcm_store_fire = active_dtcm_store && active_at_rob_head &&
        store_buffer_has_room;
    wire mmio_fire = active_mmio && active_at_rob_head && !mmio_busy && store_buffer_empty &&
        (!active_pkt.is_store || active_pkt.store_data_valid);
    wire active_fire = dtcm_load_fire || dtcm_store_fire || mmio_fire;
    wire request_dequeue = active_fire && !active_from_head_ingress;
    wire head_request_dequeue = active_fire && active_from_head_ingress;
    wire store_buffer_enqueue = dtcm_store_fire;

    wire [REQUEST_COUNT_WIDTH-1:0] request_post_dequeue_count =
        request_count_q - (request_dequeue ? REQUEST_COUNT_WIDTH'(1) : '0);
    wire request_slot_after_dequeue = request_post_dequeue_count <
        REQUEST_COUNT_WIDTH'(REQUEST_DEPTH);

    wire req_live_dir = req_i.producer_tracked &&
        producer_live_mask_i[req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            req_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire req_recovery_kept =
        redirect_keep_mask_i[req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            req_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire req_survives_redirect = req_live_dir &&
        (!redirect_i || req_recovery_kept);
    logic request_alloc_valid;
    logic [$clog2(REQUEST_DEPTH)-1:0] request_alloc_idx;
    integer request_alloc_i;
    always_comb begin
        request_alloc_valid = 1'b0;
        request_alloc_idx = '0;
        for (request_alloc_i = 0; request_alloc_i < REQUEST_DEPTH;
             request_alloc_i = request_alloc_i + 1) begin
            if (!request_alloc_valid &&
                (!request_valid_q[request_alloc_i] ||
                 (request_dequeue && active_selected &&
                  active_idx == request_alloc_i[$clog2(REQUEST_DEPTH)-1:0]) ||
                 // Only the redirect cycle uses the recovery mask.  It is
                 // intentionally all-zero in ordinary cycles and therefore
                 // must never be used as the request station's live table.
                 (redirect_i && request_valid_q[request_alloc_i] &&
                  (!request_q[request_alloc_i].producer_tracked ||
                   !redirect_keep_mask_i[request_q[request_alloc_i].producer_id[PRODUCER_SLOT_WIDTH-1:0]] ||
                   redirect_keep_epoch_i[request_q[request_alloc_i].producer_id[PRODUCER_SLOT_WIDTH-1:0]] !=
                       request_q[request_alloc_i].producer_id[PRODUCER_ID_WIDTH-1])))) begin
                request_alloc_valid = 1'b1;
                request_alloc_idx = request_alloc_i[$clog2(REQUEST_DEPTH)-1:0];
            end
        end
    end
    wire request_enqueue = req_i.valid && req_survives_redirect &&
        reserve_s1_live && request_slot_after_dequeue && request_alloc_valid;
    // A head request uses this ingress only when the normal station has no
    // reclaimable slot.  If a load/store dequeues in the same cycle, normal
    // allocation wins and no extra state is consumed.
    wire head_request_enqueue = req_i.valid && req_survives_redirect &&
        reserve_s1_live && !request_slot_after_dequeue &&
        !head_request_valid_q &&
        req_i.producer_id == rob_head_tag_i;

    wire [REQUEST_COUNT_WIDTH:0] admission_occupancy =
        {1'b0, request_post_dequeue_count} +
        {{(REQUEST_COUNT_WIDTH-1){1'b0}}, reservation_count_q};
    wire accept_ready = admission_occupancy < REQUEST_DEPTH_EXT;
    wire head_reservation_inflight =
        (reserve_s0_live && reserve_s0_q.producer_id == rob_head_tag_i) ||
        (reserve_s1_live && reserve_s1_q.producer_id == rob_head_tag_i);
    wire head_accept_ready = !accept_ready && !head_request_valid_q &&
        !head_reservation_inflight;

    wire load_rsp_live_dir = load_rsp_producer_tracked_q &&
        producer_live_mask_i[load_rsp_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[load_rsp_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            load_rsp_producer_id_q[PRODUCER_ID_WIDTH-1];
    wire load_rsp_recovery_kept =
        redirect_keep_mask_i[load_rsp_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[load_rsp_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            load_rsp_producer_id_q[PRODUCER_ID_WIDTH-1];
    // A captured producer id has no architectural meaning once its request
    // has completed.  Qualifying the directory lookup with the state valid
    // bit prevents an old response tag from participating in a later branch
    // recovery decision.
    wire mmio_req_live_dir = mmio_req_valid_q && mmio_producer_tracked_q &&
        producer_live_mask_i[mmio_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[mmio_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            mmio_producer_id_q[PRODUCER_ID_WIDTH-1];
    wire mmio_req_recovery_kept =
        redirect_keep_mask_i[mmio_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[mmio_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            mmio_producer_id_q[PRODUCER_ID_WIDTH-1];
    wire mmio_wb_live_dir = mmio_wb_valid_q && mmio_wb_producer_tracked_q &&
        producer_live_mask_i[mmio_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[mmio_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            mmio_wb_producer_id_q[PRODUCER_ID_WIDTH-1];
    wire mmio_wb_recovery_kept =
        redirect_keep_mask_i[mmio_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[mmio_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            mmio_wb_producer_id_q[PRODUCER_ID_WIDTH-1];

    wire load_rsp_survives_redirect = load_rsp_live_dir &&
        (!redirect_i || load_rsp_recovery_kept);
    // An issued MMIO transaction cannot be cancelled.  Its request remains
    // stable until the fabric responds; liveness only suppresses the result.
    wire mmio_req_survives_redirect = mmio_req_live_dir &&
        (!redirect_i || mmio_req_recovery_kept);
    wire mmio_wb_survives_redirect = mmio_wb_live_dir &&
        (!redirect_i || mmio_wb_recovery_kept);
    wire mmio_rsp_fire = mmio_req_valid_q && mmio_rsp_i.valid;

    reg [BUS_DATA_WIDTH-1:0] load_merged_word;
    reg [BUS_DATA_WIDTH-1:0] load_shifted_word;
    reg [BUS_DATA_WIDTH-1:0] dtcm_load_result;
    reg [BUS_DATA_WIDTH-1:0] mmio_load_result;
    always_comb begin
        load_merged_word = dtcm_rdata_i;
        for (byte_scan = 0; byte_scan < 4; byte_scan = byte_scan + 1) begin
            if (load_rsp_forward_mask_q[byte_scan])
                load_merged_word[byte_scan*8 +: 8] =
                    load_rsp_forward_data_q[byte_scan*8 +: 8];
        end
        load_shifted_word = load_merged_word >>
            ({3'b000, load_rsp_addr_index_q} << 3);
        dtcm_load_result = load_shifted_word;
        unique case (1'b1)
            load_rsp_op_q[OP_LSU_LB]:
                dtcm_load_result = {{24{load_shifted_word[7]}}, load_shifted_word[7:0]};
            load_rsp_op_q[OP_LSU_LBU]:
                dtcm_load_result = {24'b0, load_shifted_word[7:0]};
            load_rsp_op_q[OP_LSU_LH]:
                dtcm_load_result = {{16{load_shifted_word[15]}}, load_shifted_word[15:0]};
            load_rsp_op_q[OP_LSU_LHU]:
                dtcm_load_result = {16'b0, load_shifted_word[15:0]};
            default: dtcm_load_result = load_shifted_word;
        endcase

        mmio_load_result = mmio_rsp_i.rdata >>
            ({3'b000, mmio_addr_index_q} << 3);
        unique case (1'b1)
            mmio_op_q[OP_LSU_LB]:
                mmio_load_result = {{24{mmio_load_result[7]}}, mmio_load_result[7:0]};
            mmio_op_q[OP_LSU_LBU]:
                mmio_load_result = {24'b0, mmio_load_result[7:0]};
            mmio_op_q[OP_LSU_LH]:
                mmio_load_result = {{16{mmio_load_result[15]}}, mmio_load_result[15:0]};
            mmio_op_q[OP_LSU_LHU]:
                mmio_load_result = {16'b0, mmio_load_result[15:0]};
            default: mmio_load_result = mmio_load_result;
        endcase
    end

    wire dtcm_wb_valid = load_rsp_valid_q && load_rsp_survives_redirect;
    wire mmio_wb_out_valid = mmio_wb_valid_q && mmio_wb_survives_redirect &&
        !dtcm_wb_valid;
    wire dtcm_store_wb_out_valid = dtcm_store_wb_valid_q &&
        dtcm_store_wb_survives_redirect && !dtcm_wb_valid &&
        !mmio_wb_out_valid;
    always_comb begin
        completion_o = '0;
        if (dtcm_wb_valid) begin
            completion_o.valid = load_rsp_producer_tracked_q;
            completion_o.producer_id = load_rsp_producer_id_q;
            completion_o.producer_tracked = load_rsp_producer_tracked_q;
            completion_o.addr = load_rsp_rd_addr_q;
            completion_o.data = dtcm_load_result;
        end else if (mmio_wb_out_valid) begin
            completion_o.valid = mmio_wb_producer_tracked_q;
            completion_o.producer_id = mmio_wb_producer_id_q;
            completion_o.producer_tracked = mmio_wb_producer_tracked_q;
            completion_o.addr = mmio_wb_rd_addr_q;
            completion_o.data = mmio_wb_result_q;
        end else if (dtcm_store_wb_out_valid) begin
            completion_o.valid = dtcm_store_wb_producer_tracked_q;
            completion_o.producer_id = dtcm_store_wb_producer_id_q;
            completion_o.producer_tracked = dtcm_store_wb_producer_tracked_q;
        end
    end
    assign fp_completion_valid_o = dtcm_wb_valid ? load_rsp_fp_load_q :
        (mmio_wb_out_valid && mmio_wb_fp_load_q);
    assign fp_completion_addr_o = dtcm_wb_valid ? load_rsp_fp_rd_addr_q :
        mmio_wb_fp_rd_addr_q;
    assign fp_completion_data_o = completion_o.data;

    always_comb begin
        dtcm_req_o = '0;
        dtcm_req_o.load.valid = dtcm_load_fire;
        dtcm_req_o.load.addr = active_pkt.addr;
        dtcm_req_o.store.valid = store_buffer_dequeue;
        dtcm_req_o.store.write = store_buffer_dequeue;
        dtcm_req_o.store.addr = store_buffer_q[store_head_q].addr;
        dtcm_req_o.store.wdata = store_head_wdata;
        dtcm_req_o.store.wmask = store_buffer_q[store_head_q].store_mask;
    end

    assign mmio_req_o.valid = mmio_req_valid_q;
    assign mmio_req_o.write = mmio_req_valid_q && !mmio_is_load_q;
    assign mmio_req_o.addr = mmio_addr_q;
    assign mmio_req_o.wdata = mmio_wdata_q;
    assign mmio_req_o.wmask = mmio_req_o.write ? mmio_wmask_q : '0;

    wire station_idle = request_empty && !head_request_valid_q &&
        store_buffer_empty &&
        !mmio_busy && !load_rsp_valid_q && !dtcm_store_wb_valid_q &&
        (reservation_count_q == '0) &&
        !req_i.valid;
    assign status_o.busy = !station_idle;
    assign status_o.idle = station_idle;
    assign status_o.fast_load = !store_buffer_full && !load_issue_hold &&
        (request_count_q < 2);
    assign status_o.accept_ready = accept_ready;
    assign status_o.head_accept_ready = head_accept_ready;

    ydrasil_lsu_req_pkt_t store_recovery_q [0:STORE_BUFFER_DEPTH-1];
    logic [REQUEST_DEPTH-1:0] request_recovery_valid;
    reg [REQUEST_COUNT_WIDTH-1:0] request_recovery_count;
    reg [STORE_COUNT_WIDTH-1:0] store_recovery_count;
    integer recovery_i;
    integer recovery_src;
    always_comb begin
        request_recovery_count = '0;
        store_recovery_count = '0;
        for (recovery_i = 0; recovery_i < STORE_BUFFER_DEPTH;
             recovery_i = recovery_i + 1)
            store_recovery_q[recovery_i] = '0;

        for (recovery_i = 0; recovery_i < REQUEST_DEPTH;
             recovery_i = recovery_i + 1) begin
            request_recovery_valid[recovery_i] = 1'b0;
            if (request_valid_q[recovery_i] &&
                !(request_dequeue && active_selected &&
                  active_idx == recovery_i[$clog2(REQUEST_DEPTH)-1:0]) &&
                (!redirect_i ||
                 (request_q[recovery_i].producer_tracked &&
                  redirect_keep_mask_i[request_q[recovery_i].producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
                  redirect_keep_epoch_i[request_q[recovery_i].producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
                      request_q[recovery_i].producer_id[PRODUCER_ID_WIDTH-1]))) begin
                request_recovery_valid[recovery_i] = 1'b1;
                request_recovery_count = request_recovery_count + 1'b1;
            end
        end
        if (request_enqueue) begin
            request_recovery_valid[request_alloc_idx] = 1'b1;
            request_recovery_count = request_recovery_count + 1'b1;
        end

        for (recovery_i = 0; recovery_i < STORE_BUFFER_DEPTH;
             recovery_i = recovery_i + 1) begin
            recovery_src = store_head_q + recovery_i;
            if (recovery_src >= STORE_BUFFER_DEPTH)
                recovery_src = recovery_src - STORE_BUFFER_DEPTH;
            if ((recovery_i < store_buffer_count_q) &&
                !(store_buffer_dequeue && recovery_i == 0) &&
                (!redirect_i ||
                 (store_buffer_q[recovery_src].producer_tracked &&
                  redirect_keep_mask_i[store_buffer_q[recovery_src].producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
                  redirect_keep_epoch_i[store_buffer_q[recovery_src].producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
                      store_buffer_q[recovery_src].producer_id[PRODUCER_ID_WIDTH-1]))) begin
                store_recovery_q[store_recovery_count[$clog2(STORE_BUFFER_DEPTH)-1:0]] =
                    store_buffer_q[recovery_src];
                store_recovery_count = store_recovery_count + 1'b1;
            end
        end
        if (store_buffer_enqueue) begin
            store_recovery_q[store_recovery_count[$clog2(STORE_BUFFER_DEPTH)-1:0]] = active_pkt;
            store_recovery_q[store_recovery_count[$clog2(STORE_BUFFER_DEPTH)-1:0]].valid = 1'b1;
            store_recovery_q[store_recovery_count[$clog2(STORE_BUFFER_DEPTH)-1:0]].store_data =
                active_store_aligned_data;
            store_recovery_q[store_recovery_count[$clog2(STORE_BUFFER_DEPTH)-1:0]].store_data_valid = 1'b1;
            store_recovery_count = store_recovery_count + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reserve_s0_q <= '0;
            reserve_s1_q <= '0;
            request_valid_q <= '0;
            request_count_q <= '0;
            head_request_q <= '0;
            head_request_valid_q <= 1'b0;
            store_buffer_count_q <= '0;
            store_head_q <= '0;
            store_tail_q <= '0;
            load_rsp_valid_q <= 1'b0;
            load_rsp_rd_addr_q <= '0;
            load_rsp_producer_id_q <= '0;
            load_rsp_producer_tracked_q <= 1'b0;
            load_rsp_op_q <= '0;
            load_rsp_addr_index_q <= '0;
            load_rsp_forward_mask_q <= '0;
            load_rsp_forward_data_q <= '0;
            load_rsp_fp_load_q <= 1'b0;
            load_rsp_fp_rd_addr_q <= '0;
            mmio_req_valid_q <= 1'b0;
            mmio_is_load_q <= 1'b0;
            mmio_addr_q <= '0;
            mmio_wdata_q <= '0;
            mmio_wmask_q <= '0;
            mmio_addr_index_q <= '0;
            mmio_op_q <= '0;
            mmio_rd_addr_q <= '0;
            mmio_producer_id_q <= '0;
            mmio_producer_tracked_q <= 1'b0;
            mmio_fp_load_q <= 1'b0;
            mmio_fp_rd_addr_q <= '0;
            mmio_wb_valid_q <= 1'b0;
            mmio_wb_result_q <= '0;
            mmio_wb_rd_addr_q <= '0;
            mmio_wb_producer_id_q <= '0;
            mmio_wb_producer_tracked_q <= 1'b0;
            mmio_wb_fp_load_q <= 1'b0;
            mmio_wb_fp_rd_addr_q <= '0;
            dtcm_store_wb_valid_q <= 1'b0;
            dtcm_store_wb_producer_id_q <= '0;
            dtcm_store_wb_producer_tracked_q <= 1'b0;
        end else begin
            reserve_s1_q <= reserve_s0_live ? reserve_s0_q : '0;
            reserve_s0_q <= reserve_i_live ? reserve_i : '0;

            if (request_dequeue)
                request_valid_q[active_idx] <= 1'b0;
            if (request_enqueue) begin
                request_q[request_alloc_idx] <= req_i;
                request_q[request_alloc_idx].valid <= 1'b1;
                request_valid_q[request_alloc_idx] <= 1'b1;
            end
            unique case ({request_enqueue, request_dequeue})
                2'b10: request_count_q <= request_count_q + 1'b1;
                2'b01: request_count_q <= request_count_q - 1'b1;
                default: request_count_q <= request_count_q;
            endcase

            if (head_request_dequeue)
                head_request_valid_q <= 1'b0;
            if (head_request_enqueue) begin
                head_request_q <= req_i;
                head_request_q.valid <= 1'b1;
                head_request_valid_q <= 1'b1;
            end

            if (store_buffer_dequeue)
                store_head_q <= store_head_q + 1'b1;
            if (store_buffer_enqueue) begin
                store_buffer_q[store_tail_q] <= active_pkt;
                store_buffer_q[store_tail_q].valid <= 1'b1;
                store_buffer_q[store_tail_q].store_data <=
                    active_store_aligned_data;
                store_buffer_q[store_tail_q].store_data_valid <= 1'b1;
                store_tail_q <= store_tail_q + 1'b1;
            end
            unique case ({store_buffer_enqueue, store_buffer_dequeue})
                2'b10: store_buffer_count_q <= store_buffer_count_q + 1'b1;
                2'b01: store_buffer_count_q <= store_buffer_count_q - 1'b1;
                default: store_buffer_count_q <= store_buffer_count_q;
            endcase

            if (dtcm_store_wb_out_valid)
                dtcm_store_wb_valid_q <= 1'b0;
            if (store_buffer_dequeue) begin
                dtcm_store_wb_valid_q <= 1'b1;
                dtcm_store_wb_producer_id_q <=
                    store_buffer_q[store_head_q].producer_id;
                dtcm_store_wb_producer_tracked_q <=
                    store_buffer_q[store_head_q].producer_tracked;
            end

            load_rsp_valid_q <= dtcm_load_fire;
            if (dtcm_load_fire) begin
                load_rsp_rd_addr_q <= active_pkt.rd_addr;
                load_rsp_producer_id_q <= active_pkt.producer_id;
                load_rsp_producer_tracked_q <= active_pkt.producer_tracked;
                load_rsp_op_q <= active_pkt.op;
                load_rsp_addr_index_q <= active_pkt.addr[1:0];
                load_rsp_forward_mask_q <= load_forward_mask;
                load_rsp_forward_data_q <= load_forward_data;
                load_rsp_fp_load_q <= active_pkt.fp_load;
                load_rsp_fp_rd_addr_q <= active_pkt.fp_rd_addr;
            end

            // A response for a token squashed in an earlier redirect has no
            // consumer.  Drop the response state so it cannot retain the
            // single MMIO port indefinitely.
            if (mmio_wb_valid_q && !mmio_wb_live_dir)
                mmio_wb_valid_q <= 1'b0;
            if (mmio_wb_out_valid)
                mmio_wb_valid_q <= 1'b0;
            if (mmio_rsp_fire) begin
                mmio_req_valid_q <= 1'b0;
                // Both reads and writes retire only after the fabric has
                // acknowledged the held transaction.  A store carries an
                // address of zero and a zero result, so it cannot write GPRs.
                mmio_wb_valid_q <= mmio_producer_tracked_q &&
                    (!redirect_i || mmio_req_recovery_kept);
                mmio_wb_result_q <= mmio_is_load_q ? mmio_load_result : '0;
                mmio_wb_rd_addr_q <= mmio_rd_addr_q;
                mmio_wb_producer_id_q <= mmio_producer_id_q;
                mmio_wb_producer_tracked_q <= mmio_producer_tracked_q &&
                    (!redirect_i || mmio_req_recovery_kept);
                mmio_wb_fp_load_q <= mmio_fp_load_q;
                mmio_wb_fp_rd_addr_q <= mmio_fp_rd_addr_q;
            end
            if (mmio_fire) begin
                mmio_req_valid_q <= 1'b1;
                mmio_is_load_q <= active_pkt.is_load;
                mmio_addr_q <= active_pkt.addr;
                mmio_wdata_q <= active_store_aligned_data;
                mmio_wmask_q <= active_pkt.store_mask;
                mmio_addr_index_q <= active_pkt.addr[1:0];
                mmio_op_q <= active_pkt.op;
                mmio_rd_addr_q <= active_pkt.rd_addr;
                mmio_producer_id_q <= active_pkt.producer_id;
                mmio_producer_tracked_q <= active_pkt.producer_tracked;
                mmio_fp_load_q <= active_pkt.fp_load;
                mmio_fp_rd_addr_q <= active_pkt.fp_rd_addr;
            end

            if (redirect_i) begin
                // The stage-one reservation corresponds to req_i at this
                // edge and is consumed or squashed.  The younger stage-zero
                // reservation remains only when its producer survives.
                reserve_s0_q <= '0;
                reserve_s1_q <= '0;
                if (reserve_s0_live)
                    reserve_s1_q <= reserve_s0_q;

                request_count_q <= request_recovery_count;
                request_valid_q <= request_recovery_valid;
                store_buffer_count_q <= store_recovery_count;
                store_head_q <= '0;
                store_tail_q <= store_recovery_count[$clog2(STORE_BUFFER_DEPTH)-1:0];
                for (recovery_i = 0; recovery_i < STORE_BUFFER_DEPTH;
                     recovery_i = recovery_i + 1)
                    store_buffer_q[recovery_i] <= store_recovery_q[recovery_i];

                if (!load_rsp_survives_redirect)
                    load_rsp_valid_q <= dtcm_load_fire;
                if (!head_request_survives_redirect && !head_request_enqueue)
                    head_request_valid_q <= 1'b0;
                // A new head MMIO request may issue in the same cycle as a
                // younger branch resolves.  It is an older instruction and
                // therefore survives that redirect; do not let cleanup for
                // the previous token overwrite its just-captured context.
                if (!mmio_req_survives_redirect && !mmio_fire) begin
                    mmio_producer_tracked_q <= 1'b0;
                    mmio_fp_load_q <= 1'b0;
                end
                // Likewise, a response arriving with the redirect creates a
                // fresh writeback token.  Its keep decision is derived from
                // the request token above, not from the old writeback state.
                if (!mmio_wb_survives_redirect && !mmio_rsp_fire) begin
                    mmio_wb_valid_q <= 1'b0;
                    mmio_wb_producer_tracked_q <= 1'b0;
                    mmio_wb_fp_load_q <= 1'b0;
                end
                // A store dequeued in this edge has already passed the
                // redirect keep check.  Its freshly-created acknowledgement
                // must take precedence over the old acknowledgement state.
                if (!dtcm_store_wb_survives_redirect &&
                    !store_buffer_dequeue) begin
                    dtcm_store_wb_valid_q <= 1'b0;
                    dtcm_store_wb_producer_tracked_q <= 1'b0;
                end
            end

            if (kill_i) begin
                reserve_s0_q <= '0;
                reserve_s1_q <= '0;
                request_valid_q <= '0;
                request_count_q <= '0;
                head_request_valid_q <= 1'b0;
                load_rsp_valid_q <= 1'b0;
            end

`ifndef SYNTHESIS
            if (!redirect_i && !kill_i && reserve_i_live && !accept_ready &&
                !(reserve_i.producer_id == rob_head_tag_i &&
                  !head_request_valid_q && !head_reservation_inflight))
                $fatal(1, "LSU reservation accepted without a request slot");
            if (!redirect_i && !kill_i && req_i.valid && req_live_dir &&
                (!reserve_s1_q.valid ||
                 reserve_s1_q.producer_id != req_i.producer_id ||
                 reserve_s1_q.producer_tracked != req_i.producer_tracked))
                $fatal(1, "LSU request/reservation mismatch req=%b/%0h/%b s1=%b/%0h/%b s0=%b/%0h/%b ingress=%b/%0h/%b",
                    req_i.valid, req_i.producer_id, req_i.producer_tracked,
                    reserve_s1_q.valid, reserve_s1_q.producer_id,
                    reserve_s1_q.producer_tracked, reserve_s0_q.valid,
                    reserve_s0_q.producer_id, reserve_s0_q.producer_tracked,
                    reserve_i.valid, reserve_i.producer_id,
                    reserve_i.producer_tracked);
            if (!redirect_i && !kill_i && req_i.valid && req_live_dir &&
                !request_slot_after_dequeue && !head_request_enqueue)
                $fatal(1, "LSU request FIFO overflow");
            if (!redirect_i && !kill_i && head_request_enqueue &&
                (!reserve_s1_q.valid || req_i.producer_id != rob_head_tag_i))
                $fatal(1, "LSU head ingress accepted a non-head request");
            if (request_count_q > REQUEST_COUNT_WIDTH'(REQUEST_DEPTH))
                $fatal(1, "LSU request FIFO count overflow");
            if (store_buffer_count_q > STORE_COUNT_WIDTH'(STORE_BUFFER_DEPTH))
                $fatal(1, "LSU store buffer count overflow");
            if (redirect_i && mmio_fire)
                assert (active_survives_redirect)
                    else $fatal(1, "redirect attempted to launch squashed MMIO request");
`endif
        end
    end
endmodule
