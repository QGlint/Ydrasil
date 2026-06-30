// 内存管理模块，包含ITCM和DTCM
module ydrasil_mems 
import ydrasil_pkg::*;
(
    input wire clk,
    input wire rst_n,

    // PC访问接口
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr_i,   // PC地址
    output wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] if_mem_rdata_o, // 指令输出

    // EX访问接口
    input  wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0] lsu_mem_addr_i,  
    input  wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0] lsu_mem_data_i,  
    output wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0] lsu_mem_data_o,  
    input  wire                       lsu_mem_we_i,    
    input  wire                       lsu_mem_req_i, 
    input  wire [                3:0] lsu_mem_wmask_i, 

    input  wire                         dram_sel_i       // 来自EXU的DRAM访问选择信号
    // 暂停信号
    // output wire hold_flag_o  // 暂停流水线信号
);


    wire [ITCM_ADDR_WIDTH-1:0] itcm_addr;
    wire [INST_DATA_WIDTH-1:0] itcm_rdata;

    wire [DTCM_ADDR_WIDTH-1:0] dtcm_addr;
    wire [BUS_DATA_WIDTH-1:0] dtcm_rdata;
    wire [BUS_DATA_WIDTH-1:0] dtcm_wdata;
    wire        dtcm_wen;
    wire        dtcm_en;
    wire [3:0]  dtcm_wmask;

    localparam [31:0] DTCM_BYTE_SIZE = (32'd1 << DTCM_ADDR_WIDTH) << 2;
`ifdef TARGET_FPGA
    localparam bit IF_DTCM_FETCH_ENABLE = 1'b0;
`else
`ifdef TARGET_SYNTHESIS
    localparam bit IF_DTCM_FETCH_ENABLE = 1'b0;
`else
    localparam bit IF_DTCM_FETCH_ENABLE = 1'b1;
`endif
`endif

    wire if_dtcm_sel;
    wire if_dtcm_access;
    wire [DTCM_ADDR_WIDTH-1:0] if_dtcm_addr;
    wire [DTCM_ADDR_WIDTH-1:0] lsu_dtcm_addr;

    assign if_dtcm_sel = (if_mem_addr_i >= DTCM_BASE_ADDR) &&
                         (if_mem_addr_i < (DTCM_BASE_ADDR + DTCM_BYTE_SIZE));
    assign if_dtcm_access = IF_DTCM_FETCH_ENABLE & if_dtcm_sel;
    assign if_dtcm_addr = if_mem_addr_i[DTCM_ADDR_WIDTH+1:2];
    assign lsu_dtcm_addr = lsu_mem_addr_i[DTCM_ADDR_WIDTH+1:2];

    assign itcm_addr = if_mem_addr_i[ITCM_ADDR_WIDTH+1:2]; // 地址对齐到4字节
    assign dtcm_wdata = lsu_mem_data_i;
    assign dtcm_wmask = (lsu_mem_req_i & lsu_mem_we_i) ? lsu_mem_wmask_i : 4'b0000;

    if (MEMS_MODE == MEMS_MODE_NEW) begin : g_new
        assign dtcm_addr = lsu_mem_req_i ? lsu_dtcm_addr : if_dtcm_addr;
        assign if_mem_rdata_o = if_dtcm_access ? dtcm_rdata : itcm_rdata;
        assign lsu_mem_data_o = dtcm_rdata;
        assign dtcm_en = 1'b1;
        assign dtcm_wen = lsu_mem_req_i & lsu_mem_we_i;
    end else begin : g_legacy
        assign dtcm_addr = lsu_dtcm_addr;
        assign if_mem_rdata_o = itcm_rdata;
        assign lsu_mem_data_o = dtcm_rdata;
        assign dtcm_en = 1'b1;
        assign dtcm_wen = lsu_mem_we_i;
    end

    itcm #(
        .ITCM_ADDR_WIDTH(ITCM_ADDR_WIDTH),
        .INST_DATA_WIDTH(INST_DATA_WIDTH)
    ) u_itcm (
        .clk(clk),
        .itcm_en(rst_n), // ITCM在复位后始终使能
        .itcm_addr(itcm_addr),
        .itcm_data_o(itcm_rdata)
    );

    dtcm #(
        .DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),
        .BUS_DATA_WIDTH(BUS_DATA_WIDTH)
    ) u_dtcm (
        .clk(clk),
        .dtcm_en(dtcm_en),
        .dtcm_wen(dtcm_wen),
        .dtcm_mask(dtcm_wmask),
        .dtcm_addr(dtcm_addr),
        .dtcm_data_i(dtcm_wdata),
        .dtcm_data_o(dtcm_rdata)
    );



endmodule
