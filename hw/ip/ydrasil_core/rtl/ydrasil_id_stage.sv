
module ydrasil_id_stage
import ydrasil_pkg::*;
 #(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            stall_id_i,
    input  wire                            bubble_id_i,
    input  wire                            flush_id_i,

    // IF/ID input  
    input  wire [DATA_WIDTH-1:0]           if_id_pc_i,
    input  wire [DATA_WIDTH-1:0]           if_id_instr_i,
    input  wire                            if_id_pred_hit_i,
    input  wire                            if_id_pred_taken_i,
    input  wire [DATA_WIDTH-1:0]           if_id_pred_target_i,
    input  wire [1:0]                      if_id_pred_counter_i,
    input  wire [DATA_WIDTH-1:0]           if_id_pred_bht_index_i,
    input  wire                            if_id_pred_l0_taken_i,
    input  wire                            if_id_valid_i,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,
    output wire [4:0]                      pipe1_rf_addr_rs1_o,
    output wire [4:0]                      pipe1_rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           pipe1_rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_rf_rdata_rs2_i,
    input  wire                            wb_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           wb_fwd_data_i,
    input  wire                            lsu_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           lsu_fwd_data_i,
    input  wire                            alu_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] alu_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           alu_fwd_data_i,
    input  wire                            pipe1_alu_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pipe1_alu_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_alu_fwd_data_i,
    input  wire                            prf_rs1_ready_i,
    input  wire                            prf_rs2_ready_i,
    input  wire [DATA_WIDTH-1:0]           prf_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]           prf_rs2_data_i,
    input  wire                            pipe1_prf_rs1_ready_i,
    input  wire                            pipe1_prf_rs2_ready_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_prf_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_prf_rs2_data_i,
    input  wire                            pipe1_rename_ready_i,
    input  wire [5:0]                      rn_if_rs1_psrc_i,
    input  wire [5:0]                      rn_if_rs2_psrc_i,
    input  wire [5:0]                      rn_if_pdst_i,
    input  wire                            rs1_issue_alu_ready_next_i,
    input  wire                            rs2_issue_alu_ready_next_i,
`ifndef SYNTHESIS
    input  wire                            rs1_issue_alu_stable_bypass_i,
    input  wire                            rs2_issue_alu_stable_bypass_i,
`endif
    input  wire                            ready_issue_allow_i,
    input  wire [ydrasil_pkg::REGS_NUM-1:0] gpr_pending_i,
    input  wire                            pipe1_resbuf_full_i,
    output wire                            issue_frontend_stall_o,

    // Dispatch to EX   
    // output wire                            alu_valid_o,
    output wire [DATA_WIDTH-1:0]           operand_a_o,
    output wire [DATA_WIDTH-1:0]           operand_b_o,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      operator_o, // 统一的ALU操作信息信号

    output wire [DATA_WIDTH-1:0]           bt_a_operand_o,
    output wire [DATA_WIDTH-1:0]           bt_b_operand_o,

    output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   operator_lsu_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_rs2_data_o, // 操作类型信号
    output wire [DATA_WIDTH-1:0]           id_lsu_addr_o,
    output wire                            id_lsu_addr_is_dtcm_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_store_data_o,
    output wire [3:0]                      id_lsu_store_mask_o,

    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    output wire                            id_ex_jalr_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rs1_addr_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rs2_addr_o,
    output wire                            id_ctrl_rs1_ren_o,
    output wire                            id_ctrl_rs2_ren_o,
    output wire                            id_ctrl_rd_wen_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rd_addr_o,
    output wire                            id_ctrl_lsu_req_o,
`ifndef SYNTHESIS
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] id_ctrl_operator_type_o,
`endif

    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	    id_csr_raddr_o,  
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	    id_ex_csr_waddr_o,  
    output wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_o,
    output wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]    id_op_sys_info_o,

    output wire [DATA_WIDTH-1:0]           id_instr_addr_o, // 当前指令地址，供CLINT使用
    output wire                            id_fence_i_o,
    output wire                            id_ex_pred_hit_o,
    output wire                            id_ex_pred_taken_o,
    output wire [DATA_WIDTH-1:0]           id_ex_pred_target_o,
    output wire [1:0]                      id_ex_pred_counter_o,
    output wire [DATA_WIDTH-1:0]           id_ex_pred_bht_index_o,
    output wire                            id_ex_pred_l0_taken_o,
    output wire                            id_ex_valid_o,
    // Generic writeback information
    output wire                            id_alu_rf_wen_rd_o,
    output wire [4:0]                      id_rf_waddr_rd_o,
    output wire [5:0]                      id_rn_pdst_o,
    output wire [5:0]                      id_ctrl_rs1_psrc_o,
    output wire [5:0]                      id_ctrl_rs2_psrc_o,
    output wire [5:0]                      id_ctrl_pdst_o,
    output wire                            pipe1_ctrl_rs1_ren_o,
    output wire                            pipe1_ctrl_rs2_ren_o,
    output wire [5:0]                      pipe1_ctrl_rs1_psrc_o,
    output wire [5:0]                      pipe1_ctrl_rs2_psrc_o,
    output wire                            rn_alloc_valid_o,
    output wire [4:0]                      rn_alloc_rd_addr_o,
    output wire                            rn_if_rd_valid_o,
`ifndef SYNTHESIS
    output wire                            id_alu_stable_valid_o,
    output wire [4:0]                      id_alu_stable_addr_o,
    output wire [DATA_WIDTH-1:0]           id_alu_stable_data_o,
`endif

    output wire                            pipe1_issue_valid_o,
    output wire [DATA_WIDTH-1:0]           pipe1_operand_a_o,
    output wire [DATA_WIDTH-1:0]           pipe1_operand_b_o,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_operator_o,
    output wire                            pipe1_rf_wen_rd_o,
    output wire [4:0]                      pipe1_rf_waddr_rd_o,
    output wire [5:0]                      pipe1_rn_pdst_o,
    output wire [DATA_WIDTH-1:0]           pipe1_pc_o,
    output wire [DATA_WIDTH-1:0]           pipe1_instr_o
`ifndef SYNTHESIS
    ,
    output wire                            commit_trace_alloc_valid_o,
    output wire [DATA_WIDTH-1:0]           commit_trace_alloc_pc_o,
    output wire [DATA_WIDTH-1:0]           commit_trace_alloc_instr_o
`endif


);
`ifdef YDRASIL_ENABLE_PIPE1_REAL
`ifdef YDRASIL_PIPE1_REAL_MODE
    localparam int PIPE1_REAL_MODE = `YDRASIL_PIPE1_REAL_MODE;
`else
    localparam int PIPE1_REAL_MODE = 1;
`endif
`else
    localparam int PIPE1_REAL_MODE = 0;
`endif

    wire [4:0]                           rf_raddr_rs1;
    wire [4:0]                           rf_raddr_rs2;
    wire                                 rf_ren_rs1;
    wire                                 rf_ren_rs2;

    wire [4:0]                           rf_waddr_rd;
    wire                                 rf_wen_rd;

    reg [4:0]                           rf_waddr_rd_ff;
    reg                                 rf_wen_rd_ff;

    wire [DATA_WIDTH-1:0]                imm_i;
    wire                                 operand_b_rs_sel;
    wire                                 operand_a_pc_sel;
    wire                                 operand_a_imm_sel;
    wire                                 bt_a_rs_sel;

    reg [DATA_WIDTH-1:0]                id_lsu_rs2_data_ff;
    reg [DATA_WIDTH-1:0]                id_lsu_addr_ff;
    reg                                 id_lsu_addr_is_dtcm_ff;
    reg [DATA_WIDTH-1:0]                id_lsu_store_data_ff;
    reg [3:0]                           id_lsu_store_mask_ff;

    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]      operator_type;
    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]       operator_type_ff;

    wire [DATA_WIDTH-1:0]                operand_a;
    wire [DATA_WIDTH-1:0]                operand_b;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]           operator;


    reg [DATA_WIDTH-1:0]                operand_a_ff;
    reg [DATA_WIDTH-1:0]                operand_b_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]           operator_ff;

    wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]        operator_lsu;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]         operator_lsu_ff;

    wire [DATA_WIDTH-1:0]                bt_a_operand;
    wire [DATA_WIDTH-1:0]                bt_b_operand;
    reg [DATA_WIDTH-1:0]                 bt_a_operand_ff;
    reg [DATA_WIDTH-1:0]                 bt_b_operand_ff;
    reg [DATA_WIDTH-1:0]                 id_instr_addr_ff;
    reg                                  id_ex_jalr_ff;
    reg                                  id_ex_pred_hit_ff;
    reg                                  id_ex_pred_taken_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_target_ff;
    reg [1:0]                            id_ex_pred_counter_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_bht_index_ff;
    reg                                  id_ex_pred_l0_taken_ff;
    reg                                  id_ex_valid_ff;
    reg                                  id_fence_i_ff;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr;
   
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr;
	wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]  csr_op_info;

    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr_ff;

    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr_ff; 
	reg [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]  csr_op_info_ff;

    wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]  sys_op_info;
    reg [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   sys_op_info_ff;
    wire                            operand_b_jump_sel;
    wire                            id_fence_i;

    wire                            id_advance;

    reg                             skid_valid_ff;
    reg [DATA_WIDTH-1:0]            skid_pc_ff;
    reg [DATA_WIDTH-1:0]            skid_instr_ff;
    reg                             skid_pred_hit_ff;
    reg                             skid_pred_taken_ff;
    reg [DATA_WIDTH-1:0]            skid_pred_target_ff;
    reg [1:0]                       skid_pred_counter_ff;
    reg [DATA_WIDTH-1:0]            skid_pred_bht_index_ff;
    reg                             skid_pred_l0_taken_ff;
    reg [4:0]                       skid_rf_raddr_rs1_ff;
    reg [4:0]                       skid_rf_raddr_rs2_ff;
    reg                             skid_rf_ren_rs1_ff;
    reg                             skid_rf_ren_rs2_ff;
    reg [4:0]                       skid_rf_waddr_rd_ff;
    reg                             skid_rf_wen_rd_ff;
    reg [DATA_WIDTH-1:0]            skid_imm_ff;
    reg                             skid_operand_b_rs_sel_ff;
    reg                             skid_operand_a_pc_sel_ff;
    reg                             skid_operand_a_imm_sel_ff;
    reg                             skid_bt_a_rs_sel_ff;
    reg                             skid_operand_b_jump_sel_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]       skid_operator_ff;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]    skid_operator_lsu_ff;
    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]  skid_operator_type_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       skid_csr_reg_raddr_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       skid_csr_ex_waddr_ff;
    reg [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    skid_csr_op_info_ff;
    reg [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]    skid_sys_op_info_ff;
    reg                             skid_fence_i_ff;
    reg [5:0]                       skid_rn_rs1_psrc_ff;
    reg [5:0]                       skid_rn_rs2_psrc_ff;
    reg [5:0]                       skid_rn_pdst_ff;
    reg                             skid_rn_pdst_valid_ff;

    reg                             issue_valid_ff;
    reg                             issue_wait_rs1_ff;
    reg                             issue_wait_rs2_ff;
    reg [DATA_WIDTH-1:0]            issue_pc_ff;
    reg                             issue_pred_hit_ff;
    reg                             issue_pred_taken_ff;
    reg [DATA_WIDTH-1:0]            issue_pred_target_ff;
    reg [1:0]                       issue_pred_counter_ff;
    reg [DATA_WIDTH-1:0]            issue_pred_bht_index_ff;
    reg                             issue_pred_l0_taken_ff;
    reg [4:0]                       issue_rf_raddr_rs1_ff;
    reg [4:0]                       issue_rf_raddr_rs2_ff;
    reg                             issue_rf_ren_rs1_ff;
    reg                             issue_rf_ren_rs2_ff;
    reg [4:0]                       issue_rf_waddr_rd_ff;
    reg                             issue_rf_wen_rd_ff;
    reg [DATA_WIDTH-1:0]            issue_imm_ff;
    reg                             issue_operand_b_rs_sel_ff;
    reg                             issue_operand_a_pc_sel_ff;
    reg                             issue_operand_a_imm_sel_ff;
    reg                             issue_bt_a_rs_sel_ff;
    reg                             issue_operand_b_jump_sel_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]       issue_operator_ff;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]    issue_operator_lsu_ff;
    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]  issue_operator_type_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       issue_csr_reg_raddr_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       issue_csr_ex_waddr_ff;
    reg [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    issue_csr_op_info_ff;
    reg [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]    issue_sys_op_info_ff;
    reg                             issue_fence_i_ff;
    reg [5:0]                       issue_rn_rs1_psrc_ff;
    reg [5:0]                       issue_rn_rs2_psrc_ff;
    reg [5:0]                       issue_rn_pdst_ff;
    reg                             issue_rn_pdst_valid_ff;
    reg [5:0]                       id_rn_pdst_ff;
`ifndef SYNTHESIS
    reg                             alu_stable_valid_ff;
    reg [4:0]                       alu_stable_addr_ff;
    reg [DATA_WIDTH-1:0]            alu_stable_data_ff;
`endif

    wire [DATA_WIDTH-1:0]            decode_pc;
    wire [DATA_WIDTH-1:0]            decode_instr;
    wire                             decode_pred_hit;
    wire                             decode_pred_taken;
    wire [DATA_WIDTH-1:0]            decode_pred_target;
    wire [1:0]                       decode_pred_counter;
    wire [DATA_WIDTH-1:0]            decode_pred_bht_index;
    wire                             decode_pred_l0_taken;
    wire                             decode_valid;
    wire                             issue_wait_rs1_ready;
    wire                             issue_wait_rs2_ready;
    wire                             issue_wait_block;
    wire                             issue_slot0_fire;
    wire                             issue_slot1_bypass_fire;
    wire                             pipe1_dual_fire;
    wire                             pair1_fire;
    wire                             pipe1_dual_supported;
    wire                             pipe1_dual_operands_ready;
    wire                             pipe1_dual_raw_pipe0;
    wire                             pipe1_dual_waw_pipe0;
    wire                             pipe1_dual_war_pipe0;
    wire                             pipe1_dual_pending_rd;
    wire                             pipe1_younger_flush_risk;
    wire                             pipe1_dual_pipe0_safe;
    wire                             pipe1_dual_rs1_ready;
    wire                             pipe1_dual_rs2_ready;
    wire                             pipe1_dual_rs1_alu_fwd;
    wire                             pipe1_dual_rs2_alu_fwd;
    wire                             pipe1_dual_rs1_p1alu_fwd;
    wire                             pipe1_dual_rs2_p1alu_fwd;
    wire                             pipe1_dual_rs1_wb_fwd;
    wire                             pipe1_dual_rs2_wb_fwd;
    wire [DATA_WIDTH-1:0]            pipe1_dual_rs1_data;
    wire [DATA_WIDTH-1:0]            pipe1_dual_rs2_data;
    wire [DATA_WIDTH-1:0]            pipe1_dual_operand_a;
    wire [DATA_WIDTH-1:0]            pipe1_dual_operand_b;
    wire                             pair1_refill_dep_p1;
    wire                             pair1_refill_dep_p0;
    wire                             pair1_refill_srcs_ready;
    wire                             pair1_refill_simple_alu;
    wire                             pair1_refill_direct;
    wire                             issue_fire;
    wire                             issue_accept;
    wire                             issue_load_from_skid;
    wire                             skid_fill;
    wire                             skid_drain;
`ifndef SYNTHESIS
    wire                             issue_alu_stable_candidate;
    wire [DATA_WIDTH-1:0]            issue_alu_stable_result;
