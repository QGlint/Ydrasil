module ydrasil_fpu_to_int
    import ydrasil_pkg::*;
    import ydrasil_fpu_math_pkg::*;
(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start_i,
    input  ydrasil_fpu_op_t op_i,
    input  wire             fmt_i,
    input  wire [2:0]       rm_i,
    input  wire [63:0]      operand_i,
    output wire             busy_o,
    output wire             done_o,
    output wire [63:0]      result_o,
    output wire [4:0]       flags_o
);
    typedef enum logic [2:0] {
        IDLE,
        SCALE,
        SHIFT,
        ROUND,
        RANGE,
        CHECK
    } state_t;

    state_t state_q;
    fp_dec_t value_q;
    reg unsigned_q;
    reg fmt_q;
    reg [2:0] rm_q;
    reg signed [15:0] scale_q;
    reg [63:0] magnitude_q;
    reg increment_q;
    reg inexact_q;
    reg invalid_q;
    reg done_q;
    reg [63:0] result_q;
    reg [4:0] flags_q;

    always_ff @(posedge clk or negedge rst_n) begin
        fp_dec_t decoded;
        integer precision;
        integer shift;
        integer index;
        logic [63:0] main_value;
        logic guard_bit;
        logic sticky_bit;
        logic increment;
        logic invalid;
        logic [31:0] int_value;
        if (!rst_n) begin
            state_q <= IDLE;
            value_q <= '0;
            unsigned_q <= 1'b0;
            fmt_q <= 1'b0;
            rm_q <= '0;
            scale_q <= '0;
            magnitude_q <= '0;
            increment_q <= 1'b0;
            inexact_q <= 1'b0;
            invalid_q <= 1'b0;
            done_q <= 1'b0;
            result_q <= '0;
            flags_q <= '0;
        end else begin
            done_q <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    decoded = fp_decode(operand_i, fmt_i);
                    value_q <= decoded;
                    unsigned_q <= (op_i == FPU_OP_CVT_WU_S) ||
                        (op_i == FPU_OP_CVT_WU_D);
                    fmt_q <= fmt_i;
                    rm_q <= rm_i;
                    state_q <= SCALE;
                end
                SCALE: begin
                    precision = fmt_q ? 53 : 24;
                    scale_q <= value_q.exponent - (precision-1);
                    invalid_q <= value_q.nan || value_q.inf;
                    state_q <= SHIFT;
                end
                SHIFT: begin
                    main_value = '0;
                    guard_bit = 1'b0;
                    sticky_bit = 1'b0;
                    invalid = invalid_q;
                    if (!invalid && !value_q.zero) begin
                        if (scale_q >= 0) begin
                            if (scale_q < 64)
                                main_value =
                                    value_q.significand << scale_q;
                            else
                                invalid = 1'b1;
                        end else begin
                            shift = -scale_q;
                            if (shift < 64) begin
                                main_value = value_q.significand >> shift;
                                guard_bit = value_q.significand[shift-1];
                                for (index = 0; index < 53;
                                     index = index + 1)
                                    if (index < shift-1)
                                        sticky_bit = sticky_bit |
                                            value_q.significand[index];
                            end else
                                sticky_bit = |value_q.significand;
                        end
                    end
                    magnitude_q <= main_value;
                    inexact_q <= guard_bit | sticky_bit;
                    invalid_q <= invalid;
                    case (rm_q)
                        RM_RNE: increment = guard_bit &&
                            (sticky_bit || main_value[0]);
                        RM_RDN: increment = value_q.sign &&
                            (guard_bit || sticky_bit);
                        RM_RUP: increment = !value_q.sign &&
                            (guard_bit || sticky_bit);
                        RM_RMM: increment = guard_bit;
                        default: increment = 1'b0;
                    endcase
                    increment_q <= increment;
                    state_q <= ROUND;
                end
                ROUND: begin
                    if (increment_q)
                        magnitude_q <= magnitude_q + 1'b1;
                    state_q <= RANGE;
                end
                RANGE: begin
                    invalid = invalid_q;
                    if (!invalid) begin
                        if (unsigned_q) begin
                            if (value_q.sign && (|magnitude_q))
                                invalid = 1'b1;
                            else if (|magnitude_q[63:32])
                                invalid = 1'b1;
                        end else if ((!value_q.sign &&
                                     (magnitude_q > 64'h7fff_ffff)) ||
                                    (value_q.sign &&
                                     (magnitude_q > 64'h8000_0000)))
                            invalid = 1'b1;
                    end
                    invalid_q <= invalid;
                    state_q <= CHECK;
                end
                CHECK: begin
                    flags_q <= '0;
                    if (invalid_q) begin
                        flags_q[4] <= 1'b1;
                        if (unsigned_q)
                            int_value = value_q.sign && !value_q.nan ?
                                32'h0000_0000 : 32'hffff_ffff;
                        else
                            int_value = value_q.sign && !value_q.nan ?
                                32'h8000_0000 : 32'h7fff_ffff;
                    end else begin
                        int_value = value_q.sign ?
                            (~magnitude_q[31:0] + 1'b1) :
                            magnitude_q[31:0];
                        flags_q[0] <= inexact_q;
                    end
                    result_q <= {32'b0, int_value};
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
