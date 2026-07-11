module ydrasil_ctrl
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,

    // from ex
    input  wire                         ex_branch_jump_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ex_branch_target_i,
    input  ydrasil_ex_hzd_pkt_t         ex_hzd_i,

    input  ydrasil_id_ctrl_pkt_t        id_ctrl_i,
    input  ydrasil_gpr_fwd_pkt_t        alu_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t        lsu_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t        mul_fwd_i,
    input  wire                         lsu_ctrl_busy_i,
    input  wire                         clint_stall_i,
    input  wire                         ex_mul_stall_i,
    input  wire                         wb_backpressure_i,
    input  wire                         rf_wen_rd_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] rf_waddr_rd_i,
    input  wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_wdata_rd_i,

    output ydrasil_hzd_status_pkt_t     hzd_status_o,
    output ydrasil_gpr_fwd_pkt_t        wb_fwd_o,
    output ydrasil_gpr_fwd_pkt_t        producer_rs1_fwd_o,
    output ydrasil_gpr_fwd_pkt_t        producer_rs2_fwd_o,
    output wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_o,
    output wire                         ex_accept_valid_o,

    output wire                         stall_if_o,
    output wire                         stall_id_o,
    output wire                         stall_pc_o,
    output wire                         bubble_id_o,
    output wire                         flush_if_o,
    output wire                         flush_id_o,
    output wire                         flush_ex_o,
    output wire                         branch_jump_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] branch_target_o
);

    reg [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_q;
    reg [ydrasil_pkg::REGS_NUM-1:0] producer_ready_q;
    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] producer_value_q [0:ydrasil_pkg::REGS_NUM-1];
    ydrasil_gpr_fwd_pkt_t wb_fwd_q;
    integer producer_idx;

    wire ex_is_load =
        ex_hzd_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD];
    wire ex_is_alu =
        ex_hzd_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU];
    wire ex_is_mul =
        ex_hzd_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL];
    wire ex_is_bitmanip =
        ex_hzd_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];

    wire id_ex_rd_issue =
        ex_accept_valid_o & (ex_hzd_i.rd_addr != '0) & !ex_hzd_i.interrupt &
        (ex_hzd_i.alu_rf_wen | ex_is_load);
    wire id_ex_prev_alu_bypassable =
        ex_accept_valid_o & ex_hzd_i.alu_rf_wen & (ex_hzd_i.rd_addr != '0) &
        !ex_hzd_i.interrupt & ex_is_alu & !ex_is_bitmanip &
        (ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_ADD]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_SUB]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_SLT]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_SLTU] |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_XOR]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_OR]   |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_AND]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_LUI]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_AUIPC]);

    wire prev_alu_bypass_rs1 =
        id_ex_prev_alu_bypassable & id_ctrl_i.prev_alu_bypass_ok &
        id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr);
    wire prev_alu_bypass_rs2 =
        id_ex_prev_alu_bypassable & id_ctrl_i.prev_alu_bypass_ok &
        id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr);

    wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_clear_mask =
        wb_fwd_q.valid ? (ydrasil_pkg::REGS_NUM'(1) << wb_fwd_q.addr) : '0;
    wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_issue_mask =
        id_ex_rd_issue ? (ydrasil_pkg::REGS_NUM'(1) << ex_hzd_i.rd_addr) : '0;
    wire id_ex_rd_flush_kill =
        ex_branch_jump_i & ex_hzd_i.valid & (ex_hzd_i.rd_addr != '0) &
        (ex_hzd_i.alu_rf_wen | ex_is_load);
    wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_flush_kill_mask =
        id_ex_rd_flush_kill ? (ydrasil_pkg::REGS_NUM'(1) << ex_hzd_i.rd_addr) : '0;
    wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_for_hazard =
        (gpr_pending_q & ~gpr_pending_clear_mask & ~gpr_pending_flush_kill_mask) |
        gpr_pending_issue_mask;

    wire rs1_clear_fwd =
        (wb_fwd_q.valid & id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr != '0) &
         (id_ctrl_i.rs1_addr == wb_fwd_q.addr)) |
        (lsu_fwd_i.valid & id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr != '0) &
         (id_ctrl_i.rs1_addr == lsu_fwd_i.addr)) |
        (alu_fwd_i.valid & id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr != '0) &
         (id_ctrl_i.rs1_addr == alu_fwd_i.addr)) |
        (mul_fwd_i.valid & id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr != '0) &
         (id_ctrl_i.rs1_addr == mul_fwd_i.addr)) |
        producer_rs1_fwd_o.valid;
    wire rs2_clear_fwd =
        (wb_fwd_q.valid & id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr != '0) &
         (id_ctrl_i.rs2_addr == wb_fwd_q.addr)) |
        (lsu_fwd_i.valid & id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr != '0) &
         (id_ctrl_i.rs2_addr == lsu_fwd_i.addr)) |
        (alu_fwd_i.valid & id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr != '0) &
         (id_ctrl_i.rs2_addr == alu_fwd_i.addr)) |
        (mul_fwd_i.valid & id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr != '0) &
         (id_ctrl_i.rs2_addr == mul_fwd_i.addr)) |
        producer_rs2_fwd_o.valid;
    wire rd_clear_fwd =
        (wb_fwd_q.valid & id_ctrl_i.rd_wen & (id_ctrl_i.rd_addr != '0) &
         (id_ctrl_i.rd_addr == wb_fwd_q.addr)) |
        (lsu_fwd_i.valid & id_ctrl_i.rd_wen & (id_ctrl_i.rd_addr != '0) &
         (id_ctrl_i.rd_addr == lsu_fwd_i.addr)) |
        (alu_fwd_i.valid & id_ctrl_i.rd_wen & (id_ctrl_i.rd_addr != '0) &
         (id_ctrl_i.rd_addr == alu_fwd_i.addr));

    wire rs1_issue_hzd =
        id_ex_rd_issue & id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr) &
        !prev_alu_bypass_rs1;
    wire rs2_issue_hzd =
        id_ex_rd_issue & id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr) &
        !prev_alu_bypass_rs2;
    wire rd_issue_hzd =
        id_ex_rd_issue & id_ctrl_i.rd_wen & (id_ctrl_i.rd_addr == ex_hzd_i.rd_addr);
    wire rs1_pending_stall =
        id_ctrl_i.rs1_ren && gpr_pending_q[id_ctrl_i.rs1_addr] && !rs1_clear_fwd;
    wire rs2_pending_stall =
        id_ctrl_i.rs2_ren && gpr_pending_q[id_ctrl_i.rs2_addr] && !rs2_clear_fwd;
    wire rd_waw_stall =
        id_ctrl_i.rd_wen && gpr_pending_q[id_ctrl_i.rd_addr] && !rd_clear_fwd;
    wire store_data_wait =
        id_ctrl_i.store_req & (rs2_issue_hzd | rs2_pending_stall);
    wire scoreboard_stall =
        rs1_issue_hzd |
        (rs2_issue_hzd & !id_ctrl_i.store_req) |
        rd_issue_hzd |
        rs1_pending_stall |
        (rs2_pending_stall & !id_ctrl_i.store_req) |
        rd_waw_stall;
    wire lsu_struct_stall = id_ctrl_i.lsu_req & lsu_ctrl_busy_i;
    wire decode_bubble_stall =
        scoreboard_stall | lsu_struct_stall | clint_stall_i | wb_backpressure_i;

    assign ex_accept_valid_o = ex_hzd_i.valid & !ex_branch_jump_i;
    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;
    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o;
    assign flush_ex_o = branch_jump_o;
    assign stall_id_o = ex_mul_stall_i;
    assign stall_if_o = decode_bubble_stall | ex_mul_stall_i;
    assign stall_pc_o = decode_bubble_stall | ex_mul_stall_i;
    assign bubble_id_o = decode_bubble_stall;

    assign hzd_status_o.scoreboard_stall = scoreboard_stall;
    assign hzd_status_o.lsu_struct_stall = lsu_struct_stall;
    assign hzd_status_o.issue_store_data_ready = !id_ctrl_i.store_req | !store_data_wait;
    assign hzd_status_o.prev_alu_bypass_rs1 = prev_alu_bypass_rs1;
    assign hzd_status_o.prev_alu_bypass_rs2 = prev_alu_bypass_rs2;
    assign hzd_status_o.rs1_pending_stall = rs1_pending_stall;
    assign hzd_status_o.rs2_pending_stall = rs2_pending_stall;
    assign hzd_status_o.rd_waw_stall = rd_waw_stall;
    assign hzd_status_o.rs1_issue_hzd = rs1_issue_hzd;
    assign hzd_status_o.rs2_issue_hzd = rs2_issue_hzd;
    assign hzd_status_o.rd_issue_hzd = rd_issue_hzd;
    assign hzd_status_o.issue_load_producer = id_ex_rd_issue & ex_is_load;
    assign hzd_status_o.issue_alu_producer = id_ex_rd_issue & ex_hzd_i.alu_rf_wen & ex_is_alu;
    assign hzd_status_o.issue_mul_div_producer = id_ex_rd_issue & ex_is_mul;
    assign hzd_status_o.issue_src_hzd = rs1_issue_hzd | rs2_issue_hzd;
    assign hzd_status_o.store_data_wait = store_data_wait;
    assign hzd_status_o.id_ex_rd_issue = id_ex_rd_issue;
    assign hzd_status_o.gpr_pending_clear_mask = gpr_pending_clear_mask;
    assign hzd_status_o.gpr_pending_issue_mask = gpr_pending_issue_mask;
    assign hzd_status_o.gpr_pending_for_hazard = gpr_pending_for_hazard;
    assign wb_fwd_o = wb_fwd_q;
    assign producer_rs1_fwd_o.valid = 1'b0;
    assign producer_rs1_fwd_o.addr = id_ctrl_i.rs1_addr;
    assign producer_rs1_fwd_o.data = producer_value_q[id_ctrl_i.rs1_addr];
    assign producer_rs2_fwd_o.valid = 1'b0;
    assign producer_rs2_fwd_o.addr = id_ctrl_i.rs2_addr;
    assign producer_rs2_fwd_o.data = producer_value_q[id_ctrl_i.rs2_addr];
    assign gpr_pending_o = gpr_pending_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpr_pending_q <= '0;
            producer_ready_q <= '0;
            wb_fwd_q <= '0;
            for (producer_idx = 0; producer_idx < ydrasil_pkg::REGS_NUM;
                 producer_idx = producer_idx + 1) begin
                producer_value_q[producer_idx] <= '0;
            end
        end else if (ex_hzd_i.interrupt) begin
            gpr_pending_q <= '0;
            producer_ready_q <= '0;
            wb_fwd_q <= '0;
        end else begin
            gpr_pending_q <= gpr_pending_for_hazard;
            wb_fwd_q.valid <= rf_wen_rd_i & (rf_waddr_rd_i != '0);
            wb_fwd_q.addr <= rf_waddr_rd_i;
            wb_fwd_q.data <= rf_wdata_rd_i;

            // RF writeback belongs to an older producer.  If a newer result for
            // the same rd completes in this cycle, the completion capture below
            // must win and keep that value available for forwarding.
            if (rf_wen_rd_i && (rf_waddr_rd_i != '0)) begin
                producer_ready_q[rf_waddr_rd_i] <= 1'b0;
            end
            if (alu_fwd_i.valid && (alu_fwd_i.addr != '0)) begin
                producer_ready_q[alu_fwd_i.addr] <= 1'b1;
                producer_value_q[alu_fwd_i.addr] <= alu_fwd_i.data;
            end
            if (lsu_fwd_i.valid && (lsu_fwd_i.addr != '0)) begin
                producer_ready_q[lsu_fwd_i.addr] <= 1'b1;
                producer_value_q[lsu_fwd_i.addr] <= lsu_fwd_i.data;
            end
            if (mul_fwd_i.valid && (mul_fwd_i.addr != '0)) begin
                producer_ready_q[mul_fwd_i.addr] <= 1'b1;
                producer_value_q[mul_fwd_i.addr] <= mul_fwd_i.data;
            end
        end
    end

endmodule