`endif
    wire                             ri_slot1_valid;
    wire                             ri_slot1_supported;
    wire                             ri_slot1_block_raw;
    wire                             ri_slot1_block_waw;
    wire                             ri_slot1_block_war;
    wire                             ri_slot1_block_ctrl;
    wire                             ri_slot1_block_mem;
    wire                             ri_slot1_block_unsupported;
    wire                             ri_slot1_block_old_unsupported;
    wire                             ri_slot1_block_rs1_pending;
    wire                             ri_slot1_block_rs2_pending;
    wire                             ri_slot1_block_rd_pending;
    wire                             ri_slot1_ready;
    wire                             ri_slot1_ready_when_slot0_blocked;
    wire                             ri_slot1_ready_when_slot0_ready;
    wire                             ri_slot1_fire_blocked_by_single_issue;
    wire                             ri_slot1_fire_blocked_by_wb_order;
    wire                             ri_bypass_flush_killed;
    wire [4:0]                       selected_rf_raddr_rs1;
    wire [4:0]                       selected_rf_raddr_rs2;
    wire                             selected_rf_ren_rs1;
    wire                             selected_rf_ren_rs2;
    wire [4:0]                       selected_rf_waddr_rd;
    wire                             selected_rf_wen_rd;
    wire [DATA_WIDTH-1:0]            selected_pc;
    wire [DATA_WIDTH-1:0]            selected_imm;
    wire                             selected_operand_b_rs_sel;
    wire                             selected_operand_a_pc_sel;
    wire                             selected_operand_a_imm_sel;
    wire                             selected_bt_a_rs_sel;
    wire                             selected_operand_b_jump_sel;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]       selected_operator;
    wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]    selected_operator_lsu;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]  selected_operator_type;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       selected_csr_reg_raddr;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       selected_csr_ex_waddr;
    wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    selected_csr_op_info;
    wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]    selected_sys_op_info;
    wire                             selected_fence_i;
    wire [5:0]                       selected_rn_rs1_psrc;
    wire [5:0]                       selected_rn_rs2_psrc;
    wire [5:0]                       selected_rn_pdst;
    wire                             selected_rn_pdst_valid;
    wire                             selected_pred_hit;
    wire                             selected_pred_taken;
    wire [DATA_WIDTH-1:0]            selected_pred_target;
    wire [1:0]                       selected_pred_counter;
    wire [DATA_WIDTH-1:0]            selected_pred_bht_index;
    wire                             selected_pred_l0_taken;
    wire [4:0]                       slot1_rf_raddr_rs1;
    wire [4:0]                       slot1_rf_raddr_rs2;
    wire                             slot1_rf_ren_rs1;
    wire                             slot1_rf_ren_rs2;
    wire [4:0]                       slot1_rf_waddr_rd;
    wire                             slot1_rf_wen_rd;
    wire [DATA_WIDTH-1:0]            slot1_imm;
    wire                             slot1_operand_b_rs_sel;
    wire                             slot1_operand_a_pc_sel;
    wire                             slot1_operand_a_imm_sel;
    wire                             slot1_bt_a_rs_sel;
    wire                             slot1_operand_b_jump_sel;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]       slot1_operator;
    wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]    slot1_operator_lsu;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]  slot1_operator_type;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       slot1_csr_reg_raddr;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]       slot1_csr_ex_waddr;
    wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    slot1_csr_op_info;
    wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]    slot1_sys_op_info;
    wire                             slot1_fence_i;
    wire                             uopq0_valid;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq0_operator_type;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      uopq0_operator;
    wire                             uopq0_fence_i;
    wire                             uopq0_rf_wen_rd;
    wire [4:0]                       uopq0_rf_waddr_rd;
    wire                             uopq1_valid;
    wire [DATA_WIDTH-1:0]            uopq1_pc;
    wire [DATA_WIDTH-1:0]            uopq1_instr;
    wire [4:0]                       uopq1_rf_raddr_rs1;
    wire [4:0]                       uopq1_rf_raddr_rs2;
    wire                             uopq1_rf_ren_rs1;
    wire                             uopq1_rf_ren_rs2;
    wire [4:0]                       uopq1_rf_waddr_rd;
    wire                             uopq1_rf_wen_rd;
    wire [DATA_WIDTH-1:0]            uopq1_imm;
    wire                             uopq1_operand_b_rs_sel;
    wire                             uopq1_operand_a_pc_sel;
    wire                             uopq1_operand_a_imm_sel;
    wire                             uopq1_operand_b_jump_sel;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      uopq1_operator;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq1_operator_type;
    wire                             uopq1_fence_i;
    wire                             uopq2_valid;
    wire [DATA_WIDTH-1:0]            uopq2_pc;
    wire [DATA_WIDTH-1:0]            uopq2_instr;
    wire [4:0]                       uopq2_rf_raddr_rs1;
    wire [4:0]                       uopq2_rf_raddr_rs2;
    wire                             uopq2_rf_ren_rs1;
    wire                             uopq2_rf_ren_rs2;
    wire [4:0]                       uopq2_rf_waddr_rd;
    wire                             uopq2_rf_wen_rd;
    wire [DATA_WIDTH-1:0]            uopq2_imm;
    wire                             uopq2_operand_b_rs_sel;
    wire                             uopq2_operand_a_pc_sel;
    wire                             uopq2_operand_a_imm_sel;
    wire                             uopq2_operand_b_jump_sel;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      uopq2_operator;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq2_operator_type;
    wire                             uopq2_fence_i;
    wire                             pipe1_sel_from1;
    wire                             pipe1_sel_from2;
    wire [DATA_WIDTH-1:0]            pipe1_sel_pc;
    wire [DATA_WIDTH-1:0]            pipe1_sel_instr;
    wire [4:0]                       pipe1_sel_rf_raddr_rs1;
    wire [4:0]                       pipe1_sel_rf_raddr_rs2;
    wire                             pipe1_sel_rf_ren_rs1;
    wire                             pipe1_sel_rf_ren_rs2;
    wire [4:0]                       pipe1_sel_rf_waddr_rd;
    wire                             pipe1_sel_rf_wen_rd;
    wire [5:0]                       pipe1_sel_rs1_psrc;
    wire [5:0]                       pipe1_sel_rs2_psrc;
    wire [5:0]                       pipe1_sel_pdst;
    wire                             pipe1_sel_pdst_valid;
    wire [DATA_WIDTH-1:0]            pipe1_sel_imm;
    wire                             pipe1_sel_operand_b_rs_sel;
    wire                             pipe1_sel_operand_a_pc_sel;
    wire                             pipe1_sel_operand_a_imm_sel;
    wire                             pipe1_sel_operand_b_jump_sel;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      pipe1_sel_operator;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] pipe1_sel_operator_type;
    wire                             pipe1_uopq1_supported;
    wire                             pipe1_uopq2_supported;
    wire                             pipe1_uopq1_operands_ready;
    wire                             pipe1_uopq2_operands_ready;
    wire                             pipe1_uopq1_safe;
    wire                             pipe1_uopq2_safe;
    wire                             pipe1_p0_ready_context;
    wire                             pipe1_p0_blocked_context;
    wire                             pipe1_fire_from1;
    wire                             pipe1_fire_from2;

    reg [31:0]                       perf_id_decode_valid;
    reg [31:0]                       perf_id_issue_accept;
    reg [31:0]                       perf_id_issue_fire;
    reg [31:0]                       perf_id_issue_slot_valid;
    reg [31:0]                       perf_id_issue_no_fire;
    reg [31:0]                       perf_id_issue_wait_block;
    reg [31:0]                       perf_id_wait_rs1;
    reg [31:0]                       perf_id_wait_rs2;
    reg [31:0]                       perf_id_wait_alu_ready_next_rs1;
    reg [31:0]                       perf_id_wait_alu_ready_next_rs2;
    reg [31:0]                       perf_id_wait_lsu_fwd_rs1;
    reg [31:0]                       perf_id_wait_lsu_fwd_rs2;
    reg [31:0]                       perf_id_wait_wb_fwd_rs1;
    reg [31:0]                       perf_id_wait_wb_fwd_rs2;
    reg [31:0]                       perf_id_skid_valid;
    reg [31:0]                       perf_id_skid_fill;
    reg [31:0]                       perf_id_skid_drain;
    reg [31:0]                       perf_id_skid_full_stall;
    reg [31:0]                       perf_id_frontend_stall;
    reg [31:0]                       perf_ri_slot0_valid;
    reg [31:0]                       perf_ri_slot1_valid;
    reg [31:0]                       perf_ri_slot0_ready;
    reg [31:0]                       perf_ri_slot1_ready;
    reg [31:0]                       perf_ri_fire_slot0;
    reg [31:0]                       perf_ri_fire_slot1_bypass;
    reg [31:0]                       perf_ri_slot1_block_raw;
    reg [31:0]                       perf_ri_slot1_block_waw;
    reg [31:0]                       perf_ri_slot1_block_ctrl;
    reg [31:0]                       perf_ri_slot1_block_mem;
    reg [31:0]                       perf_ri_slot1_block_unsupported;
    reg [31:0]                       perf_ri_slot1_ready_when_slot0_blocked;
    reg [31:0]                       perf_ri_slot1_ready_when_slot0_ready;
    reg [31:0]                       perf_ri_slot1_fire_blocked_by_single_issue;
    reg [31:0]                       perf_ri_slot1_fire_blocked_by_operand_port;
    reg [31:0]                       perf_ri_slot1_fire_blocked_by_wb_order;
    reg [31:0]                       perf_ri_bypass_flush_killed;
    reg [31:0]                       perf_di_pipe0_fire;
    reg [31:0]                       perf_di_pipe1_fire;
    reg [31:0]                       perf_di_pair_fire;
    reg [31:0]                       perf_di_pair_simple_alu;
    reg [31:0]                       perf_di_pipe1_killed_flush;
    reg [31:0]                       perf_di_pipe1_block_stall_recheck;
    reg [31:0]                       perf_di_pipe1_block_resbuf_full;
    reg [31:0]                       perf_di_pipe1_block_alu_fifo_full;
    reg [31:0]                       perf_di_pipe1_block_pending_recheck;
    reg [31:0]                       perf_di_pipe1_block_timing_guard;
    reg [31:0]                       perf_dual_cycles_with_pair_fire;
    reg [31:0]                       perf_dual_extra_instret_pipe1;
    reg [31:0]                       perf_dual_pipe1_useful_commit;
    reg [31:0]                       perf_dual_pipe1_squashed;

    reg                              pipe1_issue_valid_ff;
    reg [DATA_WIDTH-1:0]             pipe1_operand_a_ff;
    reg [DATA_WIDTH-1:0]             pipe1_operand_b_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0] pipe1_operator_ff;
    reg                              pipe1_rf_wen_rd_ff;
    reg [4:0]                        pipe1_rf_waddr_rd_ff;
    reg [5:0]                        pipe1_rn_pdst_ff;
    reg [DATA_WIDTH-1:0]             pipe1_pc_ff;
    reg [DATA_WIDTH-1:0]             pipe1_instr_ff;

    wire [4:0]                       if_id_trace_rf_waddr_rd;
    wire                             if_id_trace_rf_wen_rd;
    wire [DATA_WIDTH-1:0]            if_id_trace_imm;
    wire                             if_id_trace_operand_b_rs_sel;
    wire                             if_id_trace_operand_a_pc_sel;
    wire                             if_id_trace_operand_a_imm_sel;
    wire                             if_id_trace_bt_a_rs_sel;
    wire                             if_id_trace_operand_b_jump_sel;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] if_id_trace_csr_reg_raddr;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] if_id_trace_csr_ex_waddr;
    wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] if_id_trace_csr_op_info;
    wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] if_id_trace_sys_op_info;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] if_id_trace_operator;
    wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] if_id_trace_operator_lsu;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] if_id_trace_operator_type;
    wire [4:0]                       if_id_trace_rf_raddr_rs1;
    wire [4:0]                       if_id_trace_rf_raddr_rs2;
    wire                             if_id_trace_rf_ren_rs1;
    wire                             if_id_trace_rf_ren_rs2;

`ifndef SYNTHESIS
    wire                             commit_trace_alloc_if_id;

    wire                             ds_pipe0_valid;
    wire                             ds_pipe0_ready;
    wire                             ds_pipe0_ctrl;
    wire                             ds_pipe0_mem;
    wire                             ds_pipe0_csr_sys;
    wire                             ds_pipe0_mul;
    wire                             ds_pipe0_no_side_effect;
    wire                             ds_pipe1_valid;
    wire                             ds_pipe1_simple_alu;
    wire                             ds_pipe1_unsupported;
    wire                             ds_pipe1_ctrl;
    wire                             ds_pipe1_mem;
    wire                             ds_pipe1_csr_sys;
    wire                             ds_pipe1_rd_valid;
    wire                             ds_block_raw_pipe0;
    wire                             ds_block_waw_pipe0;
    wire                             ds_block_pending_rs1;
    wire                             ds_block_pending_rs2;
    wire                             ds_block_ctrl;
    wire                             ds_block_mem;
    wire                             ds_block_csr_sys;
    wire                             ds_block_flush;
    wire                             ds_block_wb_port;
    wire                             ds_block_forward_complex;
    wire                             ds_shadow_safe_candidate;

    reg [31:0]                       perf_ds_cycles;
    reg [31:0]                       perf_ds_pipe0_valid;
    reg [31:0]                       perf_ds_pipe0_ready;
    reg [31:0]                       perf_ds_pipe1_valid;
    reg [31:0]                       perf_ds_pipe1_simple_alu;
    reg [31:0]                       perf_ds_safe_candidate;
    reg [31:0]                       perf_ds_safe_when_pipe0_ready;
    reg [31:0]                       perf_ds_safe_when_pipe0_blocked;
    reg [31:0]                       perf_ds_block_pipe1_unsupported;
    reg [31:0]                       perf_ds_block_raw_pipe0;
    reg [31:0]                       perf_ds_block_waw_pipe0;
    reg [31:0]                       perf_ds_block_pending_rs1;
    reg [31:0]                       perf_ds_block_pending_rs2;
    reg [31:0]                       perf_ds_block_ctrl;
    reg [31:0]                       perf_ds_block_mem;
    reg [31:0]                       perf_ds_block_csr_sys;
    reg [31:0]                       perf_ds_block_flush;
    reg [31:0]                       perf_ds_block_wb_port;
    reg [31:0]                       perf_ds_block_forward_complex;

    reg                              pair1_valid_ff;
    reg [DATA_WIDTH-1:0]             pair1_pc_ff;
    reg [DATA_WIDTH-1:0]             pair1_instr_ff;
    reg [31:0]                       pair1_seq_ff;
    reg [31:0]                       pair1_seq_next_ff;
    reg [4:0]                        pair1_rs1_ff;
    reg [4:0]                        pair1_rs2_ff;
    reg [4:0]                        pair1_rd_ff;
    reg                              pair1_rs1_ren_ff;
    reg                              pair1_rs2_ren_ff;
    reg                              pair1_rd_wen_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]      pair1_operator_ff;
    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] pair1_operator_type_ff;
    reg [DATA_WIDTH-1:0]             pair1_imm_ff;
    reg                              pair1_pred_hit_ff;
    reg                              pair1_pred_taken_ff;
    reg [DATA_WIDTH-1:0]             pair1_pred_target_ff;
    reg [1:0]                        pair1_pred_counter_ff;
    reg [DATA_WIDTH-1:0]             pair1_pred_bht_index_ff;
    reg                              pair1_pred_l0_taken_ff;
    wire                             p1sh_simple_alu;
    wire                             p1sh_block_raw_pair0;
    wire                             p1sh_block_waw_pair0;
    wire                             p1sh_block_pending_rs;
    wire                             p1sh_block_ctrl_mem;
    wire                             p1sh_safe_cand;
    reg [31:0]                       perf_p1sh_valid_cycles;
    reg [31:0]                       perf_p1sh_simple_alu;
    reg [31:0]                       perf_p1sh_safe_cand;
    reg [31:0]                       perf_p1sh_block_raw_pair0;
    reg [31:0]                       perf_p1sh_block_waw_pair0;
    reg [31:0]                       perf_p1sh_block_pending_rs;
    reg [31:0]                       perf_p1sh_block_ctrl_mem;

    reg [3:0]                        uopq_shadow_valid;
    reg [DATA_WIDTH-1:0]             uopq_shadow_pc [0:3];
    reg [DATA_WIDTH-1:0]             uopq_shadow_instr [0:3];
    reg [31:0]                       uopq_shadow_seq [0:3];
    reg [31:0]                       uopq_shadow_seq_next_ff;
    reg [4:0]                        uopq_shadow_rs1 [0:3];
    reg [4:0]                        uopq_shadow_rs2 [0:3];
    reg [4:0]                        uopq_shadow_rd [0:3];
    reg [3:0]                        uopq_shadow_rs1_ren;
    reg [3:0]                        uopq_shadow_rs2_ren;
    reg [3:0]                        uopq_shadow_rd_wen;
    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] uopq_shadow_optype [0:3];
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]      uopq_shadow_operator [0:3];
    reg [3:0]                        uopq_shadow_simple_alu;
    reg [3:0]                        uopq_shadow_ctrl;
    reg [3:0]                        uopq_shadow_mem;
    reg [3:0]                        uopq_shadow_csr_sys_fence;
    wire [3:1]                       uopq_shadow_raw_older;
    wire [3:1]                       uopq_shadow_waw_older;
    wire [3:1]                       uopq_shadow_older_ctrl_mem;
    wire [3:1]                       uopq_shadow_pending_rs;
    wire [3:1]                       uopq_shadow_p1_safe;
    wire [2:0]                       uopq_shadow_occupancy;
    reg [31:0]                       perf_uopq_occ_0;
    reg [31:0]                       perf_uopq_occ_1;
    reg [31:0]                       perf_uopq_occ_2;
    reg [31:0]                       perf_uopq_occ_3;
    reg [31:0]                       perf_uopq_occ_4;
    reg [31:0]                       perf_uopq_p1_safe_1;
    reg [31:0]                       perf_uopq_p1_safe_2;
    reg [31:0]                       perf_uopq_p1_safe_3;
    reg [31:0]                       perf_uopq_block_older_ctrl_mem;
    reg [31:0]                       perf_uopq_block_raw_older;
    reg [31:0]                       perf_uopq_block_waw_older;
    reg [31:0]                       perf_uopq_p1_fire_from_1;
    reg [31:0]                       perf_uopq_p1_fire_from_2;
    reg [31:0]                       perf_uopq_p1_fire_from_3;
    reg [31:0]                       perf_uopq_p1_fire_when_p0_ready;
    reg [31:0]                       perf_uopq_p1_fire_when_p0_blocked;
    reg [31:0]                       perf_uopq_p1_block_older_ctrl_mem;
    reg [31:0]                       perf_uopq_p1_block_raw_older;
    reg [31:0]                       perf_uopq_p1_block_waw_older;
    reg [31:0]                       perf_uopq_p1_block_commit_order;
