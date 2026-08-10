
module ydrasil_ex_block
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            flush_ex_i,
    input  wire                            lane_b_flush_i,

	input  wire [DATA_WIDTH-1:0]           alu_operand_a_i,
	input  wire [DATA_WIDTH-1:0]           alu_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           lsu_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           lsu_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           lsu_store_data_i,
    input  wire [DATA_WIDTH-1:0]           mul_operand_a_i,
    input  wire [DATA_WIDTH-1:0]           mul_operand_b_i,
    input  wire [DATA_WIDTH-1:0]           csr_operand_a_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      csr_rf_waddr_i,
    input  wire                            csr_rf_wen_i,
    input  producer_id_t                   csr_producer_id_i,
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
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  csr_operator_type_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      mul_rf_waddr_i,
    input  wire                            mul_rf_wen_i,
    input  producer_id_t                   mul_producer_id_i,
    input  wire [REGS_ADDR_WIDTH-1:0]      id_rf_waddr_rd_i,
    input  wire                            id_alu_rf_wen_rd_i,
    input  producer_id_t                   id_ex_producer_id_i,
    input  wire                            trap_redirect_i,
    input  wire [INST_ADDR_WIDTH-1:0]      trap_redirect_addr_i,
    input  wire                            branch_recovery_i,
    input  producer_slot_t                 recovery_head_slot_i,
    input  producer_slot_t                 recovery_branch_slot_i,

    input  wire [CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr_i,
    input  wire [OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_i,
    input  wire [DATA_WIDTH-1:0]           csr_ex_rdata_i,

    output wire                            ex_csr_wen_o,
	output wire [DATA_WIDTH-1:0]           ex_csr_wdata_o,
    output wire [CSR_ADDR_WIDTH-1:0]       ex_csr_waddr_o,

	output wire [BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_o,

    output wire [DATA_WIDTH-1:0]           ex_lsu_result_o,

    output wire [REGS_DATA_WIDTH-1:0]      alu_result_o,
    output wire                            alu_rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]      alu_rf_waddr_rd_o,
    output producer_id_t                   alu_producer_id_o,
    output wire                            completion_valid_o,
    output producer_id_t                   completion_producer_id_o,
    output wire                            completion_producer_tracked_o,
    output wire [REGS_ADDR_WIDTH-1:0]      completion_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]      completion_data_o,

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
    wire                       mul_due_valid;
    wire [REGS_ADDR_WIDTH-1:0] mul_due_waddr;
    producer_id_t              mul_due_producer_id;

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

    // A redirecting branch may squash a younger divider already resident in
    // the MDU. Older DIV state remains live and is allowed to complete, so the
    // scheduler identity token and physical reservation agree.
    wire div_recovery_keep = producer_slot_in_window(
        div_producer_id_q[PRODUCER_SLOT_WIDTH-1:0],
        recovery_head_slot_i, recovery_branch_slot_i) &&
        (div_producer_id_q[PRODUCER_SLOT_WIDTH-1:0] !=
         recovery_branch_slot_i);
    wire div_kill = trap_redirect_i ||
        (branch_recovery_i && !div_recovery_keep);

    reg [REGS_DATA_WIDTH-1:0] alu_result_ff;
    reg                       alu_rf_wen_rd_ff;
    producer_id_t             alu_producer_id_ff;
    (* max_fanout = 8 *) reg [REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd_ff;

    wire [31:0] operand_a;
    wire [31:0] operand_b;
    wire [31:0] lsu_operand_b;
    wire [31:0] lsu_store_data;
    wire [31:0] mul_operand_a;
    wire [31:0] mul_operand_b;
    wire [31:0] csr_operand_a;
    wire [31:0] lsu_fast_add_result;
    wire [31:0] lsu_base_add_result;
    // JALR uses rs1 only for the BRU target. Its architectural rd value is
    // always PC+4, so the ALU link operand must remain the registered PC.
    assign operand_a = alu_operand_a_i;
    assign operand_b = alu_operand_b_i;
    assign lsu_operand_b = lsu_operand_b_i;
    assign lsu_store_data = lsu_store_data_i;
    assign mul_operand_a = mul_operand_a_i;
    assign mul_operand_b = mul_operand_b_i;
    assign csr_operand_a = csr_operand_a_i;

    assign lsu_base_add_result = lsu_operand_a_i + lsu_operand_b;
    assign lsu_fast_add_result = lsu_base_add_result;
    assign ex_lsu_mem_addr_o = lsu_fast_add_result;
    assign ex_lsu_result_o = lsu_store_data;

    // MDU control belongs exclusively to the lane-B MDU input cell.  The
    // operator bits remain registered after a bubble, so validity must gate
    // the class decode; otherwise a same-cycle lane-A ALU result is silently
    // suppressed whenever the stale MDU class is still present.
    assign op_m_unit = mul_valid_i &&
        mul_operator_type_i[OPERATOR_TYPE_MUL];
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

    assign mul_issue_valid = mul_valid_i & op_mul & mul_issue_ready &
        !trap_redirect_i & !lane_b_flush_i;
    assign mul_issue_wen = mul_rf_wen_i & (mul_rf_waddr_i != '0);
    assign mul_issue_o = mul_issue_valid & mul_issue_wen;
    assign mul_issue_waddr_o = mul_rf_waddr_i;

    assign div_start = mul_valid_i & op_div & !div_active_q &
        !div_pending_q & !div_busy & !div_done & !div_kill &
        !lane_b_flush_i;
    // A multiply result cannot be backpressured. Hold DIV completion state
    // until the single typed MDU result port is available.
    assign div_complete = div_pending_q & !mul_pipe_wen & !div_kill;
    assign div_rf_wen_rd = div_complete & div_wen_q;
    assign ex_mul_stall_o = mul_valid_i & op_div &
        (div_active_q | div_pending_q | div_busy | div_done) &
        !lane_b_flush_i;
`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && !lane_b_flush_i)
            assert (!ex_mul_stall_o)
                else $fatal(1, "lane B issued DIV without a local reservation");
    end
`endif

    wire op_csr = csr_valid_i & csr_operator_type_i[OPERATOR_TYPE_CSR] &
        !trap_redirect_i & !lane_b_flush_i;

    assign normal_alu_rf_wen_rd = alu_valid_i & alu_rf_wen_rd &
        (operator_type_i[OPERATOR_TYPE_ALU] | operator_type_i[OPERATOR_TYPE_BJP]) &
        !flush_ex_i;
    assign ex_rf_wen_rd = normal_alu_rf_wen_rd | op_csr;
    assign mul_result_valid_o = mul_result_valid | div_complete;
    assign ex_instret_inc_o =
			(alu_valid_i & !trap_redirect_i & !flush_ex_i) |
        div_complete;

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
        .result_wdata_o  (mul_pipe_wdata),
        .due_valid_o     (mul_due_valid),
        .due_waddr_o     (mul_due_waddr),
        .due_producer_id_o(mul_due_producer_id)
    );

    assign mul_rf_wen_rd_o = mul_pipe_wen | div_rf_wen_rd;
    assign mul_rf_waddr_rd_o = div_rf_wen_rd ? div_waddr_q : mul_pipe_waddr;
    assign mul_producer_id_o = div_rf_wen_rd ?
        div_producer_id_q : mul_pipe_producer_id;
    assign mul_wdata_rd_o = div_rf_wen_rd ? div_result_q : mul_pipe_wdata;

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

    assign alu_result_o = alu_result_ff;
    assign alu_rf_wen_rd_o = alu_rf_wen_rd_ff;
    assign alu_rf_waddr_rd_o = alu_rf_waddr_rd_ff;
    assign alu_producer_id_o = alu_producer_id_ff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_ff       <= '0;
            alu_rf_wen_rd_ff    <= 1'b0;
            alu_rf_waddr_rd_ff  <= '0;
            alu_producer_id_ff  <= '0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
        end else if (trap_redirect_i) begin
            alu_result_ff       <= '0;
            alu_rf_wen_rd_ff    <= 1'b0;
            alu_rf_waddr_rd_ff  <= '0;
            alu_producer_id_ff  <= '0;
            ex_csr_wdata_o_ff   <= '0;
            ex_csr_wen_o_ff     <= 1'b0;
            ex_csr_waddr_o_ff   <= '0;
        end else begin
            alu_result_ff      <= slow_result_wen ? slow_result : alu_result;
            alu_rf_wen_rd_ff   <= ex_rf_wen_rd;
            alu_rf_waddr_rd_ff <= op_csr ? csr_rf_waddr_i : alu_rf_waddr_rd;
            alu_producer_id_ff <= op_csr ? csr_producer_id_i :
                id_ex_producer_id_i;
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

    wire [REGS_ADDR_WIDTH-1:0] completion_waddr = op_csr ?
        csr_rf_waddr_i : id_rf_waddr_rd_i;
    assign completion_valid_o = ex_rf_wen_rd && (completion_waddr != '0);
    assign completion_producer_id_o = op_csr ? csr_producer_id_i :
        id_ex_producer_id_i;
    assign completion_producer_tracked_o = ex_rf_wen_rd &&
        (completion_waddr != '0);
    assign completion_addr_o = completion_waddr;
    assign completion_data_o = slow_result_wen ? slow_result : alu_result;

endmodule
