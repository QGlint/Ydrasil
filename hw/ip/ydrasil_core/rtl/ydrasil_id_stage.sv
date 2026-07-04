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

    // ID/RF pipeline register outputs (issue_*_ff -> rf_stage)
    output wire                            id_rf_valid_o,
    output wire [DATA_WIDTH-1:0]           id_rf_pc_o,
    output wire [4:0]                      id_rf_raddr_rs1_o,
    output wire [4:0]                      id_rf_raddr_rs2_o,
    output wire                            id_rf_ren_rs1_o,
    output wire                            id_rf_ren_rs2_o,
    output wire [4:0]                      id_rf_waddr_rd_o,
    output wire                            id_rf_wen_rd_o,
    output wire [DATA_WIDTH-1:0]           id_rf_imm_o,
    output wire                            id_rf_operand_b_rs_sel_o,
    output wire                            id_rf_operand_a_pc_sel_o,
    output wire                            id_rf_operand_a_imm_sel_o,
    output wire                            id_rf_bt_a_rs_sel_o,
    output wire                            id_rf_operand_b_jump_sel_o,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      id_rf_operator_o,
    output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   id_rf_operator_lsu_o,
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] id_rf_operator_type_o,
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      id_rf_csr_raddr_o,
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      id_rf_csr_waddr_o,
    output wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]   id_rf_csr_op_info_o,
    output wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   id_rf_sys_op_info_o,
    output wire                            id_rf_fence_i_o,

    // Branch prediction passthrough
    output wire                            id_rf_pred_hit_o,
    output wire                            id_rf_pred_taken_o,
    output wire [DATA_WIDTH-1:0]           id_rf_pred_target_o,
    output wire [1:0]                      id_rf_pred_counter_o,
    output wire [DATA_WIDTH-1:0]           id_rf_pred_bht_index_o

);

    wire [4:0]                           rf_raddr_rs1;
    wire [4:0]                           rf_raddr_rs2;
    wire                                 rf_ren_rs1;
    wire                                 rf_ren_rs2;
    wire [4:0]                           rf_waddr_rd;
    wire                                 rf_wen_rd;
    wire [DATA_WIDTH-1:0]                imm_i;
    wire                                 operand_b_rs_sel;
    wire                                 operand_a_pc_sel;
    wire                                 operand_a_imm_sel;
    wire                                 bt_a_rs_sel;
    wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]      operator_type;
    wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]           operator;
    wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]        operator_lsu;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr;
    wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr;
    wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]  csr_op_info;
    wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]  sys_op_info;
    wire                            operand_b_jump_sel;
    wire                            id_fence_i;
    wire                            id_advance;

    // issue pipeline registers (ID -> RF boundary)
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
        .csr_ex_waddr_o     (csr_ex_waddr),
        .csr_op_info_o      (csr_op_info),
        .sys_op_info_o      (sys_op_info),
        .operator_o         (operator),
        .operator_lsu_o     (operator_lsu),
        .operator_type_o    (operator_type)
    );

    assign id_advance = !stall_id_i && !bubble_id_i;

    assign id_fence_i = (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                        (if_id_instr_i[14:12] == 3'b001);

    // Issue pipeline registers (ID -> RF boundary)
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
        end else begin
            if (flush_id_i) begin
                issue_valid_ff <= 1'b0;
                issue_fence_i_ff <= 1'b0;
            end else if (id_advance) begin
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

                issue_valid_ff <= if_id_valid_i;
            end
        end
    end

    // ID/RF outputs
    assign id_rf_valid_o           = issue_valid_ff;
    assign id_rf_pc_o              = issue_pc_ff;
    assign id_rf_raddr_rs1_o       = issue_rf_raddr_rs1_ff;
    assign id_rf_raddr_rs2_o       = issue_rf_raddr_rs2_ff;
    assign id_rf_ren_rs1_o         = issue_rf_ren_rs1_ff;
    assign id_rf_ren_rs2_o         = issue_rf_ren_rs2_ff;
    assign id_rf_waddr_rd_o        = issue_rf_waddr_rd_ff;
    assign id_rf_wen_rd_o          = issue_rf_wen_rd_ff;
    assign id_rf_imm_o             = issue_imm_ff;
    assign id_rf_operand_b_rs_sel_o    = issue_operand_b_rs_sel_ff;
    assign id_rf_operand_a_pc_sel_o    = issue_operand_a_pc_sel_ff;
    assign id_rf_operand_a_imm_sel_o   = issue_operand_a_imm_sel_ff;
    assign id_rf_bt_a_rs_sel_o         = issue_bt_a_rs_sel_ff;
    assign id_rf_operand_b_jump_sel_o  = issue_operand_b_jump_sel_ff;
    assign id_rf_operator_o        = issue_operator_ff;
    assign id_rf_operator_lsu_o    = issue_operator_lsu_ff;
    assign id_rf_operator_type_o   = issue_operator_type_ff;
    assign id_rf_csr_raddr_o       = issue_csr_reg_raddr_ff;
    assign id_rf_csr_waddr_o       = issue_csr_ex_waddr_ff;
    assign id_rf_csr_op_info_o     = issue_csr_op_info_ff;
    assign id_rf_sys_op_info_o     = issue_sys_op_info_ff;
    assign id_rf_fence_i_o         = issue_fence_i_ff;
    assign id_rf_pred_hit_o        = issue_pred_hit_ff;
    assign id_rf_pred_taken_o      = issue_pred_taken_ff;
    assign id_rf_pred_target_o     = issue_pred_target_ff;
    assign id_rf_pred_counter_o    = issue_pred_counter_ff;
    assign id_rf_pred_bht_index_o  = issue_pred_bht_index_ff;

endmodule
