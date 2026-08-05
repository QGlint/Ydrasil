module ydrasil_div
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
    output wire [REGS_DATA_WIDTH-1:0]      result_o
);

    generate
        begin : g_lzc_div
            localparam int unsigned LZC_CNT_WIDTH =
                (REGS_DATA_WIDTH > 1) ? $clog2(REGS_DATA_WIDTH) : 1;

            typedef enum logic [1:0] {
                DIV_STATE_IDLE,
                DIV_STATE_SHIFT,
                DIV_STATE_ITER,
                DIV_STATE_FINISH
            } div_state_e;

            div_state_e                    state_q;
            logic                          busy_q;
            logic                          done_q;
            logic [LZC_CNT_WIDTH:0]        iter_q;
            logic [REGS_DATA_WIDTH-1:0]    dividend_q;
            logic [REGS_DATA_WIDTH-1:0]    divisor_q;
            logic [REGS_DATA_WIDTH-1:0]    divisor_shift_q;
            logic [REGS_DATA_WIDTH-1:0]    quotient_q;
            logic signed [REGS_DATA_WIDTH:0] remainder_q;
            logic                          quotient_neg_q;
            logic                          remainder_neg_q;
            logic                          rem_result_q;
            logic [LZC_CNT_WIDTH-1:0]      dividend_lzc_q;
            logic [LZC_CNT_WIDTH-1:0]      divisor_lzc_q;
            logic                          dividend_empty_q;
            logic [REGS_DATA_WIDTH-1:0]    result_q;

            logic [LZC_CNT_WIDTH-1:0]      dividend_lzc;
            logic [LZC_CNT_WIDTH-1:0]      divisor_lzc;
            logic                          dividend_empty;
            logic                          divisor_empty;

            wire op_div  = operator_i[OP_MUL_DIV];
            wire op_rem  = operator_i[OP_MUL_REM];
            wire op_remu = operator_i[OP_MUL_REMU];

            wire signed_op = op_div | op_rem;
            wire rem_op    = op_rem | op_remu;

            wire dividend_neg = signed_op & operand_a_i[REGS_DATA_WIDTH-1];
            wire divisor_neg  = signed_op & operand_b_i[REGS_DATA_WIDTH-1];

            wire [REGS_DATA_WIDTH-1:0] dividend_abs =
                dividend_neg ? (~operand_a_i + REGS_DATA_WIDTH'(1)) : operand_a_i;
            wire [REGS_DATA_WIDTH-1:0] divisor_abs =
                divisor_neg ? (~operand_b_i + REGS_DATA_WIDTH'(1)) : operand_b_i;

            wire divisor_is_zero = (operand_b_i == REGS_DATA_WIDTH'(0));
            wire signed_overflow = signed_op &
                (operand_a_i == {1'b1, {(REGS_DATA_WIDTH-1){1'b0}}}) &
                (operand_b_i == {REGS_DATA_WIDTH{1'b1}});

            wire [REGS_DATA_WIDTH-1:0] divide_by_zero_result =
                rem_op ? operand_a_i : {REGS_DATA_WIDTH{1'b1}};
            wire [REGS_DATA_WIDTH-1:0] overflow_result =
                rem_op ? REGS_DATA_WIDTH'(0) : {1'b1, {(REGS_DATA_WIDTH-1){1'b0}}};

            wire dividend_smaller = dividend_lzc_q > divisor_lzc_q;
            wire [LZC_CNT_WIDTH:0] divisor_lzc_ext = {1'b0, divisor_lzc_q};
            wire [LZC_CNT_WIDTH:0] dividend_lzc_ext = {1'b0, dividend_lzc_q};
            wire [LZC_CNT_WIDTH:0] align_shift = divisor_lzc_ext - dividend_lzc_ext;
            wire [REGS_DATA_WIDTH-1:0] divisor_aligned =
                divisor_q << align_shift[LZC_CNT_WIDTH-1:0];

            wire signed [REGS_DATA_WIDTH:0] divisor_shift_ext =
                $signed({1'b0, divisor_shift_q});
            wire signed [REGS_DATA_WIDTH:0] divisor_ext =
                $signed({1'b0, divisor_q});
            wire signed [REGS_DATA_WIDTH:0] remainder_calc =
                remainder_q[REGS_DATA_WIDTH] ?
                (remainder_q + divisor_shift_ext) :
                (remainder_q - divisor_shift_ext);
            wire remainder_calc_nonneg = ~remainder_calc[REGS_DATA_WIDTH];
            wire [REGS_DATA_WIDTH-1:0] quotient_bit_mask =
                REGS_DATA_WIDTH'(1) << iter_q[LZC_CNT_WIDTH-1:0];
            wire [REGS_DATA_WIDTH-1:0] quotient_next =
                quotient_q | (remainder_calc_nonneg ? quotient_bit_mask : '0);
            wire signed [REGS_DATA_WIDTH:0] remainder_q_final =
                remainder_q[REGS_DATA_WIDTH] ? (remainder_q + divisor_ext) : remainder_q;

            wire [REGS_DATA_WIDTH-1:0] quotient_finish_result =
                quotient_neg_q ? (~quotient_q + REGS_DATA_WIDTH'(1)) : quotient_q;
            wire [REGS_DATA_WIDTH-1:0] remainder_finish_result =
                remainder_neg_q ?
                (~remainder_q_final[REGS_DATA_WIDTH-1:0] + REGS_DATA_WIDTH'(1)) :
                remainder_q_final[REGS_DATA_WIDTH-1:0];
            wire [REGS_DATA_WIDTH-1:0] smaller_remainder_result =
                remainder_neg_q ? (~dividend_q + REGS_DATA_WIDTH'(1)) : dividend_q;
            wire [REGS_DATA_WIDTH-1:0] finish_result =
                rem_result_q ? remainder_finish_result : quotient_finish_result;
            wire [REGS_DATA_WIDTH-1:0] smaller_result =
                rem_result_q ? smaller_remainder_result : '0;

            ydrasil_lzc #(
                .WIDTH     (REGS_DATA_WIDTH),
                .MODE      (1'b0),
                .CNT_WIDTH (LZC_CNT_WIDTH)
            ) u_dividend_lzc (
                .lzc_in_i    (dividend_abs),
                .lzc_cnt_o   (dividend_lzc),
                .lzc_empty_o (dividend_empty)
            );

            ydrasil_lzc #(
                .WIDTH     (REGS_DATA_WIDTH),
                .MODE      (1'b0),
                .CNT_WIDTH (LZC_CNT_WIDTH)
            ) u_divisor_lzc (
                .lzc_in_i    (divisor_abs),
                .lzc_cnt_o   (divisor_lzc),
                .lzc_empty_o (divisor_empty)
            );

            // Redirect handling only needs to kill the architectural divider
            // state. Keeping that control separate prevents the high-fanout
            // recovery signal from becoming a data-select input on every
            // iterative datapath register.
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    state_q <= DIV_STATE_IDLE;
                    busy_q  <= 1'b0;
                    done_q  <= 1'b0;
                end else if (flush_i) begin
                    state_q <= DIV_STATE_IDLE;
                    busy_q  <= 1'b0;
                    done_q  <= 1'b0;
                end else begin
                    done_q <= 1'b0;

                    unique case (state_q)
                        DIV_STATE_IDLE: begin
                            if (start_i && !busy_q) begin
                                if (divisor_is_zero || signed_overflow) begin
                                    busy_q <= 1'b0;
                                    done_q <= 1'b1;
                                end else begin
                                    busy_q  <= 1'b1;
                                    state_q <= DIV_STATE_SHIFT;
                                end
                            end
                        end

                        DIV_STATE_SHIFT: begin
                            if (dividend_empty_q || dividend_smaller) begin
                                busy_q  <= 1'b0;
                                done_q  <= 1'b1;
                                state_q <= DIV_STATE_IDLE;
                            end else begin
                                state_q <= DIV_STATE_ITER;
                            end
                        end

                        DIV_STATE_ITER: begin
                            if (iter_q == '0)
                                state_q <= DIV_STATE_FINISH;
                        end

                        DIV_STATE_FINISH: begin
                            busy_q  <= 1'b0;
                            done_q  <= 1'b1;
                            state_q <= DIV_STATE_IDLE;
                        end

                        default: begin
                            state_q <= DIV_STATE_IDLE;
                            busy_q  <= 1'b0;
                            done_q  <= 1'b0;
                        end
                    endcase
                end
            end

            // The ex-block clears the matching producer state on the same
            // redirect edge, so a killed result is architecturally invisible.
            // Do not reference flush_i here: it must remain out of the wide
            // iterative data cone.
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    iter_q           <= '0;
                    dividend_q       <= '0;
                    divisor_q        <= '0;
                    divisor_shift_q  <= '0;
                    quotient_q       <= '0;
                    remainder_q      <= '0;
                    quotient_neg_q   <= 1'b0;
                    remainder_neg_q  <= 1'b0;
                    rem_result_q     <= 1'b0;
                    dividend_lzc_q   <= '0;
                    divisor_lzc_q    <= '0;
                    dividend_empty_q <= 1'b0;
                    result_q         <= '0;
                end else begin
                    unique case (state_q)
                        DIV_STATE_IDLE: begin
                            if (start_i && !busy_q) begin
                                if (divisor_is_zero) begin
                                    result_q <= divide_by_zero_result;
                                end else if (signed_overflow) begin
                                    result_q <= overflow_result;
                                end else begin
                                    dividend_q       <= dividend_abs;
                                    divisor_q        <= divisor_abs;
                                    quotient_q       <= '0;
                                    remainder_q      <= '0;
                                    divisor_shift_q  <= '0;
                                    iter_q           <= '0;
                                    quotient_neg_q   <= dividend_neg ^ divisor_neg;
                                    remainder_neg_q  <= dividend_neg;
                                    rem_result_q     <= rem_op;
                                    dividend_lzc_q   <= dividend_lzc;
                                    divisor_lzc_q    <= divisor_lzc;
                                    dividend_empty_q <= dividend_empty;
                                end
                            end
                        end

                        DIV_STATE_SHIFT: begin
                            if (dividend_empty_q || dividend_smaller) begin
                                result_q <= smaller_result;
                            end else begin
                                iter_q          <= align_shift;
                                divisor_shift_q <= divisor_aligned;
                                quotient_q      <= '0;
                                remainder_q     <= $signed({1'b0, dividend_q});
                            end
                        end

                        DIV_STATE_ITER: begin
                            remainder_q     <= remainder_calc;
                            quotient_q      <= quotient_next;
                            divisor_shift_q <= divisor_shift_q >> 1;
                            if (iter_q == '0)
                                iter_q <= '0;
                            else
                                iter_q <= iter_q -
                                    {{LZC_CNT_WIDTH{1'b0}}, 1'b1};
                        end

                        DIV_STATE_FINISH: begin
                            result_q <= finish_result;
                        end

                        default: begin end
                    endcase
                end
            end

            assign busy_o   = busy_q;
            assign done_o   = done_q;
            assign result_o = result_q;

            wire unused_divisor_empty = divisor_empty;
        end
    endgenerate

endmodule
