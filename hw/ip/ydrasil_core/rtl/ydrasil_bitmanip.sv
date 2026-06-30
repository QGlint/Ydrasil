module ydrasil_bitmanip
import ydrasil_pkg::*;
(
    input  wire [REGS_DATA_WIDTH-1:0]     operand_a_i,
    input  wire [REGS_DATA_WIDTH-1:0]     operand_b_i,
    input  wire [OPERATOR_WIDTH-1:0]      operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] operator_type_i,

    output reg  [REGS_DATA_WIDTH-1:0]     result_o
);

    wire op_bitmanip = operator_type_i[OPERATOR_TYPE_BITMANIP];
    wire [4:0] shamt = operand_b_i[4:0];
    wire [REGS_DATA_WIDTH-1:0] shamt_ext = {{(REGS_DATA_WIDTH-5){1'b0}}, shamt};
    wire [REGS_DATA_WIDTH-1:0] rotate_inv_shamt = REGS_DATA_WIDTH'(REGS_DATA_WIDTH) - shamt_ext;

    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_a = operand_a_i;
    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_b = operand_b_i;

    wire [REGS_DATA_WIDTH-1:0] bit_index_mask = {{(REGS_DATA_WIDTH-1){1'b0}}, 1'b1} << shamt;
    reg [REGS_DATA_WIDTH-1:0] clz_result;
    reg [REGS_DATA_WIDTH-1:0] ctz_result;
    reg [REGS_DATA_WIDTH-1:0] cpop_result;
    reg [REGS_DATA_WIDTH-1:0] orc_b_result;
    reg [REGS_DATA_WIDTH-1:0] brev8_result;
    reg [REGS_DATA_WIDTH-1:0] rol_result;
    reg [REGS_DATA_WIDTH-1:0] ror_result;
    reg [DOUBLE_REGS_WIDTH-1:0] clmul_full;
    reg [REGS_DATA_WIDTH-1:0] zip_result;
    reg [REGS_DATA_WIDTH-1:0] unzip_result;
    reg [REGS_DATA_WIDTH-1:0] xperm4_result;
    reg [REGS_DATA_WIDTH-1:0] xperm8_result;
    reg [3:0] xperm4_sel;
    reg [7:0] xperm8_sel;
    integer bit_idx;
    integer byte_idx;
    integer item_idx;

    always_comb begin
        clz_result = REGS_DATA_WIDTH'(REGS_DATA_WIDTH);
        ctz_result = REGS_DATA_WIDTH'(REGS_DATA_WIDTH);
        cpop_result = '0;
        orc_b_result = '0;
        brev8_result = '0;
        rol_result = (shamt == 5'd0) ?
            operand_a_i :
            ((operand_a_i << shamt) | (operand_a_i >> rotate_inv_shamt[4:0]));
        ror_result = (shamt == 5'd0) ?
            operand_a_i :
            ((operand_a_i >> shamt) | (operand_a_i << rotate_inv_shamt[4:0]));
        clmul_full = '0;
        zip_result = '0;
        unzip_result = '0;
        xperm4_result = '0;
        xperm8_result = '0;
        xperm4_sel = 4'b0;
        xperm8_sel = 8'b0;

        for (bit_idx = REGS_DATA_WIDTH - 1; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            if (operand_a_i[bit_idx] && (clz_result == REGS_DATA_WIDTH'(REGS_DATA_WIDTH))) begin
                clz_result = REGS_DATA_WIDTH'(REGS_DATA_WIDTH - 1 - bit_idx);
            end
        end

        for (bit_idx = 0; bit_idx < REGS_DATA_WIDTH; bit_idx = bit_idx + 1) begin
            if (operand_a_i[bit_idx] && (ctz_result == REGS_DATA_WIDTH'(REGS_DATA_WIDTH))) begin
                ctz_result = REGS_DATA_WIDTH'(bit_idx);
            end
            cpop_result = cpop_result + {{(REGS_DATA_WIDTH-1){1'b0}}, operand_a_i[bit_idx]};
            if (operand_b_i[bit_idx]) begin
                clmul_full = clmul_full ^ ({32'b0, operand_a_i} << bit_idx);
            end
        end

        for (byte_idx = 0; byte_idx < REGS_DATA_WIDTH / 8; byte_idx = byte_idx + 1) begin
            orc_b_result[byte_idx * 8 +: 8] =
                (operand_a_i[byte_idx * 8 +: 8] == 8'h00) ? 8'h00 : 8'hff;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                brev8_result[(byte_idx * 8) + bit_idx] =
                    operand_a_i[(byte_idx * 8) + (7 - bit_idx)];
            end
        end

        for (item_idx = 0; item_idx < 16; item_idx = item_idx + 1) begin
            zip_result[2 * item_idx] = operand_a_i[item_idx];
            zip_result[2 * item_idx + 1] = operand_a_i[16 + item_idx];
            unzip_result[item_idx] = operand_a_i[2 * item_idx];
            unzip_result[16 + item_idx] = operand_a_i[2 * item_idx + 1];
        end

        for (item_idx = 0; item_idx < REGS_DATA_WIDTH / 4; item_idx = item_idx + 1) begin
            xperm4_sel = operand_b_i[item_idx * 4 +: 4];
            if (xperm4_sel < 4'd8) begin
                xperm4_result[item_idx * 4 +: 4] = operand_a_i[xperm4_sel * 4 +: 4];
            end
        end

        for (item_idx = 0; item_idx < REGS_DATA_WIDTH / 8; item_idx = item_idx + 1) begin
            xperm8_sel = operand_b_i[item_idx * 8 +: 8];
            if (xperm8_sel < 8'd4) begin
                xperm8_result[item_idx * 8 +: 8] = operand_a_i[xperm8_sel * 8 +: 8];
            end
        end
    end

    always_comb begin
        result_o = '0;

        if (op_bitmanip) begin
            unique case (1'b1)
                operator_i[OP_B_SH1ADD]: result_o = (operand_a_i << 1) + operand_b_i;
                operator_i[OP_B_SH2ADD]: result_o = (operand_a_i << 2) + operand_b_i;
                operator_i[OP_B_SH3ADD]: result_o = (operand_a_i << 3) + operand_b_i;
                operator_i[OP_B_ANDN]:   result_o = operand_a_i & ~operand_b_i;
                operator_i[OP_B_CLZ]:    result_o = clz_result;
                operator_i[OP_B_CPOP]:   result_o = cpop_result;
                operator_i[OP_B_CTZ]:    result_o = ctz_result;
                operator_i[OP_B_MAX]:    result_o = (signed_operand_a >= signed_operand_b) ? operand_a_i : operand_b_i;
                operator_i[OP_B_MAXU]:   result_o = (operand_a_i >= operand_b_i) ? operand_a_i : operand_b_i;
                operator_i[OP_B_MIN]:    result_o = (signed_operand_a <= signed_operand_b) ? operand_a_i : operand_b_i;
                operator_i[OP_B_MINU]:   result_o = (operand_a_i <= operand_b_i) ? operand_a_i : operand_b_i;
                operator_i[OP_B_ORC_B]:  result_o = orc_b_result;
                operator_i[OP_B_ORN]:    result_o = operand_a_i | ~operand_b_i;
                operator_i[OP_B_REV8]:   result_o = {operand_a_i[7:0], operand_a_i[15:8], operand_a_i[23:16], operand_a_i[31:24]};
                operator_i[OP_B_ROL]:    result_o = rol_result;
                operator_i[OP_B_ROR]:    result_o = ror_result;
                operator_i[OP_B_RORI]:   result_o = ror_result;
                operator_i[OP_B_SEXT_B]: result_o = {{24{operand_a_i[7]}}, operand_a_i[7:0]};
                operator_i[OP_B_SEXT_H]: result_o = {{16{operand_a_i[15]}}, operand_a_i[15:0]};
                operator_i[OP_B_XNOR]:   result_o = ~(operand_a_i ^ operand_b_i);
                operator_i[OP_B_ZEXT_H]: result_o = {16'b0, operand_a_i[15:0]};
                operator_i[OP_B_CLMUL]:  result_o = clmul_full[31:0];
                operator_i[OP_B_CLMULH]: result_o = clmul_full[63:32];
                operator_i[OP_B_CLMULR]: result_o = clmul_full[62:31];
                operator_i[OP_B_BCLR]:   result_o = operand_a_i & ~bit_index_mask;
                operator_i[OP_B_BCLRI]:  result_o = operand_a_i & ~bit_index_mask;
                operator_i[OP_B_BEXT]:   result_o = {31'b0, |(operand_a_i & bit_index_mask)};
                operator_i[OP_B_BEXTI]:  result_o = {31'b0, |(operand_a_i & bit_index_mask)};
                operator_i[OP_B_BINV]:   result_o = operand_a_i ^ bit_index_mask;
                operator_i[OP_B_BINVI]:  result_o = operand_a_i ^ bit_index_mask;
                operator_i[OP_B_BSET]:   result_o = operand_a_i | bit_index_mask;
                operator_i[OP_B_BSETI]:  result_o = operand_a_i | bit_index_mask;
                operator_i[OP_B_BREV8]:  result_o = brev8_result;
                operator_i[OP_B_PACK]:   result_o = {operand_b_i[15:0], operand_a_i[15:0]};
                operator_i[OP_B_PACKH]:  result_o = {16'b0, operand_b_i[7:0], operand_a_i[7:0]};
                operator_i[OP_B_ZIP]:    result_o = zip_result;
                operator_i[OP_B_UNZIP]:  result_o = unzip_result;
                operator_i[OP_B_XPERM4]: result_o = xperm4_result;
                operator_i[OP_B_XPERM8]: result_o = xperm8_result;
                default:                 result_o = '0;
            endcase
        end
    end

endmodule
