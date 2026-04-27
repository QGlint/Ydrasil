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

`include "define_mem_reg.svh"
`include "define_rv32i_ins.svh"

// CSR寄存器模块
module ydrasil_registers_csr (

    input wire clk,
    input wire rst_n,

    // form ex
    input wire                          ex_csr_wen_i,     // ex模块写寄存器标志
    input wire [`CSR_ADDR_WIDTH-1:0]    id_csr_raddr_i,  // ex模块读寄存器地址
    input wire [`CSR_ADDR_WIDTH-1:0]    ex_csr_waddr_i,  // ex模块写寄存器地址
    input wire [`REGS_DATA_WIDTH-1:0]   ex_csr_data_i,   // ex模块写寄存器数据

    // from clint
    input wire                          clint_csr_we_i,     // clint模块写寄存器标志
    input wire [`CSR_ADDR_WIDTH-1:0]    clint_csr_raddr_i,  // clint模块读寄存器地址
    input wire [`CSR_ADDR_WIDTH-1:0]    clint_csr_waddr_i,  // clint模块写寄存器地址
    input wire [`REGS_DATA_WIDTH-1:0]   clint_csr_data_i,   // clint模块写寄存器数据

    output wire global_int_en_o,  // 全局中断使能标志

    // to clint
    output wire [`REGS_DATA_WIDTH-1:0] csr_clint_data_o,      // clint模块读寄存器数据
    output wire [`REGS_DATA_WIDTH-1:0] csr_clint_mtvec,   // mtvec
    output wire [`REGS_DATA_WIDTH-1:0] csr_clint_mepc,    // mepc
    output wire [`REGS_DATA_WIDTH-1:0] csr_clint_mstatus, // mstatus

    // to ex
    output wire [`REGS_DATA_WIDTH-1:0] csr_ex_data_o  // ex模块读寄存器数据

);

    reg  [`DOUBLE_REGS_WIDTH-1:0] cycle;
    reg  [  `REGS_DATA_WIDTH-1:0] mtvec;
    reg  [  `REGS_DATA_WIDTH-1:0] mcause;
    reg  [  `REGS_DATA_WIDTH-1:0] mepc;
    reg  [  `REGS_DATA_WIDTH-1:0] mie;
    reg  [  `REGS_DATA_WIDTH-1:0] mstatus;
    reg  [  `REGS_DATA_WIDTH-1:0] mscratch;

    // 内部寄存器的值更新信号
    wire [  `REGS_DATA_WIDTH-1:0] mtvec_next;
    wire [  `REGS_DATA_WIDTH-1:0] mcause_next;
    wire [  `REGS_DATA_WIDTH-1:0] mepc_next;
    wire [  `REGS_DATA_WIDTH-1:0] mie_next;
    wire [  `REGS_DATA_WIDTH-1:0] mstatus_next;
    wire [  `REGS_DATA_WIDTH-1:0] mscratch_next;
    wire [`DOUBLE_REGS_WIDTH-1:0] cycle_next;

    // 寄存器写使能信号
    wire                         mtvec_we;
    wire                         mcause_we;
    wire                         mepc_we;
    wire                         mie_we;
    wire                         mstatus_we;
    wire                         mscratch_we;

    assign global_int_en_o   = (mstatus[3] == 1'b1) ? 1'b1 : 1'b0;


    assign csr_clint_mtvec   = mtvec;
    assign csr_clint_mepc    = mepc;
    assign csr_clint_mstatus = mstatus;

    // cycle counter
    // 复位撤销后就一直计数
    assign cycle_next        = cycle + 1'b1;

    // 一级时序寄存器：仅寄存，不改assign组合逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle    <= {`DOUBLE_REGS_WIDTH{1'b0}};
            mtvec    <= {`REGS_DATA_WIDTH{1'b0}};
            mcause   <= {`REGS_DATA_WIDTH{1'b0}};
            mepc     <= {`REGS_DATA_WIDTH{1'b0}};
            mie      <= {`REGS_DATA_WIDTH{1'b0}};
            mstatus  <= {`REGS_DATA_WIDTH{1'b0}};
            mscratch <= {`REGS_DATA_WIDTH{1'b0}};
        end else begin
            cycle <= cycle_next;
            if (mtvec_we)    mtvec    <= mtvec_next;
            if (mcause_we)   mcause   <= mcause_next;
            if (mepc_we)     mepc     <= mepc_next;
            if (mie_we)      mie      <= mie_next;
            if (mstatus_we)  mstatus  <= mstatus_next;
            if (mscratch_we) mscratch <= mscratch_next;
        end
    end

    // 计算寄存器写使能信号和下一个值
    // 优先响应ex模块的写操作，其次是clint模块
    assign mtvec_we = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MTVEC) || 
                      (clint_csr_we_i  && clint_csr_waddr_i[11:0] == `CSR_MTVEC);
    assign mtvec_next = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MTVEC) ? ex_csr_data_i : clint_csr_data_i;

    assign mcause_we = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MCAUSE) || 
                       (clint_csr_we_i  && clint_csr_waddr_i[11:0] == `CSR_MCAUSE);
    assign mcause_next = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MCAUSE) ? ex_csr_data_i : clint_csr_data_i;

    assign mepc_we = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MEPC) || 
                     (clint_csr_we_i  && clint_csr_waddr_i[11:0] == `CSR_MEPC);
    assign mepc_next = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MEPC) ? ex_csr_data_i : clint_csr_data_i;

    assign mie_we = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MIE) || 
                    (clint_csr_we_i  && clint_csr_waddr_i[11:0] == `CSR_MIE);
    assign mie_next = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MIE) ? ex_csr_data_i : clint_csr_data_i;

    assign mstatus_we = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MSTATUS) || 
                        (clint_csr_we_i  && clint_csr_waddr_i[11:0] == `CSR_MSTATUS);
    assign mstatus_next = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MSTATUS) ? ex_csr_data_i : clint_csr_data_i;

    assign mscratch_we = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MSCRATCH) || 
                         (clint_csr_we_i  && clint_csr_waddr_i[11:0] == `CSR_MSCRATCH);
    assign mscratch_next = (ex_csr_wen_i  && ex_csr_waddr_i[11:0] == `CSR_MSCRATCH) ? ex_csr_data_i : clint_csr_data_i;



    // ex模块读CSR寄存器
    assign csr_ex_data_o = ((ex_csr_waddr_i[11:0] == id_csr_raddr_i[11:0]) && (ex_csr_wen_i )) ? ex_csr_data_i :
                   (id_csr_raddr_i[11:0] == `CSR_CYCLE) ? cycle[31:0] :
                   (id_csr_raddr_i[11:0] == `CSR_CYCLEH) ? cycle[63:32] :
                   (id_csr_raddr_i[11:0] == `CSR_MTVEC) ? mtvec :
                   (id_csr_raddr_i[11:0] == `CSR_MCAUSE) ? mcause :
                   (id_csr_raddr_i[11:0] == `CSR_MEPC) ? mepc :
                   (id_csr_raddr_i[11:0] == `CSR_MIE) ? mie :
                   (id_csr_raddr_i[11:0] == `CSR_MSTATUS) ? mstatus :
                   (id_csr_raddr_i[11:0] == `CSR_MSCRATCH) ? mscratch :
                   '0;

    // clint模块读CSR寄存器
    assign csr_clint_data_o = ((clint_csr_waddr_i[11:0] == clint_csr_raddr_i[11:0]) && (clint_csr_we_i )) ? clint_csr_data_i :
                         (clint_csr_raddr_i[11:0] == `CSR_CYCLE) ? cycle[31:0] :
                         (clint_csr_raddr_i[11:0] == `CSR_CYCLEH) ? cycle[63:32] :
                         (clint_csr_raddr_i[11:0] == `CSR_MTVEC) ? mtvec :
                         (clint_csr_raddr_i[11:0] == `CSR_MCAUSE) ? mcause :
                         (clint_csr_raddr_i[11:0] == `CSR_MEPC) ? mepc :
                         (clint_csr_raddr_i[11:0] == `CSR_MIE) ? mie :
                         (clint_csr_raddr_i[11:0] == `CSR_MSTATUS) ? mstatus :
                         (clint_csr_raddr_i[11:0] == `CSR_MSCRATCH) ? mscratch :
                         '0;

endmodule
