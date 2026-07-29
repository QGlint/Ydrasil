package ydrasil_fpu_math_pkg;
    import ydrasil_pkg::*;

    localparam logic [2:0] RM_RNE = 3'b000;
    localparam logic [2:0] RM_RTZ = 3'b001;
    localparam logic [2:0] RM_RDN = 3'b010;
    localparam logic [2:0] RM_RUP = 3'b011;
    localparam logic [2:0] RM_RMM = 3'b100;

    typedef struct packed {
        logic sign;
        logic zero;
        logic subnormal;
        logic inf;
        logic nan;
        logic snan;
        logic signed [15:0] exponent;
        logic [52:0] significand;
    } fp_dec_t;

    typedef struct packed {
        logic [63:0] data;
        logic [4:0] flags;
    } fp_result_t;

    function automatic logic [63:0] canonical_nan(input logic fmt);
        canonical_nan = fmt ? 64'h7ff8_0000_0000_0000 :
            64'hffff_ffff_7fc0_0000;
    endfunction

    function automatic logic [63:0] box_single(input logic [31:0] value);
        box_single = {32'hffff_ffff, value};
    endfunction

    function automatic fp_dec_t fp_decode(
        input logic [63:0] raw,
        input logic fmt
    );
        fp_dec_t value;
        logic [10:0] exp_field;
        logic [51:0] frac_field;
        integer frac_bits;
        integer bias;
        begin
            value = '0;
            frac_bits = fmt ? 52 : 23;
            bias = fmt ? 1023 : 127;
            if (!fmt && raw[63:32] != 32'hffff_ffff) begin
                value.nan = 1'b1;
                value.significand = 53'h1_8000_0000_0000;
            end else begin
                value.sign = fmt ? raw[63] : raw[31];
                exp_field = fmt ? raw[62:52] : {3'b000, raw[30:23]};
                frac_field = fmt ? raw[51:0] : {29'b0, raw[22:0]};
                value.zero = (exp_field == '0) && (frac_field == '0);
                value.subnormal = (exp_field == '0) && (frac_field != '0);
                value.inf = fmt ? ((exp_field == 11'h7ff) && (frac_field == '0)) :
                    ((exp_field[7:0] == 8'hff) && (frac_field == '0));
                value.nan = fmt ? ((exp_field == 11'h7ff) && (frac_field != '0)) :
                    ((exp_field[7:0] == 8'hff) && (frac_field != '0));
                value.snan = value.nan && !frac_field[frac_bits-1];
                if (!value.zero && !value.inf && !value.nan) begin
                    if (exp_field != '0) begin
                        value.exponent = $signed({1'b0, exp_field}) - bias;
                        value.significand = fmt ? {1'b1, frac_field} :
                            {29'b0, 1'b1, frac_field[22:0]};
                    end else begin
                        value.significand = frac_field;
                        value.exponent = 1 - bias;
                    end
                end
            end
            fp_decode = value;
        end
    endfunction

    function automatic logic [2:0] msb_index8(input logic [7:0] value);
        begin
            if (|value[7:4]) begin
                if (|value[7:6])
                    msb_index8 = value[7] ? 3'd7 : 3'd6;
                else
                    msb_index8 = value[5] ? 3'd5 : 3'd4;
            end else begin
                if (|value[3:2])
                    msb_index8 = value[3] ? 3'd3 : 3'd2;
                else
                    msb_index8 = value[1] ? 3'd1 : 3'd0;
            end
        end
    endfunction

    function automatic logic [4:0] msb_index32(input logic [31:0] value);
        logic [3:0] group_valid;
        logic [1:0] group_index;
        logic [7:0] selected_group;
        begin
            group_valid = {
                |value[31:24], |value[23:16],
                |value[15:8], |value[7:0]
            };
            if (|group_valid[3:2])
                group_index = group_valid[3] ? 2'd3 : 2'd2;
            else
                group_index = group_valid[1] ? 2'd1 : 2'd0;
            case (group_index)
                2'd3: selected_group = value[31:24];
                2'd2: selected_group = value[23:16];
                2'd1: selected_group = value[15:8];
                default: selected_group = value[7:0];
            endcase
            msb_index32 = {group_index, msb_index8(selected_group)};
        end
    endfunction

    function automatic integer msb_index64(input logic [63:0] value);
        logic upper_valid;
        logic [31:0] selected_half;
        begin
            if (value == '0)
                msb_index64 = -1;
            else begin
                upper_valid = |value[63:32];
                selected_half = upper_valid ? value[63:32] : value[31:0];
                msb_index64 = {upper_valid, msb_index32(selected_half)};
            end
        end
    endfunction

    function automatic integer msb_index(input logic [255:0] value);
        logic [7:0] group_valid;
        logic [2:0] group_index;
        logic [31:0] selected_group;
        begin
            group_valid = {
                |value[255:224], |value[223:192],
                |value[191:160], |value[159:128],
                |value[127:96], |value[95:64],
                |value[63:32], |value[31:0]
            };
            if (value == '0)
                msb_index = -1;
            else begin
                group_index = msb_index8(group_valid);
                case (group_index)
                    3'd7: selected_group = value[255:224];
                    3'd6: selected_group = value[223:192];
                    3'd5: selected_group = value[191:160];
                    3'd4: selected_group = value[159:128];
                    3'd3: selected_group = value[127:96];
                    3'd2: selected_group = value[95:64];
                    3'd1: selected_group = value[63:32];
                    default: selected_group = value[31:0];
                endcase
                msb_index = {group_index, msb_index32(selected_group)};
            end
        end
    endfunction

    function automatic logic [255:0] shift_with_sticky(
        input logic [255:0] value,
        input integer amount
    );
        logic [255:0] shifted;
        logic sticky;
        integer index;
        begin
            shifted = '0;
            sticky = 1'b0;
            if (amount >= 0) begin
                shifted = amount < 256 ? value << amount : '0;
            end else if (-amount >= 256) begin
                shifted[0] = |value;
            end else begin
                shifted = value >> (-amount);
                for (index = 0; index < 256; index = index + 1)
                    if (index < (-amount))
                        sticky = sticky | value[index];
                shifted[0] = shifted[0] | sticky;
            end
            shift_with_sticky = shifted;
        end
    endfunction

    function automatic fp_result_t round_pack(
        input logic [255:0] magnitude,
        input logic signed [15:0] scale,
        input logic sign,
        input logic fmt,
        input logic [2:0] rm
    );
        fp_result_t result;
        logic [255:0] main_value;
        logic guard_bit;
        logic sticky_bit;
        logic inexact;
        logic increment;
        logic to_infinity;
        logic tiny_after;
        logic [63:0] packed_value;
        integer precision;
        integer frac_bits;
        integer bias;
        integer emin;
        integer emax;
        integer top;
        integer exponent;
        integer discard;
        integer index;
        integer exp_field;
        begin
            result = '0;
            packed_value = '0;
            precision = fmt ? 53 : 24;
            frac_bits = precision - 1;
            bias = fmt ? 1023 : 127;
            emin = 1 - bias;
            emax = bias;
            top = msb_index(magnitude);
            if (top < 0) begin
                packed_value = fmt ? {sign, 63'b0} :
                    box_single({sign, 31'b0});
            end else begin
                exponent = top + $signed(scale);
                if (exponent >= emin)
                    discard = top - frac_bits;
                else
                    discard = (emin - frac_bits) - $signed(scale);

                main_value = '0;
                guard_bit = 1'b0;
                sticky_bit = 1'b0;
                if (discard <= 0) begin
                    main_value = (-discard < 256) ?
                        magnitude << (-discard) : '0;
                end else if (discard < 256) begin
                    main_value = magnitude >> discard;
                    guard_bit = magnitude[discard-1];
                    for (index = 0; index < 255; index = index + 1)
                        if (index < discard-1)
                            sticky_bit = sticky_bit | magnitude[index];
                end else if (discard == 256) begin
                    guard_bit = magnitude[255];
                    sticky_bit = |magnitude[254:0];
                end else begin
                    sticky_bit = |magnitude;
                end
                inexact = guard_bit | sticky_bit;
                unique case (rm)
                    RM_RNE: increment = guard_bit && (sticky_bit || main_value[0]);
                    RM_RDN: increment = sign && inexact;
                    RM_RUP: increment = !sign && inexact;
                    RM_RMM: increment = guard_bit;
                    default: increment = 1'b0;
                endcase
                if (increment)
                    main_value = main_value + 1'b1;

                if (exponent >= emin) begin
                    if (main_value[precision]) begin
                        main_value = main_value >> 1;
                        exponent = exponent + 1;
                    end
                    if (exponent > emax) begin
                        to_infinity = (rm == RM_RNE) || (rm == RM_RMM) ||
                            ((rm == RM_RUP) && !sign) ||
                            ((rm == RM_RDN) && sign);
                        if (fmt)
                            packed_value = to_infinity ?
                                {sign, 11'h7ff, 52'b0} :
                                {sign, 11'h7fe, 52'hf_ffff_ffff_ffff};
                        else
                            packed_value = box_single(to_infinity ?
                                {sign, 8'hff, 23'b0} :
                                {sign, 8'hfe, 23'h7f_ffff});
                        result.flags[2] = 1'b1;
                        result.flags[0] = 1'b1;
                    end else begin
                        exp_field = exponent + bias;
                        if (fmt)
                            packed_value = {sign, exp_field[10:0],
                                main_value[51:0]};
                        else
                            packed_value = box_single({sign, exp_field[7:0],
                                main_value[22:0]});
                        result.flags[0] = inexact;
                    end
                end else begin
                    if (main_value[frac_bits]) begin
                        if (fmt)
                            packed_value = {sign, 11'h001, 52'b0};
                        else
                            packed_value = box_single({sign, 8'h01, 23'b0});
                        tiny_after = 1'b0;
                    end else begin
                        if (fmt)
                            packed_value = {sign, 11'h000, main_value[51:0]};
                        else
                            packed_value = box_single({sign, 8'h00,
                                main_value[22:0]});
                        tiny_after = 1'b1;
                    end
                    result.flags[1] = tiny_after && inexact;
                    result.flags[0] = inexact;
                end
            end
            result.data = packed_value;
            round_pack = result;
        end
    endfunction

    function automatic fp_result_t round_pack64(
        input logic [63:0] magnitude,
        input logic signed [15:0] scale,
        input logic sign,
        input logic fmt,
        input logic [2:0] rm
    );
        fp_result_t result;
        logic [63:0] main_value;
        logic guard_bit;
        logic sticky_bit;
        logic inexact;
        logic increment;
        logic to_infinity;
        logic tiny_after;
        logic [63:0] packed_value;
        integer precision;
        integer frac_bits;
        integer bias;
        integer emin;
        integer emax;
        integer top;
        integer exponent;
        integer discard;
        integer index;
        integer found;
        integer exp_field;
        begin
            result = '0;
            packed_value = '0;
            precision = fmt ? 53 : 24;
            frac_bits = precision - 1;
            bias = fmt ? 1023 : 127;
            emin = 1 - bias;
            emax = bias;
            top = -1;
            found = 0;
            for (index = 63; index >= 0; index = index - 1)
                if (!found && magnitude[index]) begin
                    top = index;
                    found = 1;
                end
            if (top < 0)
                packed_value = fmt ? {sign, 63'b0} :
                    box_single({sign, 31'b0});
            else begin
                exponent = top + $signed(scale);
                if (exponent >= emin)
                    discard = top - frac_bits;
                else
                    discard = (emin - frac_bits) - $signed(scale);
                main_value = '0;
                guard_bit = 1'b0;
                sticky_bit = 1'b0;
                if (discard <= 0)
                    main_value = (-discard < 64) ?
                        magnitude << (-discard) : '0;
                else if (discard < 64) begin
                    main_value = magnitude >> discard;
                    guard_bit = magnitude[discard-1];
                    for (index = 0; index < 63; index = index + 1)
                        if (index < discard-1)
                            sticky_bit = sticky_bit | magnitude[index];
                end else if (discard == 64) begin
                    guard_bit = magnitude[63];
                    sticky_bit = |magnitude[62:0];
                end else
                    sticky_bit = |magnitude;
                inexact = guard_bit | sticky_bit;
                case (rm)
                    RM_RNE: increment = guard_bit &&
                        (sticky_bit || main_value[0]);
                    RM_RDN: increment = sign && inexact;
                    RM_RUP: increment = !sign && inexact;
                    RM_RMM: increment = guard_bit;
                    default: increment = 1'b0;
                endcase
                if (increment)
                    main_value = main_value + 1'b1;
                if (exponent >= emin) begin
                    if (main_value[precision]) begin
                        main_value = main_value >> 1;
                        exponent = exponent + 1;
                    end
                    if (exponent > emax) begin
                        to_infinity = (rm == RM_RNE) || (rm == RM_RMM) ||
                            ((rm == RM_RUP) && !sign) ||
                            ((rm == RM_RDN) && sign);
                        if (fmt)
                            packed_value = to_infinity ?
                                {sign, 11'h7ff, 52'b0} :
                                {sign, 11'h7fe, 52'hf_ffff_ffff_ffff};
                        else
                            packed_value = box_single(to_infinity ?
                                {sign, 8'hff, 23'b0} :
                                {sign, 8'hfe, 23'h7f_ffff});
                        result.flags[2] = 1'b1;
                        result.flags[0] = 1'b1;
                    end else begin
                        exp_field = exponent + bias;
                        if (fmt)
                            packed_value = {sign, exp_field[10:0],
                                main_value[51:0]};
                        else
                            packed_value = box_single({sign,
                                exp_field[7:0], main_value[22:0]});
                        result.flags[0] = inexact;
                    end
                end else begin
                    if (main_value[frac_bits]) begin
                        if (fmt)
                            packed_value = {sign, 11'h001, 52'b0};
                        else
                            packed_value =
                                box_single({sign, 8'h01, 23'b0});
                        tiny_after = 1'b0;
                    end else begin
                        if (fmt)
                            packed_value =
                                {sign, 11'h000, main_value[51:0]};
                        else
                            packed_value = box_single({sign,
                                8'h00, main_value[22:0]});
                        tiny_after = 1'b1;
                    end
                    result.flags[1] = tiny_after && inexact;
                    result.flags[0] = inexact;
                end
            end
            result.data = packed_value;
            round_pack64 = result;
        end
    endfunction

    function automatic fp_result_t execute_basic(
        input ydrasil_fpu_op_t op,
        input logic fmt,
        input logic dst_fmt,
        input logic [2:0] rm,
        input logic [63:0] operand_a,
        input logic [63:0] operand_b,
        input logic [63:0] operand_c
    );
        fp_result_t result;
        fp_result_t rounded;
        fp_dec_t a;
        fp_dec_t b;
        fp_dec_t c;
        logic [255:0] mag_a;
        logic [255:0] mag_b;
        logic [255:0] product;
        logic [255:0] wide_a;
        logic [255:0] wide_b;
        logic [255:0] magnitude;
        logic signed [256:0] signed_a;
        logic signed [256:0] signed_b;
        logic signed [256:0] signed_sum;
        logic sign_a;
        logic sign_b;
        logic sign_c;
        logic result_sign;
        logic invalid;
        logic unordered;
        logic compare_less;
        logic compare_equal;
        logic [63:0] chosen;
        logic [31:0] int_value;
        logic [63:0] int_magnitude;
        logic [255:0] int_main;
        logic int_guard;
        logic int_sticky;
        logic int_inexact;
        logic int_increment;
        logic unsigned_int;
        logic conversion_invalid;
        integer precision;
        integer scale_a;
        integer scale_b;
        integer scale_c;
        integer scale_product;
        integer top_a;
        integer top_b;
        integer top_common;
        integer shift;
        integer index;
        integer exponent;
        begin
            result = '0;
            a = fp_decode(operand_a, fmt);
            b = fp_decode(operand_b, fmt);
            c = fp_decode(operand_c, fmt);
            precision = fmt ? 53 : 24;
            invalid = a.snan || b.snan ||
                ((op != FPU_OP_MUL) && c.snan);

            case (op)
                FPU_OP_SGNJ, FPU_OP_SGNJN, FPU_OP_SGNJX: begin
                    chosen = operand_a;
                    if (fmt) begin
                        if (op == FPU_OP_SGNJ) chosen[63] = operand_b[63];
                        else if (op == FPU_OP_SGNJN) chosen[63] = ~operand_b[63];
                        else chosen[63] = operand_a[63] ^ operand_b[63];
                    end else begin
                        chosen[63:32] = 32'hffff_ffff;
                        if (op == FPU_OP_SGNJ) chosen[31] = operand_b[31];
                        else if (op == FPU_OP_SGNJN) chosen[31] = ~operand_b[31];
                        else chosen[31] = operand_a[31] ^ operand_b[31];
                    end
                    result.data = chosen;
                end
                FPU_OP_CLASS: begin
                    result.data = '0;
                    result.data[0] = a.inf && a.sign;
                    result.data[1] = !a.sign && 1'b0;
                    result.data[1] = a.sign && !a.inf && !a.nan &&
                        !a.zero && !a.subnormal;
                    result.data[2] = a.sign && a.subnormal;
                    result.data[3] = a.sign && a.zero;
                    result.data[4] = !a.sign && a.zero;
                    result.data[5] = !a.sign && a.subnormal;
                    result.data[6] = !a.sign && !a.inf && !a.nan &&
                        !a.zero && !a.subnormal;
                    result.data[7] = a.inf && !a.sign;
                    result.data[8] = a.snan;
                    result.data[9] = a.nan && !a.snan;
                end
                FPU_OP_EQ, FPU_OP_LT, FPU_OP_LE: begin
                    unordered = a.nan || b.nan;
                    compare_equal = (a.zero && b.zero) ||
                        (operand_a == operand_b);
                    if (a.sign != b.sign)
                        compare_less = a.sign && !(a.zero && b.zero);
                    else if (!a.sign)
                        compare_less = fmt ? (operand_a[62:0] < operand_b[62:0]) :
                            (operand_a[30:0] < operand_b[30:0]);
                    else
                        compare_less = fmt ? (operand_a[62:0] > operand_b[62:0]) :
                            (operand_a[30:0] > operand_b[30:0]);
                    result.data = '0;
                    if (!unordered) begin
                        if (op == FPU_OP_EQ) result.data[0] = compare_equal;
                        else if (op == FPU_OP_LT) result.data[0] = compare_less;
                        else result.data[0] = compare_less || compare_equal;
                    end
                    result.flags[4] = (op == FPU_OP_EQ) ?
                        (a.snan || b.snan) : unordered;
                end
                FPU_OP_MIN, FPU_OP_MAX: begin
                    if (a.nan && b.nan)
                        chosen = canonical_nan(fmt);
                    else if (a.nan)
                        chosen = fmt ? operand_b : box_single(operand_b[31:0]);
                    else if (b.nan)
                        chosen = fmt ? operand_a : box_single(operand_a[31:0]);
                    else if (a.zero && b.zero) begin
                        chosen = fmt ? operand_a : box_single(operand_a[31:0]);
                        if (fmt)
                            chosen[63] = (op == FPU_OP_MIN) ?
                                (a.sign | b.sign) : (a.sign & b.sign);
                        else
                            chosen[31] = (op == FPU_OP_MIN) ?
                                (a.sign | b.sign) : (a.sign & b.sign);
                    end else begin
                        if (a.sign != b.sign)
                            compare_less = a.sign;
                        else if (!a.sign)
                            compare_less = fmt ?
                                (operand_a[62:0] < operand_b[62:0]) :
                                (operand_a[30:0] < operand_b[30:0]);
                        else
                            compare_less = fmt ?
                                (operand_a[62:0] > operand_b[62:0]) :
                                (operand_a[30:0] > operand_b[30:0]);
                        if ((op == FPU_OP_MIN) ? compare_less : !compare_less)
                            chosen = fmt ? operand_a : box_single(operand_a[31:0]);
                        else
                            chosen = fmt ? operand_b : box_single(operand_b[31:0]);
                    end
                    result.data = chosen;
                    result.flags[4] = a.snan || b.snan;
                end
                FPU_OP_MV_X_W: result.data = {{32{operand_a[31]}}, operand_a[31:0]};
                FPU_OP_MV_W_X: result.data = box_single(operand_a[31:0]);
`ifndef SYNTHESIS
                FPU_OP_CVT_S_W, FPU_OP_CVT_S_WU,
                FPU_OP_CVT_D_W, FPU_OP_CVT_D_WU: begin
                    unsigned_int = (op == FPU_OP_CVT_S_WU) ||
                        (op == FPU_OP_CVT_D_WU);
                    result_sign = !unsigned_int && operand_a[31];
                    int_magnitude = result_sign ?
                        {32'b0, (~operand_a[31:0] + 1'b1)} :
                        {32'b0, operand_a[31:0]};
                    rounded = round_pack({192'b0, int_magnitude}, 16'sd0,
                        result_sign, dst_fmt, rm);
                    result = rounded;
                end
                FPU_OP_CVT_S_D, FPU_OP_CVT_D_S: begin
                    if (a.nan) begin
                        result.data = canonical_nan(dst_fmt);
                        result.flags[4] = a.snan;
                    end else if (a.inf) begin
                        result.data = dst_fmt ? {a.sign, 11'h7ff, 52'b0} :
                            box_single({a.sign, 8'hff, 23'b0});
                    end else if (a.zero) begin
                        result.data = dst_fmt ? {a.sign, 63'b0} :
                            box_single({a.sign, 31'b0});
                    end else begin
                        scale_a = a.exponent - (precision-1);
                        rounded = round_pack({203'b0, a.significand}, scale_a,
                            a.sign, dst_fmt, rm);
                        result = rounded;
                    end
                end
                FPU_OP_CVT_W_S, FPU_OP_CVT_WU_S,
                FPU_OP_CVT_W_D, FPU_OP_CVT_WU_D: begin
                    unsigned_int = (op == FPU_OP_CVT_WU_S) ||
                        (op == FPU_OP_CVT_WU_D);
                    conversion_invalid = a.nan || a.inf;
                    int_main = '0;
                    int_guard = 1'b0;
                    int_sticky = 1'b0;
                    int_inexact = 1'b0;
                    if (!conversion_invalid && !a.zero) begin
                        scale_a = a.exponent - (precision-1);
                        if (scale_a >= 0)
                            int_main = {203'b0, a.significand} << scale_a;
                        else begin
                            shift = -scale_a;
                            if (shift < 256) begin
                                int_main = {203'b0, a.significand} >> shift;
                                mag_a = {203'b0, a.significand};
                                int_guard = shift > 0 ? mag_a[shift-1] : 1'b0;
                                for (index = 0; index < 53; index = index + 1)
                                    if (index < shift-1)
                                        int_sticky = int_sticky | a.significand[index];
                            end else
                                int_sticky = |a.significand;
                            int_inexact = int_guard | int_sticky;
                            unique case (rm)
                                RM_RNE: int_increment = int_guard &&
                                    (int_sticky || int_main[0]);
                                RM_RDN: int_increment = a.sign && int_inexact;
                                RM_RUP: int_increment = !a.sign && int_inexact;
                                RM_RMM: int_increment = int_guard;
                                default: int_increment = 1'b0;
                            endcase
                            if (int_increment)
                                int_main = int_main + 1'b1;
                        end
                        if (unsigned_int) begin
                            if (a.sign && (|int_main))
                                conversion_invalid = 1'b1;
                            else if (|int_main[255:32])
                                conversion_invalid = 1'b1;
                        end else if ((!a.sign && ((|int_main[255:31]) ||
                                      int_main[31])) ||
                                     (a.sign && ((|int_main[255:32]) ||
                                      (int_main[31:0] > 32'h8000_0000))))
                            conversion_invalid = 1'b1;
                    end
                    if (conversion_invalid) begin
                        result.flags[4] = 1'b1;
                        if (unsigned_int)
                            int_value = a.sign && !a.nan ? 32'h0000_0000 :
                                32'hffff_ffff;
                        else
                            int_value = a.sign && !a.nan ? 32'h8000_0000 :
                                32'h7fff_ffff;
                    end else begin
                        int_value = a.sign ? (~int_main[31:0] + 1'b1) :
                            int_main[31:0];
                        result.flags[0] = int_inexact;
                    end
                    result.data = {32'b0, int_value};
                end
`endif
`ifndef SYNTHESIS
                FPU_OP_ADD, FPU_OP_SUB: begin
                    sign_a = a.sign;
                    sign_b = b.sign ^ (op == FPU_OP_SUB);
                    if (a.nan || b.nan) begin
                        result.data = canonical_nan(fmt);
                        result.flags[4] = a.snan || b.snan;
                    end else if (a.inf && b.inf && (sign_a != sign_b)) begin
                        result.data = canonical_nan(fmt);
                        result.flags[4] = 1'b1;
                    end else if (a.inf)
                        result.data = fmt ? {sign_a, 11'h7ff, 52'b0} :
                            box_single({sign_a, 8'hff, 23'b0});
                    else if (b.inf)
                        result.data = fmt ? {sign_b, 11'h7ff, 52'b0} :
                            box_single({sign_b, 8'hff, 23'b0});
                    else begin
                        scale_a = a.exponent - (precision-1);
                        scale_b = b.exponent - (precision-1);
                        top_common = a.zero ? b.exponent :
                            b.zero ? a.exponent :
                            (a.exponent > b.exponent ? a.exponent : b.exponent);
                        wide_a = a.zero ? '0 : shift_with_sticky(
                            {203'b0, a.significand}, 180 + scale_a - top_common);
                        wide_b = b.zero ? '0 : shift_with_sticky(
                            {203'b0, b.significand}, 180 + scale_b - top_common);
                        signed_a = $signed({1'b0, wide_a});
                        signed_b = $signed({1'b0, wide_b});
                        if (sign_a) signed_a = -signed_a;
                        if (sign_b) signed_b = -signed_b;
                        signed_sum = signed_a + signed_b;
                        result_sign = signed_sum[256];
                        magnitude = result_sign ? -signed_sum : signed_sum;
                        if (magnitude == '0)
                            result_sign = (sign_a == sign_b) ? sign_a :
                                (rm == RM_RDN);
                        rounded = round_pack(magnitude, top_common-180,
                            result_sign, fmt, rm);
                        result = rounded;
                    end
                end
                FPU_OP_MUL, FPU_OP_FMADD, FPU_OP_FMSUB,
                FPU_OP_FNMSUB, FPU_OP_FNMADD: begin
                    sign_a = a.sign ^ b.sign;
                    sign_c = c.sign;
                    if (op == FPU_OP_FNMSUB || op == FPU_OP_FNMADD)
                        sign_a = ~sign_a;
                    if (op == FPU_OP_FMSUB || op == FPU_OP_FNMADD)
                        sign_c = ~sign_c;
                    if (a.nan || b.nan || ((op != FPU_OP_MUL) && c.nan)) begin
                        result.data = canonical_nan(fmt);
                        result.flags[4] = invalid;
                    end else if ((a.inf && b.zero) || (a.zero && b.inf)) begin
                        result.data = canonical_nan(fmt);
                        result.flags[4] = 1'b1;
                    end else if ((op != FPU_OP_MUL) && (a.inf || b.inf) &&
                                 c.inf && (sign_a != sign_c)) begin
                        result.data = canonical_nan(fmt);
                        result.flags[4] = 1'b1;
                    end else if (a.inf || b.inf)
                        result.data = fmt ? {sign_a, 11'h7ff, 52'b0} :
                            box_single({sign_a, 8'hff, 23'b0});
                    else if ((op != FPU_OP_MUL) && c.inf)
                        result.data = fmt ? {sign_c, 11'h7ff, 52'b0} :
                            box_single({sign_c, 8'hff, 23'b0});
                    else begin
                        product = a.zero || b.zero ? '0 :
                            ({53'b0, a.significand} *
                             {53'b0, b.significand});
                        scale_product = a.exponent + b.exponent -
                            2*(precision-1);
                        if (op == FPU_OP_MUL) begin
                            rounded = round_pack(product, scale_product,
                                sign_a, fmt, rm);
                            result = rounded;
                        end else begin
                            scale_c = c.exponent - (precision-1);
                            top_a = product == '0 ? -32768 :
                                msb_index(product) + scale_product;
                            top_b = c.zero ? -32768 :
                                msb_index({203'b0, c.significand}) + scale_c;
                            top_common = top_a > top_b ? top_a : top_b;
                            wide_a = product == '0 ? '0 : shift_with_sticky(
                                product, 180 + scale_product - top_common);
                            wide_b = c.zero ? '0 : shift_with_sticky(
                                {203'b0, c.significand},
                                180 + scale_c - top_common);
                            signed_a = $signed({1'b0, wide_a});
                            signed_b = $signed({1'b0, wide_b});
                            if (sign_a) signed_a = -signed_a;
                            if (sign_c) signed_b = -signed_b;
                            signed_sum = signed_a + signed_b;
                            result_sign = signed_sum[256];
                            magnitude = result_sign ? -signed_sum : signed_sum;
                            if (magnitude == '0)
                                result_sign = (sign_a == sign_c) ? sign_a :
                                    (rm == RM_RDN);
                            rounded = round_pack(magnitude, top_common-180,
                                result_sign, fmt, rm);
                            result = rounded;
                        end
                    end
                end
`endif
                default: begin
                    result.data = canonical_nan(fmt);
                    result.flags[4] = 1'b1;
                end
            endcase
            execute_basic = result;
        end
    endfunction
endpackage
