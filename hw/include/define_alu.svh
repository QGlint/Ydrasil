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

`define EX_INFO_BUS_WIDTH 3
`define EX_INFO_BYPASS_BIT 2
`define EX_INFO_ALU 3'b000
`define EX_INFO_MUL 3'b001
`define EX_INFO_DIV 3'b010
`define EX_INFO_CSR 3'b011
`define EX_INFO_BJP 3'b100
`define EX_INFO_LOAD 3'b101
`define EX_INFO_OTHER 3'b110