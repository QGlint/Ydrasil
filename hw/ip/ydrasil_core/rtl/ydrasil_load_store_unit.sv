module ydrasil_load_store_unit
import ydrasil_pkg::*;
(
    input  wire clk,
    input  wire rst_n,

    input  ydrasil_lsu_req_pkt_t           req_i,
    input  ydrasil_redirect_pkt_t          redirect_pkt_i,
    input  ydrasil_completion_bus_t        completion_bus_i,

    input  wire [BUS_DATA_WIDTH-1:0]       dtcm_rdata_i,
    output ydrasil_mem_req_pkt_t           dtcm_req_o,

    input  ydrasil_mem_rsp_pkt_t           mmio_rsp_i,
    output ydrasil_mem_req_pkt_t           mmio_req_o,

    output ydrasil_lsu_status_pkt_t        status_o,
    output ydrasil_gpr_fwd_pkt_t           completion_o,
    output ydrasil_gpr_fwd_pkt_t           load_bypass_o,
    output ydrasil_gpr_fwd_pkt_t           load_wakeup_o,
    output wire                            fp_completion_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0]      fp_completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]      fp_completion_data_o
);
	localparam int QUEUE_DEPTH = 8;
	localparam int QUEUE_COUNT_WIDTH = $clog2(QUEUE_DEPTH + 1);
	localparam int STORE_COMPLETION_DEPTH = 2;
	localparam int STORE_COMPLETION_COUNT_WIDTH =
		$clog2(STORE_COMPLETION_DEPTH + 1);

	ydrasil_lsu_req_pkt_t queue_q [0:QUEUE_DEPTH-1];
	reg [QUEUE_COUNT_WIDTH-1:0] queue_count_q;
	ydrasil_completion_bus_t completion_history_q;
	ydrasil_gpr_fwd_pkt_t store_completion_q [0:STORE_COMPLETION_DEPTH-1];
	reg [STORE_COMPLETION_COUNT_WIDTH-1:0] store_completion_count_q;

    wire input_is_load = req_i.is_load;
    wire input_is_store = req_i.is_store;
    wire input_valid = req_i.valid;
    wire queue_empty = (queue_count_q == '0);
    wire queue_full = (queue_count_q == QUEUE_COUNT_WIDTH'(QUEUE_DEPTH));
    wire active_from_queue = !queue_empty;

    function automatic logic tag_is_younger(
        input producer_id_t tag,
        input rob_tag_t redirect_tag
    );
        rob_tag_t distance;
        begin
            distance = tag - redirect_tag;
            tag_is_younger = (distance != '0) &&
                (distance <= rob_tag_t'(PRODUCER_NUM));
        end
    endfunction

    logic [QUEUE_COUNT_WIDTH-1:0] redirect_queue_keep_count;
    logic redirect_queue_prefix_open;
    integer redirect_queue_idx;
    always_comb begin
        redirect_queue_keep_count = '0;
        redirect_queue_prefix_open = 1'b1;
        for (redirect_queue_idx = 0; redirect_queue_idx < QUEUE_DEPTH;
             redirect_queue_idx = redirect_queue_idx + 1) begin
            if (redirect_queue_idx < queue_count_q && redirect_queue_prefix_open &&
                !tag_is_younger(queue_q[redirect_queue_idx].producer_id,
                                redirect_pkt_i.rob_tag))
                redirect_queue_keep_count = redirect_queue_keep_count + 1'b1;
            else if (redirect_queue_idx < queue_count_q)
                redirect_queue_prefix_open = 1'b0;
        end
    end

    reg input_wake_valid;
    reg [REGS_DATA_WIDTH-1:0] input_wake_data;
    reg [QUEUE_DEPTH-1:0] queue_wake_valid;
    reg [REGS_DATA_WIDTH-1:0] queue_wake_data [0:QUEUE_DEPTH-1];
    reg input_addr_wake_valid;
    reg [REGS_DATA_WIDTH-1:0] input_addr_wake_data;
    reg [QUEUE_DEPTH-1:0] queue_addr_wake_valid;
    reg [REGS_DATA_WIDTH-1:0] queue_addr_wake_data [0:QUEUE_DEPTH-1];
    integer wake_entry;
    integer wake_lane;

    integer completion_history_lane;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || (redirect_pkt_i.valid && !redirect_pkt_i.recover_rob)) begin
            for (completion_history_lane = 0;
                 completion_history_lane < COMPLETION_LANES;
                 completion_history_lane = completion_history_lane + 1)
                completion_history_q[completion_history_lane] <= '0;
        end else begin
            for (completion_history_lane = 0;
                 completion_history_lane < COMPLETION_LANES;
                 completion_history_lane = completion_history_lane + 1)
                completion_history_q[completion_history_lane] <=
                    completion_bus_i[completion_history_lane];
        end
    end

    always_comb begin
        input_wake_valid = 1'b0;
        input_wake_data = '0;
        input_addr_wake_valid = 1'b0;
        input_addr_wake_data = '0;
        for (wake_entry = 0; wake_entry < QUEUE_DEPTH; wake_entry = wake_entry + 1) begin
            queue_wake_valid[wake_entry] = 1'b0;
            queue_wake_data[wake_entry] = '0;
            queue_addr_wake_valid[wake_entry] = 1'b0;
            queue_addr_wake_data[wake_entry] = '0;
            for (wake_lane = 0; wake_lane < COMPLETION_LANES; wake_lane = wake_lane + 1) begin
                if (queue_q[wake_entry].valid &&
                    queue_q[wake_entry].store_data_producer_tracked &&
                    completion_bus_i[wake_lane].valid &&
                    completion_bus_i[wake_lane].producer_tracked &&
                    (completion_bus_i[wake_lane].producer_id ==
                     queue_q[wake_entry].store_data_producer_id)) begin
                    queue_wake_valid[wake_entry] = 1'b1;
                    queue_wake_data[wake_entry] = completion_bus_i[wake_lane].data;
                end
                if (queue_q[wake_entry].valid &&
                    queue_q[wake_entry].store_data_producer_tracked &&
                    completion_history_q[wake_lane].valid &&
                    completion_history_q[wake_lane].producer_tracked &&
                    (completion_history_q[wake_lane].producer_id ==
                     queue_q[wake_entry].store_data_producer_id)) begin
                    queue_wake_valid[wake_entry] = 1'b1;
                    queue_wake_data[wake_entry] = completion_history_q[wake_lane].data;
                end
                if (queue_q[wake_entry].valid && !queue_q[wake_entry].addr_valid &&
                    queue_q[wake_entry].addr_producer_tracked &&
                    completion_bus_i[wake_lane].valid &&
                    completion_bus_i[wake_lane].producer_tracked &&
                    (completion_bus_i[wake_lane].producer_id ==
                     queue_q[wake_entry].addr_producer_id)) begin
                    queue_addr_wake_valid[wake_entry] = 1'b1;
                    queue_addr_wake_data[wake_entry] = completion_bus_i[wake_lane].data;
                end
                if (queue_q[wake_entry].valid && !queue_q[wake_entry].addr_valid &&
                    queue_q[wake_entry].addr_producer_tracked &&
                    completion_history_q[wake_lane].valid &&
                    completion_history_q[wake_lane].producer_tracked &&
                    (completion_history_q[wake_lane].producer_id ==
                     queue_q[wake_entry].addr_producer_id)) begin
                    queue_addr_wake_valid[wake_entry] = 1'b1;
                    queue_addr_wake_data[wake_entry] = completion_history_q[wake_lane].data;
                end
                if (input_valid && input_is_store && !req_i.store_data_valid &&
                    req_i.store_data_producer_tracked &&
                    completion_bus_i[wake_lane].valid &&
                    completion_bus_i[wake_lane].producer_tracked &&
                    (completion_bus_i[wake_lane].producer_id ==
                     req_i.store_data_producer_id)) begin
                    input_wake_valid = 1'b1;
                    input_wake_data = completion_bus_i[wake_lane].data;
                end
                if (input_valid && input_is_store && !req_i.store_data_valid &&
                    req_i.store_data_producer_tracked &&
                    completion_history_q[wake_lane].valid &&
                    completion_history_q[wake_lane].producer_tracked &&
                    (completion_history_q[wake_lane].producer_id ==
                     req_i.store_data_producer_id)) begin
                    input_wake_valid = 1'b1;
                    input_wake_data = completion_history_q[wake_lane].data;
                end
                if (input_valid && !req_i.addr_valid &&
                    req_i.addr_producer_tracked &&
                    completion_bus_i[wake_lane].valid &&
                    completion_bus_i[wake_lane].producer_tracked &&
                    (completion_bus_i[wake_lane].producer_id ==
                     req_i.addr_producer_id)) begin
                    input_addr_wake_valid = 1'b1;
                    input_addr_wake_data = completion_bus_i[wake_lane].data;
                end
                if (input_valid && !req_i.addr_valid &&
                    req_i.addr_producer_tracked &&
                    completion_history_q[wake_lane].valid &&
                    completion_history_q[wake_lane].producer_tracked &&
                    (completion_history_q[wake_lane].producer_id ==
                     req_i.addr_producer_id)) begin
                    input_addr_wake_valid = 1'b1;
                    input_addr_wake_data = completion_history_q[wake_lane].data;
                end
            end
        end
    end

    wire active_is_load = active_from_queue ? queue_q[0].is_load : input_is_load;
    wire active_is_store = active_from_queue ? queue_q[0].is_store : input_is_store;
    wire [OP_LSU_INFO_WIDTH-1:0] active_op = active_from_queue ?
        queue_q[0].op : req_i.op;
    wire [BUS_ADDR_WIDTH-1:0] active_addr = active_from_queue ?
        queue_q[0].addr : req_i.addr;
    wire active_addr_valid = active_from_queue ?
        queue_q[0].addr_valid : req_i.addr_valid;
    wire active_addr_is_dtcm =
        active_addr[31:DTCM_ADDR_WIDTH+2] ==
        DTCM_BASE_ADDR[31:DTCM_ADDR_WIDTH+2];
    wire [REGS_ADDR_WIDTH-1:0] active_rd_addr = active_from_queue ?
        queue_q[0].rd_addr : req_i.rd_addr;
    producer_id_t active_producer_id;
    assign active_producer_id = active_from_queue ?
        queue_q[0].producer_id : req_i.producer_id;
    wire active_producer_tracked = active_from_queue ?
        queue_q[0].producer_tracked : req_i.producer_tracked;
    wire active_fp_load = active_from_queue ? queue_q[0].fp_load : req_i.fp_load;
    wire [REGS_ADDR_WIDTH-1:0] active_fp_rd_addr = active_from_queue ?
        queue_q[0].fp_rd_addr : req_i.fp_rd_addr;
    wire [REGS_DATA_WIDTH-1:0] active_store_raw_data = active_from_queue ?
        queue_q[0].store_data : req_i.store_data;
    wire active_store_data_valid = active_from_queue ?
        queue_q[0].store_data_valid : req_i.store_data_valid;
    wire active_valid = active_from_queue | input_valid;
    wire [1:0] active_addr_index = active_addr[1:0];

    reg [3:0] active_store_mask;
    reg [31:0] active_store_data;
    always_comb begin
        active_store_mask = '0;
        if (active_op[OP_LSU_SB])
            active_store_mask = 4'b0001 << active_addr_index;
        else if (active_op[OP_LSU_SH])
            active_store_mask = active_addr_index[1] ? 4'b1100 : 4'b0011;
        else if (active_op[OP_LSU_SW])
            active_store_mask = 4'b1111;
        active_store_data = active_store_raw_data;
        if (active_op[OP_LSU_SB]) begin
            unique case (active_addr_index)
                2'b00: active_store_data = {24'b0, active_store_raw_data[7:0]};
                2'b01: active_store_data = {16'b0, active_store_raw_data[7:0], 8'b0};
                2'b10: active_store_data = {8'b0, active_store_raw_data[7:0], 16'b0};
                default: active_store_data = {active_store_raw_data[7:0], 24'b0};
            endcase
        end else if (active_op[OP_LSU_SH]) begin
            active_store_data = active_addr_index[1] ?
                {active_store_raw_data[15:0], 16'b0} :
                {16'b0, active_store_raw_data[15:0]};
        end
    end

    reg mmio_req_valid_q;
    reg mmio_is_load_q;
    reg mmio_is_store_q;
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
    reg [REGS_DATA_WIDTH-1:0] mmio_wb_result_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_rd_addr_q;
    producer_id_t mmio_wb_producer_id_q;
    reg mmio_wb_producer_tracked_q;
    reg mmio_wb_fp_load_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_fp_rd_addr_q;
    wire mmio_busy = mmio_req_valid_q | mmio_wb_valid_q;

    reg load_s1_valid_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s1_rd_addr_q;
    producer_id_t load_s1_producer_id_q;
    reg load_s1_producer_tracked_q;
    reg [OP_LSU_INFO_WIDTH-1:0] load_s1_operator_lsu_q;
    reg [1:0] load_s1_addr_index_q;
    reg [BUS_ADDR_WIDTH-1:2] load_s1_word_addr_q;
    reg [1:0] load_s1_hot_generation_q;
    reg load_s1_redirect_hold_q;
    reg load_s1_fp_load_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s1_fp_rd_addr_q;

    reg load_s2_valid_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s2_rd_addr_q;
    producer_id_t load_s2_producer_id_q;
    reg load_s2_producer_tracked_q;
    reg [OP_LSU_INFO_WIDTH-1:0] load_s2_operator_lsu_q;
    reg [1:0] load_s2_addr_index_q;
    reg load_s2_hot_q;
    reg [REGS_DATA_WIDTH-1:0] load_s2_hot_shifted_q;
    reg [BUS_ADDR_WIDTH-1:2] load_s2_word_addr_q;
    reg [1:0] load_s2_hot_generation_q;
    reg load_s2_fp_load_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s2_fp_rd_addr_q;

    localparam int HOT_ENTRIES = 8;
    localparam int HOT_INDEX_WIDTH = $clog2(HOT_ENTRIES);
    reg [HOT_ENTRIES-1:0] hot_valid_q;
    reg [BUS_ADDR_WIDTH-1:2] hot_addr_q [0:HOT_ENTRIES-1];
    reg [31:0] hot_data_q [0:HOT_ENTRIES-1];
    reg [1:0] hot_generation_q [0:HOT_ENTRIES-1];
    reg hot_lookup_hit;
    reg [HOT_INDEX_WIDTH-1:0] hot_lookup_idx;
    reg [31:0] hot_lookup_data;
    wire dtcm_store_req;
    integer hot_idx;

    always_comb begin
        hot_lookup_idx = active_addr[HOT_INDEX_WIDTH+1:2];
        hot_lookup_hit = hot_valid_q[hot_lookup_idx] &&
            (hot_addr_q[hot_lookup_idx] == active_addr[BUS_ADDR_WIDTH-1:2]);
        hot_lookup_data = hot_data_q[hot_lookup_idx];
    end

    // MMIO is a strict ordering boundary; no younger DTCM request may pass it.
    wire dtcm_backend_ready = !mmio_busy;
    wire active_operand_ready = active_addr_valid &
        (active_is_load | (active_is_store & active_store_data_valid));
    wire redirect_valid = redirect_pkt_i.valid;
    wire selective_redirect = redirect_valid && redirect_pkt_i.recover_rob;
    wire full_redirect = redirect_valid && !redirect_pkt_i.recover_rob;
	wire load_completion_valid = load_s2_valid_q | mmio_wb_valid_q;
	wire store_completion_dequeue =
		(store_completion_count_q != '0) && !load_completion_valid;
	wire store_completion_space =
		(store_completion_count_q <
		 STORE_COMPLETION_COUNT_WIDTH'(STORE_COMPLETION_DEPTH)) ||
		store_completion_dequeue;
	wire dtcm_fire = active_valid & active_addr_is_dtcm &
		active_operand_ready & dtcm_backend_ready & !redirect_valid &
		(!active_is_store | store_completion_space);
	wire mmio_fire = active_valid & !active_addr_is_dtcm &
		active_operand_ready & !mmio_busy & !redirect_valid &
		(!active_is_store | store_completion_space);
    wire active_fire = dtcm_fire | mmio_fire;
    wire queue_dequeue = active_from_queue & active_fire;
    wire input_direct_fire = !active_from_queue & active_fire;
    wire queue_enqueue = input_valid & (active_from_queue | !input_direct_fire);
    wire [QUEUE_COUNT_WIDTH-1:0] queue_post_dequeue_count =
        queue_count_q - (queue_dequeue ? QUEUE_COUNT_WIDTH'(1) : '0);
`ifndef SYNTHESIS
    // Compatibility probes for the existing coverage counters. A shift queue
    // has a fixed head; its insertion position is the post-dequeue count.
	wire [2:0] queue_head_q = 3'b000;
	wire [2:0] queue_tail_q = queue_post_dequeue_count[2:0];
`endif
    ydrasil_lsu_req_pkt_t enqueue_pkt;
    always_comb begin
        enqueue_pkt = req_i;
        enqueue_pkt.valid = 1'b1;
        enqueue_pkt.store_data = req_i.store_data_valid ?
            req_i.store_data : input_wake_data;
        enqueue_pkt.store_data_valid = input_is_load |
            req_i.store_data_valid | input_wake_valid;
        enqueue_pkt.addr = req_i.addr_valid ? req_i.addr :
            (input_addr_wake_data + req_i.addr_offset);
        enqueue_pkt.addr_valid = req_i.addr_valid | input_addr_wake_valid;
        enqueue_pkt.addr_base = req_i.addr_valid ?
            req_i.addr_base : input_addr_wake_data;
        enqueue_pkt.addr_producer_tracked =
            req_i.addr_producer_tracked && !input_addr_wake_valid;
    end

    localparam bit HOT_BYPASS_ENABLE = 1'b1;
    wire hot_load_req = dtcm_fire & active_is_load & hot_lookup_hit &
        HOT_BYPASS_ENABLE & !load_s1_valid_q;
    wire dtcm_array_load_req = dtcm_fire & active_is_load &
        !(hot_lookup_hit & HOT_BYPASS_ENABLE & !load_s1_valid_q);
    assign dtcm_store_req = dtcm_fire & active_is_store;
    wire [31:0] hot_load_shifted = hot_lookup_data >>
        ({3'b000, active_addr_index} << 3);

    assign status_o.fast_load = hot_load_req & !active_from_queue;
    // Ready is registered at the scheduler and the accepted request crosses
    // the issue stage before reaching the queue. Reserve two physical entries
    // for those requests already in flight when backpressure becomes visible.
    assign status_o.busy = queue_count_q >= QUEUE_COUNT_WIDTH'(QUEUE_DEPTH-2);
	assign status_o.idle = queue_empty & !input_valid & !mmio_busy &
		!load_s1_valid_q & !load_s2_valid_q &
		(store_completion_count_q == '0);

    assign dtcm_req_o.valid = dtcm_array_load_req | dtcm_store_req;
    assign dtcm_req_o.write = dtcm_store_req;
    assign dtcm_req_o.addr = active_addr;
    // valid/write are the only BRAM side-effect controls.  Keep address decode
    // out of the data and mask cones so a new direct request does not carry the
    // AGU path into the BRAM data inputs.
    assign dtcm_req_o.wmask = active_store_mask;
    assign dtcm_req_o.wdata = active_store_data;

    assign mmio_req_o.valid = mmio_req_valid_q;
    assign mmio_req_o.write = mmio_req_valid_q & mmio_is_store_q;
    assign mmio_req_o.addr = mmio_addr_q;
    assign mmio_req_o.wmask = mmio_req_o.write ? mmio_wmask_q : 4'b0000;
    assign mmio_req_o.wdata = mmio_req_o.write ? mmio_wdata_q : 32'b0;

    reg [31:0] load_s2_array_shifted;
    reg [31:0] load_s1_array_shifted;
    reg [31:0] dtcm_load_result;
    reg [31:0] mmio_load_result;

    always_comb begin
        unique case (load_s2_addr_index_q)
            2'b00: load_s2_array_shifted = dtcm_rdata_i;
            2'b01: load_s2_array_shifted = {8'b0, dtcm_rdata_i[31:8]};
            2'b10: load_s2_array_shifted = {16'b0, dtcm_rdata_i[31:16]};
            default: load_s2_array_shifted = {24'b0, dtcm_rdata_i[31:24]};
        endcase
    end

    always_comb begin
        unique case (load_s1_addr_index_q)
            2'b00: load_s1_array_shifted = dtcm_rdata_i;
            2'b01: load_s1_array_shifted = {8'b0, dtcm_rdata_i[31:8]};
            2'b10: load_s1_array_shifted = {16'b0, dtcm_rdata_i[31:16]};
            default: load_s1_array_shifted = {24'b0, dtcm_rdata_i[31:24]};
        endcase
    end

    wire [31:0] load_s2_shifted = load_s2_hot_q ?
        load_s2_hot_shifted_q : load_s2_array_shifted;

    always_comb begin
        dtcm_load_result = load_s2_shifted;
        unique case (1'b1)
            load_s2_operator_lsu_q[OP_LSU_LB]:
                dtcm_load_result = {{24{load_s2_shifted[7]}}, load_s2_shifted[7:0]};
            load_s2_operator_lsu_q[OP_LSU_LBU]:
                dtcm_load_result = {24'b0, load_s2_shifted[7:0]};
            load_s2_operator_lsu_q[OP_LSU_LH]:
                dtcm_load_result = {{16{load_s2_shifted[15]}}, load_s2_shifted[15:0]};
            load_s2_operator_lsu_q[OP_LSU_LHU]:
                dtcm_load_result = {16'b0, load_s2_shifted[15:0]};
            default: dtcm_load_result = load_s2_shifted;
        endcase
    end

    always_comb begin
        mmio_load_result = mmio_rsp_i.rdata;
        unique case (1'b1)
            mmio_operator_lsu_q[OP_LSU_LB]: begin
                unique case (mmio_addr_index_q)
                    2'b00: mmio_load_result = {{24{mmio_rsp_i.rdata[7]}}, mmio_rsp_i.rdata[7:0]};
                    2'b01: mmio_load_result = {{24{mmio_rsp_i.rdata[15]}}, mmio_rsp_i.rdata[15:8]};
                    2'b10: mmio_load_result = {{24{mmio_rsp_i.rdata[23]}}, mmio_rsp_i.rdata[23:16]};
                    default: mmio_load_result = {{24{mmio_rsp_i.rdata[31]}}, mmio_rsp_i.rdata[31:24]};
                endcase
            end
            mmio_operator_lsu_q[OP_LSU_LBU]: begin
                unique case (mmio_addr_index_q)
                    2'b00: mmio_load_result = {24'b0, mmio_rsp_i.rdata[7:0]};
                    2'b01: mmio_load_result = {24'b0, mmio_rsp_i.rdata[15:8]};
                    2'b10: mmio_load_result = {24'b0, mmio_rsp_i.rdata[23:16]};
                    default: mmio_load_result = {24'b0, mmio_rsp_i.rdata[31:24]};
                endcase
            end
            mmio_operator_lsu_q[OP_LSU_LH]:
                mmio_load_result = mmio_addr_index_q[1] ?
                    {{16{mmio_rsp_i.rdata[31]}}, mmio_rsp_i.rdata[31:16]} :
                    {{16{mmio_rsp_i.rdata[15]}}, mmio_rsp_i.rdata[15:0]};
            mmio_operator_lsu_q[OP_LSU_LHU]:
                mmio_load_result = mmio_addr_index_q[1] ?
                    {16'b0, mmio_rsp_i.rdata[31:16]} : {16'b0, mmio_rsp_i.rdata[15:0]};
            default: mmio_load_result = mmio_rsp_i.rdata;
        endcase
    end

    wire dtcm_wb_valid = load_s2_valid_q;
    wire mmio_wb_out_valid = mmio_wb_valid_q & !dtcm_wb_valid;
    wire store_wb_valid = active_fire & active_is_store;
    wire [REGS_DATA_WIDTH-1:0] selected_wb_result = dtcm_wb_valid ?
        dtcm_load_result : mmio_wb_result_q;
    wire [REGS_ADDR_WIDTH-1:0] selected_wb_rd_addr = dtcm_wb_valid ?
        load_s2_rd_addr_q : mmio_wb_rd_addr_q;
    wire selected_wb_fp_load = dtcm_wb_valid ? load_s2_fp_load_q :
        mmio_wb_fp_load_q;
    wire selected_wb_producer_tracked = dtcm_wb_valid ?
        load_s2_producer_tracked_q : mmio_wb_producer_tracked_q;
    wire [REGS_ADDR_WIDTH-1:0] selected_wb_fp_rd_addr = dtcm_wb_valid ?
        load_s2_fp_rd_addr_q : mmio_wb_fp_rd_addr_q;
	wire producer_id_t selected_wb_producer_id = dtcm_wb_valid ?
		load_s2_producer_id_q : mmio_wb_producer_id_q;

    always_comb begin
        load_bypass_o = '0;
        load_bypass_o.valid = !full_redirect &&
            (dtcm_wb_valid | mmio_wb_out_valid) &&
            selected_wb_producer_tracked;
        load_bypass_o.producer_id = selected_wb_producer_id;
        load_bypass_o.producer_tracked = load_bypass_o.valid;
        load_bypass_o.addr = selected_wb_rd_addr;
        load_bypass_o.data = selected_wb_result;

        load_wakeup_o = '0;
		load_wakeup_o.valid = !redirect_valid &&
			((hot_load_req && active_producer_tracked) ||
			 (load_s1_valid_q && load_s1_producer_tracked_q));
		load_wakeup_o.producer_id = hot_load_req ? active_producer_id :
			load_s1_producer_id_q;
        load_wakeup_o.producer_tracked = load_wakeup_o.valid;
		load_wakeup_o.addr = hot_load_req ? active_rd_addr : load_s1_rd_addr_q;
    end

	wire load_completion_out_valid = dtcm_wb_valid | mmio_wb_out_valid;
	wire store_completion_out_valid = !load_completion_out_valid &&
		(store_completion_count_q != '0) &&
		store_completion_q[0].valid;
	assign completion_o.valid = !full_redirect &&
		(load_completion_out_valid ? selected_wb_producer_tracked :
		 store_completion_out_valid);
	assign completion_o.data = load_completion_out_valid ? selected_wb_result : '0;
	assign completion_o.addr = load_completion_out_valid && completion_o.valid ?
		selected_wb_rd_addr : '0;
	assign completion_o.producer_id = load_completion_out_valid ?
		selected_wb_producer_id :
		store_completion_q[0].producer_id;
	assign completion_o.producer_tracked = completion_o.valid;
    assign fp_completion_valid_o = !full_redirect &&
        (dtcm_wb_valid | mmio_wb_out_valid) && selected_wb_fp_load;
    assign fp_completion_addr_o = selected_wb_fp_rd_addr;
    assign fp_completion_data_o = selected_wb_result;

`ifndef SYNTHESIS
    reg [31:0] perf_hot_lookup_q;
    reg [31:0] perf_hot_hit_q;
    reg [31:0] perf_hot_fill_q;
    reg [31:0] perf_hot_store_update_q;
`endif

	integer queue_idx;
	integer store_completion_idx;
	ydrasil_gpr_fwd_pkt_t store_completion_enqueue_pkt;
	always_comb begin
		store_completion_enqueue_pkt = '0;
		store_completion_enqueue_pkt.valid = active_producer_tracked;
		store_completion_enqueue_pkt.producer_id = active_producer_id;
		store_completion_enqueue_pkt.producer_tracked = active_producer_tracked;
	end
	wire store_completion_enqueue = store_wb_valid & active_producer_tracked;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			queue_count_q <= '0;
			store_completion_count_q <= '0;
			for (store_completion_idx = 0;
			     store_completion_idx < STORE_COMPLETION_DEPTH;
			     store_completion_idx = store_completion_idx + 1)
				store_completion_q[store_completion_idx] <= '0;
            for (queue_idx = 0; queue_idx < QUEUE_DEPTH; queue_idx = queue_idx + 1)
                queue_q[queue_idx] <= '0;

            mmio_req_valid_q <= 1'b0;
            mmio_is_load_q <= 1'b0;
            mmio_is_store_q <= 1'b0;
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

            load_s1_valid_q <= 1'b0;
            load_s1_rd_addr_q <= '0;
            load_s1_producer_id_q <= '0;
            load_s1_producer_tracked_q <= 1'b0;
            load_s1_operator_lsu_q <= '0;
            load_s1_addr_index_q <= '0;
            load_s1_word_addr_q <= '0;
            load_s1_hot_generation_q <= '0;
			load_s1_redirect_hold_q <= 1'b0;
            load_s1_fp_load_q <= 1'b0;
            load_s1_fp_rd_addr_q <= '0;
            load_s2_valid_q <= 1'b0;
            load_s2_rd_addr_q <= '0;
            load_s2_producer_id_q <= '0;
            load_s2_producer_tracked_q <= 1'b0;
            load_s2_operator_lsu_q <= '0;
            load_s2_addr_index_q <= '0;
            load_s2_hot_q <= 1'b0;
            load_s2_hot_shifted_q <= '0;
			load_s2_word_addr_q <= '0;
			load_s2_hot_generation_q <= '0;
            load_s2_fp_load_q <= 1'b0;
            load_s2_fp_rd_addr_q <= '0;

            hot_valid_q <= '0;
            for (hot_idx = 0; hot_idx < HOT_ENTRIES; hot_idx = hot_idx + 1) begin
                hot_addr_q[hot_idx] <= '0;
                hot_data_q[hot_idx] <= '0;
                hot_generation_q[hot_idx] <= '0;
            end
`ifndef SYNTHESIS
            perf_hot_lookup_q <= '0;
            perf_hot_hit_q <= '0;
            perf_hot_fill_q <= '0;
            perf_hot_store_update_q <= '0;
`endif
        end else begin
			if (full_redirect) begin
				store_completion_count_q <= '0;
				for (store_completion_idx = 0;
				     store_completion_idx < STORE_COMPLETION_DEPTH;
				     store_completion_idx = store_completion_idx + 1)
					store_completion_q[store_completion_idx] <= '0;
			end else begin
				unique case ({store_completion_enqueue,
				              store_completion_dequeue})
					2'b10: begin
						if (store_completion_count_q == '0)
							store_completion_q[0] <=
								store_completion_enqueue_pkt;
						else
							store_completion_q[1] <=
								store_completion_enqueue_pkt;
						store_completion_count_q <=
							store_completion_count_q + 1'b1;
					end
					2'b01: begin
						store_completion_q[0] <= store_completion_q[1];
						store_completion_q[1] <= '0;
						store_completion_count_q <=
							store_completion_count_q - 1'b1;
					end
					2'b11: begin
						if (store_completion_count_q ==
						    STORE_COMPLETION_COUNT_WIDTH'(1)) begin
							store_completion_q[0] <=
								store_completion_enqueue_pkt;
							store_completion_q[1] <= '0;
						end else begin
							store_completion_q[0] <= store_completion_q[1];
							store_completion_q[1] <=
								store_completion_enqueue_pkt;
						end
					end
					default: begin end
				endcase
			end

            if (redirect_valid) begin
                queue_count_q <= full_redirect ? '0 : redirect_queue_keep_count;
                for (queue_idx = 0; queue_idx < QUEUE_DEPTH; queue_idx = queue_idx + 1) begin
                    if (full_redirect || queue_idx >= redirect_queue_keep_count) begin
                        queue_q[queue_idx] <= '0;
                    end else begin
                        if (queue_wake_valid[queue_idx] &&
                            !queue_q[queue_idx].store_data_valid) begin
                            // A retained older store can receive its data in the
                            // same cycle that a younger branch redirects.
                            queue_q[queue_idx].store_data_valid <= 1'b1;
                            queue_q[queue_idx].store_data <= queue_wake_data[queue_idx];
                        end
                        if (queue_addr_wake_valid[queue_idx] &&
                            !queue_q[queue_idx].addr_valid) begin
                            queue_q[queue_idx].addr_valid <= 1'b1;
                            queue_q[queue_idx].addr <=
                                queue_addr_wake_data[queue_idx] +
                                queue_q[queue_idx].addr_offset;
                            queue_q[queue_idx].addr_base <=
                                queue_addr_wake_data[queue_idx];
                            queue_q[queue_idx].addr_producer_tracked <= 1'b0;
                        end
                    end
                end
            end else begin
                for (queue_idx = 0; queue_idx < QUEUE_DEPTH; queue_idx = queue_idx + 1) begin
                    if (queue_wake_valid[queue_idx] && !queue_q[queue_idx].store_data_valid) begin
                        queue_q[queue_idx].store_data_valid <= 1'b1;
                        queue_q[queue_idx].store_data <= queue_wake_data[queue_idx];
                    end
                    if (queue_addr_wake_valid[queue_idx] &&
                        !queue_q[queue_idx].addr_valid) begin
                        queue_q[queue_idx].addr_valid <= 1'b1;
                        queue_q[queue_idx].addr <=
                            queue_addr_wake_data[queue_idx] +
                            queue_q[queue_idx].addr_offset;
                        queue_q[queue_idx].addr_base <=
                            queue_addr_wake_data[queue_idx];
                        queue_q[queue_idx].addr_producer_tracked <= 1'b0;
                    end
                end

                if (queue_dequeue) begin
                    for (queue_idx = 0; queue_idx < QUEUE_DEPTH-1; queue_idx = queue_idx + 1) begin
                        queue_q[queue_idx] <= queue_q[queue_idx+1];
                        if (queue_wake_valid[queue_idx+1] &&
                            !queue_q[queue_idx+1].store_data_valid) begin
                            queue_q[queue_idx].store_data_valid <= 1'b1;
                            queue_q[queue_idx].store_data <= queue_wake_data[queue_idx+1];
                        end
                        if (queue_addr_wake_valid[queue_idx+1] &&
                            !queue_q[queue_idx+1].addr_valid) begin
                            queue_q[queue_idx].addr_valid <= 1'b1;
                            queue_q[queue_idx].addr <=
                                queue_addr_wake_data[queue_idx+1] +
                                queue_q[queue_idx+1].addr_offset;
                            queue_q[queue_idx].addr_base <=
                                queue_addr_wake_data[queue_idx+1];
                            queue_q[queue_idx].addr_producer_tracked <= 1'b0;
                        end
                    end
                    queue_q[QUEUE_DEPTH-1] <= '0;
                end

				if (queue_enqueue) begin
					unique case (queue_post_dequeue_count)
						0: queue_q[0] <= enqueue_pkt;
						1: queue_q[1] <= enqueue_pkt;
						2: queue_q[2] <= enqueue_pkt;
						3: queue_q[3] <= enqueue_pkt;
						4: queue_q[4] <= enqueue_pkt;
						5: queue_q[5] <= enqueue_pkt;
						6: queue_q[6] <= enqueue_pkt;
						default: queue_q[7] <= enqueue_pkt;
					endcase
				end

                unique case ({queue_enqueue, queue_dequeue})
                    2'b10: queue_count_q <= queue_count_q + 1'b1;
                    2'b01: queue_count_q <= queue_count_q - 1'b1;
                    default: queue_count_q <= queue_count_q;
                endcase
            end

            if (full_redirect) begin
                load_s1_valid_q <= 1'b0;
				load_s1_redirect_hold_q <= 1'b0;
                load_s2_valid_q <= 1'b0;
            end else if (selective_redirect) begin
				load_s1_valid_q <= load_s1_valid_q &&
					!tag_is_younger(load_s1_producer_id_q, redirect_pkt_i.rob_tag);
				load_s1_redirect_hold_q <= load_s1_valid_q &&
					!tag_is_younger(load_s1_producer_id_q, redirect_pkt_i.rob_tag);
                load_s2_valid_q <= 1'b0;
            end else begin
				load_s1_valid_q <= dtcm_array_load_req;
				load_s2_valid_q <= load_s1_valid_q | hot_load_req;
				load_s2_hot_q <= hot_load_req | load_s1_redirect_hold_q;
				load_s1_redirect_hold_q <= 1'b0;
            end
            if (dtcm_array_load_req && !redirect_valid) begin
                load_s1_rd_addr_q <= active_rd_addr;
                load_s1_producer_id_q <= active_producer_id;
                load_s1_producer_tracked_q <= active_producer_tracked;
                load_s1_operator_lsu_q <= active_op;
                load_s1_addr_index_q <= active_addr_index;
                load_s1_word_addr_q <= active_addr[BUS_ADDR_WIDTH-1:2];
                load_s1_hot_generation_q <= hot_generation_q[hot_lookup_idx];
                load_s1_fp_load_q <= active_fp_load;
                load_s1_fp_rd_addr_q <= active_fp_rd_addr;
            end

            if (hot_load_req && !redirect_valid) begin
                load_s2_rd_addr_q <= active_rd_addr;
                load_s2_producer_id_q <= active_producer_id;
                load_s2_producer_tracked_q <= active_producer_tracked;
                load_s2_operator_lsu_q <= active_op;
                load_s2_addr_index_q <= active_addr_index;
                load_s2_hot_shifted_q <= hot_load_shifted;
				load_s2_word_addr_q <= active_addr[BUS_ADDR_WIDTH-1:2];
				load_s2_hot_generation_q <= hot_generation_q[hot_lookup_idx];
                load_s2_fp_load_q <= active_fp_load;
                load_s2_fp_rd_addr_q <= active_fp_rd_addr;
			end else if (load_s1_valid_q && !redirect_valid) begin
				load_s2_rd_addr_q <= load_s1_rd_addr_q;
				load_s2_producer_id_q <= load_s1_producer_id_q;
				load_s2_producer_tracked_q <= load_s1_producer_tracked_q;
				load_s2_operator_lsu_q <= load_s1_operator_lsu_q;
				load_s2_addr_index_q <= load_s1_addr_index_q;
				load_s2_word_addr_q <= load_s1_word_addr_q;
				load_s2_hot_generation_q <= load_s1_hot_generation_q;
				if (load_s1_redirect_hold_q)
					load_s2_hot_shifted_q <= load_s1_array_shifted;
				load_s2_fp_load_q <= load_s1_fp_load_q;
				load_s2_fp_rd_addr_q <= load_s1_fp_rd_addr_q;
            end

			if (load_s2_valid_q && !load_s2_hot_q && !redirect_valid &&
				(load_s2_hot_generation_q == hot_generation_q[
				 load_s2_word_addr_q[HOT_INDEX_WIDTH+1:2]]) &&
				!(dtcm_store_req &&
				  (load_s2_word_addr_q[HOT_INDEX_WIDTH+1:2] == hot_lookup_idx))) begin
				hot_valid_q[load_s2_word_addr_q[HOT_INDEX_WIDTH+1:2]] <= 1'b1;
				hot_addr_q[load_s2_word_addr_q[HOT_INDEX_WIDTH+1:2]] <=
					load_s2_word_addr_q;
				hot_data_q[load_s2_word_addr_q[HOT_INDEX_WIDTH+1:2]] <=
					dtcm_rdata_i;
            end

            if (dtcm_store_req) begin
                hot_generation_q[hot_lookup_idx] <=
                    hot_generation_q[hot_lookup_idx] + 1'b1;
                // A store conservatively invalidates its indexed entry. This
                // removes the AGU/hit/byte-merge path from all 256 data FFs;
                // the following load refills the entry from DTCM.
                hot_valid_q[hot_lookup_idx] <= 1'b0;
            end

            if (full_redirect) begin
                mmio_req_valid_q <= 1'b0;
                mmio_wb_valid_q <= 1'b0;
            end else if (mmio_wb_valid_q && !dtcm_wb_valid)
                mmio_wb_valid_q <= 1'b0;

            if (mmio_req_valid_q && mmio_rsp_i.valid && !full_redirect) begin
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
                mmio_is_load_q <= active_is_load;
                mmio_is_store_q <= active_is_store;
                mmio_addr_q <= active_addr;
                mmio_wdata_q <= active_store_data;
                mmio_wmask_q <= active_store_mask;
                mmio_addr_index_q <= active_addr_index;
                mmio_operator_lsu_q <= active_op;
                mmio_rd_addr_q <= active_rd_addr;
                mmio_producer_id_q <= active_producer_id;
                mmio_producer_tracked_q <= active_producer_tracked;
                mmio_fp_load_q <= active_fp_load;
                mmio_fp_rd_addr_q <= active_fp_rd_addr;
            end

`ifndef SYNTHESIS
            if (dtcm_fire & active_is_load) perf_hot_lookup_q <= perf_hot_lookup_q + 1'b1;
            if (hot_load_req) perf_hot_hit_q <= perf_hot_hit_q + 1'b1;
            if (load_s1_valid_q) perf_hot_fill_q <= perf_hot_fill_q + 1'b1;
            if (dtcm_store_req && hot_lookup_hit)
                perf_hot_store_update_q <= perf_hot_store_update_q + 1'b1;
            if (queue_enqueue && queue_full && !queue_dequeue)
                $fatal(1, "LSU request queue overflow");
            if (queue_enqueue && input_is_store && !req_i.store_data_valid &&
                !req_i.store_data_producer_tracked && !input_wake_valid)
                $fatal(1, "LSU delayed store has no producer token");
            if (queue_enqueue && !req_i.addr_valid &&
                !req_i.addr_producer_tracked && !input_addr_wake_valid)
                $fatal(1, "LSU delayed address has no producer token");
`endif
        end
    end
endmodule
