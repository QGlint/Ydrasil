
module ydrasil_ex_block
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            flush_ex_i,

    input  wire [DATA_WIDTH-1:0]           bt_a_operand_i,
    input  wire [DATA_WIDTH-1:0]           bt_b_operand_i,

    input  wire [DATA_WIDTH-1:0]           operand_a_i,
    input  wire [DATA_WIDTH-1:0]           operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0]       operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  operator_type_i,
    input  wire                            id_ex_valid_i,
    input  wire                            id_ex_jalr_i,
    input  wire                            id_ex_pred_hit_i,
    input  wire                            id_ex_pred_taken_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_pred_target_i,
    input  wire [1:0]                      id_ex_pred_counter_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_pred_bht_index_i,
    input  wire                            id_ex_pred_l0_taken_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      id_rf_waddr_rd_i,
    input  wire                            id_alu_rf_wen_rd_i,
    input  wire [5:0]                      id_rn_pdst_i,
    input  wire                            pipe1_issue_valid_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           pipe1_operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0]       pipe1_operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  pipe1_operator_type_i,
	    input  wire                            pipe1_rf_wen_rd_i,
	    input  wire [REGS_ADDR_WIDTH-1:0]      pipe1_rf_waddr_rd_i,
	    input  wire [5:0]                      pipe1_rn_pdst_i,
	    input  wire                            pipe1_rob_valid_i,
	    input  wire [5:0]                      pipe1_rob_idx_i,
    input  wire                            interrupt_i,
    input  wire [INST_ADDR_WIDTH-1:0]      clint_ex_int_addr_i,

    input  wire [CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr_i,
    input  wire [OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_i,
    input  wire [DATA_WIDTH-1:0]           csr_ex_rdata_i,

    output wire                            ex_csr_wen_o,
    output wire [DATA_WIDTH-1:0]           ex_csr_wdata_o,
    output wire [CSR_ADDR_WIDTH-1:0]       ex_csr_waddr_o,

    output wire                            ex_branch_jump_o,
    output wire [DATA_WIDTH-1:0]           ex_branch_target_o,
    output wire                            ex_pc_redirect_o,
    output wire [DATA_WIDTH-1:0]           ex_pc_redirect_target_o,
    output wire                            ex_bp_train_valid_o,
    output wire [DATA_WIDTH-1:0]           ex_bp_train_pc_o,
    output wire                            ex_bp_train_taken_o,
    output wire [DATA_WIDTH-1:0]           ex_bp_train_target_o,
    output wire [1:0]                      ex_bp_train_counter_o,
    output wire [DATA_WIDTH-1:0]           ex_bp_train_bht_index_o,
    output wire                            ex_branch_mispredict_o,
    output wire [BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_o,

    output wire [DATA_WIDTH-1:0]           ex_lsu_result_o,

    output wire [REGS_DATA_WIDTH-1:0]      alu_result_o,
    output wire                            alu_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      alu_rf_waddr_rd_o,
    output wire [5:0]                      alu_rn_pdst_o,
    output wire [REGS_DATA_WIDTH-1:0]      pipe1_alu_result_o,
    output wire                            pipe1_alu_rf_wen_rd_o,
	    output wire [REGS_ADDR_WIDTH-1:0]      pipe1_alu_rf_waddr_rd_o,
	    output wire [5:0]                      pipe1_alu_rn_pdst_o,
	    output wire                            pipe1_alu_rob_valid_o,
	    output wire [5:0]                      pipe1_alu_rob_idx_o,
	    output wire                            pipe1_instret_inc_o,

    output wire                            mul_issue_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_issue_waddr_o,
    output wire [REGS_DATA_WIDTH-1:0]      mul_wdata_rd_o,
    output wire                            mul_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_rf_waddr_rd_o,
    output wire [5:0]                      mul_rn_pdst_o,
    output wire                            mul_result_valid_o,

    output wire                            ex_instret_inc_o,
    output wire                            ex_mul_stall_o,

    output wire                            ex_prf_wr_en_o,
    output wire [5:0]                      ex_prf_wr_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]      ex_prf_wr_data_o
`ifndef SYNTHESIS
    ,output wire                           dbg_bp_resolve_valid_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_resolve_pc_o
    ,output wire                           dbg_bp_actual_taken_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_actual_target_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_actual_next_pc_o
    ,output wire                           dbg_bp_pred_hit_o
    ,output wire                           dbg_bp_pred_taken_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_pred_target_o
    ,output wire [1:0]                     dbg_bp_pred_counter_o
    ,output wire                           dbg_bp_pred_l0_taken_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_pred_next_pc_o
    ,output wire                           dbg_bp_mispredict_o
`endif
);

    wire [31:0] bt_alu_result;
    wire [REGS_DATA_WIDTH-1:0] alu_result;
    wire                       alu_rf_wen_rd;
    wire [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd;

    wire op_m_unit;
    wire op_bitmanip;
    wire op_load;
    wire op_store;
    wire op_bjp;
    wire op_mul;
    wire op_div;

    wire div_start;
    wire div_busy;
    wire div_done;
    wire [REGS_DATA_WIDTH-1:0] div_result;

    wire mul_issue_ready;
    wire mul_issue_valid;
    wire mul_issue_wen;
    wire mul_result_valid;

    wire [REGS_DATA_WIDTH-1:0] bitmanip_result;
    wire                       bitmanip_rf_wen_rd;
    wire                       normal_alu_rf_wen_rd;
    wire                       div_rf_wen_rd;
    wire                       ex_rf_wen_rd;

    wire ex_is_branch;
    wire ex_is_jump;
    wire ex_branch_taken;
    wire ex_pred_taken;
    wire [DATA_WIDTH-1:0] ex_branch_pc;
    wire [DATA_WIDTH-1:0] ex_branch_next_pc;
    wire [DATA_WIDTH-1:0] ex_branch_actual_next_pc;
    wire [DATA_WIDTH-1:0] ex_branch_pred_next_pc;
    wire [DATA_WIDTH-1:0] ex_jump_target;
    wire ex_branch_mispredict;
    wire ex_branch_jump;
    wire ex_pc_redirect;
    wire [DATA_WIDTH-1:0] ex_pc_redirect_target;
    wire ex_bp_train_valid;

    reg                       ex2_branch_jump_q;
    reg [DATA_WIDTH-1:0]      ex2_branch_target_q;
    reg                       ex2_pc_redirect_q;
    reg [DATA_WIDTH-1:0]      ex2_pc_redirect_target_q;
    reg                       ex2_bp_train_valid_q;
    reg [DATA_WIDTH-1:0]      ex2_bp_train_pc_q;
    reg                       ex2_bp_train_taken_q;
    reg [DATA_WIDTH-1:0]      ex2_bp_train_target_q;
    reg [1:0]                 ex2_bp_train_counter_q;
    reg [DATA_WIDTH-1:0]      ex2_bp_train_bht_index_q;
    reg                       ex2_branch_mispredict_q;
`ifndef SYNTHESIS
    reg                       dbg_bp_resolve_valid_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_resolve_pc_q;
    reg                       dbg_bp_actual_taken_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_actual_target_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_actual_next_pc_q;
    reg                       dbg_bp_pred_hit_q;
    reg                       dbg_bp_pred_taken_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_pred_target_q;
    reg [1:0]                 dbg_bp_pred_counter_q;
    reg                       dbg_bp_pred_l0_taken_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_pred_next_pc_q;
    reg                       dbg_bp_mispredict_q;
`endif

    reg [REGS_DATA_WIDTH-1:0] alu_result_ff;
    reg                       alu_rf_wen_rd_ff;
    reg [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd_ff;
    reg [5:0]                 alu_rn_pdst_ff;
    reg [REGS_DATA_WIDTH-1:0] pipe1_alu_result_ff;
    reg                       pipe1_alu_rf_wen_rd_ff;
	    reg [REGS_ADDR_WIDTH-1:0] pipe1_alu_rf_waddr_rd_ff;
	    reg [5:0]                 pipe1_alu_rn_pdst_ff;
	    reg                       pipe1_alu_rob_valid_ff;
	    reg [5:0]                 pipe1_alu_rob_idx_ff;
	    reg                       pipe1_instret_inc_ff;

    wire [31:0] operand_a;
    wire [31:0] operand_b;
    wire [31:0] bt_a_operand;
    wire [31:0] bt_b_operand;

    assign bt_a_operand = bt_a_operand_i;
    assign bt_b_operand = bt_b_operand_i;

    assign operand_a = operand_a_i;
    assign operand_b = operand_b_i;

    assign bt_alu_result = bt_a_operand + bt_b_operand;
    assign ex_lsu_mem_addr_o = fast_add_result;
    assign ex_lsu_result_o = alu_result_ff;

    assign ex_jump_target = id_ex_jalr_i ? {bt_alu_result[DATA_WIDTH-1:1], 1'b0} : bt_alu_result;
    assign ex_branch_pc = bt_a_operand;
    assign ex_branch_next_pc = ex_branch_pc + 32'd4;

    assign ex_is_jump = id_ex_valid_i & operator_type_i[OPERATOR_TYPE_BJP] & operator_i[OP_BJP_JUMP];
    assign ex_is_branch =
        id_ex_valid_i & operator_type_i[OPERATOR_TYPE_BJP] &
        (operator_i[OP_BJP_BEQ]  |
         operator_i[OP_BJP_BNE]  |
         operator_i[OP_BJP_BLT]  |
         operator_i[OP_BJP_BGE]  |
         operator_i[OP_BJP_BLTU] |
         operator_i[OP_BJP_BGEU]);
    assign ex_branch_taken = ex_is_branch & ex_branch_jump & !interrupt_i;
    assign ex_pred_taken = id_ex_pred_hit_i & id_ex_pred_taken_i;
    assign ex_branch_actual_next_pc = ex_branch_taken ? bt_alu_result : ex_branch_next_pc;
    assign ex_branch_pred_next_pc = ex_pred_taken ? id_ex_pred_target_i : ex_branch_next_pc;
    assign ex_branch_mispredict =
        ex_is_branch & !interrupt_i & (ex_branch_actual_next_pc != ex_branch_pred_next_pc);

    assign ex_pc_redirect =
        interrupt_i | (ex_is_jump & ex_branch_jump & !interrupt_i) | ex_branch_mispredict;
    assign ex_pc_redirect_target =
        interrupt_i ? clint_ex_int_addr_i :
        (ex_is_jump & ex_branch_jump) ? ex_jump_target :
                                        ex_branch_actual_next_pc;
    assign ex_bp_train_valid = ex_is_branch & !interrupt_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex2_branch_jump_q <= 1'b0;
            ex2_branch_target_q <= '0;
            ex2_pc_redirect_q <= 1'b0;
            ex2_pc_redirect_target_q <= '0;
            ex2_bp_train_valid_q <= 1'b0;
            ex2_bp_train_pc_q <= '0;
            ex2_bp_train_taken_q <= 1'b0;
            ex2_bp_train_target_q <= '0;
            ex2_bp_train_counter_q <= 2'b01;
            ex2_bp_train_bht_index_q <= '0;
            ex2_branch_mispredict_q <= 1'b0;
`ifndef SYNTHESIS
            dbg_bp_resolve_valid_q <= 1'b0;
            dbg_bp_resolve_pc_q <= '0;
            dbg_bp_actual_taken_q <= 1'b0;
            dbg_bp_actual_target_q <= '0;
            dbg_bp_actual_next_pc_q <= '0;
            dbg_bp_pred_hit_q <= 1'b0;
            dbg_bp_pred_taken_q <= 1'b0;
            dbg_bp_pred_target_q <= '0;
            dbg_bp_pred_counter_q <= 2'b01;
            dbg_bp_pred_l0_taken_q <= 1'b0;
            dbg_bp_pred_next_pc_q <= '0;
            dbg_bp_mispredict_q <= 1'b0;
`endif
        end else if (flush_ex_i) begin
            ex2_branch_jump_q <= 1'b0;
            ex2_branch_target_q <= '0;
            ex2_pc_redirect_q <= 1'b0;
            ex2_pc_redirect_target_q <= '0;
            ex2_bp_train_valid_q <= 1'b0;
            ex2_bp_train_pc_q <= '0;
            ex2_bp_train_taken_q <= 1'b0;
            ex2_bp_train_target_q <= '0;
            ex2_bp_train_counter_q <= 2'b01;
            ex2_bp_train_bht_index_q <= '0;
            ex2_branch_mispredict_q <= 1'b0;
`ifndef SYNTHESIS
            dbg_bp_resolve_valid_q <= 1'b0;
            dbg_bp_resolve_pc_q <= '0;
            dbg_bp_actual_taken_q <= 1'b0;
            dbg_bp_actual_target_q <= '0;
            dbg_bp_actual_next_pc_q <= '0;
            dbg_bp_pred_hit_q <= 1'b0;
            dbg_bp_pred_taken_q <= 1'b0;
            dbg_bp_pred_target_q <= '0;
            dbg_bp_pred_counter_q <= 2'b01;
            dbg_bp_pred_l0_taken_q <= 1'b0;
            dbg_bp_pred_next_pc_q <= '0;
            dbg_bp_mispredict_q <= 1'b0;
`endif
        end else begin
            ex2_branch_jump_q <= ex_branch_jump | interrupt_i;
            ex2_branch_target_q <= interrupt_i ? clint_ex_int_addr_i : ex_jump_target;
            ex2_pc_redirect_q <= ex_pc_redirect;
            ex2_pc_redirect_target_q <= ex_pc_redirect_target;
            ex2_bp_train_valid_q <= ex_bp_train_valid;
            ex2_bp_train_pc_q <= ex_branch_pc;
            ex2_bp_train_taken_q <= ex_branch_taken;
            ex2_bp_train_target_q <= bt_alu_result;
            ex2_bp_train_counter_q <= id_ex_pred_counter_i;
            ex2_bp_train_bht_index_q <= id_ex_pred_bht_index_i;
            ex2_branch_mispredict_q <= ex_branch_mispredict;
`ifndef SYNTHESIS
            dbg_bp_resolve_valid_q <= ex_bp_train_valid;
            dbg_bp_resolve_pc_q <= ex_branch_pc;
            dbg_bp_actual_taken_q <= ex_branch_taken;
            dbg_bp_actual_target_q <= bt_alu_result;
            dbg_bp_actual_next_pc_q <= ex_branch_actual_next_pc;
            dbg_bp_pred_hit_q <= id_ex_pred_hit_i;
            dbg_bp_pred_taken_q <= id_ex_pred_taken_i;
            dbg_bp_pred_target_q <= id_ex_pred_target_i;
            dbg_bp_pred_counter_q <= id_ex_pred_counter_i;
            dbg_bp_pred_l0_taken_q <= id_ex_pred_l0_taken_i;
            dbg_bp_pred_next_pc_q <= ex_branch_pred_next_pc;
            dbg_bp_mispredict_q <= ex_branch_mispredict;
`endif
        end
    end

    assign ex_branch_jump_o = ex2_branch_jump_q;
    assign ex_branch_target_o = ex2_branch_target_q;
    assign ex_branch_mispredict_o = ex2_branch_mispredict_q;
    assign ex_pc_redirect_o = ex2_pc_redirect_q;
    assign ex_pc_redirect_target_o = ex2_pc_redirect_target_q;
    assign ex_bp_train_valid_o = ex2_bp_train_valid_q;
    assign ex_bp_train_pc_o = ex2_bp_train_pc_q;
    assign ex_bp_train_taken_o = ex2_bp_train_taken_q;
    assign ex_bp_train_target_o = ex2_bp_train_target_q;
    assign ex_bp_train_counter_o = ex2_bp_train_counter_q;
    assign ex_bp_train_bht_index_o = ex2_bp_train_bht_index_q;
`ifndef SYNTHESIS
    assign dbg_bp_resolve_valid_o = dbg_bp_resolve_valid_q;
    assign dbg_bp_resolve_pc_o = dbg_bp_resolve_pc_q;
    assign dbg_bp_actual_taken_o = dbg_bp_actual_taken_q;
    assign dbg_bp_actual_target_o = dbg_bp_actual_target_q;
    assign dbg_bp_actual_next_pc_o = dbg_bp_actual_next_pc_q;
    assign dbg_bp_pred_hit_o = dbg_bp_pred_hit_q;
    assign dbg_bp_pred_taken_o = dbg_bp_pred_taken_q;
    assign dbg_bp_pred_target_o = dbg_bp_pred_target_q;
    assign dbg_bp_pred_counter_o = dbg_bp_pred_counter_q;
    assign dbg_bp_pred_l0_taken_o = dbg_bp_pred_l0_taken_q;
    assign dbg_bp_pred_next_pc_o = dbg_bp_pred_next_pc_q;
    assign dbg_bp_mispredict_o = dbg_bp_mispredict_q;
`endif

    assign op_m_unit = operator_type_i[OPERATOR_TYPE_MUL];
    assign op_bitmanip = operator_type_i[OPERATOR_TYPE_BITMANIP];
    assign op_load = operator_type_i[OPERATOR_TYPE_LOAD];
    assign op_store = operator_type_i[OPERATOR_TYPE_STORE];
    assign op_bjp = operator_type_i[OPERATOR_TYPE_BJP];
    assign op_mul =
        op_m_unit &
        (operator_i[OP_MUL_MUL]    |
         operator_i[OP_MUL_MULH]   |
         operator_i[OP_MUL_MULHSU] |
         operator_i[OP_MUL_MULHU]);
    assign op_div =
        op_m_unit &
        (operator_i[OP_MUL_DIV]  |
         operator_i[OP_MUL_DIVU] |
         operator_i[OP_MUL_REM]  |
         operator_i[OP_MUL_REMU]);

    assign mul_issue_valid = id_ex_valid_i & op_mul & mul_issue_ready & !interrupt_i & !flush_ex_i;
    assign mul_issue_wen = id_alu_rf_wen_rd_i & (id_rf_waddr_rd_i != '0);
    assign mul_issue_o = mul_issue_valid & mul_issue_wen;
    assign mul_issue_waddr_o = id_rf_waddr_rd_i;

    assign div_start = id_ex_valid_i & op_div & !div_busy & !div_done & !interrupt_i & !flush_ex_i;
    assign div_rf_wen_rd = id_ex_valid_i & op_div & div_done & id_alu_rf_wen_rd_i & !interrupt_i & !flush_ex_i;
    assign ex_mul_stall_o = id_ex_valid_i & op_div & !div_done & !flush_ex_i;

    assign bitmanip_rf_wen_rd = id_ex_valid_i & op_bitmanip & id_alu_rf_wen_rd_i & !interrupt_i & !flush_ex_i;
    assign normal_alu_rf_wen_rd = id_ex_valid_i & alu_rf_wen_rd & !op_m_unit & !op_bitmanip & !flush_ex_i;
    assign ex_rf_wen_rd = div_rf_wen_rd | bitmanip_rf_wen_rd | normal_alu_rf_wen_rd | csr_wen;
    assign mul_result_valid_o = mul_result_valid;
    assign ex_instret_inc_o =
        (id_ex_valid_i & !interrupt_i & !flush_ex_i & !op_load & !op_mul & !op_div) |
        (id_ex_valid_i & !interrupt_i & !flush_ex_i & op_div & div_done);

    wire fast_alu_op =
        operator_type_i[OPERATOR_TYPE_ALU] & !op_m_unit & !op_bitmanip &
        (operator_i[OP_ALU_ADD]  |
         operator_i[OP_ALU_SUB]  |
         operator_i[OP_ALU_SLT]  |
         operator_i[OP_ALU_SLTU] |
         operator_i[OP_ALU_XOR]  |
         operator_i[OP_ALU_OR]   |
         operator_i[OP_ALU_AND]  |
         operator_i[OP_ALU_LUI]  |
         operator_i[OP_ALU_AUIPC]);
    wire fast_result_wen = id_ex_valid_i & !interrupt_i & !flush_ex_i & !op_bitmanip & !op_m_unit &
        (fast_alu_op | op_load | op_store | op_bjp);
    wire [31:0] fast_add_result = operand_a + operand_b;
    wire [32:0] fast_sub_result_ext = {1'b0, operand_a} + {1'b0, ~operand_b} + 33'd1;
    wire        fast_signs_differ = operand_a[31] ^ operand_b[31];
    wire        fast_slt_signed = fast_signs_differ ? operand_a[31] : fast_sub_result_ext[31];
    wire        fast_slt_unsigned = ~fast_sub_result_ext[32];
    wire [31:0] fast_logic_result =
        ({32{operator_i[OP_ALU_XOR]}} & (operand_a ^ operand_b)) |
        ({32{operator_i[OP_ALU_OR]}}  & (operand_a | operand_b)) |
        ({32{operator_i[OP_ALU_AND]}} & (operand_a & operand_b));
    wire [31:0] fast_alu_result =
        ({32{operator_i[OP_ALU_SUB]}}  & fast_sub_result_ext[31:0]) |
        ({32{operator_i[OP_ALU_SLT]}}  & {31'b0, fast_slt_signed}) |
        ({32{operator_i[OP_ALU_SLTU]}} & {31'b0, fast_slt_unsigned}) |
        ({32{operator_i[OP_ALU_XOR] | operator_i[OP_ALU_OR] | operator_i[OP_ALU_AND]}} & fast_logic_result) |
        ({32{operator_i[OP_ALU_LUI]}}  & operand_b) |
        ({32{operator_i[OP_ALU_ADD] | operator_i[OP_ALU_AUIPC]}} & fast_add_result);
    wire [31:0] fast_result =
        fast_alu_op ? fast_alu_result : fast_add_result;

    wire [31:0] pipe1_alu_result;
    wire [31:0] pipe1_bitmanip_result;
    wire        pipe1_alu_comp_unused;
    wire        pipe1_alu_wen_unused;
    wire [REGS_ADDR_WIDTH-1:0] pipe1_alu_waddr_unused;

    ydrasil_alu #(
        .DATAWIDTH(DATA_WIDTH)
    ) u_ydrasil_alu (
        .operand_a_i          (operand_a),
        .operand_b_i          (operand_b),
        .operator_i           (operator_i),
        .operator_type_i      (operator_type_i),
        .interrupt_i          (interrupt_i),
        .id_rf_waddr_rd_i     (id_rf_waddr_rd_i),
        .id_alu_rf_wen_rd_i   (id_alu_rf_wen_rd_i),
        .comp_result_o        (ex_branch_jump),
        .alu_result_o         (alu_result),
        .alu_rf_wen_rd_o      (alu_rf_wen_rd),
        .alu_rf_waddr_rd_o    (alu_rf_waddr_rd)
    );

    ydrasil_alu #(
        .DATAWIDTH(DATA_WIDTH)
    ) u_ydrasil_pipe1_alu (
        .operand_a_i          (pipe1_operand_a_i),
        .operand_b_i          (pipe1_operand_b_i),
        .operator_i           (pipe1_operator_i),
        .operator_type_i      (pipe1_operator_type_i),
        .interrupt_i          (interrupt_i),
        .id_rf_waddr_rd_i     (pipe1_rf_waddr_rd_i),
        .id_alu_rf_wen_rd_i   (pipe1_rf_wen_rd_i),
        .comp_result_o        (pipe1_alu_comp_unused),
        .alu_result_o         (pipe1_alu_result),
        .alu_rf_wen_rd_o      (pipe1_alu_wen_unused),
        .alu_rf_waddr_rd_o    (pipe1_alu_waddr_unused)
    );

    ydrasil_bitmanip u_ydrasil_pipe1_bitmanip (
        .operand_a_i     (pipe1_operand_a_i),
        .operand_b_i     (pipe1_operand_b_i),
        .operator_i      (pipe1_operator_i),
        .operator_type_i (pipe1_operator_type_i),
        .result_o        (pipe1_bitmanip_result)
    );

    ydrasil_div u_ydrasil_div (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (flush_ex_i | interrupt_i),
        .start_i         (div_start),
        .operand_a_i     (operand_a),
        .operand_b_i     (operand_b),
        .operator_i      (operator_i),
        .busy_o          (div_busy),
        .done_o          (div_done),
        .result_o        (div_result)
    );

    ydrasil_mul u_ydrasil_mul (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (interrupt_i),
        .issue_valid_i   (mul_issue_valid),
        .issue_ready_o   (mul_issue_ready),
        .operand_a_i     (operand_a),
        .operand_b_i     (operand_b),
        .operator_i      (operator_i),
        .issue_wen_i     (mul_issue_wen),
        .issue_waddr_i   (id_rf_waddr_rd_i),
        .issue_pdst_i    (id_rn_pdst_i),
        .result_valid_o  (mul_result_valid),
        .result_wen_o    (mul_rf_wen_rd_o),
        .result_waddr_o  (mul_rf_waddr_rd_o),
        .result_pdst_o   (mul_rn_pdst_o),
        .result_wdata_o  (mul_wdata_rd_o)
    );

    ydrasil_bitmanip u_ydrasil_bitmanip (
        .operand_a_i     (operand_a),
        .operand_b_i     (operand_b),
        .operator_i      (operator_i),
        .operator_type_i (operator_type_i),
        .result_o        (bitmanip_result)
    );

    wire [31:0] slow_result;
    wire        slow_result_wen;
    wire csr_wen;
    wire op_csr = id_ex_valid_i & operator_type_i[OPERATOR_TYPE_CSR] & !interrupt_i & !flush_ex_i;
    wire csr_csrrw = op_csr & id_op_csr_info_i[OP_CSR_CSRRW];
    wire csr_csrrs = op_csr & id_op_csr_info_i[OP_CSR_CSRRS];
    wire csr_csrrc = op_csr & id_op_csr_info_i[OP_CSR_CSRRC];
    wire [31:0] csr_reg_wdata;
    wire [31:0] csr_wdata;

    reg [REGS_DATA_WIDTH-1:0] ex_csr_wdata_o_ff;
    reg                       ex_csr_wen_o_ff;
    reg [CSR_ADDR_WIDTH-1:0]  ex_csr_waddr_o_ff;

    assign csr_reg_wdata = interrupt_i ? '0 : csr_ex_rdata_i;
    assign csr_wdata =
        interrupt_i ? '0 :
        ({REGS_DATA_WIDTH{csr_csrrw}} & operand_a) |
        ({REGS_DATA_WIDTH{csr_csrrs}} & (operand_a | csr_ex_rdata_i)) |
        ({REGS_DATA_WIDTH{csr_csrrc}} & (csr_ex_rdata_i & (~operand_a)));
    assign csr_wen = op_csr;

    assign alu_result_o = alu_result_ff;
    assign alu_rf_wen_rd_o = alu_rf_wen_rd_ff;
    assign alu_rf_waddr_rd_o = alu_rf_waddr_rd_ff;
    assign alu_rn_pdst_o = alu_rn_pdst_ff;
    assign pipe1_alu_result_o = pipe1_alu_result_ff;
	    assign pipe1_alu_rf_wen_rd_o = pipe1_alu_rf_wen_rd_ff;
	    assign pipe1_alu_rf_waddr_rd_o = pipe1_alu_rf_waddr_rd_ff;
	    assign pipe1_alu_rn_pdst_o = pipe1_alu_rn_pdst_ff;
	    assign pipe1_alu_rob_valid_o = pipe1_alu_rob_valid_ff;
	    assign pipe1_alu_rob_idx_o = pipe1_alu_rob_idx_ff;
	    assign pipe1_instret_inc_o = pipe1_instret_inc_ff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_ff       <= '0;
            alu_rf_wen_rd_ff    <= 1'b0;
            alu_rf_waddr_rd_ff  <= '0;
            alu_rn_pdst_ff      <= '0;
            pipe1_alu_result_ff <= '0;
	            pipe1_alu_rf_wen_rd_ff <= 1'b0;
	            pipe1_alu_rf_waddr_rd_ff <= '0;
	            pipe1_alu_rn_pdst_ff <= '0;
	            pipe1_alu_rob_valid_ff <= 1'b0;
	            pipe1_alu_rob_idx_ff <= '0;
	            pipe1_instret_inc_ff <= 1'b0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
        end else if (flush_ex_i) begin
            alu_result_ff       <= '0;
            alu_rf_wen_rd_ff    <= 1'b0;
            alu_rf_waddr_rd_ff  <= '0;
            alu_rn_pdst_ff      <= '0;
            pipe1_alu_result_ff <= '0;
	            pipe1_alu_rf_wen_rd_ff <= 1'b0;
	            pipe1_alu_rf_waddr_rd_ff <= '0;
	            pipe1_alu_rn_pdst_ff <= '0;
	            pipe1_alu_rob_valid_ff <= 1'b0;
	            pipe1_alu_rob_idx_ff <= '0;
	            pipe1_instret_inc_ff <= 1'b0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
        end else begin
            alu_result_ff      <= fast_result_wen ? fast_result :
                                  slow_result_wen ? slow_result :
                                  ex_is_jump ? fast_add_result : alu_result;
            alu_rf_wen_rd_ff   <= ex_rf_wen_rd;
            alu_rf_waddr_rd_ff <= div_rf_wen_rd ? id_rf_waddr_rd_i : alu_rf_waddr_rd;
            alu_rn_pdst_ff     <= id_rn_pdst_i;
            pipe1_alu_result_ff <=
                pipe1_operator_type_i[OPERATOR_TYPE_BITMANIP] ?
                pipe1_bitmanip_result : pipe1_alu_result;
            pipe1_alu_rf_wen_rd_ff <=
                pipe1_issue_valid_i & pipe1_rf_wen_rd_i &
                (pipe1_rf_waddr_rd_i != '0) & !interrupt_i & !flush_ex_i;
	            pipe1_alu_rf_waddr_rd_ff <= pipe1_rf_waddr_rd_i;
	            pipe1_alu_rn_pdst_ff <= pipe1_rn_pdst_i;
	            pipe1_alu_rob_valid_ff <= pipe1_issue_valid_i & pipe1_rob_valid_i & !interrupt_i & !flush_ex_i;
	            pipe1_alu_rob_idx_ff <= pipe1_rob_idx_i;
	            pipe1_instret_inc_ff <= pipe1_issue_valid_i & !interrupt_i & !flush_ex_i;
            ex_csr_wdata_o_ff  <= csr_wdata;
            ex_csr_wen_o_ff    <= csr_wen;
            ex_csr_waddr_o_ff  <= id_ex_csr_waddr_i;
        end
    end

    assign ex_csr_wdata_o = ex_csr_wdata_o_ff;
    assign ex_csr_wen_o = ex_csr_wen_o_ff;
    assign ex_csr_waddr_o = ex_csr_waddr_o_ff;
    assign slow_result_wen = div_rf_wen_rd | bitmanip_rf_wen_rd | csr_wen;
    assign slow_result =
        ({32{div_rf_wen_rd}}        & div_result) |
        ({32{bitmanip_rf_wen_rd}}   & bitmanip_result) |
        ({32{csr_wen}}              & csr_reg_wdata);

    assign ex_prf_wr_en_o = 1'b0; // TEMP DISABLED: normal_alu_rf_wen_rd & id_alu_rf_wen_rd_i;
    assign ex_prf_wr_addr_o = id_rn_pdst_i;
    assign ex_prf_wr_data_o = ex_is_jump ? fast_add_result : alu_result;

endmodule
