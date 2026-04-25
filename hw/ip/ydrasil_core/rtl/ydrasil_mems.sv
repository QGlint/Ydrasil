`include "define_mem_reg.svh"

// 内存管理模块，包含ITCM和DTCM
module ydrasil_mems (
    input logic clk,
    input logic rst_n,

    // PC访问接口
    input  logic [`INST_ADDR_WIDTH-1:0] if_mem_addr_o,   // PC地址
    output logic [`INST_DATA_WIDTH-1:0] if_mem_rdata_i, // 指令输出

    // EX访问接口
    input  logic [`BUS_ADDR_WIDTH-1:0] lsu_mem_addr_i,  // EX访问地址
    input  logic [`BUS_DATA_WIDTH-1:0] lsu_mem_data_i,  // EX写入数据
    output logic [`BUS_DATA_WIDTH-1:0] lsu_mem_data_o,  // EX读出数据
    input  logic                       lsu_mem_we_i,    // EX写使能
    input  logic                       lsu_mem_req_i,   // EX访问请求
    input  logic [                3:0] lsu_mem_wmask_i, // EX字节写入掩码

    // 暂停信号
    output logic hold_flag_o  // 暂停流水线信号
);

    // 地址译码信号
    logic                        ex_access_itcm;
    logic                        ex_access_dtcm;
    logic                       ex_access_itcm_ff;  // 打一拍后的信号
    logic                       ex_access_dtcm_ff;  // 打一拍后的信号

    // ITCM仲裁信号
    logic                        pc_itcm_req;
    logic                        ex_itcm_req;
    logic                        itcm_grant_to_ex;
    logic                           itcm_grant_to_ex_ff;  // 打一拍后的信号

    // ITCM接口
    logic [`ITCM_ADDR_WIDTH-1:0] itcm_addr;
    logic [`INST_DATA_WIDTH-1:0] itcm_data_out;
    logic                        itcm_ce;
    logic                        itcm_we;
    logic [                 3:0] itcm_wmask;
    logic [`INST_DATA_WIDTH-1:0] itcm_data_in;

    // DTCM接口
    logic [`DTCM_ADDR_WIDTH-1:0] dtcm_addr;
    logic [`INST_DATA_WIDTH-1:0] dtcm_data_out;
    logic                        dtcm_ce;
    logic                        dtcm_we;
    logic [                 3:0] dtcm_wmask;
    logic [`INST_DATA_WIDTH-1:0] dtcm_data_in;

    // 地址译码 - 确定EX访问的是ITCM还是DTCM
    assign ex_access_itcm   = (lsu_mem_addr_i >= `ITCM_BASE_ADDR && lsu_mem_addr_i < (`ITCM_BASE_ADDR + `ITCM_SIZE)) && lsu_mem_req_i;
    assign ex_access_dtcm   = (lsu_mem_addr_i >= `DTCM_BASE_ADDR && lsu_mem_addr_i < (`DTCM_BASE_ADDR + `DTCM_SIZE)) && lsu_mem_req_i;

    // 为访问类型和ITCM授权信号打一拍
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_access_itcm_ff   <= 1'b0;
            ex_access_dtcm_ff   <= 1'b0;
            itcm_grant_to_ex_ff <= 1'b0;
        end
        else begin
            ex_access_itcm_ff   <= ex_access_itcm;
            ex_access_dtcm_ff   <= ex_access_dtcm;
            itcm_grant_to_ex_ff <= itcm_grant_to_ex;
        end
    end

    // ITCM仲裁 - PC和EX都可能访问ITCM
    assign pc_itcm_req      = 1'b1;  // PC总是请求ITCM
    assign ex_itcm_req      = ex_access_itcm;

    // 优先考虑EX对ITCM的访问请求
    assign itcm_grant_to_ex = ex_itcm_req;

    // 根据仲裁结果设置ITCM地址和控制信号
    assign itcm_addr        = itcm_grant_to_ex ? (lsu_mem_addr_i - `ITCM_BASE_ADDR) : (if_mem_addr_o - `ITCM_BASE_ADDR);
    assign itcm_ce          = itcm_grant_to_ex ? 1'b1 : pc_itcm_req;
    assign itcm_we          = itcm_grant_to_ex ? lsu_mem_we_i : 1'b0;
    assign itcm_wmask       = itcm_grant_to_ex ? lsu_mem_wmask_i : 4'b0000;
    assign itcm_data_in     = lsu_mem_data_i;

    // 设置DTCM地址和控制信号
    assign dtcm_addr        = lsu_mem_addr_i - `DTCM_BASE_ADDR;
    assign dtcm_ce          = lsu_mem_req_i && ex_access_dtcm;
    assign dtcm_we          = lsu_mem_req_i && ex_access_dtcm && lsu_mem_we_i;
    assign dtcm_wmask       = lsu_mem_req_i && ex_access_dtcm ? lsu_mem_wmask_i : 4'b0000;
    assign dtcm_data_in     = lsu_mem_req_i && ex_access_dtcm ? lsu_mem_data_i : 32'h0;

    // 选择正确的数据返回给EX - 使用打一拍后的信号
    assign lsu_mem_data_o        = ex_access_itcm_ff ? itcm_data_out : ex_access_dtcm_ff ? dtcm_data_out : 32'h0;

    // 选择正确的指令返回给IF - 使用打一拍后的信号
    assign if_mem_rdata_i           = itcm_grant_to_ex_ff ? 32'h00000013 : itcm_data_out;  // 如果EX使用ITCM，返回NOP指令

    // 设置暂停信号 - 这里不打拍，保持原样以便立即暂停流水线
    assign hold_flag_o      = itcm_grant_to_ex;

    // ITCM模块例化 - 使用参数化和宏定义控制初始化
    gnrl_ram #(
        .ADDR_WIDTH(`ITCM_ADDR_WIDTH),
        .DATA_WIDTH(`BUS_DATA_WIDTH),
        .INIT_MEM  (`INIT_ITCM),        // 使用宏定义控制是否初始化
        .INIT_FILE (`ITCM_INIT_FILE)    // 使用宏定义指定初始化文件
    ) u_itcm (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr_i   (itcm_addr),
        .data_o   (itcm_data_out)
    );

    // DTCM模块例化 - 使用参数化，默认不初始化
    gnrl_ram #(
        .ADDR_WIDTH(`DTCM_ADDR_WIDTH),
        .DATA_WIDTH(`BUS_DATA_WIDTH),
        .INIT_MEM  (0)                  // DTCM默认不初始化
    ) u_dtcm (
        .clk      (clk),
        .rst_n    (rst_n),
        .we_i     (dtcm_we),
        .we_mask_i(dtcm_wmask),
        .addr_i   (dtcm_addr),
        .data_i   (dtcm_data_in),
        .data_o   (dtcm_data_out)
    );

endmodule
