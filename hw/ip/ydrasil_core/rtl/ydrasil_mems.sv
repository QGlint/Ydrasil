// 内存管理模块，包含ITCM和DTCM
module ydrasil_mems 
import ydrasil_pkg::*;
(
    input wire clk,
    input wire rst_n,

    // PC访问接口
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr_i,   // PC地址
    output wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] if_mem_rdata_o, // 指令输出
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] if_mem_addr1_i,
    output wire [ydrasil_pkg::INST_DATA_WIDTH-1:0] if_mem_rdata1_o,

    // LSU data-memory request
    input  wire                         lsu_load_valid_i,
    input  wire [BUS_ADDR_WIDTH-1:0]   lsu_load_addr_i,
    input  wire                         lsu_store_valid_i,
    input  wire [BUS_ADDR_WIDTH-1:0]   lsu_store_addr_i,
    input  wire [BUS_DATA_WIDTH-1:0]   lsu_store_data_i,
    input  wire [3:0]                  lsu_store_mask_i,
    output wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0] lsu_mem_data_o,  

    input  wire                         dram_sel_i       // 来自EXU的DRAM访问选择信号
    // 暂停信号
    // output wire hold_flag_o  // 暂停流水线信号
);


    wire [ITCM_ADDR_WIDTH-2:0] itcm_addr;
    wire [(2*INST_DATA_WIDTH)-1:0] itcm_rdata;
    reg itcm_addr_odd_q;
    wire [INST_DATA_WIDTH-1:0] itcm_instr;
    wire [INST_DATA_WIDTH-1:0] itcm_instr1;

    wire [DTCM_ADDR_WIDTH-1:0] dtcm_addr;
    wire [BUS_DATA_WIDTH-1:0] dtcm_rdata;
    wire [BUS_DATA_WIDTH-1:0] dtcm_wdata;
    wire        dtcm_wen;
    wire        dtcm_ren;
    wire [3:0]  dtcm_wmask;

    localparam [31:0] DTCM_BYTE_SIZE = (32'd1 << DTCM_ADDR_WIDTH) << 2;
`ifdef TARGET_FPGA
    localparam bit IF_DTCM_FETCH_ENABLE = 1'b0;
`else
`ifdef TARGET_SYNTHESIS
    localparam bit IF_DTCM_FETCH_ENABLE = 1'b0;
`else
`ifdef SYNTHESIS
    localparam bit IF_DTCM_FETCH_ENABLE = 1'b0;
`else
    localparam bit IF_DTCM_FETCH_ENABLE = 1'b1;
`endif
`endif
`endif

    wire if_dtcm_sel;
    wire if_dtcm_sel1;
    wire if_dtcm_access;
    wire [DTCM_ADDR_WIDTH-1:0] if_dtcm_addr;
    wire [DTCM_ADDR_WIDTH-1:0] lsu_dtcm_addr;

    assign if_dtcm_sel = (if_mem_addr_i >= DTCM_BASE_ADDR) &&
                         (if_mem_addr_i < (DTCM_BASE_ADDR + DTCM_BYTE_SIZE));
    assign if_dtcm_sel1 = (if_mem_addr1_i >= DTCM_BASE_ADDR) &&
                          (if_mem_addr1_i < (DTCM_BASE_ADDR + DTCM_BYTE_SIZE));
    assign if_dtcm_access = IF_DTCM_FETCH_ENABLE & if_dtcm_sel;
    assign if_dtcm_addr = if_mem_addr_i[DTCM_ADDR_WIDTH+1:2];
    assign lsu_dtcm_addr = lsu_load_addr_i[DTCM_ADDR_WIDTH+1:2];

    assign itcm_addr = if_mem_addr_i[ITCM_ADDR_WIDTH+1:3];
    assign itcm_instr = itcm_addr_odd_q ?
        itcm_rdata[(2*INST_DATA_WIDTH)-1:INST_DATA_WIDTH] :
        itcm_rdata[INST_DATA_WIDTH-1:0];
    assign itcm_instr1 = itcm_addr_odd_q ? RV32I_INS_NOP :
        itcm_rdata[(2*INST_DATA_WIDTH)-1:INST_DATA_WIDTH];
    assign dtcm_wdata = lsu_store_data_i;
    assign dtcm_wmask = lsu_store_mask_i;

    // FPGA/synthesis builds never fetch instructions from DTCM. Express that
    // constant here so LSU request valid is not part of every BRAM address bit.
    assign dtcm_addr = IF_DTCM_FETCH_ENABLE ?
        (lsu_load_valid_i ? lsu_dtcm_addr : if_dtcm_addr) : lsu_dtcm_addr;
    assign if_mem_rdata_o = if_dtcm_access ? dtcm_rdata : itcm_instr;
    // DTCM self-modifying execution is a simulation aid only.  The second
    // fetch lane is deliberately suppressed there because DTCM has one port.
    assign if_mem_rdata1_o = (IF_DTCM_FETCH_ENABLE & if_dtcm_sel1) ?
        RV32I_INS_NOP : itcm_instr1;
    assign lsu_mem_data_o = dtcm_rdata;
    assign dtcm_ren = IF_DTCM_FETCH_ENABLE ?
        (lsu_load_valid_i | if_dtcm_access) : lsu_load_valid_i;
    assign dtcm_wen = lsu_store_valid_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            itcm_addr_odd_q <= 1'b0;
        else
            itcm_addr_odd_q <= if_mem_addr_i[2];
    end

    ydrasil_itcm #(
        .ITCM_ADDR_WIDTH(ITCM_ADDR_WIDTH),
        .INST_DATA_WIDTH(INST_DATA_WIDTH),
        .INIT_FILE(ITCM_INIT_FILE),
        .INIT_ENABLE(INIT_ITCM != 0)
    ) u_itcm (
        .clk(clk),
        .itcm_en(rst_n), // ITCM在复位后始终使能
        .itcm_addr(itcm_addr),
        .itcm_data_o(itcm_rdata)
    );

    ydrasil_dtcm #(
        .DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),
        .BUS_DATA_WIDTH(BUS_DATA_WIDTH),
        .INIT_FILE(DTCM_INIT_FILE),
        .INIT_ENABLE(INIT_DTCM != 0)
    ) u_dtcm (
        .clk(clk),
        .dtcm_ren(dtcm_ren),
        .dtcm_wen(dtcm_wen),
        .dtcm_mask(dtcm_wmask),
        .dtcm_raddr(dtcm_addr),
        .dtcm_waddr(lsu_store_addr_i[DTCM_ADDR_WIDTH+1:2]),
        .dtcm_data_i(dtcm_wdata),
        .dtcm_data_o(dtcm_rdata)
    );



endmodule
