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
`include "define_decode.svh"
// core local interruptor module
module ydrasil_clint (

    input wire clk,
    input wire rst_n,

    // from id
    input wire [`INST_ADDR_WIDTH-1:0] instr_addr_i,

    // from ex
    input wire                        ex_branch_jump_i,
    input wire [`INST_ADDR_WIDTH-1:0] ex_branch_target_i,
    // input wire                        muldiv_started_i,
    
    // 添加系统操作输入端口
    input wire [`OP_SYS_INFO_WIDTH-1:0] sys_op_info_i,
    input wire                          sys_op_i,

    // from ctrl
    // input wire                        stall_if_i,

    // from csr_reg
    input wire [`REGS_DATA_WIDTH-1:0] csr_clint_data_i,
    input wire [`REGS_DATA_WIDTH-1:0] csr_clint_mtvec,
    input wire [`REGS_DATA_WIDTH-1:0] csr_clint_mepc,
    input wire [`REGS_DATA_WIDTH-1:0] csr_clint_mstatus,

    input wire global_int_en_i,  // 全局中断使能标志

    // to ctrl
    output wire                     clint_stall_o,

    // to csr_reg
    output wire                       clint_csr_we_o,
    output wire [`CSR_ADDR_WIDTH-1:0] clint_csr_waddr_o,
    output wire [`CSR_ADDR_WIDTH-1:0] clint_csr_raddr_o,
    output wire [`REGS_DATA_WIDTH-1:0] clint_csr_data_o,

    // to ex
    output wire [`INST_ADDR_WIDTH-1:0] clint_ex_int_addr_o,   //ecall和ebreak的返回地址
    output wire                        interrupt_o  //ecall和ebreak的中断信号
);

    wire    sys_op_ecall_i;
    wire    sys_op_ebreak_i;
    wire    sys_op_mret_i;

    assign sys_op_ecall_i = sys_op_info_i[`OP_SYS_ECALL] & sys_op_i;
    assign sys_op_ebreak_i = sys_op_info_i[`OP_SYS_EBREAK] & sys_op_i;
    assign sys_op_mret_i = sys_op_info_i[`OP_SYS_MRET] & sys_op_i;

    // interrupt state machine
    localparam S_INT_IDLE = 4'b0001;  // 空闲状态
    localparam S_INT_SYNC_ASSERT = 4'b0010;  // 同步中断断言状态
    localparam S_INT_ASYNC_ASSERT = 4'b0100;  // 异步中断断言状态 
    localparam S_INT_MRET = 4'b1000;  // 中断返回状态

    // CSR write state machine
    localparam S_CSR_IDLE = 5'b00001;  // CSR写入空闲状态
    localparam S_CSR_MSTATUS = 5'b00010;  // 写入mstatus寄存器状态
    localparam S_CSR_MEPC = 5'b00100;  // 写入mepc寄存器状态
    localparam S_CSR_MSTATUS_MRET = 5'b01000;  // 中断返回时写入mstatus寄存器状态
    localparam S_CSR_MCAUSE = 5'b10000;  // 写入mcause寄存器状态

    reg [`INST_ADDR_WIDTH-1:0] int_addr;
    reg                         int_assert;


    // 状态机和相关信号声明
    wire [                 3:0] int_state;  // 中断状态机当前状态
    reg  [                 4:0] csr_state;  // CSR写状态机当前状态
    reg  [`INST_ADDR_WIDTH-1:0] instr_addr;  // 保存的指令地址
    reg  [                31:0] cause;  // 中断原因代码

    // 下一个状态信号声明
    wire [                 4:0] next_csr_state;  // CSR写状态机下一状态
    wire [`INST_ADDR_WIDTH-1:0] next_instr_addr;  // 下一个保存的指令地址
    wire [                31:0] next_cause;  // 下一个中断原因代码

    // 暂停信号产生逻辑 - 当中断状态机或CSR写状态机不在空闲状态时暂停流水线
    assign clint_stall_o = ((int_state != S_INT_IDLE) | (csr_state != S_CSR_IDLE)) ? 1'b1 : 1'b0;

    // 中断处理逻辑
    assign int_state = 
        ({4{!rst_n}} & S_INT_IDLE) |
        ({4{((sys_op_ecall_i || sys_op_ebreak_i) )}} & S_INT_SYNC_ASSERT) |
        ({4{sys_op_mret_i}} & S_INT_MRET) |
        ({4{!(!rst_n || ((sys_op_ecall_i || sys_op_ebreak_i) ) || sys_op_mret_i)}} & S_INT_IDLE);

    // CSR写状态机的并行选择逻辑
    assign next_csr_state = 
        ({5{!rst_n}} & S_CSR_IDLE) |
        ({5{csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT}} & S_CSR_MEPC) |
        ({5{csr_state == S_CSR_IDLE && int_state == S_INT_MRET}} & S_CSR_MSTATUS_MRET) |
        ({5{csr_state == S_CSR_MEPC}} & S_CSR_MSTATUS) |
        ({5{csr_state == S_CSR_MSTATUS}} & S_CSR_MCAUSE) |
        ({5{csr_state == S_CSR_MCAUSE || csr_state == S_CSR_MSTATUS_MRET}} & S_CSR_IDLE) |
        ({5{!(!rst_n || 
             (csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT) || 
             (csr_state == S_CSR_IDLE && int_state == S_INT_MRET) || 
             csr_state == S_CSR_MEPC || 
             csr_state == S_CSR_MSTATUS || 
             (csr_state == S_CSR_MCAUSE || csr_state == S_CSR_MSTATUS_MRET))}} & S_CSR_IDLE);

    // 下一个中断原因cause值的并行选择逻辑
    assign next_cause = 
        ({32{!rst_n}} & '0) |
        ({32{csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT && sys_op_ecall_i}} & 32'd11) |
        ({32{csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT && sys_op_ebreak_i}} & 32'd3) |
        ({32{csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT && !sys_op_ecall_i && !sys_op_ebreak_i}} & 32'd10) |
        ({32{!(!rst_n || (csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT))}} & cause);

    // 下一个保存的指令地址instr_addr值的并行选择逻辑
    assign next_instr_addr = 
        ({`INST_ADDR_WIDTH{!rst_n}} & '0) |
        ({`INST_ADDR_WIDTH{csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT && ex_branch_jump_i}} & (ex_branch_target_i - 32'h4)) |
        ({`INST_ADDR_WIDTH{csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT && ex_branch_jump_i}} & instr_addr_i) |
        ({`INST_ADDR_WIDTH{!(!rst_n || (csr_state == S_CSR_IDLE && int_state == S_INT_SYNC_ASSERT))}} & instr_addr);

    // 写入CSR寄存器的组合逻辑 - 计算下一个写使能信号
    wire                       next_we_o;  // 下一个写使能信号
    wire [`CSR_ADDR_WIDTH-1:0] next_waddr_o;  // 下一个写地址
    wire [`REGS_DATA_WIDTH-1:0] next_data_o;  // 下一个写数据

    // 计算写使能信号 - 当需要写入任何CSR寄存器时置为WriteEnable
    assign next_we_o = (!rst_n) ? 1'b0 :
                      (csr_state == S_CSR_MEPC || csr_state == S_CSR_MCAUSE || 
                       csr_state == S_CSR_MSTATUS || csr_state == S_CSR_MSTATUS_MRET) ? 1'b1 :
                      1'b0;

    // 计算写地址 - 基于当前状态选择要写入的CSR寄存器地址
    assign next_waddr_o = (!rst_n) ? '0 :
                         (csr_state == S_CSR_MEPC) ? { `CSR_MEPC} :            // 写入mepc寄存器
        (csr_state == S_CSR_MCAUSE) ? {`CSR_MCAUSE} :  // 写入mcause寄存器
        (csr_state == S_CSR_MSTATUS || csr_state == S_CSR_MSTATUS_MRET) ? {`CSR_MSTATUS} : // 写入mstatus寄存器
        '0;

    // 计算写数据 - 基于当前状态确定要写入CSR寄存器的数据
    assign next_data_o = (!rst_n) ? '0 :
                        (csr_state == S_CSR_MEPC) ? instr_addr :                     // 保存当前指令地址到mepc
        (csr_state == S_CSR_MCAUSE) ? cause :  // 写入中断原因到mcause
        (csr_state == S_CSR_MSTATUS) ? {csr_clint_mstatus[31:4], 1'b0, csr_clint_mstatus[2:0]} :      // 中断发生时修改mstatus，关闭全局中断
        (csr_state == S_CSR_MSTATUS_MRET) ? {csr_clint_mstatus[31:4], csr_clint_mstatus[7], csr_clint_mstatus[2:0]} : // 中断返回时恢复mstatus
        '0;

    // 发送中断信号到ex模块的组合逻辑
    wire                        next_int_assert_o;  // 下一个中断断言信号
    wire [`INST_ADDR_WIDTH-1:0] next_int_addr_o;  // 下一个中断地址

    // 计算中断断言信号 - 在完成CSR写入或中断返回时断言
    assign next_int_assert_o = (!rst_n) ? 1'b0 :
                              (csr_state == S_CSR_MCAUSE || csr_state == S_CSR_MSTATUS_MRET) ? 1'b1 :
                              1'b0;

    // 计算中断地址 - 中断处理或中断返回的目标地址
    assign next_int_addr_o = (!rst_n) ? '0 :
                            (csr_state == S_CSR_MCAUSE) ? csr_clint_mtvec :      // 中断发生时跳转到mtvec
        (csr_state == S_CSR_MSTATUS_MRET) ? csr_clint_mepc :  // 中断返回时跳转到mepc
        '0;

    reg                         we_o;
    reg [`CSR_ADDR_WIDTH-1:0]   waddr_o;
    reg [`CSR_ADDR_WIDTH-1:0]   raddr_o;
    reg [`REGS_DATA_WIDTH-1:0]  data_o;

    // 一级时序寄存器：仅寄存，不改assign组合逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_state     <= S_CSR_IDLE;
            cause         <= 32'h0;
            instr_addr     <= {`INST_ADDR_WIDTH{1'b0}};
            we_o          <= 1'b0;
            waddr_o       <= {`CSR_ADDR_WIDTH{1'b0}};
            data_o        <= {`REGS_DATA_WIDTH{1'b0}};
            int_assert  <= 1'b0;
            int_addr    <= {`INST_ADDR_WIDTH{1'b0}};
            raddr_o       <= {`CSR_ADDR_WIDTH{1'b0}};
        end else begin
            csr_state     <= next_csr_state;
            cause         <= next_cause;
            instr_addr     <= next_instr_addr;
            we_o          <= next_we_o;
            waddr_o       <= next_waddr_o;
            data_o        <= next_data_o;
            int_assert  <= next_int_assert_o;
            int_addr    <= next_int_addr_o;
            raddr_o       <= {`CSR_ADDR_WIDTH{1'b0}};
        end
    end


    assign clint_csr_we_o = we_o;
    assign clint_csr_waddr_o = waddr_o;
    assign clint_csr_raddr_o = raddr_o;
    assign clint_csr_data_o = data_o;
    assign interrupt_o = int_assert;
    assign clint_ex_int_addr_o = int_addr;

endmodule
