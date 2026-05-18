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

    itcm u_itcm (
        .clk(clk),
        .itcm_en(rst_n), // ITCM在复位后始终使能
        .itcm_addr(itcm_addr),
        .itcm_data_o(itcm_rdata)
    );

    dtcm u_dtcm (
        .clk(clk),
        .dtcm_en(dtcm_en),
        .dtcm_wen(dtcm_wen),
        .dtcm_mask(dtcm_wmask),
        .dtcm_addr(dtcm_addr),
        .dtcm_data_i(dtcm_wdata),
        .dtcm_data_o(dtcm_rdata)
    );



endmodule
