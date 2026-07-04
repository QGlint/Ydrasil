module ydrasil_rf_stage
import ydrasil_pkg::*;
 #(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            stall_rf_i,
    input  wire                            bubble_rf_i,
    input  wire                            flush_rf_i,

    // ID/RF pipeline register inputs (from id_stage issue_*_ff)
    input  wire                            id_rf_valid_i,
    input  wire [DATA_WIDTH-1:0]           id_rf_pc_i,
    input  wire [4:0]                      id_rf_raddr_rs1_i,
    input  wire [4:0]                      id_rf_raddr_rs2_i,
    input  wire                            id_rf_ren_rs1_i,
    input  wire                            id_rf_ren_rs2_i,
    input  wire [4:0]                      id_rf_waddr_rd_i,
    input  wire                            id_rf_wen_rd_i,
    input  wire [DATA_WIDTH-1:0]           id_rf_imm_i,
    input  wire                            id_rf_operand_b_rs_sel_i,
    input  wire                            id_rf_operand_a_pc_sel_i,
    input  wire                            id_rf_operand_a_imm_sel_i,
    input  wire                            id_rf_bt_a_rs_sel_i,
    input  wire                            id_rf_operand_b_jump_sel_i,
    input  wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      id_rf_operator_i,
    input  wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   id_rf_operator_lsu_i,
    input  wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] id_rf_operator_type_i,
    input  wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      id_rf_csr_raddr_i,
    input  wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      id_rf_csr_waddr_i,
    input  wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]   id_rf_csr_op_info_i,
    input  wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   id_rf_sys_op_info_i,
    input  wire                            id_rf_fence_i_i,

    // Branch prediction passthrough
    input  wire                            id_rf_pred_hit_i,
    input  wire                            id_rf_pred_taken_i,
    input  wire [DATA_WIDTH-1:0]           id_rf_pred_target_i,
    input  wire [1:0]                      id_rf_pred_counter_i,
    input  wire [DATA_WIDTH-1:0]           id_rf_pred_bht_index_i,

    // Register file read ports (driven by this stage)
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,

    // Forwarding inputs
    input  wire                            wb_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] wb_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           wb_fwd_data_i,
    input  wire                            lsu_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           lsu_fwd_data_i,
    input  wire                            alu_fwd_valid_i,
    input  wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] alu_fwd_addr_i,
    input  wire [DATA_WIDTH-1:0]           alu_fwd_data_i,

    // Dispatch to EX
    output wire [DATA_WIDTH-1:0]           operand_a_o,
    output wire [DATA_WIDTH-1:0]           operand_b_o,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      operator_o,
    output wire [DATA_WIDTH-1:0]           bt_a_operand_o,
    output wire [DATA_WIDTH-1:0]           bt_b_operand_o,
    output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   operator_lsu_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_rs2_data_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_addr_o,
    output wire                            id_lsu_addr_is_dtcm_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_store_data_o,
    output wire [3:0]                      id_lsu_store_mask_o,
    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o,

    // Branch / control passthrough
    output wire                            rf_ex_jalr_o,
    output wire                            rf_ex_pred_hit_o,
    output wire                            rf_ex_pred_taken_o,
    output wire [DATA_WIDTH-1:0]           rf_ex_pred_target_o,
    output wire [1:0]                      rf_ex_pred_counter_o,
    output wire [DATA_WIDTH-1:0]           rf_ex_pred_bht_index_o,
    output wire                            rf_ex_valid_o,

    // Writeback info
    output wire                            rf_alu_rf_wen_rd_o,
    output wire [4:0]                      rf_rf_waddr_rd_o,

    // CSR / sys passthrough
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]     rf_csr_raddr_o,
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]     rf_ex_csr_waddr_o,
    output wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]  rf_op_csr_info_o,
    output wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]  rf_op_sys_info_o,

    output wire [DATA_WIDTH-1:0]           rf_instr_addr_o,
    output wire                            rf_fence_i_o,

    // Scoreboard interface (for gpr_pending check in core)
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    rf_ctrl_rs1_addr_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    rf_ctrl_rs2_addr_o,
    output wire                            rf_ctrl_rs1_ren_o,
    output wire                            rf_ctrl_rs2_ren_o,
    output wire                            rf_ctrl_rd_wen_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]    rf_ctrl_rd_addr_o,
    output wire                            rf_ctrl_lsu_req_o
);

    wire                            rf_advance;
    localparam int DTCM_TAG_LSB = ydrasil_pkg::DTCM_ADDR_WIDTH + 2;

    // Output pipeline registers (RF -> EX)
    reg [DATA_WIDTH-1:0]                operand_a_ff;
    reg [DATA_WIDTH-1:0]                operand_b_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]           operator_ff;
    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]       operator_type_ff;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]         operator_lsu_ff;
    reg [DATA_WIDTH-1:0]                id_lsu_rs2_data_ff;
    reg [DATA_WIDTH-1:0]                id_lsu_addr_ff;
    reg                                 id_lsu_addr_is_dtcm_ff;
    reg [DATA_WIDTH-1:0]                id_lsu_store_data_ff;
    reg [3:0]                           id_lsu_store_mask_ff;
    reg [DATA_WIDTH-1:0]                bt_a_operand_ff;
    reg [DATA_WIDTH-1:0]                bt_b_operand_ff;
    reg [4:0]                           rf_waddr_rd_ff;
    reg                                 rf_wen_rd_ff;
    reg [DATA_WIDTH-1:0]                instr_addr_ff;
    reg                                 ex_jalr_ff;
    reg                                 ex_pred_hit_ff;
    reg                                 ex_pred_taken_ff;
    reg [DATA_WIDTH-1:0]                ex_pred_target_ff;
    reg [1:0]                           ex_pred_counter_ff;
    reg [DATA_WIDTH-1:0]                ex_pred_bht_index_ff;
    reg                                 ex_valid_ff;
    reg                                 fence_i_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      csr_raddr_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]      csr_waddr_ff;
    reg [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]   csr_op_info_ff;
    reg [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   sys_op_info_ff;

    assign rf_advance = !stall_rf_i && !bubble_rf_i;

    // Drive register file read addresses
    assign rf_addr_rs1_o = id_rf_raddr_rs1_i;
    assign rf_addr_rs2_o = id_rf_raddr_rs2_i;

    // ── Forwarding mux ──
    wire rs1_wb_fwd =
        wb_fwd_valid_i &&
        id_rf_ren_rs1_i &&
        (id_rf_raddr_rs1_i != '0) &&
        (id_rf_raddr_rs1_i == wb_fwd_addr_i);
    wire rs2_wb_fwd =
        wb_fwd_valid_i &&
        (id_rf_ren_rs2_i | id_rf_operator_type_i[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (id_rf_raddr_rs2_i != '0) &&
        (id_rf_raddr_rs2_i == wb_fwd_addr_i);
    wire rs1_lsu_fwd =
        lsu_fwd_valid_i &&
        id_rf_ren_rs1_i &&
        (id_rf_raddr_rs1_i != '0) &&
        (id_rf_raddr_rs1_i == lsu_fwd_addr_i);
    wire rs2_lsu_fwd =
        lsu_fwd_valid_i &&
        (id_rf_ren_rs2_i | id_rf_operator_type_i[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (id_rf_raddr_rs2_i != '0) &&
        (id_rf_raddr_rs2_i == lsu_fwd_addr_i);
    wire rs1_alu_fwd =
        alu_fwd_valid_i &&
        id_rf_ren_rs1_i &&
        (id_rf_raddr_rs1_i != '0) &&
        (id_rf_raddr_rs1_i == alu_fwd_addr_i);
    wire rs2_alu_fwd =
        alu_fwd_valid_i &&
        (id_rf_ren_rs2_i | id_rf_operator_type_i[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (id_rf_raddr_rs2_i != '0) &&
        (id_rf_raddr_rs2_i == alu_fwd_addr_i);

    wire [DATA_WIDTH-1:0] issue_rs1_data =
        rs1_lsu_fwd ? lsu_fwd_data_i :
        rs1_alu_fwd ? alu_fwd_data_i :
        rs1_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs1_i;
    wire [DATA_WIDTH-1:0] issue_rs2_data =
        rs2_lsu_fwd ? lsu_fwd_data_i :
        rs2_alu_fwd ? alu_fwd_data_i :
        rs2_wb_fwd  ? wb_fwd_data_i  : rf_rdata_rs2_i;

    // ── Operand mux ──
    wire [DATA_WIDTH-1:0] operand_a =
        id_rf_operand_a_pc_sel_i  ? id_rf_pc_i :
        id_rf_operand_a_imm_sel_i ? id_rf_imm_i : issue_rs1_data;
    wire [DATA_WIDTH-1:0] operand_b =
        id_rf_operand_b_jump_sel_i ? 32'h4 :
        id_rf_operand_b_rs_sel_i  ? issue_rs2_data : id_rf_imm_i;
    wire [DATA_WIDTH-1:0] bt_a_operand =
        id_rf_bt_a_rs_sel_i ? issue_rs1_data : id_rf_pc_i;
    wire [DATA_WIDTH-1:0] bt_b_operand = id_rf_imm_i;

    // ── LSU address and store data generation ──
    wire [DATA_WIDTH-1:0] issue_lsu_addr_fast = issue_rs1_data + id_rf_imm_i;
    wire [DATA_WIDTH-1:0] issue_lsu_addr = issue_lsu_addr_fast;
    wire [1:0] issue_lsu_addr_index = issue_lsu_addr[1:0];
    wire issue_lsu_addr_is_dtcm =
        (issue_lsu_addr[DATA_WIDTH-1:DTCM_TAG_LSB] ==
         ydrasil_pkg::DTCM_BASE_ADDR[DATA_WIDTH-1:DTCM_TAG_LSB]);
    wire issue_lsu_is_sb = id_rf_operator_lsu_i[ydrasil_pkg::OP_LSU_SB];
    wire issue_lsu_is_sh = id_rf_operator_lsu_i[ydrasil_pkg::OP_LSU_SH];
    wire issue_lsu_is_sw = id_rf_operator_lsu_i[ydrasil_pkg::OP_LSU_SW];
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

    // ── Pipeline registers (RF -> EX) ──
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            operator_lsu_ff     <= '0;
            id_lsu_rs2_data_ff  <= '0;
            id_lsu_addr_ff      <= '0;
            id_lsu_addr_is_dtcm_ff <= 1'b0;
            id_lsu_store_data_ff <= '0;
            id_lsu_store_mask_ff <= 4'b0000;
            bt_a_operand_ff     <= '0;
            bt_b_operand_ff     <= '0;
            rf_waddr_rd_ff      <= '0;
            rf_wen_rd_ff        <= '0;
            instr_addr_ff       <= '0;
            ex_jalr_ff          <= 1'b0;
            ex_pred_hit_ff      <= 1'b0;
            ex_pred_taken_ff    <= 1'b0;
            ex_pred_target_ff   <= '0;
            ex_pred_counter_ff  <= 2'b01;
            ex_pred_bht_index_ff <= '0;
            ex_valid_ff         <= 1'b0;
            fence_i_ff          <= 1'b0;
            csr_raddr_ff        <= '0;
            csr_waddr_ff        <= '0;
            csr_op_info_ff      <= '0;
            sys_op_info_ff      <= '0;
        end else if (flush_rf_i) begin
            ex_valid_ff         <= 1'b0;
            fence_i_ff          <= 1'b0;
        end else if (bubble_rf_i) begin
            // Scoreboard/LSU/CLINT/WB bubble: clear valid to prevent re-execution in EX
            ex_valid_ff         <= 1'b0;
            fence_i_ff          <= 1'b0;
        end else if (rf_advance) begin
            operand_a_ff        <= operand_a;
            operand_b_ff        <= operand_b;
            operator_ff         <= id_rf_operator_i;
            operator_type_ff    <= id_rf_operator_type_i;
            operator_lsu_ff     <= id_rf_operator_lsu_i;
            id_lsu_rs2_data_ff  <= issue_rs2_data;
            id_lsu_addr_ff      <= issue_lsu_addr;
            id_lsu_addr_is_dtcm_ff <= issue_lsu_addr_is_dtcm;
            id_lsu_store_data_ff <= issue_lsu_store_data;
            id_lsu_store_mask_ff <= issue_lsu_store_mask;
            bt_a_operand_ff     <= bt_a_operand;
            bt_b_operand_ff     <= bt_b_operand;
            rf_waddr_rd_ff      <= id_rf_waddr_rd_i;
            rf_wen_rd_ff        <= id_rf_wen_rd_i;
            instr_addr_ff       <= id_rf_pc_i;
            ex_jalr_ff          <= id_rf_bt_a_rs_sel_i;
            ex_pred_hit_ff      <= id_rf_pred_hit_i;
            ex_pred_taken_ff    <= id_rf_pred_taken_i;
            ex_pred_target_ff   <= id_rf_pred_target_i;
            ex_pred_counter_ff  <= id_rf_pred_counter_i;
            ex_pred_bht_index_ff <= id_rf_pred_bht_index_i;
            csr_raddr_ff        <= id_rf_csr_raddr_i;
            csr_waddr_ff        <= id_rf_csr_waddr_i;
            csr_op_info_ff      <= id_rf_csr_op_info_i;
            sys_op_info_ff      <= id_rf_sys_op_info_i;

            ex_valid_ff         <= id_rf_valid_i;
            fence_i_ff          <= id_rf_valid_i & id_rf_fence_i_i;
        end
        // else: DIV stall (stall_rf=1, bubble_rf=0): retain ex_valid_ff
    end

    // ── Output assignments ──
    assign operand_a_o          = operand_a_ff;
    assign operand_b_o          = operand_b_ff;
    assign operator_o           = operator_ff;
    assign operator_type_o      = operator_type_ff;
    assign operator_lsu_o       = operator_lsu_ff;
    assign id_lsu_rs2_data_o    = id_lsu_rs2_data_ff;
    assign id_lsu_addr_o        = id_lsu_addr_ff;
    assign id_lsu_addr_is_dtcm_o = id_lsu_addr_is_dtcm_ff;
    assign id_lsu_store_data_o  = id_lsu_store_data_ff;
    assign id_lsu_store_mask_o  = id_lsu_store_mask_ff;
    assign bt_a_operand_o       = bt_a_operand_ff;
    assign bt_b_operand_o       = bt_b_operand_ff;
    assign rf_alu_rf_wen_rd_o   = rf_wen_rd_ff;
    assign rf_rf_waddr_rd_o     = rf_waddr_rd_ff;
    assign rf_csr_raddr_o       = csr_raddr_ff;
    assign rf_ex_csr_waddr_o    = csr_waddr_ff;
    assign rf_op_csr_info_o     = csr_op_info_ff;
    assign rf_op_sys_info_o     = sys_op_info_ff;
    assign rf_instr_addr_o      = instr_addr_ff;
    assign rf_ex_jalr_o         = ex_jalr_ff;
    assign rf_fence_i_o         = fence_i_ff;
    assign rf_ex_pred_hit_o     = ex_pred_hit_ff;
    assign rf_ex_pred_taken_o   = ex_pred_taken_ff;
    assign rf_ex_pred_target_o  = ex_pred_target_ff;
    assign rf_ex_pred_counter_o = ex_pred_counter_ff;
    assign rf_ex_pred_bht_index_o = ex_pred_bht_index_ff;
    assign rf_ex_valid_o        = ex_valid_ff;

    // Scoreboard interface (from input side - RF stage sees the instruction speculatively)
    assign rf_ctrl_rs1_addr_o = id_rf_raddr_rs1_i;
    assign rf_ctrl_rs2_addr_o = id_rf_raddr_rs2_i;
    assign rf_ctrl_rs1_ren_o  = id_rf_valid_i & id_rf_ren_rs1_i;
    assign rf_ctrl_rs2_ren_o  = id_rf_valid_i &
        (id_rf_ren_rs2_i | id_rf_operator_type_i[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign rf_ctrl_rd_wen_o   = id_rf_valid_i & (id_rf_waddr_rd_i != '0) &
        (id_rf_wen_rd_i | id_rf_operator_type_i[ydrasil_pkg::OPERATOR_TYPE_LOAD]);
    assign rf_ctrl_rd_addr_o  = id_rf_waddr_rd_i;
    assign rf_ctrl_lsu_req_o  = id_rf_valid_i &
        (id_rf_operator_type_i[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         id_rf_operator_type_i[ydrasil_pkg::OPERATOR_TYPE_STORE]);

endmodule
