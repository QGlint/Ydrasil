module ydrasil_execute_stage
import ydrasil_pkg::*;
(
    input  wire clk,
    input  wire rst_n,
    input  wire flush_i,
    input  wire trap_redirect_i,
    input  wire [INST_ADDR_WIDTH-1:0] trap_redirect_addr_i,
    input  wire [PRODUCER_NUM-1:0] branch_recovery_keep_mask_i,
    input  wire ex_accept_valid1_i,

    input  wire alu_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0] alu_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0] alu_operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0] alu_operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] alu_operator_type_i,
    input  wire alu_rd_wen_i,
    input  wire [REGS_ADDR_WIDTH-1:0] alu_rd_addr_i,
    input  producer_id_t alu_producer_id_i,
    input  wire [INST_ADDR_WIDTH-1:0] lane_a_pc_i,
    input  wire illegal_instr_i,

    input  wire agu_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0] agu_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0] agu_operand_b_i,
    input  ydrasil_lsu_req_pkt_t agu_req_i,
    input  wire [REGS_DATA_WIDTH-1:0] agu_store_data_i,

    input  wire csr_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0] csr_operand_a_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] csr_operator_type_i,
    input  wire [CSR_ADDR_WIDTH-1:0] csr_waddr_i,
    input  wire [OP_CSR_INFO_WIDTH-1:0] csr_op_info_i,
    input  wire [REGS_DATA_WIDTH-1:0] csr_rdata_i,

    input  wire mul_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0] mul_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0] mul_operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0] mul_operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] mul_operator_type_i,

    input  ydrasil_lane_b_meta_t dual_meta_i,
    input  wire dual_alu_valid_i,
    input  ydrasil_lane_b_alu_payload_t dual_alu_payload_i,
    input  wire [REGS_DATA_WIDTH-1:0] dual_alu_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0] dual_alu_operand_b_i,
    input  wire dual_bru_valid_i,
    input  ydrasil_lane_b_bru_payload_t dual_bru_payload_i,
    input  wire [REGS_DATA_WIDTH-1:0] dual_bru_operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0] dual_bru_operand_b_i,

    output ydrasil_ex_hzd_pkt_t ex_hzd_o,
    output ydrasil_ex_hzd_pkt_t ex_hzd1_o,
    output ydrasil_lsu_req_pkt_t lsu_req_o,
    output wire [INST_ADDR_WIDTH-1:0] lane_a_pc_o,
    output wire [INST_ADDR_WIDTH-1:0] lane_b_pc_o,
    output wire lane_a_valid_o,
    output wire lane_b_valid_o,
    output wire lane_a_execute_valid_o,

    output wire ex_csr_wen_o,
    output wire [REGS_DATA_WIDTH-1:0] ex_csr_wdata_o,
    output wire [CSR_ADDR_WIDTH-1:0] ex_csr_waddr_o,
    output wire [REGS_DATA_WIDTH-1:0] alu_result_o,
    output wire alu_rf_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_o,
    output producer_id_t alu_producer_id_o,
    output wire alu_completion_valid_o,
    output producer_id_t alu_completion_producer_id_o,
    output wire alu_completion_producer_tracked_o,
    output wire [REGS_ADDR_WIDTH-1:0] alu_completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0] alu_completion_data_o,
    output wire [REGS_DATA_WIDTH-1:0] main_early_bypass_data_o,
    output wire mul_issue_o,
    output wire [REGS_ADDR_WIDTH-1:0] mul_issue_waddr_o,
    output wire [REGS_DATA_WIDTH-1:0] mul_result_o,
    output wire mul_rf_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0] mul_rf_waddr_o,
    output producer_id_t mul_producer_id_o,
    output wire mul_result_valid_o,
    output wire mul_stall_o,

    output wire dual_completion_valid_o,
    output producer_id_t dual_completion_producer_id_o,
    output wire dual_completion_producer_tracked_o,
    output wire [REGS_ADDR_WIDTH-1:0] dual_completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0] dual_completion_data_o,
    output wire [REGS_DATA_WIDTH-1:0] dual_early_bypass_data_o,
    output wire ex_branch_jump_o,
    output wire [INST_ADDR_WIDTH-1:0] ex_branch_target_o,
    output wire ex_pc_redirect_o,
    output wire [INST_ADDR_WIDTH-1:0] ex_pc_redirect_target_o,
    output ydrasil_bp_train_pkt_t ex_bp_train_o,
    output wire ex_branch_mispredict_o,
    output wire dual_instret_valid_o,
    output wire [INST_ADDR_WIDTH-1:0] dual_commit_pc_o,
    output wire [INST_DATA_WIDTH-1:0] dual_commit_instr_o
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
    logic [OPERATOR_WIDTH-1:0] dual_operator;
    logic [OPERATOR_TYPE_WIDTH-1:0] dual_operator_type;
    wire [REGS_DATA_WIDTH-1:0] dual_operand_a = dual_alu_operand_a_i;
    wire [REGS_DATA_WIDTH-1:0] dual_operand_b = dual_alu_operand_b_i;
    wire dual_valid = dual_alu_valid_i || agu_valid_i || mul_valid_i;
    wire [BUS_ADDR_WIDTH-1:0] lsu_mem_addr;
    wire [REGS_DATA_WIDTH-1:0] lsu_store_result;
    wire unused_instret;

    always_comb begin
        dual_operator = '0;
        dual_operator_type = '0;
        if (mul_valid_i) begin
            dual_operator = mul_operator_i;
            dual_operator_type = mul_operator_type_i;
        end else if (agu_valid_i) begin
            dual_operator_type[OPERATOR_TYPE_LOAD] = agu_req_i.is_load;
            dual_operator_type[OPERATOR_TYPE_STORE] = agu_req_i.is_store;
        end else if (dual_alu_valid_i) begin
            dual_operator[dual_alu_payload_i.subop] = 1'b1;
            dual_operator_type[OPERATOR_TYPE_ALU] =
                !dual_alu_payload_i.bitmanip;
            dual_operator_type[OPERATOR_TYPE_BITMANIP] =
                dual_alu_payload_i.bitmanip;
        end
    end

    always_comb begin
        ex_hzd_o = '0;
        ex_hzd_o.valid = alu_valid_i;
        ex_hzd_o.interrupt_pending = trap_redirect_i;
        ex_hzd_o.producer_id = alu_producer_id_i;
        ex_hzd_o.producer_tracked = alu_valid_i;
        ex_hzd_o.rd_addr = alu_rd_addr_i;
        ex_hzd_o.alu_rf_wen = alu_rd_wen_i;
        ex_hzd_o.operator_type = alu_operator_type_i;
        ex_hzd_o.operator_info = alu_operator_i;

        ex_hzd1_o = '0;
        ex_hzd1_o.valid = dual_valid;
        ex_hzd1_o.interrupt_pending = trap_redirect_i;
        ex_hzd1_o.producer_id = dual_meta_i.producer_id;
        ex_hzd1_o.producer_tracked = dual_meta_i.producer_tracked;
        ex_hzd1_o.rd_addr = dual_meta_i.rd_addr;
        ex_hzd1_o.alu_rf_wen = dual_meta_i.rd_wen;
        ex_hzd1_o.operator_type = dual_operator_type;
        ex_hzd1_o.operator_info = dual_operator;
    end

    always_comb begin
        lsu_req_o = agu_req_i;
        lsu_req_o.valid = agu_req_i.valid && !ex_pc_redirect_o;
        lsu_req_o.addr = lsu_mem_addr;
        lsu_req_o.store_data = agu_store_data_i;
        lsu_req_o.addr_is_dtcm =
            (lsu_mem_addr >= DTCM_BASE_ADDR) &&
            (lsu_mem_addr < (DTCM_BASE_ADDR +
             ((32'd1 << DTCM_ADDR_WIDTH) << 2)));
        if (agu_req_i.op[OP_LSU_SB])
            lsu_req_o.store_mask = 4'b0001 << lsu_mem_addr[1:0];
        else if (agu_req_i.op[OP_LSU_SH])
            lsu_req_o.store_mask = lsu_mem_addr[1] ? 4'b1100 : 4'b0011;
        else if (agu_req_i.op[OP_LSU_SW])
            lsu_req_o.store_mask = 4'b1111;
        else
            lsu_req_o.store_mask = 4'b0000;
    end

    assign lane_a_pc_o = lane_a_pc_i;
    assign lane_b_pc_o = dual_meta_i.pc;
    assign lane_a_valid_o = alu_valid_i;
    assign lane_b_valid_o = dual_valid;
    assign lane_a_execute_valid_o = alu_valid_i && !illegal_instr_i;

    ydrasil_ex_block u_main_ex (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .flush_ex_i             (flush_i),
        .alu_operand_a_i        (alu_operand_a_i),
        .alu_operand_b_i        (alu_operand_b_i),
        .lsu_operand_a_i        (agu_operand_a_i),
        .lsu_operand_b_i        (agu_operand_b_i),
        .lsu_store_data_i       (agu_store_data_i),
        .mul_operand_a_i        (mul_operand_a_i),
        .mul_operand_b_i        (mul_operand_b_i),
        .csr_operand_a_i        (csr_operand_a_i),
        .operator_i             (alu_operator_i),
        .operator_type_i        (alu_operator_type_i),
        .alu_valid_i            (alu_valid_i),
        .lsu_valid_i            (agu_valid_i),
        .lsu_is_load_i          (agu_req_i.is_load),
        .lsu_is_store_i         (agu_req_i.is_store),
        .mul_valid_i            (mul_valid_i),
        .csr_valid_i            (csr_valid_i),
        .mul_operator_i         (mul_operator_i),
        .mul_operator_type_i    (mul_operator_type_i),
        .mul_rf_waddr_i         (dual_meta_i.rd_addr),
        .mul_rf_wen_i           (dual_meta_i.rd_wen),
        .mul_producer_id_i      (dual_meta_i.producer_id),
        .csr_operator_type_i    (csr_operator_type_i),
        .id_rf_waddr_rd_i       (alu_rd_addr_i),
        .id_alu_rf_wen_rd_i     (alu_rd_wen_i),
        .id_ex_producer_id_i    (alu_producer_id_i),
        .redirect_valid_i       (ex_bp_train_o.valid),
        .redirect_keep_mask_i   (branch_recovery_keep_mask_i),
        .trap_redirect_i        (trap_redirect_i),
        .trap_redirect_addr_i   (trap_redirect_addr_i),
        .id_ex_csr_waddr_i      (csr_waddr_i),
        .id_op_csr_info_i       (csr_op_info_i),
        .csr_ex_rdata_i         (csr_rdata_i),
        .ex_csr_wen_o           (ex_csr_wen_o),
        .ex_csr_wdata_o         (ex_csr_wdata_o),
        .ex_csr_waddr_o         (ex_csr_waddr_o),
        .ex_lsu_mem_addr_o      (lsu_mem_addr),
        .ex_lsu_result_o        (lsu_store_result),
        .alu_result_o           (alu_result_o),
        .alu_rf_wen_rd_o        (alu_rf_wen_o),
        .alu_rf_waddr_rd_o      (alu_rf_waddr_o),
        .alu_producer_id_o      (alu_producer_id_o),
        .completion_valid_o     (alu_completion_valid_o),
        .completion_producer_id_o(alu_completion_producer_id_o),
        .completion_producer_tracked_o(alu_completion_producer_tracked_o),
        .completion_addr_o      (alu_completion_addr_o),
        .completion_data_o      (alu_completion_data_o),
        .early_bypass_data_o    (main_early_bypass_data_o),
        .mul_issue_o            (mul_issue_o),
        .mul_issue_waddr_o      (mul_issue_waddr_o),
        .mul_wdata_rd_o         (mul_result_o),
        .mul_rf_wen_rd_o        (mul_rf_wen_o),
        .mul_rf_waddr_rd_o      (mul_rf_waddr_o),
        .mul_producer_id_o      (mul_producer_id_o),
        .mul_result_valid_o     (mul_result_valid_o),
        .ex_instret_inc_o       (unused_instret),
        .ex_mul_stall_o         (mul_stall_o)
    );

    ydrasil_bru u_lane_a_bru (
        .clk(clk),
        .rst_n(rst_n),
        .flush_i(flush_i),
        .operand_a_i(dual_bru_operand_a_i),
        .operand_b_i(dual_bru_operand_b_i),
        .bt_a_operand_i(dual_bru_payload_i.jalr ?
            dual_bru_operand_a_i : lane_a_pc_i),
        .bt_b_operand_i(dual_bru_payload_i.imm),
        .operator_i(alu_operator_i),
        .operator_type_i(alu_operator_type_i),
        .id_ex_valid_i(dual_bru_valid_i),
        .id_ex_jalr_i(dual_bru_payload_i.jalr),
        .id_ex_branch_target_i(lane_a_pc_i + dual_bru_payload_i.imm),
        .id_ex_branch_next_pc_i(lane_a_pc_i + 32'd4),
        .id_ex_pred_hit_i(dual_bru_payload_i.pred_hit),
        .id_ex_pred_taken_i(dual_bru_payload_i.pred_taken),
        .id_ex_pred_target_i(dual_bru_payload_i.pred_target),
        .id_ex_pred_counter_i(dual_bru_payload_i.pred_counter),
        .id_ex_pred_bht_index_i(dual_bru_payload_i.pred_bht_index),
        .id_ex_producer_id_i(alu_producer_id_i),
        .trap_redirect_i(trap_redirect_i),
        .trap_redirect_addr_i(trap_redirect_addr_i),
        .ex_branch_jump_o(ex_branch_jump_o),
        .ex_branch_target_o(ex_branch_target_o),
        .ex_pc_redirect_o(ex_pc_redirect_o),
        .ex_pc_redirect_target_o(ex_pc_redirect_target_o),
        .ex_bp_train_o(ex_bp_train_o),
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

    ydrasil_dual_alu u_dual_ex (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .flush_i                (flush_i),
        .interrupt_i            (trap_redirect_i),
        .valid_i                (ex_accept_valid1_i && dual_alu_valid_i),
        .operand_a_i            (dual_operand_a),
        .operand_b_i            (dual_operand_b),
        .operator_i             (dual_operator),
        .operator_type_i        (dual_operator_type),
        .rd_addr_i              (dual_meta_i.rd_addr),
        .rd_wen_i               (dual_meta_i.rd_wen),
        .producer_id_i          (dual_meta_i.producer_id),
        .producer_tracked_i     (dual_meta_i.producer_tracked),
        .pc_i                   (dual_meta_i.pc),
        .instr_i                (dual_meta_i.instr),
        .completion_valid_o     (dual_completion_valid_o),
        .completion_producer_id_o(dual_completion_producer_id_o),
        .completion_producer_tracked_o(dual_completion_producer_tracked_o),
        .completion_addr_o      (dual_completion_addr_o),
        .completion_data_o      (dual_completion_data_o),
        .early_bypass_data_o    (dual_early_bypass_data_o),
        .instret_valid_o        (dual_instret_valid_o),
        .commit_pc_o            (dual_commit_pc_o),
        .commit_instr_o         (dual_commit_instr_o)
    );

    wire unused = &{1'b0, lsu_store_result};
endmodule
