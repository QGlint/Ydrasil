// The two visible entries are FFs. Older entries live in a two-bank backing
// ring, whose read addresses depend only on the registered backing head.
module ydrasil_fetch_queue
import ydrasil_pkg::*;
#(
    parameter int DEPTH = 10,
    parameter int COUNT_WIDTH = $clog2(DEPTH + 1),
    parameter int PAYLOAD_WIDTH = 80
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         flush_i,
    input  wire [1:0]                   pop_count_i,
    input  wire [1:0]                   push_count_i,
    input  wire [PAYLOAD_WIDTH-1:0]      push_payload0_i,
    input  wire [PAYLOAD_WIDTH-1:0]      push_payload1_i,
    output wire [COUNT_WIDTH-1:0]       count_o,
    output wire                         valid0_o,
    output wire                         valid1_o,
    output wire [PAYLOAD_WIDTH-1:0]      payload0_o,
    output wire [PAYLOAD_WIDTH-1:0]      payload1_o
);
    localparam int BACK_DEPTH = DEPTH - 2;
    localparam int BANK_DEPTH = BACK_DEPTH / 2;
    localparam int BACK_INDEX_WIDTH = (BACK_DEPTH > 1) ? $clog2(BACK_DEPTH) : 1;
    localparam int BANK_ADDR_WIDTH = (BANK_DEPTH > 1) ? $clog2(BANK_DEPTH) : 1;

    reg [COUNT_WIDTH-1:0] count_q;
    reg [BACK_INDEX_WIDTH-1:0] back_head_q;
    reg [BACK_INDEX_WIDTH-1:0] back_tail_q;
    reg [PAYLOAD_WIDTH-1:0] payload0_q;
    reg [PAYLOAD_WIDTH-1:0] payload1_q;

    function automatic [BACK_INDEX_WIDTH-1:0] advance_back_ptr(
        input [BACK_INDEX_WIDTH-1:0] ptr,
        input [1:0] amount
    );
        logic [BACK_INDEX_WIDTH:0] sum;
        begin
            sum = {1'b0, ptr} + (BACK_INDEX_WIDTH + 1)'(amount);
            advance_back_ptr = (sum >= (BACK_INDEX_WIDTH + 1)'(BACK_DEPTH)) ?
                BACK_INDEX_WIDTH'(sum - (BACK_INDEX_WIDTH + 1)'(BACK_DEPTH)) :
                BACK_INDEX_WIDTH'(sum);
        end
    endfunction

    wire [COUNT_WIDTH-1:0] old_remaining =
        count_q - COUNT_WIDTH'(pop_count_i);
    reg [1:0] back_head_advance;
    always_comb begin
        // Advance once for each backing entry promoted into the FF head. A
        // direct push is a physical backing write promoted on the same edge.
        unique case (count_q)
            COUNT_WIDTH'(0): back_head_advance = push_count_i;
            COUNT_WIDTH'(1): begin
                if (pop_count_i != 2'd0)
                    back_head_advance = push_count_i;
                else
                    back_head_advance = (push_count_i != 2'd0) ? 2'd1 : 2'd0;
            end
            COUNT_WIDTH'(2): begin
                unique case (pop_count_i)
                    2'd0: back_head_advance = 2'd0;
                    2'd1: back_head_advance =
                        (push_count_i != 2'd0) ? 2'd1 : 2'd0;
                    default: back_head_advance = push_count_i;
                endcase
            end
            COUNT_WIDTH'(3): begin
                if (pop_count_i == 2'd0)
                    back_head_advance = 2'd0;
                else if (pop_count_i == 2'd1)
                    back_head_advance = 2'd1;
                else
                    back_head_advance = (push_count_i != 2'd0) ? 2'd2 : 2'd1;
            end
            default: back_head_advance = pop_count_i;
        endcase
    end

    wire [BACK_INDEX_WIDTH-1:0] back_head1 =
        advance_back_ptr(back_head_q, 2'd1);
    wire [BACK_INDEX_WIDTH-1:0] back_tail1 =
        advance_back_ptr(back_tail_q, 2'd1);
    wire [BANK_ADDR_WIDTH-1:0] back_head_addr =
        back_head_q[BACK_INDEX_WIDTH-1:1];
    wire [BANK_ADDR_WIDTH-1:0] back_head1_addr =
        back_head1[BACK_INDEX_WIDTH-1:1];
    wire [BANK_ADDR_WIDTH-1:0] back_tail_addr =
        back_tail_q[BACK_INDEX_WIDTH-1:1];
    wire [BANK_ADDR_WIDTH-1:0] back_tail1_addr =
        back_tail1[BACK_INDEX_WIDTH-1:1];

    wire [BANK_ADDR_WIDTH-1:0] read_addr_even = back_head_q[0] ?
        back_head1_addr : back_head_addr;
    wire [BANK_ADDR_WIDTH-1:0] read_addr_odd = back_head_q[0] ?
        back_head_addr : back_head1_addr;
    wire [PAYLOAD_WIDTH-1:0] payload_even;
    wire [PAYLOAD_WIDTH-1:0] payload_odd;
    wire [PAYLOAD_WIDTH-1:0] backing_payload0 = back_head_q[0] ?
        payload_odd : payload_even;
    wire [PAYLOAD_WIDTH-1:0] backing_payload1 = back_head_q[0] ?
        payload_even : payload_odd;

    reg                         write_even;
    reg                         write_odd;
    reg [BANK_ADDR_WIDTH-1:0]   write_addr_even;
    reg [BANK_ADDR_WIDTH-1:0]   write_addr_odd;
    reg [PAYLOAD_WIDTH-1:0]     write_data_even;
    reg [PAYLOAD_WIDTH-1:0]     write_data_odd;

    always_comb begin
        // Every response is physically written. Entries sent directly to the
        // FF head advance both backing pointers on this edge, so the backing
        // RAM pins never depend on current-cycle pop/stall control.
        write_even = (push_count_i == 2'd2) ||
            ((push_count_i != 2'd0) && !back_tail_q[0]);
        write_odd = (push_count_i == 2'd2) ||
            ((push_count_i != 2'd0) && back_tail_q[0]);
        write_addr_even = back_tail_q[0] ? back_tail1_addr : back_tail_addr;
        write_addr_odd = back_tail_q[0] ? back_tail_addr : back_tail1_addr;
        write_data_even = back_tail_q[0] ? push_payload1_i : push_payload0_i;
        write_data_odd = back_tail_q[0] ? push_payload0_i : push_payload1_i;
    end

    ydrasil_1r1w_ram #(
        .DEPTH       (BANK_DEPTH),
        .DATA_WIDTH  (PAYLOAD_WIDTH),
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
        .DATA_WIDTH  (PAYLOAD_WIDTH),
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

    reg [PAYLOAD_WIDTH-1:0] payload0_d;
    reg [PAYLOAD_WIDTH-1:0] payload1_d;
    always_comb begin
        payload0_d = payload0_q;
        payload1_d = payload1_q;

        if (old_remaining != '0) begin
            unique case (pop_count_i)
                2'd0: payload0_d = payload0_q;
                2'd1: payload0_d = payload1_q;
                default: payload0_d = backing_payload0;
            endcase
        end else if (push_count_i != 2'd0) begin
            payload0_d = push_payload0_i;
        end

        if (old_remaining > COUNT_WIDTH'(1)) begin
            unique case (pop_count_i)
                2'd0: payload1_d = payload1_q;
                2'd1: payload1_d = backing_payload0;
                default: payload1_d = backing_payload1;
            endcase
        end else if ((old_remaining == COUNT_WIDTH'(1)) &&
                     (push_count_i != 2'd0)) begin
            payload1_d = push_payload0_i;
        end else if ((old_remaining == '0) && (push_count_i == 2'd2)) begin
            payload1_d = push_payload1_i;
        end
    end

    assign valid0_o = count_q != '0;
    assign valid1_o = count_q > COUNT_WIDTH'(1);
    assign payload0_o = payload0_q;
    assign payload1_o = payload1_q;
    assign count_o = count_q;

    // Payload has no reset mux; count suppresses stale data after reset/flush.
    always_ff @(posedge clk) begin
        payload0_q <= payload0_d;
        payload1_q <= payload1_d;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            count_q <= '0;
            back_head_q <= '0;
            back_tail_q <= '0;
        end else begin
            count_q <= count_q - COUNT_WIDTH'(pop_count_i) +
                COUNT_WIDTH'(push_count_i);
            if (back_head_advance != 2'd0)
                back_head_q <= advance_back_ptr(back_head_q, back_head_advance);
            if (push_count_i != 2'd0)
                back_tail_q <= advance_back_ptr(back_tail_q, push_count_i);
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert ((DEPTH >= 4) && ((DEPTH % 2) == 0))
            else $fatal(1, "fetch queue depth must be even and at least four");
    end
    always_ff @(posedge clk) begin
        if (rst_n && !flush_i) begin
			assert (({1'b0, back_head_q} <
					 (BACK_INDEX_WIDTH + 1)'(BACK_DEPTH)) &&
					({1'b0, back_tail_q} <
					 (BACK_INDEX_WIDTH + 1)'(BACK_DEPTH)))
                else $fatal(1, "fetch queue backing pointer out of range");
            assert (COUNT_WIDTH'(pop_count_i) <= count_q)
                else $fatal(1, "fetch queue underflow");
            assert (count_q - COUNT_WIDTH'(pop_count_i) +
                    COUNT_WIDTH'(push_count_i) <= COUNT_WIDTH'(DEPTH))
                else $fatal(1, "fetch queue overflow");
        end
    end
`endif
endmodule

module ydrasil_if_stage
import ydrasil_pkg::*;
#(
    parameter int FETCHQ_DEPTH = 4,
    parameter int BHT_ENTRIES = BP_BHT_ENTRIES
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall_if_i,
    input  wire        flush_if_i,
    input  wire        consume_two_i,

    input  wire        branch_jump_i,
    input  wire [31:0] branch_target_i,

    input  wire        bp_predict_taken_i,
    input  wire [31:0] bp_predict_target_i,
    input  wire [1:0]  bp_predict_counter_i,
    input  wire        bp_predict1_taken_i,
    input  wire [31:0] bp_predict1_target_i,
    input  wire [1:0]  bp_predict1_counter_i,
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
    output bp_bht_index_t if_id_pred_bht_index_o,
    output wire        if_id_valid_o,
    output wire [31:0] if_id_instr_o,

    output wire [31:0] if_id1_pc_o,
    output wire        if_id1_pred_hit_o,
    output wire        if_id1_pred_taken_o,
    output wire [31:0] if_id1_pred_target_o,
    output wire [1:0]  if_id1_pred_counter_o,
    output bp_bht_index_t if_id1_pred_bht_index_o,
    output wire        if_id1_valid_o,
    output wire [31:0] if_id1_instr_o,
    output wire        target_ff_hit_o,
    output wire        target_ff_hit1_o,
    output wire        target_ff_correction_o
);

    localparam int COUNT_WIDTH = $clog2(FETCHQ_DEPTH + 1);
    localparam int RESERVED_WIDTH = $clog2(FETCHQ_DEPTH + 3);
    localparam int FETCH_ADDR_TOKEN_WIDTH = ITCM_ADDR_WIDTH + 1;
    localparam int BHT_INDEX_WIDTH = $clog2(BHT_ENTRIES);

    typedef logic [FETCH_ADDR_TOKEN_WIDTH-1:0] fetch_addr_token_t;
    typedef struct packed {
        fetch_addr_token_t pc;
        logic [31:0] instr;
        logic pred_taken;
        fetch_addr_token_t pred_target;
        logic [1:0] pred_counter;
    } fetch_payload_t;
    localparam int FETCH_PAYLOAD_WIDTH = $bits(fetch_payload_t);

    reg [31:0] pc_q;
    reg        mem_req_valid_q;
    reg        mem_req_two_q;
    reg [31:0] mem_req_pc_q;
    reg [31:0] mem_req_next_pc_q;
	reg        mem_req_target_ff_hit_q;
    reg        pending_redirect_valid_q;
    reg [31:0] pending_redirect_target_q;

	localparam int TARGET_FF_ENTRIES = 32;
	localparam int TARGET_FF_TAG_WIDTH = FETCH_ADDR_TOKEN_WIDTH - 6;
	localparam int TARGET_FF_LANE_DATA_WIDTH =
		TARGET_FF_TAG_WIDTH + FETCH_ADDR_TOKEN_WIDTH;
	localparam int TARGET_FF_LANE_WIDTH = 32;
	localparam int TARGET_FF_DATA_WIDTH = 2 * TARGET_FF_LANE_WIDTH;
	localparam int TARGET_FF_WRITE_LANES = TARGET_FF_DATA_WIDTH / 8;
	wire [31:0] fetch_addr;
	wire [31:0] fetch_addr1;
	wire [4:0] target_ff_index = fetch_addr[7:3];
	reg [TARGET_FF_ENTRIES-1:0] target_ff_valid0_q;
	reg [TARGET_FF_ENTRIES-1:0] target_ff_valid1_q;
	wire target_ff_write = target_ff_train_i.valid &&
		target_ff_train_i.conditional && target_ff_train_i.taken;
	wire [4:0] target_ff_write_index = target_ff_train_i.pc[7:3];
	wire [TARGET_FF_DATA_WIDTH-1:0] target_ff_word;
	wire [TARGET_FF_LANE_WIDTH-1:0] target_ff_lane0 =
		target_ff_word[TARGET_FF_LANE_WIDTH-1:0];
	wire [TARGET_FF_LANE_WIDTH-1:0] target_ff_lane1 =
		target_ff_word[TARGET_FF_DATA_WIDTH-1:TARGET_FF_LANE_WIDTH];
	fetch_addr_token_t target_ff_train_pc_token;
	assign target_ff_train_pc_token = {
		target_ff_train_i.pc[31:ITCM_ADDR_WIDTH+2] ==
			DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
		target_ff_train_i.pc[ITCM_ADDR_WIDTH+1:2]};
	wire [TARGET_FF_TAG_WIDTH-1:0] target_ff_train_tag =
		target_ff_train_pc_token[FETCH_ADDR_TOKEN_WIDTH-1:6];
	wire [TARGET_FF_LANE_WIDTH-1:0] target_ff_train_lane =
		{{(TARGET_FF_LANE_WIDTH-TARGET_FF_LANE_DATA_WIDTH){1'b0}},
		 target_ff_train_tag,
		 {target_ff_train_i.target[31:ITCM_ADDR_WIDTH+2] ==
			DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
		  target_ff_train_i.target[ITCM_ADDR_WIDTH+1:2]}};
	wire [TARGET_FF_DATA_WIDTH-1:0] target_ff_write_data =
		target_ff_train_i.pc[2] ?
		{target_ff_train_lane, {TARGET_FF_LANE_WIDTH{1'b0}}} :
		{{TARGET_FF_LANE_WIDTH{1'b0}},
		 target_ff_train_lane};
	wire [TARGET_FF_WRITE_LANES-1:0] target_ff_write_strobe =
		target_ff_write ?
		(target_ff_train_i.pc[2] ? 8'b1111_0000 : 8'b0000_1111) : '0;

	// A 64-bit fetch word performs one L0 lookup. Each halfword lane owns a
	// byte-writeable tag/target subentry, so training one lane does not duplicate
	// the read table or evict the other lane in the same fetch word.
	ydrasil_1r1w_masked_ram #(
		.DEPTH(TARGET_FF_ENTRIES),
		.DATA_WIDTH(TARGET_FF_DATA_WIDTH),
		.ADDR_WIDTH(5),
		.WRITE_LANES(TARGET_FF_WRITE_LANES)
	) u_target_ff_word (
		.clk(clk),
		.ren_i(1'b1),
		.raddr_i(target_ff_index),
		.rdata_o(target_ff_word),
		.wstrb_i(target_ff_write_strobe),
		.waddr_i(target_ff_write_index),
		.wdata_i(target_ff_write_data)
	);

    wire [COUNT_WIDTH-1:0] fetchq_count_q;
    wire fetchq_valid0;
    wire fetchq_valid1;
    fetch_payload_t fetchq_payload0;
    fetch_payload_t fetchq_payload1;

    wire flush_fetch = flush_if_i | branch_jump_i;
    wire [31:0] pc_plus4 = pc_q + 32'd4;
    wire [31:0] flush_target = branch_jump_i ? branch_target_i : pc_plus4;
    wire [1:0] pop_count = (!flush_fetch && !stall_if_i && fetchq_valid0) ?
        ((consume_two_i && fetchq_valid1) ? 2'd2 : 2'd1) : 2'd0;
    wire mem_resp_valid = !flush_fetch && mem_req_valid_q;
    wire [31:0] sequential_next_pc =
        mem_req_pc_q + (mem_req_two_q ? 32'd8 : 32'd4);
    wire lane1_pred_taken = mem_req_two_q && bp_predict1_taken_i;
    wire bram_pred_taken_any = bp_predict_taken_i || lane1_pred_taken;
    // Keep target selection out of the control path to the next request.
    // Each candidate compares in parallel, and only the one-bit result is
    // selected using the established lane0-over-lane1 priority.
    wire [31:0] predict_next_pc = bp_predict_taken_i ? bp_predict_target_i :
        (lane1_pred_taken ? bp_predict1_target_i : sequential_next_pc);
    (* keep = "true" *) wire lane0_target_mismatch =
        bp_predict_target_i != mem_req_next_pc_q;
    (* keep = "true" *) wire lane1_target_mismatch =
        bp_predict1_target_i != mem_req_next_pc_q;
    (* keep = "true" *) wire seq_target_mismatch =
        sequential_next_pc != mem_req_next_pc_q;
    (* keep = "true" *) wire bram_next_pc_mismatch = bp_predict_taken_i ?
        lane0_target_mismatch :
        (lane1_pred_taken ? lane1_target_mismatch : seq_target_mismatch);
    wire predict_redirect_resp = mem_resp_valid && bram_pred_taken_any;
    wire predict_correction_resp = mem_resp_valid && bram_next_pc_mismatch;
	// The registered L0 decision, rather than the returning BRAM data, releases
	// the next fetch.  A stale entry kills that speculative request below and
	// retains the existing one-cycle correction through pending_redirect_target_q.
	wire target_ff_hit = mem_resp_valid && mem_req_target_ff_hit_q;
    wire target_ff_correction_resp = target_ff_hit &&
        bram_next_pc_mismatch;
    wire [1:0] push_count = mem_resp_valid ?
        ((bp_predict_taken_i || !mem_req_two_q) ? 2'd1 : 2'd2) : 2'd0;
    wire [RESERVED_WIDTH-1:0] reserved_count =
        RESERVED_WIDTH'(fetchq_count_q) +
        (mem_req_valid_q ? (mem_req_two_q ? RESERVED_WIDTH'(2) :
         RESERVED_WIDTH'(1)) : '0);
    wire pair_capacity = reserved_count <= RESERVED_WIDTH'(FETCHQ_DEPTH - 2);
    // Launch the next physical fetch whenever queue capacity permits.  A BTB
    // response that corrects the sequential launch is still captured into the
    // redirect state below, but its already-started wrong-path fetch is marked
    // invalid on this edge.  This keeps BRAM tag/data comparison out of the
    // high-fanout PC clock-enable cone without making the stale request visible
    // to the fetch queue on the following cycle.
    wire fetch_issue = !flush_fetch && !bp_invalidate_i && pair_capacity;

    fetch_payload_t fetchq_push_payload0;
    fetch_payload_t fetchq_push_payload1;
    wire [31:0] mem_req_pc_plus4 = mem_req_pc_q + 32'd4;
    always_comb begin
        fetchq_push_payload0 = '0;
        fetchq_push_payload0.pc = {
            mem_req_pc_q[31:ITCM_ADDR_WIDTH+2] ==
                DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
            mem_req_pc_q[ITCM_ADDR_WIDTH+1:2]};
        fetchq_push_payload0.instr = if_mem_rdata_i;
        fetchq_push_payload0.pred_taken = bp_predict_taken_i;
        fetchq_push_payload0.pred_target = {
            bp_predict_target_i[31:ITCM_ADDR_WIDTH+2] ==
                DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
            bp_predict_target_i[ITCM_ADDR_WIDTH+1:2]};
        fetchq_push_payload0.pred_counter = bp_predict_counter_i;

        fetchq_push_payload1 = '0;
        fetchq_push_payload1.pc = {
            mem_req_pc_plus4[31:ITCM_ADDR_WIDTH+2] ==
                DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
            mem_req_pc_plus4[ITCM_ADDR_WIDTH+1:2]};
        fetchq_push_payload1.instr = if_mem_rdata1_i;
        fetchq_push_payload1.pred_taken = bp_predict1_taken_i;
        fetchq_push_payload1.pred_target = {
            bp_predict1_target_i[31:ITCM_ADDR_WIDTH+2] ==
                DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
            bp_predict1_target_i[ITCM_ADDR_WIDTH+1:2]};
        fetchq_push_payload1.pred_counter = bp_predict1_counter_i;
    end
    ydrasil_fetch_queue #(
        .DEPTH      (FETCHQ_DEPTH),
        .COUNT_WIDTH(COUNT_WIDTH),
        .PAYLOAD_WIDTH(FETCH_PAYLOAD_WIDTH)
    ) u_fetch_queue (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush_i        (flush_fetch || bp_invalidate_i),
        .pop_count_i    (pop_count),
        .push_count_i   (push_count),
        .push_payload0_i(fetchq_push_payload0),
        .push_payload1_i(fetchq_push_payload1),
        .count_o        (fetchq_count_q),
        .valid0_o       (fetchq_valid0),
        .valid1_o       (fetchq_valid1),
        .payload0_o     (fetchq_payload0),
        .payload1_o     (fetchq_payload1)
    );
    assign fetch_addr = pending_redirect_valid_q ?
        pending_redirect_target_q : pc_q;
    wire fetch_addr_is_dtcm =
        (fetch_addr >= DTCM_BASE_ADDR) &&
        (fetch_addr < (DTCM_BASE_ADDR + ((32'd1 << DTCM_ADDR_WIDTH) << 2)));
	wire fetch_two = !fetch_addr_is_dtcm && !fetch_addr[2];
	assign fetch_addr1 = fetch_addr + 32'd4;
	fetch_addr_token_t target_ff_lookup_token;
	assign target_ff_lookup_token = {
		fetch_addr[31:ITCM_ADDR_WIDTH+2] ==
			DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
		fetch_addr[ITCM_ADDR_WIDTH+1:2]};
	wire [TARGET_FF_TAG_WIDTH-1:0] target_ff_lookup_tag =
		target_ff_lookup_token[FETCH_ADDR_TOKEN_WIDTH-1:6];
	wire [TARGET_FF_TAG_WIDTH-1:0] target_ff_tag0 = fetch_addr[2] ?
		target_ff_lane1[TARGET_FF_LANE_DATA_WIDTH-1:FETCH_ADDR_TOKEN_WIDTH] :
		target_ff_lane0[TARGET_FF_LANE_DATA_WIDTH-1:FETCH_ADDR_TOKEN_WIDTH];
	wire [TARGET_FF_TAG_WIDTH-1:0] target_ff_tag1 =
		target_ff_lane1[TARGET_FF_LANE_DATA_WIDTH-1:FETCH_ADDR_TOKEN_WIDTH];
	wire fetch_addr_token_t target_ff_target0_token = fetch_addr[2] ?
		target_ff_lane1[FETCH_ADDR_TOKEN_WIDTH-1:0] :
		target_ff_lane0[FETCH_ADDR_TOKEN_WIDTH-1:0];
	wire fetch_addr_token_t target_ff_target1_token =
		target_ff_lane1[FETCH_ADDR_TOKEN_WIDTH-1:0];
	wire [31:0] target_ff_target0 = {
		target_ff_target0_token[FETCH_ADDR_TOKEN_WIDTH-1] ?
			DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2] :
			ITCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
		target_ff_target0_token[ITCM_ADDR_WIDTH-1:0], 2'b00};
	wire [31:0] target_ff_target1 = {
		target_ff_target1_token[FETCH_ADDR_TOKEN_WIDTH-1] ?
			DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2] :
			ITCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
		target_ff_target1_token[ITCM_ADDR_WIDTH-1:0], 2'b00};
    wire target_ff_hit0 =
		(fetch_addr[2] ? target_ff_valid1_q[target_ff_index] :
		 target_ff_valid0_q[target_ff_index]) &&
		(target_ff_tag0 == target_ff_lookup_tag);
    wire target_ff_hit1 = target_ff_valid1_q[target_ff_index] &&
		(target_ff_tag1 == target_ff_lookup_tag);
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
    wire [31:0] fetchq_pc0 = {
        fetchq_payload0.pc[FETCH_ADDR_TOKEN_WIDTH-1] ?
            DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2] :
            ITCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
        fetchq_payload0.pc[ITCM_ADDR_WIDTH-1:0], 2'b00};
    wire [31:0] fetchq_pred_target0 = {
        fetchq_payload0.pred_target[FETCH_ADDR_TOKEN_WIDTH-1] ?
            DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2] :
            ITCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
        fetchq_payload0.pred_target[ITCM_ADDR_WIDTH-1:0], 2'b00};
    wire [31:0] fetchq_pc1 = {
        fetchq_payload1.pc[FETCH_ADDR_TOKEN_WIDTH-1] ?
            DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2] :
            ITCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
        fetchq_payload1.pc[ITCM_ADDR_WIDTH-1:0], 2'b00};
    wire [31:0] fetchq_pred_target1 = {
        fetchq_payload1.pred_target[FETCH_ADDR_TOKEN_WIDTH-1] ?
            DTCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2] :
            ITCM_BASE_ADDR[31:ITCM_ADDR_WIDTH+2],
        fetchq_payload1.pred_target[ITCM_ADDR_WIDTH-1:0], 2'b00};
    // Valid qualifies the complete payload at Decode. Do not spread queue
    // occupancy into every data bit by substituting NOP/zero values while the
    // head is invalid; stale payload is architecturally invisible.
    assign if_id_pc_o = fetchq_pc0;
    assign if_id_instr_o = fetchq_payload0.instr;
    assign if_id_pred_hit_o = fetchq_payload0.pred_taken;
    assign if_id_pred_taken_o = fetchq_payload0.pred_taken;
    assign if_id_pred_target_o = fetchq_pred_target0;
    assign if_id_pred_counter_o = fetchq_payload0.pred_counter;
    wire [BHT_INDEX_WIDTH-1:0] fetchq_bht_index0 =
        BHT_INDEX_WIDTH'(fetchq_pc0 >> 2);
    assign if_id_pred_bht_index_o = BP_BHT_INDEX_WIDTH'(fetchq_bht_index0);

    assign if_id1_valid_o = fetchq_valid1;
    assign if_id1_pc_o = fetchq_pc1;
    assign if_id1_instr_o = fetchq_payload1.instr;
    assign if_id1_pred_hit_o = fetchq_payload1.pred_taken;
    assign if_id1_pred_taken_o = fetchq_payload1.pred_taken;
    assign if_id1_pred_target_o = fetchq_pred_target1;
    assign if_id1_pred_counter_o = fetchq_payload1.pred_counter;
    wire [BHT_INDEX_WIDTH-1:0] fetchq_bht_index1 =
        BHT_INDEX_WIDTH'(fetchq_pc1 >> 2);
    assign if_id1_pred_bht_index_o = BP_BHT_INDEX_WIDTH'(fetchq_bht_index1);

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
            target_ff_valid0_q <= '0;
            target_ff_valid1_q <= '0;
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
				target_ff_valid0_q <= '0;
				target_ff_valid1_q <= '0;
			end
        end else begin
			// On an L0 mismatch the request issued from the stale target is
			// intentionally discarded; pending_redirect_target_q retries the
			// corrected address on the following cycle.
			mem_req_valid_q <= fetch_issue && !target_ff_correction_resp &&
                !predict_correction_resp;
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
                if (target_ff_train_i.pc[2])
					target_ff_valid1_q[target_ff_train_i.pc[7:3]] <=
                        target_ff_train_i.taken;
                else
					target_ff_valid0_q[target_ff_train_i.pc[7:3]] <=
                        target_ff_train_i.taken;
            end
        end
    end

endmodule
