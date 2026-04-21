`ifndef DEFINE_ALU_SVH
`define DEFINE_ALU_SVH

//exu_alu的数据通路
`define DATAPATH_MUX_WIDTH (32+32+16)

// ALU操作信息位定义
`define ALU_OP_WIDTH 13
`define ALU_OP_ADD 0
`define ALU_OP_SUB 1
`define ALU_OP_SLL 2
`define ALU_OP_SLT 3
`define ALU_OP_SLTU 4
`define ALU_OP_XOR 5
`define ALU_OP_SRL 6
`define ALU_OP_SRA 7
`define ALU_OP_OR 8
`define ALU_OP_AND 9
`define ALU_OP_LUI 10
`define ALU_OP_AUIPC 11
`define ALU_OP_JUMP 12


`endif
