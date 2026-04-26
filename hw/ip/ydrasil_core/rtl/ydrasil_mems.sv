`include "define_mem_reg.svh"

// 内存管理模块，包含ITCM和DTCM
module ydrasil_mems (
    input wire clk,
    input wire rst_n,

    // PC访问接口
    input  wire [`INST_ADDR_WIDTH-1:0] if_mem_addr_o,   // PC地址
    output wire [`INST_DATA_WIDTH-1:0] if_mem_rdata_i, // 指令输出

    // EX访问接口
    input  wire [`BUS_ADDR_WIDTH-1:0] lsu_mem_addr_i,  
    input  wire [`BUS_DATA_WIDTH-1:0] lsu_mem_data_i,  
    output wire [`BUS_DATA_WIDTH-1:0] lsu_mem_data_o,  
    input  wire                       lsu_mem_we_i,    
    input  wire                       lsu_mem_req_i,   
    input  wire [                3:0] lsu_mem_wmask_i, 

    // 暂停信号
    output wire hold_flag_o  // 暂停流水线信号
);




`ifdef SYNTHESIS
    IROM u_itcm (
    .a(if_mem_addr_o),      // input wire [11 : 0] a
    .spo(if_mem_rdata_i)  // output wire [31 : 0] spo
    );

    blk_mem_gen_0 u_dtcm (
    .clka(clk),    // input wire clka
    .ena(lsu_mem_req_i),      // input wire ena
    .wea(lsu_mem_wmask_i),      // input wire [3 : 0] wea
    .addra(lsu_mem_addr_i),  // input wire [15 : 0] addra
    .dina(lsu_mem_data_i),    // input wire [31 : 0] dina
    .douta(lsu_mem_data_o)  // output wire [31 : 0] douta
    );

`elsif __XILINX_SIMULATOR__

    IROM u_itcm (
    .a(if_mem_addr_o),      // input wire [11 : 0] a
    .spo(if_mem_rdata_i)  // output wire [31 : 0] spo
    );

    blk_mem_gen_0 u_dtcm (
    .clka(clk),    // input wire clka
    .ena(lsu_mem_req_i),      // input wire ena
    .wea(lsu_mem_wmask_i),      // input wire [3 : 0] wea
    .addra(lsu_mem_addr_i),  // input wire [15 : 0] addra
    .dina(lsu_mem_data_i),    // input wire [31 : 0] dina
    .douta(lsu_mem_data_o)  // output wire [31 : 0] douta
    );
    
`else
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

`endif

endmodule
