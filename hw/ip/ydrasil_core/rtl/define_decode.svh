// `ifndef DEFINE_DECODE_SVH
// `define DEFINE_DECODE_SVH

`define OPERATOR_TYPE_WIDTH 4
`define OPERATOR_TYPE_ALU 0
`define OPERATOR_TYPE_BJP 1
`define OPERATOR_TYPE_LOAD 2
`define OPERATOR_TYPE_STORE 3

`define OPERATOR_TYPE_LSU_BASE 2

`define OPERATOR_WIDTH 12

`define OP_ALU_INFO_WIDTH    12

`define OP_ALU_LUI          0
`define OP_ALU_AUIPC        1
`define OP_ALU_ADD          2
`define OP_ALU_SUB          3
`define OP_ALU_SLL          4
`define OP_ALU_SLT          5
`define OP_ALU_SLTU         6
`define OP_ALU_XOR          7
`define OP_ALU_SRL          8
`define OP_ALU_SRA          9
`define OP_ALU_OR           10
`define OP_ALU_AND          11
// `define OP_ALU_OP2IMM       12
// `define OP_ALU_OP1PC        13

`define OP_BJP_INFO_WIDTH    7

`define OP_BJP_JUMP         0
`define OP_BJP_BEQ          1
`define OP_BJP_BNE          2
`define OP_BJP_BLT          3
`define OP_BJP_BGE          4
`define OP_BJP_BLTU         5
`define OP_BJP_BGEU         6
// `define OP_BJP_OP1RS1       7

`define OP_LSU_INFO_WIDTH    8
`define OP_LOAD_INFO_WIDTH   5

`define OP_LSU_LB           0
`define OP_LSU_LH           1
`define OP_LSU_LW           2
`define OP_LSU_LBU          3
`define OP_LSU_LHU          4
`define OP_LSU_SB           5
`define OP_LSU_SH           6
`define OP_LSU_SW           7


`define op_CSR_BUS_WIDTH    4  
`define op_CSR_CSRRW        0
`define op_CSR_CSRRS        1
`define op_CSR_CSRRC        2
`define op_CSR_RS1IMM       3
`define op_CSR_CSRADDR_WIDTH      12


// `endif
