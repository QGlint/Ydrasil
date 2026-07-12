
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
    output wire                            issue_ready_o,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,
    input  ydrasil_gpr_fwd_pkt_t           wb_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs1_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs2_fwd_i,
    input  ydrasil_completion_bus_t        completion_bus_i,
    input  ydrasil_hzd_status_pkt_t        hzd_status_i,
    input  producer_id_t                   producer_alloc_id_i,
    input  wire                            producer_alloc_tracked_i,

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
    // Generic writeback information
    output wire                            id_alu_rf_wen_rd_o,
    output wire [4:0]                      id_rf_waddr_rd_o


);

    reg [4:0]                           rf_waddr_rd_ff;
    reg                                 rf_wen_rd_ff;
    producer_id_t                       producer_id_ff;
    reg                                 producer_tracked_ff;

    reg [DATA_WIDTH-1:0]                id_lsu_addr_ff;
    reg [DATA_WIDTH-1:0]                id_lsu_store_data_ff;
    reg [3:0]                           id_lsu_store_mask_ff;
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
    reg [DATA_WIDTH-1:0]                 id_ex_branch_pc_target_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_jalr_target_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_branch_next_pc_ff;
    reg                                  id_ex_branch_eq_ff;
    reg                                  id_ex_branch_ge_signed_ff;
    reg                                  id_ex_branch_ge_unsigned_ff;
    reg                                  id_ex_pred_hit_ff;
    reg                                  id_ex_pred_taken_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_target_ff;
    reg [1:0]                            id_ex_pred_counter_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_bht_index_ff;
    reg                                  id_ex_valid_ff;
    reg                                  id_fence_i_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr_ff;

    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr_ff; 
	reg [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]  csr_op_info_ff;

    reg [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   sys_op_info_ff;

    wire                            id_advance;
    localparam int DTCM_TAG_LSB = ydrasil_pkg::DTCM_ADDR_WIDTH + 2;

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
    reg                             issue_early_alu_valid_ff;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]      issue_early_alu_addr_ff;
    localparam int EARLY_KIND_ADD   = 0;
    localparam int EARLY_KIND_SUB   = 1;
    localparam int EARLY_KIND_CMP   = 2;
    localparam int EARLY_KIND_LOGIC = 3;
    localparam int EARLY_KIND_SHIFT = 4;
    localparam int EARLY_KIND_PASS  = 5;
    reg [5:0]                       issue_early_kind_ff;
    reg [DATA_WIDTH-1:0]            issue_early_add_data_ff;
    reg [DATA_WIDTH-1:0]            issue_early_sub_data_ff;
    reg [DATA_WIDTH-1:0]            issue_early_cmp_data_ff;
    reg [DATA_WIDTH-1:0]            issue_early_logic_data_ff;
    reg [DATA_WIDTH-1:0]            issue_early_shift_data_ff;
    reg [DATA_WIDTH-1:0]            issue_early_pass_data_ff;
    wire [DATA_WIDTH-1:0] issue_early_alu_data =
        ({DATA_WIDTH{issue_early_kind_ff[EARLY_KIND_ADD]}}   & issue_early_add_data_ff) |
        ({DATA_WIDTH{issue_early_kind_ff[EARLY_KIND_SUB]}}   & issue_early_sub_data_ff) |
        ({DATA_WIDTH{issue_early_kind_ff[EARLY_KIND_CMP]}}   & issue_early_cmp_data_ff) |
        ({DATA_WIDTH{issue_early_kind_ff[EARLY_KIND_LOGIC]}} & issue_early_logic_data_ff) |
        ({DATA_WIDTH{issue_early_kind_ff[EARLY_KIND_SHIFT]}} & issue_early_shift_data_ff) |
        ({DATA_WIDTH{issue_early_kind_ff[EARLY_KIND_PASS]}}  & issue_early_pass_data_ff);
    assign id_advance = !stall_id_i && !bubble_id_i;
    assign issue_ready_o = id_advance;

    assign rf_addr_rs1_o = issue_rf_raddr_rs1_ff;
    assign rf_addr_rs2_o = issue_rf_raddr_rs2_ff;

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
    reg rs1_completion_fwd;
    reg rs2_completion_fwd;
    reg [DATA_WIDTH-1:0] rs1_completion_data;
    reg [DATA_WIDTH-1:0] rs2_completion_data;
    integer completion_lane;
    always_comb begin
        rs1_completion_fwd = 1'b0;
        rs2_completion_fwd = 1'b0;
        rs1_completion_data = '0;
        rs2_completion_data = '0;
        for (completion_lane = 0; completion_lane < COMPLETION_LANES;
             completion_lane = completion_lane + 1) begin
            if (completion_bus_i[completion_lane].valid &&
                issue_rf_ren_rs1_ff && (issue_rf_raddr_rs1_ff != '0) &&
                (producer_rs1_fwd_i.producer_tracked ?
                 (completion_bus_i[completion_lane].producer_tracked &&
                  (completion_bus_i[completion_lane].producer_id ==
                   producer_rs1_fwd_i.producer_id)) :
                 (completion_bus_i[completion_lane].addr == issue_rf_raddr_rs1_ff))) begin
                rs1_completion_fwd = 1'b1;
                rs1_completion_data = completion_bus_i[completion_lane].data;
            end
            if (completion_bus_i[completion_lane].valid &&
                (issue_rf_ren_rs2_ff |
                 issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
                (issue_rf_raddr_rs2_ff != '0) &&
                (producer_rs2_fwd_i.producer_tracked ?
                 (completion_bus_i[completion_lane].producer_tracked &&
                  (completion_bus_i[completion_lane].producer_id ==
                   producer_rs2_fwd_i.producer_id)) :
                 (completion_bus_i[completion_lane].addr == issue_rf_raddr_rs2_ff))) begin
                rs2_completion_fwd = 1'b1;
                rs2_completion_data = completion_bus_i[completion_lane].data;
            end
        end
    end
    wire issue_plain_alu_op =
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
    wire issue_early_alu_consumer = issue_plain_alu_op |
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE];
    wire rs1_issue_early_alu_fwd =
        issue_early_alu_valid_ff &&
        issue_early_alu_consumer &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == issue_early_alu_addr_ff);
    wire rs2_issue_early_alu_fwd =
        issue_early_alu_valid_ff &&
        issue_early_alu_consumer &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == issue_early_alu_addr_ff);
    wire [DATA_WIDTH-1:0] issue_rs1_data =
        rs1_issue_early_alu_fwd ? issue_early_alu_data :
        rs1_completion_fwd ? rs1_completion_data :
        producer_rs1_fwd_i.valid ? producer_rs1_fwd_i.data :
        rs1_wb_fwd  ? wb_fwd_i.data  : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_rs2_data =
        rs2_issue_early_alu_fwd ? issue_early_alu_data :
        rs2_completion_fwd ? rs2_completion_data :
        producer_rs2_fwd_i.valid ? producer_rs2_fwd_i.data :
        rs2_wb_fwd  ? wb_fwd_i.data  : rf_rdata_rs2_i;
    assign operand_a     =  issue_operand_a_pc_sel_ff ? issue_pc_ff :
                            issue_operand_a_imm_sel_ff ? issue_imm_ff : issue_rs1_data;
    assign operand_b     = issue_operand_b_jump_sel_ff ? 32'h4 :
                            issue_operand_b_rs_sel_ff ? issue_rs2_data : issue_imm_ff;


    assign bt_a_operand = issue_bt_a_rs_sel_ff ? issue_rs1_data : issue_pc_ff;
    assign bt_b_operand = issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_lsu_addr_fast = issue_rs1_data + issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_lsu_addr = issue_lsu_addr_fast;
    wire [1:0] issue_lsu_addr_index = issue_lsu_addr[1:0];
    wire issue_lsu_is_sb = issue_operator_lsu_ff[ydrasil_pkg::OP_LSU_SB];
    wire issue_lsu_is_sh = issue_operator_lsu_ff[ydrasil_pkg::OP_LSU_SH];
    wire issue_lsu_is_sw = issue_operator_lsu_ff[ydrasil_pkg::OP_LSU_SW];
    wire [3:0] issue_lsu_sb_mask =
        ({4{issue_lsu_addr_index == 2'b00}} & 4'b0001) |
        ({4{issue_lsu_addr_index == 2'b01}} & 4'b0010) |
        ({4{issue_lsu_addr_index == 2'b10}} & 4'b0100) |
        ({4{issue_lsu_addr_index == 2'b11}} & 4'b1000);
    wire [3:0] issue_lsu_sh_mask = issue_lsu_addr_index[1] ? 4'b1100 : 4'b0011;
    wire [3:0] issue_lsu_store_mask =
        ({4{issue_lsu_is_sb}} & issue_lsu_sb_mask) |
        ({4{issue_lsu_is_sh}} & issue_lsu_sh_mask) |
        ({4{issue_lsu_is_sw}} & 4'b1111);
    wire [DATA_WIDTH-1:0] issue_branch_pc_target = issue_pc_ff + issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_jalr_target = issue_rs1_data + issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_branch_next_pc = issue_pc_ff + 32'd4;
    wire issue_branch_eq = (issue_rs1_data == issue_rs2_data);
    wire issue_branch_ge_signed = ($signed(issue_rs1_data) >= $signed(issue_rs2_data));
    wire issue_branch_ge_unsigned = (issue_rs1_data >= issue_rs2_data);
    wire issue_early_sources_ready =
        issue_valid_ff & issue_rf_wen_rd_ff & (issue_rf_waddr_rd_ff != '0) &
        !(hzd_status_i.prev_alu_bypass_rs1 & !rs1_issue_early_alu_fwd) &
        !(hzd_status_i.prev_alu_bypass_rs2 & !rs2_issue_early_alu_fwd) &
        !hzd_status_i.prev_load_bypass_rs1 &
        !hzd_status_i.prev_load_bypass_rs2 &
        !(issue_rf_ren_rs1_ff && producer_rs1_fwd_i.valid &&
          !rs1_issue_early_alu_fwd && !rs1_completion_fwd) &
        !(issue_operand_b_rs_sel_ff && producer_rs2_fwd_i.valid &&
          !rs2_issue_early_alu_fwd && !rs2_completion_fwd);
    wire issue_early_add_op = issue_early_sources_ready & issue_plain_alu_op &
        issue_operator_ff[ydrasil_pkg::OP_ALU_ADD];
    wire issue_early_sub_op = issue_early_sources_ready & issue_plain_alu_op &
        issue_operator_ff[ydrasil_pkg::OP_ALU_SUB];
    wire issue_early_cmp_op = issue_early_sources_ready & issue_plain_alu_op &
        (issue_operator_ff[ydrasil_pkg::OP_ALU_SLT] |
         issue_operator_ff[ydrasil_pkg::OP_ALU_SLTU]);
    wire issue_early_logic_op = issue_early_sources_ready & issue_plain_alu_op &
        (issue_operator_ff[ydrasil_pkg::OP_ALU_XOR] |
         issue_operator_ff[ydrasil_pkg::OP_ALU_OR]   |
         issue_operator_ff[ydrasil_pkg::OP_ALU_AND]);
    wire issue_early_pass_op = issue_valid_ff & issue_rf_wen_rd_ff &
        (issue_rf_waddr_rd_ff != '0) & issue_plain_alu_op &
        (issue_operator_ff[ydrasil_pkg::OP_ALU_LUI] |
         issue_operator_ff[ydrasil_pkg::OP_ALU_AUIPC]);
    wire issue_early_shift_amount =
        (issue_imm_ff[4:0] == 5'd1) |
        (issue_imm_ff[4:0] == 5'd8) |
        (issue_imm_ff[4:0] == 5'd16);
    wire issue_early_shift_op = issue_early_sources_ready & issue_plain_alu_op &
        !issue_operand_b_rs_sel_ff & issue_early_shift_amount &
        issue_operator_ff[ydrasil_pkg::OP_ALU_SRL];
    wire issue_simple_alu_op = issue_early_add_op | issue_early_sub_op |
        issue_early_cmp_op | issue_early_logic_op | issue_early_shift_op |
        issue_early_pass_op;
    wire [DATA_WIDTH-1:0] issue_early_rs1_data =
        rs1_issue_early_alu_fwd ? issue_early_alu_data :
        rs1_completion_fwd ? rs1_completion_data :
        rs1_wb_fwd ? wb_fwd_i.data : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_early_rs2_data =
        rs2_issue_early_alu_fwd ? issue_early_alu_data :
        rs2_completion_fwd ? rs2_completion_data :
        rs2_wb_fwd ? wb_fwd_i.data : rf_rdata_rs2_i;
    wire [DATA_WIDTH-1:0] issue_early_operand_a =
        issue_operand_a_pc_sel_ff ? issue_pc_ff :
        issue_operand_a_imm_sel_ff ? issue_imm_ff : issue_early_rs1_data;
    wire [DATA_WIDTH-1:0] issue_early_operand_b =
        issue_operand_b_jump_sel_ff ? 32'h4 :
        issue_operand_b_rs_sel_ff ? issue_early_rs2_data : issue_imm_ff;
    wire [DATA_WIDTH:0] issue_simple_alu_sub_ext =
        {1'b0, issue_early_operand_a} + {1'b0, ~issue_early_operand_b} +
        {{DATA_WIDTH{1'b0}}, 1'b1};
    wire issue_simple_alu_signs_differ =
        issue_early_operand_a[DATA_WIDTH-1] ^ issue_early_operand_b[DATA_WIDTH-1];
    wire issue_simple_alu_slt_signed =
        issue_simple_alu_signs_differ ? issue_early_operand_a[DATA_WIDTH-1] :
                                        issue_simple_alu_sub_ext[DATA_WIDTH-1];
    wire issue_simple_alu_slt_unsigned = ~issue_simple_alu_sub_ext[DATA_WIDTH];
    wire [DATA_WIDTH-1:0] issue_simple_alu_logic =
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_XOR]}} &
         (issue_early_operand_a ^ issue_early_operand_b)) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_OR]}} &
         (issue_early_operand_a | issue_early_operand_b)) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_AND]}} &
         (issue_early_operand_a & issue_early_operand_b));
    wire [DATA_WIDTH-1:0] issue_simple_alu_add =
        issue_early_operand_a + issue_early_operand_b;
    wire [DATA_WIDTH-1:0] issue_early_pass_result =
        issue_operator_ff[ydrasil_pkg::OP_ALU_LUI] ?
            issue_imm_ff : (issue_pc_ff + issue_imm_ff);
    wire [DATA_WIDTH-1:0] issue_early_cmp_result =
        issue_operator_ff[ydrasil_pkg::OP_ALU_SLT] ?
            {{(DATA_WIDTH-1){1'b0}}, issue_simple_alu_slt_signed} :
            {{(DATA_WIDTH-1){1'b0}}, issue_simple_alu_slt_unsigned};
    reg [DATA_WIDTH-1:0] issue_early_shift_result;
    always_comb begin
        unique case (issue_imm_ff[4:0])
            5'd1:    issue_early_shift_result = issue_early_operand_a >> 1;
            5'd8:    issue_early_shift_result = issue_early_operand_a >> 8;
            5'd16:   issue_early_shift_result = issue_early_operand_a >> 16;
            default: issue_early_shift_result = '0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_early_alu_valid_ff <= 1'b0;
            issue_early_alu_addr_ff <= '0;
            issue_early_kind_ff <= '0;
            issue_early_add_data_ff <= '0;
            issue_early_sub_data_ff <= '0;
            issue_early_cmp_data_ff <= '0;
            issue_early_logic_data_ff <= '0;
            issue_early_shift_data_ff <= '0;
            issue_early_pass_data_ff <= '0;
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
            id_lsu_addr_ff      <= '0;
            id_lsu_store_data_ff <= '0;
            id_lsu_store_mask_ff <= 4'b0000;
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
            id_ex_branch_pc_target_ff <= '0;
            id_ex_jalr_target_ff <= '0;
            id_ex_branch_next_pc_ff <= '0;
            id_ex_branch_eq_ff <= 1'b0;
            id_ex_branch_ge_signed_ff <= 1'b0;
            id_ex_branch_ge_unsigned_ff <= 1'b0;
            id_ex_pred_hit_ff <= 1'b0;
            id_ex_pred_taken_ff <= 1'b0;
            id_ex_pred_target_ff <= '0;
            id_ex_pred_counter_ff <= 2'b01;
            id_ex_pred_bht_index_ff <= '0;
            id_ex_valid_ff <= 1'b0;
            id_fence_i_ff <= 1'b0;
        end else begin
            if (id_advance) begin
                issue_early_alu_valid_ff <= issue_simple_alu_op;
                issue_early_alu_addr_ff <= issue_simple_alu_op ? issue_rf_waddr_rd_ff : '0;
                issue_early_kind_ff <= {
                    issue_early_pass_op,
                    issue_early_shift_op,
                    issue_early_logic_op,
                    issue_early_cmp_op,
                    issue_early_sub_op,
                    issue_early_add_op};
                issue_early_add_data_ff <= issue_early_add_op ?
                    issue_simple_alu_add : '0;
                issue_early_sub_data_ff <= issue_early_sub_op ?
                    issue_simple_alu_sub_ext[DATA_WIDTH-1:0] : '0;
                issue_early_cmp_data_ff <= issue_early_cmp_op ?
                    issue_early_cmp_result : '0;
                issue_early_logic_data_ff <= issue_early_logic_op ?
                    issue_simple_alu_logic : '0;
                issue_early_shift_data_ff <= issue_early_shift_op ?
                    issue_early_shift_result : '0;
                issue_early_pass_data_ff <= issue_early_pass_op ?
                    issue_early_pass_result : '0;

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
                id_lsu_addr_ff      <= issue_lsu_addr;
                // Register raw store data here; lane alignment belongs after the
                // ID/LSU boundary so the RF read path does not also include the
                // LSU address adder and byte-lane mux.
                id_lsu_store_data_ff <= issue_rs2_data;
                id_lsu_store_mask_ff <= issue_lsu_store_mask;
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
                id_ex_branch_pc_target_ff <= issue_branch_pc_target;
                id_ex_jalr_target_ff <= issue_jalr_target;
                id_ex_branch_next_pc_ff <= issue_branch_next_pc;
                id_ex_branch_eq_ff <= issue_branch_eq;
                id_ex_branch_ge_signed_ff <= issue_branch_ge_signed;
                id_ex_branch_ge_unsigned_ff <= issue_branch_ge_unsigned;
                id_ex_pred_hit_ff <= issue_pred_hit_ff;
                id_ex_pred_taken_ff <= issue_pred_taken_ff;
                id_ex_pred_target_ff <= issue_pred_target_ff;
                id_ex_pred_counter_ff <= issue_pred_counter_ff;
                id_ex_pred_bht_index_ff <= issue_pred_bht_index_ff;
            end

            if (flush_id_i) begin
                id_ex_valid_ff <= 1'b0;
                issue_early_alu_valid_ff <= 1'b0;
                issue_early_kind_ff <= '0;
                id_ex_alu_bypass_rs1_ff <= 1'b0;
                id_ex_alu_bypass_rs2_ff <= 1'b0;
                id_ex_load_bypass_rs1_ff <= 1'b0;
                id_ex_load_bypass_rs2_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
            end else if (id_advance) begin
                id_ex_valid_ff <= issue_valid_ff;
                id_fence_i_ff <= issue_valid_ff & issue_fence_i_ff;
            end else if (bubble_id_i) begin
                id_ex_valid_ff <= 1'b0;
                issue_early_alu_valid_ff <= 1'b0;
                issue_early_kind_ff <= '0;
                id_ex_alu_bypass_rs1_ff <= 1'b0;
                id_ex_alu_bypass_rs2_ff <= 1'b0;
                id_ex_load_bypass_rs1_ff <= 1'b0;
                id_ex_load_bypass_rs2_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
            end else begin
                id_fence_i_ff <= 1'b0;
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
    assign lsu_req_o.addr = id_lsu_addr_ff;
    // Classify the already-registered address so the source-forwarding mux and
    // address carry chain are not part of the DTCM-select register path.
    assign lsu_req_o.addr_is_dtcm =
        (id_lsu_addr_ff[DATA_WIDTH-1:DTCM_TAG_LSB] ==
         ydrasil_pkg::DTCM_BASE_ADDR[DATA_WIDTH-1:DTCM_TAG_LSB]);
    assign lsu_req_o.rd_addr = rf_waddr_rd_ff;
    assign lsu_req_o.producer_id = producer_id_ff;
    assign lsu_req_o.producer_tracked = producer_tracked_ff;
    assign lsu_req_o.store_data = id_lsu_store_data_ff;
    assign lsu_req_o.store_mask = id_lsu_store_mask_ff;
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
    assign id_ex_branch_target_o = id_ex_jalr_ff ?
        id_ex_jalr_target_ff : id_ex_branch_pc_target_ff;
    assign id_ex_branch_next_pc_o = id_ex_branch_next_pc_ff;
    assign id_ex_branch_eq_o = id_ex_branch_eq_ff;
    assign id_ex_branch_ge_signed_o = id_ex_branch_ge_signed_ff;
    assign id_ex_branch_ge_unsigned_o = id_ex_branch_ge_unsigned_ff;
    assign id_fence_i_o = id_fence_i_ff;
    assign id_ex_pred_hit_o = id_ex_pred_hit_ff;
    assign id_ex_pred_taken_o = id_ex_pred_taken_ff;
    assign id_ex_pred_target_o = id_ex_pred_target_ff;
    assign id_ex_pred_counter_o = id_ex_pred_counter_ff;
    assign id_ex_pred_bht_index_o = id_ex_pred_bht_index_ff;
    assign id_ex_valid_o = id_ex_valid_ff;
    assign id_ex_producer_id_o = producer_id_ff;
    assign id_ex_producer_tracked_o = producer_tracked_ff;

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
         ((issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
           issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &
          issue_early_alu_valid_ff) |
         (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] &
          issue_rf_ren_rs1_ff & issue_rf_ren_rs2_ff & !issue_rf_wen_rd_ff));
    assign id_ctrl_o.load_bypass_ok = issue_valid_ff & issue_plain_alu_op;
    assign id_ctrl_o.serialize_before = issue_valid_ff &
        (issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_CSR] |
         issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_SYS] |
         issue_fence_i_ff);

endmodule
