
module ydrasil_mul
import ydrasil_pkg::*;
(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            flush_i,

    input  wire                            start_i,
    input  wire [REGS_DATA_WIDTH-1:0]      operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]      operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0]       operator_i,

    output wire                            busy_o,
    output wire                            done_o,
    output wire [DOUBLE_REGS_WIDTH-1:0]    result_o
);

    wire op_mulh   = operator_i[OP_MUL_MULH];
    wire op_mulhsu = operator_i[OP_MUL_MULHSU];

    wire operand_a_signed = op_mulh | op_mulhsu;
    wire operand_b_signed = op_mulh;

    if (MUL_MODE == MUL_MODE_RADIX8) begin : g_radix8
        wire operand_a_neg = operand_a_signed & operand_a_i[REGS_DATA_WIDTH-1];
        wire operand_b_neg = operand_b_signed & operand_b_i[REGS_DATA_WIDTH-1];

        wire [REGS_DATA_WIDTH-1:0] operand_a_abs =
            operand_a_neg ? (~operand_a_i + REGS_DATA_WIDTH'(1)) : operand_a_i;
        wire [REGS_DATA_WIDTH-1:0] operand_b_abs =
            operand_b_neg ? (~operand_b_i + REGS_DATA_WIDTH'(1)) : operand_b_i;

        localparam [3:0] MUL_ITER_LAST = 4'd10;

        reg                          busy_q;
        reg                          done_q;
        reg [3:0]                    iter_q;
        reg [32:0]                   multiplier_q;
        reg [66:0]                   acc_q;
        reg [66:0]                   multiplicand_x0_q;
        reg [66:0]                   multiplicand_x1_q;
        reg [66:0]                   multiplicand_x2_q;
        reg [66:0]                   multiplicand_x3_q;
        reg [66:0]                   multiplicand_x4_q;
        reg [66:0]                   multiplicand_x5_q;
        reg [66:0]                   multiplicand_x6_q;
        reg [66:0]                   multiplicand_x7_q;
        reg                          result_neg_q;
        reg [DOUBLE_REGS_WIDTH-1:0]  result_q;

        wire [34:0] operand_a_abs_ext = {3'b000, operand_a_abs};
        wire [34:0] operand_a_x0 = 35'b0;
        wire [34:0] operand_a_x1 = operand_a_abs_ext;
        wire [34:0] operand_a_x2 = operand_a_abs_ext << 1;
        wire [34:0] operand_a_x3 = (operand_a_abs_ext << 1) + operand_a_abs_ext;
        wire [34:0] operand_a_x4 = operand_a_abs_ext << 2;
        wire [34:0] operand_a_x5 = (operand_a_abs_ext << 2) + operand_a_abs_ext;
        wire [34:0] operand_a_x6 = (operand_a_abs_ext << 2) + (operand_a_abs_ext << 1);
        wire [34:0] operand_a_x7 = (operand_a_abs_ext << 2) + (operand_a_abs_ext << 1) + operand_a_abs_ext;

        wire [66:0] start_x0 = {32'b0, operand_a_x0};
        wire [66:0] start_x1 = {32'b0, operand_a_x1};
        wire [66:0] start_x2 = {32'b0, operand_a_x2};
        wire [66:0] start_x3 = {32'b0, operand_a_x3};
        wire [66:0] start_x4 = {32'b0, operand_a_x4};
        wire [66:0] start_x5 = {32'b0, operand_a_x5};
        wire [66:0] start_x6 = {32'b0, operand_a_x6};
        wire [66:0] start_x7 = {32'b0, operand_a_x7};

        wire [32:0] multiplier_start = {1'b0, operand_b_abs};
        wire [32:0] multiplier_start_shift = {3'b000, multiplier_start[32:3]};
        wire [32:0] multiplier_shift = {3'b000, multiplier_q[32:3]};

        reg [66:0] start_partial;
        reg [66:0] partial;

        always_comb begin
            case (multiplier_start[2:0])
                3'd0: start_partial = start_x0;
                3'd1: start_partial = start_x1;
                3'd2: start_partial = start_x2;
                3'd3: start_partial = start_x3;
                3'd4: start_partial = start_x4;
                3'd5: start_partial = start_x5;
                3'd6: start_partial = start_x6;
                default: start_partial = start_x7;
            endcase
        end

        always_comb begin
            case (multiplier_q[2:0])
                3'd0: partial = multiplicand_x0_q;
                3'd1: partial = multiplicand_x1_q;
                3'd2: partial = multiplicand_x2_q;
                3'd3: partial = multiplicand_x3_q;
                3'd4: partial = multiplicand_x4_q;
                3'd5: partial = multiplicand_x5_q;
                3'd6: partial = multiplicand_x6_q;
                default: partial = multiplicand_x7_q;
            endcase
        end

        wire [66:0] acc_next = acc_q + partial;
        wire [DOUBLE_REGS_WIDTH-1:0] result_abs = acc_next[DOUBLE_REGS_WIDTH-1:0];
        wire [DOUBLE_REGS_WIDTH-1:0] result_signed =
            result_neg_q ? (~result_abs + DOUBLE_REGS_WIDTH'(1)) : result_abs;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                busy_q            <= 1'b0;
                done_q            <= 1'b0;
                iter_q            <= '0;
                multiplier_q      <= '0;
                acc_q             <= '0;
                multiplicand_x0_q <= '0;
                multiplicand_x1_q <= '0;
                multiplicand_x2_q <= '0;
                multiplicand_x3_q <= '0;
                multiplicand_x4_q <= '0;
                multiplicand_x5_q <= '0;
                multiplicand_x6_q <= '0;
                multiplicand_x7_q <= '0;
                result_neg_q      <= 1'b0;
                result_q          <= '0;
            end else if (flush_i) begin
                busy_q            <= 1'b0;
                done_q            <= 1'b0;
                iter_q            <= '0;
                multiplier_q      <= '0;
                acc_q             <= '0;
                multiplicand_x0_q <= '0;
                multiplicand_x1_q <= '0;
                multiplicand_x2_q <= '0;
                multiplicand_x3_q <= '0;
                multiplicand_x4_q <= '0;
                multiplicand_x5_q <= '0;
                multiplicand_x6_q <= '0;
                multiplicand_x7_q <= '0;
                result_neg_q      <= 1'b0;
                result_q          <= '0;
            end else begin
                done_q <= 1'b0;

                if (start_i && !busy_q) begin
                    busy_q            <= 1'b1;
                    iter_q            <= 4'd1;
                    multiplier_q      <= multiplier_start_shift;
                    acc_q             <= start_partial;
                    multiplicand_x0_q <= start_x0 << 3;
                    multiplicand_x1_q <= start_x1 << 3;
                    multiplicand_x2_q <= start_x2 << 3;
                    multiplicand_x3_q <= start_x3 << 3;
                    multiplicand_x4_q <= start_x4 << 3;
                    multiplicand_x5_q <= start_x5 << 3;
                    multiplicand_x6_q <= start_x6 << 3;
                    multiplicand_x7_q <= start_x7 << 3;
                    result_neg_q      <= operand_a_neg ^ operand_b_neg;
                end else if (busy_q) begin
                    acc_q <= acc_next;

                    if (iter_q == MUL_ITER_LAST) begin
                        busy_q   <= 1'b0;
                        done_q   <= 1'b1;
                        result_q <= result_signed;
                    end else begin
                        iter_q            <= iter_q + 4'd1;
                        multiplier_q      <= multiplier_shift;
                        multiplicand_x0_q <= multiplicand_x0_q << 3;
                        multiplicand_x1_q <= multiplicand_x1_q << 3;
                        multiplicand_x2_q <= multiplicand_x2_q << 3;
                        multiplicand_x3_q <= multiplicand_x3_q << 3;
                        multiplicand_x4_q <= multiplicand_x4_q << 3;
                        multiplicand_x5_q <= multiplicand_x5_q << 3;
                        multiplicand_x6_q <= multiplicand_x6_q << 3;
                        multiplicand_x7_q <= multiplicand_x7_q << 3;
                    end
                end
            end
        end

        assign busy_o   = busy_q;
        assign done_o   = done_q;
        assign result_o = result_q;
    end else begin : g_4cycle
        localparam [1:0] MUL_4CYCLE_LAST = 2'd3;

        reg                          busy_q;
        reg                          done_q;
        reg [1:0]                    iter_q;
        reg [15:0]                   operand_a_lo_q;
        reg signed [16:0]            operand_a_hi_q;
        reg [15:0]                   operand_b_lo_q;
        reg signed [16:0]            operand_b_hi_q;
        reg [DOUBLE_REGS_WIDTH-1:0]  acc_q;
        reg [DOUBLE_REGS_WIDTH-1:0]  result_q;

        wire signed [16:0] operand_a_lo_half = $signed({1'b0, operand_a_i[15:0]});
        wire signed [16:0] operand_b_lo_half = $signed({1'b0, operand_b_i[15:0]});
        wire signed [16:0] operand_a_hi_half =
            operand_a_signed ? $signed({operand_a_i[31], operand_a_i[31:16]}) :
                               $signed({1'b0, operand_a_i[31:16]});
        wire signed [16:0] operand_b_hi_half =
            operand_b_signed ? $signed({operand_b_i[31], operand_b_i[31:16]}) :
                               $signed({1'b0, operand_b_i[31:16]});

        reg signed [16:0]           mul_lhs;
        reg signed [16:0]           mul_rhs;
        reg [1:0]                   partial_shift;
        reg [DOUBLE_REGS_WIDTH-1:0] partial;

        always_comb begin
            if (!busy_q) begin
                mul_lhs       = operand_a_lo_half;
                mul_rhs       = operand_b_lo_half;
                partial_shift = 2'd0;
            end else begin
                case (iter_q)
                    2'd1: begin
                        mul_lhs       = $signed({1'b0, operand_a_lo_q});
                        mul_rhs       = operand_b_hi_q;
                        partial_shift = 2'd1;
                    end
                    2'd2: begin
                        mul_lhs       = operand_a_hi_q;
                        mul_rhs       = $signed({1'b0, operand_b_lo_q});
                        partial_shift = 2'd1;
                    end
                    default: begin
                        mul_lhs       = operand_a_hi_q;
                        mul_rhs       = operand_b_hi_q;
                        partial_shift = 2'd2;
                    end
                endcase
            end
        end

        wire signed [33:0] mul_product = mul_lhs * mul_rhs;

        always_comb begin
            case (partial_shift)
                2'd0: partial = {{30{mul_product[33]}}, mul_product};
                2'd1: partial = {{14{mul_product[33]}}, mul_product, 16'b0};
                default: partial = {mul_product[31:0], 32'b0};
            endcase
        end

        wire [DOUBLE_REGS_WIDTH-1:0] acc_next = acc_q + partial;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                busy_q         <= 1'b0;
                done_q         <= 1'b0;
                iter_q         <= '0;
                operand_a_lo_q <= '0;
                operand_a_hi_q <= '0;
                operand_b_lo_q <= '0;
                operand_b_hi_q <= '0;
                acc_q          <= '0;
                result_q       <= '0;
            end else if (flush_i) begin
                busy_q         <= 1'b0;
                done_q         <= 1'b0;
                iter_q         <= '0;
                operand_a_lo_q <= '0;
                operand_a_hi_q <= '0;
                operand_b_lo_q <= '0;
                operand_b_hi_q <= '0;
                acc_q          <= '0;
                result_q       <= '0;
            end else begin
                done_q <= 1'b0;

                if (start_i && !busy_q) begin
                    busy_q         <= 1'b1;
                    iter_q         <= 2'd1;
                    operand_a_lo_q <= operand_a_i[15:0];
                    operand_a_hi_q <= operand_a_hi_half;
                    operand_b_lo_q <= operand_b_i[15:0];
                    operand_b_hi_q <= operand_b_hi_half;
                    acc_q          <= partial;
                end else if (busy_q) begin
                    acc_q <= acc_next;

                    if (iter_q == MUL_4CYCLE_LAST) begin
                        busy_q   <= 1'b0;
                        done_q   <= 1'b1;
                        result_q <= acc_next;
                    end else begin
                        iter_q <= iter_q + 2'd1;
                    end
                end
            end
        end

        assign busy_o   = busy_q;
        assign done_o   = done_q;
        assign result_o = result_q;
    end

endmodule
