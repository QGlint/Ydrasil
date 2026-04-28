`include "define_decode.svh"
`include "define_mem_reg.svh"
module ydrasil_alu#(
    parameter   DATAWIDTH = 32   
)(
    // input wire rst_n,
    // ALU
    // input wire                             req_alu_i,
    input wire [DATAWIDTH-1:0]             operand_a_i,
    input wire [DATAWIDTH-1:0]             operand_b_i,
    input wire [`OPERATOR_WIDTH-1:0]       operator_i,  // 统一的ALU操作信息信号
    input wire [`OPERATOR_TYPE_WIDTH-1:0]  operator_type_i, // 操作类型信号
    
    input wire [ 4:0]                      id_rf_waddr_rd_i,
    input wire                             id_alu_rf_wen_rd_i,
    input wire                             interrupt_i,
    // 中断信号
    // input wire                             int_assert_i,

    //比较输出
    output wire                            comp_result_o,
    // 结果输出
    output wire [`REGS_DATA_WIDTH-1:0]     alu_result_o,
    output wire                            alu_rf_wen_rd_o,
    output wire [`REGS_ADDR_WIDTH-1:0]     alu_rf_waddr_rd_o
);

    // ALU操作数选择 - 统一的运算器输入
    wire [31:0] mux_op1 = operand_a_i;
    wire [31:0] mux_op2 = operand_b_i;

    wire        req_alu = operator_type_i[`OPERATOR_TYPE_ALU];

    // ALU运算类型选择(包括R与I类型)
    wire        op_add   ;
    wire        op_sub   ;
    wire        op_sll   ;
    wire        op_slt   ;
    wire        op_sltu  ;
    wire        op_xor   ;
    wire        op_srl   ;
    wire        op_sra   ;
    wire        op_or    ;
    wire        op_and   ;
    wire        op_lui   ;
    wire        op_auipc ;

    assign op_add   = operator_i [`OP_ALU_ADD] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_sub   = operator_i [`OP_ALU_SUB] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_sll   = operator_i [`OP_ALU_SLL] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_slt   = operator_i [`OP_ALU_SLT] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_sltu  = operator_i [`OP_ALU_SLTU] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_xor   = operator_i [`OP_ALU_XOR] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_srl   = operator_i [`OP_ALU_SRL] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_sra   = operator_i [`OP_ALU_SRA] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_or    = operator_i [`OP_ALU_OR] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_and   = operator_i [`OP_ALU_AND] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_lui   = operator_i [`OP_ALU_LUI] &  operator_type_i[`OPERATOR_TYPE_ALU];
    assign op_auipc = operator_i [`OP_ALU_AUIPC] &  operator_type_i[`OPERATOR_TYPE_ALU];

    wire        op_jump ;
    wire        op_beq  ;
    wire        op_bne  ;
    wire        op_blt  ;
    wire        op_bge  ;
    wire        op_bltu ;
    wire        op_bgeu ;
    wire        op_branch;

    assign op_branch = op_beq | op_bne | op_blt | op_bge | op_bltu | op_bgeu;

    assign op_jump = operator_i [`OP_BJP_JUMP] &  operator_type_i[`OPERATOR_TYPE_BJP];
    assign op_beq  = operator_i [`OP_BJP_BEQ] &  operator_type_i[`OPERATOR_TYPE_BJP];
    assign op_bne  = operator_i [`OP_BJP_BNE] &  operator_type_i[`OPERATOR_TYPE_BJP];
    assign op_blt  = operator_i [`OP_BJP_BLT] &  operator_type_i[`OPERATOR_TYPE_BJP];
    assign op_bge  = operator_i [`OP_BJP_BGE] &  operator_type_i[`OPERATOR_TYPE_BJP];
    assign op_bltu = operator_i [`OP_BJP_BLTU] &  operator_type_i[`OPERATOR_TYPE_BJP];
    assign op_bgeu = operator_i [`OP_BJP_BGEU] &  operator_type_i[`OPERATOR_TYPE_BJP]   ;

    wire        op_lsu   ;
    
    assign op_lsu = operator_type_i[`OPERATOR_TYPE_LOAD] | operator_type_i[`OPERATOR_TYPE_STORE];

    // 指令分类信号 - 便于复用运算器

    wire        op_shift        ;
    wire        op_compare      ;

    assign op_shift     = op_sll | op_srl | op_sra; // 移位操作
    assign op_compare   = op_slt | op_sltu| op_branch; // 比较操作

    //////////////////////////////////////////////////////////////
    // 1. 实现移位器 - 统一实现左移，右移通过输入翻转实现
    //////////////////////////////////////////////////////////////
    wire [31:0] shifter_in1;
    wire [4:0] shifter_in2;
    wire [31:0] shifter_res;

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
    wire [31:0] sll_res ;
    // 逻辑右移结果 - 通过反转左移结果
    wire [31:0] srl_res ;
    assign sll_res = shifter_res;
    assign srl_res = {
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
    wire [31:0] shift_mask ;
    wire [31:0] sra_res    ;

    assign shift_mask = ~(32'hffffffff >> shifter_in2);
    assign sra_res    = (srl_res & (~shift_mask)) | ({32{mux_op1[31]}} & shift_mask);

    //////////////////////////////////////////////////////////////
    // 2. 实现加减法器 - 统一处理加减法和比较操作
    //////////////////////////////////////////////////////////////
    wire [31:0] adder_in1;
    wire [31:0] adder_in2;
    wire        adder_cin;
    wire [32:0] adder_res; // 33位，包含进位信息


    // 加减法操作 - 复用于加减法、比较、地址计算等
    // wire adder_op = op_addsub | op_compare | op_auipc | op_jump;

    // 无符号操作时不进行符号扩展
    assign adder_in1 = mux_op1;
    assign adder_in2 = (op_sub | op_compare ? ~mux_op2 : mux_op2);
    assign adder_cin = (op_sub | op_compare);

    // 执行加法运算
    assign adder_res = {1'b0, adder_in1} + {1'b0, adder_in2} + {{32{1'b0}}, adder_cin};

    wire [31:0] xor_res ;
    wire [31:0] or_res  ;
    wire [31:0] and_res ;

    assign xor_res = mux_op1 ^ mux_op2;
    assign or_res  = mux_op1 | mux_op2;
    assign and_res = mux_op1 & mux_op2;


    //执行比较
    wire op_signed          ;
    wire signs_differ       ;
    wire is_equal           ;
    wire is_greater_equal   ;
    wire op_ge_alu          ;
    wire op_lt_alu          ;
    wire [31:0] sl_alu_res  ;
    wire op_sl_alu          ;
    wire comp_result        ;
                            
    assign op_signed          = op_slt | op_bge | op_blt ; // 有符号比较操作
    assign signs_differ       = mux_op1[31] ^ mux_op2[31];
    assign is_equal           = (adder_res[31:0] == 32'b0);
    assign is_greater_equal   = signs_differ ? mux_op1[31] ^ op_signed: ~adder_res[31];
    assign op_ge_alu          = op_bge | op_bgeu;
    assign op_lt_alu          = op_blt | op_bltu;
    assign sl_alu_res         = {31'b0, ~is_greater_equal};
    assign op_sl_alu          = op_slt | op_sltu;
    assign comp_result        = (op_beq & is_equal )|
                                (op_bne & (!is_equal)) |
                                (op_ge_alu & is_greater_equal) |
                                (op_lt_alu & (!is_greater_equal)) |
                                (op_jump);



    assign comp_result_o    = comp_result;


    wire [31:0] lui_res ;
    assign lui_res = mux_op2;

    wire [31:0] alu_res ;
    assign alu_res = 
        ({32{interrupt_i}} & 32'h0) |
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

    assign alu_result_o = alu_res;

    // 所有算术逻辑操作都需要写回寄存器
    wire alu_rf_wen_rd ;
    assign alu_rf_wen_rd =interrupt_i ? 1'b0: id_alu_rf_wen_rd_i;

    assign alu_rf_wen_rd_o = alu_rf_wen_rd;

    // 目标寄存器地址逻辑
    wire [4:0] alu_rf_waddr_rd ;
    assign alu_rf_waddr_rd   = id_rf_waddr_rd_i;

    assign alu_rf_waddr_rd_o = alu_rf_waddr_rd;



endmodule
