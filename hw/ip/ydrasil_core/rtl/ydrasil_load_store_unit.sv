module ydrasil_load_store_unit
import ydrasil_pkg::*;
(
    input  wire                            clk,
	    input  wire                            rst_n,
	    input  ydrasil_lsu_req_pkt_t           req_i,
	    input  wire                            req_raw_valid_i,
	    input  wire [DTCM_ADDR_WIDTH-1:0]      req_dtcm_word_addr_i,
	    input  wire                            commit0_valid_i,
	    input  producer_id_t                   commit0_id_i,
	    input  wire                            commit1_valid_i,
	    input  producer_id_t                   commit1_id_i,
	    input  wire                            branch_recovery_i,
	    input  wire                            trap_flush_i,
	    input  producer_slot_t                 recovery_head_slot_i,
	    input  producer_slot_t                 recovery_branch_slot_i,
	    input  producer_id_t                   rob_head_id_i,
		    input  ydrasil_completion_meta_t       completion_meta_i [COMPLETION_LANES],
		    input  wire [REGS_DATA_WIDTH-1:0]      completion_data_i [COMPLETION_LANES],
	    input  wire [BUS_DATA_WIDTH-1:0]       dtcm_rdata_i,
	    output wire                            dtcm_load_valid_o,
	    output wire [BUS_ADDR_WIDTH-1:0]       dtcm_load_addr_o,
	    output wire [DTCM_ADDR_WIDTH-1:0]      dtcm_load_word_addr_o,
	    output wire                            dtcm_store_valid_o,
	    output wire [BUS_ADDR_WIDTH-1:0]       dtcm_store_addr_o,
	    output wire [BUS_DATA_WIDTH-1:0]       dtcm_store_data_o,
	    output wire [3:0]                      dtcm_store_mask_o,
    input  ydrasil_mem_rsp_pkt_t           mmio_rsp_i,
    // Explicit request boundary for the single outstanding AXI transaction.
    // A response may still be retiring while the master is not able to
    // accept a new request; keeping this boundary local prevents an old
    // response from clearing a newly launched LSU request.
    input  wire                            mmio_ready_i,
    output ydrasil_mem_req_pkt_t           mmio_req_o,
    output ydrasil_lsu_status_pkt_t        status_o,
	    output wire [1:0]                     issue_credit_o,
	    output ydrasil_reservation_pkt_t      dtcm_reservation_o,
	    output wire                            dtcm_launch_wakeup_valid_o,
	    output producer_id_t                   dtcm_launch_wakeup_id_o,
		output wire [REGS_DATA_WIDTH-1:0]     dtcm_resp_data_o,
	output wire                            completion_valid_o,
	output wire [REGS_DATA_WIDTH-1:0]      completion_data_o,
	output wire [REGS_ADDR_WIDTH-1:0]      completion_addr_o,
		output producer_id_t                   completion_producer_id_o,
		output wire                            completion_producer_tracked_o,
		output wire                            fp_completion_valid_o,
		output wire [REGS_ADDR_WIDTH-1:0]      fp_completion_addr_o,
		output wire [FPU_DATA_WIDTH-1:0]       fp_completion_data_o
);
    localparam int QUEUE_DEPTH = 2;
    localparam int STORE_BUFFER_DEPTH = 2;
    localparam int QUEUE_COUNT_WIDTH = $clog2(QUEUE_DEPTH + 1);
    localparam int STORE_COUNT_WIDTH = $clog2(STORE_BUFFER_DEPTH + 1);
    localparam int PRODUCER_AGE_WIDTH = PRODUCER_SLOT_WIDTH + 1;

    function automatic logic [PRODUCER_AGE_WIDTH-1:0]
        producer_age_from_head(input producer_id_t producer_id);
        logic [PRODUCER_AGE_WIDTH-1:0] producer_slot_ext;
        logic [PRODUCER_AGE_WIDTH-1:0] rob_head_slot_ext;
        begin
            producer_slot_ext = {1'b0,
                producer_id[PRODUCER_SLOT_WIDTH-1:0]};
            rob_head_slot_ext = {1'b0,
                rob_head_id_i[PRODUCER_SLOT_WIDTH-1:0]};
            producer_age_from_head =
                (producer_slot_ext >= rob_head_slot_ext) ?
                (producer_slot_ext - rob_head_slot_ext) :
                (PRODUCER_AGE_WIDTH'(PRODUCER_NUM) -
                 rob_head_slot_ext + producer_slot_ext);
        end
    endfunction

    ydrasil_lsu_req_pkt_t queue_q [0:QUEUE_DEPTH-1];
    reg [QUEUE_COUNT_WIDTH-1:0] queue_count_q;
    reg [QUEUE_COUNT_WIDTH-1:0] issue_credit_q;
    reg [$clog2(QUEUE_DEPTH)-1:0] queue_head_q;
    reg [$clog2(QUEUE_DEPTH)-1:0] queue_tail_q;
    // Only the fields below survive after a store has left the request queue.
    // Keeping the full LSU request packet in this tiny FIFO turns every
    // forwarding lookup into a wide four-way table, even though most fields
    // are dead.  Store entries are maintained in age order (entry 0 is the
    // drain head), so the forwarding CAM can use direct registers rather than
    // pointer-indexed array reads.
	    typedef struct packed {
	        logic                         valid;
	        logic                         retired;
	        producer_id_t                 producer_id;
	        logic [BUS_ADDR_WIDTH-1:0]    addr;
	        logic [BUS_DATA_WIDTH-1:0]    store_data;
	        logic [3:0]                   store_mask;
	        logic                         store_data_valid;
	        producer_id_t                 store_producer_id;
	        logic                         store_producer_tracked;
	    } store_buf_entry_t;
	    store_buf_entry_t store_buf0_q;
	    store_buf_entry_t store_buf1_q;
	    store_buf_entry_t store_enqueue_pkt;
	    reg [STORE_COUNT_WIDTH-1:0] store_buf_count_q;

	    // Completion data stops at this local FF boundary. Queue and store-buffer
	    // entries consume only registered shadows, so an execution result never
	    // drives every LSU entry and its multiwrite priority logic in one cycle.
	    // Keep one extra dual-lane sample for a redirected JAL target store.
	    localparam int STORE_COMPLETION_SHADOWS = COMPLETION_LANES + 1;
	    logic completion_shadow_valid_q [0:STORE_COMPLETION_SHADOWS-1];
	    producer_id_t completion_shadow_id_q [0:STORE_COMPLETION_SHADOWS-1];
	    logic [BUS_DATA_WIDTH-1:0] completion_shadow_data_q
	        [0:STORE_COMPLETION_SHADOWS-1];
	    logic commit_valid_q [0:1];
	    producer_id_t commit_id_q [0:1];
	    reg recovery_pending_q;
	    producer_slot_t recovery_head_slot_q;
	    producer_slot_t recovery_branch_slot_q;

	    ydrasil_lsu_req_pkt_t patched_queue0;
	    ydrasil_lsu_req_pkt_t patched_queue1;
	    store_buf_entry_t patched_store_buf0;
	    store_buf_entry_t patched_store_buf1;
	    integer completion_patch_idx;
	    always_comb begin
	        patched_queue0 = queue_q[0];
	        patched_queue1 = queue_q[1];
	        patched_store_buf0 = store_buf0_q;
	        patched_store_buf1 = store_buf1_q;

	        if (queue_q[0].valid && queue_q[0].is_store &&
	            ((commit_valid_q[0] &&
	              (commit_id_q[0] == queue_q[0].producer_id)) ||
	             (commit_valid_q[1] &&
	              (commit_id_q[1] == queue_q[0].producer_id))))
	            patched_queue0.retired = 1'b1;
	        if (queue_q[1].valid && queue_q[1].is_store &&
	            ((commit_valid_q[0] &&
	              (commit_id_q[0] == queue_q[1].producer_id)) ||
	             (commit_valid_q[1] &&
	              (commit_id_q[1] == queue_q[1].producer_id))))
	            patched_queue1.retired = 1'b1;
	        if (store_buf0_q.valid &&
	            ((commit_valid_q[0] &&
	              (commit_id_q[0] == store_buf0_q.producer_id)) ||
	             (commit_valid_q[1] &&
	              (commit_id_q[1] == store_buf0_q.producer_id))))
	            patched_store_buf0.retired = 1'b1;
	        if (store_buf1_q.valid &&
	            ((commit_valid_q[0] &&
	              (commit_id_q[0] == store_buf1_q.producer_id)) ||
	             (commit_valid_q[1] &&
	              (commit_id_q[1] == store_buf1_q.producer_id))))
	            patched_store_buf1.retired = 1'b1;

	        for (completion_patch_idx = 0;
	             completion_patch_idx < STORE_COMPLETION_SHADOWS;
	             completion_patch_idx = completion_patch_idx + 1) begin
	            if (queue_q[0].valid && queue_q[0].is_store &&
	                !queue_q[0].store_data_valid &&
	                queue_q[0].store_producer_tracked &&
	                completion_shadow_valid_q[completion_patch_idx] &&
	                (completion_shadow_id_q[completion_patch_idx] ==
	                 queue_q[0].store_producer_id)) begin
	                patched_queue0.store_data =
	                    completion_shadow_data_q[completion_patch_idx];
	                patched_queue0.store_data_valid = 1'b1;
	                patched_queue0.store_producer_tracked = 1'b0;
	            end
	            if (queue_q[1].valid && queue_q[1].is_store &&
	                !queue_q[1].store_data_valid &&
	                queue_q[1].store_producer_tracked &&
	                completion_shadow_valid_q[completion_patch_idx] &&
	                (completion_shadow_id_q[completion_patch_idx] ==
	                 queue_q[1].store_producer_id)) begin
	                patched_queue1.store_data =
	                    completion_shadow_data_q[completion_patch_idx];
	                patched_queue1.store_data_valid = 1'b1;
	                patched_queue1.store_producer_tracked = 1'b0;
	            end
	            if (store_buf0_q.valid && !store_buf0_q.store_data_valid &&
	                store_buf0_q.store_producer_tracked &&
	                completion_shadow_valid_q[completion_patch_idx] &&
	                (completion_shadow_id_q[completion_patch_idx] ==
	                 store_buf0_q.store_producer_id)) begin
	                unique case (store_buf0_q.store_mask)
	                    4'b0001: patched_store_buf0.store_data =
	                        {24'b0, completion_shadow_data_q[
	                            completion_patch_idx][7:0]};
	                    4'b0010: patched_store_buf0.store_data =
	                        {16'b0, completion_shadow_data_q[
	                            completion_patch_idx][7:0], 8'b0};
	                    4'b0100: patched_store_buf0.store_data =
	                        {8'b0, completion_shadow_data_q[
	                            completion_patch_idx][7:0], 16'b0};
	                    4'b1000: patched_store_buf0.store_data =
	                        {completion_shadow_data_q[
	                            completion_patch_idx][7:0], 24'b0};
	                    4'b0011: patched_store_buf0.store_data =
	                        {16'b0, completion_shadow_data_q[
	                            completion_patch_idx][15:0]};
	                    4'b1100: patched_store_buf0.store_data =
	                        {completion_shadow_data_q[
	                            completion_patch_idx][15:0], 16'b0};
	                    default: patched_store_buf0.store_data =
	                        completion_shadow_data_q[completion_patch_idx];
	                endcase
	                patched_store_buf0.store_data_valid = 1'b1;
	                patched_store_buf0.store_producer_tracked = 1'b0;
	            end
	            if (store_buf1_q.valid && !store_buf1_q.store_data_valid &&
	                store_buf1_q.store_producer_tracked &&
	                completion_shadow_valid_q[completion_patch_idx] &&
	                (completion_shadow_id_q[completion_patch_idx] ==
	                 store_buf1_q.store_producer_id)) begin
	                unique case (store_buf1_q.store_mask)
	                    4'b0001: patched_store_buf1.store_data =
	                        {24'b0, completion_shadow_data_q[
	                            completion_patch_idx][7:0]};
	                    4'b0010: patched_store_buf1.store_data =
	                        {16'b0, completion_shadow_data_q[
	                            completion_patch_idx][7:0], 8'b0};
	                    4'b0100: patched_store_buf1.store_data =
	                        {8'b0, completion_shadow_data_q[
	                            completion_patch_idx][7:0], 16'b0};
	                    4'b1000: patched_store_buf1.store_data =
	                        {completion_shadow_data_q[
	                            completion_patch_idx][7:0], 24'b0};
	                    4'b0011: patched_store_buf1.store_data =
	                        {16'b0, completion_shadow_data_q[
	                            completion_patch_idx][15:0]};
	                    4'b1100: patched_store_buf1.store_data =
	                        {completion_shadow_data_q[
	                            completion_patch_idx][15:0], 16'b0};
	                    default: patched_store_buf1.store_data =
	                        completion_shadow_data_q[completion_patch_idx];
	                endcase
	                patched_store_buf1.store_data_valid = 1'b1;
	                patched_store_buf1.store_producer_tracked = 1'b0;
	            end
	        end
	    end

    wire queue_empty = queue_count_q == '0;
    wire queue_full = queue_count_q == QUEUE_COUNT_WIDTH'(QUEUE_DEPTH);
    wire store_buf_empty = store_buf_count_q == '0;
    wire store_buf_full =
        store_buf_count_q == STORE_COUNT_WIDTH'(STORE_BUFFER_DEPTH);

	    wire store_head_data_valid = !store_buf_empty &&
	        store_buf0_q.store_data_valid && store_buf0_q.retired;
    wire [31:0] store_head_wdata = store_buf0_q.store_data;
    wire store_buf_dequeue = store_head_data_valid;

	    ydrasil_lsu_req_pkt_t active_pkt;
	    ydrasil_lsu_req_pkt_t second_pkt;
	    ydrasil_lsu_req_pkt_t patched_active_pkt;
	    ydrasil_lsu_req_pkt_t patched_second_pkt;
	    wire [$clog2(QUEUE_DEPTH)-1:0] queue_second_index =
	        queue_head_q + 1'b1;
	    // Queue patching commits into queue_q at the clock edge. Execution and
	    // DTCM launch consume only the previously registered queue image so ROB
	    // retirement/completion data cannot cross the LSU and memory boundary in
	    // one cycle.
	    assign active_pkt = queue_head_q[0] ? queue_q[1] : queue_q[0];
	    assign second_pkt = queue_head_q[0] ? queue_q[0] : queue_q[1];
	    assign patched_active_pkt = queue_head_q[0] ?
	        patched_queue1 : patched_queue0;
	    assign patched_second_pkt = queue_head_q[0] ?
	        patched_queue0 : patched_queue1;

    wire active_valid = !queue_empty && active_pkt.valid;
    wire active_is_load = active_pkt.is_load;
    wire active_is_store = active_pkt.is_store;
    wire [OP_LSU_INFO_WIDTH-1:0] active_op = active_pkt.op;
    wire [BUS_ADDR_WIDTH-1:0] active_addr = active_pkt.addr;
    wire active_addr_is_dtcm = active_pkt.addr_is_dtcm;
    wire [REGS_ADDR_WIDTH-1:0] active_rd_addr = active_pkt.rd_addr;
    wire [PRODUCER_ID_WIDTH-1:0] active_producer_id = active_pkt.producer_id;
    wire active_producer_tracked = active_pkt.producer_tracked;
    wire active_fp_load = active_pkt.fp_load;
    wire active_fp_store = active_pkt.fp_store;
    wire active_fp_memory = active_fp_load || active_fp_store;
    wire active_fp_double = active_fp_memory && active_pkt.fp_double;
    wire [REGS_ADDR_WIDTH-1:0] active_fp_rd_addr = active_pkt.fp_rd_addr;
    wire [FPU_DATA_WIDTH-1:0] active_fp_store_data = active_pkt.fp_store_data;
    wire [63:0] active_fp_store_data64 =
        {{(64-FPU_DATA_WIDTH){1'b0}}, active_fp_store_data};
    wire [BUS_DATA_WIDTH-1:0] active_store_data = active_pkt.store_data;
    wire [3:0] active_store_mask = active_fp_store ? 4'b1111 :
        active_pkt.store_mask;
    wire active_store_data_valid = active_pkt.store_data_valid;
    wire active_dtcm_load = active_valid && active_addr_is_dtcm && active_is_load;
    wire active_dtcm_store = active_valid && active_addr_is_dtcm && active_is_store;
	    wire active_mmio = active_valid && !active_addr_is_dtcm;
	    wire active_at_rob_head =
	        active_pkt.producer_id == rob_head_id_i;
    wire active_mmio_order_safe = active_at_rob_head ||
        (active_is_store && active_pkt.retired);
    reg fp_double_phase_q;
    wire [BUS_ADDR_WIDTH-1:0] active_beat_addr = active_addr +
        (active_fp_double && fp_double_phase_q ? 32'd4 : 32'd0);
    wire [1:0] active_addr_index = active_beat_addr[1:0];
    wire active_sequence_done = !active_fp_double || fp_double_phase_q;
	    wire second_is_older =
	        producer_age_from_head(second_pkt.producer_id) <
	        producer_age_from_head(active_pkt.producer_id);
	    // Load-load OoO can enqueue a younger speculative MMIO request before an
	    // older request whose address was dependency-blocked.  MMIO must wait at
	    // ROB head, so leaving that younger request at the FIFO head deadlocks the
	    // older request and the ROB.  Repair only the two registered queue cells;
	    // the normal DTCM launch payload remains on its existing registered path.
	    wire queue_age_repair =
	        (queue_count_q == QUEUE_COUNT_WIDTH'(QUEUE_DEPTH)) &&
	        active_mmio && !active_mmio_order_safe &&
	        active_pkt.producer_tracked && second_pkt.valid &&
	        second_pkt.producer_tracked && second_is_older;

    reg mmio_req_valid_q;
    reg mmio_is_load_q;
    reg [BUS_ADDR_WIDTH-1:0] mmio_addr_q;
    reg [BUS_DATA_WIDTH-1:0] mmio_wdata_q;
    reg [3:0] mmio_wmask_q;
    reg [1:0] mmio_addr_index_q;
    reg [OP_LSU_INFO_WIDTH-1:0] mmio_operator_lsu_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_rd_addr_q;
    producer_id_t mmio_producer_id_q;
    reg mmio_producer_tracked_q;
    reg mmio_fp_load_q;
    reg mmio_fp_double_q;
    reg mmio_fp_second_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_fp_rd_addr_q;
    reg mmio_wb_valid_q;
    reg [31:0] mmio_wb_result_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_rd_addr_q;
    producer_id_t mmio_wb_producer_id_q;
    reg mmio_wb_producer_tracked_q;
    reg mmio_wb_fp_load_q;
    reg [63:0] mmio_wb_fp_data_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_fp_rd_addr_q;
    wire mmio_busy = mmio_req_valid_q || mmio_wb_valid_q;

    reg load_s1_valid_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s1_rd_addr_q;
    producer_id_t load_s1_producer_id_q;
    reg load_s1_producer_tracked_q;
    reg [OP_LSU_INFO_WIDTH-1:0] load_s1_op_q;
    reg [1:0] load_s1_addr_index_q;
    reg [3:0] load_s1_forward_mask_q;
    reg [31:0] load_s1_forward_data_q;
    reg load_s1_fp_load_q;
    reg load_s1_fp_double_q;
    reg load_s1_fp_second_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s1_fp_rd_addr_q;
    reg [31:0] fp_double_low_q;
    reg store_launch_valid_q;
    reg [BUS_ADDR_WIDTH-1:0] store_launch_addr_q;
    reg [BUS_DATA_WIDTH-1:0] store_launch_data_q;
    reg [3:0] store_launch_mask_q;
    // Give a buffered peripheral response a bounded path to completion. At
    // most one already-issued DTCM response remains after this hold asserts.
    // MMIO responses are buffered in mmio_wb_valid_q. If one arrives on the
    // same edge as a DTCM launch, DTCM completes first and the buffered MMIO
    // value follows; AXI r_fire must not control the DTCM BRAM port directly.
    wire load_issue_hold = mmio_wb_valid_q;
	    // Every memory request crosses the registered request queue. The registered
	    // queue head may launch the BRAM directly; a second launch register adds
	    // latency without breaking another combinational control dependency.
	    // Empty-queue loads issue a speculative BRAM read before address-space
	    // qualification.  The enable depends only on registered request type and
	    // registered empty state; recovery, the DTCM range compare and the store
	    // forwarding CAM remain off the BRAM control path.  A non-DTCM request
	    // merely causes an ignored read and still enters the normal MMIO queue.
    wire fast_dtcm_probe = queue_empty && req_raw_valid_i && req_i.is_load &&
        !req_i.fp_load && store_buf_empty && !store_launch_valid_q &&
        !load_issue_hold;
	    wire fast_dtcm_load_fire = fast_dtcm_probe && req_i.valid &&
	        req_i.addr_is_dtcm;
	    wire queued_dtcm_load_candidate = active_dtcm_load && !load_issue_hold;
	    // The BRAM address path has only the registered queue-empty select.  All
	    // other qualification applies to response metadata, not to the RAM pin.
    wire [BUS_ADDR_WIDTH-1:0] dtcm_read_addr = queue_empty ?
        req_i.addr : active_beat_addr;
    wire [DTCM_ADDR_WIDTH-1:0] dtcm_read_word_addr = queue_empty ?
        req_dtcm_word_addr_i : active_beat_addr[DTCM_ADDR_WIDTH+1:2];
    wire [BUS_ADDR_WIDTH-1:0] load_launch_addr = fast_dtcm_load_fire ?
        req_i.addr : active_beat_addr;
	    wire [REGS_ADDR_WIDTH-1:0] load_launch_rd_addr = fast_dtcm_load_fire ?
	        req_i.rd_addr : active_rd_addr;
	    wire producer_id_t load_launch_producer_id = fast_dtcm_load_fire ?
	        req_i.producer_id : active_producer_id;
	    wire load_launch_producer_tracked = fast_dtcm_load_fire ?
	        req_i.producer_tracked : active_producer_tracked;
    wire [OP_LSU_INFO_WIDTH-1:0] load_launch_op = fast_dtcm_load_fire ?
        req_i.op : active_op;
    wire load_launch_fp_load = fast_dtcm_load_fire ? req_i.fp_load :
        active_fp_load;
    wire load_launch_fp_double = fast_dtcm_load_fire ? req_i.fp_double :
        active_fp_double;
    wire [REGS_ADDR_WIDTH-1:0] load_launch_fp_rd_addr =
        fast_dtcm_load_fire ? req_i.fp_rd_addr : active_fp_rd_addr;
    wire load_launch_fp_second = fast_dtcm_load_fire ? 1'b0 :
        (active_fp_double && fp_double_phase_q);

    // Two age-ordered entries cover the measured forwarding use while
    // removing half of the address CAM and its newest-store priority tree.
	    wire store_hit0 = (store_buf_count_q > STORE_COUNT_WIDTH'(0)) &&
	        store_buf0_q.valid &&
        (store_buf0_q.addr[BUS_ADDR_WIDTH-1:2] ==
         active_beat_addr[BUS_ADDR_WIDTH-1:2]);
	    wire store_hit1 = (store_buf_count_q > STORE_COUNT_WIDTH'(1)) &&
	        store_buf1_q.valid &&
        (store_buf1_q.addr[BUS_ADDR_WIDTH-1:2] ==
         active_beat_addr[BUS_ADDR_WIDTH-1:2]);
	    // A retired store spends one cycle in the launch register after leaving
	    // the buffer. A same-word load in that cycle must not observe the
	    // read-before-write value returned by the DTCM.
	    wire store_launch_hit = store_launch_valid_q &&
        (store_launch_addr_q[BUS_ADDR_WIDTH-1:2] ==
         active_beat_addr[BUS_ADDR_WIDTH-1:2]);
	    wire load_store_data_block =
	        (store_hit0 && !store_buf0_q.store_data_valid) ||
	        (store_hit1 && !store_buf1_q.store_data_valid);
	    wire queued_dtcm_load_fire = queued_dtcm_load_candidate &&
	        !load_store_data_block;
	    wire dtcm_load_fire = queued_dtcm_load_fire || fast_dtcm_load_fire;
	    wire dtcm_bram_read = queued_dtcm_load_fire || fast_dtcm_probe;
	    wire [3:0] forward_mask0 = {4{store_hit0}} &
	        store_buf0_q.store_mask;
	    wire [3:0] forward_mask1 = {4{store_hit1}} &
	        store_buf1_q.store_mask;
	    wire [3:0] forward_mask_launch = {4{store_launch_hit}} &
	        store_launch_mask_q;
	    wire [3:0] load_forward_mask = forward_mask_launch |
	        forward_mask0 | forward_mask1;
	    wire [31:0] load_forward_data = {
	        forward_mask1[3] ? store_buf1_q.store_data[31:24] :
	        forward_mask0[3] ? store_buf0_q.store_data[31:24] :
	                           store_launch_data_q[31:24],
	        forward_mask1[2] ? store_buf1_q.store_data[23:16] :
	        forward_mask0[2] ? store_buf0_q.store_data[23:16] :
	                           store_launch_data_q[23:16],
	        forward_mask1[1] ? store_buf1_q.store_data[15:8] :
	        forward_mask0[1] ? store_buf0_q.store_data[15:8] :
	                           store_launch_data_q[15:8],
	        forward_mask1[0] ? store_buf1_q.store_data[7:0] :
	        forward_mask0[0] ? store_buf0_q.store_data[7:0] :
	                           store_launch_data_q[7:0]
	    };

    wire store_buf_has_room = !store_buf_full || store_buf_dequeue;
    wire dtcm_store_fire = active_dtcm_store && store_buf_has_room;
    // MMIO observes all older buffered stores before it starts. Once launched,
    // younger DTCM requests can proceed independently while APB is busy.
	    wire mmio_fire = active_mmio && active_mmio_order_safe &&
	        !mmio_busy && mmio_ready_i && store_buf_empty &&
        (!active_is_store || active_store_data_valid);
    wire queue_dequeue = (queued_dtcm_load_fire || dtcm_store_fire ||
        mmio_fire) && active_sequence_done;
    wire queue_has_room_after_dequeue = !queue_full || queue_dequeue;
	    wire queue_enqueue = req_i.valid && queue_has_room_after_dequeue &&
	        !fast_dtcm_load_fire;
	    // A fast empty-queue load is consumed directly and does not advance the
	    // logical FIFO. Still write its payload into the physically free tail
	    // cell. The entry remains hidden by queue_count_q and is overwritten by
	    // the next logical enqueue, while the wide queue register enables no
	    // longer depend on address-space qualification or fast-load selection.
	    wire queue_physical_write = req_i.valid && queue_has_room_after_dequeue;
    wire store_buf_enqueue = dtcm_store_fire;
`ifndef SYNTHESIS
    reg [31:0] perf_stb_lookup_q;
    reg [31:0] perf_stb_hit_q;
    reg [31:0] perf_stb_block_q;
    reg [31:0] perf_stb_drain_q;
`endif

    // Backpressure reflects request-queue capacity. Store-buffer pressure is
    // absorbed behind this FF boundary and only stops the queue head when all
    // four entries are actually occupied.
    assign status_o.busy = queue_full ||
        (req_i.valid &&
         (queue_count_q >= QUEUE_COUNT_WIDTH'(QUEUE_DEPTH-1)));
    assign status_o.idle = queue_empty && !req_i.valid && store_buf_empty &&
        !mmio_busy && !store_launch_valid_q &&
        !load_s1_valid_q;
    assign status_o.fast_load = 1'b0;
    // Export only registered queue capacity. Issue locally reserves its
    // registered AGU request, keeping request payload and DTCM decisions out
    // of the next Issue selection cone.
    assign issue_credit_o = issue_credit_q;

	    assign dtcm_load_valid_o = dtcm_bram_read;
	    assign dtcm_load_addr_o = dtcm_read_addr;
	    assign dtcm_load_word_addr_o = dtcm_read_word_addr;
	    assign dtcm_store_valid_o = store_launch_valid_q;
	    assign dtcm_store_addr_o = store_launch_addr_q;
	    assign dtcm_store_data_o = store_launch_data_q;
	    assign dtcm_store_mask_o = store_launch_mask_q;

    assign mmio_req_o.valid = mmio_req_valid_q;
    assign mmio_req_o.write = mmio_req_valid_q && !mmio_is_load_q;
    assign mmio_req_o.addr = mmio_addr_q;
    assign mmio_req_o.wdata = mmio_wdata_q;
    // Keep the request packet acyclic.  Reading mmio_req_o.write here makes
    // the lint tool treat the packed output as self-feedback even though write is
    // another field driven by the same registered state.
    assign mmio_req_o.wmask = (mmio_req_valid_q && !mmio_is_load_q) ?
        mmio_wmask_q : 4'b0;

    wire [7:0] dtcm_load_byte0 = load_s1_forward_mask_q[0] ?
        load_s1_forward_data_q[7:0] : dtcm_rdata_i[7:0];
    wire [7:0] dtcm_load_byte1 = load_s1_forward_mask_q[1] ?
        load_s1_forward_data_q[15:8] : dtcm_rdata_i[15:8];
    wire [7:0] dtcm_load_byte2 = load_s1_forward_mask_q[2] ?
        load_s1_forward_data_q[23:16] : dtcm_rdata_i[23:16];
    wire [7:0] dtcm_load_byte3 = load_s1_forward_mask_q[3] ?
        load_s1_forward_data_q[31:24] : dtcm_rdata_i[31:24];
    reg [7:0] dtcm_load_low_byte;
    reg [7:0] dtcm_load_high_byte;
    reg [31:0] dtcm_load_shifted_word;
    reg [31:0] dtcm_load_result;
    reg [31:0] mmio_load_result;

    // Select the bytes that each architectural result actually consumes.
    // This preserves the old zero-filled right-shift behavior for every low
    // address value, including a halfword at offset three, while avoiding a
    // shared 32-bit barrel shifter between the DTCM BRAM and all FU inputs.
    always_comb begin
        dtcm_load_low_byte = dtcm_load_byte0;
        dtcm_load_high_byte = dtcm_load_byte1;
        dtcm_load_shifted_word = {
            dtcm_load_byte3, dtcm_load_byte2,
            dtcm_load_byte1, dtcm_load_byte0
        };
        unique case (load_s1_addr_index_q)
            2'b01: begin
                dtcm_load_low_byte = dtcm_load_byte1;
                dtcm_load_high_byte = dtcm_load_byte2;
                dtcm_load_shifted_word = {
                    8'b0, dtcm_load_byte3,
                    dtcm_load_byte2, dtcm_load_byte1
                };
            end
            2'b10: begin
                dtcm_load_low_byte = dtcm_load_byte2;
                dtcm_load_high_byte = dtcm_load_byte3;
                dtcm_load_shifted_word = {
                    16'b0, dtcm_load_byte3, dtcm_load_byte2
                };
            end
            2'b11: begin
                dtcm_load_low_byte = dtcm_load_byte3;
                dtcm_load_high_byte = 8'b0;
                dtcm_load_shifted_word = {24'b0, dtcm_load_byte3};
            end
            default: begin end
        endcase

        dtcm_load_result = dtcm_load_shifted_word;
        unique case (1'b1)
            load_s1_op_q[OP_LSU_LB]:
                dtcm_load_result = {
                    {24{dtcm_load_low_byte[7]}}, dtcm_load_low_byte
                };
            load_s1_op_q[OP_LSU_LBU]:
                dtcm_load_result = {24'b0, dtcm_load_low_byte};
            load_s1_op_q[OP_LSU_LH]:
                dtcm_load_result = {
                    {16{dtcm_load_high_byte[7]}},
                    dtcm_load_high_byte, dtcm_load_low_byte
                };
            load_s1_op_q[OP_LSU_LHU]:
                dtcm_load_result = {
                    16'b0, dtcm_load_high_byte, dtcm_load_low_byte
                };
            default: begin end
        endcase
    end

    // MMIO is variable latency and already crosses its own response register.
    // Keep its formatter physically independent from the DTCM fast-load cone.
    always_comb begin
        mmio_load_result = mmio_rsp_i.rdata >>
            ({3'b000, mmio_addr_index_q} << 3);
        unique case (1'b1)
            mmio_operator_lsu_q[OP_LSU_LB]:
                mmio_load_result = {{24{mmio_load_result[7]}}, mmio_load_result[7:0]};
            mmio_operator_lsu_q[OP_LSU_LBU]:
                mmio_load_result = {24'b0, mmio_load_result[7:0]};
            mmio_operator_lsu_q[OP_LSU_LH]:
                mmio_load_result = {{16{mmio_load_result[15]}}, mmio_load_result[15:0]};
            mmio_operator_lsu_q[OP_LSU_LHU]:
                mmio_load_result = {16'b0, mmio_load_result[15:0]};
            default: mmio_load_result = mmio_load_result;
        endcase
    end

    // The BRAM output and S1 metadata are the LSU response. Future File is the
    // second response register; a separate load_s2 register would add a third
    // cycle before the value becomes usable.
    // Recovery clears both response-valid registers at its clock edge. A
    // response visible on that edge crosses the registered completion bus once
    // and is accepted only if the post-recovery producer valid/epoch matches.
    // Do not feed the combinational recovery mask back through completion.
    // Recovery is applied to the registered response identity before it can
    // become a completion. A surviving response completes once; a younger
    // response is discarded without holding or replaying the BRAM transaction.
    wire dtcm_wb_valid = load_s1_valid_q &&
        (!recovery_pending_q || producer_slot_in_window(
            load_s1_producer_id_q[PRODUCER_SLOT_WIDTH-1:0],
            recovery_head_slot_q, recovery_branch_slot_q));
    wire mmio_wb_out_valid = mmio_wb_valid_q && !dtcm_wb_valid;
    wire selected_wb_fp_load = dtcm_wb_valid ? load_s1_fp_load_q :
        mmio_wb_fp_load_q;
    wire selected_wb_producer_tracked = dtcm_wb_valid ?
        load_s1_producer_tracked_q : mmio_wb_producer_tracked_q;
    wire [REGS_ADDR_WIDTH-1:0] selected_wb_fp_rd_addr = dtcm_wb_valid ?
        load_s1_fp_rd_addr_q : mmio_wb_fp_rd_addr_q;
    wire dtcm_fp_complete = dtcm_wb_valid && load_s1_fp_load_q &&
        (!load_s1_fp_double_q || load_s1_fp_second_q);
    wire [63:0] dtcm_fp_data64 = load_s1_fp_double_q ?
        {dtcm_load_result, fp_double_low_q} :
        {32'hffff_ffff, dtcm_load_result};
    wire [63:0] selected_fp_data64 = dtcm_wb_valid ? dtcm_fp_data64 :
        mmio_wb_fp_data_q;
    assign completion_valid_o = (dtcm_wb_valid || mmio_wb_out_valid) &&
        selected_wb_producer_tracked && !selected_wb_fp_load;
    assign completion_data_o = dtcm_wb_valid ?
        dtcm_load_result : mmio_wb_result_q;
    assign completion_addr_o = dtcm_wb_valid ?
        load_s1_rd_addr_q : mmio_wb_rd_addr_q;
    assign completion_producer_id_o = dtcm_wb_valid ?
        load_s1_producer_id_q : mmio_wb_producer_id_q;
    assign completion_producer_tracked_o = selected_wb_producer_tracked;
    assign fp_completion_valid_o = dtcm_fp_complete ||
        (mmio_wb_out_valid && selected_wb_fp_load);
    assign fp_completion_addr_o = selected_wb_fp_rd_addr;
    assign fp_completion_data_o = selected_fp_data64[FPU_DATA_WIDTH-1:0];

    // DTCM is fixed-latency. Its registered identity is separate from the
    // MMIO/LSU completion stream; data is only a matched local operand bypass.
    // Wake the RS locally on the actual BRAM launch edge. This gives the ready
    // FF a full cycle before Select without adding load-use latency. Recovery
    // may suppress completion, but must not enter the RS candidate network;
    // Issue independently blocks selection while rebuilding its window.
    assign dtcm_reservation_o.valid = load_s1_valid_q;
    assign dtcm_reservation_o.producer_tracked = load_s1_producer_tracked_q;
    assign dtcm_reservation_o.producer_id = load_s1_producer_id_q;
    assign dtcm_reservation_o.arch_addr = load_s1_rd_addr_q;
    assign dtcm_reservation_o.result_class = RESULT_LSU;
	assign dtcm_launch_wakeup_valid_o = dtcm_load_fire &&
	    load_launch_producer_tracked;
	assign dtcm_launch_wakeup_id_o = load_launch_producer_id;
    // Identity and formatted data describe the same registered S1 response.
    // Issue consumes this only at its Operand/FU input D boundary; it does
    // not feed Select or Dispatch control.
    assign dtcm_resp_data_o = dtcm_load_result;

	ydrasil_lsu_req_pkt_t enqueue_pkt;
	integer shadow_match_idx;
	always_comb begin
		enqueue_pkt = req_i;
		if (enqueue_pkt.valid && enqueue_pkt.is_store &&
		    !enqueue_pkt.store_data_valid &&
		    enqueue_pkt.store_producer_tracked) begin
			for (shadow_match_idx = 0;
			     shadow_match_idx < STORE_COMPLETION_SHADOWS;
			     shadow_match_idx = shadow_match_idx + 1) begin
				if (completion_shadow_valid_q[shadow_match_idx] &&
				    (completion_shadow_id_q[shadow_match_idx] ==
				     enqueue_pkt.store_producer_id)) begin
					enqueue_pkt.store_data =
					    completion_shadow_data_q[shadow_match_idx];
					enqueue_pkt.store_data_valid = 1'b1;
					enqueue_pkt.store_producer_tracked = 1'b0;
				end
			end
		end
		enqueue_pkt.valid = 1'b1;
	end

    wire [31:0] active_store_raw_data = active_fp_store ?
        (fp_double_phase_q ? active_fp_store_data64[63:32] :
         active_fp_store_data64[31:0]) : active_store_data;
    reg [31:0] active_aligned_store_data;
    always_comb begin
        active_aligned_store_data = active_store_raw_data;
        if (active_op[OP_LSU_SB]) begin
            unique case (active_addr_index)
                2'b00: active_aligned_store_data =
                    {24'b0, active_store_raw_data[7:0]};
                2'b01: active_aligned_store_data =
                    {16'b0, active_store_raw_data[7:0], 8'b0};
                2'b10: active_aligned_store_data =
                    {8'b0, active_store_raw_data[7:0], 16'b0};
                default: active_aligned_store_data =
                    {active_store_raw_data[7:0], 24'b0};
            endcase
        end else if (active_op[OP_LSU_SH]) begin
            active_aligned_store_data = active_addr_index[1] ?
                {active_store_raw_data[15:0], 16'b0} :
                {16'b0, active_store_raw_data[15:0]};
        end
    end

	always_comb begin
        store_enqueue_pkt = '0;
	        store_enqueue_pkt.valid = 1'b1;
		        store_enqueue_pkt.retired = queue_head_q[0] ?
		            patched_queue1.retired : patched_queue0.retired;
	        store_enqueue_pkt.producer_id = active_pkt.producer_id;
        store_enqueue_pkt.addr = active_beat_addr;
        store_enqueue_pkt.store_data = active_aligned_store_data;
        store_enqueue_pkt.store_mask = active_store_mask;
	        store_enqueue_pkt.store_data_valid = active_store_data_valid;
	        store_enqueue_pkt.store_producer_id =
	            active_pkt.store_producer_id;
	        store_enqueue_pkt.store_producer_tracked =
	            active_pkt.store_producer_tracked && !active_store_data_valid;
	    end

	    store_buf_entry_t patched_store_enqueue;
	    integer enqueue_completion_idx;
	    always_comb begin
	        patched_store_enqueue = store_enqueue_pkt;
	        for (enqueue_completion_idx = 0;
	             enqueue_completion_idx < STORE_COMPLETION_SHADOWS;
	             enqueue_completion_idx = enqueue_completion_idx + 1) begin
	            if (store_enqueue_pkt.valid &&
	                !store_enqueue_pkt.store_data_valid &&
	                store_enqueue_pkt.store_producer_tracked &&
	                completion_shadow_valid_q[enqueue_completion_idx] &&
	                (completion_shadow_id_q[enqueue_completion_idx] ==
	                 store_enqueue_pkt.store_producer_id)) begin
	                unique case (store_enqueue_pkt.store_mask)
	                    4'b0001: patched_store_enqueue.store_data =
	                        {24'b0, completion_shadow_data_q[
	                            enqueue_completion_idx][7:0]};
	                    4'b0010: patched_store_enqueue.store_data =
	                        {16'b0, completion_shadow_data_q[
	                            enqueue_completion_idx][7:0], 8'b0};
	                    4'b0100: patched_store_enqueue.store_data =
	                        {8'b0, completion_shadow_data_q[
	                            enqueue_completion_idx][7:0], 16'b0};
	                    4'b1000: patched_store_enqueue.store_data =
	                        {completion_shadow_data_q[
	                            enqueue_completion_idx][7:0], 24'b0};
	                    4'b0011: patched_store_enqueue.store_data =
	                        {16'b0, completion_shadow_data_q[
	                            enqueue_completion_idx][15:0]};
	                    4'b1100: patched_store_enqueue.store_data =
	                        {completion_shadow_data_q[
	                            enqueue_completion_idx][15:0], 16'b0};
	                    default: patched_store_enqueue.store_data =
	                        completion_shadow_data_q[enqueue_completion_idx];
	                endcase
	                patched_store_enqueue.store_data_valid = 1'b1;
	                patched_store_enqueue.store_producer_tracked = 1'b0;
	            end
	        end
	    end

	    wire [$clog2(QUEUE_DEPTH)-1:0] recovery_queue_second =
	        queue_head_q + 1'b1;
	    wire ydrasil_lsu_req_pkt_t recovery_queue_pkt0 =
	        queue_head_q[0] ? patched_queue1 : patched_queue0;
	    wire ydrasil_lsu_req_pkt_t recovery_queue_pkt1 =
	        recovery_queue_second[0] ? patched_queue1 : patched_queue0;
	    // A DTCM request can leave the queue on the same edge that captures a
	    // branch recovery. Its identity is already in S1 when recovery_pending_q
	    // rebuilds the queue, and dtcm_wb_valid qualifies that single response.
	    wire recovery_queue_keep0 = (queue_count_q > 0) &&
	        recovery_queue_pkt0.valid &&
	        (producer_slot_in_window(
	             recovery_queue_pkt0.producer_id[PRODUCER_SLOT_WIDTH-1:0],
	             recovery_head_slot_q, recovery_branch_slot_q) ||
	         (recovery_queue_pkt0.is_store && recovery_queue_pkt0.retired));
	    wire recovery_queue_keep1 = (queue_count_q > 1) &&
	        recovery_queue_pkt1.valid &&
	        (producer_slot_in_window(
	             recovery_queue_pkt1.producer_id[PRODUCER_SLOT_WIDTH-1:0],
	             recovery_head_slot_q, recovery_branch_slot_q) ||
	         (recovery_queue_pkt1.is_store && recovery_queue_pkt1.retired));
	    wire [QUEUE_COUNT_WIDTH-1:0] recovery_queue_count =
	        QUEUE_COUNT_WIDTH'(recovery_queue_keep0) +
	        QUEUE_COUNT_WIDTH'(recovery_queue_keep1);
	    wire recovery_store_keep0 = (store_buf_count_q > 0) &&
	        patched_store_buf0.valid &&
	        (producer_slot_in_window(
	             patched_store_buf0.producer_id[PRODUCER_SLOT_WIDTH-1:0],
	             recovery_head_slot_q, recovery_branch_slot_q) ||
	         patched_store_buf0.retired);
	    wire recovery_store_keep1 = (store_buf_count_q > 1) &&
	        patched_store_buf1.valid &&
	        (producer_slot_in_window(
	             patched_store_buf1.producer_id[PRODUCER_SLOT_WIDTH-1:0],
	             recovery_head_slot_q, recovery_branch_slot_q) ||
	         patched_store_buf1.retired);
	    wire [STORE_COUNT_WIDTH-1:0] recovery_store_count =
	        STORE_COUNT_WIDTH'(recovery_store_keep0) +
	        STORE_COUNT_WIDTH'(recovery_store_keep1);

	    // Completion capture is independent of queue recovery. A producer can
	    // complete on the cycle that recovery_pending_q rebuilds the surviving
	    // entries; gating these shadows with queue control would strand a kept
	    // store whose data token arrives on that edge.
	    always_ff @(posedge clk or negedge rst_n) begin
	        if (!rst_n || trap_flush_i) begin
	            completion_shadow_valid_q[0] <= 1'b0;
	            completion_shadow_valid_q[1] <= 1'b0;
	            completion_shadow_valid_q[2] <= 1'b0;
	            completion_shadow_valid_q[3] <= 1'b0;
	            completion_shadow_valid_q[4] <= 1'b0;
	            completion_shadow_id_q[0] <= '0;
	            completion_shadow_id_q[1] <= '0;
	            completion_shadow_id_q[2] <= '0;
	            completion_shadow_id_q[3] <= '0;
	            completion_shadow_id_q[4] <= '0;
	            completion_shadow_data_q[0] <= '0;
	            completion_shadow_data_q[1] <= '0;
	            completion_shadow_data_q[2] <= '0;
	            completion_shadow_data_q[3] <= '0;
	            completion_shadow_data_q[4] <= '0;
	        end else begin
	            completion_shadow_valid_q[0] <=
	                completion_meta_i[COMPLETION_ALU].valid &&
	                completion_meta_i[COMPLETION_ALU].producer_tracked;
	            completion_shadow_id_q[0] <=
	                completion_meta_i[COMPLETION_ALU].producer_id;
	            completion_shadow_data_q[0] <=
	                completion_data_i[COMPLETION_ALU];
	            completion_shadow_valid_q[1] <=
	                completion_meta_i[COMPLETION_MUL].valid &&
	                completion_meta_i[COMPLETION_MUL].producer_tracked;
	            completion_shadow_id_q[1] <=
	                completion_meta_i[COMPLETION_MUL].producer_id;
	            completion_shadow_data_q[1] <=
	                completion_data_i[COMPLETION_MUL];
	            completion_shadow_valid_q[3] <= completion_shadow_valid_q[2];
	            completion_shadow_id_q[3] <= completion_shadow_id_q[2];
	            completion_shadow_data_q[3] <= completion_shadow_data_q[2];
	            completion_shadow_valid_q[2] <=
	                completion_meta_i[COMPLETION_DUAL_ALU].valid &&
	                completion_meta_i[COMPLETION_DUAL_ALU].producer_tracked;
	            completion_shadow_id_q[2] <=
	                completion_meta_i[COMPLETION_DUAL_ALU].producer_id;
	            completion_shadow_data_q[2] <=
	                completion_data_i[COMPLETION_DUAL_ALU];
	            completion_shadow_valid_q[4] <=
	                completion_meta_i[COMPLETION_LSU].valid &&
	                completion_meta_i[COMPLETION_LSU].producer_tracked;
	            completion_shadow_id_q[4] <=
	                completion_meta_i[COMPLETION_LSU].producer_id;
	            completion_shadow_data_q[4] <=
	                completion_data_i[COMPLETION_LSU];
	        end
	    end

	    always_ff @(posedge clk or negedge rst_n) begin
		    if (!rst_n) begin
		        commit_valid_q[0] <= 1'b0;
		        commit_valid_q[1] <= 1'b0;
		        commit_id_q[0] <= '0;
		        commit_id_q[1] <= '0;
		        recovery_pending_q <= 1'b0;
		        recovery_head_slot_q <= '0;
		        recovery_branch_slot_q <= '0;
		    end else if (trap_flush_i) begin
		        commit_valid_q[0] <= 1'b0;
		        commit_valid_q[1] <= 1'b0;
		        recovery_pending_q <= 1'b0;
		        recovery_head_slot_q <= '0;
		        recovery_branch_slot_q <= '0;
		    end else begin
			        commit_valid_q[0] <= commit0_valid_i;
			        commit_valid_q[1] <= commit1_valid_i;
			        commit_id_q[0] <= commit0_id_i;
			        commit_id_q[1] <= commit1_id_i;
		        recovery_pending_q <= branch_recovery_i;
		        if (branch_recovery_i) begin
		            recovery_head_slot_q <= recovery_head_slot_i;
		            recovery_branch_slot_q <= recovery_branch_slot_i;
		        end
		    end
		end

	integer queue_idx;
	always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            queue_count_q <= '0;
            issue_credit_q <= QUEUE_COUNT_WIDTH'(QUEUE_DEPTH);
            queue_head_q <= '0;
            queue_tail_q <= '0;
            store_buf_count_q <= '0;
            fp_double_phase_q <= 1'b0;
            for (queue_idx = 0; queue_idx < QUEUE_DEPTH; queue_idx++)
                queue_q[queue_idx] <= '0;
            store_buf0_q <= '0;
            store_buf1_q <= '0;
            load_s1_valid_q <= 1'b0;
            load_s1_rd_addr_q <= '0;
            load_s1_producer_id_q <= '0;
            load_s1_producer_tracked_q <= 1'b0;
            load_s1_op_q <= '0;
            load_s1_addr_index_q <= '0;
            load_s1_forward_mask_q <= '0;
            load_s1_forward_data_q <= '0;
            load_s1_fp_load_q <= 1'b0;
            load_s1_fp_double_q <= 1'b0;
            load_s1_fp_second_q <= 1'b0;
            load_s1_fp_rd_addr_q <= '0;
            fp_double_low_q <= '0;
            store_launch_valid_q <= 1'b0;
            store_launch_addr_q <= '0;
            store_launch_data_q <= '0;
            store_launch_mask_q <= '0;
            mmio_req_valid_q <= 1'b0;
            mmio_is_load_q <= 1'b0;
            mmio_addr_q <= '0;
            mmio_wdata_q <= '0;
            mmio_wmask_q <= '0;
            mmio_addr_index_q <= '0;
            mmio_operator_lsu_q <= '0;
            mmio_rd_addr_q <= '0;
            mmio_producer_id_q <= '0;
            mmio_producer_tracked_q <= 1'b0;
            mmio_fp_load_q <= 1'b0;
            mmio_fp_double_q <= 1'b0;
            mmio_fp_second_q <= 1'b0;
            mmio_fp_rd_addr_q <= '0;
            mmio_wb_valid_q <= 1'b0;
            mmio_wb_result_q <= '0;
            mmio_wb_rd_addr_q <= '0;
            mmio_wb_producer_id_q <= '0;
            mmio_wb_producer_tracked_q <= 1'b0;
            mmio_wb_fp_load_q <= 1'b0;
            mmio_wb_fp_data_q <= '0;
            mmio_wb_fp_rd_addr_q <= '0;
`ifndef SYNTHESIS
            perf_stb_lookup_q <= '0;
            perf_stb_hit_q <= '0;
            perf_stb_block_q <= '0;
            perf_stb_drain_q <= '0;
`endif
	        end else if (trap_flush_i) begin
	            queue_count_q <= '0;
	            issue_credit_q <= QUEUE_COUNT_WIDTH'(QUEUE_DEPTH);
	            queue_head_q <= '0;
	            queue_tail_q <= '0;
	            store_buf_count_q <= '0;
	            queue_q[0] <= '0;
	            queue_q[1] <= '0;
	            store_buf0_q <= '0;
            store_buf1_q <= '0;
            fp_double_phase_q <= 1'b0;
            load_s1_valid_q <= 1'b0;
            store_launch_valid_q <= 1'b0;
            mmio_req_valid_q <= 1'b0;
            mmio_wb_valid_q <= 1'b0;
            mmio_fp_load_q <= 1'b0;
            mmio_fp_double_q <= 1'b0;
            mmio_fp_second_q <= 1'b0;
            mmio_wb_fp_load_q <= 1'b0;
			end else if (recovery_pending_q) begin
	            queue_head_q <= '0;
	            queue_tail_q <= recovery_queue_count[
	                $clog2(QUEUE_DEPTH)-1:0];
	            queue_count_q <= recovery_queue_count;
	            issue_credit_q <= QUEUE_COUNT_WIDTH'(QUEUE_DEPTH) -
	                recovery_queue_count;
	            queue_q[0] <= recovery_queue_keep0 ? recovery_queue_pkt0 :
	                recovery_queue_keep1 ? recovery_queue_pkt1 : '0;
	            queue_q[1] <= (recovery_queue_keep0 && recovery_queue_keep1) ?
	                recovery_queue_pkt1 : '0;
	            store_buf_count_q <= recovery_store_count;
		            store_buf0_q <= recovery_store_keep0 ? patched_store_buf0 :
		                recovery_store_keep1 ? patched_store_buf1 : '0;
		            store_buf1_q <= (recovery_store_keep0 && recovery_store_keep1) ?
		                patched_store_buf1 : '0;
	            // The current S1 response is sampled by completion_ctrl on this
	            // edge after generation/window qualification above. Clear it so
	            // the response cannot be broadcast twice.
	            load_s1_valid_q <= 1'b0;
		            store_launch_valid_q <= 1'b0;
	            mmio_req_valid_q <= mmio_req_valid_q &&
		                producer_slot_in_window(mmio_producer_id_q[
	                    PRODUCER_SLOT_WIDTH-1:0], recovery_head_slot_q,
	                    recovery_branch_slot_q);
		            mmio_wb_valid_q <= 1'b0;
		            fp_double_phase_q <= 1'b0;
		        end else begin
	            if (active_valid && (dtcm_load_fire || dtcm_store_fire ||
                mmio_fire) && active_fp_double)
                fp_double_phase_q <= !fp_double_phase_q;
            else if (active_valid && (dtcm_load_fire || dtcm_store_fire ||
                mmio_fire))
                fp_double_phase_q <= 1'b0;
	            // Only retirement and unresolved store data mutate in place.
	            // Keeping immutable request payloads out of the normal hold/patch
	            // assignment removes the full-packet self-write priority mux.
	            if (patched_queue0.retired)
	                queue_q[0].retired <= 1'b1;
	            if (patched_queue1.retired)
	                queue_q[1].retired <= 1'b1;
	            if (patched_queue0.store_data_valid &&
	                !queue_q[0].store_data_valid) begin
	                queue_q[0].store_data <= patched_queue0.store_data;
	                queue_q[0].store_data_valid <= 1'b1;
	                queue_q[0].store_producer_tracked <= 1'b0;
	            end
	            if (patched_queue1.store_data_valid &&
	                !queue_q[1].store_data_valid) begin
	                queue_q[1].store_data <= patched_queue1.store_data;
	                queue_q[1].store_data_valid <= 1'b1;
	                queue_q[1].store_producer_tracked <= 1'b0;
	            end
	            if (queue_age_repair) begin
	                queue_q[queue_head_q] <= patched_second_pkt;
	                queue_q[queue_second_index] <= patched_active_pkt;
	            end
	            if (queue_dequeue) begin
	                // queue_count_q suppresses every stale payload field. Clear
	                // only validity instead of routing a zero packet to all bits.
	                queue_q[queue_head_q].valid <= 1'b0;
	                queue_head_q <= queue_head_q + 1'b1;
	            end
	            if (queue_physical_write) begin
	                queue_q[queue_tail_q] <= enqueue_pkt;
	            end
	            if (queue_enqueue) begin
	                queue_tail_q <= queue_tail_q + 1'b1;
	            end
            unique case ({queue_enqueue, queue_dequeue})
                2'b10: begin
                    queue_count_q <= queue_count_q + 1'b1;
                    issue_credit_q <= issue_credit_q - 1'b1;
                end
                2'b01: begin
                    queue_count_q <= queue_count_q - 1'b1;
                    issue_credit_q <= issue_credit_q + 1'b1;
                end
                default: queue_count_q <= queue_count_q;
            endcase

            // The two entries are an age-ordered shift FIFO. This removes
            // the rotating head/tail lookup from both the DTCM drain and the
            // load-forwarding CAM.  Entries outside store_buf_count_q are
            // deliberately left as don't-care state; every consumer is
            // count-gated and a later enqueue overwrites the corresponding
            // tail slot.
	            store_buf0_q <= patched_store_buf0;
	            store_buf1_q <= patched_store_buf1;
	            unique case ({store_buf_enqueue, store_buf_dequeue})
	                2'b01: begin
	                    store_buf0_q <= patched_store_buf1;
	                end
	                2'b10: begin
	                    unique case (store_buf_count_q)
	                        STORE_COUNT_WIDTH'(0): store_buf0_q <= patched_store_enqueue;
	                        default: store_buf1_q <= patched_store_enqueue;
	                    endcase
	                end
	                2'b11: begin
	                    unique case (store_buf_count_q)
	                        STORE_COUNT_WIDTH'(1): store_buf0_q <= patched_store_enqueue;
	                        default: begin
	                            store_buf0_q <= patched_store_buf1;
	                            store_buf1_q <= patched_store_enqueue;
	                        end
                    endcase
                end
                default: begin end
            endcase
            unique case ({store_buf_enqueue, store_buf_dequeue})
                2'b10: store_buf_count_q <= store_buf_count_q + 1'b1;
                2'b01: store_buf_count_q <= store_buf_count_q - 1'b1;
                default: store_buf_count_q <= store_buf_count_q;
            endcase

            store_launch_valid_q <= store_buf_dequeue;
            if (store_buf_dequeue) begin
                store_launch_addr_q <= store_buf0_q.addr;
                store_launch_data_q <= store_head_wdata;
                store_launch_mask_q <= store_buf0_q.store_mask;
            end
            load_s1_valid_q <= dtcm_load_fire;
            if (dtcm_load_fire) begin
                load_s1_rd_addr_q <= load_launch_rd_addr;
                load_s1_producer_id_q <= load_launch_producer_id;
                load_s1_producer_tracked_q <=
                    load_launch_producer_tracked;
                load_s1_op_q <= load_launch_op;
                load_s1_addr_index_q <= load_launch_addr[1:0];
                load_s1_forward_mask_q <= load_forward_mask;
                load_s1_forward_data_q <= load_forward_data;
                load_s1_fp_load_q <= load_launch_fp_load;
                load_s1_fp_double_q <= load_launch_fp_double;
                load_s1_fp_second_q <= load_launch_fp_second;
                load_s1_fp_rd_addr_q <= load_launch_fp_rd_addr;
            end
            if (load_s1_valid_q && load_s1_fp_load_q &&
                load_s1_fp_double_q && !load_s1_fp_second_q)
                fp_double_low_q <= dtcm_load_result;
            if (mmio_wb_valid_q && !load_s1_valid_q)
                mmio_wb_valid_q <= 1'b0;
            if (mmio_req_valid_q && mmio_rsp_i.valid) begin
                mmio_req_valid_q <= 1'b0;
                if (mmio_is_load_q) begin
                    if (mmio_fp_load_q && mmio_fp_double_q &&
                        !mmio_fp_second_q) begin
                        fp_double_low_q <= mmio_load_result;
                    end else begin
                        mmio_wb_valid_q <= 1'b1;
                        mmio_wb_result_q <= mmio_load_result;
                        mmio_wb_rd_addr_q <= mmio_rd_addr_q;
                        mmio_wb_producer_id_q <= mmio_producer_id_q;
                        mmio_wb_producer_tracked_q <= mmio_producer_tracked_q;
                        mmio_wb_fp_load_q <= mmio_fp_load_q;
                        mmio_wb_fp_rd_addr_q <= mmio_fp_rd_addr_q;
                        mmio_wb_fp_data_q <= mmio_fp_double_q ?
                            {mmio_load_result, fp_double_low_q} :
                            {32'hffff_ffff, mmio_load_result};
                    end
                end
            end
            if (mmio_fire) begin
                mmio_req_valid_q <= 1'b1;
                mmio_is_load_q <= active_is_load;
                mmio_addr_q <= active_beat_addr;
                mmio_wdata_q <= active_aligned_store_data;
                mmio_wmask_q <= active_store_mask;
                mmio_addr_index_q <= active_addr_index;
                mmio_operator_lsu_q <= active_op;
                mmio_rd_addr_q <= active_rd_addr;
                mmio_producer_id_q <= active_producer_id;
                mmio_producer_tracked_q <= active_producer_tracked;
                mmio_fp_load_q <= active_fp_load;
                mmio_fp_double_q <= active_fp_double;
                mmio_fp_second_q <= active_fp_double && fp_double_phase_q;
                mmio_fp_rd_addr_q <= active_fp_rd_addr;
            end

`ifndef SYNTHESIS
	            if (dtcm_load_fire) begin
	                perf_stb_lookup_q <= perf_stb_lookup_q + 1'b1;
	                if (|load_forward_mask)
	                    perf_stb_hit_q <= perf_stb_hit_q + 1'b1;
	            end
	            if (queued_dtcm_load_candidate &&
	                load_store_data_block)
	                perf_stb_block_q <= perf_stb_block_q + 1'b1;
            if (store_buf_dequeue)
                perf_stb_drain_q <= perf_stb_drain_q + 1'b1;
	        if (req_i.valid && !queue_enqueue && !fast_dtcm_load_fire &&
	            !(queue_dequeue && queue_full)) begin
                $fatal(1, "LSU two-entry load queue overflow");
            end
            if (store_buf_enqueue && store_buf_full && !store_buf_dequeue)
                $fatal(1, "LSU store buffer overflow");
`endif
        end
    end
endmodule
