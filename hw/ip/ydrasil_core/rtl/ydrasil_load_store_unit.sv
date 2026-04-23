/*         
 The MIT License (MIT)

 Copyright © 2025 Yusen Wang @yusen.w@qq.com
                                                                         
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
                                                                         
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
                                                                         
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

`include "defines.svh"

// 地址生成单元 - 处理内存访问和相关寄存器操作
module ydrasil_load_store_unit (
    input wire clk,  // 时钟输入
    input wire rst_n,

    input wire        req_mem_i,
    input wire [31:0] mem_op1_i,
    input wire [31:0] mem_op2_i,
    input wire [31:0] mem_rs2_data_i,
    input wire        mem_op_lb_i,
    input wire        mem_op_lh_i,
    input wire        mem_op_lw_i,
    input wire        mem_op_lbu_i,
    input wire        mem_op_lhu_i,
    input wire        mem_op_sb_i,
    input wire        mem_op_sh_i,
    input wire        mem_op_sw_i,
    input wire        mem_op_load_i,
    input wire        mem_op_store_i,
    input wire [ 4:0] rd_addr_i,

    // 内存数据输入
    input wire [`BUS_DATA_WIDTH-1:0] mem_rdata_i,

    // 中断信号
    input wire int_assert_i,

    // 内存接口输出
    output wire [`BUS_DATA_WIDTH-1:0] mem_wdata_o,
    output wire [`BUS_ADDR_WIDTH-1:0] mem_raddr_o,
    output wire [`BUS_ADDR_WIDTH-1:0] mem_waddr_o,
    output wire                       mem_we_o,
    output wire                       mem_req_o,
    output wire [                3:0] mem_wmask_o,  // 字节写入掩码，4位分别对应4个字节

    // 寄存器写回接口
    output wire [`REG_DATA_WIDTH-1:0] reg_wdata_o,
    output wire                       reg_we_o,
    output wire [`REG_ADDR_WIDTH-1:0] reg_waddr_o
);
    // 内部信号定义
    wire [ 1:0] mem_addr_index;
    wire [31:0] mem_addr;
    wire        valid_op;  // 有效操作信号（无中断且有内存请求）

    // 打一拍后的信号
    wire        valid_op_ff;
    wire        mem_op_lb_ff;
    wire        mem_op_lh_ff;
    wire        mem_op_lw_ff;
    wire        mem_op_lbu_ff;
    wire        mem_op_lhu_ff;
    wire [4:0]  rd_addr_ff;
    // 存储mem_op1_i和mem_op2_i打一拍后的信号
    wire [31:0] mem_op1_ff;
    wire [31:0] mem_op2_ff;
    wire [31:0] mem_addr_ff;
    wire [ 1:0] mem_addr_index_ff;

    // 直接使用输入的load和store信号，不需要在内部重新计算
    wire        is_load_op = mem_op_load_i;
    wire        is_store_op = mem_op_store_i;
    wire        is_load_op_ff;

    // 并行计算基本信号
    assign mem_addr       = mem_op1_i + mem_op2_i;
    assign mem_addr_index = mem_addr[1:0];
    assign valid_op       = req_mem_i & (int_assert_i != `INT_ASSERT);

    // 将关键信号打一拍
    gnrl_dff #(
        .DW(1)
    ) u_valid_op_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (valid_op),
        .qout (valid_op_ff)
    );

    gnrl_dff #(
        .DW(1)
    ) u_is_load_op_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (is_load_op),
        .qout (is_load_op_ff)
    );

    gnrl_dff #(
        .DW(1)
    ) u_mem_op_lb_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (mem_op_lb_i),
        .qout (mem_op_lb_ff)
    );

    gnrl_dff #(
        .DW(1)
    ) u_mem_op_lh_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (mem_op_lh_i),
        .qout (mem_op_lh_ff)
    );

    gnrl_dff #(
        .DW(1)
    ) u_mem_op_lw_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (mem_op_lw_i),
        .qout (mem_op_lw_ff)
    );

    gnrl_dff #(
        .DW(1)
    ) u_mem_op_lbu_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (mem_op_lbu_i),
        .qout (mem_op_lbu_ff)
    );

    gnrl_dff #(
        .DW(1)
    ) u_mem_op_lhu_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (mem_op_lhu_i),
        .qout (mem_op_lhu_ff)
    );

    gnrl_dff #(
        .DW(5)
    ) u_rd_addr_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (rd_addr_i),
        .qout (rd_addr_ff)
    );

    // ：将mem_op1_i和mem_op2_i打一拍
    gnrl_dff #(
        .DW(32)
    ) u_mem_op1_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (mem_op1_i),
        .qout (mem_op1_ff)
    );

    gnrl_dff #(
        .DW(32)
    ) u_mem_op2_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (mem_op2_i),
        .qout (mem_op2_ff)
    );

    // 计算打一拍后的地址及索引
    assign mem_addr_ff = mem_op1_ff + mem_op2_ff;
    assign mem_addr_index_ff = mem_addr_ff[1:0];

    // 使用并行选择逻辑生成内存请求信号
    assign mem_req_o      = (valid_op & (is_load_op | is_store_op)) ? 1'b1 : 1'b0;

    // 并行选择逻辑生成地址
    assign mem_raddr_o    = (valid_op & is_load_op) ? mem_addr : `ZeroWord;
    assign mem_waddr_o    = (valid_op & is_store_op) ? mem_addr : `ZeroWord;

    // 并行选择逻辑生成写使能信号
    assign mem_we_o       = (valid_op & is_store_op) ? `WriteEnable : `WriteDisable;

    // 并行选择逻辑生成寄存器写回控制 - 使用打一拍后的信号
    assign reg_we_o       = (valid_op_ff & is_load_op_ff) ? `WriteEnable : `WriteDisable;
    assign reg_waddr_o    = (valid_op_ff & is_load_op_ff) ? rd_addr_ff : `ZeroWord;

    // 字节加载数据 - 使用并行选择逻辑
    wire [31:0] lb_data, lh_data, lw_data, lbu_data, lhu_data;
    wire [31:0] lb_byte0, lb_byte1, lb_byte2, lb_byte3;
    wire [31:0] lbu_byte0, lbu_byte1, lbu_byte2, lbu_byte3;
    wire [31:0] lh_low, lh_high, lhu_low, lhu_high;

    // 有符号字节加载 - 并行准备所有可能的字节值
    assign lb_byte0 = {{24{mem_rdata_i[7]}}, mem_rdata_i[7:0]};
    assign lb_byte1 = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
    assign lb_byte2 = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
    assign lb_byte3 = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};

    // 无符号字节加载 - 并行准备所有可能的字节值
    assign lbu_byte0 = {24'h0, mem_rdata_i[7:0]};
    assign lbu_byte1 = {24'h0, mem_rdata_i[15:8]};
    assign lbu_byte2 = {24'h0, mem_rdata_i[23:16]};
    assign lbu_byte3 = {24'h0, mem_rdata_i[31:24]};

    // 有符号半字加载 - 并行准备所有可能的半字值
    assign lh_low = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
    assign lh_high = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]};

    // 无符号半字加载 - 并行准备所有可能的半字值
    assign lhu_low = {16'h0, mem_rdata_i[15:0]};
    assign lhu_high = {16'h0, mem_rdata_i[31:16]};

    // 使用并行选择逻辑选择正确的字节/半字/字 - 使用打一拍后的地址索引
    assign lb_data = ({32{mem_addr_index_ff == 2'b00}} & lb_byte0) |
                     ({32{mem_addr_index_ff == 2'b01}} & lb_byte1) |
                     ({32{mem_addr_index_ff == 2'b10}} & lb_byte2) |
                     ({32{mem_addr_index_ff == 2'b11}} & lb_byte3);

    assign lbu_data = ({32{mem_addr_index_ff == 2'b00}} & lbu_byte0) |
                      ({32{mem_addr_index_ff == 2'b01}} & lbu_byte1) |
                      ({32{mem_addr_index_ff == 2'b10}} & lbu_byte2) |
                      ({32{mem_addr_index_ff == 2'b11}} & lbu_byte3);

    assign lh_data = ({32{mem_addr_index_ff[1] == 1'b0}} & lh_low) | ({32{mem_addr_index_ff[1] == 1'b1}} & lh_high);

    assign lhu_data = ({32{mem_addr_index_ff[1] == 1'b0}} & lhu_low) | ({32{mem_addr_index_ff[1] == 1'b1}} & lhu_high);

    assign lw_data = mem_rdata_i;

    // 并行选择最终的寄存器写回数据 - 使用打一拍后的信号
    assign reg_wdata_o = ({32{valid_op_ff & mem_op_lb_ff}} & lb_data) |
                         ({32{valid_op_ff & mem_op_lbu_ff}} & lbu_data) |
                         ({32{valid_op_ff & mem_op_lh_ff}} & lh_data) |
                         ({32{valid_op_ff & mem_op_lhu_ff}} & lhu_data) |
                         ({32{valid_op_ff & mem_op_lw_ff}} & lw_data);

    // 存储操作的掩码和数据 - 使用并行选择逻辑
    // 字节存储掩码和数据
    wire [ 3:0] sb_mask;
    wire [31:0] sb_data;

    assign sb_mask = ({4{mem_addr_index == 2'b00}} & 4'b0001) |
                     ({4{mem_addr_index == 2'b01}} & 4'b0010) |
                     ({4{mem_addr_index == 2'b10}} & 4'b0100) |
                     ({4{mem_addr_index == 2'b11}} & 4'b1000);

    assign sb_data = ({32{mem_addr_index == 2'b00}} & {24'b0, mem_rs2_data_i[7:0]}) |
                     ({32{mem_addr_index == 2'b01}} & {16'b0, mem_rs2_data_i[7:0], 8'b0}) |
                     ({32{mem_addr_index == 2'b10}} & {8'b0, mem_rs2_data_i[7:0], 16'b0}) |
                     ({32{mem_addr_index == 2'b11}} & {mem_rs2_data_i[7:0], 24'b0});

    // 半字存储掩码和数据
    wire [ 3:0] sh_mask;
    wire [31:0] sh_data;

    assign sh_mask = ({4{mem_addr_index[1] == 1'b0}} & 4'b0011) | ({4{mem_addr_index[1] == 1'b1}} & 4'b1100);

    assign sh_data = ({32{mem_addr_index[1] == 1'b0}} & {16'b0, mem_rs2_data_i[15:0]}) |
                     ({32{mem_addr_index[1] == 1'b1}} & {mem_rs2_data_i[15:0], 16'b0});

    // 字存储掩码和数据
    wire [ 3:0] sw_mask;
    wire [31:0] sw_data;

    assign sw_mask = 4'b1111;
    assign sw_data = mem_rs2_data_i;

    // 并行选择最终的存储掩码和数据
    assign mem_wmask_o = ({4{valid_op & mem_op_sb_i}} & sb_mask) |
                         ({4{valid_op & mem_op_sh_i}} & sh_mask) |
                         ({4{valid_op & mem_op_sw_i}} & sw_mask);

    assign mem_wdata_o = ({32{valid_op & mem_op_sb_i}} & sb_data) |
                         ({32{valid_op & mem_op_sh_i}} & sh_data) |
                         ({32{valid_op & mem_op_sw_i}} & sw_data);

endmodule
