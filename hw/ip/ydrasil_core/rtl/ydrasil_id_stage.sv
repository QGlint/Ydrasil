
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
    input  wire                            rs1_issue_alu_ready_next_i,
    input  wire                            rs2_issue_alu_ready_next_i,
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

    reg                             skid_valid_ff;
    reg [DATA_WIDTH-1:0]            skid_pc_ff;
    reg [DATA_WIDTH-1:0]            skid_instr_ff;
    reg                             skid_pred_hit_ff;
    reg                             skid_pred_taken_ff;
    reg [DATA_WIDTH-1:0]            skid_pred_target_ff;
    reg [1:0]                       skid_pred_counter_ff;
    reg [DATA_WIDTH-1:0]            skid_pred_bht_index_ff;

    reg                             issue_valid_ff;
    reg                             issue_wait_rs1_ff;
    reg                             issue_wait_rs2_ff;
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

    wire [DATA_WIDTH-1:0]            decode_pc;
    wire [DATA_WIDTH-1:0]            decode_instr;
    wire                             decode_pred_hit;
    wire                             decode_pred_taken;
    wire [DATA_WIDTH-1:0]            decode_pred_target;
    wire [1:0]                       decode_pred_counter;
    wire [DATA_WIDTH-1:0]            decode_pred_bht_index;
    wire                             decode_valid;
    wire                             issue_wait_rs1_ready;
    wire                             issue_wait_rs2_ready;
    wire                             issue_wait_block;
    wire                             issue_fire;
    wire                             issue_accept;
    wire                             issue_load_from_skid;

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

    assign id_advance = !stall_id_i && !bubble_id_i;
    assign decode_pc = skid_valid_ff ? skid_pc_ff : if_id_pc_i;
    assign decode_instr = skid_valid_ff ? skid_instr_ff : if_id_instr_i;
    assign decode_pred_hit = skid_valid_ff ? skid_pred_hit_ff : if_id_pred_hit_i;
    assign decode_pred_taken = skid_valid_ff ? skid_pred_taken_ff : if_id_pred_taken_i;
    assign decode_pred_target = skid_valid_ff ? skid_pred_target_ff : if_id_pred_target_i;
    assign decode_pred_counter = skid_valid_ff ? skid_pred_counter_ff : if_id_pred_counter_i;
    assign decode_pred_bht_index = skid_valid_ff ? skid_pred_bht_index_ff : if_id_pred_bht_index_i;
    assign decode_valid = skid_valid_ff | if_id_valid_i;

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
    wire [DATA_WIDTH-1:0] issue_rs1_data =
        rs1_lsu_fwd ? lsu_fwd_data_i :
        rs1_alu_fwd ? alu_fwd_data_i :
        rs1_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_rs2_data =
        rs2_lsu_fwd ? lsu_fwd_data_i :
        rs2_alu_fwd ? alu_fwd_data_i :
        rs2_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs2_i;

    assign operand_a     =  issue_operand_a_pc_sel_ff ? issue_pc_ff :
                            issue_operand_a_imm_sel_ff ? issue_imm_ff : issue_rs1_data;
    assign operand_b     = issue_operand_b_jump_sel_ff ? 32'h4 :
                            issue_operand_b_rs_sel_ff ? issue_rs2_data : issue_imm_ff;


    assign bt_a_operand = issue_bt_a_rs_sel_ff ? issue_rs1_data : issue_pc_ff;
    assign bt_b_operand = issue_imm_ff;
    assign id_fence_i = (decode_instr[6:0] == ydrasil_pkg::RV32I_INS_FENCE) &&
                        (decode_instr[14:12] == 3'b001);

    assign issue_wait_rs1_ready = !issue_wait_rs1_ff | rs1_alu_fwd | rs1_lsu_fwd | rs1_wb_fwd;
    assign issue_wait_rs2_ready = !issue_wait_rs2_ff | rs2_alu_fwd | rs2_lsu_fwd | rs2_wb_fwd;
    assign issue_wait_block =
        (issue_wait_rs1_ff & !issue_wait_rs1_ready) |
        (issue_wait_rs2_ff & !issue_wait_rs2_ready) |
        rs1_issue_alu_ready_next_i |
        rs2_issue_alu_ready_next_i;
    assign issue_fire =
        issue_valid_ff & id_advance & !issue_wait_block;
    assign issue_accept =
        id_advance & decode_valid & (!issue_valid_ff | issue_fire);
    assign issue_load_from_skid = issue_accept & skid_valid_ff;
    assign issue_frontend_stall_o =
        !flush_id_i & !stall_id_i & !bubble_id_i &
        issue_valid_ff & issue_wait_block & skid_valid_ff;

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
            issue_valid_ff <= 1'b0;
            issue_wait_rs1_ff <= 1'b0;
            issue_wait_rs2_ff <= 1'b0;
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
            id_ex_valid_ff <= 1'b0;
            id_fence_i_ff <= 1'b0;
        end else begin
            if (flush_id_i) begin
                skid_valid_ff <= 1'b0;
                issue_valid_ff <= 1'b0;
                issue_wait_rs1_ff <= 1'b0;
                issue_wait_rs2_ff <= 1'b0;
                id_ex_valid_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
            end else begin
                if (issue_accept) begin
                    issue_pc_ff <= decode_pc;
                    issue_pred_hit_ff <= decode_pred_hit;
                    issue_pred_taken_ff <= decode_pred_taken;
                    issue_pred_target_ff <= decode_pred_target;
                    issue_pred_counter_ff <= decode_pred_counter;
                    issue_pred_bht_index_ff <= decode_pred_bht_index;
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
                    issue_wait_rs1_ff <= 1'b0;
                    issue_wait_rs2_ff <= 1'b0;
                    issue_valid_ff <= 1'b1;
                end else if (id_advance && issue_valid_ff) begin
                    issue_wait_rs1_ff <= issue_wait_rs1_ff | rs1_issue_alu_ready_next_i;
                    issue_wait_rs2_ff <= issue_wait_rs2_ff | rs2_issue_alu_ready_next_i;
                end

                if (id_advance) begin
                    if (issue_load_from_skid) begin
                        skid_valid_ff <= if_id_valid_i;
                        skid_pc_ff <= if_id_pc_i;
                        skid_instr_ff <= if_id_instr_i;
                        skid_pred_hit_ff <= if_id_pred_hit_i;
                        skid_pred_taken_ff <= if_id_pred_taken_i;
                        skid_pred_target_ff <= if_id_pred_target_i;
                        skid_pred_counter_ff <= if_id_pred_counter_i;
                        skid_pred_bht_index_ff <= if_id_pred_bht_index_i;
                    end else if (issue_accept) begin
                        skid_valid_ff <= 1'b0;
                    end else if (issue_valid_ff && issue_wait_block && !skid_valid_ff && if_id_valid_i) begin
                        skid_valid_ff <= 1'b1;
                        skid_pc_ff <= if_id_pc_i;
                        skid_instr_ff <= if_id_instr_i;
                        skid_pred_hit_ff <= if_id_pred_hit_i;
                        skid_pred_taken_ff <= if_id_pred_taken_i;
                        skid_pred_target_ff <= if_id_pred_target_i;
                        skid_pred_counter_ff <= if_id_pred_counter_i;
                        skid_pred_bht_index_ff <= if_id_pred_bht_index_i;
                    end
                end

                if (stall_id_i) begin
                    // Hold ID/EX stable while EX finishes a multi-cycle operation.
                end else if (issue_fire) begin
                    operand_a_ff        <= operand_a;
                    operand_b_ff        <= operand_b;
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
                    id_ex_pred_hit_ff <= issue_pred_hit_ff;
                    id_ex_pred_taken_ff <= issue_pred_taken_ff;
                    id_ex_pred_target_ff <= issue_pred_target_ff;
                    id_ex_pred_counter_ff <= issue_pred_counter_ff;
                    id_ex_pred_bht_index_ff <= issue_pred_bht_index_ff;
                    id_ex_valid_ff <= 1'b1;
                    id_fence_i_ff <= issue_fence_i_ff;
                    if (!issue_accept) begin
                        issue_valid_ff <= 1'b0;
                        issue_wait_rs1_ff <= 1'b0;
                        issue_wait_rs2_ff <= 1'b0;
                    end
                end else begin
                    id_ex_valid_ff <= 1'b0;
                    id_fence_i_ff <= 1'b0;
                end
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
