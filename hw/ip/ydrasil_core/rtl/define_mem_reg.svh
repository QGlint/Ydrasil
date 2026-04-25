`ifndef DEFINE_MEM_REG_SVH
`define DEFINE_MEM_REG_SVH

// 内存和地址配置
`define ITCM_ADDR_WIDTH 16  // ITCM地址宽度，16位对应64KB
`define DTCM_ADDR_WIDTH 16  // DTCM地址宽度，16位对应64KB

// 内存映射地址
`define ITCM_BASE_ADDR 32'h0         // ITCM基地址
`define ITCM_SIZE (1 << `ITCM_ADDR_WIDTH)     // ITCM大小：64KB
`define DTCM_BASE_ADDR 32'h9000_0000 // DTCM基地址
`define DTCM_SIZE (1 << `DTCM_ADDR_WIDTH)     // DTCM大小：64KB

// 内存初始化控制
`define INIT_ITCM 1       // 控制ITCM是否初始化，1表示初始化，0表示不初始化
`define ITCM_INIT_FILE "itcm_init.mem"  // ITCM初始化文件路径
`define INIT_DTCM 1       // 控制DTCM是否初始化，1表示初始化，0表示不初始化
`define DTCM_INIT_FILE "dtcm_init.mem"  // DTCM初始化文件路径

// 总线宽度定义
`define BUS_DATA_WIDTH 32
`define BUS_ADDR_WIDTH 32

`define INST_DATA_WIDTH 32
`define INST_ADDR_WIDTH 32

// 寄存器配置
`define REGS_ADDR_WIDTH 5
`define REGS_DATA_WIDTH 32
`define DOUBLE_REG_WIDTH 64
`define REGS_NUM 32




`endif