`endif

`ifndef SYNTHESIS
    function automatic logic is_shadow_simple_alu(
        input logic [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] op_type,
        input logic [ydrasil_pkg::OPERATOR_WIDTH-1:0] op
    );
        begin
            is_shadow_simple_alu =
                op_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
                !op_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
                !op_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
                !op_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                !op_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
                !op_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
                !op_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
                !op_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
                (op[ydrasil_pkg::OP_ALU_ADD] |
                 op[ydrasil_pkg::OP_ALU_SUB] |
                 op[ydrasil_pkg::OP_ALU_SLT] |
                 op[ydrasil_pkg::OP_ALU_SLTU] |
                 op[ydrasil_pkg::OP_ALU_XOR] |
                 op[ydrasil_pkg::OP_ALU_OR] |
                 op[ydrasil_pkg::OP_ALU_AND] |
                 op[ydrasil_pkg::OP_ALU_LUI] |
                 op[ydrasil_pkg::OP_ALU_AUIPC]);
        end
    endfunction

    function automatic logic shadow_raw_dep(
        input logic       y_valid,
        input logic       y_rs1_ren,
        input logic [4:0] y_rs1,
        input logic       y_rs2_ren,
        input logic [4:0] y_rs2,
        input logic       o_valid,
        input logic       o_rd_wen,
        input logic [4:0] o_rd
    );
        begin
            shadow_raw_dep =
                y_valid && o_valid && o_rd_wen && (o_rd != '0) &&
                ((y_rs1_ren && (y_rs1 == o_rd)) |
                 (y_rs2_ren && (y_rs2 == o_rd)));
        end
    endfunction

    function automatic logic shadow_waw_dep(
        input logic       y_valid,
        input logic       y_rd_wen,
        input logic [4:0] y_rd,
        input logic       o_valid,
        input logic       o_rd_wen,
        input logic [4:0] o_rd
    );
        begin
            shadow_waw_dep =
                y_valid && y_rd_wen && (y_rd != '0) &&
                o_valid && o_rd_wen && (o_rd != '0) &&
                (y_rd == o_rd);
        end
    endfunction
`endif

    ydrasil_ins_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_ins_decoder (
        .instr_i            (decode_instr),
        .rf_waddr_rd_o      (rf_waddr_rd),
        .rf_raddr_rs1_o     (rf_raddr_rs1),
        .rf_raddr_rs2_o     (rf_raddr_rs2),
        .rf_ren_rs1_o       (rf_ren_rs1),
        .rf_ren_rs2_o       (rf_ren_rs2),
        .rf_wen_rd_o        (rf_wen_rd),
        .imm_i_o            (imm_i),
        .operand_b_rs_sel_o (operand_b_rs_sel),
        .operand_a_pc_sel_o (operand_a_pc_sel),
        .operand_a_imm_sel_o(operand_a_imm_sel),
        .bt_a_rs_sel_o      (bt_a_rs_sel),
        .operand_b_jump_sel_o(operand_b_jump_sel),
        .csr_reg_raddr_o    (csr_reg_raddr),
        // .csr_ex_we_o        (csr_ex_we),
        .csr_ex_waddr_o     (csr_ex_waddr),
        .csr_op_info_o      (csr_op_info),
        .sys_op_info_o      (sys_op_info),
        .operator_o         (operator),
        .operator_lsu_o     (operator_lsu),
        .operator_type_o    (operator_type)
    );

    ydrasil_ins_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_commit_trace_if_id_decoder (
        .instr_i            (if_id_instr_i),
        .rf_waddr_rd_o      (if_id_trace_rf_waddr_rd),
        .rf_raddr_rs1_o     (if_id_trace_rf_raddr_rs1),
        .rf_raddr_rs2_o     (if_id_trace_rf_raddr_rs2),
        .rf_ren_rs1_o       (if_id_trace_rf_ren_rs1),
        .rf_ren_rs2_o       (if_id_trace_rf_ren_rs2),
        .rf_wen_rd_o        (if_id_trace_rf_wen_rd),
        .imm_i_o            (if_id_trace_imm),
        .operand_b_rs_sel_o (if_id_trace_operand_b_rs_sel),
        .operand_a_pc_sel_o (if_id_trace_operand_a_pc_sel),
        .operand_a_imm_sel_o(if_id_trace_operand_a_imm_sel),
        .bt_a_rs_sel_o      (if_id_trace_bt_a_rs_sel),
        .operand_b_jump_sel_o(if_id_trace_operand_b_jump_sel),
        .csr_reg_raddr_o    (if_id_trace_csr_reg_raddr),
        .csr_ex_waddr_o     (if_id_trace_csr_ex_waddr),
        .csr_op_info_o      (if_id_trace_csr_op_info),
        .sys_op_info_o      (if_id_trace_sys_op_info),
        .operator_o         (if_id_trace_operator),
        .operator_lsu_o     (if_id_trace_operator_lsu),
        .operator_type_o    (if_id_trace_operator_type)
    );

    assign id_advance = !stall_id_i && !bubble_id_i;
    assign decode_pc = skid_valid_ff ? skid_pc_ff : if_id_pc_i;
    assign decode_instr = skid_valid_ff ? skid_instr_ff : if_id_instr_i;
    assign decode_pred_hit = skid_valid_ff ? skid_pred_hit_ff : if_id_pred_hit_i;
    assign decode_pred_taken = skid_valid_ff ? skid_pred_taken_ff : if_id_pred_taken_i;
    assign decode_pred_target = skid_valid_ff ? skid_pred_target_ff : if_id_pred_target_i;
    assign decode_pred_counter = skid_valid_ff ? skid_pred_counter_ff : if_id_pred_counter_i;
    assign decode_pred_bht_index = skid_valid_ff ? skid_pred_bht_index_ff : if_id_pred_bht_index_i;
    assign decode_pred_l0_taken = skid_valid_ff ? skid_pred_l0_taken_ff : if_id_pred_l0_taken_i;
    assign decode_valid = skid_valid_ff | if_id_valid_i;

    assign slot1_rf_raddr_rs1 = skid_rf_raddr_rs1_ff;
    assign slot1_rf_raddr_rs2 = skid_rf_raddr_rs2_ff;
    assign slot1_rf_ren_rs1 = skid_rf_ren_rs1_ff;
    assign slot1_rf_ren_rs2 = skid_rf_ren_rs2_ff;
    assign slot1_rf_waddr_rd = skid_rf_waddr_rd_ff;
    assign slot1_rf_wen_rd = skid_rf_wen_rd_ff;
    assign slot1_imm = skid_imm_ff;
    assign slot1_operand_b_rs_sel = skid_operand_b_rs_sel_ff;
    assign slot1_operand_a_pc_sel = skid_operand_a_pc_sel_ff;
    assign slot1_operand_a_imm_sel = skid_operand_a_imm_sel_ff;
    assign slot1_bt_a_rs_sel = skid_bt_a_rs_sel_ff;
    assign slot1_operand_b_jump_sel = skid_operand_b_jump_sel_ff;
    assign slot1_operator = skid_operator_ff;
    assign slot1_operator_lsu = skid_operator_lsu_ff;
    assign slot1_operator_type = skid_operator_type_ff;
    assign slot1_csr_reg_raddr = skid_csr_reg_raddr_ff;
    assign slot1_csr_ex_waddr = skid_csr_ex_waddr_ff;
    assign slot1_csr_op_info = skid_csr_op_info_ff;
    assign slot1_sys_op_info = skid_sys_op_info_ff;
    assign slot1_fence_i = skid_fence_i_ff;

    assign uopq0_valid = issue_valid_ff;
    assign uopq0_operator_type = issue_operator_type_ff;
    assign uopq0_operator = issue_operator_ff;
    assign uopq0_fence_i = issue_fence_i_ff;
    assign uopq0_rf_wen_rd = issue_rf_wen_rd_ff;
    assign uopq0_rf_waddr_rd = issue_rf_waddr_rd_ff;

    assign uopq1_valid = skid_valid_ff;
    assign uopq1_pc = decode_pc;
    assign uopq1_instr = decode_instr;
    assign uopq1_rf_raddr_rs1 = slot1_rf_raddr_rs1;
    assign uopq1_rf_raddr_rs2 = slot1_rf_raddr_rs2;
    assign uopq1_rf_ren_rs1 = slot1_rf_ren_rs1;
    assign uopq1_rf_ren_rs2 = slot1_rf_ren_rs2;
    assign uopq1_rf_waddr_rd = slot1_rf_waddr_rd;
    assign uopq1_rf_wen_rd = slot1_rf_wen_rd;
    assign uopq1_imm = slot1_imm;
    assign uopq1_operand_b_rs_sel = slot1_operand_b_rs_sel;
    assign uopq1_operand_a_pc_sel = slot1_operand_a_pc_sel;
    assign uopq1_operand_a_imm_sel = slot1_operand_a_imm_sel;
    assign uopq1_operand_b_jump_sel = slot1_operand_b_jump_sel;
    assign uopq1_operator = slot1_operator;
    assign uopq1_operator_type = slot1_operator_type;
    assign uopq1_fence_i = slot1_fence_i;

    assign uopq2_valid =
        if_id_valid_i && !skid_valid_ff &&
        !(issue_valid_ff && (if_id_pc_i == issue_pc_ff));
    assign uopq2_pc = if_id_pc_i;
    assign uopq2_instr = if_id_instr_i;
    assign uopq2_rf_raddr_rs1 = if_id_trace_rf_raddr_rs1;
    assign uopq2_rf_raddr_rs2 = if_id_trace_rf_raddr_rs2;
    assign uopq2_rf_ren_rs1 = if_id_trace_rf_ren_rs1;
    assign uopq2_rf_ren_rs2 = if_id_trace_rf_ren_rs2;
    assign uopq2_rf_waddr_rd = if_id_trace_rf_waddr_rd;
    assign uopq2_rf_wen_rd = if_id_trace_rf_wen_rd;
    assign uopq2_imm = if_id_trace_imm;
    assign uopq2_operand_b_rs_sel = if_id_trace_operand_b_rs_sel;
    assign uopq2_operand_a_pc_sel = if_id_trace_operand_a_pc_sel;
    assign uopq2_operand_a_imm_sel = if_id_trace_operand_a_imm_sel;
    assign uopq2_operand_b_jump_sel = if_id_trace_operand_b_jump_sel;
    assign uopq2_operator = if_id_trace_operator;
    assign uopq2_operator_type = if_id_trace_operator_type;
    assign uopq2_fence_i = (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                           (if_id_instr_i[14:12] == 3'b001);

    assign selected_rf_raddr_rs1 =
        issue_slot1_bypass_fire ? slot1_rf_raddr_rs1 : issue_rf_raddr_rs1_ff;
    assign selected_rf_raddr_rs2 =
        issue_slot1_bypass_fire ? slot1_rf_raddr_rs2 : issue_rf_raddr_rs2_ff;
    assign selected_rf_ren_rs1 =
        issue_slot1_bypass_fire ? slot1_rf_ren_rs1 : issue_rf_ren_rs1_ff;
    assign selected_rf_ren_rs2 =
        issue_slot1_bypass_fire ? slot1_rf_ren_rs2 : issue_rf_ren_rs2_ff;
    assign selected_rf_waddr_rd =
        issue_slot1_bypass_fire ? slot1_rf_waddr_rd : issue_rf_waddr_rd_ff;
    assign selected_rf_wen_rd =
        issue_slot1_bypass_fire ? slot1_rf_wen_rd : issue_rf_wen_rd_ff;
    assign selected_pc =
        issue_slot1_bypass_fire ? decode_pc : issue_pc_ff;
    assign selected_imm =
        issue_slot1_bypass_fire ? slot1_imm : issue_imm_ff;
    assign selected_operand_b_rs_sel =
        issue_slot1_bypass_fire ? slot1_operand_b_rs_sel : issue_operand_b_rs_sel_ff;
    assign selected_operand_a_pc_sel =
        issue_slot1_bypass_fire ? slot1_operand_a_pc_sel : issue_operand_a_pc_sel_ff;
    assign selected_operand_a_imm_sel =
        issue_slot1_bypass_fire ? slot1_operand_a_imm_sel : issue_operand_a_imm_sel_ff;
    assign selected_bt_a_rs_sel =
        issue_slot1_bypass_fire ? slot1_bt_a_rs_sel : issue_bt_a_rs_sel_ff;
    assign selected_operand_b_jump_sel =
        issue_slot1_bypass_fire ? slot1_operand_b_jump_sel : issue_operand_b_jump_sel_ff;
    assign selected_operator =
        issue_slot1_bypass_fire ? slot1_operator : issue_operator_ff;
    assign selected_operator_lsu =
        issue_slot1_bypass_fire ? slot1_operator_lsu : issue_operator_lsu_ff;
    assign selected_operator_type =
        issue_slot1_bypass_fire ? slot1_operator_type : issue_operator_type_ff;
    assign selected_csr_reg_raddr =
        issue_slot1_bypass_fire ? slot1_csr_reg_raddr : issue_csr_reg_raddr_ff;
    assign selected_csr_ex_waddr =
        issue_slot1_bypass_fire ? slot1_csr_ex_waddr : issue_csr_ex_waddr_ff;
    assign selected_csr_op_info =
        issue_slot1_bypass_fire ? slot1_csr_op_info : issue_csr_op_info_ff;
    assign selected_sys_op_info =
        issue_slot1_bypass_fire ? slot1_sys_op_info : issue_sys_op_info_ff;
    assign selected_fence_i =
        issue_slot1_bypass_fire ? slot1_fence_i : issue_fence_i_ff;
    assign selected_rn_rs1_psrc =
        issue_slot1_bypass_fire ? skid_rn_rs1_psrc_ff : issue_rn_rs1_psrc_ff;
    assign selected_rn_rs2_psrc =
        issue_slot1_bypass_fire ? skid_rn_rs2_psrc_ff : issue_rn_rs2_psrc_ff;
    assign selected_rn_pdst =
        issue_slot1_bypass_fire ? skid_rn_pdst_ff : issue_rn_pdst_ff;
    assign selected_rn_pdst_valid =
        issue_slot1_bypass_fire ? skid_rn_pdst_valid_ff : issue_rn_pdst_valid_ff;
    assign selected_pred_hit =
        issue_slot1_bypass_fire ? decode_pred_hit : issue_pred_hit_ff;
    assign selected_pred_taken =
        issue_slot1_bypass_fire ? decode_pred_taken : issue_pred_taken_ff;
    assign selected_pred_target =
        issue_slot1_bypass_fire ? decode_pred_target : issue_pred_target_ff;
    assign selected_pred_counter =
        issue_slot1_bypass_fire ? decode_pred_counter : issue_pred_counter_ff;
    assign selected_pred_bht_index =
        issue_slot1_bypass_fire ? decode_pred_bht_index : issue_pred_bht_index_ff;
    assign selected_pred_l0_taken =
        issue_slot1_bypass_fire ? decode_pred_l0_taken : issue_pred_l0_taken_ff;

    assign rf_addr_rs1_o = selected_rf_raddr_rs1;
    assign rf_addr_rs2_o = selected_rf_raddr_rs2;
    assign pipe1_rf_addr_rs1_o = pipe1_sel_rf_raddr_rs1;
    assign pipe1_rf_addr_rs2_o = pipe1_sel_rf_raddr_rs2;

    // Keep ALU source selection consistent with decoder control outputs.
    wire slot0_rs1_wb_fwd =
        wb_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == wb_fwd_addr_i);
    wire slot0_rs2_wb_fwd =
        wb_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == wb_fwd_addr_i);
    wire slot0_rs1_lsu_fwd =
        lsu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == lsu_fwd_addr_i);
    wire slot0_rs2_lsu_fwd =
        lsu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == lsu_fwd_addr_i);
    wire slot0_rs1_alu_fwd =
        alu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == alu_fwd_addr_i);
    wire slot0_rs2_alu_fwd =
        alu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == alu_fwd_addr_i);
`ifndef SYNTHESIS
    wire slot0_rs1_stable_fwd = rs1_issue_alu_stable_bypass_i;
    wire slot0_rs2_stable_fwd = rs2_issue_alu_stable_bypass_i;
`else
    wire slot0_rs1_stable_fwd = 1'b0;
    wire slot0_rs2_stable_fwd = 1'b0;
`endif
    wire slot0_rs1_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == pipe1_alu_fwd_addr_i);
    wire slot0_rs2_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == pipe1_alu_fwd_addr_i);
    wire slot0_rs1_pending_cleared =
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        !gpr_pending_i[issue_rf_raddr_rs1_ff];
    wire slot0_rs2_pending_cleared =
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        !gpr_pending_i[issue_rf_raddr_rs2_ff];
    wire rs1_wb_fwd =
        wb_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rf_raddr_rs1 == wb_fwd_addr_i);
    wire rs2_wb_fwd =
        wb_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rf_raddr_rs2 == wb_fwd_addr_i);
    wire rs1_lsu_fwd =
        lsu_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rf_raddr_rs1 == lsu_fwd_addr_i);
    wire rs2_lsu_fwd =
        lsu_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rf_raddr_rs2 == lsu_fwd_addr_i);
    wire rs1_alu_fwd =
        alu_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rf_raddr_rs1 == alu_fwd_addr_i);
    wire rs2_alu_fwd =
        alu_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rf_raddr_rs2 == alu_fwd_addr_i);
`ifndef SYNTHESIS
    wire rs1_stable_fwd =
        !issue_slot1_bypass_fire && rs1_issue_alu_stable_bypass_i;
    wire rs2_stable_fwd =
        !issue_slot1_bypass_fire && rs2_issue_alu_stable_bypass_i;
`else
    wire rs1_stable_fwd = 1'b0;
    wire rs2_stable_fwd = 1'b0;
`endif
    wire rs1_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        (selected_rf_raddr_rs1 == pipe1_alu_fwd_addr_i);
    wire rs2_p1alu_fwd =
        pipe1_alu_fwd_valid_i &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        (selected_rf_raddr_rs2 == pipe1_alu_fwd_addr_i);
`ifndef SYNTHESIS
    wire [DATA_WIDTH-1:0] issue_alu_stable_data = alu_stable_data_ff;
