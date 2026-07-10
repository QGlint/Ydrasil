
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
    input  wire                            if_id_valid_i,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,
    input  wire                            wb_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           wb_fwd_data_i,
    input  wire                            lsu_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           lsu_fwd_data_i,
    input  wire                            alu_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] alu_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           alu_fwd_data_i,
    input  wire                            prev_alu_bypass_rs1_i,
    input  wire                            prev_alu_bypass_rs2_i,

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

    output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   operator_lsu_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_rs2_data_o, // 操作类型信号
    output wire [DATA_WIDTH-1:0]           id_lsu_addr_o,
    output wire                            id_lsu_addr_is_dtcm_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_store_data_o,
    output wire [3:0]                      id_lsu_store_mask_o,

    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    output wire                            id_ex_jalr_o,
    output wire                            id_ex_alu_bypass_rs1_o,
    output wire                            id_ex_alu_bypass_rs2_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_target_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_next_pc_o,
    output wire                            id_ex_branch_eq_o,
    output wire                            id_ex_branch_ge_signed_o,
    output wire                            id_ex_branch_ge_unsigned_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rs1_addr_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rs2_addr_o,
    output wire                            id_ctrl_rs1_ren_o,
    output wire                            id_ctrl_rs2_ren_o,
    output wire                            id_ctrl_rd_wen_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rd_addr_o,
    output wire                            id_ctrl_lsu_req_o,
    output wire                            id_ctrl_prev_alu_bypass_ok_o,

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
    // Generic writeback information
    output wire                            id_alu_rf_wen_rd_o,
    output wire [4:0]                      id_rf_waddr_rd_o


);

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

    wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]        operator_lsu;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]         operator_lsu_ff;

    wire [DATA_WIDTH-1:0]                bt_a_operand;
    wire [DATA_WIDTH-1:0]                bt_b_operand;
    reg [DATA_WIDTH-1:0]                 bt_a_operand_ff;
    reg [DATA_WIDTH-1:0]                 bt_b_operand_ff;
    reg [DATA_WIDTH-1:0]                 id_instr_addr_ff;
    reg                                  id_ex_jalr_ff;
    reg                                  id_ex_alu_bypass_rs1_ff;
    reg                                  id_ex_alu_bypass_rs2_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_branch_target_ff;
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
    localparam int DTCM_TAG_LSB = ydrasil_pkg::DTCM_ADDR_WIDTH + 2;

    reg                             issue_valid_ff;
    reg [DATA_WIDTH-1:0]            issue_pc_ff;
    reg                             issue_pred_hit_ff;
    reg                             issue_pred_taken_ff;
    reg [DATA_WIDTH-1:0]            issue_pred_target_ff;
    reg [1:0]                       issue_pred_counter_ff;
    reg [DATA_WIDTH-1:0]            issue_pred_bht_index_ff;
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
    reg                             issue_early_alu_valid_ff;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]      issue_early_alu_addr_ff;
    reg [DATA_WIDTH-1:0]            issue_early_alu_data_ff;


    ydrasil_ins_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_ins_decoder (
        .instr_i            (if_id_instr_i),
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

    assign id_advance = !stall_id_i && !bubble_id_i;

    assign rf_addr_rs1_o = issue_rf_raddr_rs1_ff;
    assign rf_addr_rs2_o = issue_rf_raddr_rs2_ff;

    // Keep ALU source selection consistent with decoder control outputs.
    wire rs1_wb_fwd =
        wb_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == wb_fwd_addr_i);
    wire rs2_wb_fwd =
        wb_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == wb_fwd_addr_i);
    wire rs1_lsu_fwd =
        lsu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == lsu_fwd_addr_i);
    wire rs2_lsu_fwd =
        lsu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == lsu_fwd_addr_i);
    wire rs1_alu_fwd =
        alu_fwd_valid_i &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == alu_fwd_addr_i);
    wire rs2_alu_fwd =
        alu_fwd_valid_i &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == alu_fwd_addr_i);
    wire issue_plain_alu_op =
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
    wire rs1_issue_early_alu_fwd =
        issue_early_alu_valid_ff &&
        issue_plain_alu_op &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == issue_early_alu_addr_ff);
    wire rs2_issue_early_alu_fwd =
        issue_early_alu_valid_ff &&
        issue_plain_alu_op &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == issue_early_alu_addr_ff);
    wire [DATA_WIDTH-1:0] issue_rs1_data =
        rs1_issue_early_alu_fwd ? issue_early_alu_data_ff :
        rs1_lsu_fwd ? lsu_fwd_data_i :
        rs1_alu_fwd ? alu_fwd_data_i :
        rs1_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_rs2_data =
        rs2_issue_early_alu_fwd ? issue_early_alu_data_ff :
        rs2_lsu_fwd ? lsu_fwd_data_i :
        rs2_alu_fwd ? alu_fwd_data_i :
        rs2_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs2_i;
    wire [DATA_WIDTH-1:0] issue_early_rs1_data =
        rs1_issue_early_alu_fwd ? issue_early_alu_data_ff :
        rs1_alu_fwd ? alu_fwd_data_i :
        rs1_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_early_rs2_data =
        rs2_issue_early_alu_fwd ? issue_early_alu_data_ff :
        rs2_alu_fwd ? alu_fwd_data_i :
        rs2_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs2_i;

    assign operand_a     =  issue_operand_a_pc_sel_ff ? issue_pc_ff :
                            issue_operand_a_imm_sel_ff ? issue_imm_ff : issue_rs1_data;
    assign operand_b     = issue_operand_b_jump_sel_ff ? 32'h4 :
                            issue_operand_b_rs_sel_ff ? issue_rs2_data : issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_early_operand_a =
        issue_operand_a_pc_sel_ff ? issue_pc_ff :
        issue_operand_a_imm_sel_ff ? issue_imm_ff : issue_early_rs1_data;
    wire [DATA_WIDTH-1:0] issue_early_operand_b =
        issue_operand_b_jump_sel_ff ? 32'h4 :
        issue_operand_b_rs_sel_ff ? issue_early_rs2_data : issue_imm_ff;


    assign bt_a_operand = issue_bt_a_rs_sel_ff ? issue_rs1_data : issue_pc_ff;
    assign bt_b_operand = issue_imm_ff;
    assign id_fence_i = (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                        (if_id_instr_i[14:12] == 3'b001);

    wire [DATA_WIDTH-1:0] issue_lsu_addr_fast = issue_rs1_data + issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_lsu_addr = issue_lsu_addr_fast;
    wire [1:0] issue_lsu_addr_index = issue_lsu_addr[1:0];
    wire issue_lsu_addr_is_dtcm =
        (issue_lsu_addr[DATA_WIDTH-1:DTCM_TAG_LSB] ==
         ydrasil_pkg::DTCM_BASE_ADDR[DATA_WIDTH-1:DTCM_TAG_LSB]);
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
    wire [DATA_WIDTH-1:0] issue_lsu_sb_data =
        ({DATA_WIDTH{issue_lsu_addr_index == 2'b00}} & {24'b0, issue_rs2_data[7:0]}) |
        ({DATA_WIDTH{issue_lsu_addr_index == 2'b01}} & {16'b0, issue_rs2_data[7:0], 8'b0}) |
        ({DATA_WIDTH{issue_lsu_addr_index == 2'b10}} & {8'b0, issue_rs2_data[7:0], 16'b0}) |
        ({DATA_WIDTH{issue_lsu_addr_index == 2'b11}} & {issue_rs2_data[7:0], 24'b0});
    wire [DATA_WIDTH-1:0] issue_lsu_sh_data =
        issue_lsu_addr_index[1] ? {issue_rs2_data[15:0], 16'b0} :
                                  {16'b0, issue_rs2_data[15:0]};
    wire [DATA_WIDTH-1:0] issue_lsu_store_data =
        ({DATA_WIDTH{issue_lsu_is_sb}} & issue_lsu_sb_data) |
        ({DATA_WIDTH{issue_lsu_is_sh}} & issue_lsu_sh_data) |
        ({DATA_WIDTH{issue_lsu_is_sw}} & issue_rs2_data);
    wire [DATA_WIDTH-1:0] issue_branch_target = bt_a_operand + bt_b_operand;
    wire [DATA_WIDTH-1:0] issue_branch_next_pc = issue_pc_ff + 32'd4;
    wire issue_branch_eq = (issue_rs1_data == issue_rs2_data);
    wire issue_branch_ge_signed = ($signed(issue_rs1_data) >= $signed(issue_rs2_data));
    wire issue_branch_ge_unsigned = (issue_rs1_data >= issue_rs2_data);
    wire issue_uses_lsu_fwd = rs1_lsu_fwd | rs2_lsu_fwd;
    wire issue_simple_alu_op =
        issue_valid_ff & issue_rf_wen_rd_ff & (issue_rf_waddr_rd_ff != '0) &
        issue_plain_alu_op & !issue_uses_lsu_fwd &
        (issue_operator_ff[ydrasil_pkg::OP_ALU_ADD]  |
         issue_operator_ff[ydrasil_pkg::OP_ALU_SUB]  |
         issue_operator_ff[ydrasil_pkg::OP_ALU_SLT]  |
         issue_operator_ff[ydrasil_pkg::OP_ALU_SLTU] |
         issue_operator_ff[ydrasil_pkg::OP_ALU_XOR]  |
         issue_operator_ff[ydrasil_pkg::OP_ALU_OR]   |
         issue_operator_ff[ydrasil_pkg::OP_ALU_AND]  |
         issue_operator_ff[ydrasil_pkg::OP_ALU_LUI]  |
         issue_operator_ff[ydrasil_pkg::OP_ALU_AUIPC]);
    wire [DATA_WIDTH:0] issue_simple_alu_sub_ext =
        {1'b0, issue_early_operand_a} + {1'b0, ~issue_early_operand_b} + {{DATA_WIDTH{1'b0}}, 1'b1};
    wire issue_simple_alu_signs_differ =
        issue_early_operand_a[DATA_WIDTH-1] ^ issue_early_operand_b[DATA_WIDTH-1];
    wire issue_simple_alu_slt_signed =
        issue_simple_alu_signs_differ ? issue_early_operand_a[DATA_WIDTH-1] :
                                        issue_simple_alu_sub_ext[DATA_WIDTH-1];
    wire issue_simple_alu_slt_unsigned = ~issue_simple_alu_sub_ext[DATA_WIDTH];
    wire [DATA_WIDTH-1:0] issue_simple_alu_logic =
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_XOR]}} & (issue_early_operand_a ^ issue_early_operand_b)) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_OR]}}  & (issue_early_operand_a | issue_early_operand_b)) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_AND]}} & (issue_early_operand_a & issue_early_operand_b));
    wire [DATA_WIDTH-1:0] issue_simple_alu_result =
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_SUB]}}  & issue_simple_alu_sub_ext[DATA_WIDTH-1:0]) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_SLT]}}  & {{(DATA_WIDTH-1){1'b0}}, issue_simple_alu_slt_signed}) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_SLTU]}} & {{(DATA_WIDTH-1){1'b0}}, issue_simple_alu_slt_unsigned}) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_XOR] |
                     issue_operator_ff[ydrasil_pkg::OP_ALU_OR] |
                     issue_operator_ff[ydrasil_pkg::OP_ALU_AND]}} & issue_simple_alu_logic) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_LUI]}} & issue_early_operand_b) |
        ({DATA_WIDTH{issue_operator_ff[ydrasil_pkg::OP_ALU_ADD] |
                     issue_operator_ff[ydrasil_pkg::OP_ALU_AUIPC]}} & (issue_early_operand_a + issue_early_operand_b));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_valid_ff <= 1'b0;
            issue_pc_ff <= '0;
            issue_pred_hit_ff <= 1'b0;
            issue_pred_taken_ff <= 1'b0;
            issue_pred_target_ff <= '0;
            issue_pred_counter_ff <= 2'b01;
            issue_pred_bht_index_ff <= '0;
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
            issue_early_alu_valid_ff <= 1'b0;
            issue_early_alu_addr_ff <= '0;
            issue_early_alu_data_ff <= '0;
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
            id_ex_alu_bypass_rs1_ff <= 1'b0;
            id_ex_alu_bypass_rs2_ff <= 1'b0;
            id_ex_branch_target_ff <= '0;
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
                issue_pc_ff <= if_id_pc_i;
                issue_pred_hit_ff <= if_id_pred_hit_i;
                issue_pred_taken_ff <= if_id_pred_taken_i;
                issue_pred_target_ff <= if_id_pred_target_i;
                issue_pred_counter_ff <= if_id_pred_counter_i;
                issue_pred_bht_index_ff <= if_id_pred_bht_index_i;
                issue_rf_raddr_rs1_ff <= rf_raddr_rs1;
                issue_rf_raddr_rs2_ff <= rf_raddr_rs2;
                issue_rf_ren_rs1_ff <= rf_ren_rs1;
                issue_rf_ren_rs2_ff <= rf_ren_rs2;
                issue_rf_waddr_rd_ff <= rf_waddr_rd;
                issue_rf_wen_rd_ff <= rf_wen_rd;
                issue_imm_ff <= imm_i;
                issue_operand_b_rs_sel_ff <= operand_b_rs_sel;
                issue_operand_a_pc_sel_ff <= operand_a_pc_sel;
                issue_operand_a_imm_sel_ff <= operand_a_imm_sel;
                issue_bt_a_rs_sel_ff <= bt_a_rs_sel;
                issue_operand_b_jump_sel_ff <= operand_b_jump_sel;
                issue_operator_ff <= operator;
                issue_operator_lsu_ff <= operator_lsu;
                issue_operator_type_ff <= operator_type;
                issue_csr_reg_raddr_ff <= csr_reg_raddr;
                issue_csr_ex_waddr_ff <= csr_ex_waddr;
                issue_csr_op_info_ff <= csr_op_info;
                issue_sys_op_info_ff <= sys_op_info;
                issue_fence_i_ff <= id_fence_i;
                issue_early_alu_valid_ff <= issue_simple_alu_op;
                issue_early_alu_addr_ff <= issue_simple_alu_op ? issue_rf_waddr_rd_ff : '0;
                issue_early_alu_data_ff <= issue_simple_alu_op ? issue_simple_alu_result : '0;

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
                operator_lsu_ff     <= issue_operator_lsu_ff;
                id_lsu_rs2_data_ff  <= issue_rs2_data; // 直接传递寄存器数据，供LSU使用
                id_lsu_addr_ff      <= issue_lsu_addr;
                id_lsu_addr_is_dtcm_ff <= issue_lsu_addr_is_dtcm;
                id_lsu_store_data_ff <= issue_lsu_store_data;
                id_lsu_store_mask_ff <= issue_lsu_store_mask;
                bt_a_operand_ff     <= bt_a_operand;
                bt_b_operand_ff     <= bt_b_operand;
                csr_reg_raddr_ff <= issue_csr_reg_raddr_ff;
                // csr_ex_we_ff <= csr_ex_we;
                csr_ex_waddr_ff <= issue_csr_ex_waddr_ff;
                csr_op_info_ff <= issue_csr_op_info_ff;
                sys_op_info_ff <= issue_sys_op_info_ff;
                id_instr_addr_ff <= issue_pc_ff;
                id_ex_jalr_ff <= issue_bt_a_rs_sel_ff;
                id_ex_alu_bypass_rs1_ff <= issue_valid_ff & prev_alu_bypass_rs1_i;
                id_ex_alu_bypass_rs2_ff <= issue_valid_ff & prev_alu_bypass_rs2_i;
                id_ex_branch_target_ff <= issue_branch_target;
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
                issue_valid_ff <= 1'b0;
                id_ex_valid_ff <= 1'b0;
                issue_early_alu_valid_ff <= 1'b0;
                id_ex_alu_bypass_rs1_ff <= 1'b0;
                id_ex_alu_bypass_rs2_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
            end else if (id_advance) begin
                issue_valid_ff <= if_id_valid_i;
                id_ex_valid_ff <= issue_valid_ff;
                id_fence_i_ff <= issue_valid_ff & issue_fence_i_ff;
            end else if (bubble_id_i) begin
                id_ex_valid_ff <= 1'b0;
                issue_early_alu_valid_ff <= 1'b0;
                id_ex_alu_bypass_rs1_ff <= 1'b0;
                id_ex_alu_bypass_rs2_ff <= 1'b0;
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
    assign id_ex_alu_bypass_rs1_o = id_ex_alu_bypass_rs1_ff;
    assign id_ex_alu_bypass_rs2_o = id_ex_alu_bypass_rs2_ff;
    assign id_ex_branch_target_o = id_ex_branch_target_ff;
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
    assign id_ctrl_prev_alu_bypass_ok_o = issue_valid_ff &
        issue_plain_alu_op;

endmodule
