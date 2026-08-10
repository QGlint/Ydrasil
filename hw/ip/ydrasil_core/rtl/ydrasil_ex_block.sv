
module ydrasil_ex_block
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            flush_ex_i,

	input  wire [DATA_WIDTH-1:0]           alu_operand_a_i,
	input  wire [DATA_WIDTH-1:0]           alu_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           lsu_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           lsu_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           lsu_store_data_i,
    input  wire [DATA_WIDTH-1:0]           mul_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           mul_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           csr_operand_a_i,
    input  wire [OPERATOR_WIDTH-1:0]       operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  operator_type_i,
    input  wire                            alu_valid_i,
    input  wire                            lsu_valid_i,
    input  wire                            lsu_is_load_i,
    input  wire                            lsu_is_store_i,
    input  wire                            mul_valid_i,
    input  wire                            csr_valid_i,
    input  wire [OPERATOR_WIDTH-1:0]       mul_operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  mul_operator_type_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      mul_rf_waddr_i,
    input  wire                            mul_rf_wen_i,
    input  producer_id_t                   mul_producer_id_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  csr_operator_type_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      id_rf_waddr_rd_i,
    input  wire                            id_alu_rf_wen_rd_i,
    input  producer_id_t                   id_ex_producer_id_i,
    input  wire                            redirect_valid_i,
    input  wire [PRODUCER_NUM-1:0]         redirect_keep_mask_i,
    input  wire                            trap_redirect_i,
    input  wire [INST_ADDR_WIDTH-1:0]      trap_redirect_addr_i,

    input  wire [CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr_i,
    input  wire [OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_i,
    input  wire [DATA_WIDTH-1:0]           csr_ex_rdata_i,

    output wire                            ex_csr_wen_o,
	output wire [DATA_WIDTH-1:0]           ex_csr_wdata_o,
    output wire [CSR_ADDR_WIDTH-1:0]       ex_csr_waddr_o,

	output wire [BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_o,

    output wire [DATA_WIDTH-1:0]           ex_lsu_result_o,

    output wire                            completion_valid_o,
    output producer_id_t                   completion_producer_id_o,
    output wire                            completion_producer_tracked_o,
    output wire [REGS_ADDR_WIDTH-1:0]      completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]      completion_data_o,
    output wire [REGS_DATA_WIDTH-1:0]      early_bypass_data_o,

    output wire                            mul_issue_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_issue_waddr_o,
    output wire [REGS_DATA_WIDTH-1:0]      mul_wdata_rd_o,
    output wire                            mul_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      mul_rf_waddr_rd_o,
    output producer_id_t                   mul_producer_id_o,
    output wire                            mul_result_valid_o,

	output wire                            ex_instret_inc_o,
	output wire                            ex_mul_stall_o
);

    wire [REGS_DATA_WIDTH-1:0] alu_result;
    wire                       alu_rf_wen_rd;
    wire [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd;

    wire op_m_unit;
    wire op_bitmanip;
    wire op_load;
    wire op_store;
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
    wire [REGS_DATA_WIDTH-1:0] mul_pipe_wdata;
    wire                       mul_pipe_wen;
    wire [REGS_ADDR_WIDTH-1:0] mul_pipe_waddr;
    producer_id_t              mul_pipe_producer_id;

    wire [REGS_DATA_WIDTH-1:0] bitmanip_result;
    wire                       bitmanip_rf_wen_rd;
    wire                       normal_alu_rf_wen_rd;
    wire                       div_rf_wen_rd;
    wire                       div_complete;
    wire                       ex_rf_wen_rd;
    wire                       csr_wen;
    reg                        div_active_q;
    reg                        div_pending_q;
    reg                        div_wen_q;
    reg [REGS_ADDR_WIDTH-1:0]  div_waddr_q;
    producer_id_t              div_producer_id_q;
    reg [OPERATOR_WIDTH-1:0]   div_operator_q;
    reg [REGS_DATA_WIDTH-1:0]  div_result_q;

    wire div_kill = trap_redirect_i ||
        (flush_ex_i && redirect_valid_i &&
         !redirect_keep_mask_i[
             div_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]]);

    reg [REGS_DATA_WIDTH-1:0] alu_result_ff;
    reg [REGS_DATA_WIDTH-1:0] bitmanip_result_ff;
    reg                       bitmanip_result_valid_ff;
    reg                       completion_valid_ff;
    producer_id_t             completion_producer_id_ff;
    reg [REGS_ADDR_WIDTH-1:0] completion_addr_ff;

    wire [31:0] operand_a;
    wire [31:0] operand_b;
    wire [31:0] bitmanip_operand_a;
    wire [31:0] bitmanip_operand_b;
    wire [31:0] lsu_operand_b;
    wire [31:0] lsu_store_data;
    wire [31:0] mul_operand_a;
    wire [31:0] mul_operand_b;
    wire [31:0] csr_operand_a;
    wire [31:0] fast_add_result;
    wire [31:0] lsu_fast_add_result;
    wire [31:0] lsu_base_add_result;
    // JALR uses rs1 only for the BRU target. Its architectural rd value is
    // always PC+4, so the ALU link operand must remain the registered PC.
    assign operand_a = alu_operand_a_i;
    assign operand_b = alu_operand_b_i;
    assign bitmanip_operand_a = alu_operand_a_i;
    assign bitmanip_operand_b = alu_operand_b_i;
    assign lsu_operand_b = lsu_operand_b_i;
    assign lsu_store_data = lsu_store_data_i;
    assign mul_operand_a = mul_operand_a_i;
    assign mul_operand_b = mul_operand_b_i;
    assign csr_operand_a = csr_operand_a_i;

    assign lsu_base_add_result = lsu_operand_a_i + lsu_operand_b;
    assign lsu_fast_add_result = lsu_base_add_result;
    assign ex_lsu_mem_addr_o = lsu_fast_add_result;
    assign ex_lsu_result_o = lsu_store_data;

    assign op_m_unit = mul_operator_type_i[OPERATOR_TYPE_MUL];
    assign op_bitmanip = operator_type_i[OPERATOR_TYPE_BITMANIP];
    assign op_load = lsu_valid_i & lsu_is_load_i;
    assign op_store = lsu_valid_i & lsu_is_store_i;
    assign op_mul =
        op_m_unit &
        (mul_operator_i[OP_MUL_MUL]    |
         mul_operator_i[OP_MUL_MULH]   |
         mul_operator_i[OP_MUL_MULHSU] |
         mul_operator_i[OP_MUL_MULHU]);
    assign op_div =
        op_m_unit &
        (mul_operator_i[OP_MUL_DIV]  |
         mul_operator_i[OP_MUL_DIVU] |
         mul_operator_i[OP_MUL_REM]  |
         mul_operator_i[OP_MUL_REMU]);

    assign mul_issue_valid = mul_valid_i & op_mul & mul_issue_ready & !trap_redirect_i & !flush_ex_i;
    assign mul_issue_wen = mul_rf_wen_i & (mul_rf_waddr_i != '0);
    assign mul_issue_o = mul_issue_valid & mul_issue_wen;
    assign mul_issue_waddr_o = mul_rf_waddr_i;

    assign div_start = mul_valid_i & op_div & !div_active_q &
        !div_pending_q & !div_busy & !div_done & !trap_redirect_i &
        !flush_ex_i;
    // A multiply result cannot be backpressured. Hold DIV completion state
    // until the single typed MDU result port is available.
    assign div_complete = div_pending_q & !mul_pipe_wen &
        !trap_redirect_i & !flush_ex_i;
    assign div_rf_wen_rd = div_complete & div_wen_q;
    assign ex_mul_stall_o = mul_valid_i & op_div &
        (div_active_q | div_pending_q | div_busy | div_done) & !flush_ex_i;

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
        alu_valid_i & fast_bitmanip_op & id_alu_rf_wen_rd_i & !trap_redirect_i & !flush_ex_i;
    wire op_csr = csr_valid_i & csr_operator_type_i[OPERATOR_TYPE_CSR] &
        !trap_redirect_i & !flush_ex_i;

    assign bitmanip_rf_wen_rd =
        alu_valid_i & op_bitmanip & !fast_bitmanip_op & id_alu_rf_wen_rd_i &
        !trap_redirect_i & !flush_ex_i;
    assign normal_alu_rf_wen_rd = alu_valid_i & alu_rf_wen_rd &
        (operator_type_i[OPERATOR_TYPE_ALU] | operator_type_i[OPERATOR_TYPE_BJP]) &
        !op_bitmanip & !flush_ex_i;
    assign ex_rf_wen_rd =
        bitmanip_rf_wen_rd | fast_bitmanip_rf_wen_rd |
        normal_alu_rf_wen_rd | op_csr;
    assign mul_result_valid_o = mul_result_valid | div_complete;
    assign ex_instret_inc_o =
			(alu_valid_i & !trap_redirect_i & !flush_ex_i) |
        div_complete;

    wire fast_alu_op =
        operator_type_i[OPERATOR_TYPE_ALU] & !op_bitmanip &
        (operator_i[OP_ALU_ADD]  |
         operator_i[OP_ALU_SUB]  |
         operator_i[OP_ALU_SLT]  |
         operator_i[OP_ALU_SLTU] |
         operator_i[OP_ALU_XOR]  |
         operator_i[OP_ALU_OR]   |
         operator_i[OP_ALU_AND]  |
         operator_i[OP_ALU_LUI]  |
         operator_i[OP_ALU_AUIPC]);
    wire fast_result_wen = alu_valid_i && !trap_redirect_i && !flush_ex_i &&
        !op_bitmanip && fast_alu_op;
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
    // This is intentionally a restricted result cone. Issue uses it only
    // after recording a matching early-wakeup token, so slow bitmanip logic
    // never reaches the next instruction's operand capture path.
    wire early_lite_bitmanip_op = op_bitmanip &
        (operator_i[OP_B_SH1ADD] | operator_i[OP_B_SH2ADD] |
         operator_i[OP_B_SH3ADD] | operator_i[OP_B_PACK] |
         operator_i[OP_B_PACKH]  | operator_i[OP_B_REV8] |
         operator_i[OP_B_SEXT_B] | operator_i[OP_B_SEXT_H] |
         operator_i[OP_B_ZEXT_H]);
    wire [31:0] early_lite_bitmanip_result =
        fast_b_shadd_result | fast_b_pack_result | fast_b_extend_result;
    wire [31:0] early_plain_alu_result = fast_alu_op ?
        fast_alu_result : alu_result;
    assign early_bypass_data_o = early_lite_bitmanip_op ?
        early_lite_bitmanip_result :
		operator_type_i[OPERATOR_TYPE_BJP] ? fast_add_result :
		operator_type_i[OPERATOR_TYPE_ALU] ? early_plain_alu_result : '0;

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
        .comp_result_o        (),
        .alu_result_o         (alu_result),
        .alu_rf_wen_rd_o      (alu_rf_wen_rd),
        .alu_rf_waddr_rd_o    (alu_rf_waddr_rd)
    );

    ydrasil_div u_ydrasil_div (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (div_kill),
        .start_i         (div_start),
        .operand_a_i     (mul_operand_a),
        .operand_b_i     (mul_operand_b),
        .operator_i      (div_active_q ? div_operator_q : mul_operator_i),
        .busy_o          (div_busy),
        .done_o          (div_done),
        .result_o        (div_result)
    );

    ydrasil_mul u_ydrasil_mul (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (trap_redirect_i),
        .redirect_i      (flush_ex_i && redirect_valid_i),
        .redirect_keep_mask_i(redirect_keep_mask_i),
        .issue_valid_i   (mul_issue_valid),
        .issue_ready_o   (mul_issue_ready),
        .operand_a_i     (mul_operand_a),
        .operand_b_i     (mul_operand_b),
        .operator_i      (mul_operator_i),
        .issue_wen_i     (mul_issue_wen),
        .issue_waddr_i   (mul_rf_waddr_i),
        .issue_producer_id_i(mul_producer_id_i),
        .result_valid_o  (mul_result_valid),
        .result_wen_o    (mul_pipe_wen),
        .result_waddr_o  (mul_pipe_waddr),
        .result_producer_id_o(mul_pipe_producer_id),
        .result_wdata_o  (mul_pipe_wdata)
    );

    assign mul_rf_wen_rd_o = mul_pipe_wen | div_rf_wen_rd;
    assign mul_rf_waddr_rd_o = div_rf_wen_rd ? div_waddr_q : mul_pipe_waddr;
    assign mul_producer_id_o = div_rf_wen_rd ?
        div_producer_id_q : mul_pipe_producer_id;
    assign mul_wdata_rd_o = div_rf_wen_rd ? div_result_q : mul_pipe_wdata;

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
    wire csr_csrrw = op_csr & id_op_csr_info_i[OP_CSR_CSRRW];
    wire csr_csrrs = op_csr & id_op_csr_info_i[OP_CSR_CSRRS];
    wire csr_csrrc = op_csr & id_op_csr_info_i[OP_CSR_CSRRC];
    wire [31:0] csr_reg_wdata;
    wire [31:0] csr_wdata;

    reg [REGS_DATA_WIDTH-1:0] ex_csr_wdata_o_ff;
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_ff       <= '0;
            bitmanip_result_ff  <= '0;
            bitmanip_result_valid_ff <= 1'b0;
            completion_valid_ff <= 1'b0;
            completion_addr_ff  <= '0;
            completion_producer_id_ff <= '0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
        end else if (flush_ex_i) begin
            alu_result_ff       <= '0;
            bitmanip_result_ff  <= '0;
            bitmanip_result_valid_ff <= 1'b0;
            completion_valid_ff <= 1'b0;
            completion_addr_ff  <= '0;
            completion_producer_id_ff <= '0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
        end else begin
            // The FU input cell is held while DIV/REM stalls Issue. Capture
            // its result only when execution can advance (including the
            // release cycle), otherwise one producer would emit a completion
            // every stalled cycle and leave a late duplicate after retirement.
            completion_valid_ff <= !ex_mul_stall_o && ex_rf_wen_rd &&
                (id_rf_waddr_rd_i != '0);
            if (!ex_mul_stall_o) begin
                alu_result_ff <= fast_result_wen ? fast_result :
                                 slow_result_wen ? slow_result : alu_result;
                bitmanip_result_ff <= fast_bitmanip_rf_wen_rd ?
                                      fast_bitmanip_result : bitmanip_result;
                bitmanip_result_valid_ff <=
                    bitmanip_rf_wen_rd | fast_bitmanip_rf_wen_rd;
                completion_addr_ff <= id_rf_waddr_rd_i;
                completion_producer_id_ff <= id_ex_producer_id_i;
            end
            ex_csr_wdata_o_ff  <= csr_wdata;
            ex_csr_wen_o_ff    <= csr_wen;
            ex_csr_waddr_o_ff  <= id_ex_csr_waddr_i;

        end
    end

    // Long-latency MDU state is older than subsequently issued branches and
    // therefore survives their redirects. A paired younger DIV is identified
    // by its circular allocation tag and is cancelled precisely.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_active_q      <= 1'b0;
            div_pending_q     <= 1'b0;
            div_wen_q         <= 1'b0;
            div_waddr_q       <= '0;
            div_producer_id_q <= '0;
            div_operator_q    <= '0;
            div_result_q      <= '0;
        end else if (div_kill) begin
            div_active_q      <= 1'b0;
            div_pending_q     <= 1'b0;
            div_wen_q         <= 1'b0;
            div_waddr_q       <= '0;
            div_producer_id_q <= '0;
            div_operator_q    <= '0;
            div_result_q      <= '0;
        end else begin
            if (div_start) begin
                div_active_q <= 1'b1;
                div_wen_q    <= mul_rf_wen_i & (mul_rf_waddr_i != '0);
                div_waddr_q  <= mul_rf_waddr_i;
                div_producer_id_q <= mul_producer_id_i;
                div_operator_q <= mul_operator_i;
            end
            if (div_done && div_active_q) begin
                div_active_q <= 1'b0;
                div_pending_q <= div_wen_q;
                div_result_q <= div_result;
            end else if (div_complete) begin
                div_pending_q <= 1'b0;
                div_wen_q <= 1'b0;
                div_waddr_q <= '0;
            end
        end
    end

    assign ex_csr_wdata_o = ex_csr_wdata_o_ff;
    assign ex_csr_wen_o = ex_csr_wen_o_ff;
    assign ex_csr_waddr_o = ex_csr_waddr_o_ff;
    assign slow_result_wen = op_csr;
    assign slow_result = ({32{op_csr}} & csr_reg_wdata);

    assign completion_valid_o = completion_valid_ff;
    assign completion_producer_id_o = completion_producer_id_ff;
    assign completion_producer_tracked_o = completion_valid_ff;
    assign completion_addr_o = completion_addr_ff;
    assign completion_data_o = bitmanip_result_valid_ff ?
        bitmanip_result_ff : alu_result_ff;

endmodule
