module ydrasil_issue_stage
import ydrasil_pkg::*;
import ydrasil_pipeline_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            stall_id_i,
    input  wire                            bubble_id_i,
    input  wire                            bubble_id_no_alloc_i,
    input  wire                            flush_id_i,

    input  issue_pair_pkt_t                id_issue_pair_i,

    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,
    output wire [4:0]                      pipe1_rf_addr_rs1_o,
    output wire [4:0]                      pipe1_rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           pipe1_rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_rf_rdata_rs2_i,
    input  wire                            wb_fwd_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      wb_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           wb_fwd_data_i,
    input  wire                            lsu_fwd_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      lsu_fwd_addr_i,
    input  wire [5:0]                      lsu_fwd_pdst_i,
    input  wire [DATA_WIDTH-1:0]           lsu_fwd_data_i,
    input  wire                            alu_fwd_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      alu_fwd_addr_i,
    input  wire [5:0]                      alu_fwd_pdst_i,
    input  wire [DATA_WIDTH-1:0]           alu_fwd_data_i,
    input  wire                            pipe1_alu_fwd_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      pipe1_alu_fwd_addr_i,
    input  wire [5:0]                      pipe1_alu_fwd_pdst_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_alu_fwd_data_i,
    input  wire                            prf_rs1_ready_i,
    input  wire                            prf_rs2_ready_i,
    input  wire [DATA_WIDTH-1:0]           prf_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]           prf_rs2_data_i,
    input  wire                            prf_rs1_uncommitted_i,
    input  wire                            prf_rs2_uncommitted_i,
    input  wire                            pipe1_prf_rs1_ready_i,
    input  wire                            pipe1_prf_rs2_ready_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_prf_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_prf_rs2_data_i,
    input  wire                            pipe1_prf_rs1_uncommitted_i,
    input  wire                            pipe1_prf_rs2_uncommitted_i,
    input  wire                            ready_issue_allow_i,
    input  wire [REGS_NUM-1:0]             gpr_pending_i,
    input  wire [63:0]                     rn_preg_ready_i,
    input  wire                            pipe1_resbuf_full_i,
    output wire                            issue_frontend_stall_o,

    output wire [DATA_WIDTH-1:0]           operand_a_o,
    output wire [DATA_WIDTH-1:0]           operand_b_o,
    output wire [OPERATOR_WIDTH-1:0]       operator_o,
    output wire [DATA_WIDTH-1:0]           bt_a_operand_o,
    output wire [DATA_WIDTH-1:0]           bt_b_operand_o,
    output wire [OP_LSU_INFO_WIDTH-1:0]    operator_lsu_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_rs2_data_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_addr_o,
    output wire                            id_lsu_addr_is_dtcm_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_store_data_o,
    output wire [3:0]                      id_lsu_store_mask_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0]  operator_type_o,

    output wire                            id_ex_jalr_o,
    output wire [REGS_ADDR_WIDTH-1:0]      id_ctrl_rs1_addr_o,
    output wire [REGS_ADDR_WIDTH-1:0]      id_ctrl_rs2_addr_o,
    output wire                            id_ctrl_rs1_ren_o,
    output wire                            id_ctrl_rs2_ren_o,
    output wire                            id_ctrl_rd_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0]      id_ctrl_rd_addr_o,
    output wire                            id_ctrl_lsu_req_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0]  id_ctrl_operator_type_o,

    output wire [CSR_ADDR_WIDTH-1:0]       id_csr_raddr_o,
    output wire [CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr_o,
    output wire [OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_o,
    output wire [OP_SYS_INFO_WIDTH-1:0]    id_op_sys_info_o,

    output wire [DATA_WIDTH-1:0]           id_instr_addr_o,
    output wire                            id_fence_i_o,
    output wire                            id_ex_pred_hit_o,
    output wire                            id_ex_pred_taken_o,
    output wire [DATA_WIDTH-1:0]           id_ex_pred_target_o,
    output wire [1:0]                      id_ex_pred_counter_o,
    output wire [DATA_WIDTH-1:0]           id_ex_pred_bht_index_o,
    output wire                            id_ex_pred_l0_taken_o,
    output wire                            id_ex_valid_o,
    output wire                            id_alu_rf_wen_rd_o,
    output wire [4:0]                      id_rf_waddr_rd_o,
    output wire [5:0]                      id_rn_pdst_o,
    output wire                            id_ctrl_rob_valid_o,
    output wire [5:0]                      id_ctrl_rob_idx_o,
    output wire [5:0]                      id_ctrl_rs1_psrc_o,
    output wire [5:0]                      id_ctrl_rs2_psrc_o,
    output wire [5:0]                      id_ctrl_pdst_o,
    output wire                            pipe1_ctrl_rs1_ren_o,
    output wire                            pipe1_ctrl_rs2_ren_o,
    output wire [5:0]                      pipe1_ctrl_rs1_psrc_o,
    output wire [5:0]                      pipe1_ctrl_rs2_psrc_o,

    output wire                            pipe1_issue_valid_o,
    output wire [DATA_WIDTH-1:0]           pipe1_operand_a_o,
    output wire [DATA_WIDTH-1:0]           pipe1_operand_b_o,
    output wire [OPERATOR_WIDTH-1:0]       pipe1_operator_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0]  pipe1_operator_type_o,
    output wire                            pipe1_rf_wen_rd_o,
    output wire [4:0]                      pipe1_rf_waddr_rd_o,
    output wire [5:0]                      pipe1_rn_pdst_o,
    output wire                            pipe1_rob_valid_o,
    output wire [5:0]                      pipe1_rob_idx_o,
    output wire [DATA_WIDTH-1:0]           pipe1_pc_o,
    output wire [DATA_WIDTH-1:0]           pipe1_instr_o
);

    localparam int IQ_DEPTH = 8;
    localparam int IQ_INDEX_WIDTH = $clog2(IQ_DEPTH);
    localparam int IQ_COUNT_WIDTH = $clog2(IQ_DEPTH + 1);
    localparam logic [IQ_COUNT_WIDTH:0] IQ_DEPTH_COUNT = IQ_DEPTH;

    issue_pkt_t iq_q [0:IQ_DEPTH-1];
    issue_pkt_t iq_next [0:IQ_DEPTH-1];
    issue_pkt_t pipe0_pkt;
    issue_pkt_t pipe1_pkt;
    issue_pkt_t slot0_q;
    issue_pkt_t slot1_q;
    reg [IQ_COUNT_WIDTH-1:0] iq_count_q;
    reg [IQ_COUNT_WIDTH-1:0] iq_count_next;
    reg [IQ_INDEX_WIDTH-1:0] pipe1_sel_idx;
    reg                      pipe1_sel_valid;

    reg [31:0] perf_id_decode_valid, perf_id_issue_accept, perf_id_issue_fire;
    reg [31:0] perf_id_issue_slot_valid, perf_id_issue_no_fire, perf_id_issue_wait_block;
    reg [31:0] perf_id_wait_rs1, perf_id_wait_rs2;
    reg [31:0] perf_id_wait_alu_ready_next_rs1, perf_id_wait_alu_ready_next_rs2;
    reg [31:0] perf_id_wait_lsu_fwd_rs1, perf_id_wait_lsu_fwd_rs2;
    reg [31:0] perf_id_wait_wb_fwd_rs1, perf_id_wait_wb_fwd_rs2;
    reg [31:0] perf_id_wait_prf_ready_rs1, perf_id_wait_prf_ready_rs2;
    reg [31:0] perf_id_skid_valid, perf_id_skid_fill, perf_id_skid_drain;
    reg [31:0] perf_id_skid_full_stall, perf_id_frontend_stall;
    reg [31:0] perf_ri_slot0_valid, perf_ri_slot1_valid;
    reg [31:0] perf_ri_slot0_ready, perf_ri_slot1_ready;
    reg [31:0] perf_ri_fire_slot0, perf_ri_fire_slot1_bypass;
    reg [31:0] perf_ri_slot1_block_raw, perf_ri_slot1_block_waw;
    reg [31:0] perf_ri_slot1_block_ctrl, perf_ri_slot1_block_mem;
    reg [31:0] perf_ri_slot1_block_unsupported;
    reg [31:0] perf_ri_slot1_ready_when_slot0_blocked;
    reg [31:0] perf_ri_slot1_ready_when_slot0_ready;
    reg [31:0] perf_ri_slot1_fire_blocked_by_single_issue;
    reg [31:0] perf_ri_slot1_fire_blocked_by_operand_port;
    reg [31:0] perf_ri_slot1_fire_blocked_by_wb_order;
    reg [31:0] perf_ri_bypass_flush_killed;
    reg [31:0] perf_di_pipe0_fire, perf_di_pipe1_fire, perf_di_pair_fire;
    reg [31:0] perf_di_pair_simple_alu, perf_di_pipe1_killed_flush;
    reg [31:0] perf_di_pipe1_block_stall_recheck;
    reg [31:0] perf_di_pipe1_block_resbuf_full;
    reg [31:0] perf_di_pipe1_block_alu_fifo_full;
    reg [31:0] perf_di_pipe1_block_pending_recheck;
    reg [31:0] perf_di_pipe1_block_timing_guard;
    reg [31:0] perf_di_pipe1_operand_block_rs1;
    reg [31:0] perf_di_pipe1_operand_block_rs2;
    reg [31:0] perf_di_pipe1_operand_block_both;
    reg [31:0] perf_di_pipe1_operand_block_from1;
    reg [31:0] perf_di_pipe1_operand_block_from2;
    reg [31:0] perf_di_pipe1_operand_block_recoverable;
    reg [31:0] perf_di_pipe1_alt2_when_from1_block_safe;
    reg [31:0] perf_di_pipe1_alt2_when_from1_block_ready;
    reg [31:0] perf_di_pipe1_alt2_when_recoverable_safe;
    reg [31:0] perf_di_pipe1_alt2_when_recoverable_ready;
    reg [31:0] perf_dual_cycles_with_pair_fire;
    reg [31:0] perf_dual_extra_instret_pipe1;
    reg [31:0] perf_dual_pipe1_squashed;
    reg [31:0] perf_ds_cycles, perf_ds_pipe0_valid, perf_ds_pipe0_ready;
    reg [31:0] perf_ds_pipe1_valid, perf_ds_pipe1_simple_alu;
    reg [31:0] perf_ds_safe_candidate, perf_ds_safe_when_pipe0_ready;
    reg [31:0] perf_ds_safe_when_pipe0_blocked;
    reg [31:0] perf_ds_block_pipe1_unsupported;
    reg [31:0] perf_ds_block_raw_pipe0, perf_ds_block_waw_pipe0;
    reg [31:0] perf_ds_block_pending_rs1, perf_ds_block_pending_rs2;
    reg [31:0] perf_ds_block_ctrl, perf_ds_block_mem, perf_ds_block_csr_sys;
    reg [31:0] perf_ds_block_flush, perf_ds_block_wb_port;
    reg [31:0] perf_ds_block_forward_complex;
    reg [31:0] perf_p1sh_valid_cycles, perf_p1sh_simple_alu;
    reg [31:0] perf_p1sh_safe_cand, perf_p1sh_block_raw_pair0;
    reg [31:0] perf_p1sh_block_waw_pair0, perf_p1sh_block_pending_rs;
    reg [31:0] perf_p1sh_block_ctrl_mem;
    reg [31:0] perf_uopq_occ_0, perf_uopq_occ_1, perf_uopq_occ_2;
    reg [31:0] perf_uopq_occ_3, perf_uopq_occ_4;
    reg [31:0] perf_uopq_p1_safe_1, perf_uopq_p1_safe_2, perf_uopq_p1_safe_3;
    reg [31:0] perf_uopq_block_older_ctrl_mem;
    reg [31:0] perf_uopq_block_raw_older, perf_uopq_block_waw_older;
    reg [31:0] perf_uopq_p1_fire_from_1, perf_uopq_p1_fire_from_2;
    reg [31:0] perf_uopq_p1_fire_from_3;
    reg [31:0] perf_uopq_p1_fire_when_p0_ready;
    reg [31:0] perf_uopq_p1_fire_when_p0_blocked;
    reg [31:0] perf_uopq_p1_fire_when_p0_empty;
    reg [31:0] perf_uopq_p1_block_older_ctrl_mem;
    reg [31:0] perf_uopq_p1_block_raw_older;
    reg [31:0] perf_uopq_p1_block_waw_older;
    reg [31:0] perf_uopq_p1_block_commit_order;
    reg [31:0] perf_uopq_p1_block_p0_bjp, perf_uopq_p1_block_p0_load;
    reg [31:0] perf_uopq_p1_block_p0_store;
    reg [31:0] perf_uopq_p1_block_p0_csr_sys;
    reg [31:0] perf_uopq_p1_block_p0_bitmanip;
    reg [31:0] perf_uopq_p1_block_p0_other;
    reg [31:0] perf_uopq_p1_block_p0_other_invalid;
    reg [31:0] perf_uopq_p1_block_p0_other_no_alu_mul;
    reg [31:0] perf_uopq_p1_block_p0_invalid_issue_accept;
    reg [31:0] perf_uopq_p1_block_p0_invalid_skid;
    reg [31:0] perf_uopq_p1_block_p0_invalid_uopq2_safe;
    reg [31:0] perf_uopq_p1_empty_base, perf_uopq_p1_empty_supported;
    reg [31:0] perf_uopq_p1_empty_operands_ready;
    reg [31:0] perf_uopq_p1_empty_block_younger;
    reg [31:0] perf_uopq_p1_empty_block_ready_allow;
    reg [31:0] perf_uopq_p1_empty_block_pending_rd;
    reg [31:0] perf_uopq_p1_empty_block_resbuf;
    reg [31:0] perf_uopq_p1_blocked_base;
    reg [31:0] perf_uopq_p1_blocked_supported;
    reg [31:0] perf_uopq_p1_blocked_p0_safe;
    reg [31:0] perf_uopq_p1_blocked_operands_ready;
    reg [31:0] perf_uopq_p1_blocked_block_younger;
    reg [31:0] perf_uopq_p1_blocked_block_ready_allow;
    reg [31:0] perf_uopq_p1_blocked_block_pending_rd;
    reg [31:0] perf_uopq_p1_blocked_block_resbuf;
    reg [31:0] perf_uopq_p1_blocked_unsup_any_uop;
    reg [31:0] perf_uopq_p1_blocked_unsup_shadow_alu;
    reg [31:0] perf_uopq_p1_blocked_unsup_shift;
    reg [31:0] perf_uopq_p1_blocked_unsup_x0_rs1;
    reg [31:0] perf_uopq_p1_blocked_unsup_lui_auipc;
    reg [31:0] perf_uopq_p1_blocked_unsup_relax_ready;
    reg [31:0] perf_uopq_p1_blocked_unsup_relax_fire_safe;
    reg [31:0] perf_uopq_p1_blocked_unsup_relax_shift_safe;
    reg [31:0] perf_uopq_p1_blocked_unsup_relax_x0_safe;
    reg [31:0] perf_uopq_p1_blocked_unsup_relax_lui_auipc_safe;
    reg [31:0] perf_uopq_p1_block_younger_flush;
    reg [31:0] perf_uopq_p1_block_young_uopq2;
    reg [31:0] perf_uopq_p1_block_young_ifid;
    reg [31:0] perf_uopq_p1_block_ifid_bjp;
    reg [31:0] perf_uopq_p1_block_ifid_load;
    reg [31:0] perf_uopq_p1_block_ifid_store;
    reg [31:0] perf_uopq_p1_block_ifid_mul;
    reg [31:0] perf_uopq_p1_block_ifid_csr_sys;

    wire iq_uses_rs2 [0:IQ_DEPTH-1];
    wire iq_writes_rd [0:IQ_DEPTH-1];
    wire iq_pipe1_simple_int [0:IQ_DEPTH-1];
    wire iq_serial_before_pipe1 [0:IQ_DEPTH-1];
    wire iq_src1_arch_map [0:IQ_DEPTH-1];
    wire iq_src2_arch_map [0:IQ_DEPTH-1];
    wire iq_src1_alu_fwd [0:IQ_DEPTH-1];
    wire iq_src2_alu_fwd [0:IQ_DEPTH-1];
    wire iq_src1_lsu_fwd [0:IQ_DEPTH-1];
    wire iq_src2_lsu_fwd [0:IQ_DEPTH-1];
    wire iq_src1_p1_fwd [0:IQ_DEPTH-1];
    wire iq_src2_p1_fwd [0:IQ_DEPTH-1];
    wire iq_src1_ready [0:IQ_DEPTH-1];
    wire iq_src2_ready [0:IQ_DEPTH-1];
    wire iq_operands_ready [0:IQ_DEPTH-1];

    genvar iq_i;
    generate
        for (iq_i = 0; iq_i < IQ_DEPTH; iq_i = iq_i + 1) begin : gen_iq_decode
            assign iq_uses_rs2[iq_i] =
                iq_q[iq_i].dec.rf_ren_rs2 ||
                iq_q[iq_i].dec.operand_b_rs_sel ||
                iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_STORE];
            assign iq_writes_rd[iq_i] =
                iq_q[iq_i].dec.valid &&
                (iq_q[iq_i].dec.rf_wen_rd ||
                 iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_LOAD]) &&
                (iq_q[iq_i].dec.rf_waddr_rd != '0) &&
                !iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_SYS];
            assign iq_pipe1_simple_int[iq_i] =
                iq_q[iq_i].dec.valid &&
                (iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_ALU] ||
                 iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_BITMANIP]) &&
                !iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_BJP] &&
                !iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_LOAD] &&
                !iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_STORE] &&
                !iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_CSR] &&
                !iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_SYS] &&
                !iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_MUL] &&
                !iq_q[iq_i].dec.fence_i;
            assign iq_serial_before_pipe1[iq_i] =
                iq_q[iq_i].dec.valid &&
                (iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_BJP] ||
                 iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_CSR] ||
                 iq_q[iq_i].dec.operator_type[OPERATOR_TYPE_SYS] ||
                 iq_q[iq_i].dec.fence_i);
            assign iq_src1_arch_map[iq_i] =
                iq_q[iq_i].rn.rs1_psrc == {1'b0, iq_q[iq_i].dec.rf_raddr_rs1};
            assign iq_src2_arch_map[iq_i] =
                iq_q[iq_i].rn.rs2_psrc == {1'b0, iq_q[iq_i].dec.rf_raddr_rs2};
            assign iq_src1_alu_fwd[iq_i] =
                alu_fwd_valid_i && iq_q[iq_i].dec.rf_ren_rs1 &&
                (iq_q[iq_i].dec.rf_raddr_rs1 != '0) &&
                (iq_q[iq_i].rn.rs1_psrc == alu_fwd_pdst_i) &&
                (iq_q[iq_i].dec.rf_raddr_rs1 == alu_fwd_addr_i);
            assign iq_src2_alu_fwd[iq_i] =
                alu_fwd_valid_i && iq_uses_rs2[iq_i] &&
                (iq_q[iq_i].dec.rf_raddr_rs2 != '0) &&
                (iq_q[iq_i].rn.rs2_psrc == alu_fwd_pdst_i) &&
                (iq_q[iq_i].dec.rf_raddr_rs2 == alu_fwd_addr_i);
            assign iq_src1_lsu_fwd[iq_i] =
                lsu_fwd_valid_i && iq_q[iq_i].dec.rf_ren_rs1 &&
                (iq_q[iq_i].dec.rf_raddr_rs1 != '0) &&
                (iq_q[iq_i].rn.rs1_psrc == lsu_fwd_pdst_i) &&
                (iq_q[iq_i].dec.rf_raddr_rs1 == lsu_fwd_addr_i);
            assign iq_src2_lsu_fwd[iq_i] =
                lsu_fwd_valid_i && iq_uses_rs2[iq_i] &&
                (iq_q[iq_i].dec.rf_raddr_rs2 != '0) &&
                (iq_q[iq_i].rn.rs2_psrc == lsu_fwd_pdst_i) &&
                (iq_q[iq_i].dec.rf_raddr_rs2 == lsu_fwd_addr_i);
            assign iq_src1_p1_fwd[iq_i] =
                pipe1_alu_fwd_valid_i && iq_q[iq_i].dec.rf_ren_rs1 &&
                (iq_q[iq_i].dec.rf_raddr_rs1 != '0) &&
                (iq_q[iq_i].rn.rs1_psrc == pipe1_alu_fwd_pdst_i) &&
                (iq_q[iq_i].dec.rf_raddr_rs1 == pipe1_alu_fwd_addr_i);
            assign iq_src2_p1_fwd[iq_i] =
                pipe1_alu_fwd_valid_i && iq_uses_rs2[iq_i] &&
                (iq_q[iq_i].dec.rf_raddr_rs2 != '0) &&
                (iq_q[iq_i].rn.rs2_psrc == pipe1_alu_fwd_pdst_i) &&
                (iq_q[iq_i].dec.rf_raddr_rs2 == pipe1_alu_fwd_addr_i);
            assign iq_src1_ready[iq_i] =
                !iq_q[iq_i].dec.rf_ren_rs1 ||
                (iq_q[iq_i].dec.rf_raddr_rs1 == '0) ||
                iq_q[iq_i].rn.rs1_ready ||
                rn_preg_ready_i[iq_q[iq_i].rn.rs1_psrc] ||
                iq_src1_alu_fwd[iq_i] ||
                iq_src1_lsu_fwd[iq_i] ||
                iq_src1_p1_fwd[iq_i];
            assign iq_src2_ready[iq_i] =
                !iq_uses_rs2[iq_i] ||
                (iq_q[iq_i].dec.rf_raddr_rs2 == '0) ||
                iq_q[iq_i].rn.rs2_ready ||
                rn_preg_ready_i[iq_q[iq_i].rn.rs2_psrc] ||
                iq_src2_alu_fwd[iq_i] ||
                iq_src2_lsu_fwd[iq_i] ||
                iq_src2_p1_fwd[iq_i];
            assign iq_operands_ready[iq_i] =
                iq_q[iq_i].dec.valid &&
                iq_src1_ready[iq_i] &&
                iq_src2_ready[iq_i];
        end
    endgenerate

    wire slot0_in_valid = id_issue_pair_i.slot0.dec.valid;
    wire slot1_in_valid =
        id_issue_pair_i.pair_ctrl.decode_pair_allow &&
        id_issue_pair_i.pair_ctrl.slot1_valid &&
        id_issue_pair_i.slot1.dec.valid;
    wire slot0_in_writes_rd =
        id_issue_pair_i.slot0.dec.valid &&
        (id_issue_pair_i.slot0.dec.rf_wen_rd ||
         id_issue_pair_i.slot0.dec.operator_type[OPERATOR_TYPE_LOAD]) &&
        (id_issue_pair_i.slot0.dec.rf_waddr_rd != '0) &&
        !id_issue_pair_i.slot0.dec.operator_type[OPERATOR_TYPE_SYS];
    wire slot1_in_writes_rd =
        id_issue_pair_i.slot1.dec.valid &&
        (id_issue_pair_i.slot1.dec.rf_wen_rd ||
         id_issue_pair_i.slot1.dec.operator_type[OPERATOR_TYPE_LOAD]) &&
        (id_issue_pair_i.slot1.dec.rf_waddr_rd != '0) &&
        !id_issue_pair_i.slot1.dec.operator_type[OPERATOR_TYPE_SYS];
    wire [1:0] enqueue_count =
        {1'b0, slot0_in_valid} + {1'b0, slot1_in_valid};

    wire pipe0_valid = (iq_count_q != '0) && iq_q[0].dec.valid;
    wire pipe0_operands_ready = iq_operands_ready[0];
    wire pipe0_issue_allow =
        ready_issue_allow_i && !bubble_id_no_alloc_i &&
        !flush_id_i;
    wire pipe0_fire = pipe0_valid && pipe0_operands_ready && pipe0_issue_allow;
    wire pipe0_dequeue = pipe0_fire && !stall_id_i;
    wire slot0_fire = pipe0_fire;
    wire issue_fire_allow = pipe0_issue_allow;
    wire pipe1_issue_allow =
        ready_issue_allow_i && !stall_id_i && !flush_id_i &&
        !pipe1_resbuf_full_i;
    wire pipe1_raw_after_pipe0 =
        iq_writes_rd[0] &&
        ((iq_q[1].dec.rf_ren_rs1 &&
          (iq_q[1].dec.rf_raddr_rs1 == iq_q[0].dec.rf_waddr_rd)) ||
         (iq_uses_rs2[1] &&
          (iq_q[1].dec.rf_raddr_rs2 == iq_q[0].dec.rf_waddr_rd)));
    wire pipe1_waw_after_pipe0 =
        iq_writes_rd[0] &&
        iq_writes_rd[1] &&
        (iq_q[1].dec.rf_waddr_rd == iq_q[0].dec.rf_waddr_rd);

    always_comb begin
        pipe1_sel_valid = 1'b0;
        pipe1_sel_idx = '0;
        if (pipe0_fire &&
            (iq_count_q > IQ_COUNT_WIDTH'(1)) &&
            iq_q[1].dec.valid &&
            iq_pipe1_simple_int[0] &&
            iq_pipe1_simple_int[1] &&
            iq_operands_ready[1] &&
            pipe1_issue_allow &&
            !pipe1_raw_after_pipe0 &&
            !pipe1_waw_after_pipe0 &&
            !iq_serial_before_pipe1[0]) begin
            pipe1_sel_valid = 1'b1;
            pipe1_sel_idx = IQ_INDEX_WIDTH'(1);
        end
    end

    wire pipe1_fire = pipe1_sel_valid && pipe1_issue_allow;
    wire slot1_fire = pipe1_fire;
    wire [1:0] dequeue_count =
        {1'b0, pipe0_dequeue} + {1'b0, pipe1_fire};
    wire [IQ_COUNT_WIDTH:0] iq_free_after_issue =
        IQ_DEPTH_COUNT -
        {1'b0, iq_count_q} +
        {{IQ_COUNT_WIDTH-1{1'b0}}, dequeue_count};
    wire [IQ_COUNT_WIDTH:0] enqueue_count_ext =
        {{IQ_COUNT_WIDTH-1{1'b0}}, enqueue_count};
    wire enqueue_can_accept =
        (enqueue_count_ext <= iq_free_after_issue);
    wire enqueue0_fire = !flush_id_i && slot0_in_valid && enqueue_can_accept;
    wire enqueue1_fire = enqueue0_fire && slot1_in_valid;
    wire request_pair = slot0_in_valid && enqueue_can_accept;
    wire accept_pair = enqueue0_fire;

    assign issue_frontend_stall_o =
        !flush_id_i && slot0_in_valid && !enqueue_can_accept;

    always_comb begin
        pipe0_pkt = pipe0_valid ? iq_q[0] : '0;
        pipe1_pkt = pipe1_sel_valid ? iq_q[pipe1_sel_idx] : '0;
        slot0_q = pipe0_pkt;
        slot1_q = pipe1_pkt;
    end

    wire slot0_rs1_ready = iq_src1_ready[0];
    wire slot0_rs2_ready = iq_src2_ready[0];
    wire slot1_rs1_ready = pipe1_sel_valid ? iq_src1_ready[pipe1_sel_idx] : 1'b0;
    wire slot1_rs2_ready = pipe1_sel_valid ? iq_src2_ready[pipe1_sel_idx] : 1'b0;
    wire issue_valid_ff = pipe0_valid;
    wire [OPERATOR_TYPE_WIDTH-1:0] issue_operator_type_ff =
        pipe0_pkt.dec.operator_type;
    wire issue_wait_rs1_ff = pipe0_valid && !slot0_rs1_ready;
    wire issue_wait_rs2_ff = pipe0_valid && !slot0_rs2_ready;
    wire issue_wait_rs1_ready = slot0_rs1_ready;
    wire issue_wait_rs2_ready = slot0_rs2_ready;
    wire slot0_rs1_phys_block = pipe0_valid && !slot0_rs1_ready;
    wire slot0_rs2_phys_block = pipe0_valid && !slot0_rs2_ready;
    wire pipe0_uses_rs2 = iq_uses_rs2[0];
    wire pipe0_writes_rd = iq_writes_rd[0];
    wire pipe1_uses_rs2 = pipe1_sel_valid ? iq_uses_rs2[pipe1_sel_idx] : 1'b0;
    wire pipe1_writes_rd = pipe1_sel_valid ? iq_writes_rd[pipe1_sel_idx] : 1'b0;
    wire pipe0_src1_wb_fwd =
        wb_fwd_valid_i && pipe0_pkt.dec.rf_ren_rs1 &&
        (pipe0_pkt.dec.rf_raddr_rs1 != '0) &&
        iq_src1_arch_map[0] && !prf_rs1_uncommitted_i &&
        (pipe0_pkt.dec.rf_raddr_rs1 == wb_fwd_addr_i);
    wire pipe0_src2_wb_fwd =
        wb_fwd_valid_i && pipe0_uses_rs2 &&
        (pipe0_pkt.dec.rf_raddr_rs2 != '0) &&
        iq_src2_arch_map[0] && !prf_rs2_uncommitted_i &&
        (pipe0_pkt.dec.rf_raddr_rs2 == wb_fwd_addr_i);
    wire pipe1_src1_wb_fwd =
        wb_fwd_valid_i && pipe1_pkt.dec.rf_ren_rs1 &&
        (pipe1_pkt.dec.rf_raddr_rs1 != '0) &&
        (pipe1_pkt.rn.rs1_psrc == {1'b0, pipe1_pkt.dec.rf_raddr_rs1}) &&
        !pipe1_prf_rs1_uncommitted_i &&
        (pipe1_pkt.dec.rf_raddr_rs1 == wb_fwd_addr_i);
    wire pipe1_src2_wb_fwd =
        wb_fwd_valid_i && pipe1_uses_rs2 &&
        (pipe1_pkt.dec.rf_raddr_rs2 != '0) &&
        (pipe1_pkt.rn.rs2_psrc == {1'b0, pipe1_pkt.dec.rf_raddr_rs2}) &&
        !pipe1_prf_rs2_uncommitted_i &&
        (pipe1_pkt.dec.rf_raddr_rs2 == wb_fwd_addr_i);
    wire rs1_wb_fwd = pipe0_src1_wb_fwd;
    wire rs2_wb_fwd = pipe0_src2_wb_fwd;
    wire ri_slot1_ready = pipe1_sel_valid;

    wire pipe0_src1_prf_use =
        pipe0_pkt.dec.rf_ren_rs1 &&
        (pipe0_pkt.dec.rf_raddr_rs1 != '0) &&
        (pipe0_pkt.rn.rs1_psrc != '0) &&
        (prf_rs1_uncommitted_i || !iq_src1_arch_map[0]) &&
        (pipe0_pkt.rn.rs1_psrc != pipe0_pkt.rn.pdst);
    wire pipe0_src2_prf_use =
        pipe0_uses_rs2 &&
        (pipe0_pkt.dec.rf_raddr_rs2 != '0) &&
        (pipe0_pkt.rn.rs2_psrc != '0) &&
        (prf_rs2_uncommitted_i || !iq_src2_arch_map[0]) &&
        (pipe0_pkt.rn.rs2_psrc != pipe0_pkt.rn.pdst);
    wire pipe1_src1_prf_use =
        pipe1_pkt.dec.rf_ren_rs1 &&
        (pipe1_pkt.dec.rf_raddr_rs1 != '0) &&
        (pipe1_pkt.rn.rs1_psrc != '0) &&
        (pipe1_prf_rs1_uncommitted_i ||
         (pipe1_pkt.rn.rs1_psrc != {1'b0, pipe1_pkt.dec.rf_raddr_rs1})) &&
        (pipe1_pkt.rn.rs1_psrc != pipe1_pkt.rn.pdst);
    wire pipe1_src2_prf_use =
        pipe1_uses_rs2 &&
        (pipe1_pkt.dec.rf_raddr_rs2 != '0) &&
        (pipe1_pkt.rn.rs2_psrc != '0) &&
        (pipe1_prf_rs2_uncommitted_i ||
         (pipe1_pkt.rn.rs2_psrc != {1'b0, pipe1_pkt.dec.rf_raddr_rs2})) &&
        (pipe1_pkt.rn.rs2_psrc != pipe1_pkt.rn.pdst);

    wire [DATA_WIDTH-1:0] pipe0_rs1_data =
        (pipe0_src1_prf_use && prf_rs1_ready_i) ? prf_rs1_data_i :
        iq_src1_lsu_fwd[0] ? lsu_fwd_data_i :
        iq_src1_alu_fwd[0] ? alu_fwd_data_i :
        iq_src1_p1_fwd[0]  ? pipe1_alu_fwd_data_i :
        pipe0_src1_wb_fwd ? wb_fwd_data_i :
        rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] pipe0_rs2_data =
        (pipe0_src2_prf_use && prf_rs2_ready_i) ? prf_rs2_data_i :
        iq_src2_lsu_fwd[0] ? lsu_fwd_data_i :
        iq_src2_alu_fwd[0] ? alu_fwd_data_i :
        iq_src2_p1_fwd[0]  ? pipe1_alu_fwd_data_i :
        pipe0_src2_wb_fwd ? wb_fwd_data_i :
        rf_rdata_rs2_i;
    wire [DATA_WIDTH-1:0] pipe1_rs1_data =
        (pipe1_src1_prf_use && pipe1_prf_rs1_ready_i) ? pipe1_prf_rs1_data_i :
        iq_src1_lsu_fwd[pipe1_sel_idx] ? lsu_fwd_data_i :
        iq_src1_alu_fwd[pipe1_sel_idx] ? alu_fwd_data_i :
        iq_src1_p1_fwd[pipe1_sel_idx]  ? pipe1_alu_fwd_data_i :
        pipe1_src1_wb_fwd ? wb_fwd_data_i :
        pipe1_rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] pipe1_rs2_data =
        (pipe1_src2_prf_use && pipe1_prf_rs2_ready_i) ? pipe1_prf_rs2_data_i :
        iq_src2_lsu_fwd[pipe1_sel_idx] ? lsu_fwd_data_i :
        iq_src2_alu_fwd[pipe1_sel_idx] ? alu_fwd_data_i :
        iq_src2_p1_fwd[pipe1_sel_idx]  ? pipe1_alu_fwd_data_i :
        pipe1_src2_wb_fwd ? wb_fwd_data_i :
        pipe1_rf_rdata_rs2_i;

    wire [DATA_WIDTH-1:0] pipe0_operand_a =
        pipe0_pkt.dec.operand_a_pc_sel ? pipe0_pkt.dec.pc :
        pipe0_pkt.dec.operand_a_imm_sel ? pipe0_pkt.dec.imm :
        pipe0_rs1_data;
    wire [DATA_WIDTH-1:0] pipe0_operand_b =
        pipe0_pkt.dec.operand_b_jump_sel ? 32'd4 :
        pipe0_pkt.dec.operand_b_rs_sel ? pipe0_rs2_data :
        pipe0_pkt.dec.imm;
    wire [DATA_WIDTH-1:0] pipe1_operand_a =
        (pipe1_pkt.dec.operand_a_pc_sel ||
         (pipe1_pkt.dec.operator_type[OPERATOR_TYPE_ALU] &&
          pipe1_pkt.dec.operator[OP_ALU_AUIPC])) ? pipe1_pkt.dec.pc :
        pipe1_pkt.dec.operand_a_imm_sel ? pipe1_pkt.dec.imm :
        pipe1_rs1_data;
    wire [DATA_WIDTH-1:0] pipe1_operand_b =
        pipe1_pkt.dec.operand_b_jump_sel ? 32'd4 :
        pipe1_pkt.dec.operand_b_rs_sel ? pipe1_rs2_data :
        pipe1_pkt.dec.imm;

    assign rf_addr_rs1_o = pipe0_pkt.dec.rf_raddr_rs1;
    assign rf_addr_rs2_o = pipe0_pkt.dec.rf_raddr_rs2;
    assign pipe1_rf_addr_rs1_o = pipe1_pkt.dec.rf_raddr_rs1;
    assign pipe1_rf_addr_rs2_o = pipe1_pkt.dec.rf_raddr_rs2;

    assign operand_a_o = pipe0_operand_a;
    assign operand_b_o = pipe0_operand_b;
    assign operator_o = pipe0_pkt.dec.operator;
    assign operator_lsu_o = pipe0_pkt.dec.operator_lsu;
    assign operator_type_o = pipe0_pkt.dec.operator_type;
    assign bt_a_operand_o =
        pipe0_pkt.dec.bt_a_rs_sel ? pipe0_rs1_data : pipe0_pkt.dec.pc;
    assign bt_b_operand_o = pipe0_pkt.dec.imm;
    assign id_lsu_rs2_data_o = pipe0_rs2_data;
    assign id_lsu_addr_o = '0;
    assign id_lsu_addr_is_dtcm_o = 1'b0;
    assign id_lsu_store_data_o = pipe0_rs2_data;
    assign id_lsu_store_mask_o = 4'b0000;

    assign id_ex_jalr_o =
        pipe0_pkt.dec.valid && (pipe0_pkt.dec.instr[6:0] == RV32I_INS_JALR);
    assign id_ctrl_rs1_addr_o = pipe0_pkt.dec.rf_raddr_rs1;
    assign id_ctrl_rs2_addr_o = pipe0_pkt.dec.rf_raddr_rs2;
    assign id_ctrl_rs1_ren_o = pipe0_pkt.dec.rf_ren_rs1;
    assign id_ctrl_rs2_ren_o = pipe0_uses_rs2;
    assign id_ctrl_rd_wen_o = pipe0_writes_rd;
    assign id_ctrl_rd_addr_o = pipe0_pkt.dec.rf_waddr_rd;
    assign id_ctrl_lsu_req_o =
        pipe0_pkt.dec.valid &&
        (pipe0_pkt.dec.operator_type[OPERATOR_TYPE_LOAD] |
         pipe0_pkt.dec.operator_type[OPERATOR_TYPE_STORE]);
    assign id_ctrl_operator_type_o = pipe0_pkt.dec.operator_type;
    assign id_ctrl_rs1_psrc_o = pipe0_pkt.rn.rs1_psrc;
    assign id_ctrl_rs2_psrc_o = pipe0_pkt.rn.rs2_psrc;
    assign id_ctrl_pdst_o = pipe0_writes_rd ? pipe0_pkt.rn.pdst : '0;

    assign pipe1_ctrl_rs1_ren_o = pipe1_pkt.dec.rf_ren_rs1;
    assign pipe1_ctrl_rs2_ren_o = pipe1_uses_rs2;
    assign pipe1_ctrl_rs1_psrc_o = pipe1_pkt.rn.rs1_psrc;
    assign pipe1_ctrl_rs2_psrc_o = pipe1_pkt.rn.rs2_psrc;

    assign id_csr_raddr_o = pipe0_pkt.dec.csr_reg_raddr;
    assign id_ex_csr_waddr_o = pipe0_pkt.dec.csr_ex_waddr;
    assign id_op_csr_info_o = pipe0_pkt.dec.csr_op_info;
    assign id_op_sys_info_o = pipe0_pkt.dec.sys_op_info;
    assign id_instr_addr_o = pipe0_pkt.dec.pc;
    assign id_fence_i_o = pipe0_pkt.dec.fence_i;
    assign id_ex_pred_hit_o = pipe0_pkt.dec.pred_hit;
    assign id_ex_pred_taken_o = pipe0_pkt.dec.pred_taken;
    assign id_ex_pred_target_o = pipe0_pkt.dec.pred_target;
    assign id_ex_pred_counter_o = pipe0_pkt.dec.pred_counter;
    assign id_ex_pred_bht_index_o = pipe0_pkt.dec.pred_bht_index;
    assign id_ex_pred_l0_taken_o = pipe0_pkt.dec.pred_l0_taken;
    assign id_ex_valid_o = pipe0_fire;
    assign id_alu_rf_wen_rd_o = pipe0_pkt.dec.rf_wen_rd;
    assign id_rf_waddr_rd_o = pipe0_pkt.dec.rf_waddr_rd;
    assign id_rn_pdst_o = pipe0_writes_rd ? pipe0_pkt.rn.pdst : '0;
    assign id_ctrl_rob_valid_o = pipe0_pkt.rn.rob_valid;
    assign id_ctrl_rob_idx_o = pipe0_pkt.rn.rob_idx;

    assign pipe1_issue_valid_o = pipe1_fire;
    assign pipe1_operand_a_o = pipe1_operand_a;
    assign pipe1_operand_b_o = pipe1_operand_b;
    assign pipe1_operator_o = pipe1_pkt.dec.operator;
    assign pipe1_operator_type_o = pipe1_pkt.dec.operator_type;
    assign pipe1_rf_wen_rd_o = pipe1_pkt.dec.rf_wen_rd;
    assign pipe1_rf_waddr_rd_o = pipe1_pkt.dec.rf_waddr_rd;
    assign pipe1_rn_pdst_o = pipe1_writes_rd ? pipe1_pkt.rn.pdst : '0;
    assign pipe1_rob_valid_o = pipe1_fire && pipe1_pkt.rn.rob_valid;
    assign pipe1_rob_idx_o = pipe1_pkt.rn.rob_idx;
    assign pipe1_pc_o = pipe1_pkt.dec.pc;
    assign pipe1_instr_o = pipe1_pkt.dec.instr;

    integer rd_i;
    integer wr_i;
    always_comb begin
        for (rd_i = 0; rd_i < IQ_DEPTH; rd_i = rd_i + 1) begin
            iq_next[rd_i] = '0;
        end
        wr_i = 0;
        for (rd_i = 0; rd_i < IQ_DEPTH; rd_i = rd_i + 1) begin
            if ((rd_i < iq_count_q) &&
                !(pipe0_dequeue && (rd_i == 0)) &&
                !(pipe1_fire && (rd_i[IQ_INDEX_WIDTH-1:0] == pipe1_sel_idx))) begin
                iq_next[wr_i] = iq_q[rd_i];
                wr_i = wr_i + 1;
            end
        end
        if (enqueue0_fire && (wr_i < IQ_DEPTH)) begin
            iq_next[wr_i] = id_issue_pair_i.slot0;
            iq_next[wr_i].rn.pdst_valid = slot0_in_writes_rd;
            wr_i = wr_i + 1;
        end
        if (enqueue1_fire && (wr_i < IQ_DEPTH)) begin
            iq_next[wr_i] = id_issue_pair_i.slot1;
            iq_next[wr_i].rn.pdst_valid = slot1_in_writes_rd;
            wr_i = wr_i + 1;
        end
        iq_count_next = wr_i[IQ_COUNT_WIDTH-1:0];
    end

    initial begin
        perf_id_decode_valid = '0;
        perf_id_issue_accept = '0;
        perf_id_issue_fire = '0;
        perf_id_issue_slot_valid = '0;
        perf_id_issue_no_fire = '0;
        perf_id_issue_wait_block = '0;
        perf_id_wait_rs1 = '0;
        perf_id_wait_rs2 = '0;
        perf_id_wait_alu_ready_next_rs1 = '0;
        perf_id_wait_alu_ready_next_rs2 = '0;
        perf_id_wait_lsu_fwd_rs1 = '0;
        perf_id_wait_lsu_fwd_rs2 = '0;
        perf_id_wait_wb_fwd_rs1 = '0;
        perf_id_wait_wb_fwd_rs2 = '0;
        perf_id_wait_prf_ready_rs1 = '0;
        perf_id_wait_prf_ready_rs2 = '0;
        perf_id_skid_valid = '0;
        perf_id_skid_fill = '0;
        perf_id_skid_drain = '0;
        perf_id_skid_full_stall = '0;
        perf_id_frontend_stall = '0;
        perf_ri_slot0_valid = '0;
        perf_ri_slot1_valid = '0;
        perf_ri_slot0_ready = '0;
        perf_ri_slot1_ready = '0;
        perf_ri_fire_slot0 = '0;
        perf_ri_fire_slot1_bypass = '0;
        perf_ri_slot1_block_raw = '0;
        perf_ri_slot1_block_waw = '0;
        perf_ri_slot1_block_ctrl = '0;
        perf_ri_slot1_block_mem = '0;
        perf_ri_slot1_block_unsupported = '0;
        perf_ri_slot1_ready_when_slot0_blocked = '0;
        perf_ri_slot1_ready_when_slot0_ready = '0;
        perf_ri_slot1_fire_blocked_by_single_issue = '0;
        perf_ri_slot1_fire_blocked_by_operand_port = '0;
        perf_ri_slot1_fire_blocked_by_wb_order = '0;
        perf_ri_bypass_flush_killed = '0;
        perf_di_pipe0_fire = '0;
        perf_di_pipe1_fire = '0;
        perf_di_pair_fire = '0;
        perf_di_pair_simple_alu = '0;
        perf_di_pipe1_killed_flush = '0;
        perf_di_pipe1_block_stall_recheck = '0;
        perf_di_pipe1_block_resbuf_full = '0;
        perf_di_pipe1_block_alu_fifo_full = '0;
        perf_di_pipe1_block_pending_recheck = '0;
        perf_di_pipe1_block_timing_guard = '0;
        perf_di_pipe1_operand_block_rs1 = '0;
        perf_di_pipe1_operand_block_rs2 = '0;
        perf_di_pipe1_operand_block_both = '0;
        perf_di_pipe1_operand_block_from1 = '0;
        perf_di_pipe1_operand_block_from2 = '0;
        perf_di_pipe1_operand_block_recoverable = '0;
        perf_di_pipe1_alt2_when_from1_block_safe = '0;
        perf_di_pipe1_alt2_when_from1_block_ready = '0;
        perf_di_pipe1_alt2_when_recoverable_safe = '0;
        perf_di_pipe1_alt2_when_recoverable_ready = '0;
        perf_dual_cycles_with_pair_fire = '0;
        perf_dual_extra_instret_pipe1 = '0;
        perf_dual_pipe1_squashed = '0;
        perf_ds_cycles = '0;
        perf_ds_pipe0_valid = '0;
        perf_ds_pipe0_ready = '0;
        perf_ds_pipe1_valid = '0;
        perf_ds_pipe1_simple_alu = '0;
        perf_ds_safe_candidate = '0;
        perf_ds_safe_when_pipe0_ready = '0;
        perf_ds_safe_when_pipe0_blocked = '0;
        perf_ds_block_pipe1_unsupported = '0;
        perf_ds_block_raw_pipe0 = '0;
        perf_ds_block_waw_pipe0 = '0;
        perf_ds_block_pending_rs1 = '0;
        perf_ds_block_pending_rs2 = '0;
        perf_ds_block_ctrl = '0;
        perf_ds_block_mem = '0;
        perf_ds_block_csr_sys = '0;
        perf_ds_block_flush = '0;
        perf_ds_block_wb_port = '0;
        perf_ds_block_forward_complex = '0;
        perf_p1sh_valid_cycles = '0;
        perf_p1sh_simple_alu = '0;
        perf_p1sh_safe_cand = '0;
        perf_p1sh_block_raw_pair0 = '0;
        perf_p1sh_block_waw_pair0 = '0;
        perf_p1sh_block_pending_rs = '0;
        perf_p1sh_block_ctrl_mem = '0;
        perf_uopq_occ_0 = '0;
        perf_uopq_occ_1 = '0;
        perf_uopq_occ_2 = '0;
        perf_uopq_occ_3 = '0;
        perf_uopq_occ_4 = '0;
        perf_uopq_p1_safe_1 = '0;
        perf_uopq_p1_safe_2 = '0;
        perf_uopq_p1_safe_3 = '0;
        perf_uopq_block_older_ctrl_mem = '0;
        perf_uopq_block_raw_older = '0;
        perf_uopq_block_waw_older = '0;
        perf_uopq_p1_fire_from_1 = '0;
        perf_uopq_p1_fire_from_2 = '0;
        perf_uopq_p1_fire_from_3 = '0;
        perf_uopq_p1_fire_when_p0_ready = '0;
        perf_uopq_p1_fire_when_p0_blocked = '0;
        perf_uopq_p1_fire_when_p0_empty = '0;
        perf_uopq_p1_block_older_ctrl_mem = '0;
        perf_uopq_p1_block_raw_older = '0;
        perf_uopq_p1_block_waw_older = '0;
        perf_uopq_p1_block_commit_order = '0;
        perf_uopq_p1_block_p0_bjp = '0;
        perf_uopq_p1_block_p0_load = '0;
        perf_uopq_p1_block_p0_store = '0;
        perf_uopq_p1_block_p0_csr_sys = '0;
        perf_uopq_p1_block_p0_bitmanip = '0;
        perf_uopq_p1_block_p0_other = '0;
        perf_uopq_p1_block_p0_other_invalid = '0;
        perf_uopq_p1_block_p0_other_no_alu_mul = '0;
        perf_uopq_p1_block_p0_invalid_issue_accept = '0;
        perf_uopq_p1_block_p0_invalid_skid = '0;
        perf_uopq_p1_block_p0_invalid_uopq2_safe = '0;
        perf_uopq_p1_empty_base = '0;
        perf_uopq_p1_empty_supported = '0;
        perf_uopq_p1_empty_operands_ready = '0;
        perf_uopq_p1_empty_block_younger = '0;
        perf_uopq_p1_empty_block_ready_allow = '0;
        perf_uopq_p1_empty_block_pending_rd = '0;
        perf_uopq_p1_empty_block_resbuf = '0;
        perf_uopq_p1_blocked_base = '0;
        perf_uopq_p1_blocked_supported = '0;
        perf_uopq_p1_blocked_p0_safe = '0;
        perf_uopq_p1_blocked_operands_ready = '0;
        perf_uopq_p1_blocked_block_younger = '0;
        perf_uopq_p1_blocked_block_ready_allow = '0;
        perf_uopq_p1_blocked_block_pending_rd = '0;
        perf_uopq_p1_blocked_block_resbuf = '0;
        perf_uopq_p1_blocked_unsup_any_uop = '0;
        perf_uopq_p1_blocked_unsup_shadow_alu = '0;
        perf_uopq_p1_blocked_unsup_shift = '0;
        perf_uopq_p1_blocked_unsup_x0_rs1 = '0;
        perf_uopq_p1_blocked_unsup_lui_auipc = '0;
        perf_uopq_p1_blocked_unsup_relax_ready = '0;
        perf_uopq_p1_blocked_unsup_relax_fire_safe = '0;
        perf_uopq_p1_blocked_unsup_relax_shift_safe = '0;
        perf_uopq_p1_blocked_unsup_relax_x0_safe = '0;
        perf_uopq_p1_blocked_unsup_relax_lui_auipc_safe = '0;
        perf_uopq_p1_block_younger_flush = '0;
        perf_uopq_p1_block_young_uopq2 = '0;
        perf_uopq_p1_block_young_ifid = '0;
        perf_uopq_p1_block_ifid_bjp = '0;
        perf_uopq_p1_block_ifid_load = '0;
        perf_uopq_p1_block_ifid_store = '0;
        perf_uopq_p1_block_ifid_mul = '0;
        perf_uopq_p1_block_ifid_csr_sys = '0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perf_id_decode_valid <= '0;
            perf_id_issue_accept <= '0;
            perf_id_issue_fire <= '0;
            perf_id_issue_slot_valid <= '0;
            perf_id_issue_no_fire <= '0;
            perf_id_issue_wait_block <= '0;
            perf_id_wait_rs1 <= '0;
            perf_id_wait_rs2 <= '0;
            perf_id_frontend_stall <= '0;
            perf_ri_slot0_valid <= '0;
            perf_ri_slot1_valid <= '0;
            perf_ri_slot0_ready <= '0;
            perf_ri_slot1_ready <= '0;
            perf_ri_fire_slot0 <= '0;
            perf_ri_fire_slot1_bypass <= '0;
            perf_ri_slot1_ready_when_slot0_blocked <= '0;
            perf_ri_slot1_ready_when_slot0_ready <= '0;
            perf_di_pipe0_fire <= '0;
            perf_di_pipe1_fire <= '0;
            perf_di_pair_fire <= '0;
            perf_di_pair_simple_alu <= '0;
            perf_dual_cycles_with_pair_fire <= '0;
            perf_dual_extra_instret_pipe1 <= '0;
            perf_ds_cycles <= '0;
            perf_ds_pipe0_valid <= '0;
            perf_ds_pipe0_ready <= '0;
            perf_ds_pipe1_valid <= '0;
            perf_ds_pipe1_simple_alu <= '0;
            perf_uopq_occ_0 <= '0;
            perf_uopq_occ_1 <= '0;
            perf_uopq_occ_2 <= '0;
            perf_uopq_occ_3 <= '0;
            perf_uopq_occ_4 <= '0;
            perf_uopq_p1_fire_from_1 <= '0;
            perf_uopq_p1_fire_from_2 <= '0;
            perf_uopq_p1_fire_from_3 <= '0;
            perf_uopq_p1_fire_when_p0_ready <= '0;
            perf_uopq_p1_fire_when_p0_blocked <= '0;
            perf_uopq_p1_fire_when_p0_empty <= '0;
            perf_uopq_p1_block_older_ctrl_mem <= '0;
        end else begin
            perf_id_decode_valid <= perf_id_decode_valid + (slot0_in_valid ? 32'd1 : 32'd0);
            perf_id_issue_accept <= perf_id_issue_accept + (enqueue0_fire ? 32'd1 : 32'd0);
            perf_id_issue_fire <= perf_id_issue_fire + (pipe0_fire ? 32'd1 : 32'd0);
            perf_id_issue_slot_valid <= perf_id_issue_slot_valid + (pipe0_valid ? 32'd1 : 32'd0);
            perf_id_issue_no_fire <= perf_id_issue_no_fire + ((pipe0_valid && !pipe0_fire) ? 32'd1 : 32'd0);
            perf_id_issue_wait_block <= perf_id_issue_wait_block + ((pipe0_valid && !pipe0_operands_ready) ? 32'd1 : 32'd0);
            perf_id_wait_rs1 <= perf_id_wait_rs1 + (issue_wait_rs1_ff ? 32'd1 : 32'd0);
            perf_id_wait_rs2 <= perf_id_wait_rs2 + (issue_wait_rs2_ff ? 32'd1 : 32'd0);
            perf_id_frontend_stall <= perf_id_frontend_stall + (issue_frontend_stall_o ? 32'd1 : 32'd0);
            perf_ri_slot0_valid <= perf_ri_slot0_valid + (pipe0_valid ? 32'd1 : 32'd0);
            perf_ri_slot1_valid <= perf_ri_slot1_valid + (pipe1_sel_valid ? 32'd1 : 32'd0);
            perf_ri_slot0_ready <= perf_ri_slot0_ready + ((pipe0_valid && pipe0_operands_ready) ? 32'd1 : 32'd0);
            perf_ri_slot1_ready <= perf_ri_slot1_ready + (pipe1_sel_valid ? 32'd1 : 32'd0);
            perf_ri_fire_slot0 <= perf_ri_fire_slot0 + (pipe0_fire ? 32'd1 : 32'd0);
            perf_ri_fire_slot1_bypass <= perf_ri_fire_slot1_bypass + (pipe1_fire ? 32'd1 : 32'd0);
            perf_ri_slot1_ready_when_slot0_blocked <=
                perf_ri_slot1_ready_when_slot0_blocked +
                ((pipe1_sel_valid && !pipe0_fire) ? 32'd1 : 32'd0);
            perf_ri_slot1_ready_when_slot0_ready <=
                perf_ri_slot1_ready_when_slot0_ready +
                ((pipe1_sel_valid && pipe0_fire) ? 32'd1 : 32'd0);
            perf_di_pipe0_fire <= perf_di_pipe0_fire + (pipe0_fire ? 32'd1 : 32'd0);
            perf_di_pipe1_fire <= perf_di_pipe1_fire + (pipe1_fire ? 32'd1 : 32'd0);
            perf_di_pair_fire <= perf_di_pair_fire + ((pipe0_fire && pipe1_fire) ? 32'd1 : 32'd0);
            perf_di_pair_simple_alu <= perf_di_pair_simple_alu + ((pipe0_fire && pipe1_fire) ? 32'd1 : 32'd0);
            perf_dual_cycles_with_pair_fire <=
                perf_dual_cycles_with_pair_fire + ((pipe0_fire && pipe1_fire) ? 32'd1 : 32'd0);
            perf_dual_extra_instret_pipe1 <=
                perf_dual_extra_instret_pipe1 + (pipe1_fire ? 32'd1 : 32'd0);
            perf_ds_cycles <= perf_ds_cycles + 32'd1;
            perf_ds_pipe0_valid <= perf_ds_pipe0_valid + (pipe0_valid ? 32'd1 : 32'd0);
            perf_ds_pipe0_ready <= perf_ds_pipe0_ready + ((pipe0_valid && pipe0_operands_ready) ? 32'd1 : 32'd0);
            perf_ds_pipe1_valid <= perf_ds_pipe1_valid + (pipe1_sel_valid ? 32'd1 : 32'd0);
            perf_ds_pipe1_simple_alu <= perf_ds_pipe1_simple_alu + (pipe1_sel_valid ? 32'd1 : 32'd0);
            perf_uopq_occ_0 <= perf_uopq_occ_0 + ((iq_count_q == 0) ? 32'd1 : 32'd0);
            perf_uopq_occ_1 <= perf_uopq_occ_1 + ((iq_count_q == 1) ? 32'd1 : 32'd0);
            perf_uopq_occ_2 <= perf_uopq_occ_2 + ((iq_count_q == 2) ? 32'd1 : 32'd0);
            perf_uopq_occ_3 <= perf_uopq_occ_3 + ((iq_count_q == 3) ? 32'd1 : 32'd0);
            perf_uopq_occ_4 <= perf_uopq_occ_4 + ((iq_count_q >= 4) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_from_1 <=
                perf_uopq_p1_fire_from_1 + ((pipe1_fire && (pipe1_sel_idx == 1)) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_from_2 <=
                perf_uopq_p1_fire_from_2 + ((pipe1_fire && (pipe1_sel_idx == 2)) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_from_3 <=
                perf_uopq_p1_fire_from_3 + ((pipe1_fire && (pipe1_sel_idx >= 3)) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_when_p0_ready <=
                perf_uopq_p1_fire_when_p0_ready + ((pipe1_fire && pipe0_fire) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_when_p0_blocked <=
                perf_uopq_p1_fire_when_p0_blocked + ((pipe1_fire && pipe0_valid && !pipe0_fire) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_when_p0_empty <=
                perf_uopq_p1_fire_when_p0_empty + ((pipe1_fire && !pipe0_valid) ? 32'd1 : 32'd0);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        integer q_i;
        if (!rst_n) begin
            iq_count_q <= '0;
            for (q_i = 0; q_i < IQ_DEPTH; q_i = q_i + 1) begin
                iq_q[q_i] <= '0;
            end
        end else if (flush_id_i) begin
            iq_count_q <= '0;
            for (q_i = 0; q_i < IQ_DEPTH; q_i = q_i + 1) begin
                iq_q[q_i] <= '0;
            end
        end else begin
            iq_count_q <= iq_count_next;
            for (q_i = 0; q_i < IQ_DEPTH; q_i = q_i + 1) begin
                iq_q[q_i] <= iq_next[q_i];
            end
        end
    end

    wire unused_inputs = ^{
        bubble_id_i,
        gpr_pending_i,
        wb_fwd_valid_i,
        wb_fwd_addr_i,
        wb_fwd_data_i
    };
    wire unused_keep = unused_inputs;

endmodule
