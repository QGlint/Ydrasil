`include "define_mem_reg.svh"

// `define FPGA

// 内存管理模块，包含ITCM和DTCM
module ydrasil_mems (
    input logic clk,
    input logic rst_n,

    // PC访问接口
    input  logic [`INST_ADDR_WIDTH-1:0] if_mem_addr_o,   // PC地址
    output logic [`INST_DATA_WIDTH-1:0] if_mem_rdata_i, // 指令输出

    // EX访问接口
    input  logic [`BUS_ADDR_WIDTH-1:0] lsu_mem_addr_i,  
    input  logic [`BUS_DATA_WIDTH-1:0] lsu_mem_data_i,  
    output logic [`BUS_DATA_WIDTH-1:0] lsu_mem_data_o,  
    input  logic                       lsu_mem_we_i,    
    input  logic                       lsu_mem_req_i,   
    input  logic [                3:0] lsu_mem_wmask_i, 

    // 暂停信号
    output logic hold_flag_o  // 暂停流水线信号
);

`ifndef FPGA

    // ITCM模块例化 - 使用参数化和宏定义控制初始化
    ydrmem_rom #(
        .ADDR_WIDTH(`ITCM_ADDR_WIDTH),
        .DATA_WIDTH(`BUS_DATA_WIDTH),
        .INIT_MEM  (`INIT_ITCM),        // 使用宏定义控制是否初始化
        .INIT_FILE (`ITCM_INIT_FILE)    // 使用宏定义指定初始化文件
    ) u_itcm (
        .addr_i   (if_mem_addr_o),
        .data_o   (if_mem_rdata_i)
    );

    // DTCM模块例化 - 使用参数化，默认不初始化
    ydrmem_ram #(
        .ADDR_WIDTH(`DTCM_ADDR_WIDTH),
        .DATA_WIDTH(`BUS_DATA_WIDTH),
        .INIT_MEM  (`INIT_DTCM),        // 使用宏定义控制是否初始化
        .INIT_FILE (`DTCM_INIT_FILE)    // 使用宏定义指定初始化文件
    ) u_dtcm (
        .clk      (clk),
        .rst_n    (rst_n),
        .we_i     (lsu_mem_we_i),
        .we_mask_i(lsu_mem_wmask_i),
        .addr_i   (lsu_mem_addr_i),
        .data_i   (lsu_mem_data_i),
        .data_o   (lsu_mem_data_o)
    );
`else

`endif

endmodule