`else
    wire [DATA_WIDTH-1:0] issue_alu_stable_data = '0;
`endif
    wire selected_prf_operand_allowed =
        selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL];
    wire selected_prf_rs1_allowed =
        selected_prf_operand_allowed &&
        selected_rf_ren_rs1 &&
        (selected_rf_raddr_rs1 != '0) &&
        gpr_pending_i[selected_rf_raddr_rs1] &&
        (selected_rn_rs1_psrc != selected_rn_pdst);
    wire selected_prf_rs2_allowed =
        selected_prf_operand_allowed &&
        (selected_rf_ren_rs2 | selected_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (selected_rf_raddr_rs2 != '0) &&
        gpr_pending_i[selected_rf_raddr_rs2] &&
        (selected_rn_rs2_psrc != selected_rn_pdst);
    wire [DATA_WIDTH-1:0] issue_rs1_data =
        rs1_lsu_fwd ? lsu_fwd_data_i :
        rs1_stable_fwd ? issue_alu_stable_data :
        rs1_alu_fwd ? alu_fwd_data_i :
        rs1_p1alu_fwd ? pipe1_alu_fwd_data_i :
        rs1_wb_fwd  ? wb_fwd_data_i  :
        (!issue_slot1_bypass_fire && selected_prf_rs1_allowed && prf_rs1_ready_i) ? prf_rs1_data_i : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_rs2_data =
        rs2_lsu_fwd ? lsu_fwd_data_i :
        rs2_stable_fwd ? issue_alu_stable_data :
        rs2_alu_fwd ? alu_fwd_data_i :
        rs2_p1alu_fwd ? pipe1_alu_fwd_data_i :
        rs2_wb_fwd  ? wb_fwd_data_i  :
        (!issue_slot1_bypass_fire && selected_prf_rs2_allowed && prf_rs2_ready_i) ? prf_rs2_data_i : rf_rdata_rs2_i;

    assign operand_a     =  selected_operand_a_pc_sel ? selected_pc :
                            selected_operand_a_imm_sel ? selected_imm : issue_rs1_data;
    assign operand_b     = selected_operand_b_jump_sel ? 32'h4 :
                            selected_operand_b_rs_sel ? issue_rs2_data : selected_imm;

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && issue_fire &&
            ((selected_pc >= 32'h8000_007c && selected_pc <= 32'h8000_0090) ||
             (selected_pc >= 32'h8000_2da8 && selected_pc <= 32'h8000_2dc8))) begin
            $display("[ID_RN_DBG] pc=0x%08h instr=0x%08h slot1=%0b rs1=x%0d ren=%0b psrc=%0d prf_ready=%0b prf=0x%08h rf=0x%08h data=0x%08h use_prf=%0b rs2=x%0d psrc=%0d rd=x%0d pdst=%0d gpr_pending_rs1=%0b op_a=0x%08h op_b=0x%08h",
                     selected_pc,
                     (issue_slot1_bypass_fire ? decode_instr : 32'h0),
                     issue_slot1_bypass_fire,
                     selected_rf_raddr_rs1,
                     selected_rf_ren_rs1,
                     selected_rn_rs1_psrc,
                     prf_rs1_ready_i,
                     prf_rs1_data_i,
                     rf_rdata_rs1_i,
                     issue_rs1_data,
                     (!issue_slot1_bypass_fire && selected_prf_rs1_allowed && prf_rs1_ready_i),
                     selected_rf_raddr_rs2,
                     selected_rn_rs2_psrc,
                     selected_rf_waddr_rd,
                     selected_rn_pdst,
                     ((selected_rf_raddr_rs1 != '0) ? gpr_pending_i[selected_rf_raddr_rs1] : 1'b0),
                     operand_a,
                     operand_b);
        end
        if (rst_n && pair1_fire &&
            ((pipe1_sel_pc >= 32'h8000_007c && pipe1_sel_pc <= 32'h8000_0090) ||
             (pipe1_sel_pc >= 32'h8000_2da8 && pipe1_sel_pc <= 32'h8000_2dc8))) begin
            $display("[P1_RN_DBG] pc=0x%08h instr=0x%08h rs1=x%0d ren=%0b psrc=%0d prf_ready=%0b prf=0x%08h rf=0x%08h data=0x%08h rs2=x%0d psrc=%0d rd=x%0d pdst=%0d p1safe=%0b younger_flush_risk=%0b",
                     pipe1_sel_pc,
                     pipe1_sel_instr,
                     pipe1_sel_rf_raddr_rs1,
                     pipe1_sel_rf_ren_rs1,
                     pipe1_sel_rs1_psrc,
                     pipe1_prf_rs1_ready_i,
                     pipe1_prf_rs1_data_i,
                     pipe1_rf_rdata_rs1_i,
                     pipe1_dual_rs1_data,
                     pipe1_sel_rf_raddr_rs2,
                     pipe1_sel_rs2_psrc,
                     pipe1_sel_rf_waddr_rd,
                     pipe1_sel_pdst,
                     pipe1_uopq1_safe,
                     pipe1_younger_flush_risk);
        end
    end

    assign issue_alu_stable_candidate =
        issue_slot0_fire &&
        issue_rf_wen_rd_ff && (issue_rf_waddr_rd_ff != '0) &&
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        (issue_operator_ff[ydrasil_pkg::OP_ALU_LUI] |
         (issue_operator_ff[ydrasil_pkg::OP_ALU_ADD] &&
          !issue_operand_b_rs_sel_ff &&
          issue_rf_ren_rs1_ff &&
          (issue_rf_raddr_rs1_ff == '0)));
    assign issue_alu_stable_result = issue_imm_ff;
`endif


    assign bt_a_operand = selected_bt_a_rs_sel ? issue_rs1_data : selected_pc;
    assign bt_b_operand = selected_imm;
    assign id_fence_i = (decode_instr[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                        (decode_instr[14:12] == 3'b001);

    assign issue_wait_rs1_ready =
        !issue_wait_rs1_ff | slot0_rs1_stable_fwd | slot0_rs1_alu_fwd | slot0_rs1_p1alu_fwd |
        slot0_rs1_lsu_fwd | slot0_rs1_wb_fwd | slot0_rs1_pending_cleared;
    assign issue_wait_rs2_ready =
        !issue_wait_rs2_ff | slot0_rs2_stable_fwd | slot0_rs2_alu_fwd | slot0_rs2_p1alu_fwd |
        slot0_rs2_lsu_fwd | slot0_rs2_wb_fwd | slot0_rs2_pending_cleared;
    assign issue_wait_block =
        (issue_wait_rs1_ff & !issue_wait_rs1_ready) |
        (issue_wait_rs2_ff & !issue_wait_rs2_ready) |
        rs1_issue_alu_ready_next_i |
        rs2_issue_alu_ready_next_i;
    assign issue_slot0_fire =
        issue_valid_ff & id_advance & !issue_wait_block;
    assign issue_slot1_bypass_fire =
        ready_issue_allow_i & issue_valid_ff & issue_wait_block &
        !stall_id_i & !flush_id_i & ri_slot1_ready &
        !((PIPE1_REAL_MODE != 0) && pipe1_uopq1_safe && !pipe1_resbuf_full_i);
    assign issue_fire = issue_slot0_fire | issue_slot1_bypass_fire;
    assign issue_accept =
        id_advance & decode_valid & (!issue_valid_ff | issue_slot0_fire);
    assign issue_load_from_skid = issue_accept & skid_valid_ff;
    assign skid_fill =
        id_advance && issue_valid_ff && issue_wait_block &&
        !skid_valid_ff && if_id_valid_i;
    assign skid_drain = issue_accept & skid_valid_ff;
    assign issue_frontend_stall_o =
        (!flush_id_i & !stall_id_i & !bubble_id_i &
         issue_valid_ff & issue_wait_block & skid_valid_ff) |
        (pair1_fire & (PIPE1_REAL_MODE < 2));
    wire if_id_rn_pdst_valid =
        if_id_valid_i &&
        (if_id_trace_rf_waddr_rd != '0) &&
        (if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         (if_id_trace_rf_wen_rd &&
          !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
          !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS]));

    assign pipe1_dual_pipe0_safe =
        uopq0_valid &&
        uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !uopq0_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        !uopq0_fence_i;
    assign pipe1_uopq1_supported =
        uopq1_valid &&
        uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !uopq1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        uopq1_rf_wen_rd && (uopq1_rf_waddr_rd != '0) &&
        uopq1_rf_ren_rs1 && (uopq1_rf_raddr_rs1 != '0) &&
        ((uopq1_operator[ydrasil_pkg::OP_ALU_ADD] && uopq1_rf_ren_rs1 &&
          (!uopq1_operand_b_rs_sel || uopq1_rf_ren_rs2)) |
         ((uopq1_operator[ydrasil_pkg::OP_ALU_XOR] |
           uopq1_operator[ydrasil_pkg::OP_ALU_OR] |
           uopq1_operator[ydrasil_pkg::OP_ALU_AND]) &&
          uopq1_rf_ren_rs1 && (!uopq1_operand_b_rs_sel || uopq1_rf_ren_rs2)));
    assign pipe1_uopq2_supported =
        uopq2_valid &&
        uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        uopq2_rf_wen_rd && (uopq2_rf_waddr_rd != '0) &&
        uopq2_rf_ren_rs1 && (uopq2_rf_raddr_rs1 != '0) &&
        ((uopq2_operator[ydrasil_pkg::OP_ALU_ADD] && uopq2_rf_ren_rs1 &&
          (!uopq2_operand_b_rs_sel || uopq2_rf_ren_rs2)) |
         ((uopq2_operator[ydrasil_pkg::OP_ALU_XOR] |
           uopq2_operator[ydrasil_pkg::OP_ALU_OR] |
           uopq2_operator[ydrasil_pkg::OP_ALU_AND]) &&
          uopq2_rf_ren_rs1 && (!uopq2_operand_b_rs_sel || uopq2_rf_ren_rs2)));
    assign pipe1_uopq1_operands_ready =
        pipe1_uopq1_supported &&
        (!uopq1_rf_ren_rs1 || (uopq1_rf_raddr_rs1 == '0) || pipe1_prf_rs1_ready_i) &&
        (!uopq1_rf_ren_rs2 || (uopq1_rf_raddr_rs2 == '0) || pipe1_prf_rs2_ready_i);
    assign pipe1_uopq2_operands_ready =
        pipe1_uopq2_supported &&
        (!uopq2_rf_ren_rs1 || (uopq2_rf_raddr_rs1 == '0) ||
         !gpr_pending_i[uopq2_rf_raddr_rs1] ||
         (pipe1_alu_fwd_valid_i && (uopq2_rf_raddr_rs1 == pipe1_alu_fwd_addr_i))) &&
        (!uopq2_rf_ren_rs2 || (uopq2_rf_raddr_rs2 == '0) ||
         !gpr_pending_i[uopq2_rf_raddr_rs2] ||
         (pipe1_alu_fwd_valid_i && (uopq2_rf_raddr_rs2 == pipe1_alu_fwd_addr_i)));
    assign pipe1_uopq1_safe =
        pipe1_dual_pipe0_safe && pipe1_uopq1_operands_ready &&
        !(uopq0_rf_wen_rd && (uopq0_rf_waddr_rd != '0) &&
          ((uopq1_rf_ren_rs1 && (uopq1_rf_raddr_rs1 == uopq0_rf_waddr_rd)) |
           (uopq1_rf_ren_rs2 && (uopq1_rf_raddr_rs2 == uopq0_rf_waddr_rd)))) &&
        !(uopq0_rf_wen_rd && (uopq0_rf_waddr_rd != '0) &&
          (uopq1_rf_waddr_rd == uopq0_rf_waddr_rd)) &&
        pipe1_rename_ready_i && skid_rn_pdst_valid_ff;
    assign pipe1_uopq2_safe =
        !uopq1_valid && pipe1_dual_pipe0_safe && pipe1_uopq2_operands_ready &&
        !(uopq0_rf_wen_rd && (uopq0_rf_waddr_rd != '0) &&
          ((uopq2_rf_ren_rs1 && (uopq2_rf_raddr_rs1 == uopq0_rf_waddr_rd)) |
           (uopq2_rf_ren_rs2 && (uopq2_rf_raddr_rs2 == uopq0_rf_waddr_rd)))) &&
        !(uopq0_rf_wen_rd && (uopq0_rf_waddr_rd != '0) &&
          (uopq2_rf_waddr_rd == uopq0_rf_waddr_rd)) &&
        pipe1_rename_ready_i && if_id_rn_pdst_valid;
    assign pipe1_younger_flush_risk =
        (uopq2_valid &&
         (uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          uopq2_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] |
          uopq2_fence_i)) |
        (if_id_valid_i &&
         (if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] |
          id_fence_i));
    assign pipe1_sel_from1 = pipe1_uopq1_safe;
    assign pipe1_sel_from2 = 1'b0;
    assign pipe1_sel_pc = pipe1_sel_from2 ? uopq2_pc : uopq1_pc;
    assign pipe1_sel_instr = pipe1_sel_from2 ? uopq2_instr : uopq1_instr;
    assign pipe1_sel_rf_raddr_rs1 = pipe1_sel_from2 ? uopq2_rf_raddr_rs1 : uopq1_rf_raddr_rs1;
    assign pipe1_sel_rf_raddr_rs2 = pipe1_sel_from2 ? uopq2_rf_raddr_rs2 : uopq1_rf_raddr_rs2;
    assign pipe1_sel_rf_ren_rs1 = pipe1_sel_from2 ? uopq2_rf_ren_rs1 : uopq1_rf_ren_rs1;
    assign pipe1_sel_rf_ren_rs2 = pipe1_sel_from2 ? uopq2_rf_ren_rs2 : uopq1_rf_ren_rs2;
    assign pipe1_sel_rf_waddr_rd = pipe1_sel_from2 ? uopq2_rf_waddr_rd : uopq1_rf_waddr_rd;
    assign pipe1_sel_rf_wen_rd = pipe1_sel_from2 ? uopq2_rf_wen_rd : uopq1_rf_wen_rd;
    assign pipe1_sel_rs1_psrc = pipe1_sel_from2 ? rn_if_rs1_psrc_i : skid_rn_rs1_psrc_ff;
    assign pipe1_sel_rs2_psrc = pipe1_sel_from2 ? rn_if_rs2_psrc_i : skid_rn_rs2_psrc_ff;
    assign pipe1_sel_pdst = pipe1_sel_from2 ? rn_if_pdst_i : skid_rn_pdst_ff;
    assign pipe1_sel_pdst_valid = pipe1_sel_from2 ? if_id_rn_pdst_valid : skid_rn_pdst_valid_ff;
    assign pipe1_sel_imm = pipe1_sel_from2 ? uopq2_imm : uopq1_imm;
    assign pipe1_sel_operand_b_rs_sel =
        pipe1_sel_from2 ? uopq2_operand_b_rs_sel : uopq1_operand_b_rs_sel;
    assign pipe1_sel_operand_a_pc_sel =
        pipe1_sel_from2 ? uopq2_operand_a_pc_sel : uopq1_operand_a_pc_sel;
    assign pipe1_sel_operand_a_imm_sel =
        pipe1_sel_from2 ? uopq2_operand_a_imm_sel : uopq1_operand_a_imm_sel;
    assign pipe1_sel_operand_b_jump_sel =
        pipe1_sel_from2 ? uopq2_operand_b_jump_sel : uopq1_operand_b_jump_sel;
    assign pipe1_sel_operator = pipe1_sel_from2 ? uopq2_operator : uopq1_operator;
    assign pipe1_sel_operator_type =
        pipe1_sel_from2 ? uopq2_operator_type : uopq1_operator_type;
    assign pipe1_dual_supported =
        (pipe1_sel_from1 && pipe1_uopq1_supported) ||
        (pipe1_sel_from2 && pipe1_uopq2_supported);
    assign pipe1_dual_rs1_alu_fwd =
        alu_fwd_valid_i && pipe1_sel_rf_ren_rs1 &&
        (pipe1_sel_rf_raddr_rs1 != '0) &&
        (pipe1_sel_rf_raddr_rs1 == alu_fwd_addr_i);
    assign pipe1_dual_rs2_alu_fwd =
        alu_fwd_valid_i && pipe1_sel_rf_ren_rs2 &&
        (pipe1_sel_rf_raddr_rs2 != '0) &&
        (pipe1_sel_rf_raddr_rs2 == alu_fwd_addr_i);
    assign pipe1_dual_rs1_wb_fwd =
        wb_fwd_valid_i && pipe1_sel_rf_ren_rs1 &&
        (pipe1_sel_rf_raddr_rs1 != '0) &&
        (pipe1_sel_rf_raddr_rs1 == wb_fwd_addr_i);
    assign pipe1_dual_rs2_wb_fwd =
        wb_fwd_valid_i && pipe1_sel_rf_ren_rs2 &&
        (pipe1_sel_rf_raddr_rs2 != '0) &&
        (pipe1_sel_rf_raddr_rs2 == wb_fwd_addr_i);
    assign pipe1_dual_rs1_p1alu_fwd =
        pipe1_alu_fwd_valid_i && pipe1_sel_rf_ren_rs1 &&
        (pipe1_sel_rf_raddr_rs1 != '0) &&
        (pipe1_sel_rf_raddr_rs1 == pipe1_alu_fwd_addr_i);
    assign pipe1_dual_rs2_p1alu_fwd =
        pipe1_alu_fwd_valid_i && pipe1_sel_rf_ren_rs2 &&
        (pipe1_sel_rf_raddr_rs2 != '0) &&
        (pipe1_sel_rf_raddr_rs2 == pipe1_alu_fwd_addr_i);
    assign pipe1_dual_rs1_ready =
        !pipe1_sel_rf_ren_rs1 || (pipe1_sel_rf_raddr_rs1 == '0) ||
        pipe1_prf_rs1_ready_i;
    assign pipe1_dual_rs2_ready =
        !pipe1_sel_rf_ren_rs2 || (pipe1_sel_rf_raddr_rs2 == '0) ||
        pipe1_prf_rs2_ready_i;
    assign pipe1_dual_operands_ready =
        (pipe1_sel_from1 && pipe1_uopq1_operands_ready) ||
        (pipe1_sel_from2 && pipe1_uopq2_operands_ready);
    assign pipe1_dual_rs1_data =
        pipe1_dual_rs1_alu_fwd ? alu_fwd_data_i :
        pipe1_dual_rs1_p1alu_fwd ? pipe1_alu_fwd_data_i :
        pipe1_dual_rs1_wb_fwd  ? wb_fwd_data_i  : pipe1_prf_rs1_data_i;
    assign pipe1_dual_rs2_data =
        pipe1_dual_rs2_alu_fwd ? alu_fwd_data_i :
        pipe1_dual_rs2_p1alu_fwd ? pipe1_alu_fwd_data_i :
        pipe1_dual_rs2_wb_fwd  ? wb_fwd_data_i  : pipe1_prf_rs2_data_i;
    assign pipe1_dual_operand_a =
        (pipe1_sel_operand_a_pc_sel | pipe1_sel_operator[ydrasil_pkg::OP_ALU_AUIPC]) ? pipe1_sel_pc :
        pipe1_sel_operand_a_imm_sel ? pipe1_sel_imm : pipe1_dual_rs1_data;
    assign pipe1_dual_operand_b =
        pipe1_sel_operand_b_jump_sel ? 32'h4 :
        pipe1_sel_operand_b_rs_sel ? pipe1_dual_rs2_data : pipe1_sel_imm;
    assign pair1_refill_dep_p1 =
        if_id_valid_i && slot1_rf_wen_rd && (slot1_rf_waddr_rd != '0) &&
        ((if_id_trace_rf_ren_rs1 && (if_id_trace_rf_raddr_rs1 == slot1_rf_waddr_rd)) |
         (if_id_trace_rf_ren_rs2 && (if_id_trace_rf_raddr_rs2 == slot1_rf_waddr_rd)) |
         (if_id_trace_rf_wen_rd && (if_id_trace_rf_waddr_rd == slot1_rf_waddr_rd)));
    assign pair1_refill_dep_p0 =
        if_id_valid_i && issue_rf_wen_rd_ff && (issue_rf_waddr_rd_ff != '0) &&
        ((if_id_trace_rf_ren_rs1 && (if_id_trace_rf_raddr_rs1 == issue_rf_waddr_rd_ff)) |
         (if_id_trace_rf_ren_rs2 && (if_id_trace_rf_raddr_rs2 == issue_rf_waddr_rd_ff)) |
         (if_id_trace_rf_wen_rd && (if_id_trace_rf_waddr_rd == issue_rf_waddr_rd_ff)));
    assign pair1_refill_srcs_ready =
        (!if_id_trace_rf_ren_rs1 || (if_id_trace_rf_raddr_rs1 == '0) ||
         !gpr_pending_i[if_id_trace_rf_raddr_rs1]) &&
        (!if_id_trace_rf_ren_rs2 || (if_id_trace_rf_raddr_rs2 == '0) ||
         !gpr_pending_i[if_id_trace_rf_raddr_rs2]);
    assign pair1_refill_simple_alu =
        if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
    assign pair1_refill_direct =
        1'b0;
    assign pipe1_dual_raw_pipe0 =
        pipe1_dual_supported && (uopq0_rf_waddr_rd != '0) &&
        uopq0_rf_wen_rd &&
        ((pipe1_sel_rf_ren_rs1 && (pipe1_sel_rf_raddr_rs1 == uopq0_rf_waddr_rd)) |
         (pipe1_sel_rf_ren_rs2 && (pipe1_sel_rf_raddr_rs2 == uopq0_rf_waddr_rd)));
    assign pipe1_dual_waw_pipe0 =
        pipe1_dual_supported && uopq0_rf_wen_rd &&
        (uopq0_rf_waddr_rd != '0) && (pipe1_sel_rf_waddr_rd == uopq0_rf_waddr_rd);
    assign pipe1_dual_war_pipe0 =
        1'b0;
    assign pipe1_dual_pending_rd =
        pipe1_dual_supported && (!pipe1_rename_ready_i || !pipe1_sel_pdst_valid);
    assign pipe1_p0_ready_context = issue_slot0_fire;
    assign pipe1_p0_blocked_context =
        1'b0;
`ifdef YDRASIL_ENABLE_PIPE1_REAL
    assign pipe1_dual_fire =
        (PIPE1_REAL_MODE != 0) &&
        (pipe1_p0_ready_context | pipe1_p0_blocked_context) &&
        ready_issue_allow_i && !flush_id_i &&
        pipe1_dual_pipe0_safe && pipe1_dual_operands_ready &&
        !pipe1_younger_flush_risk &&
        !pipe1_dual_raw_pipe0 && !pipe1_dual_waw_pipe0 &&
        !pipe1_dual_war_pipe0 && !pipe1_dual_pending_rd &&
        !pipe1_resbuf_full_i;
`else
    assign pipe1_dual_fire = 1'b0;
`endif
    assign pair1_fire = pipe1_dual_fire;
    assign pipe1_fire_from1 = pair1_fire && pipe1_sel_from1;
    assign pipe1_fire_from2 = pair1_fire && pipe1_sel_from2;

    assign ri_slot1_valid = skid_valid_ff;
    assign ri_slot1_supported =
        ri_slot1_valid &&
        (slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] |
         slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP]) &&
        !(slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
          slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL]);
    assign ri_slot1_block_raw =
        ri_slot1_valid && issue_valid_ff && (issue_rf_waddr_rd_ff != '0) &&
        ((slot1_rf_ren_rs1 && (slot1_rf_raddr_rs1 == issue_rf_waddr_rd_ff)) |
         (slot1_rf_ren_rs2 && (slot1_rf_raddr_rs2 == issue_rf_waddr_rd_ff)));
    assign ri_slot1_block_waw =
        ri_slot1_valid && issue_valid_ff && slot1_rf_wen_rd &&
        (slot1_rf_waddr_rd != '0) && (slot1_rf_waddr_rd == issue_rf_waddr_rd_ff);
    assign ri_slot1_block_war =
        ri_slot1_valid && issue_valid_ff && slot1_rf_wen_rd && (slot1_rf_waddr_rd != '0) &&
        ((issue_rf_ren_rs1_ff && (issue_rf_raddr_rs1_ff == slot1_rf_waddr_rd)) |
         ((issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
          (issue_rf_raddr_rs2_ff == slot1_rf_waddr_rd)));
    assign ri_slot1_block_ctrl =
        ri_slot1_valid && issue_valid_ff &&
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP];
    assign ri_slot1_block_mem =
        ri_slot1_valid && issue_valid_ff &&
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign ri_slot1_block_old_unsupported =
        ri_slot1_valid && issue_valid_ff &&
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL]);
    wire ri_slot1_rs1_clear_fwd =
        (wb_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (slot1_rf_raddr_rs1 == wb_fwd_addr_i)) |
        (lsu_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (slot1_rf_raddr_rs1 == lsu_fwd_addr_i)) |
        (alu_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (slot1_rf_raddr_rs1 == alu_fwd_addr_i)) |
        (pipe1_alu_fwd_valid_i & slot1_rf_ren_rs1 & (slot1_rf_raddr_rs1 != '0) &
         (slot1_rf_raddr_rs1 == pipe1_alu_fwd_addr_i));
    wire ri_slot1_rs2_read = slot1_rf_ren_rs2 | slot1_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];
    wire ri_slot1_rs2_clear_fwd =
        (wb_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (slot1_rf_raddr_rs2 == wb_fwd_addr_i)) |
        (lsu_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (slot1_rf_raddr_rs2 == lsu_fwd_addr_i)) |
        (alu_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (slot1_rf_raddr_rs2 == alu_fwd_addr_i)) |
        (pipe1_alu_fwd_valid_i & ri_slot1_rs2_read & (slot1_rf_raddr_rs2 != '0) &
         (slot1_rf_raddr_rs2 == pipe1_alu_fwd_addr_i));
    wire ri_slot1_rd_clear_fwd =
        (wb_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == wb_fwd_addr_i)) |
        (lsu_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == lsu_fwd_addr_i)) |
        (alu_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == alu_fwd_addr_i)) |
        (pipe1_alu_fwd_valid_i & slot1_rf_wen_rd & (slot1_rf_waddr_rd != '0) &
         (slot1_rf_waddr_rd == pipe1_alu_fwd_addr_i));
    assign ri_slot1_block_rs1_pending =
        ri_slot1_valid && slot1_rf_ren_rs1 && gpr_pending_i[slot1_rf_raddr_rs1] &&
        !ri_slot1_rs1_clear_fwd;
    assign ri_slot1_block_rs2_pending =
        ri_slot1_valid && ri_slot1_rs2_read && gpr_pending_i[slot1_rf_raddr_rs2] &&
        !ri_slot1_rs2_clear_fwd;
    assign ri_slot1_block_rd_pending =
        ri_slot1_valid && slot1_rf_wen_rd && (slot1_rf_waddr_rd != '0) &&
        gpr_pending_i[slot1_rf_waddr_rd] && !ri_slot1_rd_clear_fwd;
    assign ri_slot1_block_unsupported = ri_slot1_valid && !ri_slot1_supported;
    assign ri_slot1_ready =
        ri_slot1_valid && ri_slot1_supported &&
        !ri_slot1_block_raw && !ri_slot1_block_waw &&
        !ri_slot1_block_war && !ri_slot1_block_ctrl &&
        !ri_slot1_block_mem && !ri_slot1_block_old_unsupported &&
        !ri_slot1_block_rs1_pending && !ri_slot1_block_rs2_pending &&
        !ri_slot1_block_rd_pending;
    assign ri_slot1_ready_when_slot0_blocked =
        ri_slot1_ready && issue_valid_ff && issue_wait_block;
    assign ri_slot1_ready_when_slot0_ready =
        ri_slot1_ready && issue_valid_ff && !issue_wait_block;
    assign ri_slot1_fire_blocked_by_single_issue =
        ri_slot1_ready_when_slot0_ready && id_advance && !stall_id_i && !flush_id_i;
    assign ri_slot1_fire_blocked_by_wb_order =
        1'b0;
    assign ri_bypass_flush_killed =
        ready_issue_allow_i && issue_valid_ff && issue_wait_block && ri_slot1_ready && flush_id_i;

`ifndef SYNTHESIS
    assign ds_pipe0_valid = issue_valid_ff;
    assign ds_pipe0_ready = issue_valid_ff && !issue_wait_block && id_advance;
    assign ds_pipe0_ctrl = issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP];
    assign ds_pipe0_mem =
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE];
    assign ds_pipe0_csr_sys =
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] |
        issue_fence_i_ff;
    assign ds_pipe0_mul = issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL];
    assign ds_pipe0_no_side_effect =
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !ds_pipe0_ctrl && !ds_pipe0_mem && !ds_pipe0_csr_sys && !ds_pipe0_mul;

    assign ds_pipe1_valid = skid_valid_ff;
    assign ds_pipe1_simple_alu =
        ds_pipe1_valid &&
        operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !operator_type[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        (operator[ydrasil_pkg::OP_ALU_ADD] |
         operator[ydrasil_pkg::OP_ALU_SUB] |
         operator[ydrasil_pkg::OP_ALU_SLT] |
         operator[ydrasil_pkg::OP_ALU_SLTU] |
         operator[ydrasil_pkg::OP_ALU_XOR] |
         operator[ydrasil_pkg::OP_ALU_OR] |
         operator[ydrasil_pkg::OP_ALU_AND] |
         operator[ydrasil_pkg::OP_ALU_LUI] |
         operator[ydrasil_pkg::OP_ALU_AUIPC]);
    assign ds_pipe1_unsupported = ds_pipe1_valid && !ds_pipe1_simple_alu;
    assign ds_pipe1_ctrl = ds_pipe1_valid && operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP];
    assign ds_pipe1_mem =
        ds_pipe1_valid &&
        (operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign ds_pipe1_csr_sys =
        ds_pipe1_valid &&
        (operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
         operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
         id_fence_i);
    assign ds_pipe1_rd_valid = !rf_wen_rd || (rf_waddr_rd != '0);
    assign ds_block_raw_pipe0 =
        ds_pipe1_valid && ds_pipe0_valid && (issue_rf_waddr_rd_ff != '0) &&
        issue_rf_wen_rd_ff &&
        ((rf_ren_rs1 && (rf_raddr_rs1 == issue_rf_waddr_rd_ff)) |
         (rf_ren_rs2 && (rf_raddr_rs2 == issue_rf_waddr_rd_ff)));
    assign ds_block_waw_pipe0 =
        ds_pipe1_valid && ds_pipe0_valid && rf_wen_rd &&
        (rf_waddr_rd != '0) && issue_rf_wen_rd_ff &&
        (rf_waddr_rd == issue_rf_waddr_rd_ff);
    assign ds_block_pending_rs1 = ds_pipe1_valid && ri_slot1_block_rs1_pending;
    assign ds_block_pending_rs2 = ds_pipe1_valid && ri_slot1_block_rs2_pending;
    assign ds_block_ctrl =
        ds_pipe1_valid && (ds_pipe0_ctrl | ds_pipe1_ctrl);
    assign ds_block_mem =
        ds_pipe1_valid && (ds_pipe0_mem | ds_pipe1_mem);
    assign ds_block_csr_sys =
        ds_pipe1_valid && (ds_pipe0_csr_sys | ds_pipe1_csr_sys);
    assign ds_block_flush = ds_pipe1_valid && flush_id_i;
    assign ds_block_forward_complex =
        ds_pipe1_valid && ds_pipe1_simple_alu &&
        ((rf_ren_rs1 && ri_slot1_rs1_clear_fwd) |
         (ri_slot1_rs2_read && ri_slot1_rs2_clear_fwd));
    assign ds_shadow_safe_candidate =
        ds_pipe0_valid && ds_pipe1_valid &&
        ds_pipe0_no_side_effect && ds_pipe1_simple_alu &&
        ds_pipe1_rd_valid &&
        !ds_block_raw_pipe0 && !ds_block_waw_pipe0 &&
        !ds_block_pending_rs1 && !ds_block_pending_rs2 &&
        !ds_block_ctrl && !ds_block_mem && !ds_block_csr_sys &&
        !ds_block_flush && !stall_id_i && ready_issue_allow_i;
    assign ds_block_wb_port =
        ds_shadow_safe_candidate &&
        issue_rf_wen_rd_ff && (issue_rf_waddr_rd_ff != '0) &&
        rf_wen_rd && (rf_waddr_rd != '0);

    assign p1sh_simple_alu =
        pair1_valid_ff &&
        pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
        !pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
        !pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] &&
        !pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] &&
        !pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL] &&
        !pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &&
        (pair1_operator_ff[ydrasil_pkg::OP_ALU_ADD] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_SUB] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_SLT] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_SLTU] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_XOR] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_OR] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_AND] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_LUI] |
         pair1_operator_ff[ydrasil_pkg::OP_ALU_AUIPC]);
    assign p1sh_block_raw_pair0 =
        pair1_valid_ff && issue_valid_ff && issue_rf_wen_rd_ff &&
        (issue_rf_waddr_rd_ff != '0) &&
        ((pair1_rs1_ren_ff && (pair1_rs1_ff == issue_rf_waddr_rd_ff)) |
         (pair1_rs2_ren_ff && (pair1_rs2_ff == issue_rf_waddr_rd_ff)));
    assign p1sh_block_waw_pair0 =
        pair1_valid_ff && issue_valid_ff && issue_rf_wen_rd_ff &&
        pair1_rd_wen_ff && (pair1_rd_ff != '0) &&
        (pair1_rd_ff == issue_rf_waddr_rd_ff);
    assign p1sh_block_pending_rs =
        pair1_valid_ff &&
        ((pair1_rs1_ren_ff && gpr_pending_i[pair1_rs1_ff]) |
         (pair1_rs2_ren_ff && gpr_pending_i[pair1_rs2_ff]));
    assign p1sh_block_ctrl_mem =
        pair1_valid_ff &&
        (pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] |
         pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
         pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
         pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS]);
    assign p1sh_safe_cand =
        p1sh_simple_alu && issue_valid_ff &&
        !p1sh_block_raw_pair0 && !p1sh_block_waw_pair0 &&
        !p1sh_block_pending_rs && !p1sh_block_ctrl_mem &&
        !flush_id_i && !stall_id_i;

    assign uopq_shadow_occupancy =
        {2'b00, uopq_shadow_valid[0]} +
        {2'b00, uopq_shadow_valid[1]} +
        {2'b00, uopq_shadow_valid[2]} +
        {2'b00, uopq_shadow_valid[3]};
    assign uopq_shadow_raw_older[1] =
        shadow_raw_dep(
            uopq_shadow_valid[1],
            uopq_shadow_rs1_ren[1], uopq_shadow_rs1[1],
            uopq_shadow_rs2_ren[1], uopq_shadow_rs2[1],
            uopq_shadow_valid[0], uopq_shadow_rd_wen[0], uopq_shadow_rd[0]);
    assign uopq_shadow_waw_older[1] =
        shadow_waw_dep(
            uopq_shadow_valid[1], uopq_shadow_rd_wen[1], uopq_shadow_rd[1],
            uopq_shadow_valid[0], uopq_shadow_rd_wen[0], uopq_shadow_rd[0]);
    assign uopq_shadow_older_ctrl_mem[1] =
        uopq_shadow_valid[1] && uopq_shadow_valid[0] &&
        (uopq_shadow_ctrl[0] | uopq_shadow_mem[0] | uopq_shadow_csr_sys_fence[0]);
    assign uopq_shadow_pending_rs[1] =
        uopq_shadow_valid[1] &&
        ((uopq_shadow_rs1_ren[1] && gpr_pending_i[uopq_shadow_rs1[1]]) |
         (uopq_shadow_rs2_ren[1] && gpr_pending_i[uopq_shadow_rs2[1]]));
    assign uopq_shadow_p1_safe[1] =
        uopq_shadow_valid[1] && uopq_shadow_simple_alu[1] &&
        !uopq_shadow_raw_older[1] && !uopq_shadow_waw_older[1] &&
        !uopq_shadow_older_ctrl_mem[1] && !uopq_shadow_pending_rs[1] &&
        !flush_id_i && !stall_id_i;

    assign uopq_shadow_raw_older[2] =
        shadow_raw_dep(
            uopq_shadow_valid[2],
            uopq_shadow_rs1_ren[2], uopq_shadow_rs1[2],
            uopq_shadow_rs2_ren[2], uopq_shadow_rs2[2],
            uopq_shadow_valid[0], uopq_shadow_rd_wen[0], uopq_shadow_rd[0]) |
        shadow_raw_dep(
            uopq_shadow_valid[2],
            uopq_shadow_rs1_ren[2], uopq_shadow_rs1[2],
            uopq_shadow_rs2_ren[2], uopq_shadow_rs2[2],
            uopq_shadow_valid[1], uopq_shadow_rd_wen[1], uopq_shadow_rd[1]);
    assign uopq_shadow_waw_older[2] =
        shadow_waw_dep(
            uopq_shadow_valid[2], uopq_shadow_rd_wen[2], uopq_shadow_rd[2],
            uopq_shadow_valid[0], uopq_shadow_rd_wen[0], uopq_shadow_rd[0]) |
        shadow_waw_dep(
            uopq_shadow_valid[2], uopq_shadow_rd_wen[2], uopq_shadow_rd[2],
            uopq_shadow_valid[1], uopq_shadow_rd_wen[1], uopq_shadow_rd[1]);
    assign uopq_shadow_older_ctrl_mem[2] =
        uopq_shadow_valid[2] &&
        ((uopq_shadow_valid[0] &&
          (uopq_shadow_ctrl[0] | uopq_shadow_mem[0] | uopq_shadow_csr_sys_fence[0])) |
         (uopq_shadow_valid[1] &&
          (uopq_shadow_ctrl[1] | uopq_shadow_mem[1] | uopq_shadow_csr_sys_fence[1])));
    assign uopq_shadow_pending_rs[2] =
        uopq_shadow_valid[2] &&
        ((uopq_shadow_rs1_ren[2] && gpr_pending_i[uopq_shadow_rs1[2]]) |
         (uopq_shadow_rs2_ren[2] && gpr_pending_i[uopq_shadow_rs2[2]]));
    assign uopq_shadow_p1_safe[2] =
        uopq_shadow_valid[2] && uopq_shadow_simple_alu[2] &&
        !uopq_shadow_raw_older[2] && !uopq_shadow_waw_older[2] &&
        !uopq_shadow_older_ctrl_mem[2] && !uopq_shadow_pending_rs[2] &&
        !flush_id_i && !stall_id_i;
    assign uopq_shadow_raw_older[3] = 1'b0;
    assign uopq_shadow_waw_older[3] = 1'b0;
    assign uopq_shadow_older_ctrl_mem[3] = 1'b0;
    assign uopq_shadow_pending_rs[3] = 1'b0;
    assign uopq_shadow_p1_safe[3] = 1'b0;
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_valid_ff <= 1'b0;
            skid_pc_ff <= '0;
            skid_instr_ff <= ydrasil_pkg::RV32I_INS_NOP;
            skid_pred_hit_ff <= 1'b0;
            skid_pred_taken_ff <= 1'b0;
            skid_pred_target_ff <= '0;
            skid_pred_counter_ff <= 2'b01;
            skid_pred_bht_index_ff <= '0;
            skid_pred_l0_taken_ff <= 1'b0;
            skid_rf_raddr_rs1_ff <= '0;
            skid_rf_raddr_rs2_ff <= '0;
            skid_rf_ren_rs1_ff <= 1'b0;
            skid_rf_ren_rs2_ff <= 1'b0;
            skid_rf_waddr_rd_ff <= '0;
            skid_rf_wen_rd_ff <= 1'b0;
            skid_imm_ff <= '0;
            skid_operand_b_rs_sel_ff <= 1'b0;
            skid_operand_a_pc_sel_ff <= 1'b0;
            skid_operand_a_imm_sel_ff <= 1'b0;
            skid_bt_a_rs_sel_ff <= 1'b0;
            skid_operand_b_jump_sel_ff <= 1'b0;
            skid_operator_ff <= '0;
            skid_operator_lsu_ff <= '0;
            skid_operator_type_ff <= '0;
            skid_csr_reg_raddr_ff <= '0;
            skid_csr_ex_waddr_ff <= '0;
            skid_csr_op_info_ff <= '0;
            skid_sys_op_info_ff <= '0;
            skid_fence_i_ff <= 1'b0;
            skid_rn_rs1_psrc_ff <= '0;
            skid_rn_rs2_psrc_ff <= '0;
            skid_rn_pdst_ff <= '0;
            skid_rn_pdst_valid_ff <= 1'b0;
            issue_valid_ff <= 1'b0;
            issue_wait_rs1_ff <= 1'b0;
            issue_wait_rs2_ff <= 1'b0;
            issue_pc_ff <= '0;
            issue_pred_hit_ff <= 1'b0;
            issue_pred_taken_ff <= 1'b0;
            issue_pred_target_ff <= '0;
            issue_pred_counter_ff <= 2'b01;
            issue_pred_bht_index_ff <= '0;
            issue_pred_l0_taken_ff <= 1'b0;
            issue_rf_raddr_rs1_ff <= '0;
            issue_rf_raddr_rs2_ff <= '0;
            issue_rf_ren_rs1_ff <= 1'b0;
            issue_rf_ren_rs2_ff <= 1'b0;
            issue_rf_waddr_rd_ff <= '0;
            issue_rf_wen_rd_ff <= 1'b0;
            issue_imm_ff <= '0;
            issue_operand_b_rs_sel_ff <= 1'b0;
            issue_operand_a_pc_sel_ff <= 1'b0;
            issue_operand_a_imm_sel_ff <= 1'b0;
            issue_bt_a_rs_sel_ff <= 1'b0;
            issue_operand_b_jump_sel_ff <= 1'b0;
            issue_operator_ff <= '0;
            issue_operator_lsu_ff <= '0;
            issue_operator_type_ff <= '0;
            issue_csr_reg_raddr_ff <= '0;
            issue_csr_ex_waddr_ff <= '0;
            issue_csr_op_info_ff <= '0;
            issue_sys_op_info_ff <= '0;
            issue_fence_i_ff <= 1'b0;
            issue_rn_rs1_psrc_ff <= '0;
            issue_rn_rs2_psrc_ff <= '0;
            issue_rn_pdst_ff <= '0;
            issue_rn_pdst_valid_ff <= 1'b0;
            id_rn_pdst_ff <= '0;
`ifndef SYNTHESIS
            alu_stable_valid_ff <= 1'b0;
            alu_stable_addr_ff <= '0;
            alu_stable_data_ff <= '0;
`endif
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            operator_lsu_ff     <= '0;
            id_lsu_rs2_data_ff  <= '0;
            id_lsu_addr_ff      <= '0;
            id_lsu_addr_is_dtcm_ff <= 1'b0;
            id_lsu_store_data_ff <= '0;
            id_lsu_store_mask_ff <= 4'b0000;
            bt_a_operand_ff     <= '0;
            bt_b_operand_ff     <= '0;
            csr_reg_raddr_ff <= '0;
            // csr_ex_we_ff <= 1'b0;
            csr_ex_waddr_ff <= '0;
            csr_op_info_ff <= '0;
            sys_op_info_ff <= '0;
            id_instr_addr_ff <= '0;
            id_ex_jalr_ff <= 1'b0;
            id_ex_pred_hit_ff <= 1'b0;
            id_ex_pred_taken_ff <= 1'b0;
            id_ex_pred_target_ff <= '0;
            id_ex_pred_counter_ff <= 2'b01;
            id_ex_pred_bht_index_ff <= '0;
            id_ex_pred_l0_taken_ff <= 1'b0;
            id_ex_valid_ff <= 1'b0;
            id_fence_i_ff <= 1'b0;
            perf_id_decode_valid <= '0;
            perf_id_issue_accept <= '0;
            perf_id_issue_fire <= '0;
            perf_id_issue_slot_valid <= '0;
            perf_id_issue_no_fire <= '0;
            perf_id_issue_wait_block <= '0;
            perf_id_wait_rs1 <= '0;
            perf_id_wait_rs2 <= '0;
            perf_id_wait_alu_ready_next_rs1 <= '0;
            perf_id_wait_alu_ready_next_rs2 <= '0;
            perf_id_wait_lsu_fwd_rs1 <= '0;
            perf_id_wait_lsu_fwd_rs2 <= '0;
            perf_id_wait_wb_fwd_rs1 <= '0;
            perf_id_wait_wb_fwd_rs2 <= '0;
            perf_id_skid_valid <= '0;
            perf_id_skid_fill <= '0;
            perf_id_skid_drain <= '0;
            perf_id_skid_full_stall <= '0;
            perf_id_frontend_stall <= '0;
            perf_ri_slot0_valid <= '0;
            perf_ri_slot1_valid <= '0;
            perf_ri_slot0_ready <= '0;
            perf_ri_slot1_ready <= '0;
            perf_ri_fire_slot0 <= '0;
            perf_ri_fire_slot1_bypass <= '0;
            perf_ri_slot1_block_raw <= '0;
            perf_ri_slot1_block_waw <= '0;
            perf_ri_slot1_block_ctrl <= '0;
            perf_ri_slot1_block_mem <= '0;
            perf_ri_slot1_block_unsupported <= '0;
            perf_ri_slot1_ready_when_slot0_blocked <= '0;
            perf_ri_slot1_ready_when_slot0_ready <= '0;
            perf_ri_slot1_fire_blocked_by_single_issue <= '0;
            perf_ri_slot1_fire_blocked_by_operand_port <= '0;
            perf_ri_slot1_fire_blocked_by_wb_order <= '0;
            perf_ri_bypass_flush_killed <= '0;
            perf_di_pipe0_fire <= '0;
            perf_di_pipe1_fire <= '0;
            perf_di_pair_fire <= '0;
            perf_di_pair_simple_alu <= '0;
            perf_di_pipe1_killed_flush <= '0;
            perf_di_pipe1_block_stall_recheck <= '0;
            perf_di_pipe1_block_resbuf_full <= '0;
            perf_di_pipe1_block_alu_fifo_full <= '0;
            perf_di_pipe1_block_pending_recheck <= '0;
            perf_di_pipe1_block_timing_guard <= '0;
            perf_dual_cycles_with_pair_fire <= '0;
            perf_dual_extra_instret_pipe1 <= '0;
            perf_dual_pipe1_useful_commit <= '0;
            perf_dual_pipe1_squashed <= '0;
            pipe1_issue_valid_ff <= 1'b0;
            pipe1_operand_a_ff <= '0;
            pipe1_operand_b_ff <= '0;
            pipe1_operator_ff <= '0;
            pipe1_rf_wen_rd_ff <= 1'b0;
            pipe1_rf_waddr_rd_ff <= '0;
            pipe1_rn_pdst_ff <= '0;
            pipe1_pc_ff <= '0;
            pipe1_instr_ff <= '0;
`ifndef SYNTHESIS
            perf_ds_cycles <= '0;
            perf_ds_pipe0_valid <= '0;
            perf_ds_pipe0_ready <= '0;
            perf_ds_pipe1_valid <= '0;
            perf_ds_pipe1_simple_alu <= '0;
            perf_ds_safe_candidate <= '0;
            perf_ds_safe_when_pipe0_ready <= '0;
            perf_ds_safe_when_pipe0_blocked <= '0;
            perf_ds_block_pipe1_unsupported <= '0;
            perf_ds_block_raw_pipe0 <= '0;
            perf_ds_block_waw_pipe0 <= '0;
            perf_ds_block_pending_rs1 <= '0;
            perf_ds_block_pending_rs2 <= '0;
            perf_ds_block_ctrl <= '0;
            perf_ds_block_mem <= '0;
            perf_ds_block_csr_sys <= '0;
            perf_ds_block_flush <= '0;
            perf_ds_block_wb_port <= '0;
            perf_ds_block_forward_complex <= '0;
            pair1_valid_ff <= 1'b0;
            pair1_pc_ff <= '0;
            pair1_instr_ff <= ydrasil_pkg::RV32I_INS_NOP;
            pair1_seq_ff <= '0;
            pair1_seq_next_ff <= '0;
            pair1_rs1_ff <= '0;
            pair1_rs2_ff <= '0;
            pair1_rd_ff <= '0;
            pair1_rs1_ren_ff <= 1'b0;
            pair1_rs2_ren_ff <= 1'b0;
            pair1_rd_wen_ff <= 1'b0;
            pair1_operator_ff <= '0;
            pair1_operator_type_ff <= '0;
            pair1_imm_ff <= '0;
            pair1_pred_hit_ff <= 1'b0;
            pair1_pred_taken_ff <= 1'b0;
            pair1_pred_target_ff <= '0;
            pair1_pred_counter_ff <= 2'b01;
            pair1_pred_bht_index_ff <= '0;
            pair1_pred_l0_taken_ff <= 1'b0;
            perf_p1sh_valid_cycles <= '0;
            perf_p1sh_simple_alu <= '0;
            perf_p1sh_safe_cand <= '0;
            perf_p1sh_block_raw_pair0 <= '0;
            perf_p1sh_block_waw_pair0 <= '0;
            perf_p1sh_block_pending_rs <= '0;
            perf_p1sh_block_ctrl_mem <= '0;
            uopq_shadow_valid <= '0;
            uopq_shadow_seq_next_ff <= '0;
            for (int uopq_i = 0; uopq_i < 4; uopq_i++) begin
                uopq_shadow_pc[uopq_i] <= '0;
                uopq_shadow_instr[uopq_i] <= ydrasil_pkg::RV32I_INS_NOP;
                uopq_shadow_seq[uopq_i] <= '0;
                uopq_shadow_rs1[uopq_i] <= '0;
                uopq_shadow_rs2[uopq_i] <= '0;
                uopq_shadow_rd[uopq_i] <= '0;
                uopq_shadow_optype[uopq_i] <= '0;
                uopq_shadow_operator[uopq_i] <= '0;
            end
            uopq_shadow_rs1_ren <= '0;
            uopq_shadow_rs2_ren <= '0;
            uopq_shadow_rd_wen <= '0;
            uopq_shadow_simple_alu <= '0;
            uopq_shadow_ctrl <= '0;
            uopq_shadow_mem <= '0;
            uopq_shadow_csr_sys_fence <= '0;
            perf_uopq_occ_0 <= '0;
            perf_uopq_occ_1 <= '0;
            perf_uopq_occ_2 <= '0;
            perf_uopq_occ_3 <= '0;
            perf_uopq_occ_4 <= '0;
            perf_uopq_p1_safe_1 <= '0;
            perf_uopq_p1_safe_2 <= '0;
            perf_uopq_p1_safe_3 <= '0;
            perf_uopq_block_older_ctrl_mem <= '0;
            perf_uopq_block_raw_older <= '0;
            perf_uopq_block_waw_older <= '0;
            perf_uopq_p1_fire_from_1 <= '0;
            perf_uopq_p1_fire_from_2 <= '0;
            perf_uopq_p1_fire_from_3 <= '0;
            perf_uopq_p1_fire_when_p0_ready <= '0;
            perf_uopq_p1_fire_when_p0_blocked <= '0;
            perf_uopq_p1_block_older_ctrl_mem <= '0;
            perf_uopq_p1_block_raw_older <= '0;
            perf_uopq_p1_block_waw_older <= '0;
            perf_uopq_p1_block_commit_order <= '0;
`endif
        end else begin
            if (flush_id_i) begin
                skid_valid_ff <= 1'b0;
                issue_valid_ff <= 1'b0;
                issue_wait_rs1_ff <= 1'b0;
                issue_wait_rs2_ff <= 1'b0;
                skid_rn_pdst_valid_ff <= 1'b0;
                issue_rn_pdst_valid_ff <= 1'b0;
                id_rn_pdst_ff <= '0;
                id_ex_valid_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
`ifndef SYNTHESIS
                alu_stable_valid_ff <= 1'b0;
`endif
                pipe1_issue_valid_ff <= 1'b0;
`ifndef SYNTHESIS
                pair1_valid_ff <= 1'b0;
                uopq_shadow_valid <= '0;
`endif
            end else begin
                if (issue_accept) begin
                    if (pair1_refill_direct) begin
                        issue_pc_ff <= if_id_pc_i;
                        issue_pred_hit_ff <= if_id_pred_hit_i;
                        issue_pred_taken_ff <= if_id_pred_taken_i;
                        issue_pred_target_ff <= if_id_pred_target_i;
                        issue_pred_counter_ff <= if_id_pred_counter_i;
                        issue_pred_bht_index_ff <= if_id_pred_bht_index_i;
                        issue_pred_l0_taken_ff <= if_id_pred_l0_taken_i;
                        issue_rf_raddr_rs1_ff <= if_id_trace_rf_raddr_rs1;
                        issue_rf_raddr_rs2_ff <= if_id_trace_rf_raddr_rs2;
                        issue_rf_ren_rs1_ff <= if_id_trace_rf_ren_rs1;
                        issue_rf_ren_rs2_ff <= if_id_trace_rf_ren_rs2;
                        issue_rf_waddr_rd_ff <= if_id_trace_rf_waddr_rd;
                        issue_rf_wen_rd_ff <= if_id_trace_rf_wen_rd;
                        issue_imm_ff <= if_id_trace_imm;
                        issue_operand_b_rs_sel_ff <= if_id_trace_operand_b_rs_sel;
                        issue_operand_a_pc_sel_ff <= if_id_trace_operand_a_pc_sel;
                        issue_operand_a_imm_sel_ff <= if_id_trace_operand_a_imm_sel;
                        issue_bt_a_rs_sel_ff <= if_id_trace_bt_a_rs_sel;
                        issue_operand_b_jump_sel_ff <= if_id_trace_operand_b_jump_sel;
                        issue_operator_ff <= if_id_trace_operator;
                        issue_operator_lsu_ff <= if_id_trace_operator_lsu;
                        issue_operator_type_ff <= if_id_trace_operator_type;
                        issue_csr_reg_raddr_ff <= if_id_trace_csr_reg_raddr;
                        issue_csr_ex_waddr_ff <= if_id_trace_csr_ex_waddr;
                        issue_csr_op_info_ff <= if_id_trace_csr_op_info;
                        issue_sys_op_info_ff <= if_id_trace_sys_op_info;
                        issue_fence_i_ff <= (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                                            (if_id_instr_i[14:12] == 3'b001);
                        issue_rn_rs1_psrc_ff <= rn_if_rs1_psrc_i;
                        issue_rn_rs2_psrc_ff <= rn_if_rs2_psrc_i;
                        issue_rn_pdst_ff <= rn_if_pdst_i;
                        issue_rn_pdst_valid_ff <= if_id_rn_pdst_valid;
                        issue_valid_ff <= if_id_valid_i;
                    end else if (pair1_fire) begin
                        issue_valid_ff <= 1'b0;
                    end else begin
                        issue_pc_ff <= decode_pc;
                        issue_pred_hit_ff <= decode_pred_hit;
                        issue_pred_taken_ff <= decode_pred_taken;
                        issue_pred_target_ff <= decode_pred_target;
                        issue_pred_counter_ff <= decode_pred_counter;
                        issue_pred_bht_index_ff <= decode_pred_bht_index;
                        issue_pred_l0_taken_ff <= decode_pred_l0_taken;
                        issue_rf_raddr_rs1_ff <= skid_valid_ff ? slot1_rf_raddr_rs1 : rf_raddr_rs1;
                        issue_rf_raddr_rs2_ff <= skid_valid_ff ? slot1_rf_raddr_rs2 : rf_raddr_rs2;
                        issue_rf_ren_rs1_ff <= skid_valid_ff ? slot1_rf_ren_rs1 : rf_ren_rs1;
                        issue_rf_ren_rs2_ff <= skid_valid_ff ? slot1_rf_ren_rs2 : rf_ren_rs2;
                        issue_rf_waddr_rd_ff <= skid_valid_ff ? slot1_rf_waddr_rd : rf_waddr_rd;
                        issue_rf_wen_rd_ff <= skid_valid_ff ? slot1_rf_wen_rd : rf_wen_rd;
                        issue_imm_ff <= skid_valid_ff ? slot1_imm : imm_i;
                        issue_operand_b_rs_sel_ff <= skid_valid_ff ? slot1_operand_b_rs_sel : operand_b_rs_sel;
                        issue_operand_a_pc_sel_ff <= skid_valid_ff ? slot1_operand_a_pc_sel : operand_a_pc_sel;
                        issue_operand_a_imm_sel_ff <= skid_valid_ff ? slot1_operand_a_imm_sel : operand_a_imm_sel;
                        issue_bt_a_rs_sel_ff <= skid_valid_ff ? slot1_bt_a_rs_sel : bt_a_rs_sel;
                        issue_operand_b_jump_sel_ff <= skid_valid_ff ? slot1_operand_b_jump_sel : operand_b_jump_sel;
                        issue_operator_ff <= skid_valid_ff ? slot1_operator : operator;
                        issue_operator_lsu_ff <= skid_valid_ff ? slot1_operator_lsu : operator_lsu;
                        issue_operator_type_ff <= skid_valid_ff ? slot1_operator_type : operator_type;
                        issue_csr_reg_raddr_ff <= skid_valid_ff ? slot1_csr_reg_raddr : csr_reg_raddr;
                        issue_csr_ex_waddr_ff <= skid_valid_ff ? slot1_csr_ex_waddr : csr_ex_waddr;
                        issue_csr_op_info_ff <= skid_valid_ff ? slot1_csr_op_info : csr_op_info;
                        issue_sys_op_info_ff <= skid_valid_ff ? slot1_sys_op_info : sys_op_info;
                        issue_fence_i_ff <= skid_valid_ff ? slot1_fence_i : id_fence_i;
                        issue_rn_rs1_psrc_ff <= skid_valid_ff ? skid_rn_rs1_psrc_ff : rn_if_rs1_psrc_i;
                        issue_rn_rs2_psrc_ff <= skid_valid_ff ? skid_rn_rs2_psrc_ff : rn_if_rs2_psrc_i;
                        issue_rn_pdst_ff <= skid_valid_ff ? skid_rn_pdst_ff : rn_if_pdst_i;
                        issue_rn_pdst_valid_ff <= skid_valid_ff ? skid_rn_pdst_valid_ff : if_id_rn_pdst_valid;
                        issue_valid_ff <= 1'b1;
                    end
                    issue_wait_rs1_ff <= 1'b0;
                    issue_wait_rs2_ff <= 1'b0;
                end else if (id_advance && issue_valid_ff) begin
                    issue_wait_rs1_ff <= issue_wait_rs1_ff | rs1_issue_alu_ready_next_i;
                    issue_wait_rs2_ff <= issue_wait_rs2_ff | rs2_issue_alu_ready_next_i;
                end

                if (issue_slot1_bypass_fire) begin
                    skid_valid_ff <= 1'b0;
`ifndef SYNTHESIS
                    pair1_valid_ff <= 1'b0;
`endif
                end else if (pair1_fire) begin
                    if (pair1_refill_direct || pipe1_fire_from2) begin
                        skid_valid_ff <= 1'b0;
`ifndef SYNTHESIS
                        pair1_valid_ff <= 1'b0;
`endif
                    end else begin
                        skid_valid_ff <= (PIPE1_REAL_MODE >= 2) & if_id_valid_i;
                        skid_pc_ff <= if_id_pc_i;
                        skid_instr_ff <= if_id_instr_i;
                        skid_pred_hit_ff <= if_id_pred_hit_i;
                        skid_pred_taken_ff <= if_id_pred_taken_i;
                        skid_pred_target_ff <= if_id_pred_target_i;
                        skid_pred_counter_ff <= if_id_pred_counter_i;
                        skid_pred_bht_index_ff <= if_id_pred_bht_index_i;
                        skid_pred_l0_taken_ff <= if_id_pred_l0_taken_i;
                        skid_rf_raddr_rs1_ff <= if_id_trace_rf_raddr_rs1;
                        skid_rf_raddr_rs2_ff <= if_id_trace_rf_raddr_rs2;
                        skid_rf_ren_rs1_ff <= if_id_trace_rf_ren_rs1;
                        skid_rf_ren_rs2_ff <= if_id_trace_rf_ren_rs2;
                        skid_rf_waddr_rd_ff <= if_id_trace_rf_waddr_rd;
                        skid_rf_wen_rd_ff <= if_id_trace_rf_wen_rd;
                        skid_imm_ff <= if_id_trace_imm;
                        skid_operand_b_rs_sel_ff <= if_id_trace_operand_b_rs_sel;
                        skid_operand_a_pc_sel_ff <= if_id_trace_operand_a_pc_sel;
                        skid_operand_a_imm_sel_ff <= if_id_trace_operand_a_imm_sel;
                        skid_bt_a_rs_sel_ff <= if_id_trace_bt_a_rs_sel;
                        skid_operand_b_jump_sel_ff <= if_id_trace_operand_b_jump_sel;
                        skid_operator_ff <= if_id_trace_operator;
                        skid_operator_lsu_ff <= if_id_trace_operator_lsu;
                        skid_operator_type_ff <= if_id_trace_operator_type;
                        skid_csr_reg_raddr_ff <= if_id_trace_csr_reg_raddr;
                        skid_csr_ex_waddr_ff <= if_id_trace_csr_ex_waddr;
                        skid_csr_op_info_ff <= if_id_trace_csr_op_info;
                        skid_sys_op_info_ff <= if_id_trace_sys_op_info;
                        skid_fence_i_ff <= (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                                           (if_id_instr_i[14:12] == 3'b001);
                        skid_rn_rs1_psrc_ff <= rn_if_rs1_psrc_i;
                        skid_rn_rs2_psrc_ff <= rn_if_rs2_psrc_i;
                        skid_rn_pdst_ff <= rn_if_pdst_i;
                        skid_rn_pdst_valid_ff <= if_id_rn_pdst_valid;
`ifndef SYNTHESIS
                        pair1_valid_ff <= (PIPE1_REAL_MODE >= 2) & if_id_valid_i;
                        if ((PIPE1_REAL_MODE >= 2) & if_id_valid_i) begin
                            pair1_pc_ff <= if_id_pc_i;
                            pair1_instr_ff <= if_id_instr_i;
                            pair1_seq_ff <= pair1_seq_next_ff;
                            pair1_seq_next_ff <= pair1_seq_next_ff + 32'd1;
                            pair1_rs1_ff <= if_id_trace_rf_raddr_rs1;
                            pair1_rs2_ff <= if_id_trace_rf_raddr_rs2;
                            pair1_rd_ff <= if_id_trace_rf_waddr_rd;
                            pair1_rs1_ren_ff <= if_id_trace_rf_ren_rs1;
                            pair1_rs2_ren_ff <= if_id_trace_rf_ren_rs2;
                            pair1_rd_wen_ff <= if_id_trace_rf_wen_rd;
                            pair1_operator_ff <= if_id_trace_operator;
                            pair1_operator_type_ff <= if_id_trace_operator_type;
                            pair1_imm_ff <= if_id_trace_imm;
                            pair1_pred_hit_ff <= if_id_pred_hit_i;
                            pair1_pred_taken_ff <= if_id_pred_taken_i;
                            pair1_pred_target_ff <= if_id_pred_target_i;
                            pair1_pred_counter_ff <= if_id_pred_counter_i;
                            pair1_pred_bht_index_ff <= if_id_pred_bht_index_i;
                            pair1_pred_l0_taken_ff <= if_id_pred_l0_taken_i;
                        end
`endif
                    end
                end else if (id_advance) begin
                    if (issue_load_from_skid) begin
                        skid_valid_ff <= if_id_valid_i;
                        skid_pc_ff <= if_id_pc_i;
                        skid_instr_ff <= if_id_instr_i;
                        skid_pred_hit_ff <= if_id_pred_hit_i;
                        skid_pred_taken_ff <= if_id_pred_taken_i;
                        skid_pred_target_ff <= if_id_pred_target_i;
                        skid_pred_counter_ff <= if_id_pred_counter_i;
                        skid_pred_bht_index_ff <= if_id_pred_bht_index_i;
                        skid_pred_l0_taken_ff <= if_id_pred_l0_taken_i;
                        skid_rf_raddr_rs1_ff <= if_id_trace_rf_raddr_rs1;
                        skid_rf_raddr_rs2_ff <= if_id_trace_rf_raddr_rs2;
                        skid_rf_ren_rs1_ff <= if_id_trace_rf_ren_rs1;
                        skid_rf_ren_rs2_ff <= if_id_trace_rf_ren_rs2;
                        skid_rf_waddr_rd_ff <= if_id_trace_rf_waddr_rd;
                        skid_rf_wen_rd_ff <= if_id_trace_rf_wen_rd;
                        skid_imm_ff <= if_id_trace_imm;
                        skid_operand_b_rs_sel_ff <= if_id_trace_operand_b_rs_sel;
                        skid_operand_a_pc_sel_ff <= if_id_trace_operand_a_pc_sel;
                        skid_operand_a_imm_sel_ff <= if_id_trace_operand_a_imm_sel;
                        skid_bt_a_rs_sel_ff <= if_id_trace_bt_a_rs_sel;
                        skid_operand_b_jump_sel_ff <= if_id_trace_operand_b_jump_sel;
                        skid_operator_ff <= if_id_trace_operator;
                        skid_operator_lsu_ff <= if_id_trace_operator_lsu;
                        skid_operator_type_ff <= if_id_trace_operator_type;
                        skid_csr_reg_raddr_ff <= if_id_trace_csr_reg_raddr;
                        skid_csr_ex_waddr_ff <= if_id_trace_csr_ex_waddr;
                        skid_csr_op_info_ff <= if_id_trace_csr_op_info;
                        skid_sys_op_info_ff <= if_id_trace_sys_op_info;
                        skid_fence_i_ff <= (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                                           (if_id_instr_i[14:12] == 3'b001);
                        skid_rn_rs1_psrc_ff <= rn_if_rs1_psrc_i;
                        skid_rn_rs2_psrc_ff <= rn_if_rs2_psrc_i;
                        skid_rn_pdst_ff <= rn_if_pdst_i;
                        skid_rn_pdst_valid_ff <= if_id_rn_pdst_valid;
`ifndef SYNTHESIS
                        pair1_valid_ff <= if_id_valid_i;
                        if (if_id_valid_i) begin
                            pair1_pc_ff <= if_id_pc_i;
                            pair1_instr_ff <= if_id_instr_i;
                            pair1_seq_ff <= pair1_seq_next_ff;
                            pair1_seq_next_ff <= pair1_seq_next_ff + 32'd1;
                            pair1_rs1_ff <= if_id_trace_rf_raddr_rs1;
                            pair1_rs2_ff <= if_id_trace_rf_raddr_rs2;
                            pair1_rd_ff <= if_id_trace_rf_waddr_rd;
                            pair1_rs1_ren_ff <= if_id_trace_rf_ren_rs1;
                            pair1_rs2_ren_ff <= if_id_trace_rf_ren_rs2;
                            pair1_rd_wen_ff <= if_id_trace_rf_wen_rd;
                            pair1_operator_ff <= if_id_trace_operator;
                            pair1_operator_type_ff <= if_id_trace_operator_type;
                            pair1_imm_ff <= if_id_trace_imm;
                            pair1_pred_hit_ff <= if_id_pred_hit_i;
                            pair1_pred_taken_ff <= if_id_pred_taken_i;
                            pair1_pred_target_ff <= if_id_pred_target_i;
                            pair1_pred_counter_ff <= if_id_pred_counter_i;
                            pair1_pred_bht_index_ff <= if_id_pred_bht_index_i;
                            pair1_pred_l0_taken_ff <= if_id_pred_l0_taken_i;
                        end
`endif
                    end else if (issue_accept) begin
                        skid_valid_ff <= 1'b0;
`ifndef SYNTHESIS
                        pair1_valid_ff <= 1'b0;
`endif
                    end else if (issue_valid_ff && issue_wait_block && !skid_valid_ff && if_id_valid_i &&
                                 !pipe1_fire_from2) begin
                        skid_valid_ff <= 1'b1;
                        skid_pc_ff <= if_id_pc_i;
                        skid_instr_ff <= if_id_instr_i;
                        skid_pred_hit_ff <= if_id_pred_hit_i;
                        skid_pred_taken_ff <= if_id_pred_taken_i;
                        skid_pred_target_ff <= if_id_pred_target_i;
                        skid_pred_counter_ff <= if_id_pred_counter_i;
                        skid_pred_bht_index_ff <= if_id_pred_bht_index_i;
                        skid_pred_l0_taken_ff <= if_id_pred_l0_taken_i;
                        skid_rf_raddr_rs1_ff <= if_id_trace_rf_raddr_rs1;
                        skid_rf_raddr_rs2_ff <= if_id_trace_rf_raddr_rs2;
                        skid_rf_ren_rs1_ff <= if_id_trace_rf_ren_rs1;
                        skid_rf_ren_rs2_ff <= if_id_trace_rf_ren_rs2;
                        skid_rf_waddr_rd_ff <= if_id_trace_rf_waddr_rd;
                        skid_rf_wen_rd_ff <= if_id_trace_rf_wen_rd;
                        skid_imm_ff <= if_id_trace_imm;
                        skid_operand_b_rs_sel_ff <= if_id_trace_operand_b_rs_sel;
                        skid_operand_a_pc_sel_ff <= if_id_trace_operand_a_pc_sel;
                        skid_operand_a_imm_sel_ff <= if_id_trace_operand_a_imm_sel;
                        skid_bt_a_rs_sel_ff <= if_id_trace_bt_a_rs_sel;
                        skid_operand_b_jump_sel_ff <= if_id_trace_operand_b_jump_sel;
                        skid_operator_ff <= if_id_trace_operator;
                        skid_operator_lsu_ff <= if_id_trace_operator_lsu;
                        skid_operator_type_ff <= if_id_trace_operator_type;
                        skid_csr_reg_raddr_ff <= if_id_trace_csr_reg_raddr;
                        skid_csr_ex_waddr_ff <= if_id_trace_csr_ex_waddr;
                        skid_csr_op_info_ff <= if_id_trace_csr_op_info;
                        skid_sys_op_info_ff <= if_id_trace_sys_op_info;
                        skid_fence_i_ff <= (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                                           (if_id_instr_i[14:12] == 3'b001);
                        skid_rn_rs1_psrc_ff <= rn_if_rs1_psrc_i;
                        skid_rn_rs2_psrc_ff <= rn_if_rs2_psrc_i;
                        skid_rn_pdst_ff <= rn_if_pdst_i;
                        skid_rn_pdst_valid_ff <= if_id_rn_pdst_valid;
`ifndef SYNTHESIS
                        pair1_valid_ff <= 1'b1;
                        pair1_pc_ff <= if_id_pc_i;
                        pair1_instr_ff <= if_id_instr_i;
                        pair1_seq_ff <= pair1_seq_next_ff;
                        pair1_seq_next_ff <= pair1_seq_next_ff + 32'd1;
                        pair1_rs1_ff <= if_id_trace_rf_raddr_rs1;
                        pair1_rs2_ff <= if_id_trace_rf_raddr_rs2;
                        pair1_rd_ff <= if_id_trace_rf_waddr_rd;
                        pair1_rs1_ren_ff <= if_id_trace_rf_ren_rs1;
                        pair1_rs2_ren_ff <= if_id_trace_rf_ren_rs2;
                        pair1_rd_wen_ff <= if_id_trace_rf_wen_rd;
                        pair1_operator_ff <= if_id_trace_operator;
                        pair1_operator_type_ff <= if_id_trace_operator_type;
                        pair1_imm_ff <= if_id_trace_imm;
                        pair1_pred_hit_ff <= if_id_pred_hit_i;
                        pair1_pred_taken_ff <= if_id_pred_taken_i;
                        pair1_pred_target_ff <= if_id_pred_target_i;
                        pair1_pred_counter_ff <= if_id_pred_counter_i;
                        pair1_pred_bht_index_ff <= if_id_pred_bht_index_i;
                        pair1_pred_l0_taken_ff <= if_id_pred_l0_taken_i;
`endif
                    end
                end

                if (stall_id_i) begin
                    // Hold ID/EX stable while EX finishes a multi-cycle operation.
                end else begin
                    if (issue_fire) begin
                        operand_a_ff        <= operand_a;
                        operand_b_ff        <= operand_b;
                        operator_ff         <= selected_operator;
                        operator_type_ff    <= selected_operator_type;
                        rf_wen_rd_ff        <= selected_rf_wen_rd;
                        rf_waddr_rd_ff      <= selected_rf_waddr_rd;
                        id_rn_pdst_ff       <= selected_rn_pdst_valid ? selected_rn_pdst : '0;
                        operator_lsu_ff     <= selected_operator_lsu;
                        id_lsu_rs2_data_ff  <= issue_rs2_data; // 直接传递寄存器数据，供LSU使用
                        id_lsu_addr_ff      <= '0;
                        id_lsu_addr_is_dtcm_ff <= 1'b0;
                        id_lsu_store_data_ff <= issue_rs2_data;
                        id_lsu_store_mask_ff <= 4'b0000;
                        bt_a_operand_ff     <= bt_a_operand;
                        bt_b_operand_ff     <= bt_b_operand;
                        csr_reg_raddr_ff <= selected_csr_reg_raddr;
                        // csr_ex_we_ff <= csr_ex_we;
                        csr_ex_waddr_ff <= selected_csr_ex_waddr;
                        csr_op_info_ff <= selected_csr_op_info;
                        sys_op_info_ff <= selected_sys_op_info;
                        id_instr_addr_ff <= selected_pc;
                        id_ex_jalr_ff <= selected_bt_a_rs_sel;
                        id_ex_pred_hit_ff <= selected_pred_hit;
                        id_ex_pred_taken_ff <= selected_pred_taken;
                        id_ex_pred_target_ff <= selected_pred_target;
                        id_ex_pred_counter_ff <= selected_pred_counter;
                        id_ex_pred_bht_index_ff <= selected_pred_bht_index;
                        id_ex_pred_l0_taken_ff <= selected_pred_l0_taken;
                        id_ex_valid_ff <= 1'b1;
                        id_fence_i_ff <= selected_fence_i;
                        if (issue_slot0_fire && !issue_accept) begin
                            issue_valid_ff <= 1'b0;
                            issue_wait_rs1_ff <= 1'b0;
                            issue_wait_rs2_ff <= 1'b0;
                        end
`ifndef SYNTHESIS
                        alu_stable_valid_ff <= issue_alu_stable_candidate;
                        alu_stable_addr_ff <= issue_rf_waddr_rd_ff;
                        alu_stable_data_ff <= issue_alu_stable_result;
`endif
                    end else begin
                        id_ex_valid_ff <= 1'b0;
                        id_fence_i_ff <= 1'b0;
                    end
                    pipe1_issue_valid_ff <= pair1_fire;
                    pipe1_operand_a_ff   <= pipe1_dual_operand_a;
                    pipe1_operand_b_ff   <= pipe1_dual_operand_b;
                    pipe1_operator_ff    <= pipe1_sel_operator;
                    pipe1_rf_wen_rd_ff   <= pipe1_sel_rf_wen_rd;
                    pipe1_rf_waddr_rd_ff <= pipe1_sel_rf_waddr_rd;
                    pipe1_rn_pdst_ff     <= (pair1_fire && pipe1_sel_pdst_valid) ? pipe1_sel_pdst : '0;
                    pipe1_pc_ff          <= pipe1_sel_pc;
                    pipe1_instr_ff       <= pipe1_sel_instr;
                end
            end
`ifndef SYNTHESIS
            if (flush_id_i) begin
                uopq_shadow_valid <= '0;
            end else begin
                uopq_shadow_valid[0] <= issue_valid_ff;
                uopq_shadow_pc[0] <= issue_pc_ff;
                uopq_shadow_instr[0] <= ydrasil_pkg::RV32I_INS_NOP;
                uopq_shadow_seq[0] <= '0;
                uopq_shadow_rs1[0] <= issue_rf_raddr_rs1_ff;
                uopq_shadow_rs2[0] <= issue_rf_raddr_rs2_ff;
                uopq_shadow_rd[0] <= issue_rf_waddr_rd_ff;
                uopq_shadow_rs1_ren[0] <= issue_rf_ren_rs1_ff;
                uopq_shadow_rs2_ren[0] <= issue_rf_ren_rs2_ff;
                uopq_shadow_rd_wen[0] <= issue_rf_wen_rd_ff;
                uopq_shadow_optype[0] <= issue_operator_type_ff;
                uopq_shadow_operator[0] <= issue_operator_ff;
                uopq_shadow_simple_alu[0] <= is_shadow_simple_alu(issue_operator_type_ff, issue_operator_ff);
                uopq_shadow_ctrl[0] <= issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP];
                uopq_shadow_mem[0] <=
                    issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
                    issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE];
                uopq_shadow_csr_sys_fence[0] <=
                    issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
                    issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] |
                    issue_fence_i_ff;

                uopq_shadow_valid[1] <= pair1_valid_ff;
                uopq_shadow_pc[1] <= pair1_pc_ff;
                uopq_shadow_instr[1] <= pair1_instr_ff;
                uopq_shadow_seq[1] <= pair1_seq_ff;
                uopq_shadow_rs1[1] <= pair1_rs1_ff;
                uopq_shadow_rs2[1] <= pair1_rs2_ff;
                uopq_shadow_rd[1] <= pair1_rd_ff;
                uopq_shadow_rs1_ren[1] <= pair1_rs1_ren_ff;
                uopq_shadow_rs2_ren[1] <= pair1_rs2_ren_ff;
                uopq_shadow_rd_wen[1] <= pair1_rd_wen_ff;
                uopq_shadow_optype[1] <= pair1_operator_type_ff;
                uopq_shadow_operator[1] <= pair1_operator_ff;
                uopq_shadow_simple_alu[1] <= is_shadow_simple_alu(pair1_operator_type_ff, pair1_operator_ff);
                uopq_shadow_ctrl[1] <= pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP];
                uopq_shadow_mem[1] <=
                    pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
                    pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE];
                uopq_shadow_csr_sys_fence[1] <=
                    pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
                    pair1_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] |
                    ((pair1_instr_ff[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                     (pair1_instr_ff[14:12] == 3'b001));

                uopq_shadow_valid[2] <=
                    if_id_valid_i &&
                    !(issue_valid_ff && (if_id_pc_i == issue_pc_ff)) &&
                    !(pair1_valid_ff && (if_id_pc_i == pair1_pc_ff));
                uopq_shadow_pc[2] <= if_id_pc_i;
                uopq_shadow_instr[2] <= if_id_instr_i;
                uopq_shadow_seq[2] <= uopq_shadow_seq_next_ff;
                uopq_shadow_rs1[2] <= if_id_trace_rf_raddr_rs1;
                uopq_shadow_rs2[2] <= if_id_trace_rf_raddr_rs2;
                uopq_shadow_rd[2] <= if_id_trace_rf_waddr_rd;
                uopq_shadow_rs1_ren[2] <= if_id_trace_rf_ren_rs1;
                uopq_shadow_rs2_ren[2] <= if_id_trace_rf_ren_rs2;
                uopq_shadow_rd_wen[2] <= if_id_trace_rf_wen_rd;
                uopq_shadow_optype[2] <= if_id_trace_operator_type;
                uopq_shadow_operator[2] <= if_id_trace_operator;
                uopq_shadow_simple_alu[2] <= is_shadow_simple_alu(if_id_trace_operator_type, if_id_trace_operator);
                uopq_shadow_ctrl[2] <= if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP];
                uopq_shadow_mem[2] <=
                    if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
                    if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];
                uopq_shadow_csr_sys_fence[2] <=
                    if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
                    if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
                    ((if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                     (if_id_instr_i[14:12] == 3'b001));

                uopq_shadow_valid[3] <= 1'b0;
                uopq_shadow_pc[3] <= '0;
                uopq_shadow_instr[3] <= ydrasil_pkg::RV32I_INS_NOP;
                uopq_shadow_seq[3] <= '0;
                uopq_shadow_rs1[3] <= '0;
                uopq_shadow_rs2[3] <= '0;
                uopq_shadow_rd[3] <= '0;
                uopq_shadow_rs1_ren[3] <= 1'b0;
                uopq_shadow_rs2_ren[3] <= 1'b0;
                uopq_shadow_rd_wen[3] <= 1'b0;
                uopq_shadow_optype[3] <= '0;
                uopq_shadow_operator[3] <= '0;
                uopq_shadow_simple_alu[3] <= 1'b0;
                uopq_shadow_ctrl[3] <= 1'b0;
                uopq_shadow_mem[3] <= 1'b0;
                uopq_shadow_csr_sys_fence[3] <= 1'b0;
                if (if_id_valid_i &&
                    !(issue_valid_ff && (if_id_pc_i == issue_pc_ff)) &&
                    !(pair1_valid_ff && (if_id_pc_i == pair1_pc_ff))) begin
                    uopq_shadow_seq_next_ff <= uopq_shadow_seq_next_ff + 32'd1;
                end
            end
`endif
            perf_id_decode_valid <= perf_id_decode_valid + (decode_valid ? 32'd1 : 32'd0);
            perf_id_issue_accept <= perf_id_issue_accept + (issue_accept ? 32'd1 : 32'd0);
            perf_id_issue_fire <= perf_id_issue_fire + (issue_fire ? 32'd1 : 32'd0);
            perf_id_issue_slot_valid <= perf_id_issue_slot_valid + (issue_valid_ff ? 32'd1 : 32'd0);
            perf_id_issue_no_fire <= perf_id_issue_no_fire +
                ((issue_valid_ff && id_advance && !issue_fire) ? 32'd1 : 32'd0);
            perf_id_issue_wait_block <= perf_id_issue_wait_block +
                (issue_wait_block ? 32'd1 : 32'd0);
            perf_id_wait_rs1 <= perf_id_wait_rs1 +
                ((issue_wait_rs1_ff && !issue_wait_rs1_ready) ? 32'd1 : 32'd0);
            perf_id_wait_rs2 <= perf_id_wait_rs2 +
                ((issue_wait_rs2_ff && !issue_wait_rs2_ready) ? 32'd1 : 32'd0);
            perf_id_wait_alu_ready_next_rs1 <= perf_id_wait_alu_ready_next_rs1 +
                (rs1_issue_alu_ready_next_i ? 32'd1 : 32'd0);
            perf_id_wait_alu_ready_next_rs2 <= perf_id_wait_alu_ready_next_rs2 +
                (rs2_issue_alu_ready_next_i ? 32'd1 : 32'd0);
            perf_id_wait_lsu_fwd_rs1 <= perf_id_wait_lsu_fwd_rs1 +
                ((issue_wait_rs1_ff && rs1_lsu_fwd) ? 32'd1 : 32'd0);
            perf_id_wait_lsu_fwd_rs2 <= perf_id_wait_lsu_fwd_rs2 +
                ((issue_wait_rs2_ff && rs2_lsu_fwd) ? 32'd1 : 32'd0);
            perf_id_wait_wb_fwd_rs1 <= perf_id_wait_wb_fwd_rs1 +
                ((issue_wait_rs1_ff && rs1_wb_fwd) ? 32'd1 : 32'd0);
            perf_id_wait_wb_fwd_rs2 <= perf_id_wait_wb_fwd_rs2 +
                ((issue_wait_rs2_ff && rs2_wb_fwd) ? 32'd1 : 32'd0);
            perf_id_skid_valid <= perf_id_skid_valid + (skid_valid_ff ? 32'd1 : 32'd0);
            perf_id_skid_fill <= perf_id_skid_fill + (skid_fill ? 32'd1 : 32'd0);
            perf_id_skid_drain <= perf_id_skid_drain + (skid_drain ? 32'd1 : 32'd0);
            perf_id_skid_full_stall <= perf_id_skid_full_stall +
                (issue_frontend_stall_o ? 32'd1 : 32'd0);
            perf_id_frontend_stall <= perf_id_frontend_stall +
                (issue_frontend_stall_o ? 32'd1 : 32'd0);
            perf_ri_slot0_valid <= perf_ri_slot0_valid + (issue_valid_ff ? 32'd1 : 32'd0);
            perf_ri_slot1_valid <= perf_ri_slot1_valid + (ri_slot1_valid ? 32'd1 : 32'd0);
            perf_ri_slot0_ready <= perf_ri_slot0_ready +
                ((issue_valid_ff && !issue_wait_block) ? 32'd1 : 32'd0);
            perf_ri_slot1_ready <= perf_ri_slot1_ready + (ri_slot1_ready ? 32'd1 : 32'd0);
            perf_ri_fire_slot0 <= perf_ri_fire_slot0 + (issue_slot0_fire ? 32'd1 : 32'd0);
            perf_ri_fire_slot1_bypass <= perf_ri_fire_slot1_bypass +
                (issue_slot1_bypass_fire ? 32'd1 : 32'd0);
            perf_ri_slot1_block_raw <= perf_ri_slot1_block_raw +
                (ri_slot1_block_raw ? 32'd1 : 32'd0);
            perf_ri_slot1_block_waw <= perf_ri_slot1_block_waw +
                (ri_slot1_block_waw ? 32'd1 : 32'd0);
            perf_ri_slot1_block_ctrl <= perf_ri_slot1_block_ctrl +
                (ri_slot1_block_ctrl ? 32'd1 : 32'd0);
            perf_ri_slot1_block_mem <= perf_ri_slot1_block_mem +
                (ri_slot1_block_mem ? 32'd1 : 32'd0);
            perf_ri_slot1_block_unsupported <= perf_ri_slot1_block_unsupported +
                (ri_slot1_block_unsupported ? 32'd1 : 32'd0);
            perf_ri_slot1_ready_when_slot0_blocked <= perf_ri_slot1_ready_when_slot0_blocked +
                (ri_slot1_ready_when_slot0_blocked ? 32'd1 : 32'd0);
            perf_ri_slot1_ready_when_slot0_ready <= perf_ri_slot1_ready_when_slot0_ready +
                (ri_slot1_ready_when_slot0_ready ? 32'd1 : 32'd0);
            perf_ri_slot1_fire_blocked_by_single_issue <= perf_ri_slot1_fire_blocked_by_single_issue +
                (ri_slot1_fire_blocked_by_single_issue ? 32'd1 : 32'd0);
            perf_ri_slot1_fire_blocked_by_wb_order <= perf_ri_slot1_fire_blocked_by_wb_order +
                (ri_slot1_fire_blocked_by_wb_order ? 32'd1 : 32'd0);
            perf_ri_bypass_flush_killed <= perf_ri_bypass_flush_killed +
                (ri_bypass_flush_killed ? 32'd1 : 32'd0);
            perf_di_pipe0_fire <= perf_di_pipe0_fire + (issue_slot0_fire ? 32'd1 : 32'd0);
`ifdef YDRASIL_ENABLE_PIPE1_REAL
            perf_di_pipe1_fire <= perf_di_pipe1_fire + (pair1_fire ? 32'd1 : 32'd0);
            perf_di_pair_fire <= perf_di_pair_fire +
                ((pair1_fire && pipe1_p0_ready_context) ? 32'd1 : 32'd0);
            perf_di_pair_simple_alu <= perf_di_pair_simple_alu +
                ((pair1_fire && pipe1_p0_ready_context) ? 32'd1 : 32'd0);
            perf_di_pipe1_killed_flush <= perf_di_pipe1_killed_flush +
                ((pipe1_issue_valid_ff && flush_id_i) ? 32'd1 : 32'd0);
            perf_di_pipe1_block_stall_recheck <= perf_di_pipe1_block_stall_recheck +
                ((pipe1_dual_supported && issue_slot0_fire && stall_id_i) ? 32'd1 : 32'd0);
            perf_di_pipe1_block_resbuf_full <= perf_di_pipe1_block_resbuf_full +
                ((pipe1_dual_supported && pipe1_resbuf_full_i) ? 32'd1 : 32'd0);
            perf_di_pipe1_block_alu_fifo_full <= perf_di_pipe1_block_alu_fifo_full + 32'd0;
            perf_di_pipe1_block_pending_recheck <= perf_di_pipe1_block_pending_recheck +
                ((pipe1_dual_supported && pipe1_dual_pending_rd) ? 32'd1 : 32'd0);
            perf_di_pipe1_block_timing_guard <= perf_di_pipe1_block_timing_guard +
                ((pipe1_dual_supported && !pipe1_dual_operands_ready) ? 32'd1 : 32'd0);
            perf_dual_cycles_with_pair_fire <= perf_dual_cycles_with_pair_fire +
                (pair1_fire ? 32'd1 : 32'd0);
            perf_dual_extra_instret_pipe1 <= perf_dual_extra_instret_pipe1 +
                (pair1_fire ? 32'd1 : 32'd0);
`endif
`ifndef SYNTHESIS
            perf_ds_cycles <= perf_ds_cycles + 32'd1;
            perf_ds_pipe0_valid <= perf_ds_pipe0_valid +
                (ds_pipe0_valid ? 32'd1 : 32'd0);
            perf_ds_pipe0_ready <= perf_ds_pipe0_ready +
                (ds_pipe0_ready ? 32'd1 : 32'd0);
            perf_ds_pipe1_valid <= perf_ds_pipe1_valid +
                (ds_pipe1_valid ? 32'd1 : 32'd0);
            perf_ds_pipe1_simple_alu <= perf_ds_pipe1_simple_alu +
                (ds_pipe1_simple_alu ? 32'd1 : 32'd0);
            perf_ds_safe_candidate <= perf_ds_safe_candidate +
                (ds_shadow_safe_candidate ? 32'd1 : 32'd0);
            perf_ds_safe_when_pipe0_ready <= perf_ds_safe_when_pipe0_ready +
                ((ds_shadow_safe_candidate && !issue_wait_block) ? 32'd1 : 32'd0);
            perf_ds_safe_when_pipe0_blocked <= perf_ds_safe_when_pipe0_blocked +
                ((ds_shadow_safe_candidate && issue_wait_block) ? 32'd1 : 32'd0);
            perf_ds_block_pipe1_unsupported <= perf_ds_block_pipe1_unsupported +
                (ds_pipe1_unsupported ? 32'd1 : 32'd0);
            perf_ds_block_raw_pipe0 <= perf_ds_block_raw_pipe0 +
                (ds_block_raw_pipe0 ? 32'd1 : 32'd0);
            perf_ds_block_waw_pipe0 <= perf_ds_block_waw_pipe0 +
                (ds_block_waw_pipe0 ? 32'd1 : 32'd0);
            perf_ds_block_pending_rs1 <= perf_ds_block_pending_rs1 +
                (ds_block_pending_rs1 ? 32'd1 : 32'd0);
            perf_ds_block_pending_rs2 <= perf_ds_block_pending_rs2 +
                (ds_block_pending_rs2 ? 32'd1 : 32'd0);
            perf_ds_block_ctrl <= perf_ds_block_ctrl +
                (ds_block_ctrl ? 32'd1 : 32'd0);
            perf_ds_block_mem <= perf_ds_block_mem +
                (ds_block_mem ? 32'd1 : 32'd0);
            perf_ds_block_csr_sys <= perf_ds_block_csr_sys +
                (ds_block_csr_sys ? 32'd1 : 32'd0);
            perf_ds_block_flush <= perf_ds_block_flush +
                (ds_block_flush ? 32'd1 : 32'd0);
            perf_ds_block_wb_port <= perf_ds_block_wb_port +
                (ds_block_wb_port ? 32'd1 : 32'd0);
            perf_ds_block_forward_complex <= perf_ds_block_forward_complex +
                (ds_block_forward_complex ? 32'd1 : 32'd0);
            perf_p1sh_valid_cycles <= perf_p1sh_valid_cycles +
                (pair1_valid_ff ? 32'd1 : 32'd0);
            perf_p1sh_simple_alu <= perf_p1sh_simple_alu +
                (p1sh_simple_alu ? 32'd1 : 32'd0);
            perf_p1sh_safe_cand <= perf_p1sh_safe_cand +
                (p1sh_safe_cand ? 32'd1 : 32'd0);
            perf_p1sh_block_raw_pair0 <= perf_p1sh_block_raw_pair0 +
                (p1sh_block_raw_pair0 ? 32'd1 : 32'd0);
            perf_p1sh_block_waw_pair0 <= perf_p1sh_block_waw_pair0 +
                (p1sh_block_waw_pair0 ? 32'd1 : 32'd0);
            perf_p1sh_block_pending_rs <= perf_p1sh_block_pending_rs +
                (p1sh_block_pending_rs ? 32'd1 : 32'd0);
            perf_p1sh_block_ctrl_mem <= perf_p1sh_block_ctrl_mem +
                (p1sh_block_ctrl_mem ? 32'd1 : 32'd0);
            perf_uopq_occ_0 <= perf_uopq_occ_0 +
                ((uopq_shadow_occupancy == 3'd0) ? 32'd1 : 32'd0);
            perf_uopq_occ_1 <= perf_uopq_occ_1 +
                ((uopq_shadow_occupancy == 3'd1) ? 32'd1 : 32'd0);
            perf_uopq_occ_2 <= perf_uopq_occ_2 +
                ((uopq_shadow_occupancy == 3'd2) ? 32'd1 : 32'd0);
            perf_uopq_occ_3 <= perf_uopq_occ_3 +
                ((uopq_shadow_occupancy == 3'd3) ? 32'd1 : 32'd0);
            perf_uopq_occ_4 <= perf_uopq_occ_4 +
                ((uopq_shadow_occupancy == 3'd4) ? 32'd1 : 32'd0);
            perf_uopq_p1_safe_1 <= perf_uopq_p1_safe_1 +
                (uopq_shadow_p1_safe[1] ? 32'd1 : 32'd0);
            perf_uopq_p1_safe_2 <= perf_uopq_p1_safe_2 +
                (uopq_shadow_p1_safe[2] ? 32'd1 : 32'd0);
            perf_uopq_p1_safe_3 <= perf_uopq_p1_safe_3 +
                (uopq_shadow_p1_safe[3] ? 32'd1 : 32'd0);
            perf_uopq_block_older_ctrl_mem <= perf_uopq_block_older_ctrl_mem +
                ((uopq_shadow_older_ctrl_mem[1] |
                  uopq_shadow_older_ctrl_mem[2] |
                  uopq_shadow_older_ctrl_mem[3]) ? 32'd1 : 32'd0);
            perf_uopq_block_raw_older <= perf_uopq_block_raw_older +
                ((uopq_shadow_raw_older[1] |
                  uopq_shadow_raw_older[2] |
                  uopq_shadow_raw_older[3]) ? 32'd1 : 32'd0);
            perf_uopq_block_waw_older <= perf_uopq_block_waw_older +
                ((uopq_shadow_waw_older[1] |
                  uopq_shadow_waw_older[2] |
                  uopq_shadow_waw_older[3]) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_from_1 <= perf_uopq_p1_fire_from_1 +
                (pipe1_fire_from1 ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_from_2 <= perf_uopq_p1_fire_from_2 +
                (pipe1_fire_from2 ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_from_3 <= perf_uopq_p1_fire_from_3 + 32'd0;
            perf_uopq_p1_fire_when_p0_ready <= perf_uopq_p1_fire_when_p0_ready +
                ((pair1_fire && pipe1_p0_ready_context) ? 32'd1 : 32'd0);
            perf_uopq_p1_fire_when_p0_blocked <= perf_uopq_p1_fire_when_p0_blocked +
                ((pair1_fire && pipe1_p0_blocked_context) ? 32'd1 : 32'd0);
            perf_uopq_p1_block_older_ctrl_mem <= perf_uopq_p1_block_older_ctrl_mem +
                (((pipe1_uopq1_supported | pipe1_uopq2_supported) &&
                  !pipe1_dual_pipe0_safe) ? 32'd1 : 32'd0);
            perf_uopq_p1_block_raw_older <= perf_uopq_p1_block_raw_older +
                (pipe1_dual_raw_pipe0 ? 32'd1 : 32'd0);
            perf_uopq_p1_block_waw_older <= perf_uopq_p1_block_waw_older +
                (pipe1_dual_waw_pipe0 ? 32'd1 : 32'd0);
            perf_uopq_p1_block_commit_order <= perf_uopq_p1_block_commit_order +
                ((issue_valid_ff && id_advance && issue_wait_block &&
                  pipe1_uopq1_safe && !pipe1_resbuf_full_i) ? 32'd1 : 32'd0);
`endif
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && ds_shadow_safe_candidate) begin
            if (!ds_pipe1_simple_alu || ds_pipe1_ctrl || ds_pipe1_mem || ds_pipe1_csr_sys) begin
                $fatal(1, "dual shadow candidate has pipe1 side effect");
            end
            if (ds_pipe0_ctrl || ds_pipe0_mem || ds_pipe0_csr_sys || ds_pipe0_mul) begin
                $fatal(1, "dual shadow candidate has unsafe pipe0 class");
            end
            if (ds_block_raw_pipe0 || ds_block_waw_pipe0 ||
                ds_block_pending_rs1 || ds_block_pending_rs2) begin
                $fatal(1, "dual shadow candidate has unresolved register hazard");
            end
            if (flush_id_i || stall_id_i) begin
                $fatal(1, "dual shadow candidate survived flush/stall");
            end
        end
    end
`endif

    assign operand_a_o          = operand_a_ff;
    assign operand_b_o          = operand_b_ff;
    assign operator_o           = operator_ff;
    assign id_alu_rf_wen_rd_o   = rf_wen_rd_ff;
    assign id_rf_waddr_rd_o     = rf_waddr_rd_ff;
`ifndef SYNTHESIS
    assign id_alu_stable_valid_o = alu_stable_valid_ff;
    assign id_alu_stable_addr_o  = alu_stable_addr_ff;
    assign id_alu_stable_data_o  = alu_stable_data_ff;
`endif
    assign operator_lsu_o       = operator_lsu_ff;
    assign operator_type_o      = operator_type_ff;
    assign id_lsu_rs2_data_o    = id_lsu_rs2_data_ff; // 直接传递寄存器数据，供LSU使用
    assign id_lsu_addr_o        = id_lsu_addr_ff;
    assign id_lsu_addr_is_dtcm_o = id_lsu_addr_is_dtcm_ff;
    assign id_lsu_store_data_o  = id_lsu_store_data_ff;
    assign id_lsu_store_mask_o  = id_lsu_store_mask_ff;
    assign bt_a_operand_o       = bt_a_operand_ff;
    assign bt_b_operand_o       = bt_b_operand_ff;
    assign  id_csr_raddr_o = csr_reg_raddr_ff;
    // assign  id_ex_csr_we_o = csr_ex_we_ff;
    assign  id_ex_csr_waddr_o = csr_ex_waddr_ff;
    assign  id_op_csr_info_o = csr_op_info_ff;
    assign  id_op_sys_info_o = sys_op_info_ff;
    assign id_instr_addr_o = id_instr_addr_ff;
    assign id_ex_jalr_o = id_ex_jalr_ff;
    assign id_fence_i_o = id_fence_i_ff;
    assign id_ex_pred_hit_o = id_ex_pred_hit_ff;
    assign id_ex_pred_taken_o = id_ex_pred_taken_ff;
    assign id_ex_pred_target_o = id_ex_pred_target_ff;
    assign id_ex_pred_counter_o = id_ex_pred_counter_ff;
    assign id_ex_pred_bht_index_o = id_ex_pred_bht_index_ff;
    assign id_ex_pred_l0_taken_o = id_ex_pred_l0_taken_ff;
    assign id_ex_valid_o = id_ex_valid_ff;
`ifdef YDRASIL_ENABLE_PIPE1_REAL
    assign pipe1_issue_valid_o = pipe1_issue_valid_ff;
    assign pipe1_operand_a_o = pipe1_operand_a_ff;
    assign pipe1_operand_b_o = pipe1_operand_b_ff;
    assign pipe1_operator_o = pipe1_operator_ff;
    assign pipe1_rf_wen_rd_o = pipe1_rf_wen_rd_ff;
    assign pipe1_rf_waddr_rd_o = pipe1_rf_waddr_rd_ff;
    assign pipe1_rn_pdst_o = pipe1_rn_pdst_ff;
    assign pipe1_pc_o = pipe1_pc_ff;
    assign pipe1_instr_o = pipe1_instr_ff;
`else
    assign pipe1_issue_valid_o = 1'b0;
    assign pipe1_operand_a_o = '0;
    assign pipe1_operand_b_o = '0;
    assign pipe1_operator_o = '0;
    assign pipe1_rf_wen_rd_o = 1'b0;
    assign pipe1_rf_waddr_rd_o = '0;
    assign pipe1_rn_pdst_o = '0;
    assign pipe1_pc_o = '0;
    assign pipe1_instr_o = '0;
`endif

    assign id_ctrl_rs1_addr_o = issue_rf_raddr_rs1_ff;
    assign id_ctrl_rs2_addr_o = issue_rf_raddr_rs2_ff;
    assign id_ctrl_rs1_ren_o = issue_valid_ff & issue_rf_ren_rs1_ff;
    assign id_ctrl_rs2_ren_o = issue_valid_ff &
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign id_ctrl_rd_wen_o = issue_valid_ff & (issue_rf_waddr_rd_ff != '0) &
        (issue_rf_wen_rd_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD]);
    assign id_ctrl_rd_addr_o = issue_rf_waddr_rd_ff;
    assign id_ctrl_lsu_req_o = issue_valid_ff &
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign id_ctrl_rs1_psrc_o = issue_rn_rs1_psrc_ff;
    assign id_ctrl_rs2_psrc_o = issue_rn_rs2_psrc_ff;
    assign id_ctrl_pdst_o = issue_rn_pdst_valid_ff ? issue_rn_pdst_ff : '0;
    assign pipe1_ctrl_rs1_ren_o = pipe1_sel_rf_ren_rs1;
    assign pipe1_ctrl_rs2_ren_o = pipe1_sel_rf_ren_rs2;
    assign pipe1_ctrl_rs1_psrc_o = pipe1_sel_rs1_psrc;
    assign pipe1_ctrl_rs2_psrc_o = pipe1_sel_rs2_psrc;
    assign id_rn_pdst_o = id_rn_pdst_ff;
    assign rn_if_rd_valid_o = if_id_rn_pdst_valid;
    assign rn_alloc_valid_o =
        if_id_rn_pdst_valid && !flush_id_i &&
        !((PIPE1_REAL_MODE < 2) && pair1_fire) &&
        ((issue_accept && !skid_valid_ff) ||
         issue_load_from_skid ||
         skid_fill);
    assign rn_alloc_rd_addr_o = if_id_trace_rf_waddr_rd;
`ifndef SYNTHESIS
    assign id_ctrl_operator_type_o = issue_valid_ff ? issue_operator_type_ff : '0;
`endif

`ifndef SYNTHESIS
    assign commit_trace_alloc_if_id =
        if_id_valid_i && !flush_id_i &&
        !((PIPE1_REAL_MODE < 2) && pair1_fire) &&
        ((issue_accept && !skid_valid_ff) ||
         issue_load_from_skid ||
         skid_fill);
    assign commit_trace_alloc_valid_o =
        commit_trace_alloc_if_id &&
        (if_id_trace_rf_waddr_rd != '0) &&
        (if_id_trace_rf_wen_rd |
         if_id_trace_operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD]);
    assign commit_trace_alloc_pc_o = if_id_pc_i;
    assign commit_trace_alloc_instr_o = if_id_instr_i;
`endif

endmodule
