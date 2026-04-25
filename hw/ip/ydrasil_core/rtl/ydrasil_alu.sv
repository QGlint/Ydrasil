`include "define_decode.svh"
`include "config.svh"
module ydrasil_alu#(
    parameter   DATAWIDTH = 32   
)(
    // input logic rst_n,
    // ALU
    input logic                             req_alu_i,
    input logic [DATAWIDTH-1:0]             operand_a_i,
    input logic [DATAWIDTH-1:0]             operand_b_i,
    input logic [`OPERATOR_WIDTH-1:0]       operator_i,  // 统一的ALU操作信息信号
    input logic [`OPERATOR_TYPE_WIDTH-1:0]  operator_type_i, // 操作类型信号
    
    input logic [ 4:0]                      rf_waddr_rd_i,
    input logic                             rf_wen_rd_i,
    // 中断信号
    // input logic                             int_assert_i,

    //比较输出
    output logic                            comp_result_o,

    // 结果输出
    output logic [`REGS_DATA_WIDTH-1:0]     alu_wb_result_o,
    output logic                            alu_rf_wen_rd_o,
    output logic [`REGS_ADDR_WIDTH-1:0]     alu_rf_waddr_rd_o
);

    // ALU操作数选择 - 统一的运算器输入
    logic [31:0] mux_op1 = operand_a_i;
    logic [31:0] mux_op2 = operand_b_i;

    // ALU运算类型选择(包括R与I类型)
    logic        op_add   = operator_i [`OP_ALU_ADD] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_sub   = operator_i [`OP_ALU_SUB] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_sll   = operator_i [`OP_ALU_SLL] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_slt   = operator_i [`OP_ALU_SLT] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_sltu  = operator_i [`OP_ALU_SLTU] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_xor   = operator_i [`OP_ALU_XOR] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_srl   = operator_i [`OP_ALU_SRL] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_sra   = operator_i [`OP_ALU_SRA] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_or    = operator_i [`OP_ALU_OR] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_and   = operator_i [`OP_ALU_AND] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_lui   = operator_i [`OP_ALU_LUI] &  operator_type_i[`OPERATOR_TYPE_ALU];
    logic        op_auipc = operator_i [`OP_ALU_AUIPC] &  operator_type_i[`OPERATOR_TYPE_ALU];

    logic        op_jump  = operator_i [`OP_BJP_JUMP] &  operator_type_i[`OPERATOR_TYPE_BJP];
    logic        op_beq   = operator_i [`OP_BJP_BEQ] &  operator_type_i[`OPERATOR_TYPE_BJP];
    logic        op_bne   = operator_i [`OP_BJP_BNE] &  operator_type_i[`OPERATOR_TYPE_BJP];
    logic        op_blt   = operator_i [`OP_BJP_BLT] &  operator_type_i[`OPERATOR_TYPE_BJP];
    logic        op_bge   = operator_i [`OP_BJP_BGE] &  operator_type_i[`OPERATOR_TYPE_BJP];
    logic        op_bltu  = operator_i [`OP_BJP_BLTU] &  operator_type_i[`OPERATOR_TYPE_BJP];
    logic        op_bgeu  = operator_i [`OP_BJP_BGEU] &  operator_type_i[`OPERATOR_TYPE_BJP]   ;

    logic        op_lsu   = operator_type_i[`OPERATOR_TYPE_LOAD] | operator_type_i[`OPERATOR_TYPE_STORE];

    // 指令分类信号 - 便于复用运算器
    // logic        op_addsub = op_add | op_sub |op_lsu;  // 加减法操作
    logic        op_shift = op_sll | op_srl | op_sra; // 移位操作
    // logic        op_logic = op_xor | op_or | op_and; // 逻辑操作
    logic        op_compare = op_slt | op_sltu; // 比较操作
    // logic        op_mvop2 = op_lui; // 直接使用操作数2

    //////////////////////////////////////////////////////////////
    // 1. 实现移位器 - 统一实现左移，右移通过输入翻转实现
    //////////////////////////////////////////////////////////////
    logic [31:0] shifter_in1;
    logic [4:0] shifter_in2;
    logic [31:0] shifter_res;

    // 为右移操作翻转输入位
    assign shifter_in1 = {32{op_shift}} & (
        (op_sra | op_srl) ? 
        {   // 输入位反转
            mux_op1[00],mux_op1[01],mux_op1[02],mux_op1[03],
            mux_op1[04],mux_op1[05],mux_op1[06],mux_op1[07],
            mux_op1[08],mux_op1[09],mux_op1[10],mux_op1[11],
            mux_op1[12],mux_op1[13],mux_op1[14],mux_op1[15],
            mux_op1[16],mux_op1[17],mux_op1[18],mux_op1[19],
            mux_op1[20],mux_op1[21],mux_op1[22],mux_op1[23],
            mux_op1[24],mux_op1[25],mux_op1[26],mux_op1[27],
            mux_op1[28],mux_op1[29],mux_op1[30],mux_op1[31]
        } : mux_op1
    );

    assign shifter_in2 = mux_op2[4:0];

    // 执行左移操作
    assign shifter_res = (shifter_in1 << shifter_in2);

    // 左移结果
    logic [31:0] sll_res = shifter_res;

    // 逻辑右移结果 - 通过反转左移结果
    logic [31:0] srl_res = {
        shifter_res[00],shifter_res[01],shifter_res[02],shifter_res[03],
        shifter_res[04],shifter_res[05],shifter_res[06],shifter_res[07],
        shifter_res[08],shifter_res[09],shifter_res[10],shifter_res[11],
        shifter_res[12],shifter_res[13],shifter_res[14],shifter_res[15],
        shifter_res[16],shifter_res[17],shifter_res[18],shifter_res[19],
        shifter_res[20],shifter_res[21],shifter_res[22],shifter_res[23],
        shifter_res[24],shifter_res[25],shifter_res[26],shifter_res[27],
        shifter_res[28],shifter_res[29],shifter_res[30],shifter_res[31]
    };

    // 算术右移结果 - 在逻辑右移基础上处理符号位
    logic [31:0] shift_mask = ~(32'hffffffff >> shifter_in2);
    logic [31:0] sra_res = (srl_res & (~shift_mask)) | ({32{mux_op1[31]}} & shift_mask);

    //////////////////////////////////////////////////////////////
    // 2. 实现加减法器 - 统一处理加减法和比较操作
    //////////////////////////////////////////////////////////////
    logic [31:0] adder_in1;
    logic [31:0] adder_in2;
    logic        adder_cin;
    logic [32:0] adder_res; // 33位，包含进位信息


    // 加减法操作 - 复用于加减法、比较、地址计算等
    // logic adder_op = op_addsub | op_compare | op_auipc | op_jump;

    // 无符号操作时不进行符号扩展
    assign adder_in1 = mux_op1;
    assign adder_in2 = (op_sub | op_compare ? ~mux_op2 : mux_op2);
    assign adder_cin = (op_sub | op_compare);

    // 执行加法运算
    assign adder_res = {1'b0, adder_in1} + {1'b0, adder_in2} + {{32{1'b0}}, adder_cin};

    logic [31:0] xor_res =  (mux_op1 ^ mux_op2);
    logic [31:0] or_res  =  (mux_op1 | mux_op2);
    logic [31:0] and_res =  (mux_op1 & mux_op2);

    //执行比较
    logic op_signed = op_slt | op_bge | op_blt ; // 有符号比较操作

    logic signs_differ = mux_op1[31] ^ mux_op2[31];
    logic is_equal = (adder_res[31:0] == 32'b0);
    logic is_greater_equal = signs_differ ? mux_op1[31] ^ op_signed: ~adder_res[31];


    logic op_ge_alu = op_bge | op_bgeu;
    logic op_lt_alu = op_blt | op_bltu;

    logic [31:0] sl_alu_res = {31'b0, ~is_greater_equal};

    logic op_sl_alu = op_slt | op_sltu;

    logic comp_result = (op_beq & is_equal )|
                        (op_bne & (!is_equal)) |
                        (op_ge_alu & is_greater_equal) |
                        (op_lt_alu & (!is_greater_equal)) |
                        (op_jump);

    assign comp_result_o = comp_result;


    logic [31:0] lui_res = mux_op2;

    logic [31:0] alu_res =
        // ({32{int_assert_i}} & 32'h0) |
        ({32{!req_alu_i && !op_jump}} & 32'h0) |
        ({32{op_add | op_auipc | op_jump | op_lsu}} & adder_res[31:0]) |
        ({32{op_sub}} & adder_res[31:0]) |
        ({32{op_xor}} & xor_res) |
        ({32{op_or}} & or_res) |
        ({32{op_and}} & and_res) |
        ({32{op_sll}} & sll_res) |
        ({32{op_srl}} & srl_res) |
        ({32{op_sra}} & sra_res) |
        ({32{op_sl_alu}} & sl_alu_res) |
        ({32{op_lui}} & lui_res);

    assign alu_wb_result_o = alu_res;

    // 所有算术逻辑操作都需要写回寄存器
    logic alu_rf_wen_rd = 
            // (int_assert_i) ? 0 : 
            (rf_wen_rd_i);

    assign alu_rf_wen_rd_o = alu_rf_wen_rd;

    // 目标寄存器地址逻辑
    logic [4:0] alu_rf_waddr_rd = 
        //(int_assert_i) ? 5'b0 :
         rf_waddr_rd_i;

    assign alu_rf_waddr_rd_o = alu_rf_waddr_rd;



endmodule
