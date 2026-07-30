module ydrasil_load_store_unit
import ydrasil_pkg::*;
(
    input  wire                            clk,
    input  wire                            rst_n,
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
    // Issue samples structural status through a registered boundary while a
    // selected memory uop is still travelling through Issue/EX and the AGU.
    // Four request slots retain one observable backlog plus the bounded
    // three-request flight window without feeding live LSU state into issue.
    localparam int QUEUE_DEPTH = 4;
    localparam int STORE_BUFFER_DEPTH = 4;
    localparam int QUEUE_COUNT_WIDTH = $clog2(QUEUE_DEPTH + 1);
    localparam int STORE_COUNT_WIDTH = $clog2(STORE_BUFFER_DEPTH + 1);

    function automatic [31:0] align_store_data(
        input [OP_LSU_INFO_WIDTH-1:0] op,
        input [1:0] addr_index,
        input [31:0] raw_data
    );
        begin
            align_store_data = raw_data;
            if (op[OP_LSU_SB]) begin
                unique case (addr_index)
                    2'b00: align_store_data = {24'b0, raw_data[7:0]};
                    2'b01: align_store_data = {16'b0, raw_data[7:0], 8'b0};
                    2'b10: align_store_data = {8'b0, raw_data[7:0], 16'b0};
                    default: align_store_data = {raw_data[7:0], 24'b0};
                endcase
            end else if (op[OP_LSU_SH]) begin
                align_store_data = addr_index[1] ?
                    {raw_data[15:0], 16'b0} : {16'b0, raw_data[15:0]};
            end
        end
    endfunction

    ydrasil_lsu_req_pkt_t queue_q [0:QUEUE_DEPTH-1];
    reg [QUEUE_COUNT_WIDTH-1:0] queue_count_q;
    reg [$clog2(QUEUE_DEPTH)-1:0] queue_head_q;
    reg [$clog2(QUEUE_DEPTH)-1:0] queue_tail_q;
    ydrasil_lsu_req_pkt_t store_buf_q [0:STORE_BUFFER_DEPTH-1];
    reg [STORE_COUNT_WIDTH-1:0] store_buf_count_q;
    reg [$clog2(STORE_BUFFER_DEPTH)-1:0] store_head_q;
    reg [$clog2(STORE_BUFFER_DEPTH)-1:0] store_tail_q;

    wire queue_empty = queue_count_q == '0;
    wire queue_full = queue_count_q == QUEUE_COUNT_WIDTH'(QUEUE_DEPTH);
    wire store_buf_empty = store_buf_count_q == '0;
    wire store_buf_full =
        store_buf_count_q == STORE_COUNT_WIDTH'(STORE_BUFFER_DEPTH);

    wire store_head_data_valid = !store_buf_empty &&
        store_buf_q[store_head_q].store_data_valid;
    wire [31:0] store_head_wdata = store_buf_q[store_head_q].store_data;
    wire store_buf_dequeue = store_head_data_valid;

	ydrasil_lsu_req_pkt_t active_pkt;
	assign active_pkt = queue_empty ? req_i : queue_q[queue_head_q];

    wire active_from_queue = !queue_empty;
    wire active_valid = active_pkt.valid;
    wire active_dtcm_load = active_valid && active_pkt.addr_is_dtcm &&
        active_pkt.is_load;
    wire active_dtcm_store = active_valid && active_pkt.addr_is_dtcm &&
        active_pkt.is_store;
    wire active_mmio = active_valid && !active_pkt.addr_is_dtcm;

    reg [3:0] load_forward_mask;
    reg [31:0] load_forward_data;
    integer store_scan;
    integer byte_scan;
    integer store_scan_slot;
    always_comb begin
        load_forward_mask = '0;
        load_forward_data = '0;
        for (store_scan = 0; store_scan < STORE_BUFFER_DEPTH; store_scan++) begin
            store_scan_slot = (store_head_q + store_scan) % STORE_BUFFER_DEPTH;
            if ((store_scan < store_buf_count_q) &&
                store_buf_q[store_scan_slot].valid &&
                (store_buf_q[store_scan_slot].addr[BUS_ADDR_WIDTH-1:2] ==
                 active_pkt.addr[BUS_ADDR_WIDTH-1:2])) begin
                for (byte_scan = 0; byte_scan < 4; byte_scan++) begin
                    if (store_buf_q[store_scan_slot].store_mask[byte_scan]) begin
                        load_forward_mask[byte_scan] = 1'b1;
                        load_forward_data[byte_scan*8 +: 8] =
                            store_buf_q[store_scan_slot].store_data
                                [byte_scan*8 +: 8];
                    end
                end
            end
        end
    end

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
    reg [REGS_ADDR_WIDTH-1:0] mmio_fp_rd_addr_q;
    reg mmio_wb_valid_q;
    reg [31:0] mmio_wb_result_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_rd_addr_q;
    producer_id_t mmio_wb_producer_id_q;
    reg mmio_wb_producer_tracked_q;
    reg mmio_wb_fp_load_q;
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
    reg [REGS_ADDR_WIDTH-1:0] load_s1_fp_rd_addr_q;

    // Give a buffered peripheral response a bounded path to completion. At
    // most one already-issued DTCM response remains after this hold asserts.
    wire load_issue_hold = mmio_wb_valid_q ||
        (mmio_req_valid_q && mmio_rsp_i.valid && mmio_is_load_q);
    // The request interface is a full FF boundary. Every E-stage request first
    // enters the two-entry queue; CAM lookup and DTCM launch only consume queue
    // registers on the following cycle.
    wire dtcm_load_fire = active_dtcm_load && !load_issue_hold;
    wire store_buf_has_room = !store_buf_full || store_buf_dequeue;
    wire dtcm_store_fire = active_dtcm_store && store_buf_has_room;
    // MMIO observes all older buffered stores before it starts. Once launched,
    // younger DTCM requests can proceed independently while APB is busy.
    wire active_store_data_valid = active_pkt.store_data_valid;
    wire mmio_fire = active_mmio && !mmio_busy && store_buf_empty &&
        (!active_pkt.is_store || active_store_data_valid);
    wire active_fire = dtcm_load_fire || dtcm_store_fire || mmio_fire;
    wire input_direct_fire = active_fire && !active_from_queue;
    wire queue_dequeue = active_fire && active_from_queue;
    wire [QUEUE_COUNT_WIDTH-1:0] queue_post_dequeue_count =
        queue_count_q - (queue_dequeue ? QUEUE_COUNT_WIDTH'(1) : '0);
    wire queue_enqueue = req_i.valid && !input_direct_fire &&
        (queue_post_dequeue_count < QUEUE_COUNT_WIDTH'(QUEUE_DEPTH));
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
    // `busy` becomes visible to issue only through issue's registered status
    // snapshot.  Assert at the first queued request so ordinary DTCM traffic
    // remains one request per cycle while MMIO/store-buffer backpressure is
    // stopped before the queue consumes its bounded in-flight headroom.
    assign status_o.busy = !queue_empty || mmio_busy;
    assign status_o.idle = queue_empty && store_buf_empty &&
        !mmio_busy && !load_s1_valid_q;
    assign status_o.fast_load = 1'b0;

    always_comb begin
        dtcm_req_o = '0;
        dtcm_req_o.load.valid = dtcm_load_fire;
        dtcm_req_o.load.addr = active_pkt.addr;
        dtcm_req_o.store.valid = store_buf_dequeue;
        dtcm_req_o.store.write = store_buf_dequeue;
        dtcm_req_o.store.addr = store_buf_q[store_head_q].addr;
        dtcm_req_o.store.wdata = store_head_wdata;
        dtcm_req_o.store.wmask = store_buf_q[store_head_q].store_mask;
    end

    assign mmio_req_o.valid = mmio_req_valid_q;
    assign mmio_req_o.write = mmio_req_valid_q && !mmio_is_load_q;
    assign mmio_req_o.addr = mmio_addr_q;
    assign mmio_req_o.wdata = mmio_wdata_q;
    assign mmio_req_o.wmask = mmio_req_o.write ? mmio_wmask_q : 4'b0;

    reg [31:0] load_merged_word;
    reg [31:0] load_shifted;
    reg [31:0] dtcm_load_result;
    reg [31:0] mmio_load_result;
    always_comb begin
        load_merged_word = dtcm_rdata_i;
        for (byte_scan = 0; byte_scan < 4; byte_scan++) begin
            if (load_s1_forward_mask_q[byte_scan])
                load_merged_word[byte_scan*8 +: 8] =
                    load_s1_forward_data_q[byte_scan*8 +: 8];
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
    assign completion_o.valid = dtcm_wb_valid ?
        load_s1_producer_tracked_q :
        (mmio_wb_out_valid && mmio_wb_producer_tracked_q);
    assign completion_o.data = dtcm_wb_valid ?
        dtcm_load_result : mmio_wb_result_q;
    assign completion_o.addr = dtcm_wb_valid ?
        load_s1_rd_addr_q : mmio_wb_rd_addr_q;
    assign completion_o.producer_id = dtcm_wb_valid ?
        load_s1_producer_id_q : mmio_wb_producer_id_q;
    assign completion_o.producer_tracked = dtcm_wb_valid ?
        load_s1_producer_tracked_q : mmio_wb_producer_tracked_q;
    assign fp_completion_valid_o = dtcm_wb_valid ? load_s1_fp_load_q :
        (mmio_wb_out_valid && mmio_wb_fp_load_q);
    assign fp_completion_addr_o = dtcm_wb_valid ?
        load_s1_fp_rd_addr_q : mmio_wb_fp_rd_addr_q;
    assign fp_completion_data_o = completion_o.data;

	ydrasil_lsu_req_pkt_t enqueue_pkt;
	always_comb begin
		enqueue_pkt = req_i;
		enqueue_pkt.valid = 1'b1;
	end

    integer queue_idx;
    integer store_idx;
	always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            queue_count_q <= '0;
            queue_head_q <= '0;
            queue_tail_q <= '0;
            store_buf_count_q <= '0;
            store_head_q <= '0;
            store_tail_q <= '0;
            for (queue_idx = 0; queue_idx < QUEUE_DEPTH; queue_idx++)
                queue_q[queue_idx] <= '0;
            for (store_idx = 0; store_idx < STORE_BUFFER_DEPTH; store_idx++)
                store_buf_q[store_idx] <= '0;
            load_s1_valid_q <= 1'b0;
            load_s1_rd_addr_q <= '0;
            load_s1_producer_id_q <= '0;
            load_s1_producer_tracked_q <= 1'b0;
            load_s1_op_q <= '0;
            load_s1_addr_index_q <= '0;
            load_s1_forward_mask_q <= '0;
            load_s1_forward_data_q <= '0;
            load_s1_fp_load_q <= 1'b0;
            load_s1_fp_rd_addr_q <= '0;
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
            mmio_fp_rd_addr_q <= '0;
            mmio_wb_valid_q <= 1'b0;
            mmio_wb_result_q <= '0;
            mmio_wb_rd_addr_q <= '0;
            mmio_wb_producer_id_q <= '0;
            mmio_wb_producer_tracked_q <= 1'b0;
            mmio_wb_fp_load_q <= 1'b0;
            mmio_wb_fp_rd_addr_q <= '0;
`ifndef SYNTHESIS
            perf_stb_lookup_q <= '0;
            perf_stb_hit_q <= '0;
            perf_stb_block_q <= '0;
            perf_stb_drain_q <= '0;
`endif
        end else begin
            if (queue_dequeue) begin
                queue_q[queue_head_q] <= '0;
                queue_head_q <= queue_head_q + 1'b1;
            end
            if (queue_enqueue) begin
                queue_q[queue_tail_q] <= enqueue_pkt;
                queue_tail_q <= queue_tail_q + 1'b1;
            end
            unique case ({queue_enqueue, queue_dequeue})
                2'b10: queue_count_q <= queue_count_q + 1'b1;
                2'b01: queue_count_q <= queue_count_q - 1'b1;
                default: queue_count_q <= queue_count_q;
            endcase

            if (store_buf_dequeue) begin
                store_buf_q[store_head_q] <= '0;
                store_head_q <= store_head_q + 1'b1;
            end
            if (store_buf_enqueue) begin
                store_buf_q[store_tail_q] <= active_pkt;
                store_buf_q[store_tail_q].valid <= 1'b1;
                store_buf_q[store_tail_q].store_data <= align_store_data(
                    active_pkt.op, active_pkt.addr[1:0], active_pkt.store_data);
                store_buf_q[store_tail_q].store_data_valid <= 1'b1;
                store_tail_q <= store_tail_q + 1'b1;
            end
            unique case ({store_buf_enqueue, store_buf_dequeue})
                2'b10: store_buf_count_q <= store_buf_count_q + 1'b1;
                2'b01: store_buf_count_q <= store_buf_count_q - 1'b1;
                default: store_buf_count_q <= store_buf_count_q;
            endcase

            load_s1_valid_q <= dtcm_load_fire;
            if (dtcm_load_fire) begin
                load_s1_rd_addr_q <= active_pkt.rd_addr;
                load_s1_producer_id_q <= active_pkt.producer_id;
                load_s1_producer_tracked_q <= active_pkt.producer_tracked;
                load_s1_op_q <= active_pkt.op;
                load_s1_addr_index_q <= active_pkt.addr[1:0];
                load_s1_forward_mask_q <= load_forward_mask;
                load_s1_forward_data_q <= load_forward_data;
                load_s1_fp_load_q <= active_pkt.fp_load;
                load_s1_fp_rd_addr_q <= active_pkt.fp_rd_addr;
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
                    mmio_wb_fp_load_q <= mmio_fp_load_q;
                    mmio_wb_fp_rd_addr_q <= mmio_fp_rd_addr_q;
                end
            end
            if (mmio_fire) begin
                mmio_req_valid_q <= 1'b1;
                mmio_is_load_q <= active_pkt.is_load;
                mmio_addr_q <= active_pkt.addr;
                mmio_wdata_q <= align_store_data(
                    active_pkt.op, active_pkt.addr[1:0], active_pkt.store_data);
                mmio_wmask_q <= active_pkt.store_mask;
                mmio_addr_index_q <= active_pkt.addr[1:0];
                mmio_operator_lsu_q <= active_pkt.op;
                mmio_rd_addr_q <= active_pkt.rd_addr;
                mmio_producer_id_q <= active_pkt.producer_id;
                mmio_producer_tracked_q <= active_pkt.producer_tracked;
                mmio_fp_load_q <= active_pkt.fp_load;
                mmio_fp_rd_addr_q <= active_pkt.fp_rd_addr;
            end

`ifndef SYNTHESIS
            if (dtcm_load_fire) begin
                perf_stb_lookup_q <= perf_stb_lookup_q + 1'b1;
                if (|load_forward_mask)
                    perf_stb_hit_q <= perf_stb_hit_q + 1'b1;
            end
            if (store_buf_dequeue)
                perf_stb_drain_q <= perf_stb_drain_q + 1'b1;
            if (req_i.valid && !queue_enqueue && !input_direct_fire &&
                !(queue_dequeue && queue_full))
                $fatal(1, "LSU two-entry load queue overflow");
            if (store_buf_enqueue && store_buf_full && !store_buf_dequeue)
                $fatal(1, "LSU store buffer overflow");
`endif
        end
    end
endmodule
