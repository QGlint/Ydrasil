
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

    input  wire                            decode_valid_i,
    input  ydrasil_decode_pkt_t            decode_pkt_i,
    input  wire                            decode_valid1_i,
    input  ydrasil_decode_pkt_t            decode_pkt1_i,
    output wire                            issue_ready_o,
    output wire                            issue_consume_two_o,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    output wire [4:0]                      rf_addr_rs3_o,
    output wire [4:0]                      rf_addr_rs4_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs3_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs4_i,
    input  ydrasil_gpr_fwd_pkt_t           wb_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           wb_fwd1_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs1_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs2_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs3_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs4_fwd_i,
    input  ydrasil_completion_bus_t        completion_bus_i,
    input  ydrasil_hzd_status_pkt_t        hzd_status_i,
    input  ydrasil_hzd_status_pkt_t        hzd_status1_i,
    input  producer_id_t                   producer_alloc_id_i,
    input  wire                            producer_alloc_tracked_i,
    input  producer_id_t                   producer_alloc_id1_i,
    input  wire                            producer_alloc_tracked1_i,

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

    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    output wire                            id_ex_jalr_o,
    output wire                            id_ex_alu_bypass_rs1_o,
    output wire                            id_ex_alu_bypass_rs2_o,
    output wire                            id_ex_load_bypass_rs1_o,
    output wire                            id_ex_load_bypass_rs2_o,
    output producer_id_t                   id_ex_load_bypass_producer_id_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_target_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_next_pc_o,
    output wire                            id_ex_branch_eq_o,
    output wire                            id_ex_branch_ge_signed_o,
    output wire                            id_ex_branch_ge_unsigned_o,
    output ydrasil_id_ctrl_pkt_t           id_ctrl_o,

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
    output wire [REGS_ADDR_WIDTH-1:0]      dual_rf_waddr_o,
    output producer_id_t                   dual_producer_id_o,
    output wire                            dual_producer_tracked_o,
    output wire                            dual_valid_o,
    output wire [INST_ADDR_WIDTH-1:0]      dual_pc_o,
    output wire [INST_DATA_WIDTH-1:0]      dual_instr_o,
    output ydrasil_id_ctrl_pkt_t           id_ctrl1_o,
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
    producer_id_t                       id_lsu_store_data_producer_id_ff;
    reg                                 id_lsu_store_data_producer_tracked_ff;

    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]       operator_type_ff;

    wire [DATA_WIDTH-1:0]                operand_a;
    wire [DATA_WIDTH-1:0]                operand_b;
    reg [DATA_WIDTH-1:0]                operand_a_ff;
    reg [DATA_WIDTH-1:0]                operand_b_ff;
    reg [DATA_WIDTH-1:0]                alu_operand_a_ff;
    reg [DATA_WIDTH-1:0]                alu_operand_b_ff;
    reg [DATA_WIDTH-1:0]                bru_operand_a_ff;
    reg [DATA_WIDTH-1:0]                bru_operand_b_ff;
    reg [DATA_WIDTH-1:0]                lsu_operand_a_ff;
    reg [DATA_WIDTH-1:0]                lsu_operand_b_ff;
    reg [DATA_WIDTH-1:0]                mul_operand_a_ff;
    reg [DATA_WIDTH-1:0]                mul_operand_b_ff;
    reg [DATA_WIDTH-1:0]                csr_operand_a_ff;
    reg [DATA_WIDTH-1:0]                csr_operand_b_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]           operator_ff;

    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]         operator_lsu_ff;

    wire [DATA_WIDTH-1:0]                bt_a_operand;
    wire [DATA_WIDTH-1:0]                bt_b_operand;
    reg [DATA_WIDTH-1:0]                 bt_a_operand_ff;
    reg [DATA_WIDTH-1:0]                 bt_b_operand_ff;
    reg [DATA_WIDTH-1:0]                 id_instr_addr_ff;
    reg                                  id_ex_jalr_ff;
    (* max_fanout = 8 *) reg             id_ex_alu_bypass_rs1_ff;
    (* max_fanout = 8 *) reg             id_ex_alu_bypass_rs2_ff;
    (* max_fanout = 8 *) reg             id_ex_load_bypass_rs1_ff;
    (* max_fanout = 8 *) reg             id_ex_load_bypass_rs2_ff;
    producer_id_t                       id_ex_load_bypass_producer_id_ff;
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

    wire                            id_advance;
    wire                            issue_valid_ff = decode_valid_i;
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
    wire issue1_rs1_ren = decode_pkt1_i.rs1_ren;
    wire issue1_rs2_ren = decode_pkt1_i.rs2_ren;
    wire issue1_rd_wen = decode_pkt1_i.rd_wen && (decode_pkt1_i.rd_addr != '0);
    wire slot0_simple_int = decode_valid_i &&
        (decode_pkt_i.operator_type[OPERATOR_TYPE_ALU] ||
         decode_pkt_i.operator_type[OPERATOR_TYPE_BITMANIP]) &&
        !decode_pkt_i.operator_type[OPERATOR_TYPE_BJP] &&
        !decode_pkt_i.operator_type[OPERATOR_TYPE_LOAD] &&
        !decode_pkt_i.operator_type[OPERATOR_TYPE_STORE] &&
        !decode_pkt_i.operator_type[OPERATOR_TYPE_MUL] &&
        !decode_pkt_i.operator_type[OPERATOR_TYPE_CSR] &&
        !decode_pkt_i.operator_type[OPERATOR_TYPE_SYS] && !decode_pkt_i.fence_i;
    wire slot1_simple_int = decode_valid1_i &&
        (decode_pkt1_i.operator_type[OPERATOR_TYPE_ALU] ||
         decode_pkt1_i.operator_type[OPERATOR_TYPE_BITMANIP]) &&
        !decode_pkt1_i.operator_type[OPERATOR_TYPE_BJP] &&
        !decode_pkt1_i.operator_type[OPERATOR_TYPE_LOAD] &&
        !decode_pkt1_i.operator_type[OPERATOR_TYPE_STORE] &&
        !decode_pkt1_i.operator_type[OPERATOR_TYPE_MUL] &&
        !decode_pkt1_i.operator_type[OPERATOR_TYPE_CSR] &&
        !decode_pkt1_i.operator_type[OPERATOR_TYPE_SYS] && !decode_pkt1_i.fence_i;
    wire slot0_writes = decode_pkt_i.rd_wen && (decode_pkt_i.rd_addr != '0);
    wire pair_raw = slot0_writes &&
        ((issue1_rs1_ren && (issue1_rs1_addr == decode_pkt_i.rd_addr)) ||
         (issue1_rs2_ren && (issue1_rs2_addr == decode_pkt_i.rd_addr)));
    wire pair_waw = slot0_writes && issue1_rd_wen &&
        (decode_pkt_i.rd_addr == decode_pkt1_i.rd_addr);
    wire pair_eligible = slot0_simple_int && slot1_simple_int &&
        !pair_raw && !pair_waw && !hzd_status1_i.scoreboard_stall;
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

    assign rf_addr_rs1_o = issue_rf_raddr_rs1_ff;
    assign rf_addr_rs2_o = issue_rf_raddr_rs2_ff;
    assign rf_addr_rs3_o = issue1_rs1_addr;
    assign rf_addr_rs4_o = issue1_rs2_addr;

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
        producer_rs1_fwd_i.valid ? producer_rs1_fwd_i.data :
        rs1_wb_fwd1 ? wb_fwd1_i.data :
        rs1_wb_fwd  ? wb_fwd_i.data  : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_rs2_data =
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
    reg held_store_wake_valid;
    reg [DATA_WIDTH-1:0] held_store_wake_data;
    integer held_store_lane;
    always_comb begin
        held_store_wake_valid = 1'b0;
        held_store_wake_data = '0;
        for (held_store_lane = 0; held_store_lane < COMPLETION_LANES;
             held_store_lane = held_store_lane + 1) begin
            if (id_ex_valid_ff &&
                operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                !id_lsu_store_data_valid_ff &&
                id_lsu_store_data_producer_tracked_ff &&
                completion_bus_i[held_store_lane].valid &&
                completion_bus_i[held_store_lane].producer_tracked &&
                (completion_bus_i[held_store_lane].producer_id ==
                 id_lsu_store_data_producer_id_ff)) begin
                held_store_wake_valid = 1'b1;
                held_store_wake_data = completion_bus_i[held_store_lane].data;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            alu_operand_a_ff    <= '0;
            alu_operand_b_ff    <= '0;
            bru_operand_a_ff    <= '0;
            bru_operand_b_ff    <= '0;
            lsu_operand_a_ff    <= '0;
            lsu_operand_b_ff    <= '0;
            mul_operand_a_ff    <= '0;
            mul_operand_b_ff    <= '0;
            csr_operand_a_ff    <= '0;
            csr_operand_b_ff    <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            producer_id_ff      <= '0;
            producer_tracked_ff <= 1'b0;
            operator_lsu_ff     <= '0;
            id_lsu_store_data_ff <= '0;
            id_lsu_store_data_valid_ff <= 1'b0;
            id_lsu_store_data_producer_id_ff <= '0;
            id_lsu_store_data_producer_tracked_ff <= 1'b0;
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
            id_ex_load_bypass_rs1_ff <= 1'b0;
            id_ex_load_bypass_rs2_ff <= 1'b0;
            id_ex_load_bypass_producer_id_ff <= '0;
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
            dual_rf_waddr_q <= '0;
            dual_producer_id_q <= '0;
            dual_producer_tracked_q <= 1'b0;
            dual_valid_q <= 1'b0;
            dual_pc_q <= '0;
            dual_instr_q <= RV32I_INS_NOP;
        end else begin
            if (!stall_id_i) begin
                operand_a_ff        <= operand_a;
                operand_b_ff        <= operand_b;
                alu_operand_a_ff    <= operand_a;
                alu_operand_b_ff    <= operand_b;
                bru_operand_a_ff    <= operand_a;
                bru_operand_b_ff    <= operand_b;
                lsu_operand_a_ff    <= operand_a;
                lsu_operand_b_ff    <= operand_b;
                mul_operand_a_ff    <= operand_a;
                mul_operand_b_ff    <= operand_b;
                csr_operand_a_ff    <= operand_a;
                csr_operand_b_ff    <= operand_b;
                operator_ff         <= issue_operator_ff;
                operator_type_ff    <= issue_operator_type_ff;
                rf_wen_rd_ff        <= issue_rf_wen_rd_ff;
                rf_waddr_rd_ff      <= issue_rf_waddr_rd_ff;
                producer_id_ff      <= producer_alloc_id_i;
                producer_tracked_ff <= producer_alloc_tracked_i;
                operator_lsu_ff     <= issue_operator_lsu_ff;
                // Register raw store data here; lane alignment belongs after the
                // ID/LSU boundary so the RF read path does not also include the
                // LSU address adder and byte-lane mux.
                id_lsu_store_data_ff <= issue_rs2_data;
                id_lsu_store_data_valid_ff <=
                    !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
                    hzd_status_i.issue_store_data_ready;
                id_lsu_store_data_producer_id_ff <=
                    hzd_status_i.store_data_producer_id;
                id_lsu_store_data_producer_tracked_ff <=
                    hzd_status_i.store_data_producer_tracked;
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
                id_ex_load_bypass_rs1_ff <= issue_valid_ff & hzd_status_i.prev_load_bypass_rs1;
                id_ex_load_bypass_rs2_ff <= issue_valid_ff & hzd_status_i.prev_load_bypass_rs2;
                id_ex_load_bypass_producer_id_ff <=
                    hzd_status_i.prev_load_producer_id;
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
                dual_rf_waddr_q <= decode_pkt1_i.rd_addr;
                dual_producer_id_q <= producer_alloc_id1_i;
                dual_producer_tracked_q <= producer_alloc_tracked1_i;
                dual_pc_q <= decode_pkt1_i.pc;
                dual_instr_q <= decode_pkt1_i.instr;
            end else if (stall_id_i && !flush_id_i && held_store_wake_valid) begin
                // A replayed store may receive its data before its address
                // dependency completes. Absorb that completion into the held
                // ID/EX packet so the later LSU request cannot miss the pulse.
                id_lsu_store_data_ff <= held_store_wake_data;
                id_lsu_store_data_valid_ff <= 1'b1;
                id_lsu_store_data_producer_tracked_ff <= 1'b0;
            end

            if (flush_id_i) begin
                id_ex_valid_ff <= 1'b0;
                id_ex_alu_bypass_rs1_ff <= 1'b0;
                id_ex_alu_bypass_rs2_ff <= 1'b0;
                id_ex_load_bypass_rs1_ff <= 1'b0;
                id_ex_load_bypass_rs2_ff <= 1'b0;
                id_ex_load_bypass_producer_id_ff <= '0;
                id_fence_i_ff <= 1'b0;
                dual_valid_q <= 1'b0;
            end else if (id_advance) begin
                id_ex_valid_ff <= issue_valid_ff;
                id_fence_i_ff <= issue_valid_ff & issue_fence_i_ff;
                dual_valid_q <= pair_eligible;
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
    assign alu_operand_a_o      = alu_operand_a_ff;
    assign alu_operand_b_o      = alu_operand_b_ff;
    assign bru_operand_a_o      = bru_operand_a_ff;
    assign bru_operand_b_o      = bru_operand_b_ff;
    assign lsu_operand_a_o      = lsu_operand_a_ff;
    assign lsu_operand_b_o      = lsu_operand_b_ff;
    assign mul_operand_a_o      = mul_operand_a_ff;
    assign mul_operand_b_o      = mul_operand_b_ff;
    assign csr_operand_a_o      = csr_operand_a_ff;
    assign csr_operand_b_o      = csr_operand_b_ff;
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
    assign lsu_req_o.store_data_producer_id = id_lsu_store_data_producer_id_ff;
    assign lsu_req_o.store_data_producer_tracked =
        id_lsu_store_data_producer_tracked_ff;
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
    assign id_ex_load_bypass_rs1_o = id_ex_load_bypass_rs1_ff;
    assign id_ex_load_bypass_rs2_o = id_ex_load_bypass_rs2_ff;
    assign id_ex_load_bypass_producer_id_o =
        id_ex_load_bypass_producer_id_ff;
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
    assign dual_rf_waddr_o = dual_rf_waddr_q;
    assign dual_producer_id_o = dual_producer_id_q;
    assign dual_producer_tracked_o = dual_producer_tracked_q;
    assign dual_valid_o = dual_valid_q;
    assign dual_pc_o = dual_pc_q;
    assign dual_instr_o = dual_instr_q;

    assign id_ctrl_o.rs1_addr = issue_rf_raddr_rs1_ff;
    assign id_ctrl_o.rs2_addr = issue_rf_raddr_rs2_ff;
    assign id_ctrl_o.rs1_ren = issue_valid_ff & issue_rf_ren_rs1_ff;
    assign id_ctrl_o.rs2_ren = issue_valid_ff &
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign id_ctrl_o.rd_wen = issue_valid_ff & (issue_rf_waddr_rd_ff != '0) &
        (issue_rf_wen_rd_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD]);
    assign id_ctrl_o.rd_addr = issue_rf_waddr_rd_ff;
    assign id_ctrl_o.lsu_req = issue_valid_ff &
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign id_ctrl_o.store_req = issue_valid_ff &
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE];
    assign id_ctrl_o.prev_alu_bypass_ok = issue_valid_ff &
        (issue_plain_alu_op |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
         (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] &
          issue_rf_ren_rs1_ff & issue_rf_ren_rs2_ff & !issue_rf_wen_rd_ff));
    // Branch compare is kept off the combinational DTCM load-data path. A
    // true load-to-branch dependency waits for the registered completion.
    assign id_ctrl_o.load_bypass_ok = issue_valid_ff & issue_plain_alu_op;
    assign id_ctrl_o.serialize_before = issue_valid_ff &
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] |
         issue_fence_i_ff);

    assign id_ctrl1_o.rs1_addr = issue1_rs1_addr;
    assign id_ctrl1_o.rs2_addr = issue1_rs2_addr;
    assign id_ctrl1_o.rs1_ren = decode_valid1_i && issue1_rs1_ren;
    assign id_ctrl1_o.rs2_ren = decode_valid1_i && issue1_rs2_ren;
    // 控制器必须在决定是否成对发射前看见槽位 1 的资源需求。
    // 最终是否分配/锁存仍由 pair_eligible 与 dual_valid_q 限定。
    assign id_ctrl1_o.rd_wen = decode_valid1_i && issue1_rd_wen;
    assign id_ctrl1_o.rd_addr = decode_pkt1_i.rd_addr;
    assign id_ctrl1_o.lsu_req = 1'b0;
    assign id_ctrl1_o.store_req = 1'b0;
    assign id_ctrl1_o.prev_alu_bypass_ok = 1'b0;
    assign id_ctrl1_o.load_bypass_ok = 1'b0;
    assign id_ctrl1_o.serialize_before = 1'b0;

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
    input  wire [REGS_ADDR_WIDTH-1:0]     rd_addr_i,
    input  producer_id_t                  producer_id_i,
    input  wire                           producer_tracked_i,
    input  wire [INST_ADDR_WIDTH-1:0]     pc_i,
    input  wire [INST_DATA_WIDTH-1:0]     instr_i,
    output ydrasil_gpr_fwd_pkt_t          completion_o,
    output wire                           instret_valid_o,
    output wire [INST_ADDR_WIDTH-1:0]     commit_pc_o,
    output wire [INST_DATA_WIDTH-1:0]     commit_instr_o
);
    wire [REGS_DATA_WIDTH-1:0] alu_result;
    wire [REGS_DATA_WIDTH-1:0] bitmanip_result;
    wire [4:0] fast_b_shamt = operand_b_i[4:0];
    wire [REGS_DATA_WIDTH-1:0] fast_b_mask = REGS_DATA_WIDTH'(1) << fast_b_shamt;
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
    wire [REGS_DATA_WIDTH-1:0] fast_b_bit_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_BCLR] | operator_i[OP_B_BCLRI]}} &
         (operand_a_i & ~fast_b_mask)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_BEXT] | operator_i[OP_B_BEXTI]}} &
         {{(REGS_DATA_WIDTH-1){1'b0}}, |(operand_a_i & fast_b_mask)}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_BINV] | operator_i[OP_B_BINVI]}} &
         (operand_a_i ^ fast_b_mask)) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_BSET] | operator_i[OP_B_BSETI]}} &
         (operand_a_i | fast_b_mask));
    wire [REGS_DATA_WIDTH-1:0] fast_b_pack_result =
        ({REGS_DATA_WIDTH{operator_i[OP_B_PACK]}} &
         {operand_b_i[15:0], operand_a_i[15:0]}) |
        ({REGS_DATA_WIDTH{operator_i[OP_B_PACKH]}} &
         {16'b0, operand_b_i[7:0], operand_a_i[7:0]});
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
         operator_i[OP_B_BCLR]   | operator_i[OP_B_BCLRI]  | operator_i[OP_B_BEXT]   |
         operator_i[OP_B_BEXTI]  | operator_i[OP_B_BINV]   | operator_i[OP_B_BINVI]  |
         operator_i[OP_B_BSET]   | operator_i[OP_B_BSETI]  | operator_i[OP_B_PACK]   |
         operator_i[OP_B_PACKH]  | operator_i[OP_B_REV8]   | operator_i[OP_B_SEXT_B] |
         operator_i[OP_B_SEXT_H] | operator_i[OP_B_ZEXT_H]);
    wire [REGS_DATA_WIDTH-1:0] fast_bitmanip_result =
        fast_b_shadd_result | fast_b_logic_result | fast_b_bit_result |
        fast_b_pack_result | fast_b_extend_result;
    logic [OPERATOR_WIDTH-1:0] slow_bitmanip_operator;
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

    always_comb begin
        slow_bitmanip_operator = operator_i;
        slow_bitmanip_operator[OP_B_SH1ADD] = 1'b0;
        slow_bitmanip_operator[OP_B_SH2ADD] = 1'b0;
        slow_bitmanip_operator[OP_B_SH3ADD] = 1'b0;
        slow_bitmanip_operator[OP_B_ANDN]   = 1'b0;
        slow_bitmanip_operator[OP_B_ORN]    = 1'b0;
        slow_bitmanip_operator[OP_B_REV8]   = 1'b0;
        slow_bitmanip_operator[OP_B_SEXT_B] = 1'b0;
        slow_bitmanip_operator[OP_B_SEXT_H] = 1'b0;
        slow_bitmanip_operator[OP_B_XNOR]   = 1'b0;
        slow_bitmanip_operator[OP_B_ZEXT_H] = 1'b0;
        slow_bitmanip_operator[OP_B_BCLR]   = 1'b0;
        slow_bitmanip_operator[OP_B_BCLRI]  = 1'b0;
        slow_bitmanip_operator[OP_B_BEXT]   = 1'b0;
        slow_bitmanip_operator[OP_B_BEXTI]  = 1'b0;
        slow_bitmanip_operator[OP_B_BINV]   = 1'b0;
        slow_bitmanip_operator[OP_B_BINVI]  = 1'b0;
        slow_bitmanip_operator[OP_B_BSET]   = 1'b0;
        slow_bitmanip_operator[OP_B_BSETI]  = 1'b0;
        slow_bitmanip_operator[OP_B_PACK]   = 1'b0;
        slow_bitmanip_operator[OP_B_PACKH]  = 1'b0;
    end

    ydrasil_alu u_dual_alu (
        .operand_a_i(operand_a_i), .operand_b_i(operand_b_i),
        .operator_i(operator_i), .operator_type_i(operator_type_i),
        .id_rf_waddr_rd_i(rd_addr_i), .id_alu_rf_wen_rd_i(1'b1),
        .interrupt_i(interrupt_i), .comp_result_o(alu_unused_comp),
        .alu_result_o(alu_result), .alu_rf_wen_rd_o(alu_unused_wen),
        .alu_rf_waddr_rd_o(alu_unused_waddr)
    );
    ydrasil_bitmanip u_dual_bitmanip (
        .operand_a_i(operand_a_i), .operand_b_i(operand_b_i),
        .operator_i(slow_bitmanip_operator), .operator_type_i(operator_type_i),
        .result_o(bitmanip_result)
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
        end else begin
            valid_q <= valid_i && !interrupt_i;
            result_q <= operator_type_i[OPERATOR_TYPE_BITMANIP] ?
                (fast_bitmanip_op ? fast_bitmanip_result : bitmanip_result) :
                alu_result;
            rd_addr_q <= rd_addr_i;
            producer_id_q <= producer_id_i;
            producer_tracked_q <= producer_tracked_i;
            pc_q <= pc_i;
            instr_q <= instr_i;
        end
    end

    assign completion_o.valid = valid_q && (rd_addr_q != '0);
    assign completion_o.producer_id = producer_id_q;
    assign completion_o.producer_tracked = producer_tracked_q;
    assign completion_o.addr = rd_addr_q;
    assign completion_o.data = result_q;
    assign instret_valid_o = valid_q;
    assign commit_pc_o = pc_q;
    assign commit_instr_o = instr_q;
endmodule
