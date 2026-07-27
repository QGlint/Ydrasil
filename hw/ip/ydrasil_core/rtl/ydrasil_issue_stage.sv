
module ydrasil_issue_stage
import ydrasil_pkg::*;
 #(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            stall_id_i,
    input  wire                            bubble_id_i,
    input  wire                            flush_id_i,

    input  ydrasil_issue_pkt_t              issue_pkt_i,
    input  ydrasil_issue_pkt_t              issue_pkt1_i,
    output wire                            issue_ready_o,
    output wire                            issue_consume_two_o,
    output wire                            issue_slot1_replay_o,
	output ydrasil_issue_feedback_pkt_t     issue_feedback_o,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    output wire [4:0]                      rf_addr_rs3_o,
    output wire [4:0]                      rf_addr_rs4_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs3_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs4_i,
    output wire [4:0]                      fpr_addr_rs1_o,
    output wire [4:0]                      fpr_addr_rs2_o,
    output wire [4:0]                      fpr_addr_rs3_o,
    input  wire [DATA_WIDTH-1:0]           fpr_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           fpr_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]           fpr_rdata_rs3_i,
    input  ydrasil_issue_wb_pkt_t          issue_wb_i,
    input  ydrasil_completion_bus_t        completion_bus_i,

    // Dispatch to EX   
    // output wire                            alu_valid_o,
    output wire [DATA_WIDTH-1:0]           operand_a_o,
    output wire [DATA_WIDTH-1:0]           operand_b_o,
    output wire [DATA_WIDTH-1:0]           alu_operand_a_o,
    output wire [DATA_WIDTH-1:0]           alu_operand_b_o,
    output wire [DATA_WIDTH-1:0]           bru_operand_a_o,
    output wire [DATA_WIDTH-1:0]           bru_operand_b_o,
    output wire [DATA_WIDTH-1:0]           lsu_operand_a_o,
    output wire [DATA_WIDTH-1:0]           lsu_operand_b_o,
    output wire [DATA_WIDTH-1:0]           mul_operand_a_o,
    output wire [DATA_WIDTH-1:0]           mul_operand_b_o,
    output wire [DATA_WIDTH-1:0]           csr_operand_a_o,
    output wire [DATA_WIDTH-1:0]           csr_operand_b_o,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      operator_o, // 统一的ALU操作信息信号

    output wire [DATA_WIDTH-1:0]           bt_a_operand_o,
    output wire [DATA_WIDTH-1:0]           bt_b_operand_o,

    output ydrasil_lsu_req_pkt_t           lsu_req_o,
    output ydrasil_fpu_req_pkt_t           fpu_req_o,

    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    output wire                            id_ex_jalr_o,
    output wire                            id_ex_alu_bypass_rs1_o,
    output wire                            id_ex_alu_bypass_rs2_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_target_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_next_pc_o,
    output wire                            id_ex_branch_eq_o,
    output wire                            id_ex_branch_ge_signed_o,
    output wire                            id_ex_branch_ge_unsigned_o,
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
    output wire                            id_ex_valid_o,
    output producer_id_t                   id_ex_producer_id_o,
    output wire                            id_ex_producer_tracked_o,
    output wire [DATA_WIDTH-1:0]           dual_operand_a_o,
    output wire [DATA_WIDTH-1:0]           dual_operand_b_o,
    output wire [OPERATOR_WIDTH-1:0]       dual_operator_o,
    output wire [OPERATOR_TYPE_WIDTH-1:0]  dual_operator_type_o,
    output wire [OP_LSU_INFO_WIDTH-1:0]    dual_operator_lsu_o,
    output wire [DATA_WIDTH-1:0]           dual_store_data_o,
    output wire                            dual_store_data_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0]      dual_rf_waddr_o,
    output producer_id_t                   dual_producer_id_o,
    output wire                            dual_producer_tracked_o,
    output wire                            dual_valid_o,
    output wire [INST_ADDR_WIDTH-1:0]      dual_pc_o,
    output wire [INST_DATA_WIDTH-1:0]      dual_instr_o,
    // Generic writeback information
    output wire                            id_alu_rf_wen_rd_o,
    output wire [4:0]                      id_rf_waddr_rd_o


);

    reg [4:0]                           rf_waddr_rd_ff;
    reg                                 rf_wen_rd_ff;
    producer_id_t                       producer_id_ff;
    reg                                 producer_tracked_ff;

	reg [DATA_WIDTH-1:0]                id_lsu_store_data_ff;
	reg                                 id_lsu_store_data_valid_ff;

    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]       operator_type_ff;

    wire [DATA_WIDTH-1:0]                operand_a;
    wire [DATA_WIDTH-1:0]                operand_b;
    reg [DATA_WIDTH-1:0]                operand_a_ff;
    reg [DATA_WIDTH-1:0]                operand_b_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]           operator_ff;

    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]         operator_lsu_ff;
    ydrasil_fpu_op_t                                 fpu_op_ff;
    reg [2:0]                                        fpu_rm_ff;
    reg                                              fpu_illegal_ff;
    reg                                              fpu_rd_fpr_ff;
    reg                                              fpu_rd_gpr_ff;
    reg [DATA_WIDTH-1:0]                             fpu_operand_a_ff;
    reg [DATA_WIDTH-1:0]                             fpu_operand_b_ff;
    reg [DATA_WIDTH-1:0]                             fpu_operand_c_ff;
    reg [INST_DATA_WIDTH-1:0]                        fpu_instr_ff;

    wire [DATA_WIDTH-1:0]                bt_a_operand;
    wire [DATA_WIDTH-1:0]                bt_b_operand;
    reg [DATA_WIDTH-1:0]                 bt_a_operand_ff;
    reg [DATA_WIDTH-1:0]                 bt_b_operand_ff;
    reg [DATA_WIDTH-1:0]                 id_instr_addr_ff;
    reg                                  id_ex_jalr_ff;
    (* max_fanout = 8 *) reg             id_ex_alu_bypass_rs1_ff;
    (* max_fanout = 8 *) reg             id_ex_alu_bypass_rs2_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_branch_pc_target_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_branch_next_pc_ff;
    reg                                  id_ex_pred_hit_ff;
    reg                                  id_ex_pred_taken_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_target_ff;
    reg [1:0]                            id_ex_pred_counter_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_bht_index_ff;
    reg                                  id_ex_valid_ff;
    reg                                  id_fence_i_ff;
    reg [DATA_WIDTH-1:0]                 dual_operand_a_q;
    reg [DATA_WIDTH-1:0]                 dual_operand_b_q;
    reg [OPERATOR_WIDTH-1:0]             dual_operator_q;
    reg [OPERATOR_TYPE_WIDTH-1:0]        dual_operator_type_q;
    reg [OP_LSU_INFO_WIDTH-1:0]          dual_operator_lsu_q;
    reg [DATA_WIDTH-1:0]                 dual_store_data_q;
    reg                                  dual_store_data_valid_q;
    reg [REGS_ADDR_WIDTH-1:0]            dual_rf_waddr_q;
    producer_id_t                        dual_producer_id_q;
    reg                                  dual_producer_tracked_q;
    reg                                  dual_valid_q;
    reg [INST_ADDR_WIDTH-1:0]            dual_pc_q;
    reg [INST_DATA_WIDTH-1:0]            dual_instr_q;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr_ff;

    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr_ff; 
	reg [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]  csr_op_info_ff;

    reg [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   sys_op_info_ff;

    ydrasil_decode_pkt_t decode_pkt_i;
    ydrasil_decode_pkt_t decode_pkt1_i;
    assign decode_pkt_i = issue_pkt_i.decode;
    assign decode_pkt1_i = issue_pkt1_i.decode;
    ydrasil_hzd_status_pkt_t hzd_status_i;
    ydrasil_hzd_status_pkt_t hzd_status1_i;
    ydrasil_gpr_fwd_pkt_t wb_fwd_i;
    ydrasil_gpr_fwd_pkt_t wb_fwd1_i;
    ydrasil_gpr_fwd_pkt_t producer_rs1_fwd_i;
    ydrasil_gpr_fwd_pkt_t producer_rs2_fwd_i;
    ydrasil_gpr_fwd_pkt_t producer_rs3_fwd_i;
    ydrasil_gpr_fwd_pkt_t producer_rs4_fwd_i;
    assign hzd_status_i = issue_pkt_i.schedule.hazard;
    assign hzd_status1_i = issue_pkt1_i.schedule.hazard;
    assign wb_fwd_i = issue_wb_i.wb0;
    assign wb_fwd1_i = issue_wb_i.wb1;
    assign producer_rs1_fwd_i = issue_pkt_i.schedule.src1;
    assign producer_rs2_fwd_i = issue_pkt_i.schedule.src2;
    assign producer_rs3_fwd_i = issue_pkt1_i.schedule.src1;
    assign producer_rs4_fwd_i = issue_pkt1_i.schedule.src2;

    wire                            id_advance;
    wire                            issue_valid_ff = issue_pkt_i.valid;
    wire [DATA_WIDTH-1:0]           issue_pc_ff = decode_pkt_i.pc;
    wire                            issue_pred_hit_ff = decode_pkt_i.pred_hit;
    wire                            issue_pred_taken_ff = decode_pkt_i.pred_taken;
    wire [DATA_WIDTH-1:0]           issue_pred_target_ff = decode_pkt_i.pred_target;
    wire [1:0]                      issue_pred_counter_ff = decode_pkt_i.pred_counter;
    wire [DATA_WIDTH-1:0]           issue_pred_bht_index_ff = decode_pkt_i.pred_bht_index;
    wire [4:0]                      issue_rf_raddr_rs1_ff = decode_pkt_i.rs1_addr;
    wire [4:0]                      issue_rf_raddr_rs2_ff = decode_pkt_i.rs2_addr;
    wire                            issue_rf_ren_rs1_ff = decode_pkt_i.rs1_ren;
    wire                            issue_rf_ren_rs2_ff = decode_pkt_i.rs2_ren;
    wire [4:0]                      issue_rf_waddr_rd_ff = decode_pkt_i.rd_addr;
    wire                            issue_rf_wen_rd_ff = decode_pkt_i.rd_wen;
    wire [DATA_WIDTH-1:0]           issue_imm_ff = decode_pkt_i.imm;
    wire                            issue_operand_b_rs_sel_ff = decode_pkt_i.operand_b_rs_sel;
    wire                            issue_operand_a_pc_sel_ff = decode_pkt_i.operand_a_pc_sel;
    wire                            issue_operand_a_imm_sel_ff = decode_pkt_i.operand_a_imm_sel;
    wire                            issue_bt_a_rs_sel_ff = decode_pkt_i.bt_a_rs_sel;
    wire                            issue_operand_b_jump_sel_ff = decode_pkt_i.operand_b_jump_sel;
    wire [OPERATOR_WIDTH-1:0]       issue_operator_ff = decode_pkt_i.operator_info;
    wire [OP_LSU_INFO_WIDTH-1:0]    issue_operator_lsu_ff = decode_pkt_i.operator_lsu;
    wire [OPERATOR_TYPE_WIDTH-1:0]  issue_operator_type_ff = decode_pkt_i.operator_type;
    wire [CSR_ADDR_WIDTH-1:0]       issue_csr_reg_raddr_ff = decode_pkt_i.csr_raddr;
    wire [CSR_ADDR_WIDTH-1:0]       issue_csr_ex_waddr_ff = decode_pkt_i.csr_waddr;
    wire [OP_CSR_INFO_WIDTH-1:0]    issue_csr_op_info_ff = decode_pkt_i.csr_op_info;
    wire [OP_SYS_INFO_WIDTH-1:0]    issue_sys_op_info_ff = decode_pkt_i.sys_op_info;
    wire                            issue_fence_i_ff = decode_pkt_i.fence_i;
    wire [4:0] issue1_rs1_addr = decode_pkt1_i.rs1_addr;
    wire [4:0] issue1_rs2_addr = decode_pkt1_i.rs2_addr;
    wire issue1_rs1_ren = issue_pkt1_i.ctrl.rs1_ren;
    wire issue1_rs2_ren = issue_pkt1_i.ctrl.rs2_ren;
    wire issue1_rd_wen = issue_pkt1_i.ctrl.rd_wen;
    wire slot1_memory = issue_pkt1_i.memory_op;
    // Pair eligibility belongs to the packed ID contract.  A lane1 hazard is
    // handled locally as a replay so lane0 can advance without backpressuring
    // ID or changing its two-packet transfer.
    wire pair_eligible = issue_pkt_i.pair_eligible;
    wire slot1_replay = pair_eligible && hzd_status1_i.scoreboard_stall;
    wire pair_issue = pair_eligible && !slot1_replay;

    // LSU completions terminate in BRU-specific holding registers while a
    // branch waits at the issue head.  The EX BRU still sees only its normal
    // registered operands; no completion input is added to the EX muxes.
    reg bru_lsu_rs1_valid_q;
    reg bru_lsu_rs2_valid_q;
    producer_id_t bru_lsu_rs1_tag_q;
    producer_id_t bru_lsu_rs2_tag_q;
    reg [DATA_WIDTH-1:0] bru_lsu_rs1_data_q;
    reg [DATA_WIDTH-1:0] bru_lsu_rs2_data_q;
    wire issue_is_branch = issue_pkt_i.valid &&
        decode_pkt_i.operator_type[OPERATOR_TYPE_BJP];
    wire lsu_bru_rs1_capture = issue_is_branch &&
        producer_rs1_fwd_i.producer_tracked && completion_bus_i[COMPLETION_LSU].valid &&
        completion_bus_i[COMPLETION_LSU].producer_tracked &&
        (producer_rs1_fwd_i.producer_id == completion_bus_i[COMPLETION_LSU].producer_id);
    wire lsu_bru_rs2_capture = issue_is_branch &&
        producer_rs2_fwd_i.producer_tracked && completion_bus_i[COMPLETION_LSU].valid &&
        completion_bus_i[COMPLETION_LSU].producer_tracked &&
        (producer_rs2_fwd_i.producer_id == completion_bus_i[COMPLETION_LSU].producer_id);
    wire bru_lsu_rs1_hit = issue_is_branch && bru_lsu_rs1_valid_q &&
        producer_rs1_fwd_i.producer_tracked &&
        (bru_lsu_rs1_tag_q == producer_rs1_fwd_i.producer_id);
    wire bru_lsu_rs2_hit = issue_is_branch && bru_lsu_rs2_valid_q &&
        producer_rs2_fwd_i.producer_tracked &&
        (bru_lsu_rs2_tag_q == producer_rs2_fwd_i.producer_id);
	assign issue_feedback_o.bru_lsu_rs1_hit = bru_lsu_rs1_hit;
	assign issue_feedback_o.bru_lsu_rs2_hit = bru_lsu_rs2_hit;
`ifndef SYNTHESIS
    // Retain zero-valued observability points used by the coverage testbench.
    // The former issue-stage early ALU is intentionally removed from hardware.
    wire issue_early_alu_valid_ff = 1'b0;
    wire [5:0] issue_early_kind_ff = '0;
    wire [REGS_ADDR_WIDTH-1:0] issue_early_alu_addr_ff = '0;
    wire rs1_issue_early_alu_fwd = 1'b0;
    wire rs2_issue_early_alu_fwd = 1'b0;
    wire issue_simple_alu_op = 1'b0;
`endif
    assign id_advance = !stall_id_i && !bubble_id_i;
    assign issue_ready_o = id_advance;
    assign issue_consume_two_o = id_advance && pair_eligible;
    assign issue_slot1_replay_o = id_advance && slot1_replay;

    assign rf_addr_rs1_o = issue_rf_raddr_rs1_ff;
    assign rf_addr_rs2_o = issue_rf_raddr_rs2_ff;
    assign rf_addr_rs3_o = issue1_rs1_addr;
    assign rf_addr_rs4_o = issue1_rs2_addr;
    assign fpr_addr_rs1_o = decode_pkt_i.fp_rs1_addr;
    assign fpr_addr_rs2_o = decode_pkt_i.fp_rs2_addr;
    assign fpr_addr_rs3_o = decode_pkt_i.fp_rs3_addr;

    // Keep ALU source selection consistent with decoder control outputs.
    wire rs1_wb_fwd =
        wb_fwd_i.valid &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == wb_fwd_i.addr);
    wire rs2_wb_fwd =
        wb_fwd_i.valid &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == wb_fwd_i.addr);
    wire rs1_wb_fwd1 = wb_fwd1_i.valid && issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) && (issue_rf_raddr_rs1_ff == wb_fwd1_i.addr);
    wire rs2_wb_fwd1 = wb_fwd1_i.valid &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) && (issue_rf_raddr_rs2_ff == wb_fwd1_i.addr);
    wire issue_plain_alu_op =
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
`ifndef SYNTHESIS
    wire rs1_completion_fwd =
        (completion_bus_i[0].valid && completion_bus_i[0].producer_tracked &&
         producer_rs1_fwd_i.producer_tracked &&
         (completion_bus_i[0].producer_id == producer_rs1_fwd_i.producer_id)) ||
        (completion_bus_i[1].valid && completion_bus_i[1].producer_tracked &&
         producer_rs1_fwd_i.producer_tracked &&
         (completion_bus_i[1].producer_id == producer_rs1_fwd_i.producer_id)) ||
        (completion_bus_i[2].valid && completion_bus_i[2].producer_tracked &&
         producer_rs1_fwd_i.producer_tracked &&
         (completion_bus_i[2].producer_id == producer_rs1_fwd_i.producer_id)) ||
        (completion_bus_i[3].valid && completion_bus_i[3].producer_tracked &&
         producer_rs1_fwd_i.producer_tracked &&
         (completion_bus_i[3].producer_id == producer_rs1_fwd_i.producer_id));
    wire rs2_completion_fwd =
        (completion_bus_i[0].valid && completion_bus_i[0].producer_tracked &&
         producer_rs2_fwd_i.producer_tracked &&
         (completion_bus_i[0].producer_id == producer_rs2_fwd_i.producer_id)) ||
        (completion_bus_i[1].valid && completion_bus_i[1].producer_tracked &&
         producer_rs2_fwd_i.producer_tracked &&
         (completion_bus_i[1].producer_id == producer_rs2_fwd_i.producer_id)) ||
        (completion_bus_i[2].valid && completion_bus_i[2].producer_tracked &&
         producer_rs2_fwd_i.producer_tracked &&
         (completion_bus_i[2].producer_id == producer_rs2_fwd_i.producer_id)) ||
        (completion_bus_i[3].valid && completion_bus_i[3].producer_tracked &&
         producer_rs2_fwd_i.producer_tracked &&
         (completion_bus_i[3].producer_id == producer_rs2_fwd_i.producer_id));
`endif
    wire [DATA_WIDTH-1:0] issue_rs1_data =
        bru_lsu_rs1_hit ? bru_lsu_rs1_data_q :
        producer_rs1_fwd_i.valid ? producer_rs1_fwd_i.data :
        rs1_wb_fwd1 ? wb_fwd1_i.data :
        rs1_wb_fwd  ? wb_fwd_i.data  : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_rs2_data =
        bru_lsu_rs2_hit ? bru_lsu_rs2_data_q :
        producer_rs2_fwd_i.valid ? producer_rs2_fwd_i.data :
        rs2_wb_fwd1 ? wb_fwd1_i.data :
        rs2_wb_fwd  ? wb_fwd_i.data  : rf_rdata_rs2_i;

    wire issue1_rs1_wb0 = wb_fwd_i.valid && issue1_rs1_ren &&
        (issue1_rs1_addr != '0) && (issue1_rs1_addr == wb_fwd_i.addr);
    wire issue1_rs2_wb0 = wb_fwd_i.valid && issue1_rs2_ren &&
        (issue1_rs2_addr != '0) && (issue1_rs2_addr == wb_fwd_i.addr);
    wire issue1_rs1_wb1 = wb_fwd1_i.valid && issue1_rs1_ren &&
        (issue1_rs1_addr != '0) && (issue1_rs1_addr == wb_fwd1_i.addr);
    wire issue1_rs2_wb1 = wb_fwd1_i.valid && issue1_rs2_ren &&
        (issue1_rs2_addr != '0) && (issue1_rs2_addr == wb_fwd1_i.addr);
    wire [DATA_WIDTH-1:0] issue1_rs1_data =
        producer_rs3_fwd_i.valid ? producer_rs3_fwd_i.data :
        issue1_rs1_wb1 ? wb_fwd1_i.data :
        issue1_rs1_wb0 ? wb_fwd_i.data : rf_rdata_rs3_i;
    wire [DATA_WIDTH-1:0] issue1_rs2_data =
        producer_rs4_fwd_i.valid ? producer_rs4_fwd_i.data :
        issue1_rs2_wb1 ? wb_fwd1_i.data :
        issue1_rs2_wb0 ? wb_fwd_i.data : rf_rdata_rs4_i;
    wire [DATA_WIDTH-1:0] issue1_operand_a = decode_pkt1_i.operand_a_pc_sel ?
        decode_pkt1_i.pc : decode_pkt1_i.operand_a_imm_sel ?
        decode_pkt1_i.imm : issue1_rs1_data;
    wire [DATA_WIDTH-1:0] issue1_operand_b = decode_pkt1_i.operand_b_jump_sel ?
        32'd4 : decode_pkt1_i.operand_b_rs_sel ? issue1_rs2_data : decode_pkt1_i.imm;
    assign operand_a     =  issue_operand_a_pc_sel_ff ? issue_pc_ff :
                            issue_operand_a_imm_sel_ff ? issue_imm_ff : issue_rs1_data;
    assign operand_b     = issue_operand_b_jump_sel_ff ? 32'h4 :
                            issue_operand_b_rs_sel_ff ? issue_rs2_data : issue_imm_ff;


    assign bt_a_operand = issue_bt_a_rs_sel_ff ? issue_rs1_data : issue_pc_ff;
    assign bt_b_operand = issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_branch_pc_target = issue_pc_ff + issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_branch_next_pc = issue_pc_ff + 32'd4;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
			bru_lsu_rs1_valid_q <= 1'b0;
			bru_lsu_rs2_valid_q <= 1'b0;
			bru_lsu_rs1_tag_q <= '0;
			bru_lsu_rs2_tag_q <= '0;
			bru_lsu_rs1_data_q <= '0;
			bru_lsu_rs2_data_q <= '0;
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            producer_id_ff      <= '0;
            producer_tracked_ff <= 1'b0;
            operator_lsu_ff     <= '0;
            fpu_op_ff           <= FPU_OP_ADD;
            fpu_rm_ff           <= '0;
            fpu_illegal_ff      <= 1'b0;
            fpu_rd_fpr_ff       <= 1'b0;
            fpu_rd_gpr_ff       <= 1'b0;
            fpu_operand_a_ff    <= '0;
            fpu_operand_b_ff    <= '0;
            fpu_operand_c_ff    <= '0;
            fpu_instr_ff        <= '0;
            id_lsu_store_data_ff <= '0;
            id_lsu_store_data_valid_ff <= 1'b0;
            bt_a_operand_ff     <= '0;
            bt_b_operand_ff     <= '0;
            csr_reg_raddr_ff <= '0;
            // csr_ex_we_ff <= 1'b0;
            csr_ex_waddr_ff <= '0;
            csr_op_info_ff <= '0;
            sys_op_info_ff <= '0;
            id_instr_addr_ff <= '0;
            id_ex_jalr_ff <= 1'b0;
            id_ex_alu_bypass_rs1_ff <= 1'b0;
            id_ex_alu_bypass_rs2_ff <= 1'b0;
            id_ex_branch_pc_target_ff <= '0;
            id_ex_branch_next_pc_ff <= '0;
            id_ex_pred_hit_ff <= 1'b0;
            id_ex_pred_taken_ff <= 1'b0;
            id_ex_pred_target_ff <= '0;
            id_ex_pred_counter_ff <= 2'b01;
            id_ex_pred_bht_index_ff <= '0;
            id_ex_valid_ff <= 1'b0;
            id_fence_i_ff <= 1'b0;
            dual_operand_a_q <= '0;
            dual_operand_b_q <= '0;
            dual_operator_q <= '0;
            dual_operator_type_q <= '0;
            dual_operator_lsu_q <= '0;
            dual_store_data_q <= '0;
            dual_store_data_valid_q <= 1'b0;
            dual_rf_waddr_q <= '0;
            dual_producer_id_q <= '0;
            dual_producer_tracked_q <= 1'b0;
            dual_valid_q <= 1'b0;
            dual_pc_q <= '0;
            dual_instr_q <= RV32I_INS_NOP;
        end else begin
			if (flush_id_i || (id_advance && issue_pkt_i.valid)) begin
				bru_lsu_rs1_valid_q <= 1'b0;
				bru_lsu_rs2_valid_q <= 1'b0;
			end
			if (lsu_bru_rs1_capture) begin
				bru_lsu_rs1_valid_q <= 1'b1;
				bru_lsu_rs1_tag_q <= completion_bus_i[COMPLETION_LSU].producer_id;
				bru_lsu_rs1_data_q <= completion_bus_i[COMPLETION_LSU].data;
			end
			if (lsu_bru_rs2_capture) begin
				bru_lsu_rs2_valid_q <= 1'b1;
				bru_lsu_rs2_tag_q <= completion_bus_i[COMPLETION_LSU].producer_id;
				bru_lsu_rs2_data_q <= completion_bus_i[COMPLETION_LSU].data;
			end
            if (!stall_id_i) begin
                operand_a_ff        <= operand_a;
                operand_b_ff        <= operand_b;
                operator_ff         <= issue_operator_ff;
                operator_type_ff    <= issue_operator_type_ff;
                rf_wen_rd_ff        <= issue_rf_wen_rd_ff;
                rf_waddr_rd_ff      <= issue_rf_waddr_rd_ff;
                producer_id_ff      <= issue_pkt_i.schedule.producer_id;
                producer_tracked_ff <= issue_pkt_i.schedule.producer_tracked;
                operator_lsu_ff     <= issue_operator_lsu_ff;
                fpu_op_ff           <= decode_pkt_i.fp_op;
                fpu_rm_ff           <= decode_pkt_i.fp_rm;
                fpu_illegal_ff      <= decode_pkt_i.fp_illegal;
                fpu_rd_fpr_ff       <= decode_pkt_i.fp_rd_fpr;
                fpu_rd_gpr_ff       <= decode_pkt_i.fp_rd_gpr;
                fpu_operand_a_ff    <= decode_pkt_i.fp_rs1_fpr ? fpr_rdata_rs1_i : issue_rs1_data;
                fpu_operand_b_ff    <= fpr_rdata_rs2_i;
                fpu_operand_c_ff    <= fpr_rdata_rs3_i;
                fpu_instr_ff        <= decode_pkt_i.instr;
                // Register raw store data here; lane alignment belongs after the
                // ID/LSU boundary so the RF read path does not also include the
                // LSU address adder and byte-lane mux.
                id_lsu_store_data_ff <= decode_pkt_i.fp_valid &&
                    decode_pkt_i.fp_rs2_fpr ? fpr_rdata_rs2_i : issue_rs2_data;
				id_lsu_store_data_valid_ff <= 1'b1;
                bt_a_operand_ff     <= bt_a_operand;
                bt_b_operand_ff     <= bt_b_operand;
                csr_reg_raddr_ff <= issue_csr_reg_raddr_ff;
                // csr_ex_we_ff <= csr_ex_we;
                csr_ex_waddr_ff <= issue_csr_ex_waddr_ff;
                csr_op_info_ff <= issue_csr_op_info_ff;
                sys_op_info_ff <= issue_sys_op_info_ff;
                id_instr_addr_ff <= issue_pc_ff;
                id_ex_jalr_ff <= issue_bt_a_rs_sel_ff;
                id_ex_alu_bypass_rs1_ff <= issue_valid_ff & hzd_status_i.prev_alu_bypass_rs1;
                id_ex_alu_bypass_rs2_ff <= issue_valid_ff & hzd_status_i.prev_alu_bypass_rs2;
                id_ex_branch_pc_target_ff <= issue_branch_pc_target;
                id_ex_branch_next_pc_ff <= issue_branch_next_pc;
                id_ex_pred_hit_ff <= issue_pred_hit_ff;
                id_ex_pred_taken_ff <= issue_pred_taken_ff;
                id_ex_pred_target_ff <= issue_pred_target_ff;
                id_ex_pred_counter_ff <= issue_pred_counter_ff;
                id_ex_pred_bht_index_ff <= issue_pred_bht_index_ff;
                dual_operand_a_q <= issue1_operand_a;
                dual_operand_b_q <= issue1_operand_b;
                dual_operator_q <= decode_pkt1_i.operator_info;
                dual_operator_type_q <= decode_pkt1_i.operator_type;
                dual_operator_lsu_q <= decode_pkt1_i.operator_lsu;
                dual_store_data_q <= issue1_rs2_data;
                dual_store_data_valid_q <= !slot1_memory ||
                    !decode_pkt1_i.operator_type[OPERATOR_TYPE_STORE] ||
                    !hzd_status1_i.scoreboard_stall;
                dual_rf_waddr_q <= decode_pkt1_i.rd_addr;
                dual_producer_id_q <= issue_pkt1_i.schedule.producer_id;
                dual_producer_tracked_q <=
                    issue_pkt1_i.schedule.producer_tracked;
                dual_pc_q <= decode_pkt1_i.pc;
                dual_instr_q <= decode_pkt1_i.instr;
            end

            if (flush_id_i) begin
                id_ex_valid_ff <= 1'b0;
                id_ex_alu_bypass_rs1_ff <= 1'b0;
                id_ex_alu_bypass_rs2_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
                dual_valid_q <= 1'b0;
            end else if (id_advance) begin
                id_ex_valid_ff <= issue_valid_ff;
                id_fence_i_ff <= issue_valid_ff & issue_fence_i_ff;
                dual_valid_q <= pair_issue;
            end else if (stall_id_i) begin
                // A backend replay holds the complete ID/EX packet. Do not let
                // a simultaneous decode bubble clear only its valid/bypass bits.
                id_ex_valid_ff <= id_ex_valid_ff;
                id_fence_i_ff <= id_fence_i_ff;
                dual_valid_q <= dual_valid_q;
            end else if (bubble_id_i) begin
                id_ex_valid_ff <= 1'b0;
                // The invalid bit already suppresses the complete ID/EX
                // packet. Leave payload controls on their normal update path
                // so scoreboard bubble generation is not part of their D cone.
                id_fence_i_ff <= 1'b0;
                dual_valid_q <= 1'b0;
            end else begin
                id_fence_i_ff <= 1'b0;
                dual_valid_q <= 1'b0;
            end
        end
    end

    assign operand_a_o          = operand_a_ff;
    assign operand_b_o          = operand_b_ff;
    // Lane0 carries one registered operand pair. Per-unit input selection is
    // an EX concern and must not duplicate the issue-stage bypass mux.
    assign alu_operand_a_o      = operand_a_ff;
    assign alu_operand_b_o      = operand_b_ff;
    assign bru_operand_a_o      = operand_a_ff;
    assign bru_operand_b_o      = operand_b_ff;
    assign lsu_operand_a_o      = operand_a_ff;
    assign lsu_operand_b_o      = operand_b_ff;
    assign mul_operand_a_o      = operand_a_ff;
    assign mul_operand_b_o      = operand_b_ff;
    assign csr_operand_a_o      = operand_a_ff;
    assign csr_operand_b_o      = operand_b_ff;
    assign operator_o           = operator_ff;
    assign id_alu_rf_wen_rd_o   = rf_wen_rd_ff;
    assign id_rf_waddr_rd_o     = rf_waddr_rd_ff;
    assign operator_type_o      = operator_type_ff;
    assign lsu_req_o.valid = id_ex_valid_ff &
        (operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign lsu_req_o.is_load = operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD];
    assign lsu_req_o.is_store = operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE];
    assign lsu_req_o.op = operator_lsu_ff;
    // EX supplies the address after applying its local previous-ALU bypass.
    assign lsu_req_o.addr = '0;
    assign lsu_req_o.addr_is_dtcm = 1'b0;
    assign lsu_req_o.rd_addr = rf_waddr_rd_ff;
    assign lsu_req_o.producer_id = producer_id_ff;
    assign lsu_req_o.producer_tracked = producer_tracked_ff;
    assign lsu_req_o.store_data = id_lsu_store_data_ff;
    assign lsu_req_o.store_mask = '0;
    assign lsu_req_o.store_data_valid = id_lsu_store_data_valid_ff;
    assign lsu_req_o.fp_load = operator_type_ff[OPERATOR_TYPE_FPU] &&
        operator_type_ff[OPERATOR_TYPE_LOAD];
    assign lsu_req_o.fp_rd_addr = rf_waddr_rd_ff;
    assign fpu_req_o.valid = id_ex_valid_ff &&
        operator_type_ff[OPERATOR_TYPE_FPU] &&
        !operator_type_ff[OPERATOR_TYPE_LOAD] &&
        !operator_type_ff[OPERATOR_TYPE_STORE];
    assign fpu_req_o.illegal = fpu_illegal_ff;
    assign fpu_req_o.op = fpu_op_ff;
    assign fpu_req_o.rm = fpu_rm_ff;
    assign fpu_req_o.operand_a = fpu_operand_a_ff;
    assign fpu_req_o.operand_b = fpu_operand_b_ff;
    assign fpu_req_o.operand_c = fpu_operand_c_ff;
    assign fpu_req_o.rd_addr = rf_waddr_rd_ff;
    assign fpu_req_o.rd_fpr = fpu_rd_fpr_ff;
    assign fpu_req_o.rd_gpr = fpu_rd_gpr_ff;
    assign fpu_req_o.producer_id = producer_id_ff;
    assign fpu_req_o.producer_tracked = producer_tracked_ff;
    assign fpu_req_o.pc = id_instr_addr_ff;
    assign fpu_req_o.instr = fpu_instr_ff;
    assign bt_a_operand_o       = bt_a_operand_ff;
    assign bt_b_operand_o       = bt_b_operand_ff;
    assign  id_csr_raddr_o = csr_reg_raddr_ff;
    // assign  id_ex_csr_we_o = csr_ex_we_ff;
    assign  id_ex_csr_waddr_o = csr_ex_waddr_ff;
    assign  id_op_csr_info_o = csr_op_info_ff;
    assign  id_op_sys_info_o = sys_op_info_ff;
    assign id_instr_addr_o = id_instr_addr_ff;
    assign id_ex_jalr_o = id_ex_jalr_ff;
    assign id_ex_alu_bypass_rs1_o = id_ex_alu_bypass_rs1_ff;
    assign id_ex_alu_bypass_rs2_o = id_ex_alu_bypass_rs2_ff;
    assign id_ex_branch_target_o = id_ex_branch_pc_target_ff;
    assign id_ex_branch_next_pc_o = id_ex_branch_next_pc_ff;
    // Branch comparisons are local to EX so decode/issue does not carry a
    // register-file/producer mux through three comparators.
    assign id_ex_branch_eq_o = 1'b0;
    assign id_ex_branch_ge_signed_o = 1'b0;
    assign id_ex_branch_ge_unsigned_o = 1'b0;
    assign id_fence_i_o = id_fence_i_ff;
    assign id_ex_pred_hit_o = id_ex_pred_hit_ff;
    assign id_ex_pred_taken_o = id_ex_pred_taken_ff;
    assign id_ex_pred_target_o = id_ex_pred_target_ff;
    assign id_ex_pred_counter_o = id_ex_pred_counter_ff;
    assign id_ex_pred_bht_index_o = id_ex_pred_bht_index_ff;
    assign id_ex_valid_o = id_ex_valid_ff;
    assign id_ex_producer_id_o = producer_id_ff;
    assign id_ex_producer_tracked_o = producer_tracked_ff;
    assign dual_operand_a_o = dual_operand_a_q;
    assign dual_operand_b_o = dual_operand_b_q;
    assign dual_operator_o = dual_operator_q;
    assign dual_operator_type_o = dual_operator_type_q;
    assign dual_operator_lsu_o = dual_operator_lsu_q;
    assign dual_store_data_o = dual_store_data_q;
    assign dual_store_data_valid_o = dual_store_data_valid_q;
    assign dual_rf_waddr_o = dual_rf_waddr_q;
    assign dual_producer_id_o = dual_producer_id_q;
    assign dual_producer_tracked_o = dual_producer_tracked_q;
    assign dual_valid_o = dual_valid_q;
    assign dual_pc_o = dual_pc_q;
    assign dual_instr_o = dual_instr_q;

endmodule

// 第二槽位仅执行无异常的单周期整数/位操作。输入与输出各打一拍，
// 使其完成时序与主 ALU 完成总线保持一致。
module ydrasil_dual_alu
import ydrasil_pkg::*;
(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           flush_i,
    input  wire                           interrupt_i,
    input  wire                           valid_i,
    input  wire [REGS_DATA_WIDTH-1:0]     operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]     operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0]      operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] operator_type_i,
    input  wire [OP_LSU_INFO_WIDTH-1:0]   operator_lsu_i,
    input  wire [REGS_DATA_WIDTH-1:0]     store_data_i,
    input  wire                           store_data_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0]     rd_addr_i,
    input  producer_id_t                  producer_id_i,
    input  wire                           producer_tracked_i,
    input  wire [INST_ADDR_WIDTH-1:0]     pc_i,
    input  wire [INST_DATA_WIDTH-1:0]     instr_i,
    output ydrasil_gpr_fwd_pkt_t          completion_o,
    output ydrasil_lsu_req_pkt_t          lsu_req_o,
    output wire                           instret_valid_o,
    output wire [INST_ADDR_WIDTH-1:0]     commit_pc_o,
    output wire [INST_DATA_WIDTH-1:0]     commit_instr_o
);
    wire [REGS_DATA_WIDTH-1:0] alu_result;
    wire [REGS_DATA_WIDTH-1:0] fast_b_shadd_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_SH1ADD]}} &
         ((operand_a_i << 1) + operand_b_i)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SH2ADD]}} &
         ((operand_a_i << 2) + operand_b_i)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SH3ADD]}} &
         ((operand_a_i << 3) + operand_b_i));
    wire [REGS_DATA_WIDTH-1:0] fast_b_logic_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_ANDN]}} &
         (operand_a_i & ~operand_b_i)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_ORN]}} &
         (operand_a_i | ~operand_b_i)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_XNOR]}} &
         ~(operand_a_i ^ operand_b_i));
    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_a = operand_a_i;
    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_b = operand_b_i;
    wire [REGS_DATA_WIDTH-1:0] fast_b_minmax_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_MIN]}} &
         ((signed_operand_a <= signed_operand_b) ? operand_a_i : operand_b_i)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_MAX]}} &
         ((signed_operand_a >= signed_operand_b) ? operand_a_i : operand_b_i)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_MINU]}} &
         ((operand_a_i <= operand_b_i) ? operand_a_i : operand_b_i)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_MAXU]}} &
         ((operand_a_i >= operand_b_i) ? operand_a_i : operand_b_i));
    wire [REGS_DATA_WIDTH-1:0] fast_b_extend_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_REV8]}} &
         {operand_a_i[7:0], operand_a_i[15:8],
          operand_a_i[23:16], operand_a_i[31:24]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SEXT_B]}} &
         {{24{operand_a_i[7]}}, operand_a_i[7:0]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_SEXT_H]}} &
         {{16{operand_a_i[15]}}, operand_a_i[15:0]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_ZEXT_H]}} &
         {16'b0, operand_a_i[15:0]});
    wire fast_bitmanip_op = operator_type_i[OPERATOR_TYPE_BITMANIP] &&
        (operator_i[OP_B_SH1ADD] | operator_i[OP_B_SH2ADD] | operator_i[OP_B_SH3ADD] |
         operator_i[OP_B_ANDN]   | operator_i[OP_B_ORN]    | operator_i[OP_B_XNOR]   |
         operator_i[OP_B_MIN]    | operator_i[OP_B_MAX]    | operator_i[OP_B_MINU]   |
         operator_i[OP_B_MAXU]   | operator_i[OP_B_REV8]   | operator_i[OP_B_SEXT_B] |
         operator_i[OP_B_SEXT_H] | operator_i[OP_B_ZEXT_H]);
    wire [REGS_DATA_WIDTH-1:0] fast_bitmanip_result =
        fast_b_shadd_result | fast_b_logic_result | fast_b_minmax_result |
        fast_b_extend_result;
    wire alu_unused_comp;
    wire alu_unused_wen;
    wire [REGS_ADDR_WIDTH-1:0] alu_unused_waddr;
    reg valid_q;
    reg [REGS_DATA_WIDTH-1:0] result_q;
    reg [REGS_ADDR_WIDTH-1:0] rd_addr_q;
    producer_id_t producer_id_q;
    reg producer_tracked_q;
    reg [INST_ADDR_WIDTH-1:0] pc_q;
    reg [INST_DATA_WIDTH-1:0] instr_q;
    reg memory_q;
    reg load_q;

    wire memory_op = operator_type_i[OPERATOR_TYPE_LOAD] ||
        operator_type_i[OPERATOR_TYPE_STORE];
    wire [BUS_ADDR_WIDTH-1:0] agu_addr = operand_a_i + operand_b_i;

    always_comb begin
        lsu_req_o = '0;
        lsu_req_o.valid = valid_i && memory_op && !interrupt_i;
        lsu_req_o.is_load = operator_type_i[OPERATOR_TYPE_LOAD];
        lsu_req_o.is_store = operator_type_i[OPERATOR_TYPE_STORE];
        lsu_req_o.op = operator_lsu_i;
        lsu_req_o.addr = agu_addr;
        lsu_req_o.addr_is_dtcm =
            (agu_addr[31:DTCM_ADDR_WIDTH+2] ==
             DTCM_BASE_ADDR[31:DTCM_ADDR_WIDTH+2]);
        lsu_req_o.rd_addr = rd_addr_i;
        lsu_req_o.producer_id = producer_id_i;
        lsu_req_o.producer_tracked = producer_tracked_i;
        lsu_req_o.store_data = store_data_i;
        lsu_req_o.store_data_valid = store_data_valid_i;
        lsu_req_o.fp_load = 1'b0;
        lsu_req_o.fp_rd_addr = '0;
        if (operator_lsu_i[OP_LSU_SB])
            lsu_req_o.store_mask = 4'b0001 << agu_addr[1:0];
        else if (operator_lsu_i[OP_LSU_SH])
            lsu_req_o.store_mask = agu_addr[1] ? 4'b1100 : 4'b0011;
        else if (operator_lsu_i[OP_LSU_SW])
            lsu_req_o.store_mask = 4'b1111;
    end

    ydrasil_alu u_dual_alu (
        .operand_a_i(operand_a_i), .operand_b_i(operand_b_i),
        .operator_i(operator_i), .operator_type_i(operator_type_i),
        .id_rf_waddr_rd_i(rd_addr_i), .id_alu_rf_wen_rd_i(1'b1),
        .interrupt_i(interrupt_i), .comp_result_o(alu_unused_comp),
        .alu_result_o(alu_result), .alu_rf_wen_rd_o(alu_unused_wen),
        .alu_rf_waddr_rd_o(alu_unused_waddr)
    );
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            valid_q <= 1'b0;
            result_q <= '0;
            rd_addr_q <= '0;
            producer_id_q <= '0;
            producer_tracked_q <= 1'b0;
            pc_q <= '0;
            instr_q <= RV32I_INS_NOP;
            memory_q <= 1'b0;
            load_q <= 1'b0;
        end else begin
            valid_q <= valid_i && !interrupt_i;
            result_q <= operator_type_i[OPERATOR_TYPE_BITMANIP] ?
                fast_bitmanip_result :
                alu_result;
            rd_addr_q <= rd_addr_i;
            producer_id_q <= producer_id_i;
            producer_tracked_q <= producer_tracked_i;
            pc_q <= pc_i;
            instr_q <= instr_i;
            memory_q <= memory_op;
            load_q <= operator_type_i[OPERATOR_TYPE_LOAD];
        end
    end

    // Lane 1 is the second E pipe, not a seventh pipeline stage. Its result is
    // presented during E and captured by the Future File at the W edge, just
    // like lane 0. The q registers below remain commit-trace state only.
    assign completion_o.valid = valid_i && !memory_op && !interrupt_i &&
        (rd_addr_i != '0);
    assign completion_o.producer_id = producer_id_i;
    assign completion_o.producer_tracked = producer_tracked_i;
    assign completion_o.addr = rd_addr_i;
    assign completion_o.data = operator_type_i[OPERATOR_TYPE_BITMANIP] ?
        fast_bitmanip_result : alu_result;
    assign instret_valid_o = valid_q && !load_q;
    assign commit_pc_o = pc_q;
    assign commit_instr_o = instr_q;
endmodule
