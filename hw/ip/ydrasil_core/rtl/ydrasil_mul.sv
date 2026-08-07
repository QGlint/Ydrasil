module ydrasil_mul
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         flush_i,
    input  wire                         redirect_i,
    input  wire [PRODUCER_NUM-1:0]      redirect_keep_mask_i,

    input  wire                         issue_valid_i,
    output wire                         issue_ready_o,
    input  wire [REGS_DATA_WIDTH-1:0]   operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]   operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0]    operator_i,
    input  wire                         issue_wen_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   issue_waddr_i,
    input  producer_id_t                issue_producer_id_i,

    output wire                         result_valid_o,
    output wire                         result_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0]   result_waddr_o,
    output producer_id_t                result_producer_id_o,
    output wire [REGS_DATA_WIDTH-1:0]   result_wdata_o,
    output wire                         due_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0]   due_waddr_o,
    output producer_id_t                due_producer_id_o
);

    reg                         s0_valid_q;
    reg signed [32:0]           s0_operand_a_q;
    reg signed [32:0]           s0_operand_b_q;
    reg                         s0_high_q;
    reg                         s0_wen_q;
    reg [REGS_ADDR_WIDTH-1:0]   s0_waddr_q;
    producer_id_t               s0_producer_id_q;

    reg                         s1_valid_q;
    reg signed [33:0]           s1_p00_q;
    reg signed [33:0]           s1_p01_q;
    reg signed [33:0]           s1_p10_q;
    reg signed [33:0]           s1_p11_q;
    reg                         s1_high_q;
    reg                         s1_wen_q;
    reg [REGS_ADDR_WIDTH-1:0]   s1_waddr_q;
    producer_id_t               s1_producer_id_q;

    reg                         s2_valid_q;
    reg signed [65:0]           s2_sum_a_q;
    reg signed [65:0]           s2_sum_b_q;
    reg                         s2_high_q;
    reg                         s2_wen_q;
    reg [REGS_ADDR_WIDTH-1:0]   s2_waddr_q;
    producer_id_t               s2_producer_id_q;

    reg                         s3_valid_q;
    reg signed [65:0]           s3_product_q;
    reg                         s3_high_q;
    reg                         s3_wen_q;
    reg [REGS_ADDR_WIDTH-1:0]   s3_waddr_q;
    producer_id_t               s3_producer_id_q;

    wire op_mulh   = operator_i[OP_MUL_MULH];
    wire op_mulhsu = operator_i[OP_MUL_MULHSU];
    wire op_mulhu  = operator_i[OP_MUL_MULHU];

    wire operand_a_signed = op_mulh | op_mulhsu;
    wire operand_b_signed = op_mulh;
    wire select_high = op_mulh | op_mulhsu | op_mulhu;

    wire signed [32:0] operand_a_ext =
        operand_a_signed ? $signed({operand_a_i[31], operand_a_i}) :
                           $signed({1'b0, operand_a_i});
    wire signed [32:0] operand_b_ext =
        operand_b_signed ? $signed({operand_b_i[31], operand_b_i}) :
                           $signed({1'b0, operand_b_i});

    wire signed [16:0] operand_a_lo = $signed({1'b0, s0_operand_a_q[15:0]});
    wire signed [16:0] operand_b_lo = $signed({1'b0, s0_operand_b_q[15:0]});
    wire signed [16:0] operand_a_hi = s0_operand_a_q[32:16];
    wire signed [16:0] operand_b_hi = s0_operand_b_q[32:16];

    wire signed [33:0] p00 = operand_a_lo * operand_b_lo;
    wire signed [33:0] p01 = operand_a_lo * operand_b_hi;
    wire signed [33:0] p10 = operand_a_hi * operand_b_lo;
    wire signed [33:0] p11 = operand_a_hi * operand_b_hi;

    wire signed [65:0] p00_ext = $signed({{32{s1_p00_q[33]}}, s1_p00_q});
    wire signed [65:0] p01_ext = $signed({{32{s1_p01_q[33]}}, s1_p01_q}) <<< 16;
    wire signed [65:0] p10_ext = $signed({{32{s1_p10_q[33]}}, s1_p10_q}) <<< 16;
    wire signed [65:0] p11_ext = $signed({{32{s1_p11_q[33]}}, s1_p11_q}) <<< 32;
    wire signed [65:0] product = s2_sum_a_q + s2_sum_b_q;

    assign issue_ready_o  = 1'b1;
    assign result_valid_o = s3_valid_q;
    assign result_wen_o   = s3_valid_q & s3_wen_q;
    assign result_waddr_o = s3_waddr_q;
    assign result_producer_id_o = s3_producer_id_q;
    assign result_wdata_o = s3_high_q ? s3_product_q[63:32] :
                                        s3_product_q[31:0];
    assign due_valid_o = s2_valid_q && s2_wen_q;
    assign due_waddr_o = s2_waddr_q;
    assign due_producer_id_o = s2_producer_id_q;

    // Keep the DSP boundary free of asynchronous reset controls. Valid and
    // write-enable bits still provide the architectural flush contract.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s0_valid_q  <= 1'b0;
            s0_operand_a_q <= '0;
            s0_operand_b_q <= '0;
            s0_high_q   <= 1'b0;
            s0_wen_q    <= 1'b0;
            s0_waddr_q  <= '0;
            s0_producer_id_q <= '0;
            s1_valid_q  <= 1'b0;
            s1_p00_q    <= '0;
            s1_p01_q    <= '0;
            s1_p10_q    <= '0;
            s1_p11_q    <= '0;
            s1_high_q   <= 1'b0;
            s1_wen_q    <= 1'b0;
            s1_waddr_q  <= '0;
            s1_producer_id_q <= '0;
            s2_valid_q  <= 1'b0;
            s2_sum_a_q  <= '0;
            s2_sum_b_q  <= '0;
            s2_high_q   <= 1'b0;
            s2_wen_q    <= 1'b0;
            s2_waddr_q  <= '0;
            s2_producer_id_q <= '0;
            s3_valid_q  <= 1'b0;
            s3_product_q <= '0;
            s3_high_q   <= 1'b0;
            s3_wen_q    <= 1'b0;
            s3_waddr_q  <= '0;
            s3_producer_id_q <= '0;
        end else if (flush_i) begin
            s0_valid_q  <= 1'b0;
            s1_valid_q  <= 1'b0;
            s2_valid_q  <= 1'b0;
            s3_valid_q  <= 1'b0;
            s0_wen_q    <= 1'b0;
            s1_wen_q    <= 1'b0;
            s2_wen_q    <= 1'b0;
            s3_wen_q    <= 1'b0;
        end else begin
            s0_valid_q <= issue_valid_i & issue_ready_o & !redirect_i;
            s0_operand_a_q <= operand_a_ext;
            s0_operand_b_q <= operand_b_ext;
            s0_high_q <= select_high;
            s0_wen_q <= issue_wen_i;
            s0_waddr_q <= issue_waddr_i;
            s0_producer_id_q <= issue_producer_id_i;

            s1_valid_q <= s0_valid_q &&
                (!redirect_i || redirect_keep_mask_i[
                    s0_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]]);
            s1_p00_q   <= p00;
            s1_p01_q   <= p01;
            s1_p10_q   <= p10;
            s1_p11_q   <= p11;
            s1_high_q  <= s0_high_q;
            s1_wen_q   <= s0_wen_q;
            s1_waddr_q <= s0_waddr_q;
            s1_producer_id_q <= s0_producer_id_q;

            s2_valid_q <= s1_valid_q &&
                (!redirect_i || redirect_keep_mask_i[
                    s1_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]]);
            s2_sum_a_q <= p00_ext + p01_ext;
            s2_sum_b_q <= p10_ext + p11_ext;
            s2_high_q  <= s1_high_q;
            s2_wen_q   <= s1_wen_q;
            s2_waddr_q <= s1_waddr_q;
            s2_producer_id_q <= s1_producer_id_q;

            s3_valid_q   <= s2_valid_q &&
                (!redirect_i || redirect_keep_mask_i[
                    s2_producer_id_q[PRODUCER_SLOT_WIDTH-1:0]]);
            s3_product_q <= product;
            s3_high_q    <= s2_high_q;
            s3_wen_q     <= s2_wen_q;
            s3_waddr_q   <= s2_waddr_q;
            s3_producer_id_q <= s2_producer_id_q;

        end
    end

endmodule
