module ydrasil_fpu_fma
    import ydrasil_pkg::*;
    import ydrasil_fpu_math_pkg::*;
(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_i,
    input  ydrasil_fpu_op_t op_i,
    input  wire         fmt_i,
    input  wire         dst_fmt_i,
    input  wire [2:0]   rm_i,
    input  wire [63:0]  operand_a_i,
    input  wire [63:0]  operand_b_i,
    input  wire [63:0]  operand_c_i,
    output wire         busy_o,
    output wire         done_o,
    output wire [63:0]  result_o,
    output wire [4:0]   flags_o
);
    typedef enum logic [4:0] {
        IDLE,
        PRODUCT,
        PRODUCT_COMBINE,
        PRODUCT_COMBINE_2,
        PRODUCT_COMBINE_3,
        PRODUCT_COMBINE_4,
        PRODUCT_LOCATE,
        SCALE,
        PREALIGN,
        ALIGN,
        ALIGN_SHIFT_A,
        ALIGN_SHIFT_B,
        ALIGN_CAPTURE,
        OPERANDS,
        SUM_LOW,
        SUM_HIGH,
        LOCATE_BLOCK,
        LOCATE,
        EXPONENT,
        SHIFT,
        ROUND,
        PACK
    } state_t;

    state_t state_q;
    fp_dec_t a_q;
    fp_dec_t b_q;
    fp_dec_t c_q;
    ydrasil_fpu_op_t op_q;
    reg fmt_q;
    reg [2:0] rm_q;
    reg special_q;
    reg [63:0] special_data_q;
    reg [4:0] special_flags_q;
    reg sign_product_q;
    reg sign_c_q;
    reg [63:0] raw_operand_a_q;
    reg [6:0] source_precision_q;
    reg [6:0] precision_q;
    reg [6:0] frac_bits_q;
    reg signed [15:0] common_scale_q;
    reg signed [15:0] scale_a_q;
    reg signed [15:0] scale_b_q;
    reg signed [15:0] top_common_q;
    reg signed [15:0] align_shift_a_q;
    reg signed [15:0] align_shift_b_q;
    reg signed [15:0] align_remaining_a_q;
    reg signed [15:0] align_remaining_b_q;
    reg align_left_a_q;
    reg align_left_b_q;
    reg [255:0] align_value_a_q;
    reg [255:0] align_value_b_q;
    reg [105:0] product_q;
    reg [47:0] single_product_low_q;
    reg [47:0] single_product_high_q;
    reg [35:0] double_product_00_q;
    reg [35:0] double_product_01_q;
    reg [35:0] double_product_02_q;
    reg [35:0] double_product_10_q;
    reg [35:0] double_product_11_q;
    reg [35:0] double_product_12_q;
    reg [35:0] double_product_20_q;
    reg [35:0] double_product_21_q;
    reg [35:0] double_product_22_q;
    reg [105:0] product_sum0_q;
    reg [105:0] product_sum1_q;
    reg [105:0] product_sum2_q;
    reg [105:0] product_sum3_q;
    reg [105:0] product_sum4_q;
    reg signed [15:0] product_top_q;
    reg [255:0] wide_a_q;
    reg [255:0] wide_b_q;
    reg [255:0] arithmetic_lhs_q;
    reg [255:0] arithmetic_rhs_q;
    reg arithmetic_subtract_q;
    reg [127:0] sum_low_q;
    reg sum_carry_q;
    reg [255:0] magnitude_q;
    reg [4:0] block_top_q [0:7];
    reg [7:0] block_valid_q;
    reg result_sign_q;
    reg signed [15:0] exponent_q;
    reg signed [15:0] discard_q;
    reg signed [15:0] top_q;
    reg zero_q;
    reg [255:0] main_value_q;
    reg guard_q;
    reg sticky_q;
    reg [255:0] rounded_value_q;
    reg signed [15:0] rounded_top_q;
    reg rounded_inexact_q;
    reg done_q;
    reg [63:0] result_q;
    reg [4:0] flags_q;

    fp_dec_t start_a;
    fp_dec_t start_b;
    fp_dec_t start_c;
    reg start_special;
    reg [63:0] start_special_data;
    reg [4:0] start_special_flags;
    reg start_sign_product;
    reg start_sign_c;
    wire start_pack_conversion = (op_i == FPU_OP_CVT_S_W) ||
        (op_i == FPU_OP_CVT_S_WU) ||
        (op_i == FPU_OP_CVT_D_W) ||
        (op_i == FPU_OP_CVT_D_WU) ||
        (op_i == FPU_OP_CVT_S_D) ||
        (op_i == FPU_OP_CVT_D_S);
    wire start_int_to_float = (op_i == FPU_OP_CVT_S_W) ||
        (op_i == FPU_OP_CVT_S_WU) ||
        (op_i == FPU_OP_CVT_D_W) ||
        (op_i == FPU_OP_CVT_D_WU);

    always_comb begin
        start_a = fp_decode(operand_a_i, fmt_i);
        start_b = fp_decode(operand_b_i, fmt_i);
        start_c = fp_decode(operand_c_i, fmt_i);
        start_special = 1'b0;
        start_special_data = '0;
        start_special_flags = '0;
        start_sign_product = start_a.sign ^ start_b.sign;
        start_sign_c = start_c.sign;
        if (op_i == FPU_OP_FNMSUB || op_i == FPU_OP_FNMADD)
            start_sign_product = ~start_sign_product;
        if (op_i == FPU_OP_FMSUB || op_i == FPU_OP_FNMADD)
            start_sign_c = ~start_sign_c;

        if (start_pack_conversion) begin
            if (start_int_to_float) begin
                start_sign_product =
                    !((op_i == FPU_OP_CVT_S_WU) ||
                      (op_i == FPU_OP_CVT_D_WU)) && operand_a_i[31];
            end else begin
                start_sign_product = start_a.sign;
                if (start_a.nan) begin
                    start_special = 1'b1;
                    start_special_data = canonical_nan(dst_fmt_i);
                    start_special_flags[4] = start_a.snan;
                end else if (start_a.inf) begin
                    start_special = 1'b1;
                    start_special_data = dst_fmt_i ?
                        {start_a.sign, 11'h7ff, 52'b0} :
                        box_single({start_a.sign, 8'hff, 23'b0});
                end else if (start_a.zero) begin
                    start_special = 1'b1;
                    start_special_data = dst_fmt_i ?
                        {start_a.sign, 63'b0} :
                        box_single({start_a.sign, 31'b0});
                end
            end
        end else if (op_i == FPU_OP_ADD || op_i == FPU_OP_SUB) begin
            if (start_a.nan || start_b.nan) begin
                start_special = 1'b1;
                start_special_data = canonical_nan(fmt_i);
                start_special_flags[4] = start_a.snan || start_b.snan;
            end else if (start_a.inf && start_b.inf &&
                         (start_a.sign !=
                          (start_b.sign ^ (op_i == FPU_OP_SUB)))) begin
                start_special = 1'b1;
                start_special_data = canonical_nan(fmt_i);
                start_special_flags[4] = 1'b1;
            end else if (start_a.inf) begin
                start_special = 1'b1;
                start_special_data = fmt_i ?
                    {start_a.sign, 11'h7ff, 52'b0} :
                    box_single({start_a.sign, 8'hff, 23'b0});
            end else if (start_b.inf) begin
                start_special = 1'b1;
                start_special_data = fmt_i ?
                    {start_b.sign ^ (op_i == FPU_OP_SUB), 11'h7ff, 52'b0} :
                    box_single({start_b.sign ^ (op_i == FPU_OP_SUB),
                                8'hff, 23'b0});
            end
        end else begin
            if (start_a.nan || start_b.nan ||
                ((op_i != FPU_OP_MUL) && start_c.nan)) begin
                start_special = 1'b1;
                start_special_data = canonical_nan(fmt_i);
                start_special_flags[4] = start_a.snan || start_b.snan ||
                    ((op_i != FPU_OP_MUL) && start_c.snan);
            end else if ((start_a.inf && start_b.zero) ||
                         (start_a.zero && start_b.inf)) begin
                start_special = 1'b1;
                start_special_data = canonical_nan(fmt_i);
                start_special_flags[4] = 1'b1;
            end else if ((op_i != FPU_OP_MUL) &&
                         (start_a.inf || start_b.inf) && start_c.inf &&
                         (start_sign_product != start_sign_c)) begin
                start_special = 1'b1;
                start_special_data = canonical_nan(fmt_i);
                start_special_flags[4] = 1'b1;
            end else if (start_a.inf || start_b.inf) begin
                start_special = 1'b1;
                start_special_data = fmt_i ?
                    {start_sign_product, 11'h7ff, 52'b0} :
                    box_single({start_sign_product, 8'hff, 23'b0});
            end else if ((op_i != FPU_OP_MUL) && start_c.inf) begin
                start_special = 1'b1;
                start_special_data = fmt_i ?
                    {start_sign_c, 11'h7ff, 52'b0} :
                    box_single({start_sign_c, 8'hff, 23'b0});
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        integer scale_a;
        integer scale_b;
        integer scale_c;
        integer scale_product;
        integer top_a;
        integer top_b;
        integer top_common;
        integer top;
        integer discard;
        integer bias;
        integer emin;
        integer emax;
        integer exp_field;
        integer index;
        logic sign_a;
        logic sign_b;
        logic [128:0] partial_sum;
        logic [255:0] magnitude_next;
        logic [255:0] main_value;
        logic guard_bit;
        logic sticky_bit;
        logic inexact;
        logic increment;
        logic to_infinity;
        logic tiny_after;
        logic [63:0] packed_value;
        if (!rst_n) begin
            state_q <= IDLE;
            a_q <= '0;
            b_q <= '0;
            c_q <= '0;
            op_q <= FPU_OP_ADD;
            fmt_q <= 1'b0;
            rm_q <= '0;
            special_q <= 1'b0;
            special_data_q <= '0;
            special_flags_q <= '0;
            sign_product_q <= 1'b0;
            sign_c_q <= 1'b0;
            raw_operand_a_q <= '0;
            source_precision_q <= '0;
            precision_q <= '0;
            frac_bits_q <= '0;
            common_scale_q <= '0;
            scale_a_q <= '0;
            scale_b_q <= '0;
            top_common_q <= '0;
            align_shift_a_q <= '0;
            align_shift_b_q <= '0;
            align_remaining_a_q <= '0;
            align_remaining_b_q <= '0;
            align_left_a_q <= 1'b0;
            align_left_b_q <= 1'b0;
            align_value_a_q <= '0;
            align_value_b_q <= '0;
            product_q <= '0;
            single_product_low_q <= '0;
            single_product_high_q <= '0;
            double_product_00_q <= '0;
            double_product_01_q <= '0;
            double_product_02_q <= '0;
            double_product_10_q <= '0;
            double_product_11_q <= '0;
            double_product_12_q <= '0;
            double_product_20_q <= '0;
            double_product_21_q <= '0;
            double_product_22_q <= '0;
            product_sum0_q <= '0;
            product_sum1_q <= '0;
            product_sum2_q <= '0;
            product_sum3_q <= '0;
            product_sum4_q <= '0;
            product_top_q <= '0;
            wide_a_q <= '0;
            wide_b_q <= '0;
            arithmetic_lhs_q <= '0;
            arithmetic_rhs_q <= '0;
            arithmetic_subtract_q <= 1'b0;
            sum_low_q <= '0;
            sum_carry_q <= 1'b0;
            magnitude_q <= '0;
            block_top_q[0] <= '0;
            block_top_q[1] <= '0;
            block_top_q[2] <= '0;
            block_top_q[3] <= '0;
            block_top_q[4] <= '0;
            block_top_q[5] <= '0;
            block_top_q[6] <= '0;
            block_top_q[7] <= '0;
            block_valid_q <= '0;
            result_sign_q <= 1'b0;
            exponent_q <= '0;
            discard_q <= '0;
            top_q <= '0;
            zero_q <= 1'b0;
            main_value_q <= '0;
            guard_q <= 1'b0;
            sticky_q <= 1'b0;
            rounded_value_q <= '0;
            rounded_top_q <= '0;
            rounded_inexact_q <= 1'b0;
            done_q <= 1'b0;
            result_q <= '0;
            flags_q <= '0;
        end else begin
            done_q <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    a_q <= start_a;
                    b_q <= start_b;
                    c_q <= start_c;
                    op_q <= op_i;
                    fmt_q <= start_pack_conversion ? dst_fmt_i : fmt_i;
                    rm_q <= rm_i;
                    special_q <= start_special;
                    special_data_q <= start_special_data;
                    special_flags_q <= start_special_flags;
                    sign_product_q <= start_sign_product;
                    sign_c_q <= start_sign_c;
                    raw_operand_a_q <= operand_a_i;
                    source_precision_q <= fmt_i ? 7'd53 : 7'd24;
                    precision_q <= (start_pack_conversion ?
                        dst_fmt_i : fmt_i) ? 7'd53 : 7'd24;
                    frac_bits_q <= (start_pack_conversion ?
                        dst_fmt_i : fmt_i) ? 7'd52 : 7'd23;
                    state_q <= PRODUCT;
                end
                PRODUCT: begin
                    if (op_q == FPU_OP_CVT_S_W ||
                        op_q == FPU_OP_CVT_S_WU ||
                        op_q == FPU_OP_CVT_D_W ||
                        op_q == FPU_OP_CVT_D_WU ||
                        op_q == FPU_OP_CVT_S_D ||
                        op_q == FPU_OP_CVT_D_S) begin
                        product_q <= '0;
                        state_q <= PRODUCT_LOCATE;
                    end else
`ifdef YDRASIL_FPU_DOUBLE
                        begin
                            double_product_00_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[17:0] *
                                b_q.significand[17:0];
                            double_product_01_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[17:0] *
                                b_q.significand[35:18];
                            double_product_02_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[17:0] *
                                b_q.significand[52:36];
                            double_product_10_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[35:18] *
                                b_q.significand[17:0];
                            double_product_11_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[35:18] *
                                b_q.significand[35:18];
                            double_product_12_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[35:18] *
                                b_q.significand[52:36];
                            double_product_20_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[52:36] *
                                b_q.significand[17:0];
                            double_product_21_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[52:36] *
                                b_q.significand[35:18];
                            double_product_22_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[52:36] *
                                b_q.significand[52:36];
                            state_q <= PRODUCT_COMBINE;
                        end
`else
                        begin
                            single_product_low_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[23:0] *
                                b_q.significand[16:0];
                            single_product_high_q <=
                                (a_q.zero || b_q.zero) ? '0 :
                                a_q.significand[23:0] *
                                b_q.significand[23:17];
                            state_q <= PRODUCT_COMBINE;
                        end
`endif
                end
                PRODUCT_COMBINE: begin
`ifdef YDRASIL_FPU_DOUBLE
                    product_sum0_q <= {70'b0, double_product_00_q} +
                        {52'b0, double_product_01_q, 18'b0};
                    product_sum1_q <=
                        {52'b0, double_product_10_q, 18'b0} +
                        {34'b0, double_product_11_q, 36'b0};
                    product_sum2_q <=
                        {34'b0, double_product_02_q, 36'b0} +
                        {34'b0, double_product_20_q, 36'b0};
                    product_sum3_q <=
                        {16'b0, double_product_12_q, 54'b0} +
                        {16'b0, double_product_21_q, 54'b0};
                    product_sum4_q <=
                        {double_product_22_q[33:0], 72'b0};
                    state_q <= PRODUCT_COMBINE_2;
`else
                    product_q <= {58'b0, single_product_low_q +
                        (single_product_high_q << 17)};
                    state_q <= PRODUCT_LOCATE;
`endif
                end
                PRODUCT_COMBINE_2: begin
                    product_sum0_q <= product_sum0_q + product_sum1_q;
                    product_sum1_q <= product_sum2_q + product_sum3_q;
                    product_sum2_q <= product_sum4_q;
                    state_q <= PRODUCT_COMBINE_3;
                end
                PRODUCT_COMBINE_3: begin
                    product_sum0_q <= product_sum0_q + product_sum1_q;
                    product_sum1_q <= product_sum2_q;
                    state_q <= PRODUCT_COMBINE_4;
                end
                PRODUCT_COMBINE_4: begin
                    product_q <= product_sum0_q + product_sum1_q;
                    state_q <= PRODUCT_LOCATE;
                end
                PRODUCT_LOCATE: begin
                    product_top_q <= msb_index({150'b0, product_q});
                    state_q <= SCALE;
                end
                SCALE: begin
                    if (op_q == FPU_OP_CVT_S_W ||
                        op_q == FPU_OP_CVT_S_WU ||
                        op_q == FPU_OP_CVT_D_W ||
                        op_q == FPU_OP_CVT_D_WU) begin
                        scale_a_q <= '0;
                        scale_b_q <= '0;
                        top_common_q <= '0;
                    end else if (op_q == FPU_OP_CVT_S_D ||
                                 op_q == FPU_OP_CVT_D_S) begin
                        scale_a_q <= a_q.exponent -
                            (source_precision_q-1);
                        scale_b_q <= '0;
                        top_common_q <= '0;
                    end else if (op_q == FPU_OP_ADD ||
                                 op_q == FPU_OP_SUB) begin
                        scale_a = a_q.exponent - (precision_q-1);
                        scale_b = b_q.exponent - (precision_q-1);
                        top_common = a_q.zero ? b_q.exponent :
                            b_q.zero ? a_q.exponent :
                            (a_q.exponent > b_q.exponent ?
                             a_q.exponent : b_q.exponent);
                        scale_a_q <= scale_a;
                        scale_b_q <= scale_b;
                        top_common_q <= top_common;
                    end else begin
                        scale_product = a_q.exponent + b_q.exponent -
                            2*(precision_q-1);
                        top_a = product_q == '0 ? -32768 :
                            scale_product + product_top_q;
                        scale_c = c_q.exponent - (precision_q-1);
                        top_b = c_q.zero ? -32768 : c_q.exponent;
                        top_common = op_q == FPU_OP_MUL ? top_a :
                            (top_a > top_b ? top_a : top_b);
                        scale_a_q <= scale_product;
                        scale_b_q <= scale_c;
                        top_common_q <= top_common;
                    end
                    state_q <= PREALIGN;
                end
                PREALIGN: begin
                    if (op_q == FPU_OP_CVT_S_W ||
                        op_q == FPU_OP_CVT_S_WU ||
                        op_q == FPU_OP_CVT_D_W ||
                        op_q == FPU_OP_CVT_D_WU) begin
                        common_scale_q <= '0;
                        align_shift_a_q <= '0;
                        align_shift_b_q <= '0;
                    end else if (op_q == FPU_OP_CVT_S_D ||
                                 op_q == FPU_OP_CVT_D_S) begin
                        common_scale_q <= scale_a_q;
                        align_shift_a_q <= '0;
                        align_shift_b_q <= '0;
                    end else begin
                        align_shift_a_q <=
                            16'sd180 + scale_a_q - top_common_q;
                        align_shift_b_q <=
                            16'sd180 + scale_b_q - top_common_q;
                        common_scale_q <= top_common_q - 16'sd180;
                    end
                    state_q <= ALIGN;
                end
                ALIGN: begin
                    align_value_a_q <= '0;
                    align_value_b_q <= '0;
                    align_remaining_a_q <= '0;
                    align_remaining_b_q <= '0;
                    align_left_a_q <= align_shift_a_q >= 0;
                    align_left_b_q <= align_shift_b_q >= 0;
                    if (op_q == FPU_OP_CVT_S_W ||
                        op_q == FPU_OP_CVT_S_WU ||
                        op_q == FPU_OP_CVT_D_W ||
                        op_q == FPU_OP_CVT_D_WU) begin
                        align_value_a_q <= sign_product_q ?
                            {224'b0, (~raw_operand_a_q[31:0] + 1'b1)} :
                            {224'b0, raw_operand_a_q[31:0]};
                    end else if (op_q == FPU_OP_CVT_S_D ||
                                 op_q == FPU_OP_CVT_D_S) begin
                        align_value_a_q <= {203'b0, a_q.significand};
                    end else if (op_q == FPU_OP_ADD ||
                                 op_q == FPU_OP_SUB) begin
                        align_value_a_q <= a_q.zero ? '0 :
                            {203'b0, a_q.significand};
                        align_value_b_q <= b_q.zero ? '0 :
                            {203'b0, b_q.significand};
                        align_remaining_a_q <=
                            (align_shift_a_q > 16'sd255 ||
                             align_shift_a_q < -16'sd255) ? 16'sd256 :
                            (align_shift_a_q < 0 ?
                             -align_shift_a_q : align_shift_a_q);
                        align_remaining_b_q <=
                            (align_shift_b_q > 16'sd255 ||
                             align_shift_b_q < -16'sd255) ? 16'sd256 :
                            (align_shift_b_q < 0 ?
                             -align_shift_b_q : align_shift_b_q);
                    end else begin
                        align_value_a_q <= product_q == '0 ? '0 :
                            {150'b0, product_q};
                        align_value_b_q <=
                            (op_q == FPU_OP_MUL || c_q.zero) ? '0 :
                            {203'b0, c_q.significand};
                        align_remaining_a_q <=
                            (align_shift_a_q > 16'sd255 ||
                             align_shift_a_q < -16'sd255) ? 16'sd256 :
                            (align_shift_a_q < 0 ?
                             -align_shift_a_q : align_shift_a_q);
                        align_remaining_b_q <=
                            (align_shift_b_q > 16'sd255 ||
                             align_shift_b_q < -16'sd255) ? 16'sd256 :
                            (align_shift_b_q < 0 ?
                             -align_shift_b_q : align_shift_b_q);
                    end
                    state_q <= ALIGN_SHIFT_A;
                end
                ALIGN_SHIFT_A: begin
                    if (align_remaining_a_q == 0) begin
                        state_q <= ALIGN_SHIFT_B;
                    end else begin
                        align_remaining_a_q <= align_remaining_a_q - 1'b1;
                        if (align_left_a_q)
                            align_value_a_q <=
                                {align_value_a_q[254:0], 1'b0};
                        else
                            align_value_a_q <=
                                {1'b0, align_value_a_q[255:2],
                                 align_value_a_q[1] |
                                 align_value_a_q[0]};
                    end
                end
                ALIGN_SHIFT_B: begin
                    if (align_remaining_b_q == 0) begin
                        state_q <= ALIGN_CAPTURE;
                    end else begin
                        align_remaining_b_q <= align_remaining_b_q - 1'b1;
                        if (align_left_b_q)
                            align_value_b_q <=
                                {align_value_b_q[254:0], 1'b0};
                        else
                            align_value_b_q <=
                                {1'b0, align_value_b_q[255:2],
                                 align_value_b_q[1] |
                                 align_value_b_q[0]};
                    end
                end
                ALIGN_CAPTURE: begin
                    wide_a_q <= align_value_a_q;
                    wide_b_q <= align_value_b_q;
                    state_q <= OPERANDS;
                end
                OPERANDS: begin
                    if (op_q == FPU_OP_ADD || op_q == FPU_OP_SUB) begin
                        sign_a = a_q.sign;
                        sign_b = b_q.sign ^ (op_q == FPU_OP_SUB);
                    end else begin
                        sign_a = sign_product_q;
                        sign_b = sign_c_q;
                    end
                    arithmetic_subtract_q <= sign_a != sign_b;
                    if ((sign_a == sign_b) || (wide_a_q >= wide_b_q)) begin
                        arithmetic_lhs_q <= wide_a_q;
                        arithmetic_rhs_q <= wide_b_q;
                        result_sign_q <= sign_a;
                    end else begin
                        arithmetic_lhs_q <= wide_b_q;
                        arithmetic_rhs_q <= wide_a_q;
                        result_sign_q <= sign_b;
                    end
                    state_q <= SUM_LOW;
                end
                SUM_LOW: begin
                    partial_sum =
                        {1'b0, arithmetic_lhs_q[127:0]} +
                        {1'b0, arithmetic_subtract_q ?
                            ~arithmetic_rhs_q[127:0] :
                            arithmetic_rhs_q[127:0]} +
                        arithmetic_subtract_q;
                    sum_low_q <= partial_sum[127:0];
                    sum_carry_q <= partial_sum[128];
                    state_q <= SUM_HIGH;
                end
                SUM_HIGH: begin
                    partial_sum =
                        {1'b0, arithmetic_lhs_q[255:128]} +
                        {1'b0, arithmetic_subtract_q ?
                            ~arithmetic_rhs_q[255:128] :
                            arithmetic_rhs_q[255:128]} +
                        sum_carry_q;
                    magnitude_next = {partial_sum[127:0], sum_low_q};
                    magnitude_q <= magnitude_next;
                    if (magnitude_next == '0) begin
                        if (op_q == FPU_OP_ADD || op_q == FPU_OP_SUB)
                            result_sign_q <=
                                (a_q.sign ==
                                 (b_q.sign ^ (op_q == FPU_OP_SUB))) ?
                                a_q.sign : (rm_q == RM_RDN);
                        else if (op_q != FPU_OP_MUL)
                            result_sign_q <=
                                (sign_product_q == sign_c_q) ?
                                sign_product_q : (rm_q == RM_RDN);
                        else
                            result_sign_q <= sign_product_q;
                    end
                    state_q <= LOCATE_BLOCK;
                end
                LOCATE_BLOCK: begin
                    block_top_q[0] <= msb_index32(magnitude_q[31:0]);
                    block_top_q[1] <= msb_index32(magnitude_q[63:32]);
                    block_top_q[2] <= msb_index32(magnitude_q[95:64]);
                    block_top_q[3] <= msb_index32(magnitude_q[127:96]);
                    block_top_q[4] <= msb_index32(magnitude_q[159:128]);
                    block_top_q[5] <= msb_index32(magnitude_q[191:160]);
                    block_top_q[6] <= msb_index32(magnitude_q[223:192]);
                    block_top_q[7] <= msb_index32(magnitude_q[255:224]);
                    block_valid_q[0] <= |magnitude_q[31:0];
                    block_valid_q[1] <= |magnitude_q[63:32];
                    block_valid_q[2] <= |magnitude_q[95:64];
                    block_valid_q[3] <= |magnitude_q[127:96];
                    block_valid_q[4] <= |magnitude_q[159:128];
                    block_valid_q[5] <= |magnitude_q[191:160];
                    block_valid_q[6] <= |magnitude_q[223:192];
                    block_valid_q[7] <= |magnitude_q[255:224];
                    state_q <= LOCATE;
                end
                LOCATE: begin
                    if (block_valid_q[7])
                        top = 224 + block_top_q[7];
                    else if (block_valid_q[6])
                        top = 192 + block_top_q[6];
                    else if (block_valid_q[5])
                        top = 160 + block_top_q[5];
                    else if (block_valid_q[4])
                        top = 128 + block_top_q[4];
                    else if (block_valid_q[3])
                        top = 96 + block_top_q[3];
                    else if (block_valid_q[2])
                        top = 64 + block_top_q[2];
                    else if (block_valid_q[1])
                        top = 32 + block_top_q[1];
                    else if (block_valid_q[0])
                        top = block_top_q[0];
                    else
                        top = -1;
                    zero_q <= top < 0;
                    top_q <= top;
                    state_q <= EXPONENT;
                end
                EXPONENT: begin
                    bias = fmt_q ? 1023 : 127;
                    emin = 1 - bias;
                    exponent_q <= top_q + $signed(common_scale_q);
                    if ((top_q + $signed(common_scale_q)) >= emin)
                        discard = top_q - frac_bits_q;
                    else
                        discard = (emin - frac_bits_q) -
                            $signed(common_scale_q);
                    discard_q <= discard;
                    state_q <= SHIFT;
                end
                SHIFT: begin
                    main_value = '0;
                    guard_bit = 1'b0;
                    sticky_bit = 1'b0;
                    if (discard_q <= 0)
                        main_value = (-discard_q < 256) ?
                            magnitude_q << (-discard_q) : '0;
                    else if (discard_q < 256) begin
                        main_value = magnitude_q >> discard_q;
                        guard_bit = magnitude_q[discard_q-1];
                        for (index = 0; index < 255; index = index + 1)
                            if (index < discard_q-1)
                                sticky_bit = sticky_bit |
                                    magnitude_q[index];
                    end else if (discard_q == 256) begin
                        guard_bit = magnitude_q[255];
                        sticky_bit = |magnitude_q[254:0];
                    end else
                        sticky_bit = |magnitude_q;
                    main_value_q <= main_value;
                    guard_q <= guard_bit;
                    sticky_q <= sticky_bit;
                    state_q <= ROUND;
                end
                ROUND: begin
                    rounded_value_q <= main_value_q;
                    rounded_top_q <= exponent_q;
                    rounded_inexact_q <= guard_q | sticky_q;
                    if (!special_q && !zero_q) begin
                        main_value = main_value_q;
                        inexact = guard_q | sticky_q;
                        case (rm_q)
                            RM_RNE: increment = guard_q &&
                                (sticky_q || main_value[0]);
                            RM_RDN: increment = result_sign_q && inexact;
                            RM_RUP: increment = !result_sign_q && inexact;
                            RM_RMM: increment = guard_q;
                            default: increment = 1'b0;
                        endcase
                        if (increment)
                            main_value = main_value + 1'b1;
                        bias = fmt_q ? 1023 : 127;
                        emin = 1 - bias;
                        top = exponent_q;
                        if ((top >= emin) && main_value[precision_q]) begin
                            main_value = main_value >> 1;
                            top = top + 1;
                        end
                        rounded_value_q <= main_value;
                        rounded_top_q <= top;
                        rounded_inexact_q <= inexact;
                    end
                    state_q <= PACK;
                end
                PACK: begin
                    packed_value = '0;
                    flags_q <= '0;
                    if (special_q) begin
                        result_q <= special_data_q;
                        flags_q <= special_flags_q;
                    end else if (zero_q) begin
                        result_q <= fmt_q ? {result_sign_q, 63'b0} :
                            box_single({result_sign_q, 31'b0});
                    end else begin
                        main_value = rounded_value_q;
                        inexact = rounded_inexact_q;
                        bias = fmt_q ? 1023 : 127;
                        emin = 1 - bias;
                        emax = bias;
                        top = rounded_top_q;
                        if (top >= emin) begin
                            if (top > emax) begin
                                to_infinity = (rm_q == RM_RNE) ||
                                    (rm_q == RM_RMM) ||
                                    ((rm_q == RM_RUP) && !result_sign_q) ||
                                    ((rm_q == RM_RDN) && result_sign_q);
                                if (fmt_q)
                                    packed_value = to_infinity ?
                                        {result_sign_q, 11'h7ff, 52'b0} :
                                        {result_sign_q, 11'h7fe,
                                         52'hf_ffff_ffff_ffff};
                                else
                                    packed_value = box_single(to_infinity ?
                                        {result_sign_q, 8'hff, 23'b0} :
                                        {result_sign_q, 8'hfe, 23'h7f_ffff});
                                flags_q[2] <= 1'b1;
                                flags_q[0] <= 1'b1;
                            end else begin
                                exp_field = top + bias;
                                if (fmt_q)
                                    packed_value = {result_sign_q,
                                        exp_field[10:0],
                                        main_value[51:0]};
                                else
                                    packed_value = box_single({
                                        result_sign_q, exp_field[7:0],
                                        main_value[22:0]});
                                flags_q[0] <= inexact;
                            end
                        end else begin
                            if (main_value[frac_bits_q]) begin
                                if (fmt_q)
                                    packed_value =
                                        {result_sign_q, 11'h001, 52'b0};
                                else
                                    packed_value = box_single(
                                        {result_sign_q, 8'h01, 23'b0});
                                tiny_after = 1'b0;
                            end else begin
                                if (fmt_q)
                                    packed_value = {result_sign_q,
                                        11'h000, main_value[51:0]};
                                else
                                    packed_value = box_single({
                                        result_sign_q, 8'h00,
                                        main_value[22:0]});
                                tiny_after = 1'b1;
                            end
                            flags_q[1] <= tiny_after && inexact;
                            flags_q[0] <= inexact;
                        end
                        result_q <= packed_value;
                    end
                    done_q <= 1'b1;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end

    assign busy_o = state_q != IDLE;
    assign done_o = done_q;
    assign result_o = result_q;
    assign flags_o = flags_q;
endmodule
