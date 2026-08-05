// The fetch queue is a two-bank ring.  Consecutive logical entries land in
// opposite banks, so one read port per bank is sufficient for the two fetch
// lanes and one write port per bank is sufficient for a two-entry response.
// The queue metadata is resettable FF state; payload storage is intentionally
// not reset so it can map to distributed RAM.
module ydrasil_fetch_queue
import ydrasil_pkg::*;
#(
    parameter int DEPTH = 8,
    parameter int COUNT_WIDTH = $clog2(DEPTH + 1),
    parameter int INDEX_WIDTH = $clog2(DEPTH)
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         flush_i,
    input  wire [1:0]                   pop_count_i,
    input  wire [1:0]                   read_pop_count_i,
    input  wire [1:0]                   push_count_i,
    input  wire [1:0]                   read_push_count_i,
    input  wire [131:0]                 push_payload0_i,
    input  wire [131:0]                 push_payload1_i,
    output wire [COUNT_WIDTH-1:0]       count_o,
    output wire                         valid0_o,
    output wire                         valid1_o,
    output wire [131:0]                 payload0_o,
    output wire [131:0]                 payload1_o
);
    localparam int BANK_DEPTH = DEPTH / 2;
    localparam int BANK_ADDR_WIDTH = (BANK_DEPTH > 1) ? $clog2(BANK_DEPTH) : 1;
    localparam int COUNT_EXT_WIDTH = COUNT_WIDTH + 1;

    reg [COUNT_WIDTH-1:0] count_q;
    reg [INDEX_WIDTH-1:0] head_q;
    reg [INDEX_WIDTH-1:0] tail_q;

    wire [INDEX_WIDTH-1:0] head1 = head_q + INDEX_WIDTH'(1);
    wire [INDEX_WIDTH-1:0] head_after_pop =
        head_q + INDEX_WIDTH'(read_pop_count_i);
    wire [INDEX_WIDTH-1:0] head_after_pop1 =
        head_after_pop + INDEX_WIDTH'(1);
    wire [INDEX_WIDTH-1:0] tail1 = tail_q + INDEX_WIDTH'(1);
    wire [BANK_ADDR_WIDTH-1:0] head_after_pop_addr =
        head_after_pop[INDEX_WIDTH-1:1];
    wire [BANK_ADDR_WIDTH-1:0] head_after_pop1_addr =
        head_after_pop1[INDEX_WIDTH-1:1];
    wire [BANK_ADDR_WIDTH-1:0] tail_addr = tail_q[INDEX_WIDTH-1:1];
    wire [BANK_ADDR_WIDTH-1:0] tail1_addr = tail1[INDEX_WIDTH-1:1];

    // Read-ahead is independent of flush qualification. The output valid bits
    // are discarded on a redirect, keeping redirect control out of the LUTRAM
    // data path while architectural head/count still use pop_count_i and
    // push_count_i below.
    // Each bank reads whichever lane has the matching parity. Since the two
    // lanes have opposite parity, no read port is shared by both lanes.
    wire [BANK_ADDR_WIDTH-1:0] read_addr_even = head_after_pop[0] ?
        head_after_pop1_addr : head_after_pop_addr;
    wire [BANK_ADDR_WIDTH-1:0] read_addr_odd  = head_after_pop[0] ?
        head_after_pop_addr : head_after_pop1_addr;
    wire [131:0] payload_even;
    wire [131:0] payload_odd;

    reg                         write_even;
    reg                         write_odd;
    reg [BANK_ADDR_WIDTH-1:0]   write_addr_even;
    reg [BANK_ADDR_WIDTH-1:0]   write_addr_odd;
    reg [131:0]                 write_data_even;
    reg [131:0]                 write_data_odd;

    always_comb begin
        write_even = 1'b0;
        write_odd = 1'b0;
        write_addr_even = '0;
        write_addr_odd = '0;
        write_data_even = '0;
        write_data_odd = '0;

        if (push_count_i != 2'd0) begin
            if (!tail_q[0]) begin
                write_even = 1'b1;
                write_addr_even = tail_addr;
                write_data_even = push_payload0_i;
            end else begin
                write_odd = 1'b1;
                write_addr_odd = tail_addr;
                write_data_odd = push_payload0_i;
            end
        end
        if (push_count_i == 2'd2) begin
            if (!tail1[0]) begin
                write_even = 1'b1;
                write_addr_even = tail1_addr;
                write_data_even = push_payload1_i;
            end else begin
                write_odd = 1'b1;
                write_addr_odd = tail1_addr;
                write_data_odd = push_payload1_i;
            end
        end
    end

    ydrasil_1r1w_ram #(
        .DEPTH       (BANK_DEPTH),
        .DATA_WIDTH  (132),
        .ADDR_WIDTH  (BANK_ADDR_WIDTH),
        .READ_LATENCY(0)
    ) u_payload_even (
        .clk    (clk),
        .ren_i  (1'b1),
        .raddr_i(read_addr_even),
        .rdata_o(payload_even),
        .wen_i  (write_even),
        .waddr_i(write_addr_even),
        .wdata_i(write_data_even)
    );
    ydrasil_1r1w_ram #(
        .DEPTH       (BANK_DEPTH),
        .DATA_WIDTH  (132),
        .ADDR_WIDTH  (BANK_ADDR_WIDTH),
        .READ_LATENCY(0)
    ) u_payload_odd (
        .clk    (clk),
        .ren_i  (1'b1),
        .raddr_i(read_addr_odd),
        .rdata_o(payload_odd),
        .wen_i  (write_odd),
        .waddr_i(write_addr_odd),
        .wdata_i(write_data_odd)
    );

    wire [COUNT_EXT_WIDTH-1:0] count_after_op =
        COUNT_EXT_WIDTH'(count_q) - COUNT_EXT_WIDTH'(read_pop_count_i) +
        COUNT_EXT_WIDTH'(read_push_count_i);
    wire [COUNT_EXT_WIDTH-1:0] old_remaining =
        COUNT_EXT_WIDTH'(count_q) - COUNT_EXT_WIDTH'(read_pop_count_i);
    wire [131:0] memory_payload0 = head_after_pop[0] ?
        payload_odd : payload_even;
    wire [131:0] memory_payload1 = head_after_pop[0] ?
        payload_even : payload_odd;

    // A synchronous output boundary captures the post-pop head.  When the
    // address is also written in this cycle (empty queue, or a refill behind a
    // one-entry queue), use the request payload directly because distributed
    // RAM is read-first at the write edge.
    wire payload0_push_bypass = (old_remaining == '0) &&
        (read_push_count_i != 2'd0);
    wire payload1_push_bypass =
        ((old_remaining == '0) && (read_push_count_i == 2'd2)) ||
        ((old_remaining == COUNT_EXT_WIDTH'(1)) && (read_push_count_i != 2'd0));
    assign valid0_o = !flush_i && (count_after_op != '0);
    assign valid1_o = !flush_i && (count_after_op > COUNT_EXT_WIDTH'(1));
    assign payload0_o = payload0_push_bypass ? push_payload0_i :
        memory_payload0;
    assign payload1_o = payload1_push_bypass ?
        ((old_remaining == '0) ? push_payload1_i : push_payload0_i) :
        memory_payload1;
    assign count_o = count_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            count_q <= '0;
            head_q <= '0;
            tail_q <= '0;
        end else begin
            count_q <= count_q - COUNT_WIDTH'(pop_count_i) +
                COUNT_WIDTH'(push_count_i);
            if (pop_count_i != 2'd0)
                head_q <= head_q + INDEX_WIDTH'(pop_count_i);
            if (push_count_i != 2'd0)
                tail_q <= tail_q + INDEX_WIDTH'(push_count_i);
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && !flush_i)
            assert (count_q - COUNT_WIDTH'(pop_count_i) +
                    COUNT_WIDTH'(push_count_i) <= COUNT_WIDTH'(DEPTH))
                else $fatal(1, "fetch queue ring overflow");
    end
`endif
endmodule

module ydrasil_if_stage
import ydrasil_pkg::*;
#(
    parameter int FETCHQ_DEPTH = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall_if_i,
    input  wire        flush_if_i,
    input  wire        consume_two_i,

    input  wire        branch_jump_i,
    input  wire [31:0] branch_target_i,

    input  wire        bp_predict_hit_i,
    input  wire        bp_predict_taken_i,
    input  wire [31:0] bp_predict_target_i,
    input  wire [1:0]  bp_predict_counter_i,
    input  wire [31:0] bp_predict_bht_index_i,
    input  wire        bp_predict1_hit_i,
    input  wire        bp_predict1_taken_i,
    input  wire [31:0] bp_predict1_target_i,
    input  wire [1:0]  bp_predict1_counter_i,
    input  wire [31:0] bp_predict1_bht_index_i,
    input  wire        bp_invalidate_i,
    input  wire [31:0] bp_invalidate_target_i,
    // Install L0 entries only after EX has resolved real control flow.
    input  ydrasil_bp_train_pkt_t target_ff_train_i,

    output wire [31:0] if_mem_addr_o,
    output wire [31:0] if_mem_addr1_o,
    output wire [31:0] bp_lookup_pc_o,
    input  wire [31:0] if_mem_rdata_i,
    input  wire [31:0] if_mem_rdata1_i,

    output wire [31:0] if_id_pc_o,
    output wire        if_id_pred_hit_o,
    output wire        if_id_pred_taken_o,
    output wire [31:0] if_id_pred_target_o,
    output wire [1:0]  if_id_pred_counter_o,
    output wire [31:0] if_id_pred_bht_index_o,
    output wire        if_id_valid_o,
    output wire [31:0] if_id_instr_o,

    output wire [31:0] if_id1_pc_o,
    output wire        if_id1_pred_hit_o,
    output wire        if_id1_pred_taken_o,
    output wire [31:0] if_id1_pred_target_o,
    output wire [1:0]  if_id1_pred_counter_o,
    output wire [31:0] if_id1_pred_bht_index_o,
    output wire        if_id1_valid_o,
    output wire [31:0] if_id1_instr_o,
    output wire        target_ff_hit_o,
    output wire        target_ff_hit1_o,
    output wire        target_ff_correction_o
);

    localparam int COUNT_WIDTH = $clog2(FETCHQ_DEPTH + 1);
    localparam int RESERVED_WIDTH = $clog2(FETCHQ_DEPTH + 3);

    reg [31:0] pc_q;
    reg        mem_req_valid_q;
    reg        mem_req_two_q;
    reg [31:0] mem_req_pc_q;
    reg [31:0] mem_req_next_pc_q;
	reg        mem_req_target_ff_hit_q;
    reg        pending_redirect_valid_q;
    reg [31:0] pending_redirect_target_q;

	localparam int TARGET_FF_ENTRIES = 32;
	wire [31:0] fetch_addr;
	wire [31:0] fetch_addr1;
	wire [4:0] target_ff_index = fetch_addr[7:3];
	wire [4:0] target_ff_index1 = fetch_addr1[7:3];
	reg [TARGET_FF_ENTRIES-1:0] target_ff_valid_q;
	reg [TARGET_FF_ENTRIES-1:0] target_ff_taken_q;
	reg [TARGET_FF_ENTRIES-1:0] target_ff_lane_q;
	wire [23:0] target_ff_tag0;
	wire [23:0] target_ff_tag1;
	wire [29:0] target_ff_target0_q;
	wire [29:0] target_ff_target1_q;
	wire target_ff_write = target_ff_train_i.valid &&
		target_ff_train_i.conditional;
	wire [4:0] target_ff_write_index = target_ff_train_i.pc[7:3];

	// Two read copies preserve the original two-lane, zero-latency lookup
	// contract while making the data arrays explicit distributed RAM. Metadata
	// stays in resettable FFs and prevents an uninitialized table from hitting.
	ydrasil_1r1w_ram #(
		.DEPTH       (TARGET_FF_ENTRIES),
		.DATA_WIDTH  (24),
		.ADDR_WIDTH  (5),
		.READ_LATENCY(0)
	) u_target_ff_tag0 (
		.clk    (clk),
		.ren_i  (1'b1),
		.raddr_i(target_ff_index),
		.rdata_o(target_ff_tag0),
		.wen_i  (target_ff_write),
		.waddr_i(target_ff_write_index),
		.wdata_i(target_ff_train_i.pc[31:8])
	);
	ydrasil_1r1w_ram #(
		.DEPTH       (TARGET_FF_ENTRIES),
		.DATA_WIDTH  (24),
		.ADDR_WIDTH  (5),
		.READ_LATENCY(0)
	) u_target_ff_tag1 (
		.clk    (clk),
		.ren_i  (1'b1),
		.raddr_i(target_ff_index1),
		.rdata_o(target_ff_tag1),
		.wen_i  (target_ff_write),
		.waddr_i(target_ff_write_index),
		.wdata_i(target_ff_train_i.pc[31:8])
	);
	ydrasil_1r1w_ram #(
		.DEPTH       (TARGET_FF_ENTRIES),
		.DATA_WIDTH  (30),
		.ADDR_WIDTH  (5),
		.READ_LATENCY(0)
	) u_target_ff_target0 (
		.clk    (clk),
		.ren_i  (1'b1),
		.raddr_i(target_ff_index),
		.rdata_o(target_ff_target0_q),
		.wen_i  (target_ff_write),
		.waddr_i(target_ff_write_index),
		.wdata_i(target_ff_train_i.target[31:2])
	);
	ydrasil_1r1w_ram #(
		.DEPTH       (TARGET_FF_ENTRIES),
		.DATA_WIDTH  (30),
		.ADDR_WIDTH  (5),
		.READ_LATENCY(0)
	) u_target_ff_target1 (
		.clk    (clk),
		.ren_i  (1'b1),
		.raddr_i(target_ff_index1),
		.rdata_o(target_ff_target1_q),
		.wen_i  (target_ff_write),
		.waddr_i(target_ff_write_index),
		.wdata_i(target_ff_train_i.target[31:2])
	);

    wire [COUNT_WIDTH-1:0] fetchq_count_q;
    wire queue_next_valid0;
    wire queue_next_valid1;
    wire [131:0] queue_next_payload0;
    wire [131:0] queue_next_payload1;
    reg fetchq_valid0_q;
    reg fetchq_valid1_q;
    reg [131:0] fetchq_payload0_q;
    reg [131:0] fetchq_payload1_q;
    wire fetchq_valid0 = fetchq_valid0_q;
    wire fetchq_valid1 = fetchq_valid1_q;

    wire flush_fetch = flush_if_i | branch_jump_i;
    wire [31:0] pc_plus4 = pc_q + 32'd4;
    wire [31:0] flush_target = branch_jump_i ? branch_target_i : pc_plus4;
    wire [1:0] pop_count = (!flush_fetch && !stall_if_i && fetchq_valid0) ?
        ((consume_two_i && fetchq_valid1) ? 2'd2 : 2'd1) : 2'd0;
    // The ring state consumes only flush-qualified entries. The read-ahead
    // peek intentionally remains independent so redirect control does not
    // fan into the LUTRAM data pins; its valid bits are discarded below.
    wire [1:0] read_pop_count = (!stall_if_i && fetchq_valid0) ?
        ((consume_two_i && fetchq_valid1) ? 2'd2 : 2'd1) : 2'd0;
    wire mem_resp_valid = !flush_fetch && mem_req_valid_q;
    wire predict_redirect_resp = mem_resp_valid &&
        (bp_predict_taken_i || (mem_req_two_q && bp_predict1_taken_i));
    wire [31:0] predict_next_pc = bp_predict_taken_i ? bp_predict_target_i :
        ((mem_req_two_q && bp_predict1_taken_i) ? bp_predict1_target_i :
         (mem_req_pc_q + (mem_req_two_q ? 32'd8 : 32'd4)));
    wire predict_correction_resp = mem_resp_valid &&
        (predict_next_pc != mem_req_next_pc_q);
	// The registered L0 decision, rather than the returning BRAM data, releases
	// the next fetch.  A stale entry kills that speculative request below and
	// retains the existing one-cycle correction through pending_redirect_target_q.
	wire target_ff_hit = mem_resp_valid && mem_req_target_ff_hit_q;
	wire target_ff_correction_resp = target_ff_hit &&
		predict_correction_resp;
    wire [1:0] push_count = mem_resp_valid ?
        ((bp_predict_taken_i || !mem_req_two_q) ? 2'd1 : 2'd2) : 2'd0;
    wire [1:0] read_push_count = mem_req_valid_q ?
        ((bp_predict_taken_i || !mem_req_two_q) ? 2'd1 : 2'd2) : 2'd0;
    wire [RESERVED_WIDTH-1:0] reserved_count =
        RESERVED_WIDTH'(fetchq_count_q) +
        (mem_req_valid_q ? (mem_req_two_q ? RESERVED_WIDTH'(2) :
         RESERVED_WIDTH'(1)) : '0);
    wire pair_capacity = reserved_count <= RESERVED_WIDTH'(FETCHQ_DEPTH - 2);
    wire fetch_issue = !flush_fetch && !bp_invalidate_i && pair_capacity && (target_ff_hit ||
			 (!predict_correction_resp && !predict_redirect_resp));

    wire [131:0] fetchq_push_payload0 = {
        mem_req_pc_q,
        if_mem_rdata_i,
        bp_predict_hit_i,
        bp_predict_taken_i,
        bp_predict_target_i,
        bp_predict_counter_i,
        bp_predict_bht_index_i
    };
    wire [131:0] fetchq_push_payload1 = {
        mem_req_pc_q + 32'd4,
        if_mem_rdata1_i,
        bp_predict1_hit_i,
        bp_predict1_taken_i,
        bp_predict1_target_i,
        bp_predict1_counter_i,
        bp_predict1_bht_index_i
    };
    ydrasil_fetch_queue #(
        .DEPTH      (FETCHQ_DEPTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) u_fetch_queue (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush_i        (flush_fetch || bp_invalidate_i),
        .pop_count_i    (pop_count),
        .read_pop_count_i(read_pop_count),
        .push_count_i   (push_count),
        .read_push_count_i(read_push_count),
        .push_payload0_i(fetchq_push_payload0),
        .push_payload1_i(fetchq_push_payload1),
        .count_o        (fetchq_count_q),
        .valid0_o       (queue_next_valid0),
        .valid1_o       (queue_next_valid1),
        .payload0_o     (queue_next_payload0),
        .payload1_o     (queue_next_payload1)
    );
    assign fetch_addr = pending_redirect_valid_q ?
        pending_redirect_target_q : pc_q;
    wire fetch_addr_is_dtcm =
        (fetch_addr >= DTCM_BASE_ADDR) &&
        (fetch_addr < (DTCM_BASE_ADDR + ((32'd1 << DTCM_ADDR_WIDTH) << 2)));
    wire fetch_two = !fetch_addr_is_dtcm && !fetch_addr[2];
    assign fetch_addr1 = fetch_addr + 32'd4;
	wire [31:0] target_ff_target0 = {target_ff_target0_q, 2'b00};
	wire [31:0] target_ff_target1 = {target_ff_target1_q, 2'b00};
    wire target_ff_hit0 = target_ff_valid_q[target_ff_index] &&
        target_ff_taken_q[target_ff_index] &&
		(target_ff_lane_q[target_ff_index] == fetch_addr[2]) &&
		(target_ff_tag0 == fetch_addr[31:8]);
    wire target_ff_hit1 = target_ff_valid_q[target_ff_index1] &&
        target_ff_taken_q[target_ff_index1] &&
		(target_ff_lane_q[target_ff_index1] == fetch_addr1[2]) &&
		(target_ff_tag1 == fetch_addr1[31:8]);
	wire target_ff_lookup_hit = target_ff_hit0 ||
		(fetch_two && target_ff_hit1);
    wire [31:0] target_ff_target = target_ff_hit0 ? target_ff_target0 :
        target_ff_target1;
    assign target_ff_hit_o = fetch_issue && target_ff_hit0;
    assign target_ff_hit1_o = fetch_issue && fetch_two && target_ff_hit1;
    assign target_ff_correction_o = predict_correction_resp;
`ifndef SYNTHESIS
    // Hierarchical verification probes; excluded from the synthesized cone.
    wire [31:0] pc_ff = pc_q;
    wire mem_req_valid_ff = mem_req_valid_q;
    wire pending_redirect_valid_ff = pending_redirect_valid_q;
    wire bp_predict_redirect = predict_redirect_resp;
`endif
    assign if_mem_addr_o = fetch_addr;
    assign if_mem_addr1_o = fetch_addr1;
    assign bp_lookup_pc_o = fetch_addr;

    assign if_id_valid_o = fetchq_valid0;
    assign if_id_pc_o = fetchq_valid0 ? fetchq_payload0_q[131:100] : RESET_INS;
    assign if_id_instr_o = fetchq_valid0 ? fetchq_payload0_q[99:68] : RV32I_INS_NOP;
    assign if_id_pred_hit_o = fetchq_valid0 && fetchq_payload0_q[67];
    assign if_id_pred_taken_o = fetchq_valid0 && fetchq_payload0_q[66];
    assign if_id_pred_target_o = fetchq_valid0 ? fetchq_payload0_q[65:34] : '0;
    assign if_id_pred_counter_o = fetchq_valid0 ? fetchq_payload0_q[33:32] : 2'b01;
    assign if_id_pred_bht_index_o = fetchq_valid0 ? fetchq_payload0_q[31:0] : '0;

    assign if_id1_valid_o = fetchq_valid1;
    assign if_id1_pc_o = fetchq_valid1 ? fetchq_payload1_q[131:100] : (RESET_INS + 32'd4);
    assign if_id1_instr_o = fetchq_valid1 ? fetchq_payload1_q[99:68] : RV32I_INS_NOP;
    assign if_id1_pred_hit_o = fetchq_valid1 && fetchq_payload1_q[67];
    assign if_id1_pred_taken_o = fetchq_valid1 && fetchq_payload1_q[66];
    assign if_id1_pred_target_o = fetchq_valid1 ? fetchq_payload1_q[65:34] : '0;
    assign if_id1_pred_counter_o = fetchq_valid1 ? fetchq_payload1_q[33:32] : 2'b01;
    assign if_id1_pred_bht_index_o = fetchq_valid1 ? fetchq_payload1_q[31:0] : '0;

    // Register the queue peek before decode.  The queue's peek already points
    // at the post-pop head, preserving one entry per consumed cycle.
    // The queue peek is an IF-to-decode pipeline boundary.  It is cleared by
    // clocked control events, so keep reset synchronous here to avoid mixing
    // the asynchronous reset pin with the flush/invalidate enable mux.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fetchq_valid0_q <= 1'b0;
            fetchq_valid1_q <= 1'b0;
            fetchq_payload0_q <= '0;
            fetchq_payload1_q <= '0;
        end else begin
            fetchq_valid0_q <= (flush_fetch || bp_invalidate_i) ?
                1'b0 : queue_next_valid0;
            fetchq_valid1_q <= (flush_fetch || bp_invalidate_i) ?
                1'b0 : queue_next_valid1;
            fetchq_payload0_q <= queue_next_payload0;
            fetchq_payload1_q <= queue_next_payload1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q <= RESET_INS;
            mem_req_valid_q <= 1'b0;
            mem_req_two_q <= 1'b0;
            mem_req_pc_q <= RESET_INS;
            mem_req_next_pc_q <= RESET_INS + 32'd8;
			mem_req_target_ff_hit_q <= 1'b0;
            pending_redirect_valid_q <= 1'b0;
            pending_redirect_target_q <= '0;
            target_ff_valid_q <= '0;
            target_ff_taken_q <= '0;
			target_ff_lane_q <= '0;
        end else if (flush_fetch || bp_invalidate_i) begin
            pc_q <= flush_fetch ? flush_target : bp_invalidate_target_i;
            mem_req_valid_q <= 1'b0;
            mem_req_two_q <= 1'b0;
            mem_req_pc_q <= flush_fetch ? flush_target : bp_invalidate_target_i;
            mem_req_next_pc_q <= flush_fetch ? flush_target : bp_invalidate_target_i;
			mem_req_target_ff_hit_q <= 1'b0;
            pending_redirect_valid_q <= 1'b0;
            pending_redirect_target_q <= '0;
			if (bp_invalidate_i) begin
				target_ff_valid_q <= '0;
				target_ff_taken_q <= '0;
			end
        end else begin
			// On an L0 mismatch the request issued from the stale target is
			// intentionally discarded; pending_redirect_target_q retries the
			// corrected address on the following cycle.
			mem_req_valid_q <= fetch_issue && !target_ff_correction_resp;
            if (fetch_issue) begin
                mem_req_pc_q <= fetch_addr;
                mem_req_two_q <= fetch_two;
				mem_req_target_ff_hit_q <= target_ff_lookup_hit;
                mem_req_next_pc_q <= target_ff_lookup_hit ? target_ff_target :
                    (fetch_addr + (fetch_two ? 32'd8 : 32'd4));
				pc_q <= target_ff_lookup_hit ? target_ff_target :
                    (fetch_addr + (fetch_two ? 32'd8 : 32'd4));
            end

            if (pending_redirect_valid_q && fetch_issue)
                pending_redirect_valid_q <= 1'b0;
            if (predict_correction_resp) begin
                pending_redirect_valid_q <= 1'b1;
				pending_redirect_target_q <= predict_next_pc;
            end

            // Keep direct jumps on the established BTB path.  A zero-bubble
            // early target for JAL can overtake a paired slot1 store replay;
            // conditional branches are the high-frequency L0 use case.
            if (target_ff_train_i.valid && target_ff_train_i.conditional) begin
				target_ff_valid_q[target_ff_train_i.pc[7:3]] <= 1'b1;
				target_ff_taken_q[target_ff_train_i.pc[7:3]] <=
                    target_ff_train_i.taken;
				target_ff_lane_q[target_ff_train_i.pc[7:3]] <=
					target_ff_train_i.pc[2];
            end
        end
    end

endmodule
