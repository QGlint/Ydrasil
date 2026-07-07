`timescale 1ns/1ns

module ydrasil_core_observer
import ydrasil_pkg::*;
import ydrasil_pipeline_pkg::*;
#(
    parameter int RN_SHADOW_PHYS_REGS = 64,
    parameter int RN_SHADOW_ROB_DEPTH = 16,
    parameter int RN_SHADOW_PREG_BITS = 6,
    parameter int RN_SHADOW_ROB_PTR_BITS = 4
) (
    input wire clk,
    input wire rst_n,
    input observer_pkt_t observer_i,
    output observer_dbg_pkt_t observer_dbg_o
);

    localparam [4:0] RN_SHADOW_ROB_DEPTH_COUNT = 5'd16;
    localparam [2:0] RN_PROD_ALU = 3'd0;
    localparam [2:0] RN_PROD_P1 = 3'd1;
    localparam [2:0] RN_PROD_LSU = 3'd2;
    localparam [2:0] RN_PROD_MUL = 3'd3;
    localparam [2:0] RN_PROD_FLUSH_LOST = 3'd4;

    logic [RN_SHADOW_ROB_PTR_BITS-1:0] rn_shadow_rob_head_q;
    logic [RN_SHADOW_ROB_PTR_BITS-1:0] rn_shadow_rob_tail_q;
    logic [4:0] rn_shadow_rob_occ_q;
    logic rn_shadow_rob_valid_q [0:RN_SHADOW_ROB_DEPTH-1];
    logic rn_shadow_rob_ready_q [0:RN_SHADOW_ROB_DEPTH-1];
    logic [2:0] rn_shadow_rob_producer_q [0:RN_SHADOW_ROB_DEPTH-1];

    logic [31:0] perf_rn_alloc0;
    logic [31:0] perf_rn_alloc1;
    logic [31:0] perf_rn_commit;
    logic [31:0] perf_rn_free;
    logic [31:0] perf_rn_free_min;
    logic [31:0] perf_rn_full_stall;
    logic [31:0] perf_rn_full_stall_freelist;
    logic [31:0] perf_rn_full_stall_rob;
    logic [31:0] perf_rn_flush_restore;
    logic [31:0] perf_rn_same_cycle_raw;
    logic [31:0] perf_rn_same_cycle_waw;
    logic [31:0] perf_rn_x0_no_alloc;
    logic [31:0] perf_rn_shadow_raw_wb_can_remove;
    logic [31:0] perf_raw_wb_can_remove_alu_ready;
    logic [31:0] perf_raw_wb_can_remove_p1_ready;
    logic [31:0] perf_raw_wb_can_remove_lsu_ready;
    logic [31:0] perf_raw_wb_can_remove_mul_ready;
    logic [31:0] perf_raw_wb_false_positive;
    logic [31:0] perf_rn_shadow_waw_can_remove;
    logic [31:0] perf_rn_shadow_war_can_remove;
    logic [31:0] perf_rn_shadow_pipe1_when_p0_blocked_can_fire;
    logic [31:0] perf_rob_occ_0;
    logic [31:0] perf_rob_occ_1;
    logic [31:0] perf_rob_occ_2;
    logic [31:0] perf_rob_occ_3;
    logic [31:0] perf_rob_occ_4p;
    logic [31:0] perf_rob_full_stall;
    logic [31:0] perf_rob_commit0;
    logic [31:0] perf_rob_commit1;
    logic [31:0] perf_rob_head_not_ready;
    logic [31:0] perf_rob_head_wait_alu;
    logic [31:0] perf_rob_head_wait_lsu;
    logic [31:0] perf_rob_head_wait_mul;
    logic [31:0] perf_rob_head_wait_flush_lost;

    logic [31:0] perf_prf_rd0;
    logic [31:0] perf_prf_rd1;
    logic [31:0] perf_prf_rd2;
    logic [31:0] perf_prf_rd3;
    logic [31:0] perf_prf_wr0;
    logic [31:0] perf_prf_wr1;
    logic [31:0] perf_prf_bypass_rd0;
    logic [31:0] perf_prf_bypass_rd1;
    logic [31:0] perf_prf_bypass_rd2;
    logic [31:0] perf_prf_bypass_rd3;

    assign observer_dbg_o.bp_predict_pc = observer_i.bp_predict_pc;
    assign observer_dbg_o.bp_predict_hit = observer_i.bp_predict_hit;
    assign observer_dbg_o.bp_predict_taken = observer_i.bp_predict_taken;
    assign observer_dbg_o.bp_predict_target = observer_i.bp_predict_target;
    assign observer_dbg_o.bp_predict_counter = observer_i.bp_predict_counter;
    assign observer_dbg_o.bp_resolve_valid = observer_i.dbg_bp_resolve_valid;
    assign observer_dbg_o.bp_resolve_pc = observer_i.dbg_bp_resolve_pc;
    assign observer_dbg_o.bp_actual_taken = observer_i.dbg_bp_actual_taken;
    assign observer_dbg_o.bp_actual_target = observer_i.dbg_bp_actual_target;
    assign observer_dbg_o.bp_actual_next_pc = observer_i.dbg_bp_actual_next_pc;
    assign observer_dbg_o.bp_pred_hit = observer_i.dbg_bp_pred_hit;
    assign observer_dbg_o.bp_pred_taken = observer_i.dbg_bp_pred_taken;
    assign observer_dbg_o.bp_pred_target = observer_i.dbg_bp_pred_target;
    assign observer_dbg_o.bp_pred_counter = observer_i.dbg_bp_pred_counter;
    assign observer_dbg_o.bp_pred_l0_taken = observer_i.dbg_bp_pred_l0_taken;
    assign observer_dbg_o.bp_pred_next_pc = observer_i.dbg_bp_pred_next_pc;
    assign observer_dbg_o.bp_mispredict = observer_i.dbg_bp_mispredict;

    wire [REGS_NUM-1:0] gpr_pending_for_hazard = '0;
    wire [REGS_NUM-1:0] gpr_pending_q = '0;
    wire [REGS_NUM-1:0] gpr_pending_clear_mask =
        (observer_i.wb_hzd_valid & (observer_i.wb_hzd_addr != '0)) ?
        (REGS_NUM'(1) << observer_i.wb_hzd_addr) : '0;
    wire [REGS_NUM-1:0] gpr_pending_issue_mask =
        observer_i.id_ex_rd_issue ? (REGS_NUM'(1) << observer_i.id_rf_waddr_rd) : '0;

    logic [RN_SHADOW_PREG_BITS-1:0] rn_shadow_rat_q [0:REGS_NUM-1];
    logic [RN_SHADOW_PREG_BITS-1:0] rn_shadow_amt_q [0:REGS_NUM-1];
    logic [RN_SHADOW_PHYS_REGS-1:0] rn_shadow_free_q;
    logic [RN_SHADOW_PHYS_REGS-1:0] rn_shadow_busy_q;
    logic [2:0] rn_shadow_preg_ready_class_q [0:RN_SHADOW_PHYS_REGS-1];
    logic [6:0] rn_shadow_free_count_q;
    logic [6:0] rn_shadow_free_min_q;
    logic [REGS_ADDR_WIDTH-1:0] rn_shadow_rob_arch_rd_q [0:RN_SHADOW_ROB_DEPTH-1];
    logic [RN_SHADOW_PREG_BITS-1:0] rn_shadow_rob_new_pdst_q [0:RN_SHADOW_ROB_DEPTH-1];
    logic [RN_SHADOW_PREG_BITS-1:0] rn_shadow_rob_old_pdst_q [0:RN_SHADOW_ROB_DEPTH-1];

    wire rn_shadow_alloc1_valid =
        observer_i.rn_alloc_valid & observer_i.id_ctrl_rd_wen & (observer_i.id_ctrl_rd_addr != '0) &
        (observer_i.rn_alloc_rd_addr != '0);
    wire rn_shadow_same_cycle_raw =
        rn_shadow_alloc1_valid &
        (((observer_i.if_id_instr[19:15] != '0) && (observer_i.if_id_instr[19:15] == observer_i.id_ctrl_rd_addr)) |
         ((observer_i.if_id_instr[24:20] != '0) && (observer_i.if_id_instr[24:20] == observer_i.id_ctrl_rd_addr)));
    wire rn_shadow_same_cycle_waw =
        rn_shadow_alloc1_valid & (observer_i.rn_alloc_rd_addr == observer_i.id_ctrl_rd_addr);

    function automatic [RN_SHADOW_PREG_BITS-1:0] rn_shadow_first_free;
        input [RN_SHADOW_PHYS_REGS-1:0] free_map;
        integer k;
        begin
            rn_shadow_first_free = '0;
            for (k = RN_SHADOW_PHYS_REGS-1; k >= 1; k = k - 1) begin
                if (free_map[k]) begin
                    rn_shadow_first_free = k[RN_SHADOW_PREG_BITS-1:0];
                end
            end
        end
    endfunction

    task automatic rn_shadow_mark_ready;
        input [REGS_ADDR_WIDTH-1:0] arch_rd;
        input [2:0] producer_class;
        integer j;
        reg found;
        reg [RN_SHADOW_ROB_PTR_BITS-1:0] idx;
        begin
            found = 1'b0;
            for (j = 0; j < RN_SHADOW_ROB_DEPTH; j = j + 1) begin
                idx = rn_shadow_rob_head_q + RN_SHADOW_ROB_PTR_BITS'(j);
                if (!found && rn_shadow_rob_valid_q[idx] &&
                    !rn_shadow_rob_ready_q[idx] &&
                    (rn_shadow_rob_arch_rd_q[idx] == arch_rd)) begin
                    rn_shadow_rob_ready_q[idx] = 1'b1;
                    rn_shadow_busy_q[rn_shadow_rob_new_pdst_q[idx]] = 1'b0;
                    rn_shadow_preg_ready_class_q[rn_shadow_rob_new_pdst_q[idx]] = producer_class;
                    found = 1'b1;
                end
            end
        end
    endtask

    task automatic rn_shadow_count_head_wait;
        input [2:0] producer_class;
        begin
            perf_rob_head_not_ready = perf_rob_head_not_ready + 32'd1;
            unique case (producer_class)
                RN_PROD_ALU,
                RN_PROD_P1:
                    perf_rob_head_wait_alu = perf_rob_head_wait_alu + 32'd1;
                RN_PROD_LSU:
                    perf_rob_head_wait_lsu = perf_rob_head_wait_lsu + 32'd1;
                RN_PROD_MUL:
                    perf_rob_head_wait_mul = perf_rob_head_wait_mul + 32'd1;
                default:
                    perf_rob_head_wait_flush_lost = perf_rob_head_wait_flush_lost + 32'd1;
            endcase
        end
    endtask

    task automatic rn_shadow_count_raw_ready;
        input [RN_SHADOW_PREG_BITS-1:0] psrc;
        begin
            perf_rn_shadow_raw_wb_can_remove = perf_rn_shadow_raw_wb_can_remove + 32'd1;
            unique case (rn_shadow_preg_ready_class_q[psrc])
                RN_PROD_ALU:
                    perf_raw_wb_can_remove_alu_ready = perf_raw_wb_can_remove_alu_ready + 32'd1;
                RN_PROD_P1:
                    perf_raw_wb_can_remove_p1_ready = perf_raw_wb_can_remove_p1_ready + 32'd1;
                RN_PROD_LSU:
                    perf_raw_wb_can_remove_lsu_ready = perf_raw_wb_can_remove_lsu_ready + 32'd1;
                RN_PROD_MUL:
                    perf_raw_wb_can_remove_mul_ready = perf_raw_wb_can_remove_mul_ready + 32'd1;
                default:
                    perf_raw_wb_false_positive = perf_raw_wb_false_positive + 32'd1;
            endcase
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        integer rn_i;
        reg [RN_SHADOW_PREG_BITS-1:0] new_pdst;
        reg [RN_SHADOW_PREG_BITS-1:0] old_pdst;
        reg [6:0] rebuilt_free_count;
        if (!rst_n) begin
            rn_shadow_free_q = '0;
            rn_shadow_busy_q = '0;
            rn_shadow_free_count_q = 7'd32;
            rn_shadow_free_min_q = 7'd32;
            rn_shadow_rob_head_q = '0;
            rn_shadow_rob_tail_q = '0;
            rn_shadow_rob_occ_q = '0;
            for (rn_i = 0; rn_i < REGS_NUM; rn_i = rn_i + 1) begin
                rn_shadow_rat_q[rn_i] = rn_i[RN_SHADOW_PREG_BITS-1:0];
                rn_shadow_amt_q[rn_i] = rn_i[RN_SHADOW_PREG_BITS-1:0];
            end
            for (rn_i = 0; rn_i < RN_SHADOW_PHYS_REGS; rn_i = rn_i + 1) begin
                rn_shadow_free_q[rn_i] = (rn_i >= REGS_NUM);
                rn_shadow_preg_ready_class_q[rn_i] = RN_PROD_ALU;
            end
            for (rn_i = 0; rn_i < RN_SHADOW_ROB_DEPTH; rn_i = rn_i + 1) begin
                rn_shadow_rob_valid_q[rn_i] = 1'b0;
                rn_shadow_rob_ready_q[rn_i] = 1'b0;
                rn_shadow_rob_arch_rd_q[rn_i] = '0;
                rn_shadow_rob_new_pdst_q[rn_i] = '0;
                rn_shadow_rob_old_pdst_q[rn_i] = '0;
                rn_shadow_rob_producer_q[rn_i] = RN_PROD_FLUSH_LOST;
            end
            perf_rn_alloc0 = '0;
            perf_rn_alloc1 = '0;
            perf_rn_commit = '0;
            perf_rn_free = '0;
            perf_rn_free_min = 32'd32;
            perf_rn_full_stall = '0;
            perf_rn_full_stall_freelist = '0;
            perf_rn_full_stall_rob = '0;
            perf_rn_flush_restore = '0;
            perf_rn_same_cycle_raw = '0;
            perf_rn_same_cycle_waw = '0;
            perf_rn_x0_no_alloc = '0;
            perf_rn_shadow_raw_wb_can_remove = '0;
            perf_raw_wb_can_remove_alu_ready = '0;
            perf_raw_wb_can_remove_p1_ready = '0;
            perf_raw_wb_can_remove_lsu_ready = '0;
            perf_raw_wb_can_remove_mul_ready = '0;
            perf_raw_wb_false_positive = '0;
            perf_rn_shadow_waw_can_remove = '0;
            perf_rn_shadow_war_can_remove = '0;
            perf_rn_shadow_pipe1_when_p0_blocked_can_fire = '0;
            perf_rob_occ_0 = '0;
            perf_rob_occ_1 = '0;
            perf_rob_occ_2 = '0;
            perf_rob_occ_3 = '0;
            perf_rob_occ_4p = '0;
            perf_rob_full_stall = '0;
            perf_rob_commit0 = '0;
            perf_rob_commit1 = '0;
            perf_rob_head_not_ready = '0;
            perf_rob_head_wait_alu = '0;
            perf_rob_head_wait_lsu = '0;
            perf_rob_head_wait_mul = '0;
            perf_rob_head_wait_flush_lost = '0;
        end else begin
            if (observer_i.flush_id | observer_i.flush_ex | observer_i.interrupt) begin
                rn_shadow_free_q = '1;
                rn_shadow_free_q[0] = 1'b0;
                rn_shadow_busy_q = '0;
                rebuilt_free_count = RN_SHADOW_PHYS_REGS - 1;
                for (rn_i = 0; rn_i < REGS_NUM; rn_i = rn_i + 1) begin
                    rn_shadow_rat_q[rn_i] = rn_shadow_amt_q[rn_i];
                    if (rn_shadow_amt_q[rn_i] != '0 && rn_shadow_free_q[rn_shadow_amt_q[rn_i]]) begin
                        rn_shadow_free_q[rn_shadow_amt_q[rn_i]] = 1'b0;
                        rebuilt_free_count = rebuilt_free_count - 7'd1;
                    end
                end
                for (rn_i = 0; rn_i < RN_SHADOW_PHYS_REGS; rn_i = rn_i + 1) begin
                    rn_shadow_preg_ready_class_q[rn_i] = RN_PROD_FLUSH_LOST;
                end
                rn_shadow_free_count_q = rebuilt_free_count;
                rn_shadow_rob_head_q = '0;
                rn_shadow_rob_tail_q = '0;
                rn_shadow_rob_occ_q = '0;
                for (rn_i = 0; rn_i < RN_SHADOW_ROB_DEPTH; rn_i = rn_i + 1) begin
                    rn_shadow_rob_valid_q[rn_i] = 1'b0;
                    rn_shadow_rob_ready_q[rn_i] = 1'b0;
                    rn_shadow_rob_producer_q[rn_i] = RN_PROD_FLUSH_LOST;
                end
                perf_rn_flush_restore = perf_rn_flush_restore + 32'd1;
            end else begin
                if (observer_i.alu_rf_wen_rd && (observer_i.alu_rf_waddr_rd != '0)) begin
                    rn_shadow_mark_ready(observer_i.alu_rf_waddr_rd, RN_PROD_ALU);
                end
                if (observer_i.lsu_rf_wen_rd && (observer_i.lsu_rf_waddr_rd != '0)) begin
                    rn_shadow_mark_ready(observer_i.lsu_rf_waddr_rd, RN_PROD_LSU);
                end
                if (observer_i.wb_mul_complete && (observer_i.wb_mul_complete_waddr != '0)) begin
                    rn_shadow_mark_ready(observer_i.wb_mul_complete_waddr, RN_PROD_MUL);
                end
                if (observer_i.pipe1_alu_rf_wen_rd_to_wb && (observer_i.pipe1_alu_rf_waddr_rd_to_wb != '0)) begin
                    rn_shadow_mark_ready(observer_i.pipe1_alu_rf_waddr_rd_to_wb, RN_PROD_P1);
                end

                if ((rn_shadow_rob_occ_q != '0) &&
                    rn_shadow_rob_valid_q[rn_shadow_rob_head_q] &&
                    rn_shadow_rob_ready_q[rn_shadow_rob_head_q]) begin
                    rn_shadow_amt_q[rn_shadow_rob_arch_rd_q[rn_shadow_rob_head_q]] =
                        rn_shadow_rob_new_pdst_q[rn_shadow_rob_head_q];
                    if (rn_shadow_rob_old_pdst_q[rn_shadow_rob_head_q] != '0) begin
                        rn_shadow_free_q[rn_shadow_rob_old_pdst_q[rn_shadow_rob_head_q]] = 1'b1;
                        rn_shadow_free_count_q = rn_shadow_free_count_q + 7'd1;
                        perf_rn_free = perf_rn_free + 32'd1;
                    end
                    rn_shadow_rob_valid_q[rn_shadow_rob_head_q] = 1'b0;
                    rn_shadow_rob_ready_q[rn_shadow_rob_head_q] = 1'b0;
                    rn_shadow_rob_head_q = rn_shadow_rob_head_q + RN_SHADOW_ROB_PTR_BITS'(1);
                    rn_shadow_rob_occ_q = rn_shadow_rob_occ_q - 5'd1;
                    perf_rn_commit = perf_rn_commit + 32'd1;
                    perf_rob_commit1 = perf_rob_commit1 + 32'd1;
                end else begin
                    perf_rob_commit0 = perf_rob_commit0 + 32'd1;
                    if (rn_shadow_rob_occ_q != '0) begin
                        if (rn_shadow_rob_valid_q[rn_shadow_rob_head_q]) begin
                            rn_shadow_count_head_wait(rn_shadow_rob_producer_q[rn_shadow_rob_head_q]);
                        end else begin
                            rn_shadow_count_head_wait(RN_PROD_FLUSH_LOST);
                        end
                    end
                end

                if (observer_i.id_ex_rd_issue &&
                    ((rn_shadow_free_count_q == 7'd0) ||
                     (rn_shadow_rob_occ_q == RN_SHADOW_ROB_DEPTH_COUNT))) begin
                    perf_rn_full_stall = perf_rn_full_stall + 32'd1;
                    if (rn_shadow_free_count_q == 7'd0) begin
                        perf_rn_full_stall_freelist = perf_rn_full_stall_freelist + 32'd1;
                    end else begin
                        perf_rn_full_stall_rob = perf_rn_full_stall_rob + 32'd1;
                    end
                    perf_rob_full_stall = perf_rob_full_stall + 32'd1;
                end else if (observer_i.id_ex_rd_issue) begin
                    new_pdst = rn_shadow_first_free(rn_shadow_free_q);
                    old_pdst = rn_shadow_rat_q[observer_i.id_rf_waddr_rd];
                    rn_shadow_free_q[new_pdst] = 1'b0;
                    rn_shadow_busy_q[new_pdst] = 1'b1;
                    rn_shadow_rat_q[observer_i.id_rf_waddr_rd] = new_pdst;
                    rn_shadow_free_count_q = rn_shadow_free_count_q - 7'd1;
                    rn_shadow_rob_valid_q[rn_shadow_rob_tail_q] = 1'b1;
                    rn_shadow_rob_ready_q[rn_shadow_rob_tail_q] = 1'b0;
                    rn_shadow_rob_arch_rd_q[rn_shadow_rob_tail_q] = observer_i.id_rf_waddr_rd;
                    rn_shadow_rob_new_pdst_q[rn_shadow_rob_tail_q] = new_pdst;
                    rn_shadow_rob_old_pdst_q[rn_shadow_rob_tail_q] = old_pdst;
                    rn_shadow_rob_producer_q[rn_shadow_rob_tail_q] =
                        observer_i.operator_type[OPERATOR_TYPE_LOAD] ? RN_PROD_LSU :
                        (observer_i.operator_type[OPERATOR_TYPE_MUL] ? RN_PROD_MUL : RN_PROD_ALU);
                    rn_shadow_rob_tail_q = rn_shadow_rob_tail_q + RN_SHADOW_ROB_PTR_BITS'(1);
                    rn_shadow_rob_occ_q = rn_shadow_rob_occ_q + 5'd1;
                    perf_rn_alloc0 = perf_rn_alloc0 + 32'd1;
                end

                if (observer_i.pipe1_rd_issue &&
                    ((rn_shadow_free_count_q == 7'd0) ||
                     (rn_shadow_rob_occ_q == RN_SHADOW_ROB_DEPTH_COUNT))) begin
                    perf_rn_full_stall = perf_rn_full_stall + 32'd1;
                    if (rn_shadow_free_count_q == 7'd0) begin
                        perf_rn_full_stall_freelist = perf_rn_full_stall_freelist + 32'd1;
                    end else begin
                        perf_rn_full_stall_rob = perf_rn_full_stall_rob + 32'd1;
                    end
                    perf_rob_full_stall = perf_rob_full_stall + 32'd1;
                end else if (observer_i.pipe1_rd_issue) begin
                    new_pdst = rn_shadow_first_free(rn_shadow_free_q);
                    old_pdst = rn_shadow_rat_q[observer_i.pipe1_rf_waddr_rd_issue];
                    rn_shadow_free_q[new_pdst] = 1'b0;
                    rn_shadow_busy_q[new_pdst] = 1'b1;
                    rn_shadow_rat_q[observer_i.pipe1_rf_waddr_rd_issue] = new_pdst;
                    rn_shadow_free_count_q = rn_shadow_free_count_q - 7'd1;
                    rn_shadow_rob_valid_q[rn_shadow_rob_tail_q] = 1'b1;
                    rn_shadow_rob_ready_q[rn_shadow_rob_tail_q] = 1'b0;
                    rn_shadow_rob_arch_rd_q[rn_shadow_rob_tail_q] = observer_i.pipe1_rf_waddr_rd_issue;
                    rn_shadow_rob_new_pdst_q[rn_shadow_rob_tail_q] = new_pdst;
                    rn_shadow_rob_old_pdst_q[rn_shadow_rob_tail_q] = old_pdst;
                    rn_shadow_rob_producer_q[rn_shadow_rob_tail_q] = RN_PROD_P1;
                    rn_shadow_rob_tail_q = rn_shadow_rob_tail_q + RN_SHADOW_ROB_PTR_BITS'(1);
                    rn_shadow_rob_occ_q = rn_shadow_rob_occ_q + 5'd1;
                    perf_rn_alloc1 = perf_rn_alloc1 + 32'd1;
                end
                if (rn_shadow_alloc1_valid) begin
                    perf_rn_alloc1 = perf_rn_alloc1 + 32'd1;
                end

                if (observer_i.id_ex_valid && observer_i.id_alu_rf_wen_rd && (observer_i.id_rf_waddr_rd == '0)) begin
                    perf_rn_x0_no_alloc = perf_rn_x0_no_alloc + 32'd1;
                end
                if (observer_i.pipe1_issue_valid_to_ex && observer_i.pipe1_rf_wen_rd_to_ex &&
                    (observer_i.pipe1_rf_waddr_rd_to_ex == '0)) begin
                    perf_rn_x0_no_alloc = perf_rn_x0_no_alloc + 32'd1;
                end
                if (observer_i.id_ex_rd_issue && observer_i.pipe1_issue_valid_to_ex &&
                    (((observer_i.pipe1_rf_raddr_rs1 != '0) && (observer_i.pipe1_rf_raddr_rs1 == observer_i.id_rf_waddr_rd)) ||
                     ((observer_i.pipe1_rf_raddr_rs2 != '0) && (observer_i.pipe1_rf_raddr_rs2 == observer_i.id_rf_waddr_rd)))) begin
                    perf_rn_same_cycle_raw = perf_rn_same_cycle_raw + 32'd1;
                end
                if (rn_shadow_same_cycle_raw) begin
                    perf_rn_same_cycle_raw = perf_rn_same_cycle_raw + 32'd1;
                end
                if (observer_i.id_ex_rd_issue && observer_i.pipe1_rd_issue &&
                    (observer_i.pipe1_rf_waddr_rd_issue == observer_i.id_rf_waddr_rd)) begin
                    perf_rn_same_cycle_waw = perf_rn_same_cycle_waw + 32'd1;
                end
                if (rn_shadow_same_cycle_waw) begin
                    perf_rn_same_cycle_waw = perf_rn_same_cycle_waw + 32'd1;
                end
                if (observer_i.rs1_pending_stall &&
                    !rn_shadow_busy_q[rn_shadow_rat_q[observer_i.id_ctrl_rs1_addr]]) begin
                    rn_shadow_count_raw_ready(rn_shadow_rat_q[observer_i.id_ctrl_rs1_addr]);
                end else if (observer_i.rs2_pending_stall &&
                    !rn_shadow_busy_q[rn_shadow_rat_q[observer_i.id_ctrl_rs2_addr]]) begin
                    rn_shadow_count_raw_ready(rn_shadow_rat_q[observer_i.id_ctrl_rs2_addr]);
                end
                if (observer_i.rd_waw_stall && (rn_shadow_free_count_q != '0) &&
                    (rn_shadow_rob_occ_q != RN_SHADOW_ROB_DEPTH_COUNT)) begin
                    perf_rn_shadow_waw_can_remove = perf_rn_shadow_waw_can_remove + 32'd1;
                end
                if (observer_i.pipe1_issue_valid_to_ex && observer_i.id_ex_valid &&
                    observer_i.pipe1_rf_wen_rd_to_ex && (observer_i.pipe1_rf_waddr_rd_to_ex != '0) &&
                    (((observer_i.id_ctrl_rs1_ren && (observer_i.id_ctrl_rs1_addr == observer_i.pipe1_rf_waddr_rd_to_ex))) ||
                     ((observer_i.id_ctrl_rs2_ren && (observer_i.id_ctrl_rs2_addr == observer_i.pipe1_rf_waddr_rd_to_ex))))) begin
                    perf_rn_shadow_war_can_remove = perf_rn_shadow_war_can_remove + 32'd1;
                end
                if ((rn_shadow_free_min_q == '0) ||
                    (rn_shadow_free_count_q < rn_shadow_free_min_q)) begin
                    rn_shadow_free_min_q = rn_shadow_free_count_q;
                end
                perf_rn_free_min = {25'd0, rn_shadow_free_min_q};
                case (rn_shadow_rob_occ_q)
                    5'd0: perf_rob_occ_0 = perf_rob_occ_0 + 32'd1;
                    5'd1: perf_rob_occ_1 = perf_rob_occ_1 + 32'd1;
                    5'd2: perf_rob_occ_2 = perf_rob_occ_2 + 32'd1;
                    5'd3: perf_rob_occ_3 = perf_rob_occ_3 + 32'd1;
                    default: perf_rob_occ_4p = perf_rob_occ_4p + 32'd1;
                endcase
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perf_prf_rd0 <= '0;
            perf_prf_rd1 <= '0;
            perf_prf_rd2 <= '0;
            perf_prf_rd3 <= '0;
            perf_prf_wr0 <= '0;
            perf_prf_wr1 <= '0;
            perf_prf_bypass_rd0 <= '0;
            perf_prf_bypass_rd1 <= '0;
            perf_prf_bypass_rd2 <= '0;
            perf_prf_bypass_rd3 <= '0;
        end else begin
            perf_prf_rd0 <= perf_prf_rd0 + (observer_i.prf_rd0_en ? 32'd1 : 32'd0);
            perf_prf_rd1 <= perf_prf_rd1 + (observer_i.prf_rd1_en ? 32'd1 : 32'd0);
            perf_prf_rd2 <= perf_prf_rd2 + (observer_i.prf_rd2_en ? 32'd1 : 32'd0);
            perf_prf_rd3 <= perf_prf_rd3 + (observer_i.prf_rd3_en ? 32'd1 : 32'd0);
            perf_prf_wr0 <= perf_prf_wr0 + (observer_i.prf_wr0_en ? 32'd1 : 32'd0);
            perf_prf_wr1 <= perf_prf_wr1 + (observer_i.prf_wr1_en ? 32'd1 : 32'd0);
            perf_prf_bypass_rd0 <= perf_prf_bypass_rd0 +
                ((observer_i.prf_rd0_en && ((observer_i.prf_wr0_en && (observer_i.prf_wr0_addr == observer_i.prf_rd0_addr)) ||
                                  (observer_i.prf_wr1_en && (observer_i.prf_wr1_addr == observer_i.prf_rd0_addr)))) ? 32'd1 : 32'd0);
            perf_prf_bypass_rd1 <= perf_prf_bypass_rd1 +
                ((observer_i.prf_rd1_en && ((observer_i.prf_wr0_en && (observer_i.prf_wr0_addr == observer_i.prf_rd1_addr)) ||
                                  (observer_i.prf_wr1_en && (observer_i.prf_wr1_addr == observer_i.prf_rd1_addr)))) ? 32'd1 : 32'd0);
            perf_prf_bypass_rd2 <= perf_prf_bypass_rd2 +
                ((observer_i.prf_rd2_en && ((observer_i.prf_wr0_en && (observer_i.prf_wr0_addr == observer_i.prf_rd2_addr)) ||
                                  (observer_i.prf_wr1_en && (observer_i.prf_wr1_addr == observer_i.prf_rd2_addr)))) ? 32'd1 : 32'd0);
            perf_prf_bypass_rd3 <= perf_prf_bypass_rd3 +
                ((observer_i.prf_rd3_en && ((observer_i.prf_wr0_en && (observer_i.prf_wr0_addr == observer_i.prf_rd3_addr)) ||
                                  (observer_i.prf_wr1_en && (observer_i.prf_wr1_addr == observer_i.prf_rd3_addr)))) ? 32'd1 : 32'd0);
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n) begin
`ifdef YDRASIL_RN_DEBUG_DISPLAY
            if ((observer_i.alu_rf_wen_rd && (observer_i.alu_rf_waddr_rd == 5'd22)) ||
                (observer_i.wb_rf_wen_rd && (observer_i.wb_rf_waddr_rd == 5'd22)) ||
                (observer_i.rf_wen_rd && (observer_i.rf_waddr_rd == 5'd22))) begin
                $display("[X22_WB_DBG] alu_wen=%0b alu_data=0x%08h alu_pdst=%0d wb_wen=%0b wb_data=0x%08h rf_wen=%0b rf_data=0x%08h pipe1_commit=%0b prf_wr0=%0b/%0d/0x%08h prf_wr1=%0b/%0d/0x%08h",
                         observer_i.alu_rf_wen_rd,
                         observer_i.alu_result,
                         observer_i.alu_rn_pdst,
                         observer_i.wb_rf_wen_rd,
                         observer_i.wb_rf_wdata_rd,
                         observer_i.rf_wen_rd,
                         observer_i.rf_wdata_rd,
                         observer_i.pipe1_commit_rf_wen,
                         observer_i.prf_wr0_en,
                         observer_i.prf_wr0_addr,
                         observer_i.prf_wr0_data,
                         observer_i.prf_wr1_en,
                         observer_i.prf_wr1_addr,
                         observer_i.prf_wr1_data);
            end
`endif
            if (({2'b00, observer_i.rn_real_wb_pdst_found} +
                 {2'b00, observer_i.rn_real_lsu_pdst_found} +
                 {2'b00, observer_i.rn_real_mul_pdst_found} +
                 {2'b00, observer_i.rn_real_pipe1_pdst_found}) > 3'd2) begin
                $fatal(1, "[PRF_WR_CONFLICT] alu=%0b/%0d lsu=%0b/%0d mul=%0b/%0d p1=%0b/%0d",
                         observer_i.rn_real_wb_pdst_found, observer_i.rn_real_wb_pdst,
                         observer_i.rn_real_lsu_pdst_found, observer_i.rn_real_lsu_pdst,
                         observer_i.rn_real_mul_pdst_found, observer_i.rn_real_mul_pdst,
                         observer_i.rn_real_pipe1_pdst_found, observer_i.rn_real_pipe1_pdst);
            end
        end
    end

    ydrasil_commit_trace u_ydrasil_commit_trace (
        .clk(clk),
        .rst_n(rst_n),
        .flush_i(observer_i.flush_id | observer_i.flush_ex | observer_i.interrupt),
        .alloc_valid_i(observer_i.commit_trace_alloc_valid),
        .alloc_pc_i(observer_i.commit_trace_alloc_pc),
        .alloc_instr_i(observer_i.commit_trace_alloc_instr),
        .alloc1_valid_i(observer_i.commit_trace_alloc1_valid),
        .alloc1_pc_i(observer_i.commit_trace_alloc1_pc),
        .alloc1_instr_i(observer_i.commit_trace_alloc1_instr),
        .pipe0_issue_valid_i(observer_i.id_ex_valid & !observer_i.interrupt & !observer_i.flush_ex),
        .pipe0_issue_pc_i(observer_i.id_instr_addr),
        .pipe0_issue_load_i(observer_i.operator_type[OPERATOR_TYPE_LOAD]),
        .pipe0_issue_waddr_i(observer_i.id_rf_waddr_rd),
        .alu_wb_valid_i(observer_i.alu_rf_wen_rd),
        .alu_wb_waddr_i(observer_i.alu_rf_waddr_rd),
        .alu_wb_wdata_i(observer_i.alu_result),
        .lsu_wb_valid_i(observer_i.lsu_rf_wen_rd),
        .lsu_wb_waddr_i(observer_i.lsu_rf_waddr_rd),
        .lsu_wb_wdata_i(observer_i.lsu_wb_result),
        .mul_issue_valid_i(observer_i.ex_mul_issue),
        .mul_issue_pc_i(observer_i.id_instr_addr),
        .mul_wb_valid_i(observer_i.wb_mul_complete),
        .mul_wb_waddr_i(observer_i.wb_mul_complete_waddr),
        .mul_wb_wdata_i(observer_i.wb_rf_wdata_rd),
        .pipe1_issue_valid_i(observer_i.pipe1_issue_valid_to_ex & observer_i.pipe1_rf_wen_rd_to_ex &
                             (observer_i.pipe1_rf_waddr_rd_to_ex != '0) & !observer_i.interrupt & !observer_i.flush_ex),
        .pipe1_issue_pc_i(observer_i.pipe1_pc),
        .pipe1_wb_valid_i(observer_i.pipe1_alu_rf_wen_rd_to_wb),
        .pipe1_wb_waddr_i(observer_i.pipe1_alu_rf_waddr_rd_to_wb),
        .pipe1_wb_wdata_i(observer_i.pipe1_alu_result_to_wb)
    );

endmodule
