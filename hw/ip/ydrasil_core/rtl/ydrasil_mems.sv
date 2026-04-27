`include "define_mem_reg.svh"

// 内存管理模块，包含ITCM和DTCM
module ydrasil_mems (
    input wire clk,
    input wire rst_n,

    // PC访问接口
    input  wire [`INST_ADDR_WIDTH-1:0] if_mem_addr_i,   // PC地址
    output wire [`INST_DATA_WIDTH-1:0] if_mem_rdata_o, // 指令输出

    // EX访问接口
    input  wire [`BUS_ADDR_WIDTH-1:0] lsu_mem_addr_i,  
    input  wire [`BUS_DATA_WIDTH-1:0] lsu_mem_data_i,  
    output wire [`BUS_DATA_WIDTH-1:0] lsu_mem_data_o,  
    input  wire                       lsu_mem_we_i,    
    input  wire                       lsu_mem_req_i, 
    input  wire [                3:0] lsu_mem_wmask_i, 

    input  wire                         dram_sel_i       // 来自EXU的DRAM访问选择信号
    // 暂停信号
    // output wire hold_flag_o  // 暂停流水线信号
);


    wire [11:0] itcm_addr;
    wire [31:0] itcm_rdata;

    wire [15:0] dtcm_addr;
    wire [31:0] dtcm_rdata;
    wire [31:0] dtcm_wdata;
    wire        dtcm_wen;
    wire        dtcm_en;
    wire [3:0]  dtcm_wmask;

    assign itcm_addr = if_mem_addr_i[13:2]; // 16KB ITCM，地址对齐到4字节
    assign dtcm_addr = lsu_mem_addr_i[17:2]; // 256KB DTCM，地址对齐到4字节
    assign if_mem_rdata_o = itcm_rdata; // 从ITCM读取指令
    assign lsu_mem_data_o = dtcm_rdata; // 从DTCM读取

    assign dtcm_en      = lsu_mem_req_i ; 
    assign dtcm_wdata   = lsu_mem_data_i; // 写入DTCM的数据
    assign dtcm_wen     = lsu_mem_we_i; // DTCM写使能
    assign dtcm_wmask   = lsu_mem_wmask_i; // DTCM写

`ifdef SYNTHESIS
    IROM u_itcm (
    .a(itcm_addr),      // input wire [11 : 0] a
    .spo(itcm_rdata)  // output wire [31 : 0] spo
    );

    blk_mem_gen_0 u_dtcm (
    .clka(clk),    // input wire clka
    .ena(dtcm_en),      // input wire ena
    .wea(dtcm_wmask),      // input wire [3 : 0] wea
    .addra(dtcm_addr),  // input wire [15 : 0] addra
    .dina(dtcm_wdata),    // input wire [31 : 0] dina
    .douta(dtcm_rdata)  // output wire [31 : 0] douta
    );

`elsif __XILINX_SIMULATOR__

    IROM u_itcm (
    .a(itcm_addr),      // input wire [11 : 0] a
    .spo(itcm_rdata)  // output wire [31 : 0] spo
    );

    blk_mem_gen_0 u_dtcm (
    .clka(clk),    // input wire clka
    .ena(dtcm_en),      // input wire ena
    .wea(dtcm_wmask),      // input wire [3 : 0] wea
    .addra(dtcm_addr),  // input wire [15 : 0] addra
    .dina(dtcm_wdata),    // input wire [31 : 0] dina
    .douta(dtcm_rdata)  // output wire [31 : 0] douta
    );
    
`else
    // ITCM模块例化 - 使用参数化和宏定义控制初始化
    ydrmem_rom #(
        .ADDR_WIDTH(`ITCM_ADDR_WIDTH),
        .DATA_WIDTH(`BUS_DATA_WIDTH),
        .INIT_MEM  (`INIT_ITCM),        // 使用宏定义控制是否初始化
        .INIT_FILE (`ITCM_INIT_FILE)    // 使用宏定义指定初始化文件
    ) u_itcm (
        .addr_i   (itcm_addr),
        .data_o   (itcm_rdata)
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
        .we_i     (dtcm_wen),
        .we_mask_i(dtcm_wmask),
        .addr_i   (dtcm_addr),
        .data_i   (dtcm_wdata),
        .data_o   (dtcm_rdata)
    );

`endif

endmodule
