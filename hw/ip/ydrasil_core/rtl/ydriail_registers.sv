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

`include "define_specal_ins.svh"

// 通用寄存器模块
module ydriail_logicisters (

    input logic clk,
    input logic rst_n,

    // from ex
    input logic                       we_i,     // 写寄存器标志
    input logic [`logic_ADDR_WIDTH-1:0] waddr_i,  // 写寄存器地址
    input logic [`logic_DATA_WIDTH-1:0] wdata_i,  // 写寄存器数据

    // from id
    input logic [`logic_ADDR_WIDTH-1:0] raddr1_i,  // 读寄存器1地址

    // to id
    output logic [`logic_DATA_WIDTH-1:0] rdata1_o,  // 读寄存器1数据

    // from id
    input logic [`logic_ADDR_WIDTH-1:0] raddr2_i,  // 读寄存器2地址

    // to id
    output logic [`logic_DATA_WIDTH-1:0] rdata2_o  // 读寄存器2数据

);

    logic [`logic_DATA_WIDTH-1:0] logics[0:`logic_NUM - 1];
    logic [`logic_NUM-1:0] logic_we;  // 每个寄存器的写使能信号

    assign logic_we[0] = 1'b0;  

    genvar i;
    generate
        for (i = 1; i < `logic_NUM; i = i + 1) begin : gen_logic_we
            assign logic_we[i] = (we_i == `WriteEnable) && (waddr_i == i) && (rst_n == `RstDisable);
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int j = 0; j < `logic_NUM; j = j + 1) begin
                logics[j] <= `ZeroWord;
            end
        end else begin
            for (int j = 1; j < `logic_NUM; j = j + 1) begin
                if (logic_we[j]) begin
                    logics[j] <= wdata_i;
                end
            end
        end
    end

    // 读寄存器1
    // 如果读地址为零寄存器，则返回零
    // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
    // 否则返回寄存器值
    assign rdata1_o = (raddr1_i == `ZeroReg) ? `ZeroWord :
                      ((raddr1_i == waddr_i) && (we_i == `WriteEnable)) ? wdata_i :
                      logics[raddr1_i];

    // 读寄存器2
    // 如果读地址为零寄存器，则返回零
    // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
    // 否则返回寄存器值
    assign rdata2_o = (raddr2_i == `ZeroReg) ? `ZeroWord :
                      ((raddr2_i == waddr_i) && (we_i == `WriteEnable)) ? wdata_i :
                      logics[raddr2_i];

endmodule
