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
    input  wire                         rf_producer_id_i,
    input  wire                         rf_producer_tracked_i,

    output ydrasil_hzd_status_pkt_t     hzd_status_o,
    output ydrasil_gpr_fwd_pkt_t        wb_fwd_o,
    output ydrasil_gpr_fwd_pkt_t        producer_rs1_fwd_o,
    output ydrasil_gpr_fwd_pkt_t        producer_rs2_fwd_o,
    output wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_o,
    output wire                         ex_accept_valid_o,
    output wire                         producer_alloc_id_o,
    output wire                         producer_alloc_tracked_o,

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
    reg [1:0] producer_valid_q;
    reg [1:0] producer_ready_q;
    reg [1:0] producer_retire_q;
    reg producer_latest_q;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] producer_rd_q [0:1];
    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] producer_value_q [0:1];
    ydrasil_gpr_fwd_pkt_t wb_fwd_q;

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
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_SLL]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_SRL]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_SRA]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_LUI]  |
         ex_hzd_i.operator_info[ydrasil_pkg::OP_ALU_AUIPC]);

    wire prev_alu_bypass_rs1 =
        id_ex_prev_alu_bypassable & id_ctrl_i.prev_alu_bypass_ok &
        id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr);
    wire prev_alu_bypass_rs2 =
        id_ex_prev_alu_bypassable & id_ctrl_i.prev_alu_bypass_ok &
        id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr);

    wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_clear_mask =
        (wb_fwd_q.valid ? (ydrasil_pkg::REGS_NUM'(1) << wb_fwd_q.addr) : '0) |
        ((alu_fwd_i.valid && (alu_fwd_i.addr != '0)) ?
         (ydrasil_pkg::REGS_NUM'(1) << alu_fwd_i.addr) : '0) |
        ((mul_fwd_i.valid && (mul_fwd_i.addr != '0)) ?
         (ydrasil_pkg::REGS_NUM'(1) << mul_fwd_i.addr) : '0);
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
    wire ordered_short_alu_waw = id_ex_prev_alu_bypassable &
        id_ctrl_i.short_alu_writer & !wb_backpressure_i &
        ex_hzd_i.producer_tracked;
    wire rd_issue_hzd =
        id_ex_rd_issue & id_ctrl_i.rd_wen & (id_ctrl_i.rd_addr == ex_hzd_i.rd_addr) &
        !ordered_short_alu_waw;
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
    wire [1:0] producer_occupied = producer_valid_q & ~producer_retire_q;
    wire producer_alloc_ex = id_ex_rd_issue & ex_hzd_i.producer_tracked;
    wire [1:0] producer_occupied_after_ex = producer_occupied |
        (producer_alloc_ex ? (ex_hzd_i.producer_id ? 2'b10 : 2'b01) : 2'b00);
    wire producer_rd_matches_slot =
        (producer_occupied_after_ex[0] && (id_ctrl_i.rd_addr == producer_rd_q[0])) |
        (producer_occupied_after_ex[1] && (id_ctrl_i.rd_addr == producer_rd_q[1]));
    wire untracked_load_ok = id_ctrl_i.lsu_req & !producer_rd_matches_slot;
    wire producer_full_stall = (&producer_occupied_after_ex) & id_ctrl_i.rd_wen &
        !untracked_load_ok;
    wire decode_bubble_stall =
        scoreboard_stall | lsu_struct_stall | producer_full_stall |
        clint_stall_i | wb_backpressure_i;

    assign ex_accept_valid_o = ex_hzd_i.valid & !ex_branch_jump_i;
    assign producer_alloc_id_o = !producer_occupied_after_ex[0] ? 1'b0 : 1'b1;
    assign producer_alloc_tracked_o = id_ctrl_i.rd_wen &
        !((&producer_occupied_after_ex) & untracked_load_ok);
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
    wire producer_rs1_slot0 = producer_valid_q[0] & producer_ready_q[0] &
        id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr == producer_rd_q[0]);
    wire producer_rs1_slot1 = producer_valid_q[1] & producer_ready_q[1] &
        id_ctrl_i.rs1_ren & (id_ctrl_i.rs1_addr == producer_rd_q[1]);
    wire producer_rs2_slot0 = producer_valid_q[0] & producer_ready_q[0] &
        id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr == producer_rd_q[0]);
    wire producer_rs2_slot1 = producer_valid_q[1] & producer_ready_q[1] &
        id_ctrl_i.rs2_ren & (id_ctrl_i.rs2_addr == producer_rd_q[1]);
    assign producer_rs1_fwd_o.valid = producer_rs1_slot0 | producer_rs1_slot1;
    assign producer_rs1_fwd_o.producer_id = producer_rs1_slot1;
    assign producer_rs1_fwd_o.producer_tracked = 1'b1;
    assign producer_rs1_fwd_o.addr = id_ctrl_i.rs1_addr;
    assign producer_rs1_fwd_o.data =
        (producer_rs1_slot1 && (!producer_rs1_slot0 || producer_latest_q)) ?
        producer_value_q[1] : producer_value_q[0];
    assign producer_rs2_fwd_o.valid = producer_rs2_slot0 | producer_rs2_slot1;
    assign producer_rs2_fwd_o.producer_id = producer_rs2_slot1;
    assign producer_rs2_fwd_o.producer_tracked = 1'b1;
    assign producer_rs2_fwd_o.addr = id_ctrl_i.rs2_addr;
    assign producer_rs2_fwd_o.data =
        (producer_rs2_slot1 && (!producer_rs2_slot0 || producer_latest_q)) ?
        producer_value_q[1] : producer_value_q[0];
    assign gpr_pending_o = gpr_pending_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpr_pending_q <= '0;
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            producer_retire_q <= '0;
            producer_latest_q <= 1'b0;
            wb_fwd_q <= '0;
            producer_rd_q[0] <= '0;
            producer_rd_q[1] <= '0;
            producer_value_q[0] <= '0;
            producer_value_q[1] <= '0;
        end else if (ex_hzd_i.interrupt) begin
            gpr_pending_q <= '0;
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            producer_retire_q <= '0;
            producer_latest_q <= 1'b0;
            wb_fwd_q <= '0;
        end else begin
            gpr_pending_q <= gpr_pending_for_hazard;
            wb_fwd_q.valid <= rf_wen_rd_i & (rf_waddr_rd_i != '0);
            wb_fwd_q.producer_id <= rf_producer_id_i;
            wb_fwd_q.producer_tracked <= rf_producer_tracked_i;
            wb_fwd_q.addr <= rf_waddr_rd_i;
            wb_fwd_q.data <= rf_wdata_rd_i;

            if (producer_retire_q[0]) begin
                producer_valid_q[0] <= 1'b0;
                producer_ready_q[0] <= 1'b0;
                producer_retire_q[0] <= 1'b0;
            end
            if (producer_retire_q[1]) begin
                producer_valid_q[1] <= 1'b0;
                producer_ready_q[1] <= 1'b0;
                producer_retire_q[1] <= 1'b0;
            end

            if (rf_wen_rd_i && rf_producer_tracked_i && producer_valid_q[0] && producer_ready_q[0] &&
                !rf_producer_id_i)
                producer_retire_q[0] <= 1'b1;
            if (rf_wen_rd_i && rf_producer_tracked_i && producer_valid_q[1] && producer_ready_q[1] &&
                rf_producer_id_i)
                producer_retire_q[1] <= 1'b1;

            if (producer_valid_q[0] && !producer_ready_q[0]) begin
                if (alu_fwd_i.valid && !alu_fwd_i.producer_id) begin
                    producer_ready_q[0] <= 1'b1;
                    producer_value_q[0] <= alu_fwd_i.data;
                    producer_retire_q[0] <= rf_wen_rd_i &&
                        (rf_waddr_rd_i == producer_rd_q[0]);
                end else if (lsu_fwd_i.valid && lsu_fwd_i.producer_tracked &&
                             !lsu_fwd_i.producer_id) begin
                    producer_ready_q[0] <= 1'b1;
                    producer_value_q[0] <= lsu_fwd_i.data;
                    producer_retire_q[0] <= rf_wen_rd_i && rf_producer_tracked_i &&
                        !rf_producer_id_i;
                end else if (mul_fwd_i.valid && !mul_fwd_i.producer_id) begin
                    producer_ready_q[0] <= 1'b1;
                    producer_value_q[0] <= mul_fwd_i.data;
                    producer_retire_q[0] <= rf_wen_rd_i &&
                        (rf_waddr_rd_i == producer_rd_q[0]);
                end
            end
            if (producer_valid_q[1] && !producer_ready_q[1]) begin
                if (alu_fwd_i.valid && alu_fwd_i.producer_id) begin
                    producer_ready_q[1] <= 1'b1;
                    producer_value_q[1] <= alu_fwd_i.data;
                    producer_retire_q[1] <= rf_wen_rd_i &&
                        (rf_waddr_rd_i == producer_rd_q[1]);
                end else if (lsu_fwd_i.valid && lsu_fwd_i.producer_tracked &&
                             lsu_fwd_i.producer_id) begin
                    producer_ready_q[1] <= 1'b1;
                    producer_value_q[1] <= lsu_fwd_i.data;
                    producer_retire_q[1] <= rf_wen_rd_i && rf_producer_tracked_i &&
                        rf_producer_id_i;
                end else if (mul_fwd_i.valid && mul_fwd_i.producer_id) begin
                    producer_ready_q[1] <= 1'b1;
                    producer_value_q[1] <= mul_fwd_i.data;
                    producer_retire_q[1] <= rf_wen_rd_i &&
                        (rf_waddr_rd_i == producer_rd_q[1]);
                end
            end

            if (producer_alloc_ex) begin
                if (!ex_hzd_i.producer_id) begin
                    producer_latest_q <= 1'b0;
                    producer_valid_q[0] <= 1'b1;
                    producer_ready_q[0] <= alu_fwd_i.valid && !alu_fwd_i.producer_id;
                    producer_retire_q[0] <= 1'b0;
                    producer_rd_q[0] <= ex_hzd_i.rd_addr;
                    producer_value_q[0] <= alu_fwd_i.data;
                    if (alu_fwd_i.valid && (alu_fwd_i.addr == ex_hzd_i.rd_addr) &&
                        rf_wen_rd_i && (rf_waddr_rd_i == ex_hzd_i.rd_addr))
                        producer_retire_q[0] <= 1'b1;
                end else begin
                    producer_latest_q <= 1'b1;
                    producer_valid_q[1] <= 1'b1;
                    producer_ready_q[1] <= alu_fwd_i.valid && alu_fwd_i.producer_id;
                    producer_retire_q[1] <= 1'b0;
                    producer_rd_q[1] <= ex_hzd_i.rd_addr;
                    producer_value_q[1] <= alu_fwd_i.data;
                    if (alu_fwd_i.valid && (alu_fwd_i.addr == ex_hzd_i.rd_addr) &&
                        rf_wen_rd_i && (rf_waddr_rd_i == ex_hzd_i.rd_addr))
                        producer_retire_q[1] <= 1'b1;
                end
            end
        end
    end

endmodule
