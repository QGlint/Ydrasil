module ydrasil_alu
import ydrasil_pkg::*;
#(
    parameter   DATAWIDTH = 32   
)(
    // input wire rst_n,
    // ALU
    // input wire                             req_alu_i,
    input wire [DATAWIDTH-1:0]             operand_a_i,
    input wire [DATAWIDTH-1:0]             operand_b_i,
    input wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]       operator_i,  // 统一的ALU操作信息信号
    input wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]  operator_type_i, // 操作类型信号
    
    input wire [ 4:0]                      id_rf_waddr_rd_i,
    input wire                             id_alu_rf_wen_rd_i,
    input wire                             interrupt_i,
    // 中断信号
    // input wire                             int_assert_i,

    //比较输出
    output wire                            comp_result_o,
    // 结果输出
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]     alu_result_o,
    output wire                            alu_rf_wen_rd_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     alu_rf_waddr_rd_o
);

    wire [DATAWIDTH-1:0] add_result = operand_a_i + operand_b_i;
    wire [DATAWIDTH:0] sub_result =
        {1'b0, operand_a_i} + {1'b0, ~operand_b_i} + (DATAWIDTH+1)'(1);
    wire signs_differ = operand_a_i[DATAWIDTH-1] ^ operand_b_i[DATAWIDTH-1];
    wire slt_result = signs_differ ? operand_a_i[DATAWIDTH-1] :
        sub_result[DATAWIDTH-1];
    wire sltu_result = !sub_result[DATAWIDTH];
    wire [DATAWIDTH-1:0] sll_result =
        operand_a_i << operand_b_i[$clog2(DATAWIDTH)-1:0];
    wire [DATAWIDTH-1:0] srl_result =
        operand_a_i >> operand_b_i[$clog2(DATAWIDTH)-1:0];
    wire [DATAWIDTH-1:0] sra_result =
        $signed(operand_a_i) >>> operand_b_i[$clog2(DATAWIDTH)-1:0];
    wire alu_class = operator_type_i[OPERATOR_TYPE_ALU];
    wire jump_class = operator_type_i[OPERATOR_TYPE_BJP] &&
        operator_i[OP_BJP_JUMP];
    logic [DATAWIDTH-1:0] selected_result;

    // Decode already supplies a one-hot sub-operation. A single local select
    // keeps branch comparison and LSU address logic out of both ALU lanes.
    always_comb begin
        selected_result = '0;
        unique case (1'b1)
            jump_class,
            operator_i[OP_ALU_ADD],
            operator_i[OP_ALU_AUIPC]: selected_result = add_result;
            operator_i[OP_ALU_SUB]: selected_result = sub_result[DATAWIDTH-1:0];
            operator_i[OP_ALU_SLL]: selected_result = sll_result;
            operator_i[OP_ALU_SLT]: selected_result = {{(DATAWIDTH-1){1'b0}}, slt_result};
            operator_i[OP_ALU_SLTU]: selected_result = {{(DATAWIDTH-1){1'b0}}, sltu_result};
            operator_i[OP_ALU_XOR]: selected_result = operand_a_i ^ operand_b_i;
            operator_i[OP_ALU_SRL]: selected_result = srl_result;
            operator_i[OP_ALU_SRA]: selected_result = sra_result;
            operator_i[OP_ALU_OR]: selected_result = operand_a_i | operand_b_i;
            operator_i[OP_ALU_AND]: selected_result = operand_a_i & operand_b_i;
            operator_i[OP_ALU_LUI]: selected_result = operand_b_i;
            default: selected_result = '0;
        endcase
    end

    assign comp_result_o = 1'b0;
    assign alu_result_o = (!interrupt_i && (alu_class || jump_class)) ?
        selected_result : '0;
    assign alu_rf_wen_rd_o = id_alu_rf_wen_rd_i && !interrupt_i;
    assign alu_rf_waddr_rd_o = id_rf_waddr_rd_i;
endmodule
