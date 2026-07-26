module ydrasil_if_stage
import ydrasil_pkg::*;
#(
    parameter int FETCHQ_DEPTH = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall_if_i,
    input  wire        stall_pc_i,
    input  wire        flush_if_i,
    input  wire        consume_two_i,

    input  wire        branch_jump_i,
    input  wire [31:0] branch_target_i,

    input  wire        bp_predict_hit_i,
    input  wire        bp_predict_taken_i,
    input  wire [31:0] bp_predict_target_i,
    input  wire [1:0]  bp_predict_counter_i,
    input  wire [31:0] bp_predict_bht_index_i,
    input  wire [BP_GHR_WIDTH-1:0] bp_predict_history_i,
    input  wire        bp_predict1_hit_i,
    input  wire        bp_predict1_taken_i,
    input  wire [31:0] bp_predict1_target_i,
    input  wire [1:0]  bp_predict1_counter_i,
    input  wire [31:0] bp_predict1_bht_index_i,
    input  wire [BP_GHR_WIDTH-1:0] bp_predict1_history_i,
    input  wire        bp_invalidate_i,

    output ydrasil_bp_spec_update_pkt_t bp_spec_update_o,

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
    output wire [BP_GHR_WIDTH-1:0] if_id_pred_history_o,
    output wire        if_id_valid_o,
    output wire [31:0] if_id_instr_o,

    output wire [31:0] if_id1_pc_o,
    output wire        if_id1_pred_hit_o,
    output wire        if_id1_pred_taken_o,
    output wire [31:0] if_id1_pred_target_o,
    output wire [1:0]  if_id1_pred_counter_o,
    output wire [31:0] if_id1_pred_bht_index_o,
    output wire [BP_GHR_WIDTH-1:0] if_id1_pred_history_o,
    output wire        if_id1_valid_o,
    output wire [31:0] if_id1_instr_o
);

    localparam int COUNT_WIDTH = $clog2(FETCHQ_DEPTH + 1);
    localparam int RESERVED_WIDTH = $clog2(FETCHQ_DEPTH + 3);

    reg [31:0] pc_q;
    reg        mem_req_valid_q;
    reg        mem_req_two_q;
    reg [31:0] mem_req_pc_q;
    reg        pending_redirect_valid_q;
    reg [31:0] pending_redirect_target_q;

    reg [COUNT_WIDTH-1:0] fetchq_count_q;
    reg [31:0] fetchq_pc_q [0:FETCHQ_DEPTH-1];
    reg [31:0] fetchq_instr_q [0:FETCHQ_DEPTH-1];
    reg        fetchq_pred_hit_q [0:FETCHQ_DEPTH-1];
    reg        fetchq_pred_taken_q [0:FETCHQ_DEPTH-1];
    reg [31:0] fetchq_pred_target_q [0:FETCHQ_DEPTH-1];
    reg [1:0]  fetchq_pred_counter_q [0:FETCHQ_DEPTH-1];
    reg [31:0] fetchq_pred_bht_index_q [0:FETCHQ_DEPTH-1];
    reg [BP_GHR_WIDTH-1:0] fetchq_pred_history_q [0:FETCHQ_DEPTH-1];

    wire flush_fetch = flush_if_i | branch_jump_i;
    wire [31:0] pc_plus4 = pc_q + 32'd4;
    wire [31:0] flush_target = branch_jump_i ? branch_target_i : pc_plus4;
    wire fetchq_valid0 = fetchq_count_q != '0;
    wire fetchq_valid1 = fetchq_count_q > COUNT_WIDTH'(1);
    wire [1:0] pop_count = (!flush_fetch && !stall_if_i && fetchq_valid0) ?
        ((consume_two_i && fetchq_valid1) ? 2'd2 : 2'd1) : 2'd0;
    logic [31:0] invalidate_target;
    always_comb begin
        if (fetchq_count_q > COUNT_WIDTH'(pop_count)) begin
            case (pop_count)
                2'd0: invalidate_target = fetchq_pc_q[0];
                2'd1: invalidate_target = fetchq_pc_q[1];
                default: invalidate_target = fetchq_pc_q[2];
            endcase
        end else if (mem_req_valid_q) begin
            invalidate_target = mem_req_pc_q;
        end else if (pending_redirect_valid_q) begin
            invalidate_target = pending_redirect_target_q;
        end else begin
            invalidate_target = pc_q;
        end
    end

    wire mem_resp_valid = !flush_fetch && mem_req_valid_q;
    wire predict_redirect_resp = mem_resp_valid &&
        (bp_predict_taken_i || (mem_req_two_q && bp_predict1_taken_i));
    wire [31:0] predict_redirect_target = bp_predict_taken_i ?
        bp_predict_target_i : bp_predict1_target_i;
    wire [1:0] push_count = mem_resp_valid ?
        ((bp_predict_taken_i || !mem_req_two_q) ? 2'd1 : 2'd2) : 2'd0;
    wire response0_conditional = mem_resp_valid &&
        (if_mem_rdata_i[6:0] == RV32I_INS_TYPE_B);
    wire response1_conditional = (push_count == 2'd2) &&
        (if_mem_rdata1_i[6:0] == RV32I_INS_TYPE_B);
    wire response0_taken = (if_mem_rdata_i[6:0] == RV32I_INS_TYPE_B) ?
        bp_predict_taken_i : 1'b1;
    wire response1_taken = (if_mem_rdata1_i[6:0] == RV32I_INS_TYPE_B) ?
        bp_predict1_taken_i : 1'b1;
    wire [BP_GHR_WIDTH-1:0] response1_history = response0_conditional ?
        {bp_predict_history_i[BP_GHR_WIDTH-2:0], response0_taken} :
        bp_predict1_history_i;

    always_comb begin
        bp_spec_update_o = '0;
        if (response0_conditional && response1_conditional) begin
            bp_spec_update_o.count = 2'd2;
            bp_spec_update_o.taken = {response1_taken, response0_taken};
        end else if (response0_conditional) begin
            bp_spec_update_o.count = 2'd1;
            bp_spec_update_o.taken[0] = response0_taken;
        end else if (response1_conditional) begin
            bp_spec_update_o.count = 2'd1;
            bp_spec_update_o.taken[0] = response1_taken;
        end
    end
    wire [COUNT_WIDTH-1:0] post_pop_count = fetchq_count_q - COUNT_WIDTH'(pop_count);
    wire [RESERVED_WIDTH-1:0] reserved_count =
        RESERVED_WIDTH'(fetchq_count_q) +
        (mem_req_valid_q ? (mem_req_two_q ? RESERVED_WIDTH'(2) :
         RESERVED_WIDTH'(1)) : '0);
    wire pair_capacity = reserved_count <= RESERVED_WIDTH'(FETCHQ_DEPTH - 2);
    wire fetch_issue = !flush_fetch && !bp_invalidate_i && pair_capacity;
    // BTB and ITCM responses arrive together. Feed a taken target directly
    // into the next ITCM request; the pending register is only a capacity
    // fallback, not an unconditional redirect bubble.
    wire [31:0] fetch_addr = predict_redirect_resp ?
        predict_redirect_target : pending_redirect_valid_q ?
        pending_redirect_target_q : pc_q;
    wire fetch_addr_is_dtcm =
        (fetch_addr >= DTCM_BASE_ADDR) &&
        (fetch_addr < (DTCM_BASE_ADDR + ((32'd1 << DTCM_ADDR_WIDTH) << 2)));
    wire fetch_two = !fetch_addr_is_dtcm;

    // 保留验证环境使用的历史观测点名称。
    wire [31:0] pc_ff = pc_q;
    wire mem_req_valid_ff = mem_req_valid_q;
    wire pending_redirect_valid_ff = pending_redirect_valid_q;
    wire bp_predict_redirect = predict_redirect_resp;

    assign if_mem_addr_o = fetch_addr;
    assign if_mem_addr1_o = fetch_addr + 32'd4;
    assign bp_lookup_pc_o = fetch_addr;

    assign if_id_valid_o = fetchq_valid0;
    assign if_id_pc_o = fetchq_valid0 ? fetchq_pc_q[0] : RESET_INS;
    assign if_id_instr_o = fetchq_valid0 ? fetchq_instr_q[0] : RV32I_INS_NOP;
    assign if_id_pred_hit_o = fetchq_valid0 && fetchq_pred_hit_q[0];
    assign if_id_pred_taken_o = fetchq_valid0 && fetchq_pred_taken_q[0];
    assign if_id_pred_target_o = fetchq_valid0 ? fetchq_pred_target_q[0] : '0;
    assign if_id_pred_counter_o = fetchq_valid0 ? fetchq_pred_counter_q[0] : 2'b01;
    assign if_id_pred_bht_index_o = fetchq_valid0 ? fetchq_pred_bht_index_q[0] : '0;
    assign if_id_pred_history_o = fetchq_valid0 ? fetchq_pred_history_q[0] : '0;

    assign if_id1_valid_o = fetchq_valid1;
    assign if_id1_pc_o = fetchq_valid1 ? fetchq_pc_q[1] : (RESET_INS + 32'd4);
    assign if_id1_instr_o = fetchq_valid1 ? fetchq_instr_q[1] : RV32I_INS_NOP;
    assign if_id1_pred_hit_o = fetchq_valid1 && fetchq_pred_hit_q[1];
    assign if_id1_pred_taken_o = fetchq_valid1 && fetchq_pred_taken_q[1];
    assign if_id1_pred_target_o = fetchq_valid1 ? fetchq_pred_target_q[1] : '0;
    assign if_id1_pred_counter_o = fetchq_valid1 ? fetchq_pred_counter_q[1] : 2'b01;
    assign if_id1_pred_bht_index_o = fetchq_valid1 ? fetchq_pred_bht_index_q[1] : '0;
    assign if_id1_pred_history_o = fetchq_valid1 ? fetchq_pred_history_q[1] : '0;

    integer idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q <= RESET_INS;
            mem_req_valid_q <= 1'b0;
            mem_req_two_q <= 1'b0;
            mem_req_pc_q <= RESET_INS;
            pending_redirect_valid_q <= 1'b0;
            pending_redirect_target_q <= '0;
            fetchq_count_q <= '0;
            for (idx = 0; idx < FETCHQ_DEPTH; idx = idx + 1) begin
                fetchq_pc_q[idx] <= '0;
                fetchq_instr_q[idx] <= RV32I_INS_NOP;
                fetchq_pred_hit_q[idx] <= 1'b0;
                fetchq_pred_taken_q[idx] <= 1'b0;
                fetchq_pred_target_q[idx] <= '0;
                fetchq_pred_counter_q[idx] <= 2'b01;
                fetchq_pred_bht_index_q[idx] <= '0;
                fetchq_pred_history_q[idx] <= '0;
            end
        end else if (flush_fetch || bp_invalidate_i) begin
            pc_q <= flush_fetch ? flush_target : invalidate_target;
            mem_req_valid_q <= 1'b0;
            mem_req_two_q <= 1'b0;
            mem_req_pc_q <= flush_fetch ? flush_target : invalidate_target;
            pending_redirect_valid_q <= 1'b0;
            pending_redirect_target_q <= '0;
            fetchq_count_q <= '0;
        end else begin
            mem_req_valid_q <= fetch_issue;
            if (fetch_issue) begin
                mem_req_pc_q <= fetch_addr;
                mem_req_two_q <= fetch_two;
                pc_q <= fetch_addr + (fetch_two ? 32'd8 : 32'd4);
            end

            if (pending_redirect_valid_q && fetch_issue)
                pending_redirect_valid_q <= 1'b0;
            if (predict_redirect_resp) begin
                pending_redirect_valid_q <= !fetch_issue;
                pending_redirect_target_q <= predict_redirect_target;
            end

            if (pop_count == 2'd2) begin
                for (idx = 0; idx < FETCHQ_DEPTH-2; idx = idx + 1) begin
                    fetchq_pc_q[idx] <= fetchq_pc_q[idx+2];
                    fetchq_instr_q[idx] <= fetchq_instr_q[idx+2];
                    fetchq_pred_hit_q[idx] <= fetchq_pred_hit_q[idx+2];
                    fetchq_pred_taken_q[idx] <= fetchq_pred_taken_q[idx+2];
                    fetchq_pred_target_q[idx] <= fetchq_pred_target_q[idx+2];
                    fetchq_pred_counter_q[idx] <= fetchq_pred_counter_q[idx+2];
                    fetchq_pred_bht_index_q[idx] <= fetchq_pred_bht_index_q[idx+2];
                    fetchq_pred_history_q[idx] <= fetchq_pred_history_q[idx+2];
                end
            end else if (pop_count == 2'd1) begin
                for (idx = 0; idx < FETCHQ_DEPTH-1; idx = idx + 1) begin
                    fetchq_pc_q[idx] <= fetchq_pc_q[idx+1];
                    fetchq_instr_q[idx] <= fetchq_instr_q[idx+1];
                    fetchq_pred_hit_q[idx] <= fetchq_pred_hit_q[idx+1];
                    fetchq_pred_taken_q[idx] <= fetchq_pred_taken_q[idx+1];
                    fetchq_pred_target_q[idx] <= fetchq_pred_target_q[idx+1];
                    fetchq_pred_counter_q[idx] <= fetchq_pred_counter_q[idx+1];
                    fetchq_pred_bht_index_q[idx] <= fetchq_pred_bht_index_q[idx+1];
                    fetchq_pred_history_q[idx] <= fetchq_pred_history_q[idx+1];
                end
            end

            if (push_count != 2'd0) begin
                fetchq_pc_q[post_pop_count] <= mem_req_pc_q;
                fetchq_instr_q[post_pop_count] <= if_mem_rdata_i;
                fetchq_pred_hit_q[post_pop_count] <= bp_predict_hit_i;
                fetchq_pred_taken_q[post_pop_count] <= bp_predict_taken_i;
                fetchq_pred_target_q[post_pop_count] <= bp_predict_target_i;
                fetchq_pred_counter_q[post_pop_count] <= bp_predict_counter_i;
                fetchq_pred_bht_index_q[post_pop_count] <= bp_predict_bht_index_i;
                fetchq_pred_history_q[post_pop_count] <= bp_predict_history_i;
            end
            if (push_count == 2'd2) begin
                fetchq_pc_q[post_pop_count + COUNT_WIDTH'(1)] <= mem_req_pc_q + 32'd4;
                fetchq_instr_q[post_pop_count + COUNT_WIDTH'(1)] <= if_mem_rdata1_i;
                fetchq_pred_hit_q[post_pop_count + COUNT_WIDTH'(1)] <= bp_predict1_hit_i;
                fetchq_pred_taken_q[post_pop_count + COUNT_WIDTH'(1)] <= bp_predict1_taken_i;
                fetchq_pred_target_q[post_pop_count + COUNT_WIDTH'(1)] <= bp_predict1_target_i;
                fetchq_pred_counter_q[post_pop_count + COUNT_WIDTH'(1)] <= bp_predict1_counter_i;
                fetchq_pred_bht_index_q[post_pop_count + COUNT_WIDTH'(1)] <= bp_predict1_bht_index_i;
                fetchq_pred_history_q[post_pop_count + COUNT_WIDTH'(1)] <= response1_history;
            end
            fetchq_count_q <= post_pop_count + COUNT_WIDTH'(push_count);
        end
    end

    wire unused_stall_pc = stall_pc_i;

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && !flush_fetch && !bp_invalidate_i)
            assert (post_pop_count + COUNT_WIDTH'(push_count) <= COUNT_WIDTH'(FETCHQ_DEPTH))
                else $fatal(1, "fetch queue overflow");
    end
`endif

endmodule
