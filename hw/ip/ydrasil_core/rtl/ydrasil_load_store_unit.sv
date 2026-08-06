module ydrasil_load_store_unit
import ydrasil_pkg::*;
(
    input  wire                            clk,
	    input  wire                            rst_n,
	    input  ydrasil_lsu_req_pkt_t           req_i,
		    input  ydrasil_completion_meta_t       completion_meta_i [COMPLETION_LANES],
		    input  wire [REGS_DATA_WIDTH-1:0]      completion_data_i [COMPLETION_LANES],
    input  wire [BUS_DATA_WIDTH-1:0]       dtcm_rdata_i,
    output ydrasil_dtcm_req_pkt_t          dtcm_req_o,
    input  ydrasil_mem_rsp_pkt_t           mmio_rsp_i,
    output ydrasil_mem_req_pkt_t           mmio_req_o,
    output ydrasil_lsu_status_pkt_t        status_o,
    output wire [1:0]                     issue_credit_o,
    output ydrasil_reservation_pkt_t      dtcm_reservation_o,
	output wire [REGS_DATA_WIDTH-1:0]     dtcm_resp_data_o,
	output wire                            completion_valid_o,
	output wire [REGS_DATA_WIDTH-1:0]      completion_data_o,
	output wire [REGS_ADDR_WIDTH-1:0]      completion_addr_o,
	output producer_id_t                   completion_producer_id_o,
	output wire                            completion_producer_tracked_o
);
    localparam int QUEUE_DEPTH = 2;
    localparam int STORE_BUFFER_DEPTH = 2;
    localparam int QUEUE_COUNT_WIDTH = $clog2(QUEUE_DEPTH + 1);
    localparam int STORE_COUNT_WIDTH = $clog2(STORE_BUFFER_DEPTH + 1);

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

	    typedef struct packed {
	        logic                         valid;
	        producer_id_t                 producer_id;
	        logic [BUS_DATA_WIDTH-1:0]    data;
	    } store_completion_shadow_t;
	    // A taken JAL reaches the dual completion lane before its redirected
	    // target store reaches this queue. Keep one extra dual-lane sample so a
	    // link-register store can still be patched without stalling Issue.
	    localparam int STORE_COMPLETION_SHADOWS = 4;
	    store_completion_shadow_t completion_shadow_q
	        [0:STORE_COMPLETION_SHADOWS-1];

	    function automatic [BUS_DATA_WIDTH-1:0] align_store_data(
	        input [BUS_DATA_WIDTH-1:0] data,
	        input [3:0] mask
	    );
	        unique case (mask)
	            4'b0001: align_store_data = {24'b0, data[7:0]};
	            4'b0010: align_store_data = {16'b0, data[7:0], 8'b0};
	            4'b0100: align_store_data = {8'b0, data[7:0], 16'b0};
	            4'b1000: align_store_data = {data[7:0], 24'b0};
	            4'b0011: align_store_data = {16'b0, data[15:0]};
	            4'b1100: align_store_data = {data[15:0], 16'b0};
	            default: align_store_data = data;
	        endcase
	    endfunction

	    function automatic ydrasil_lsu_req_pkt_t patch_queue_store(
	        input ydrasil_lsu_req_pkt_t entry
	    );
	        integer completion_idx;
	        begin
	            patch_queue_store = entry;
	            if (entry.valid && entry.is_store &&
	                !entry.store_data_valid &&
	                entry.store_producer_tracked) begin
	                for (completion_idx = 0;
	                     completion_idx < COMPLETION_LANES;
	                     completion_idx = completion_idx + 1) begin
		                    if (completion_meta_i[completion_idx].valid &&
		                        completion_meta_i[completion_idx].producer_tracked &&
		                        (completion_meta_i[completion_idx].producer_id ==
		                         entry.store_producer_id)) begin
		                        patch_queue_store.store_data =
		                            completion_data_i[completion_idx];
	                        patch_queue_store.store_data_valid = 1'b1;
	                        patch_queue_store.store_producer_tracked = 1'b0;
	                    end
	                end
	            end
	        end
	    endfunction

	    function automatic store_buf_entry_t patch_buffer_store(
	        input store_buf_entry_t entry
	    );
	        integer completion_idx;
	        begin
	            patch_buffer_store = entry;
	            if (entry.valid && !entry.store_data_valid &&
	                entry.store_producer_tracked) begin
	                for (completion_idx = 0;
	                     completion_idx < COMPLETION_LANES;
	                     completion_idx = completion_idx + 1) begin
		                    if (completion_meta_i[completion_idx].valid &&
		                        completion_meta_i[completion_idx].producer_tracked &&
		                        (completion_meta_i[completion_idx].producer_id ==
		                         entry.store_producer_id)) begin
		                        patch_buffer_store.store_data = align_store_data(
		                            completion_data_i[completion_idx],
	                            entry.store_mask);
	                        patch_buffer_store.store_data_valid = 1'b1;
	                        patch_buffer_store.store_producer_tracked = 1'b0;
	                    end
	                end
	            end
	        end
	    endfunction

	    wire store_buf_entry_t patched_store_buf0 =
	        patch_buffer_store(store_buf0_q);
	    wire store_buf_entry_t patched_store_buf1 =
	        patch_buffer_store(store_buf1_q);

    wire queue_empty = queue_count_q == '0;
    wire queue_full = queue_count_q == QUEUE_COUNT_WIDTH'(QUEUE_DEPTH);
    wire store_buf_empty = store_buf_count_q == '0;
    wire store_buf_full =
        store_buf_count_q == STORE_COUNT_WIDTH'(STORE_BUFFER_DEPTH);

    wire store_head_data_valid = !store_buf_empty &&
        store_buf0_q.store_data_valid;
    wire [31:0] store_head_wdata = store_buf0_q.store_data;
    wire store_buf_dequeue = store_head_data_valid;

	    ydrasil_lsu_req_pkt_t active_pkt;
	    assign active_pkt = patch_queue_store(queue_q[queue_head_q]);

    wire active_valid = !queue_empty && active_pkt.valid;
    wire active_is_load = active_pkt.is_load;
    wire active_is_store = active_pkt.is_store;
    wire [OP_LSU_INFO_WIDTH-1:0] active_op = active_pkt.op;
    wire [BUS_ADDR_WIDTH-1:0] active_addr = active_pkt.addr;
    wire active_addr_is_dtcm = active_pkt.addr_is_dtcm;
    wire [REGS_ADDR_WIDTH-1:0] active_rd_addr = active_pkt.rd_addr;
    wire [PRODUCER_ID_WIDTH-1:0] active_producer_id = active_pkt.producer_id;
    wire active_producer_tracked = active_pkt.producer_tracked;
    wire [BUS_DATA_WIDTH-1:0] active_store_data = active_pkt.store_data;
    wire [3:0] active_store_mask = active_pkt.store_mask;
    wire active_store_data_valid = active_pkt.store_data_valid;
    wire active_dtcm_load = active_valid && active_addr_is_dtcm && active_is_load;
    wire active_dtcm_store = active_valid && active_addr_is_dtcm && active_is_store;
    wire active_mmio = active_valid && !active_addr_is_dtcm;

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
    reg mmio_wb_valid_q;
    reg [31:0] mmio_wb_result_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_rd_addr_q;
    producer_id_t mmio_wb_producer_id_q;
    reg mmio_wb_producer_tracked_q;
    wire mmio_busy = mmio_req_valid_q || mmio_wb_valid_q;

    reg load_s1_valid_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s1_rd_addr_q;
    producer_id_t load_s1_producer_id_q;
    reg load_s1_producer_tracked_q;
    reg [OP_LSU_INFO_WIDTH-1:0] load_s1_op_q;
    reg [1:0] load_s1_addr_index_q;
    reg [3:0] load_s1_forward_mask_q;
    reg [31:0] load_s1_forward_data_q;
    // This is the only wide DTCM response boundary.  Issue receives the
    // matching tag through dtcm_reservation_o and selects this registered
    // data only after its own FU input cells.
    reg [REGS_DATA_WIDTH-1:0] dtcm_resp_data_q;

    // Give a buffered peripheral response a bounded path to completion. At
    // most one already-issued DTCM response remains after this hold asserts.
    wire load_issue_hold = mmio_wb_valid_q ||
        (mmio_req_valid_q && mmio_rsp_i.valid && mmio_is_load_q);
    // An empty queue gives DTCM loads a dedicated metadata fast path. Stores
    // and MMIO always enter the request queue, keeping their readiness logic
    // out of the E-stage request-to-enqueue path.
	    wire direct_dtcm_load_candidate = queue_empty && req_i.valid &&
	        req_i.addr_is_dtcm && req_i.is_load && !load_issue_hold;
	    wire queued_dtcm_load_candidate = active_dtcm_load && !load_issue_hold;
	    wire [BUS_ADDR_WIDTH-1:0] load_launch_addr = queue_empty ?
	        req_i.addr : active_addr;
    wire [REGS_ADDR_WIDTH-1:0] load_launch_rd_addr = queue_empty ?
        req_i.rd_addr : active_rd_addr;
    wire producer_id_t load_launch_producer_id = queue_empty ?
        req_i.producer_id : active_producer_id;
    wire load_launch_producer_tracked = queue_empty ?
        req_i.producer_tracked : active_producer_tracked;
    wire [OP_LSU_INFO_WIDTH-1:0] load_launch_op = queue_empty ?
        req_i.op : active_op;

    // Two age-ordered entries cover the measured forwarding use while
    // removing half of the address CAM and its newest-store priority tree.
    integer byte_scan_load;
	    wire store_hit0 = (store_buf_count_q > STORE_COUNT_WIDTH'(0)) &&
	        store_buf0_q.valid &&
	        (store_buf0_q.addr[BUS_ADDR_WIDTH-1:2] ==
	         load_launch_addr[BUS_ADDR_WIDTH-1:2]);
	    wire store_hit1 = (store_buf_count_q > STORE_COUNT_WIDTH'(1)) &&
	        store_buf1_q.valid &&
	        (store_buf1_q.addr[BUS_ADDR_WIDTH-1:2] ==
	         load_launch_addr[BUS_ADDR_WIDTH-1:2]);
	    wire load_store_data_block =
	        (store_hit0 && !store_buf0_q.store_data_valid) ||
	        (store_hit1 && !store_buf1_q.store_data_valid);
	    wire direct_dtcm_load_fire = direct_dtcm_load_candidate &&
	        !load_store_data_block;
	    wire queued_dtcm_load_fire = queued_dtcm_load_candidate &&
	        !load_store_data_block;
	    wire dtcm_load_fire = direct_dtcm_load_fire || queued_dtcm_load_fire;
	    wire [3:0] forward_mask0 = {4{store_hit0}} &
	        store_buf0_q.store_mask;
	    wire [3:0] forward_mask1 = {4{store_hit1}} &
	        store_buf1_q.store_mask;
	    wire [3:0] load_forward_mask = forward_mask0 | forward_mask1;
	    wire [31:0] load_forward_data = {
	        forward_mask1[3] ? store_buf1_q.store_data[31:24] :
	                           store_buf0_q.store_data[31:24],
	        forward_mask1[2] ? store_buf1_q.store_data[23:16] :
	                           store_buf0_q.store_data[23:16],
	        forward_mask1[1] ? store_buf1_q.store_data[15:8] :
	                           store_buf0_q.store_data[15:8],
	        forward_mask1[0] ? store_buf1_q.store_data[7:0] :
	                           store_buf0_q.store_data[7:0]
	    };

    wire store_buf_has_room = !store_buf_full || store_buf_dequeue;
    wire dtcm_store_fire = active_dtcm_store && store_buf_has_room;
    // MMIO observes all older buffered stores before it starts. Once launched,
    // younger DTCM requests can proceed independently while APB is busy.
    wire mmio_fire = active_mmio && !mmio_busy && store_buf_empty &&
        (!active_is_store || active_store_data_valid);
    wire queue_dequeue = queued_dtcm_load_fire || dtcm_store_fire || mmio_fire;
    wire queue_has_room_after_dequeue = !queue_full || queue_dequeue;
    wire queue_enqueue = req_i.valid && !direct_dtcm_load_fire &&
        queue_has_room_after_dequeue;
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
        !mmio_busy && !load_s1_valid_q;
    assign status_o.fast_load = 1'b0;
    // Export only registered queue capacity. Issue locally reserves its
    // registered AGU request, keeping request payload and DTCM decisions out
    // of the next Issue selection cone.
    assign issue_credit_o = issue_credit_q;

    always_comb begin
        dtcm_req_o = '0;
        dtcm_req_o.load.valid = dtcm_load_fire;
        dtcm_req_o.load.addr = load_launch_addr;
        dtcm_req_o.store.valid = store_buf_dequeue;
        dtcm_req_o.store.write = store_buf_dequeue;
        dtcm_req_o.store.addr = store_buf0_q.addr;
        dtcm_req_o.store.wdata = store_head_wdata;
        dtcm_req_o.store.wmask = store_buf0_q.store_mask;
    end

    assign mmio_req_o.valid = mmio_req_valid_q;
    assign mmio_req_o.write = mmio_req_valid_q && !mmio_is_load_q;
    assign mmio_req_o.addr = mmio_addr_q;
    assign mmio_req_o.wdata = mmio_wdata_q;
    // Keep the request packet acyclic.  Reading mmio_req_o.write here makes
    // the lint tool treat the packed output as self-feedback even though write is
    // another field driven by the same registered state.
    assign mmio_req_o.wmask = (mmio_req_valid_q && !mmio_is_load_q) ?
        mmio_wmask_q : 4'b0;

    reg [31:0] load_merged_word;
    reg [31:0] load_shifted;
    reg [31:0] dtcm_load_result;
    reg [31:0] mmio_load_result;
    always_comb begin
        load_merged_word = dtcm_rdata_i;
        for (byte_scan_load = 0; byte_scan_load < 4; byte_scan_load++) begin
            if (load_s1_forward_mask_q[byte_scan_load])
                load_merged_word[byte_scan_load*8 +: 8] =
                    load_s1_forward_data_q[byte_scan_load*8 +: 8];
        end
        load_shifted = load_merged_word >>
            ({3'b000, load_s1_addr_index_q} << 3);
        dtcm_load_result = load_shifted;
        unique case (1'b1)
            load_s1_op_q[OP_LSU_LB]:
                dtcm_load_result = {{24{load_shifted[7]}}, load_shifted[7:0]};
            load_s1_op_q[OP_LSU_LBU]:
                dtcm_load_result = {24'b0, load_shifted[7:0]};
            load_s1_op_q[OP_LSU_LH]:
                dtcm_load_result = {{16{load_shifted[15]}}, load_shifted[15:0]};
            load_s1_op_q[OP_LSU_LHU]:
                dtcm_load_result = {16'b0, load_shifted[15:0]};
            default: dtcm_load_result = load_shifted;
        endcase

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
    wire dtcm_wb_valid = load_s1_valid_q;
    wire mmio_wb_out_valid = mmio_wb_valid_q && !dtcm_wb_valid;
    assign completion_valid_o = dtcm_wb_valid ?
        load_s1_producer_tracked_q :
        (mmio_wb_out_valid && mmio_wb_producer_tracked_q);
    assign completion_data_o = dtcm_wb_valid ?
        dtcm_load_result : mmio_wb_result_q;
    assign completion_addr_o = dtcm_wb_valid ?
        load_s1_rd_addr_q : mmio_wb_rd_addr_q;
    assign completion_producer_id_o = dtcm_wb_valid ?
        load_s1_producer_id_q : mmio_wb_producer_id_q;
    assign completion_producer_tracked_o = dtcm_wb_valid ?
        load_s1_producer_tracked_q : mmio_wb_producer_tracked_q;

    // DTCM is fixed-latency. Its registered identity is separate from the
    // MMIO/LSU completion stream; data is only a matched local operand bypass.
    assign dtcm_reservation_o.valid = dtcm_wb_valid;
    assign dtcm_reservation_o.producer_tracked = load_s1_producer_tracked_q;
    assign dtcm_reservation_o.producer_id = load_s1_producer_id_q;
    assign dtcm_reservation_o.arch_addr = load_s1_rd_addr_q;
    assign dtcm_reservation_o.result_class = RESULT_LSU;
    assign dtcm_resp_data_o = dtcm_resp_data_q;

	ydrasil_lsu_req_pkt_t enqueue_pkt;
	integer shadow_match_idx;
	always_comb begin
		enqueue_pkt = patch_queue_store(req_i);
		if (enqueue_pkt.valid && enqueue_pkt.is_store &&
		    !enqueue_pkt.store_data_valid &&
		    enqueue_pkt.store_producer_tracked) begin
			for (shadow_match_idx = 0;
			     shadow_match_idx < STORE_COMPLETION_SHADOWS;
			     shadow_match_idx = shadow_match_idx + 1) begin
				if (completion_shadow_q[shadow_match_idx].valid &&
				    (completion_shadow_q[shadow_match_idx].producer_id ==
				     enqueue_pkt.store_producer_id)) begin
					enqueue_pkt.store_data =
					    completion_shadow_q[shadow_match_idx].data;
					enqueue_pkt.store_data_valid = 1'b1;
					enqueue_pkt.store_producer_tracked = 1'b0;
				end
			end
		end
		enqueue_pkt.valid = 1'b1;
	end

    reg [31:0] active_aligned_store_data;
    always_comb begin
        active_aligned_store_data = active_store_data;
        if (active_op[OP_LSU_SB]) begin
            unique case (active_addr[1:0])
                2'b00: active_aligned_store_data =
                    {24'b0, active_store_data[7:0]};
                2'b01: active_aligned_store_data =
                    {16'b0, active_store_data[7:0], 8'b0};
                2'b10: active_aligned_store_data =
                    {8'b0, active_store_data[7:0], 16'b0};
                default: active_aligned_store_data =
                    {active_store_data[7:0], 24'b0};
            endcase
        end else if (active_op[OP_LSU_SH]) begin
            active_aligned_store_data = active_addr[1] ?
                {active_store_data[15:0], 16'b0} :
                {16'b0, active_store_data[15:0]};
        end
    end

	always_comb begin
        store_enqueue_pkt = '0;
        store_enqueue_pkt.valid = 1'b1;
        store_enqueue_pkt.addr = active_addr;
        store_enqueue_pkt.store_data = active_aligned_store_data;
        store_enqueue_pkt.store_mask = active_store_mask;
	        store_enqueue_pkt.store_data_valid = active_store_data_valid;
	        store_enqueue_pkt.store_producer_id =
	            active_pkt.store_producer_id;
	        store_enqueue_pkt.store_producer_tracked =
	            active_pkt.store_producer_tracked && !active_store_data_valid;
	    end

	    wire store_buf_entry_t patched_store_enqueue =
	        patch_buffer_store(store_enqueue_pkt);

	integer queue_idx;
	always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            queue_count_q <= '0;
            issue_credit_q <= QUEUE_COUNT_WIDTH'(QUEUE_DEPTH);
            queue_head_q <= '0;
            queue_tail_q <= '0;
            store_buf_count_q <= '0;
            for (queue_idx = 0; queue_idx < QUEUE_DEPTH; queue_idx++)
                queue_q[queue_idx] <= '0;
            store_buf0_q <= '0;
            store_buf1_q <= '0;
	            completion_shadow_q[0] <= '0;
	            completion_shadow_q[1] <= '0;
	            completion_shadow_q[2] <= '0;
	            completion_shadow_q[3] <= '0;
            load_s1_valid_q <= 1'b0;
            load_s1_rd_addr_q <= '0;
            load_s1_producer_id_q <= '0;
            load_s1_producer_tracked_q <= 1'b0;
            load_s1_op_q <= '0;
            load_s1_addr_index_q <= '0;
            load_s1_forward_mask_q <= '0;
            load_s1_forward_data_q <= '0;
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
            mmio_wb_valid_q <= 1'b0;
            mmio_wb_result_q <= '0;
            mmio_wb_rd_addr_q <= '0;
            mmio_wb_producer_id_q <= '0;
            mmio_wb_producer_tracked_q <= 1'b0;
`ifndef SYNTHESIS
            perf_stb_lookup_q <= '0;
            perf_stb_hit_q <= '0;
            perf_stb_block_q <= '0;
            perf_stb_drain_q <= '0;
`endif
	        end else begin
	            completion_shadow_q[0].valid <=
		                completion_meta_i[COMPLETION_ALU].valid &&
		                completion_meta_i[COMPLETION_ALU].producer_tracked;
		            completion_shadow_q[0].producer_id <=
		                completion_meta_i[COMPLETION_ALU].producer_id;
		            completion_shadow_q[0].data <=
		                completion_data_i[COMPLETION_ALU];
		            completion_shadow_q[1].valid <=
		                completion_meta_i[COMPLETION_MUL].valid &&
		                completion_meta_i[COMPLETION_MUL].producer_tracked;
		            completion_shadow_q[1].producer_id <=
		                completion_meta_i[COMPLETION_MUL].producer_id;
		            completion_shadow_q[1].data <=
		                completion_data_i[COMPLETION_MUL];
	            completion_shadow_q[3] <= completion_shadow_q[2];
	            completion_shadow_q[2].valid <=
		                completion_meta_i[COMPLETION_DUAL_ALU].valid &&
		                completion_meta_i[COMPLETION_DUAL_ALU].producer_tracked;
		            completion_shadow_q[2].producer_id <=
		                completion_meta_i[COMPLETION_DUAL_ALU].producer_id;
		            completion_shadow_q[2].data <=
		                completion_data_i[COMPLETION_DUAL_ALU];
	            for (queue_idx = 0; queue_idx < QUEUE_DEPTH; queue_idx++)
	                queue_q[queue_idx] <= patch_queue_store(queue_q[queue_idx]);
	            if (queue_dequeue) begin
                queue_q[queue_head_q] <= '0;
                queue_head_q <= queue_head_q + 1'b1;
            end
            if (queue_enqueue) begin
                queue_q[queue_tail_q] <= enqueue_pkt;
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

            load_s1_valid_q <= dtcm_load_fire;
            if (load_s1_valid_q)
                dtcm_resp_data_q <= dtcm_load_result;
            if (dtcm_load_fire) begin
                load_s1_rd_addr_q <= load_launch_rd_addr;
                load_s1_producer_id_q <= load_launch_producer_id;
                load_s1_producer_tracked_q <=
                    load_launch_producer_tracked;
                load_s1_op_q <= load_launch_op;
                load_s1_addr_index_q <= load_launch_addr[1:0];
                load_s1_forward_mask_q <= load_forward_mask;
                load_s1_forward_data_q <= load_forward_data;
            end
            if (mmio_wb_valid_q && !load_s1_valid_q)
                mmio_wb_valid_q <= 1'b0;
            if (mmio_req_valid_q && mmio_rsp_i.valid) begin
                mmio_req_valid_q <= 1'b0;
                if (mmio_is_load_q) begin
                    mmio_wb_valid_q <= 1'b1;
                    mmio_wb_result_q <= mmio_load_result;
                    mmio_wb_rd_addr_q <= mmio_rd_addr_q;
                    mmio_wb_producer_id_q <= mmio_producer_id_q;
                    mmio_wb_producer_tracked_q <= mmio_producer_tracked_q;
                end
            end
            if (mmio_fire) begin
                mmio_req_valid_q <= 1'b1;
                mmio_is_load_q <= active_is_load;
                mmio_addr_q <= active_addr;
                mmio_wdata_q <= active_aligned_store_data;
                mmio_wmask_q <= active_store_mask;
                mmio_addr_index_q <= active_addr[1:0];
                mmio_operator_lsu_q <= active_op;
                mmio_rd_addr_q <= active_rd_addr;
                mmio_producer_id_q <= active_producer_id;
                mmio_producer_tracked_q <= active_producer_tracked;
            end

`ifndef SYNTHESIS
	            if (dtcm_load_fire) begin
	                perf_stb_lookup_q <= perf_stb_lookup_q + 1'b1;
	                if (|load_forward_mask)
	                    perf_stb_hit_q <= perf_stb_hit_q + 1'b1;
	            end
	            if ((direct_dtcm_load_candidate || queued_dtcm_load_candidate) &&
	                load_store_data_block)
	                perf_stb_block_q <= perf_stb_block_q + 1'b1;
            if (store_buf_dequeue)
                perf_stb_drain_q <= perf_stb_drain_q + 1'b1;
            if (req_i.valid && !queue_enqueue && !direct_dtcm_load_fire &&
                !(queue_dequeue && queue_full)) begin
                $fatal(1, "LSU two-entry load queue overflow");
            end
            if (store_buf_enqueue && store_buf_full && !store_buf_dequeue)
                $fatal(1, "LSU store buffer overflow");
`endif
        end
    end
endmodule
