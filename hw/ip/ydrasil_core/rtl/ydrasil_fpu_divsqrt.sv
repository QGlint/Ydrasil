module ydrasil_fpu_divsqrt
    import ydrasil_pkg::*;
    import ydrasil_fpu_math_pkg::*;
(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_i,
    input  wire         sqrt_i,
    input  wire         fmt_i,
    input  wire [2:0]   rm_i,
    input  wire [63:0]  operand_a_i,
    input  wire [63:0]  operand_b_i,
    output wire         busy_o,
    output wire         done_o,
    output wire [63:0]  result_o,
    output wire [4:0]   flags_o
);
    typedef enum logic [3:0] {
        IDLE,
        PREPARE,
        NORMALIZE,
        DIVIDE,
        DIVIDE_UPDATE,
        SQUARE_ROOT,
        SQUARE_ROOT_UPDATE,
        FINAL_LOCATE,
        FINAL_EXPONENT,
        FINAL_SHIFT,
        FINAL_ROUND,
        FINAL_PACK
    } state_t;

    state_t state_q;
    reg done_q;
    reg [63:0] result_q;
    reg [4:0] flags_q;
    reg fmt_q;
    reg [2:0] rm_q;
    reg result_sign_q;
    reg signed [15:0] result_exp_q;
    reg [6:0] bits_q;
    reg [6:0] iterations_q;
    reg final_sqrt_q;
    reg final_zero_q;
    reg signed [15:0] final_top_q;
    reg signed [15:0] final_exponent_q;
    reg signed [15:0] final_discard_q;
    reg [63:0] final_main_q;
    reg final_guard_q;
    reg final_sticky_q;
    reg [63:0] normalized_sig_a_q;
    reg [63:0] normalized_sig_b_q;
    reg signed [15:0] normalized_exp_a_q;
    reg signed [15:0] normalized_exp_b_q;
    fp_dec_t operand_a_q;
    fp_dec_t operand_b_q;
    reg sqrt_q;

    reg [63:0] divisor_q;
    reg [63:0] div_remainder_q;
    reg [63:0] quotient_q;
    reg [64:0] div_shifted_remainder_q;
    reg div_subtract_q;

    reg [127:0] radicand_q;
    reg [127:0] sqrt_remainder_q;
    reg [63:0] sqrt_root_q;
    reg [127:0] sqrt_shifted_remainder_q;
    reg [127:0] sqrt_trial_q;
    reg sqrt_subtract_q;

    reg [63:0] rounded_main_q;
    reg signed [15:0] rounded_exponent_q;
    reg rounded_inexact_q;
    reg rounded_sign_q;

    fp_dec_t start_a;
    fp_dec_t start_b;
    fp_result_t special_result;
    reg start_special;
    reg [6:0] start_precision;
    reg [6:0] start_bits;
    reg [63:0] start_sig_a;
    reg [63:0] start_sig_b;

    always_comb begin
        start_a = operand_a_q;
        start_b = operand_b_q;
        special_result = '0;
        start_special = 1'b0;
        start_precision = fmt_q ? 7'd53 : 7'd24;
        start_bits = start_precision + 7'd4;
        start_sig_a = {11'b0, start_a.significand};
        start_sig_b = {11'b0, start_b.significand};

        if (sqrt_q) begin
            if (start_a.nan) begin
                start_special = 1'b1;
                special_result.data = canonical_nan(fmt_q);
                special_result.flags[4] = start_a.snan;
            end else if (start_a.sign && !start_a.zero) begin
                start_special = 1'b1;
                special_result.data = canonical_nan(fmt_q);
                special_result.flags[4] = 1'b1;
            end else if (start_a.inf || start_a.zero) begin
                start_special = 1'b1;
                special_result.data = fmt_q ? {start_a.sign, 11'h7ff, 52'b0} :
                    box_single({start_a.sign, 8'hff, 23'b0});
                if (start_a.zero)
                    special_result.data = fmt_q ? {start_a.sign, 63'b0} :
                        box_single({start_a.sign, 31'b0});
            end
        end else begin
            if (start_a.nan || start_b.nan) begin
                start_special = 1'b1;
                special_result.data = canonical_nan(fmt_q);
                special_result.flags[4] = start_a.snan || start_b.snan;
            end else if ((start_a.zero && start_b.zero) ||
                         (start_a.inf && start_b.inf)) begin
                start_special = 1'b1;
                special_result.data = canonical_nan(fmt_q);
                special_result.flags[4] = 1'b1;
            end else if (start_b.zero) begin
                start_special = 1'b1;
                special_result.data = fmt_q ?
                    {start_a.sign ^ start_b.sign, 11'h7ff, 52'b0} :
                    box_single({start_a.sign ^ start_b.sign, 8'hff, 23'b0});
                special_result.flags[3] = 1'b1;
            end else if (start_a.inf) begin
                start_special = 1'b1;
                special_result.data = fmt_q ?
                    {start_a.sign ^ start_b.sign, 11'h7ff, 52'b0} :
                    box_single({start_a.sign ^ start_b.sign, 8'hff, 23'b0});
            end else if (start_b.inf || start_a.zero) begin
                start_special = 1'b1;
                special_result.data = fmt_q ?
                    {start_a.sign ^ start_b.sign, 63'b0} :
                    box_single({start_a.sign ^ start_b.sign, 31'b0});
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        fp_result_t rounded;
        logic [64:0] shifted_remainder;
        logic [63:0] next_remainder;
        logic [63:0] next_quotient;
        logic [127:0] sqrt_shifted_remainder;
        logic [127:0] sqrt_trial;
        logic [127:0] sqrt_next_remainder;
        logic [63:0] sqrt_next_root;
        logic [1:0] next_pair;
        if (!rst_n) begin
            state_q <= IDLE;
            done_q <= 1'b0;
            result_q <= '0;
            flags_q <= '0;
            fmt_q <= 1'b0;
            rm_q <= '0;
            result_sign_q <= 1'b0;
            result_exp_q <= '0;
            bits_q <= '0;
            iterations_q <= '0;
            final_sqrt_q <= 1'b0;
            final_zero_q <= 1'b0;
            final_top_q <= '0;
            final_exponent_q <= '0;
            final_discard_q <= '0;
            final_main_q <= '0;
            final_guard_q <= 1'b0;
            final_sticky_q <= 1'b0;
            normalized_sig_a_q <= '0;
            normalized_sig_b_q <= '0;
            normalized_exp_a_q <= '0;
            normalized_exp_b_q <= '0;
            operand_a_q <= '0;
            operand_b_q <= '0;
            sqrt_q <= 1'b0;
            divisor_q <= '0;
            div_remainder_q <= '0;
            quotient_q <= '0;
            div_shifted_remainder_q <= '0;
            div_subtract_q <= 1'b0;
            radicand_q <= '0;
            sqrt_remainder_q <= '0;
            sqrt_root_q <= '0;
            sqrt_shifted_remainder_q <= '0;
            sqrt_trial_q <= '0;
            sqrt_subtract_q <= 1'b0;
            rounded_main_q <= '0;
            rounded_exponent_q <= '0;
            rounded_inexact_q <= 1'b0;
            rounded_sign_q <= 1'b0;
        end else begin
            done_q <= 1'b0;
            if (start_i && state_q == IDLE) begin
                fmt_q <= fmt_i;
                rm_q <= rm_i;
                operand_a_q <= fp_decode(operand_a_i, fmt_i);
                operand_b_q <= fp_decode(operand_b_i, fmt_i);
                sqrt_q <= sqrt_i;
                state_q <= PREPARE;
            end else if (state_q == PREPARE) begin
                bits_q <= start_bits;
                result_sign_q <= sqrt_q ? 1'b0 :
                    (start_a.sign ^ start_b.sign);
                if (start_special) begin
                    result_q <= special_result.data;
                    flags_q <= special_result.flags;
                    done_q <= 1'b1;
                    state_q <= IDLE;
                end else begin
                    normalized_sig_a_q <= start_sig_a;
                    normalized_sig_b_q <= start_sig_b;
                    normalized_exp_a_q <= start_a.exponent;
                    normalized_exp_b_q <= start_b.exponent;
                    state_q <= NORMALIZE;
                end
            end else if (state_q == NORMALIZE) begin
                integer precision;
                integer radicand_shift;
                logic signed [15:0] sqrt_exponent;
                logic [63:0] sqrt_significand;
                precision = fmt_q ? 53 : 24;
                if (!normalized_sig_a_q[precision-1]) begin
                    normalized_sig_a_q <= normalized_sig_a_q << 1;
                    normalized_exp_a_q <= normalized_exp_a_q - 1'b1;
                end
                if (!sqrt_q && !normalized_sig_b_q[precision-1]) begin
                    normalized_sig_b_q <= normalized_sig_b_q << 1;
                    normalized_exp_b_q <= normalized_exp_b_q - 1'b1;
                end
                if (normalized_sig_a_q[precision-1] &&
                    (sqrt_q || normalized_sig_b_q[precision-1])) begin
                    if (sqrt_q) begin
                        sqrt_exponent = normalized_exp_a_q;
                        sqrt_significand = normalized_sig_a_q;
                        if (sqrt_exponent[0]) begin
                            sqrt_significand = sqrt_significand << 1;
                            sqrt_exponent = sqrt_exponent - 1'b1;
                        end
                        result_exp_q <= sqrt_exponent >>> 1;
                        radicand_shift = 127 - precision;
                        radicand_q <=
                            {64'b0, sqrt_significand} << radicand_shift;
                        sqrt_remainder_q <= '0;
                        sqrt_root_q <= '0;
                        iterations_q <= bits_q;
                        state_q <= SQUARE_ROOT;
                    end else begin
                        result_exp_q <= normalized_exp_a_q -
                            normalized_exp_b_q -
                            (normalized_sig_a_q < normalized_sig_b_q);
                        divisor_q <= normalized_sig_b_q;
                        quotient_q <= 64'b1 << (bits_q-1);
                        if (normalized_sig_a_q >= normalized_sig_b_q)
                            div_remainder_q <= normalized_sig_a_q -
                                normalized_sig_b_q;
                        else
                            div_remainder_q <=
                                (normalized_sig_a_q << 1) -
                                normalized_sig_b_q;
                        iterations_q <= bits_q - 1'b1;
                        state_q <= DIVIDE;
                    end
                end
            end else if (state_q == DIVIDE) begin
                shifted_remainder = {div_remainder_q, 1'b0};
                div_shifted_remainder_q <= shifted_remainder;
                div_subtract_q <=
                    shifted_remainder >= {1'b0, divisor_q};
                state_q <= DIVIDE_UPDATE;
            end else if (state_q == DIVIDE_UPDATE) begin
                next_remainder = div_shifted_remainder_q[63:0];
                next_quotient = quotient_q;
                if (div_subtract_q) begin
                    next_remainder =
                        div_shifted_remainder_q - divisor_q;
                    next_quotient[iterations_q-1] = 1'b1;
                end
                div_remainder_q <= next_remainder;
                quotient_q <= next_quotient;
                if (iterations_q == 1) begin
                    if (next_remainder != '0)
                        next_quotient[0] = 1'b1;
                    quotient_q <= next_quotient;
                    final_sqrt_q <= 1'b0;
                    state_q <= FINAL_LOCATE;
                end else begin
                    iterations_q <= iterations_q - 1'b1;
                    state_q <= DIVIDE;
                end
            end else if (state_q == SQUARE_ROOT) begin
                next_pair = radicand_q[127:126];
                radicand_q <= radicand_q << 2;
                sqrt_shifted_remainder =
                    (sqrt_remainder_q << 2) | next_pair;
                sqrt_trial = (sqrt_root_q << 2) | 1'b1;
                sqrt_shifted_remainder_q <= sqrt_shifted_remainder;
                sqrt_trial_q <= sqrt_trial;
                sqrt_subtract_q <=
                    sqrt_shifted_remainder >= sqrt_trial;
                state_q <= SQUARE_ROOT_UPDATE;
            end else if (state_q == SQUARE_ROOT_UPDATE) begin
                sqrt_next_remainder = sqrt_shifted_remainder_q;
                sqrt_next_root = sqrt_root_q << 1;
                if (sqrt_subtract_q) begin
                    sqrt_next_remainder =
                        sqrt_shifted_remainder_q - sqrt_trial_q;
                    sqrt_next_root[0] = 1'b1;
                end
                sqrt_remainder_q <= sqrt_next_remainder;
                sqrt_root_q <= sqrt_next_root;
                if (iterations_q == 1) begin
                    if (sqrt_next_remainder != '0)
                        sqrt_next_root[0] = 1'b1;
                    sqrt_root_q <= sqrt_next_root;
                    final_sqrt_q <= 1'b1;
                    state_q <= FINAL_LOCATE;
                end else begin
                    iterations_q <= iterations_q - 1'b1;
                    state_q <= SQUARE_ROOT;
                end
            end else if (state_q == FINAL_LOCATE) begin
                integer top;
                logic [63:0] final_magnitude;
                final_magnitude =
                    final_sqrt_q ? sqrt_root_q : quotient_q;
                top = msb_index64(final_magnitude);
                final_zero_q <= top < 0;
                final_top_q <= top;
                state_q <= FINAL_EXPONENT;
            end else if (state_q == FINAL_EXPONENT) begin
                integer bias;
                integer emin;
                integer exponent;
                bias = fmt_q ? 1023 : 127;
                emin = 1 - bias;
                exponent = final_top_q + result_exp_q - (bits_q-1);
                final_exponent_q <= exponent;
                if (exponent >= emin)
                    final_discard_q <= final_top_q - (fmt_q ? 52 : 23);
                else
                    final_discard_q <=
                        (emin - (fmt_q ? 52 : 23)) -
                        (result_exp_q - (bits_q-1));
                state_q <= FINAL_SHIFT;
            end else if (state_q == FINAL_SHIFT) begin
                integer index;
                logic [63:0] final_magnitude;
                logic [63:0] main_value;
                logic guard_bit;
                logic sticky_bit;
                final_magnitude =
                    final_sqrt_q ? sqrt_root_q : quotient_q;
                main_value = '0;
                guard_bit = 1'b0;
                sticky_bit = 1'b0;
                if (final_discard_q <= 0)
                    main_value = (-final_discard_q < 64) ?
                        final_magnitude << (-final_discard_q) : '0;
                else if (final_discard_q < 64) begin
                    main_value = final_magnitude >> final_discard_q;
                    guard_bit = final_magnitude[final_discard_q-1];
                    for (index = 0; index < 63; index = index + 1)
                        if (index < final_discard_q-1)
                            sticky_bit = sticky_bit |
                                final_magnitude[index];
                end else if (final_discard_q == 64) begin
                    guard_bit = final_magnitude[63];
                    sticky_bit = |final_magnitude[62:0];
                end else
                    sticky_bit = |final_magnitude;
                final_main_q <= main_value;
                final_guard_q <= guard_bit;
                final_sticky_q <= sticky_bit;
                state_q <= FINAL_ROUND;
            end else if (state_q == FINAL_ROUND) begin
                integer precision;
                integer bias;
                integer emin;
                integer exponent;
                logic [63:0] main_value;
                logic inexact;
                logic increment;
                logic sign;
                main_value = final_main_q;
                inexact = final_guard_q | final_sticky_q;
                sign = final_sqrt_q ? 1'b0 : result_sign_q;
                case (rm_q)
                    RM_RNE: increment = final_guard_q &&
                        (final_sticky_q || main_value[0]);
                    RM_RDN: increment = sign && inexact;
                    RM_RUP: increment = !sign && inexact;
                    RM_RMM: increment = final_guard_q;
                    default: increment = 1'b0;
                endcase
                if (increment)
                    main_value = main_value + 1'b1;
                precision = fmt_q ? 53 : 24;
                bias = fmt_q ? 1023 : 127;
                emin = 1 - bias;
                exponent = final_exponent_q;
                if ((exponent >= emin) && main_value[precision]) begin
                    main_value = main_value >> 1;
                    exponent = exponent + 1;
                end
                rounded_main_q <= main_value;
                rounded_exponent_q <= exponent;
                rounded_inexact_q <= inexact;
                rounded_sign_q <= sign;
                state_q <= FINAL_PACK;
            end else if (state_q == FINAL_PACK) begin
                integer bias;
                integer emin;
                integer emax;
                integer exponent;
                integer exp_field;
                logic [63:0] main_value;
                logic inexact;
                logic to_infinity;
                logic tiny_after;
                logic sign;
                logic [63:0] packed_value;
                main_value = rounded_main_q;
                inexact = rounded_inexact_q;
                sign = rounded_sign_q;
                bias = fmt_q ? 1023 : 127;
                emin = 1 - bias;
                emax = bias;
                exponent = rounded_exponent_q;
                packed_value = '0;
                flags_q <= '0;
                if (final_zero_q)
                    packed_value = fmt_q ? {sign, 63'b0} :
                        box_single({sign, 31'b0});
                else if (exponent >= emin) begin
                    if (exponent > emax) begin
                        to_infinity = (rm_q == RM_RNE) ||
                            (rm_q == RM_RMM) ||
                            ((rm_q == RM_RUP) && !sign) ||
                            ((rm_q == RM_RDN) && sign);
                        if (fmt_q)
                            packed_value = to_infinity ?
                                {sign, 11'h7ff, 52'b0} :
                                {sign, 11'h7fe, 52'hf_ffff_ffff_ffff};
                        else
                            packed_value = box_single(to_infinity ?
                                {sign, 8'hff, 23'b0} :
                                {sign, 8'hfe, 23'h7f_ffff});
                        flags_q[2] <= 1'b1;
                        flags_q[0] <= 1'b1;
                    end else begin
                        exp_field = exponent + bias;
                        if (fmt_q)
                            packed_value = {sign, exp_field[10:0],
                                main_value[51:0]};
                        else
                            packed_value = box_single({sign,
                                exp_field[7:0], main_value[22:0]});
                        flags_q[0] <= inexact;
                    end
                end else begin
                    if (fmt_q ? main_value[52] : main_value[23]) begin
                        if (fmt_q)
                            packed_value = {sign, 11'h001, 52'b0};
                        else
                            packed_value =
                                box_single({sign, 8'h01, 23'b0});
                        tiny_after = 1'b0;
                    end else begin
                        if (fmt_q)
                            packed_value =
                                {sign, 11'h000, main_value[51:0]};
                        else
                            packed_value = box_single({sign,
                                8'h00, main_value[22:0]});
                        tiny_after = 1'b1;
                    end
                    flags_q[1] <= tiny_after && inexact;
                    flags_q[0] <= inexact;
                end
                result_q <= packed_value;
                done_q <= 1'b1;
                state_q <= IDLE;
            end
        end
    end

    assign busy_o = state_q != IDLE;
    assign done_o = done_q;
    assign result_o = result_q;
    assign flags_o = flags_q;
endmodule
