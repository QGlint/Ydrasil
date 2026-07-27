
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
    input  wire [DATA_WIDTH-1:0]           alu_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           alu_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           bru_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           bru_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           lsu_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           lsu_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           lsu_store_data_i,
    input  wire [DATA_WIDTH-1:0]           mul_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           mul_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           csr_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           csr_operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0]       operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  operator_type_i,
    input  wire                            id_ex_valid_i,
    input  wire                            id_ex_jalr_i,
    input  wire                            id_ex_alu_bypass_rs1_i,
    input  wire                            id_ex_alu_bypass_rs2_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_branch_target_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_branch_next_pc_i,
    input  wire                            id_ex_branch_eq_i,
    input  wire                            id_ex_branch_ge_signed_i,
    input  wire                            id_ex_branch_ge_unsigned_i,
    input  wire                            id_ex_pred_hit_i,
    input  wire                            id_ex_pred_taken_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_pred_target_i,
    input  wire [1:0]                      id_ex_pred_counter_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_pred_bht_index_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      id_rf_waddr_rd_i,
    input  wire                            id_alu_rf_wen_rd_i,
    input  producer_id_t                   id_ex_producer_id_i,
    input  wire                            trap_redirect_i,
    input  wire [INST_ADDR_WIDTH-1:0]      trap_redirect_addr_i,

    input  wire [CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr_i,
    input  wire [OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_i,
    input  wire [DATA_WIDTH-1:0]           csr_ex_rdata_i,

    output wire                            ex_csr_wen_o,
    output wire [DATA_WIDTH-1:0]           ex_csr_wdata_o,
    output wire [1:0]                      ex_csr_fs_wdata_o,
    output wire                            ex_csr_mstatus_wen_o,
    output wire [CSR_ADDR_WIDTH-1:0]       ex_csr_waddr_o,

    output wire                            ex_branch_jump_o,
    output wire [DATA_WIDTH-1:0]           ex_branch_target_o,
    output wire                            ex_pc_redirect_o,
    output wire [DATA_WIDTH-1:0]           ex_pc_redirect_target_o,
    output ydrasil_bp_train_pkt_t          ex_bp_train_o,
    output wire                            ex_branch_mispredict_o,
    output wire [BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_o,

    output wire [DATA_WIDTH-1:0]           ex_lsu_result_o,

    output wire [REGS_DATA_WIDTH-1:0]      alu_result_o,
    output wire                            alu_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      alu_rf_waddr_rd_o,
    output producer_id_t                   alu_producer_id_o,
    output ydrasil_gpr_fwd_pkt_t           completion_o,

    output wire                            mul_issue_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_issue_waddr_o,
    output wire [REGS_DATA_WIDTH-1:0]      mul_wdata_rd_o,
    output wire                            mul_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_rf_waddr_rd_o,
    output producer_id_t                   mul_producer_id_o,
    output wire                            mul_result_valid_o,

    output wire                            ex_instret_inc_o,
    output wire                            ex_mul_stall_o
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
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_pred_next_pc_o
    ,output wire                           dbg_bp_mispredict_o
`endif
);

    wire [REGS_DATA_WIDTH-1:0] alu_result;
    wire                       alu_rf_wen_rd;
    wire [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd;
    wire                       alu_comp_result;

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
    wire                       div_complete;
    wire                       ex_rf_wen_rd;
    wire                       csr_wen;
    reg                        div_active_q;
    reg                        div_wen_q;
    reg [REGS_ADDR_WIDTH-1:0]  div_waddr_q;

    reg [REGS_DATA_WIDTH-1:0] alu_result_ff;
    reg [REGS_DATA_WIDTH-1:0] bitmanip_result_ff;
    reg                       bitmanip_result_valid_ff;
    reg                       alu_rf_wen_rd_ff;
    producer_id_t             alu_producer_id_ff;
    (* max_fanout = 8 *) reg [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd_ff;
    reg                       alu_bypass_valid_q;
    reg [REGS_DATA_WIDTH-1:0] alu_bypass_data_q;

    wire [31:0] operand_a;
    wire [31:0] operand_b;
    wire [31:0] bitmanip_operand_a;
    wire [31:0] bitmanip_operand_b;
    wire [31:0] bru_operand_a;
    wire [31:0] bru_operand_b;
    wire [31:0] lsu_operand_b;
    wire [31:0] lsu_store_data;
    wire [31:0] mul_operand_a;
    wire [31:0] mul_operand_b;
    wire [31:0] csr_operand_a;
    wire [31:0] bt_a_operand;
    wire [31:0] bt_b_operand;
    wire [31:0] fast_add_result;
    wire [31:0] lsu_fast_add_result;
    wire [31:0] lsu_base_add_result;
    wire [31:0] lsu_bypass_add_result;
    wire        lsu_addr_alu_bypass;

	assign bt_a_operand =
		(id_ex_jalr_i & id_ex_alu_bypass_rs1_i & alu_bypass_valid_q) ?
        alu_bypass_data_q : bt_a_operand_i;
    assign bt_b_operand = bt_b_operand_i;

    // JALR uses rs1 only for the BRU target. Its architectural rd value is
    // always PC+4, so the ALU link operand must remain the registered PC.
	assign operand_a = id_ex_jalr_i ? alu_operand_a_i :
		(id_ex_alu_bypass_rs1_i & alu_bypass_valid_q) ? alu_bypass_data_q : alu_operand_a_i;
	assign operand_b = (id_ex_alu_bypass_rs2_i & alu_bypass_valid_q) ?
		alu_bypass_data_q : alu_operand_b_i;
    assign bitmanip_operand_a = alu_operand_a_i;
    assign bitmanip_operand_b = alu_operand_b_i;
	assign bru_operand_a = (id_ex_alu_bypass_rs1_i & alu_bypass_valid_q) ?
		alu_bypass_data_q : bru_operand_a_i;
	assign bru_operand_b = (id_ex_alu_bypass_rs2_i & alu_bypass_valid_q) ?
		alu_bypass_data_q : bru_operand_b_i;
    // LSU consumers are held by the scoreboard until load data is registered.
    // Keep branch/ALU load replay out of the otherwise inactive AGU cone.
    assign lsu_addr_alu_bypass =
        id_ex_alu_bypass_rs1_i & alu_bypass_valid_q;
    assign lsu_operand_b = lsu_operand_b_i;
    assign lsu_store_data =
        (id_ex_alu_bypass_rs2_i & alu_bypass_valid_q) ?
        alu_bypass_data_q : lsu_store_data_i;
    assign mul_operand_a = (id_ex_alu_bypass_rs1_i & alu_bypass_valid_q) ? alu_bypass_data_q : mul_operand_a_i;
    assign mul_operand_b = (id_ex_alu_bypass_rs2_i & alu_bypass_valid_q) ? alu_bypass_data_q : mul_operand_b_i;
    assign csr_operand_a = (id_ex_alu_bypass_rs1_i & alu_bypass_valid_q) ? alu_bypass_data_q : csr_operand_a_i;

    // Put the bypass select after the carry chains.  Both adder inputs are
    // registered, and the selected result is architecturally identical to a
    // mux in front of one adder, without placing bypass-valid on the carry path.
    assign lsu_base_add_result = lsu_operand_a_i + lsu_operand_b;
    assign lsu_bypass_add_result = alu_bypass_data_q + lsu_operand_b;
    assign lsu_fast_add_result = lsu_addr_alu_bypass ?
        lsu_bypass_add_result : lsu_base_add_result;
    assign ex_lsu_mem_addr_o = lsu_fast_add_result;
    assign ex_lsu_result_o = lsu_store_data;

    ydrasil_bru #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_bru (
        .clk                         (clk),
        .rst_n                       (rst_n),
        .flush_i                     (flush_ex_i),
        .operand_a_i                 (bru_operand_a),
        .operand_b_i                 (bru_operand_b),
        .bt_a_operand_i              (bt_a_operand),
        .bt_b_operand_i              (bt_b_operand),
        .operator_i                  (operator_i),
        .operator_type_i             (operator_type_i),
        .id_ex_valid_i               (id_ex_valid_i),
        .id_ex_jalr_i                (id_ex_jalr_i),
        .id_ex_alu_bypass_rs1_i      (id_ex_alu_bypass_rs1_i),
        .id_ex_alu_bypass_rs2_i      (id_ex_alu_bypass_rs2_i),
        .id_ex_branch_target_i       (id_ex_branch_target_i),
        .id_ex_branch_next_pc_i      (id_ex_branch_next_pc_i),
        .id_ex_branch_eq_i           (id_ex_branch_eq_i),
        .id_ex_branch_ge_signed_i    (id_ex_branch_ge_signed_i),
        .id_ex_branch_ge_unsigned_i  (id_ex_branch_ge_unsigned_i),
        .id_ex_pred_hit_i            (id_ex_pred_hit_i),
        .id_ex_pred_taken_i          (id_ex_pred_taken_i),
        .id_ex_pred_target_i         (id_ex_pred_target_i),
        .id_ex_pred_counter_i        (id_ex_pred_counter_i),
        .id_ex_pred_bht_index_i      (id_ex_pred_bht_index_i),
        .trap_redirect_i             (trap_redirect_i),
        .trap_redirect_addr_i        (trap_redirect_addr_i),
        .ex_branch_jump_o            (ex_branch_jump_o),
        .ex_branch_target_o          (ex_branch_target_o),
        .ex_pc_redirect_o            (ex_pc_redirect_o),
        .ex_pc_redirect_target_o     (ex_pc_redirect_target_o),
        .ex_bp_train_o               (ex_bp_train_o),
        .ex_branch_mispredict_o      (ex_branch_mispredict_o)
`ifndef SYNTHESIS
        ,.dbg_bp_resolve_valid_o     (dbg_bp_resolve_valid_o)
        ,.dbg_bp_resolve_pc_o        (dbg_bp_resolve_pc_o)
        ,.dbg_bp_actual_taken_o      (dbg_bp_actual_taken_o)
        ,.dbg_bp_actual_target_o     (dbg_bp_actual_target_o)
        ,.dbg_bp_actual_next_pc_o    (dbg_bp_actual_next_pc_o)
        ,.dbg_bp_pred_hit_o          (dbg_bp_pred_hit_o)
        ,.dbg_bp_pred_taken_o        (dbg_bp_pred_taken_o)
        ,.dbg_bp_pred_target_o       (dbg_bp_pred_target_o)
        ,.dbg_bp_pred_counter_o      (dbg_bp_pred_counter_o)
        ,.dbg_bp_pred_next_pc_o      (dbg_bp_pred_next_pc_o)
        ,.dbg_bp_mispredict_o        (dbg_bp_mispredict_o)
`endif
    );

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

    assign mul_issue_valid = id_ex_valid_i & op_mul & mul_issue_ready & !trap_redirect_i & !flush_ex_i;
    assign mul_issue_wen = id_alu_rf_wen_rd_i & (id_rf_waddr_rd_i != '0);
    assign mul_issue_o = mul_issue_valid & mul_issue_wen;
    assign mul_issue_waddr_o = id_rf_waddr_rd_i;

    assign div_start = id_ex_valid_i & op_div & !div_active_q & !div_busy & !div_done & !trap_redirect_i & !flush_ex_i;
    assign div_complete = div_active_q & div_done & !trap_redirect_i & !flush_ex_i;
    assign div_rf_wen_rd = div_complete & div_wen_q;
    assign ex_mul_stall_o = ((id_ex_valid_i & op_div) | div_active_q) & !div_done & !flush_ex_i;

    wire [4:0] fast_b_shamt = bitmanip_operand_b[4:0];
    wire [31:0] fast_b_mask = 32'h1 << fast_b_shamt;
    wire [31:0] fast_b_shadd_result =
        ({32{operator_i[OP_B_SH1ADD]}} &
         ((bitmanip_operand_a << 1) + bitmanip_operand_b)) |
        ({32{operator_i[OP_B_SH2ADD]}} &
         ((bitmanip_operand_a << 2) + bitmanip_operand_b)) |
        ({32{operator_i[OP_B_SH3ADD]}} &
         ((bitmanip_operand_a << 3) + bitmanip_operand_b));
    wire [31:0] fast_b_logic_result =
        ({32{operator_i[OP_B_ANDN]}} &
         (bitmanip_operand_a & ~bitmanip_operand_b)) |
        ({32{operator_i[OP_B_ORN]}} &
         (bitmanip_operand_a | ~bitmanip_operand_b)) |
        ({32{operator_i[OP_B_XNOR]}} &
         ~(bitmanip_operand_a ^ bitmanip_operand_b));
    wire [31:0] fast_b_bit_result =
        ({32{operator_i[OP_B_BCLR] | operator_i[OP_B_BCLRI]}} &
         (bitmanip_operand_a & ~fast_b_mask)) |
        ({32{operator_i[OP_B_BEXT] | operator_i[OP_B_BEXTI]}} &
         {31'b0, |(bitmanip_operand_a & fast_b_mask)}) |
        ({32{operator_i[OP_B_BINV] | operator_i[OP_B_BINVI]}} &
         (bitmanip_operand_a ^ fast_b_mask)) |
        ({32{operator_i[OP_B_BSET] | operator_i[OP_B_BSETI]}} &
         (bitmanip_operand_a | fast_b_mask));
    wire [31:0] fast_b_pack_result =
        ({32{operator_i[OP_B_PACK]}} &
         {bitmanip_operand_b[15:0], bitmanip_operand_a[15:0]}) |
        ({32{operator_i[OP_B_PACKH]}} &
         {16'b0, bitmanip_operand_b[7:0], bitmanip_operand_a[7:0]});
    wire [31:0] fast_b_extend_result =
        ({32{operator_i[OP_B_REV8]}} &
         {bitmanip_operand_a[7:0], bitmanip_operand_a[15:8],
          bitmanip_operand_a[23:16], bitmanip_operand_a[31:24]}) |
        ({32{operator_i[OP_B_SEXT_B]}} &
         {{24{bitmanip_operand_a[7]}}, bitmanip_operand_a[7:0]}) |
        ({32{operator_i[OP_B_SEXT_H]}} &
         {{16{bitmanip_operand_a[15]}}, bitmanip_operand_a[15:0]}) |
        ({32{operator_i[OP_B_ZEXT_H]}} &
         {16'b0, bitmanip_operand_a[15:0]});
    wire fast_bitmanip_op = op_bitmanip &
        (operator_i[OP_B_SH1ADD] | operator_i[OP_B_SH2ADD] | operator_i[OP_B_SH3ADD] |
         operator_i[OP_B_ANDN]   | operator_i[OP_B_ORN]    | operator_i[OP_B_XNOR]   |
         operator_i[OP_B_BCLR]   | operator_i[OP_B_BCLRI]  | operator_i[OP_B_BEXT]   |
         operator_i[OP_B_BEXTI]  | operator_i[OP_B_BINV]   | operator_i[OP_B_BINVI]  |
         operator_i[OP_B_BSET]   | operator_i[OP_B_BSETI]  | operator_i[OP_B_PACK]   |
         operator_i[OP_B_PACKH]  | operator_i[OP_B_REV8]   | operator_i[OP_B_SEXT_B] |
         operator_i[OP_B_SEXT_H] | operator_i[OP_B_ZEXT_H]);
    wire [31:0] fast_bitmanip_result =
        fast_b_shadd_result | fast_b_logic_result | fast_b_bit_result |
        fast_b_pack_result | fast_b_extend_result;
    wire fast_bitmanip_rf_wen_rd =
        id_ex_valid_i & fast_bitmanip_op & id_alu_rf_wen_rd_i & !trap_redirect_i & !flush_ex_i;

    assign bitmanip_rf_wen_rd =
        id_ex_valid_i & op_bitmanip & !fast_bitmanip_op & id_alu_rf_wen_rd_i &
        !trap_redirect_i & !flush_ex_i;
    assign normal_alu_rf_wen_rd = id_ex_valid_i & alu_rf_wen_rd &
        (operator_type_i[OPERATOR_TYPE_ALU] | operator_type_i[OPERATOR_TYPE_BJP]) &
        !op_m_unit & !op_bitmanip & !flush_ex_i;
    assign ex_rf_wen_rd =
        div_rf_wen_rd | bitmanip_rf_wen_rd | fast_bitmanip_rf_wen_rd |
        normal_alu_rf_wen_rd | op_csr;
    assign mul_result_valid_o = mul_result_valid;
    assign ex_instret_inc_o =
        (id_ex_valid_i & !trap_redirect_i & !flush_ex_i & !op_load & !op_mul & !op_div &
         !operator_type_i[OPERATOR_TYPE_FPU]) |
        div_complete;

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
    wire shift_alu_op =
        operator_type_i[OPERATOR_TYPE_ALU] & !op_m_unit & !op_bitmanip &
        (operator_i[OP_ALU_SLL] | operator_i[OP_ALU_SRL] | operator_i[OP_ALU_SRA]);
    wire bypassable_alu_op =
        id_ex_valid_i & id_alu_rf_wen_rd_i & (id_rf_waddr_rd_i != '0) &
        (fast_alu_op | shift_alu_op) & !trap_redirect_i & !flush_ex_i;
    wire fast_result_wen =
        (id_ex_valid_i & !trap_redirect_i & !flush_ex_i & !op_m_unit &
         !op_bitmanip & (fast_alu_op | op_load | op_store | op_bjp));
    assign fast_add_result = operand_a + operand_b;
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

    ydrasil_alu #(
        .DATAWIDTH(DATA_WIDTH)
    ) u_ydrasil_alu (
        .operand_a_i          (operand_a),
        .operand_b_i          (operand_b),
        .operator_i           (operator_i),
        .operator_type_i      (operator_type_i),
        .interrupt_i          (trap_redirect_i),
        .id_rf_waddr_rd_i     (id_rf_waddr_rd_i),
        .id_alu_rf_wen_rd_i   (id_alu_rf_wen_rd_i),
        .comp_result_o        (alu_comp_result),
        .alu_result_o         (alu_result),
        .alu_rf_wen_rd_o      (alu_rf_wen_rd),
        .alu_rf_waddr_rd_o    (alu_rf_waddr_rd)
    );

    ydrasil_div u_ydrasil_div (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (flush_ex_i | trap_redirect_i),
        .start_i         (div_start),
        .operand_a_i     (mul_operand_a),
        .operand_b_i     (mul_operand_b),
        .operator_i      (operator_i),
        .busy_o          (div_busy),
        .done_o          (div_done),
        .result_o        (div_result)
    );

    ydrasil_mul u_ydrasil_mul (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (trap_redirect_i),
        .issue_valid_i   (mul_issue_valid),
        .issue_ready_o   (mul_issue_ready),
        .operand_a_i     (mul_operand_a),
        .operand_b_i     (mul_operand_b),
        .operator_i      (operator_i),
        .issue_wen_i     (mul_issue_wen),
        .issue_waddr_i   (id_rf_waddr_rd_i),
        .issue_producer_id_i(id_ex_producer_id_i),
        .result_valid_o  (mul_result_valid),
        .result_wen_o    (mul_rf_wen_rd_o),
        .result_waddr_o  (mul_rf_waddr_rd_o),
        .result_producer_id_o(mul_producer_id_o),
        .result_wdata_o  (mul_wdata_rd_o)
    );

    logic [OPERATOR_WIDTH-1:0] slow_bitmanip_operator;

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

    ydrasil_bitmanip u_ydrasil_bitmanip (
        .operand_a_i     (bitmanip_operand_a),
        .operand_b_i     (bitmanip_operand_b),
        .operator_i      (slow_bitmanip_operator),
        .operator_type_i (operator_type_i),
        .result_o        (bitmanip_result)
    );

    wire [31:0] slow_result;
    wire        slow_result_wen;
    wire op_csr = id_ex_valid_i & operator_type_i[OPERATOR_TYPE_CSR] & !trap_redirect_i & !flush_ex_i;
    wire csr_csrrw = op_csr & id_op_csr_info_i[OP_CSR_CSRRW];
    wire csr_csrrs = op_csr & id_op_csr_info_i[OP_CSR_CSRRS];
    wire csr_csrrc = op_csr & id_op_csr_info_i[OP_CSR_CSRRC];
    wire [31:0] csr_reg_wdata;
    wire [31:0] csr_wdata;

    reg [REGS_DATA_WIDTH-1:0] ex_csr_wdata_o_ff;
    (* dont_touch = "yes" *) reg [1:0] ex_csr_fs_wdata_o_ff;
    (* dont_touch = "yes" *) reg ex_csr_mstatus_wen_o_ff;
    reg                       ex_csr_wen_o_ff;
    reg [CSR_ADDR_WIDTH-1:0]  ex_csr_waddr_o_ff;

    assign csr_reg_wdata = trap_redirect_i ? '0 : csr_ex_rdata_i;
    assign csr_wdata =
        trap_redirect_i ? '0 :
        ({REGS_DATA_WIDTH{csr_csrrw}} & csr_operand_a) |
        ({REGS_DATA_WIDTH{csr_csrrs}} & (csr_operand_a | csr_ex_rdata_i)) |
        ({REGS_DATA_WIDTH{csr_csrrc}} & (csr_ex_rdata_i & (~csr_operand_a)));
    // CSRRS/CSRRC with rs1 (or zimm) equal to zero are reads only.
    assign csr_wen = op_csr & id_op_csr_info_i[OP_CSR_WRITE];

    assign alu_result_o = bitmanip_result_valid_ff ? bitmanip_result_ff : alu_result_ff;
    assign alu_rf_wen_rd_o = alu_rf_wen_rd_ff;
    assign alu_rf_waddr_rd_o = alu_rf_waddr_rd_ff;
    assign alu_producer_id_o = alu_producer_id_ff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_ff       <= '0;
            bitmanip_result_ff  <= '0;
            bitmanip_result_valid_ff <= 1'b0;
            alu_rf_wen_rd_ff    <= 1'b0;
            alu_rf_waddr_rd_ff  <= '0;
            alu_producer_id_ff  <= '0;
            alu_bypass_valid_q  <= 1'b0;
            alu_bypass_data_q   <= '0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_fs_wdata_o_ff <= '0;
            ex_csr_mstatus_wen_o_ff <= 1'b0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
            div_active_q        <= 1'b0;
            div_wen_q           <= 1'b0;
            div_waddr_q         <= '0;
        end else if (flush_ex_i) begin
            alu_result_ff       <= '0;
            bitmanip_result_ff  <= '0;
            bitmanip_result_valid_ff <= 1'b0;
            alu_rf_wen_rd_ff    <= 1'b0;
            alu_rf_waddr_rd_ff  <= '0;
            alu_producer_id_ff  <= '0;
            alu_bypass_valid_q  <= 1'b0;
            alu_bypass_data_q   <= '0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_fs_wdata_o_ff <= '0;
            ex_csr_mstatus_wen_o_ff <= 1'b0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
            div_active_q        <= 1'b0;
            div_wen_q           <= 1'b0;
            div_waddr_q         <= '0;
        end else begin
            alu_result_ff      <= fast_result_wen ? fast_result :
                                  slow_result_wen ? slow_result : alu_result;
            bitmanip_result_ff <= fast_bitmanip_rf_wen_rd ?
                                  fast_bitmanip_result : bitmanip_result;
            bitmanip_result_valid_ff <=
                bitmanip_rf_wen_rd | fast_bitmanip_rf_wen_rd;
            alu_rf_wen_rd_ff   <= ex_rf_wen_rd;
            alu_rf_waddr_rd_ff <= div_rf_wen_rd ? div_waddr_q : alu_rf_waddr_rd;
            alu_producer_id_ff <= id_ex_producer_id_i;
            alu_bypass_valid_q <= bypassable_alu_op;
            alu_bypass_data_q  <= bypassable_alu_op ?
                                  (shift_alu_op ? alu_result : fast_alu_result) : '0;
            ex_csr_wdata_o_ff  <= csr_wdata;
            ex_csr_fs_wdata_o_ff <= csr_wdata[14:13];
            ex_csr_mstatus_wen_o_ff <= csr_wen && (id_ex_csr_waddr_i == CSR_MSTATUS);
            ex_csr_wen_o_ff    <= csr_wen;
            ex_csr_waddr_o_ff  <= id_ex_csr_waddr_i;

            if (div_start) begin
                div_active_q <= 1'b1;
                div_wen_q    <= id_alu_rf_wen_rd_i & (id_rf_waddr_rd_i != '0);
                div_waddr_q  <= id_rf_waddr_rd_i;
            end else if (div_done) begin
                div_active_q <= 1'b0;
                div_wen_q    <= 1'b0;
                div_waddr_q  <= '0;
            end
        end
    end

    assign ex_csr_wdata_o = ex_csr_wdata_o_ff;
    assign ex_csr_fs_wdata_o = ex_csr_fs_wdata_o_ff;
    assign ex_csr_mstatus_wen_o = ex_csr_mstatus_wen_o_ff;
    assign ex_csr_wen_o = ex_csr_wen_o_ff;
    assign ex_csr_waddr_o = ex_csr_waddr_o_ff;
    assign slow_result_wen = div_rf_wen_rd | op_csr;
    assign slow_result =
        ({32{div_rf_wen_rd}}        & div_result) |
        ({32{op_csr}}               & csr_reg_wdata);

    assign completion_o.valid = ex_rf_wen_rd &&
        ((div_rf_wen_rd ? div_waddr_q : id_rf_waddr_rd_i) != '0);
    assign completion_o.producer_id = id_ex_producer_id_i;
    assign completion_o.producer_tracked = completion_o.valid;
    assign completion_o.addr = div_rf_wen_rd ?
        div_waddr_q : id_rf_waddr_rd_i;
    assign completion_o.data = fast_bitmanip_rf_wen_rd ?
        fast_bitmanip_result : bitmanip_rf_wen_rd ?
        bitmanip_result : slow_result_wen ? slow_result :
        fast_result_wen ? fast_result : alu_result;

endmodule
