
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
    input  wire                            if_id_valid_i,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,

    // Dispatch to EX   
    // output wire                            alu_valid_o,
    output wire [DATA_WIDTH-1:0]           operand_a_o,
    output wire [DATA_WIDTH-1:0]           operand_b_o,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      operator_o, // 统一的ALU操作信息信号

    output wire [DATA_WIDTH-1:0]           bt_a_operand_o,
    output wire [DATA_WIDTH-1:0]           bt_b_operand_o,

    output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   operator_lsu_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_rs2_data_o, // 操作类型信号

    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    output wire                            id_ex_jalr_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rs1_addr_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rs2_addr_o,
    output wire                            id_ctrl_rs1_ren_o,
    output wire                            id_ctrl_rs2_ren_o,
    output wire                            id_ctrl_rd_wen_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     id_ctrl_rd_addr_o,
    output wire                            id_ctrl_lsu_req_o,

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

    reg                             issue_valid_ff;
    reg [DATA_WIDTH-1:0]            issue_pc_ff;
    reg                             issue_pred_hit_ff;
    reg                             issue_pred_taken_ff;
    reg [DATA_WIDTH-1:0]            issue_pred_target_ff;
    reg [1:0]                       issue_pred_counter_ff;
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
    assign operand_a     =  issue_operand_a_pc_sel_ff ? issue_pc_ff :
                            issue_operand_a_imm_sel_ff ? issue_imm_ff : rf_rdata_rs1_i;
    assign operand_b     = issue_operand_b_jump_sel_ff ? 32'h4 :
                            issue_operand_b_rs_sel_ff ? rf_rdata_rs2_i : issue_imm_ff;


    assign bt_a_operand = issue_bt_a_rs_sel_ff ? rf_rdata_rs1_i : issue_pc_ff;
    assign bt_b_operand = issue_imm_ff;
    assign id_fence_i = (if_id_instr_i[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                        (if_id_instr_i[14:12] == 3'b001);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_valid_ff <= 1'b0;
            issue_pc_ff <= '0;
            issue_pred_hit_ff <= 1'b0;
            issue_pred_taken_ff <= 1'b0;
            issue_pred_target_ff <= '0;
            issue_pred_counter_ff <= 2'b01;
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
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            operator_lsu_ff     <= '0;
            id_lsu_rs2_data_ff  <= '0;
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
            id_ex_valid_ff <= 1'b0;
            id_fence_i_ff <= 1'b0;
        end else begin
            if (id_advance) begin
                issue_pc_ff <= if_id_pc_i;
                issue_pred_hit_ff <= if_id_pred_hit_i;
                issue_pred_taken_ff <= if_id_pred_taken_i;
                issue_pred_target_ff <= if_id_pred_target_i;
                issue_pred_counter_ff <= if_id_pred_counter_i;
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

                operand_a_ff        <= operand_a;
                operand_b_ff        <= operand_b;
                operator_ff         <= issue_operator_ff;
                operator_type_ff    <= issue_operator_type_ff;
                rf_wen_rd_ff        <= issue_rf_wen_rd_ff;
                rf_waddr_rd_ff      <= issue_rf_waddr_rd_ff;
                operator_lsu_ff     <= issue_operator_lsu_ff;
                id_lsu_rs2_data_ff  <= rf_rdata_rs2_i; // 直接传递寄存器数据，供LSU使用
                bt_a_operand_ff     <= bt_a_operand;
                bt_b_operand_ff     <= bt_b_operand;
                csr_reg_raddr_ff <= issue_csr_reg_raddr_ff;
                // csr_ex_we_ff <= csr_ex_we;
                csr_ex_waddr_ff <= issue_csr_ex_waddr_ff;
                csr_op_info_ff <= issue_csr_op_info_ff;
                sys_op_info_ff <= issue_sys_op_info_ff;
                id_instr_addr_ff <= issue_pc_ff;
                id_ex_jalr_ff <= issue_bt_a_rs_sel_ff;
                id_ex_pred_hit_ff <= issue_pred_hit_ff;
                id_ex_pred_taken_ff <= issue_pred_taken_ff;
                id_ex_pred_target_ff <= issue_pred_target_ff;
                id_ex_pred_counter_ff <= issue_pred_counter_ff;
            end

            if (flush_id_i) begin
                issue_valid_ff <= 1'b0;
                id_ex_valid_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
            end else if (id_advance) begin
                issue_valid_ff <= if_id_valid_i;
                id_ex_valid_ff <= issue_valid_ff;
                id_fence_i_ff <= issue_valid_ff & issue_fence_i_ff;
            end else if (bubble_id_i) begin
                id_ex_valid_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
            end else begin
                id_fence_i_ff <= 1'b0;
            end
        end
    end

    assign operand_a_o          = operand_a_ff;
    assign operand_b_o          = operand_b_ff;
    assign operator_o           = operator_ff;
    assign id_alu_rf_wen_rd_o   = rf_wen_rd_ff;
    assign id_rf_waddr_rd_o     = rf_waddr_rd_ff;
    assign operator_lsu_o       = operator_lsu_ff;
    assign operator_type_o      = operator_type_ff;
    assign id_lsu_rs2_data_o    = id_lsu_rs2_data_ff; // 直接传递寄存器数据，供LSU使用
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

endmodule
