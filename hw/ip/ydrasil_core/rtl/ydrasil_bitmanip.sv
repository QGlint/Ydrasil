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

    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_a = operand_a_i;
    wire signed [REGS_DATA_WIDTH-1:0] signed_operand_b = operand_b_i;

    function automatic [REGS_DATA_WIDTH-1:0] clz32(input [REGS_DATA_WIDTH-1:0] value);
        integer idx;
        begin
            clz32 = REGS_DATA_WIDTH;
            for (idx = REGS_DATA_WIDTH - 1; idx >= 0; idx = idx - 1) begin
                if (value[idx] && (clz32 == REGS_DATA_WIDTH)) begin
                    clz32 = REGS_DATA_WIDTH - 1 - idx;
                end
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] ctz32(input [REGS_DATA_WIDTH-1:0] value);
        integer idx;
        begin
            ctz32 = REGS_DATA_WIDTH;
            for (idx = 0; idx < REGS_DATA_WIDTH; idx = idx + 1) begin
                if (value[idx] && (ctz32 == REGS_DATA_WIDTH)) begin
                    ctz32 = idx;
                end
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] cpop32(input [REGS_DATA_WIDTH-1:0] value);
        integer idx;
        begin
            cpop32 = '0;
            for (idx = 0; idx < REGS_DATA_WIDTH; idx = idx + 1) begin
                cpop32 = cpop32 + value[idx];
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] orc_b32(input [REGS_DATA_WIDTH-1:0] value);
        integer idx;
        begin
            orc_b32 = '0;
            for (idx = 0; idx < REGS_DATA_WIDTH / 8; idx = idx + 1) begin
                orc_b32[idx * 8 +: 8] = (value[idx * 8 +: 8] == 8'h00) ? 8'h00 : 8'hff;
            end
        end
    endfunction

    function automatic [7:0] brev8_byte(input [7:0] value);
        integer idx;
        begin
            for (idx = 0; idx < 8; idx = idx + 1) begin
                brev8_byte[idx] = value[7 - idx];
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] brev8_32(input [REGS_DATA_WIDTH-1:0] value);
        integer idx;
        begin
            brev8_32 = '0;
            for (idx = 0; idx < REGS_DATA_WIDTH / 8; idx = idx + 1) begin
                brev8_32[idx * 8 +: 8] = brev8_byte(value[idx * 8 +: 8]);
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] rol32(
        input [REGS_DATA_WIDTH-1:0] value,
        input [4:0] amount
    );
        begin
            if (amount == 5'd0) begin
                rol32 = value;
            end else begin
                rol32 = (value << amount) | (value >> (REGS_DATA_WIDTH - amount));
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] ror32(
        input [REGS_DATA_WIDTH-1:0] value,
        input [4:0] amount
    );
        begin
            if (amount == 5'd0) begin
                ror32 = value;
            end else begin
                ror32 = (value >> amount) | (value << (REGS_DATA_WIDTH - amount));
            end
        end
    endfunction

    function automatic [DOUBLE_REGS_WIDTH-1:0] clmul_full32(
        input [REGS_DATA_WIDTH-1:0] lhs,
        input [REGS_DATA_WIDTH-1:0] rhs
    );
        integer idx;
        reg [DOUBLE_REGS_WIDTH-1:0] accum;
        begin
            accum = '0;
            for (idx = 0; idx < REGS_DATA_WIDTH; idx = idx + 1) begin
                if (rhs[idx]) begin
                    accum = accum ^ ({32'b0, lhs} << idx);
                end
            end
            clmul_full32 = accum;
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] zip32(input [REGS_DATA_WIDTH-1:0] value);
        integer idx;
        begin
            zip32 = '0;
            for (idx = 0; idx < 16; idx = idx + 1) begin
                zip32[2 * idx]     = value[idx];
                zip32[2 * idx + 1] = value[16 + idx];
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] unzip32(input [REGS_DATA_WIDTH-1:0] value);
        integer idx;
        begin
            unzip32 = '0;
            for (idx = 0; idx < 16; idx = idx + 1) begin
                unzip32[idx]      = value[2 * idx];
                unzip32[16 + idx] = value[2 * idx + 1];
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] xperm4_32(
        input [REGS_DATA_WIDTH-1:0] lhs,
        input [REGS_DATA_WIDTH-1:0] rhs
    );
        integer idx;
        reg [3:0] sel;
        begin
            xperm4_32 = '0;
            for (idx = 0; idx < REGS_DATA_WIDTH / 4; idx = idx + 1) begin
                sel = rhs[idx * 4 +: 4];
                if (sel < 4'd8) begin
                    xperm4_32[idx * 4 +: 4] = lhs[sel * 4 +: 4];
                end
            end
        end
    endfunction

    function automatic [REGS_DATA_WIDTH-1:0] xperm8_32(
        input [REGS_DATA_WIDTH-1:0] lhs,
        input [REGS_DATA_WIDTH-1:0] rhs
    );
        integer idx;
        reg [7:0] sel;
        begin
            xperm8_32 = '0;
            for (idx = 0; idx < REGS_DATA_WIDTH / 8; idx = idx + 1) begin
                sel = rhs[idx * 8 +: 8];
                if (sel < 8'd4) begin
                    xperm8_32[idx * 8 +: 8] = lhs[sel * 8 +: 8];
                end
            end
        end
    endfunction

    wire [DOUBLE_REGS_WIDTH-1:0] clmul_full = clmul_full32(operand_a_i, operand_b_i);
    wire [REGS_DATA_WIDTH-1:0] bit_index_mask = {{(REGS_DATA_WIDTH-1){1'b0}}, 1'b1} << shamt;

    always_comb begin
        result_o = '0;

        if (op_bitmanip) begin
            unique case (1'b1)
                operator_i[OP_B_SH1ADD]: result_o = (operand_a_i << 1) + operand_b_i;
                operator_i[OP_B_SH2ADD]: result_o = (operand_a_i << 2) + operand_b_i;
                operator_i[OP_B_SH3ADD]: result_o = (operand_a_i << 3) + operand_b_i;
                operator_i[OP_B_ANDN]:   result_o = operand_a_i & ~operand_b_i;
                operator_i[OP_B_CLZ]:    result_o = clz32(operand_a_i);
                operator_i[OP_B_CPOP]:   result_o = cpop32(operand_a_i);
                operator_i[OP_B_CTZ]:    result_o = ctz32(operand_a_i);
                operator_i[OP_B_MAX]:    result_o = (signed_operand_a >= signed_operand_b) ? operand_a_i : operand_b_i;
                operator_i[OP_B_MAXU]:   result_o = (operand_a_i >= operand_b_i) ? operand_a_i : operand_b_i;
                operator_i[OP_B_MIN]:    result_o = (signed_operand_a <= signed_operand_b) ? operand_a_i : operand_b_i;
                operator_i[OP_B_MINU]:   result_o = (operand_a_i <= operand_b_i) ? operand_a_i : operand_b_i;
                operator_i[OP_B_ORC_B]:  result_o = orc_b32(operand_a_i);
                operator_i[OP_B_ORN]:    result_o = operand_a_i | ~operand_b_i;
                operator_i[OP_B_REV8]:   result_o = {operand_a_i[7:0], operand_a_i[15:8], operand_a_i[23:16], operand_a_i[31:24]};
                operator_i[OP_B_ROL]:    result_o = rol32(operand_a_i, shamt);
                operator_i[OP_B_ROR]:    result_o = ror32(operand_a_i, shamt);
                operator_i[OP_B_RORI]:   result_o = ror32(operand_a_i, shamt);
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
                operator_i[OP_B_BREV8]:  result_o = brev8_32(operand_a_i);
                operator_i[OP_B_PACK]:   result_o = {operand_b_i[15:0], operand_a_i[15:0]};
                operator_i[OP_B_PACKH]:  result_o = {16'b0, operand_b_i[7:0], operand_a_i[7:0]};
                operator_i[OP_B_ZIP]:    result_o = zip32(operand_a_i);
                operator_i[OP_B_UNZIP]:  result_o = unzip32(operand_a_i);
                operator_i[OP_B_XPERM4]: result_o = xperm4_32(operand_a_i, operand_b_i);
                operator_i[OP_B_XPERM8]: result_o = xperm8_32(operand_a_i, operand_b_i);
                default:                 result_o = '0;
            endcase
        end
    end

endmodule
