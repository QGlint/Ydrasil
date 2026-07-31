// FPGA execution backend.
//
// Issue owns one registered request per functional unit.  This file keeps the
// execution cones disjoint: ALU0, BIT, MDU and CSR on lane 0; ALU1, BRU and
// AGU on lane 1.  No fast-path copy of an ALU or bit operation is allowed in
// the dispatch/completion glue.
module ydrasil_ex_block
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            flush_ex_i,

    input  wire [PRODUCER_NUM-1:0]         producer_live_mask_i,
    input  wire [PRODUCER_NUM-1:0]         producer_live_epoch_i,
    input  wire                            trap_redirect_i,
    input  wire [DATA_WIDTH-1:0]           csr_ex_rdata_i,

    input  ydrasil_alu_issue_req_t         alu0_req_i,
    input  ydrasil_bit_issue_req_t         bit_req_i,
    input  ydrasil_mdu_issue_req_t         mdu_req_i,
    input  ydrasil_csr_issue_req_t         csr_req_i,

    output wire                            ex_csr_wen_o,
    output wire [DATA_WIDTH-1:0]           ex_csr_wdata_o,
    output wire [1:0]                      ex_csr_fs_wdata_o,
    output wire                            ex_csr_mstatus_wen_o,
    output wire [CSR_ADDR_WIDTH-1:0]       ex_csr_waddr_o,

    output wire [REGS_DATA_WIDTH-1:0]      alu_result_o,
    output wire                            alu_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      alu_rf_waddr_rd_o,
    output producer_id_t                   alu_producer_id_o,
    output ydrasil_gpr_fwd_pkt_t           completion_o,

    output wire                            mul_issue_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_issue_waddr_o,
    output wire [REGS_DATA_WIDTH-1:0]      mul_wdata_rd_o,
    output wire                            mul_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_rf_waddr_rd_o,
    output producer_id_t                   mul_producer_id_o,
    output wire                            mul_result_valid_o,

    output wire                            ex_instret_inc_o,
    output wire                            ex_mul_stall_o
);

    wire alu0_live = alu0_req_i.valid;
    wire bit_live = bit_req_i.valid;
    wire mdu_live = mdu_req_i.valid;
    wire csr_live = csr_req_i.valid;
    producer_id_t main_producer_id;
    logic main_producer_tracked;
    always_comb begin
        main_producer_id = '0;
        main_producer_tracked = 1'b0;
        if (alu0_live) begin
            main_producer_id = alu0_req_i.producer_id;
            main_producer_tracked = alu0_req_i.producer_tracked;
        end else if (bit_live) begin
            main_producer_id = bit_req_i.producer_id;
            main_producer_tracked = bit_req_i.producer_tracked;
        end else if (mdu_live) begin
            main_producer_id = mdu_req_i.producer_id;
            main_producer_tracked = mdu_req_i.producer_tracked;
        end else if (csr_live) begin
            main_producer_id = csr_req_i.producer_id;
            main_producer_tracked = csr_req_i.producer_tracked;
        end
    end

    wire main_producer_live = !main_producer_tracked ||
        producer_live_mask_i[main_producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[main_producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            main_producer_id[PRODUCER_ID_WIDTH-1];
    wire execution_kill = trap_redirect_i ||
        !main_producer_live;

    wire op_mul = mdu_live &&
        (mdu_req_i.operator_info[OP_MUL_MUL] ||
         mdu_req_i.operator_info[OP_MUL_MULH] ||
         mdu_req_i.operator_info[OP_MUL_MULHSU] ||
         mdu_req_i.operator_info[OP_MUL_MULHU]);
    wire op_div = mdu_live &&
        (mdu_req_i.operator_info[OP_MUL_DIV] ||
         mdu_req_i.operator_info[OP_MUL_DIVU] ||
         mdu_req_i.operator_info[OP_MUL_REM] ||
         mdu_req_i.operator_info[OP_MUL_REMU]);

    wire [REGS_DATA_WIDTH-1:0] alu0_result;
    wire alu0_unused_comp;
    wire alu0_wen;
    wire [REGS_ADDR_WIDTH-1:0] alu0_waddr;
    ydrasil_alu #(.DATAWIDTH(DATA_WIDTH)) u_alu0 (
        .operand_a_i(alu0_req_i.operand_a),
        .operand_b_i(alu0_req_i.operand_b),
        .operator_i(alu0_req_i.operator_info),
        .operator_type_i(alu0_req_i.operator_type),
        .id_rf_waddr_rd_i(alu0_req_i.rd_addr),
        .id_alu_rf_wen_rd_i(alu0_req_i.rd_wen),
        .interrupt_i(execution_kill),
        .comp_result_o(alu0_unused_comp),
        .alu_result_o(alu0_result),
        .alu_rf_wen_rd_o(alu0_wen),
        .alu_rf_waddr_rd_o(alu0_waddr)
    );

    wire [REGS_DATA_WIDTH-1:0] bit_result;
    ydrasil_bitmanip u_bit (
        .operand_a_i(bit_req_i.operand_a),
        .operand_b_i(bit_req_i.operand_b),
        .operator_i(bit_req_i.operator_info),
        .operator_type_i(bit_req_i.operator_type),
        .result_o(bit_result)
    );

    wire mul_issue_ready;
    wire mul_issue_valid = op_mul && mul_issue_ready && !execution_kill;
    wire mul_issue_wen = mdu_req_i.rd_wen && (mdu_req_i.rd_addr != '0);
    wire mul_result_valid;
    wire mul_pipe_wen;
    wire [REGS_DATA_WIDTH-1:0] mul_pipe_wdata;
    wire [REGS_ADDR_WIDTH-1:0] mul_pipe_waddr;
    producer_id_t mul_pipe_producer_id;

    reg div_active_q;
    reg div_pending_q;
    reg div_wen_q;
    reg [REGS_ADDR_WIDTH-1:0] div_waddr_q;
    producer_id_t div_producer_id_q;
    reg [OPERATOR_WIDTH-1:0] div_operator_q;
    reg [REGS_DATA_WIDTH-1:0] div_result_q;
    wire div_busy;
    wire div_done;
    wire [REGS_DATA_WIDTH-1:0] div_result;
    wire div_inflight = div_active_q || div_pending_q || div_busy || div_done;
    wire div_redirect_keep =
        producer_live_mask_i[div_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[div_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            div_producer_id_q[PRODUCER_ID_WIDTH-1];
    wire div_kill = trap_redirect_i ||
        (div_inflight && !div_redirect_keep);
    wire div_start = op_div && !div_active_q && !div_pending_q && !div_busy &&
        !div_done && !execution_kill;
    wire div_complete = div_pending_q && !mul_pipe_wen && !div_kill;
    wire div_rf_wen = div_complete && div_wen_q;

    ydrasil_div u_div (
        .clk(clk), .rst_n(rst_n), .flush_i(div_kill), .start_i(div_start),
        .operand_a_i(mdu_req_i.operand_a), .operand_b_i(mdu_req_i.operand_b),
        .operator_i(div_active_q ? div_operator_q : mdu_req_i.operator_info),
        .busy_o(div_busy), .done_o(div_done), .result_o(div_result)
    );

    ydrasil_mul u_mul (
        .clk(clk), .rst_n(rst_n), .flush_i(trap_redirect_i),
        .producer_live_mask_i(producer_live_mask_i),
        .producer_live_epoch_i(producer_live_epoch_i),
        .issue_valid_i(mul_issue_valid), .issue_ready_o(mul_issue_ready),
        .operand_a_i(mdu_req_i.operand_a), .operand_b_i(mdu_req_i.operand_b),
        .operator_i(mdu_req_i.operator_info), .issue_wen_i(mul_issue_wen),
        .issue_waddr_i(mdu_req_i.rd_addr),
        .issue_producer_id_i(mdu_req_i.producer_id),
        .result_valid_o(mul_result_valid), .result_wen_o(mul_pipe_wen),
        .result_waddr_o(mul_pipe_waddr),
        .result_producer_id_o(mul_pipe_producer_id),
        .result_wdata_o(mul_pipe_wdata)
    );

    wire csr_csrrw = csr_live && csr_req_i.op_info[OP_CSR_CSRRW];
    wire csr_csrrs = csr_live && csr_req_i.op_info[OP_CSR_CSRRS];
    wire csr_csrrc = csr_live && csr_req_i.op_info[OP_CSR_CSRRC];
    wire csr_wen = csr_live && csr_req_i.op_info[OP_CSR_WRITE] && !execution_kill;
    wire [REGS_DATA_WIDTH-1:0] csr_wdata = trap_redirect_i ? '0 :
        ({REGS_DATA_WIDTH{csr_csrrw}} & csr_req_i.operand_a) |
        ({REGS_DATA_WIDTH{csr_csrrs}} & (csr_req_i.operand_a | csr_ex_rdata_i)) |
        ({REGS_DATA_WIDTH{csr_csrrc}} & (csr_ex_rdata_i & ~csr_req_i.operand_a));

    wire alu_complete = alu0_live && alu0_req_i.rd_wen &&
        (alu0_req_i.rd_addr != '0) && !execution_kill;
    wire bit_complete = bit_live && bit_req_i.rd_wen &&
        (bit_req_i.rd_addr != '0) && !execution_kill;
    wire csr_complete = csr_live && csr_req_i.rd_wen &&
        (csr_req_i.rd_addr != '0) && !execution_kill;

    reg [REGS_DATA_WIDTH-1:0] result_q;
    reg result_wen_q;
    reg [REGS_ADDR_WIDTH-1:0] result_waddr_q;
    producer_id_t result_producer_q;
    ydrasil_gpr_fwd_pkt_t completion_q;
    reg [REGS_DATA_WIDTH-1:0] csr_wdata_q;
    reg [1:0] csr_fs_wdata_q;
    reg csr_mstatus_wen_q;
    reg csr_wen_q;
    reg [CSR_ADDR_WIDTH-1:0] csr_waddr_q;
    producer_id_t csr_producer_id_q;
    reg csr_producer_tracked_q;

    wire completion_tag_live = !completion_q.producer_tracked ||
        (producer_live_mask_i[
            completion_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
         producer_live_epoch_i[
            completion_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            completion_q.producer_id[PRODUCER_ID_WIDTH-1]);
    wire csr_tag_live = !csr_producer_tracked_q ||
        (producer_live_mask_i[
            csr_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] &&
         producer_live_epoch_i[
            csr_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]] ==
            csr_producer_id_q[PRODUCER_ID_WIDTH-1]);
    wire mul_pipe_tag_live =
        producer_live_mask_i[
            mul_pipe_producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[
            mul_pipe_producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            mul_pipe_producer_id[PRODUCER_ID_WIDTH-1];

`ifndef SYNTHESIS
    // Commit trace observes the lane-0 completion register by these stable
    // names.  They are aliases only; execution has no legacy data path.
    wire alu_rf_wen_rd_ff = result_wen_q;
    wire [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd_ff = result_waddr_q;
    wire [REGS_DATA_WIDTH-1:0] alu_result_ff = result_q;
`endif

    always_ff @(posedge clk) begin
        if (!rst_n || execution_kill) begin
            result_q <= '0;
            result_wen_q <= 1'b0;
            result_waddr_q <= '0;
            result_producer_q <= '0;
            completion_q <= '0;
            csr_wdata_q <= '0;
            csr_fs_wdata_q <= '0;
            csr_mstatus_wen_q <= 1'b0;
            csr_wen_q <= 1'b0;
            csr_waddr_q <= '0;
            csr_producer_id_q <= '0;
            csr_producer_tracked_q <= 1'b0;
        end else begin
            result_wen_q <= alu_complete | bit_complete | csr_complete;
            result_waddr_q <= bit_complete ? bit_req_i.rd_addr :
                csr_complete ? csr_req_i.rd_addr : alu0_req_i.rd_addr;
            result_producer_q <= bit_complete ? bit_req_i.producer_id :
                csr_complete ? csr_req_i.producer_id : alu0_req_i.producer_id;
            result_q <= bit_complete ? bit_result :
                csr_complete ? csr_ex_rdata_i : alu0_result;
            completion_q.valid <= alu_complete | bit_complete | csr_complete;
            completion_q.producer_id <= bit_complete ? bit_req_i.producer_id :
                csr_complete ? csr_req_i.producer_id : alu0_req_i.producer_id;
            completion_q.producer_tracked <= alu_complete ? alu0_req_i.producer_tracked :
                bit_complete ? bit_req_i.producer_tracked : csr_req_i.producer_tracked;
            completion_q.addr <= bit_complete ? bit_req_i.rd_addr :
                csr_complete ? csr_req_i.rd_addr : alu0_req_i.rd_addr;
            completion_q.data <= bit_complete ? bit_result :
                csr_complete ? csr_ex_rdata_i : alu0_result;
            csr_wdata_q <= csr_wdata;
            csr_fs_wdata_q <= csr_wdata[14:13];
            csr_mstatus_wen_q <= csr_wen && (csr_req_i.waddr == CSR_MSTATUS);
            csr_wen_q <= csr_wen;
            csr_waddr_q <= csr_req_i.waddr;
            csr_producer_id_q <= csr_req_i.producer_id;
            csr_producer_tracked_q <= csr_req_i.producer_tracked;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || div_kill) begin
            div_active_q <= 1'b0;
            div_pending_q <= 1'b0;
            div_wen_q <= 1'b0;
            div_waddr_q <= '0;
            div_producer_id_q <= '0;
            div_operator_q <= '0;
            div_result_q <= '0;
        end else begin
            if (div_start) begin
                div_active_q <= 1'b1;
                div_wen_q <= mdu_req_i.rd_wen && (mdu_req_i.rd_addr != '0);
                div_waddr_q <= mdu_req_i.rd_addr;
                div_producer_id_q <= mdu_req_i.producer_id;
                div_operator_q <= mdu_req_i.operator_info;
            end
            if (div_done && div_active_q) begin
                div_active_q <= 1'b0;
                div_pending_q <= div_wen_q;
                div_result_q <= div_result;
            end else if (div_complete) begin
                div_pending_q <= 1'b0;
                div_wen_q <= 1'b0;
                div_waddr_q <= '0;
            end
        end
    end

    assign alu_result_o = result_q;
    assign alu_rf_wen_rd_o = result_wen_q && completion_tag_live;
    assign alu_rf_waddr_rd_o = result_waddr_q;
    assign alu_producer_id_o = result_producer_q;
    always_comb begin
        completion_o = completion_q;
        completion_o.valid = completion_q.valid && completion_tag_live;
    end
    assign mul_issue_o = mul_issue_valid && mul_issue_wen;
    assign mul_issue_waddr_o = mdu_req_i.rd_addr;
    assign mul_wdata_rd_o = div_rf_wen ? div_result_q : mul_pipe_wdata;
    assign mul_rf_wen_rd_o = (mul_pipe_wen && mul_pipe_tag_live) | div_rf_wen;
    assign mul_rf_waddr_rd_o = div_rf_wen ? div_waddr_q : mul_pipe_waddr;
    assign mul_producer_id_o = div_rf_wen ? div_producer_id_q : mul_pipe_producer_id;
    assign mul_result_valid_o = (mul_result_valid && mul_pipe_tag_live) |
        div_complete;
    assign ex_mul_stall_o = op_div &&
        (div_active_q | div_pending_q | div_busy | div_done) && !execution_kill;
    assign ex_instret_inc_o = (alu0_live | bit_live | csr_live) && !execution_kill ||
        div_complete;
    assign ex_csr_wen_o = csr_wen_q && csr_tag_live;
    assign ex_csr_wdata_o = csr_wdata_q;
    assign ex_csr_fs_wdata_o = csr_fs_wdata_q;
    assign ex_csr_mstatus_wen_o = csr_mstatus_wen_q && csr_tag_live;
    assign ex_csr_waddr_o = csr_waddr_q;

endmodule

// Lane 1 contains the second ALU, the single architectural BRU and the AGU.
// BIT and MDU never enter this lane, so their operand/result fanout cannot
// couple to branch prediction or DTCM address generation.
module ydrasil_ex_lane1
import ydrasil_pkg::*;
(
    input wire clk,
    input wire rst_n,
    input wire flush_i,
    input wire execute_i,
    input wire redirect_i,
    input wire [PRODUCER_NUM-1:0] redirect_keep_mask_i,
    input wire [PRODUCER_NUM-1:0] redirect_keep_epoch_i,
    input wire [PRODUCER_NUM-1:0] producer_live_mask_i,
    input wire [PRODUCER_NUM-1:0] producer_live_epoch_i,
    input wire interrupt_i,
    input ydrasil_alu_issue_req_t alu1_req_i,
    input ydrasil_bru_issue_req_t bru_req_i,
    input ydrasil_agu_issue_req_t agu_req_i,
    input wire [INST_ADDR_WIDTH-1:0] trap_redirect_addr_i,
    output ydrasil_gpr_fwd_pkt_t completion_o,
    output ydrasil_lsu_req_pkt_t lsu_req_o,
    output wire ex_branch_jump_o,
    output wire [INST_ADDR_WIDTH-1:0] ex_branch_target_o,
    output wire ex_pc_redirect_o,
    output wire [INST_ADDR_WIDTH-1:0] ex_pc_redirect_target_o,
    output ydrasil_bp_train_pkt_t ex_bp_train_o,
    output wire ex_branch_mispredict_o,
    output wire instret_valid_o,
    output wire [INST_ADDR_WIDTH-1:0] commit_pc_o,
    output wire [INST_DATA_WIDTH-1:0] commit_instr_o
`ifndef SYNTHESIS
    ,output wire dbg_bp_resolve_valid_o
    ,output wire [INST_ADDR_WIDTH-1:0] dbg_bp_resolve_pc_o
    ,output wire dbg_bp_actual_taken_o
    ,output wire [INST_ADDR_WIDTH-1:0] dbg_bp_actual_target_o
    ,output wire [INST_ADDR_WIDTH-1:0] dbg_bp_actual_next_pc_o
    ,output wire dbg_bp_pred_hit_o
    ,output wire dbg_bp_pred_taken_o
    ,output wire [INST_ADDR_WIDTH-1:0] dbg_bp_pred_target_o
    ,output wire [1:0] dbg_bp_pred_counter_o
    ,output wire [INST_ADDR_WIDTH-1:0] dbg_bp_pred_next_pc_o
    ,output wire dbg_bp_mispredict_o
`endif
);
    wire agu_req_live = agu_req_i.producer_tracked &&
        producer_live_mask_i[agu_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[agu_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            agu_req_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire alu1_req_live = alu1_req_i.producer_tracked &&
        producer_live_mask_i[alu1_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[alu1_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            alu1_req_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire bru_req_live = bru_req_i.producer_tracked &&
        producer_live_mask_i[bru_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[bru_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            bru_req_i.producer_id[PRODUCER_ID_WIDTH-1];
    // producer_live_* is updated at the redirect edge.  Requests already in
    // the Issue/EX registers still see the old directory during that cycle,
    // so recovery must explicitly retain their tag before they can execute.
    wire agu_req_recovery_kept =
        redirect_keep_mask_i[agu_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[agu_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            agu_req_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire alu1_req_recovery_kept =
        redirect_keep_mask_i[alu1_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[alu1_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            alu1_req_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire bru_req_recovery_kept =
        redirect_keep_mask_i[bru_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        redirect_keep_epoch_i[bru_req_i.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            bru_req_i.producer_id[PRODUCER_ID_WIDTH-1];
    wire agu_req_survives_redirect = !redirect_i || agu_req_recovery_kept;
    wire alu1_req_survives_redirect = !redirect_i || alu1_req_recovery_kept;
    wire bru_req_survives_redirect = !redirect_i || bru_req_recovery_kept;

    wire [REGS_DATA_WIDTH-1:0] alu1_result;
    wire alu1_unused_comp;
    wire alu1_wen;
    wire [REGS_ADDR_WIDTH-1:0] alu1_waddr;
    ydrasil_alu u_alu1 (
        .operand_a_i(alu1_req_i.operand_a), .operand_b_i(alu1_req_i.operand_b),
        .operator_i(alu1_req_i.operator_info),
        .operator_type_i(alu1_req_i.operator_type),
        .id_rf_waddr_rd_i(alu1_req_i.rd_addr), .id_alu_rf_wen_rd_i(alu1_req_i.rd_wen),
        .interrupt_i(interrupt_i || !alu1_req_live || !alu1_req_survives_redirect), .comp_result_o(alu1_unused_comp),
        .alu_result_o(alu1_result), .alu_rf_wen_rd_o(alu1_wen),
        .alu_rf_waddr_rd_o(alu1_waddr)
    );

    wire [BUS_ADDR_WIDTH-1:0] agu_addr = agu_req_i.operand_a + agu_req_i.operand_b;
    ydrasil_lsu_req_pkt_t agu_req_d, agu_req_q;
    always_comb begin
        agu_req_d = '0;
        agu_req_d.valid = execute_i && agu_req_i.valid && !interrupt_i && !flush_i &&
            agu_req_live && agu_req_survives_redirect;
        agu_req_d.is_load = agu_req_i.is_load;
        agu_req_d.is_store = agu_req_i.is_store;
        agu_req_d.op = agu_req_i.op;
        agu_req_d.addr = agu_addr;
        agu_req_d.addr_is_dtcm =
            agu_addr[31:DTCM_ADDR_WIDTH+2] == DTCM_BASE_ADDR[31:DTCM_ADDR_WIDTH+2];
        agu_req_d.rd_addr = agu_req_i.rd_addr;
        agu_req_d.producer_id = agu_req_i.producer_id;
        agu_req_d.producer_tracked = agu_req_i.producer_tracked;
        agu_req_d.store_data = agu_req_i.store_data;
        agu_req_d.store_data_valid = agu_req_i.store_data_valid;
        if (agu_req_i.op[OP_LSU_SB])
            agu_req_d.store_mask = 4'b0001 << agu_addr[1:0];
        else if (agu_req_i.op[OP_LSU_SH])
            agu_req_d.store_mask = agu_addr[1] ? 4'b1100 : 4'b0011;
        else if (agu_req_i.op[OP_LSU_SW])
            agu_req_d.store_mask = 4'b1111;
    end

    ydrasil_bru u_bru (
        .clk(clk), .rst_n(rst_n), .flush_i(flush_i),
        .operand_a_i(bru_req_i.operand_a), .operand_b_i(bru_req_i.operand_b),
        .bt_a_operand_i(bru_req_i.bt_a_operand), .bt_b_operand_i(bru_req_i.bt_b_operand),
        .operator_i(bru_req_i.operator_info), .operator_type_i(bru_req_i.operator_type),
        .id_ex_valid_i(bru_req_i.valid && bru_req_live && bru_req_survives_redirect),
        .id_ex_jalr_i(bru_req_i.jalr),
        .id_ex_branch_target_i(bru_req_i.branch_target),
        .id_ex_branch_next_pc_i(bru_req_i.branch_next_pc),
        .id_ex_branch_eq_i(1'b0), .id_ex_branch_ge_signed_i(1'b0),
        .id_ex_branch_ge_unsigned_i(1'b0), .id_ex_pred_hit_i(bru_req_i.pred_hit),
        .id_ex_pred_taken_i(bru_req_i.pred_taken), .id_ex_pred_target_i(bru_req_i.pred_target),
        .id_ex_pred_counter_i(bru_req_i.pred_counter),
        .id_ex_pred_bht_index_i(bru_req_i.pred_bht_index),
        .id_ex_producer_id_i(bru_req_i.producer_id), .trap_redirect_i(interrupt_i),
        .trap_redirect_addr_i(trap_redirect_addr_i), .ex_branch_jump_o(ex_branch_jump_o),
        .ex_branch_target_o(ex_branch_target_o), .ex_pc_redirect_o(ex_pc_redirect_o),
        .ex_pc_redirect_target_o(ex_pc_redirect_target_o), .ex_bp_train_o(ex_bp_train_o),
        .ex_branch_mispredict_o(ex_branch_mispredict_o)
`ifndef SYNTHESIS
        ,.dbg_bp_resolve_valid_o(dbg_bp_resolve_valid_o)
        ,.dbg_bp_resolve_pc_o(dbg_bp_resolve_pc_o)
        ,.dbg_bp_actual_taken_o(dbg_bp_actual_taken_o)
        ,.dbg_bp_actual_target_o(dbg_bp_actual_target_o)
        ,.dbg_bp_actual_next_pc_o(dbg_bp_actual_next_pc_o)
        ,.dbg_bp_pred_hit_o(dbg_bp_pred_hit_o)
        ,.dbg_bp_pred_taken_o(dbg_bp_pred_taken_o)
        ,.dbg_bp_pred_target_o(dbg_bp_pred_target_o)
        ,.dbg_bp_pred_counter_o(dbg_bp_pred_counter_o)
        ,.dbg_bp_pred_next_pc_o(dbg_bp_pred_next_pc_o)
        ,.dbg_bp_mispredict_o(dbg_bp_mispredict_o)
`endif
    );

    // Lane 1 owns both ALU1 and BRU, so it has one registered completion
    // token.  JAL/JALR writes the architectural link value (PC + 4) through
    // this token; conditional branches only use the BRU redirect path.
    wire alu1_completion = alu1_req_i.valid && alu1_req_i.rd_wen &&
        (alu1_req_i.rd_addr != '0) && !interrupt_i && alu1_req_live &&
        alu1_req_survives_redirect;
    wire bru_link_completion = bru_req_i.valid && bru_req_i.rd_wen &&
        (bru_req_i.rd_addr != '0) && !interrupt_i && bru_req_live &&
        bru_req_survives_redirect;
    ydrasil_gpr_fwd_pkt_t completion_q;
    always_ff @(posedge clk) begin
        if (!rst_n || flush_i) begin
            completion_q <= '0;
            agu_req_q <= '0;
        end else begin
            completion_q <= '0;
            if (alu1_completion) begin
                completion_q.valid <= 1'b1;
                completion_q.producer_id <= alu1_req_i.producer_id;
                completion_q.producer_tracked <= alu1_req_i.producer_tracked;
                completion_q.addr <= alu1_req_i.rd_addr;
                completion_q.data <= alu1_result;
            end else if (bru_link_completion) begin
                completion_q.valid <= 1'b1;
                completion_q.producer_id <= bru_req_i.producer_id;
                completion_q.producer_tracked <= bru_req_i.producer_tracked;
                completion_q.addr <= bru_req_i.rd_addr;
                completion_q.data <= bru_req_i.branch_next_pc;
            end
            agu_req_q <= agu_req_d;
        end
    end
    wire completion_q_live = completion_q.producer_tracked &&
        producer_live_mask_i[completion_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[completion_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            completion_q.producer_id[PRODUCER_ID_WIDTH-1];
    wire agu_req_q_live = agu_req_q.producer_tracked &&
        producer_live_mask_i[agu_req_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] &&
        producer_live_epoch_i[agu_req_q.producer_id[PRODUCER_SLOT_WIDTH-1:0]] ==
            agu_req_q.producer_id[PRODUCER_ID_WIDTH-1];
    always_comb begin
        completion_o = completion_q;
        completion_o.valid = completion_q.valid && completion_q_live;
        lsu_req_o = agu_req_q;
        lsu_req_o.valid = agu_req_q.valid && agu_req_q_live;
    end
    assign instret_valid_o = (alu1_req_i.valid && alu1_req_live &&
        alu1_req_survives_redirect || bru_req_i.valid && bru_req_live &&
        bru_req_survives_redirect) && !interrupt_i;
    assign commit_pc_o = '0;
    assign commit_instr_o = RV32I_INS_NOP;
endmodule
