// `ifndef DEFINE_MEM_REG_SVH
// `define DEFINE_MEM_REG_SVH

// 内存和地址配置
`define ITCM_ADDR_WIDTH 12  // ITCM地址宽度，12位对应16KB
`define DTCM_ADDR_WIDTH 16  // DTCM地址宽度，16位对应256KB

// 内存映射地址
`define ITCM_BASE_ADDR 32'h8000_0000         // ITCM基地址
`define ITCM_SIZE (1 << `ITCM_ADDR_WIDTH)     // ITCM大小：16KB
`define DTCM_BASE_ADDR 32'h8010_0000 // DTCM基地址
`define DTCM_SIZE (1 << `DTCM_ADDR_WIDTH)     // DTCM大小：256KB

// 内存初始化控制
`ifndef INIT_ITCM
`define INIT_ITCM 1       // 控制ITCM是否初始化，1表示初始化，0表示不初始化
`endif
`ifndef ITCM_INIT_FILE
`define ITCM_INIT_FILE "hw/dv/test_data/mem_generated/rv32ui-p-add.mem"  // ITCM初始化文件路径
`endif
`ifndef INIT_DTCM
`define INIT_DTCM 1
`endif
`ifndef DTCM_INIT_FILE
`define DTCM_INIT_FILE "hw/dv/test_data/mem/dram_test.mem"
`endif
// 总线宽度定义
`define BUS_DATA_WIDTH 32
`define BUS_ADDR_WIDTH 32

`define INST_DATA_WIDTH 32
`define INST_ADDR_WIDTH 32

// 寄存器配置
`define REGS_ADDR_WIDTH 5
`define REGS_DATA_WIDTH 32
`define DOUBLE_REGS_WIDTH 64
`define REGS_NUM 32
`define CSR_ADDR_WIDTH 12

// CSR reg addr
`define CSR_CYCLE 12'hc00
`define CSR_CYCLEH 12'hc80
`define CSR_MTVEC 12'h305
`define CSR_MCAUSE 12'h342
`define CSR_MEPC 12'h341
`define CSR_MIE 12'h304
`define CSR_MSTATUS 12'h300
`define CSR_MSCRATCH 12'h340


// `endif
