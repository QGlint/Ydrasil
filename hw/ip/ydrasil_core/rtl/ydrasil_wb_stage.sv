`include "defines.svh"

// 写回单元 - 负责寄存器写回逻辑和延迟
module ydrasil_wb_stage (
    input logic clk,
    input logic rst_n,

    // 来自EXU的ALU数据
    input logic [`REG_DATA_WIDTH-1:0] alu_reg_wdata_i,
    input logic                       alu_reg_we_i,
    input logic [`REG_ADDR_WIDTH-1:0] alu_reg_waddr_i,

    // 来自EXU的MULDIV数据
    input logic [`REG_DATA_WIDTH-1:0] muldiv_reg_wdata_i,
    input logic                       muldiv_reg_we_i,
    input logic [`REG_ADDR_WIDTH-1:0] muldiv_reg_waddr_i,

    // 来自EXU的CSR数据
    input logic [`REG_DATA_WIDTH-1:0] csr_wdata_i,
    input logic                       csr_we_i,
    input logic [`BUS_ADDR_WIDTH-1:0] csr_waddr_i,

    // 添加CSR寄存器写数据输入
    input logic [`REG_DATA_WIDTH-1:0] csr_reg_wdata_i,

    // 来自EXU的AGU/LSU数据
    input logic [`REG_DATA_WIDTH-1:0] agu_reg_wdata_i,
    input logic                       agu_reg_we_i,
    input logic [`REG_ADDR_WIDTH-1:0] agu_reg_waddr_i,

    input logic [`REG_ADDR_WIDTH-1:0] idu_reg_waddr_i,
    // 中断信号
    input logic                       int_assert_i,

    // 寄存器写回接口
    output logic [`REG_DATA_WIDTH-1:0] reg_wdata_o,
    output logic                       reg_we_o,
    output logic [`REG_ADDR_WIDTH-1:0] reg_waddr_o,

    // CSR寄存器写回接口
    output logic [`REG_DATA_WIDTH-1:0] csr_wdata_o,
    output logic                       csr_we_o,
    output logic [`BUS_ADDR_WIDTH-1:0] csr_waddr_o
);

    // 延迟信号声明
    logic [`REG_DATA_WIDTH-1:0] alu_result_delay;
    logic                       alu_reg_we_delay;
    logic [`REG_ADDR_WIDTH-1:0] alu_reg_waddr_delay;

    logic [`REG_DATA_WIDTH-1:0] muldiv_wdata_delay;
    logic                       muldiv_we_delay;
    logic [`REG_ADDR_WIDTH-1:0] muldiv_waddr_delay;

    logic [`REG_DATA_WIDTH-1:0] csr_wdata_delay;
    logic                       csr_we_delay;
    logic [`BUS_ADDR_WIDTH-1:0] csr_waddr_delay;

    // 使用D触发器延迟CSR寄存器数据一个周期 
    logic [`REG_DATA_WIDTH-1:0] csr_reg_wdata_delay;

    logic [`REG_ADDR_WIDTH-1:0] idu_reg_waddr_delay;

    // 中断信号延迟
    logic int_assert_delay;

    // 统一打一拍寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_delay    <= '0;
            alu_reg_we_delay    <= 1'b0;
            alu_reg_waddr_delay <= '0;

            muldiv_wdata_delay  <= '0;
            muldiv_we_delay     <= 1'b0;
            muldiv_waddr_delay  <= '0;

            csr_wdata_delay     <= '0;
            csr_we_delay        <= 1'b0;
            csr_waddr_delay     <= '0;

            csr_reg_wdata_delay <= '0;
            idu_reg_waddr_delay <= '0;
            int_assert_delay    <= 1'b0;
        end
        else begin
            alu_result_delay    <= alu_reg_wdata_i;
            alu_reg_we_delay    <= alu_reg_we_i;
            alu_reg_waddr_delay <= alu_reg_waddr_i;

            muldiv_wdata_delay  <= muldiv_reg_wdata_i;
            muldiv_we_delay     <= muldiv_reg_we_i;
            muldiv_waddr_delay  <= muldiv_reg_waddr_i;

            csr_wdata_delay     <= csr_wdata_i;
            csr_we_delay        <= csr_we_i;
            csr_waddr_delay     <= csr_waddr_i;

            csr_reg_wdata_delay <= csr_reg_wdata_i;
            idu_reg_waddr_delay <= idu_reg_waddr_i;
            int_assert_delay    <= int_assert_i;
        end
    end

    // 选择优先级：MULDIV > AGU(LSU) > CSR > ALU
    // 注意AGU/LSU数据已经在LSU内部延迟，所以直接使用
    logic [`REG_DATA_WIDTH-1:0] reg_wdata_r;
    logic                       reg_we_r;
    logic [`REG_ADDR_WIDTH-1:0] reg_waddr_r;

    // 使用assign语句实现优先级选择逻辑，避免X不定态传播
    assign reg_wdata_r = muldiv_we_delay ? muldiv_wdata_delay :
                         agu_reg_we_i ? agu_reg_wdata_i :
                         csr_we_delay ? csr_reg_wdata_delay :
                         alu_result_delay;

    assign reg_we_r = (int_assert_delay == `INT_ASSERT) ? `WriteDisable :
                      (muldiv_we_delay || agu_reg_we_i || csr_we_delay || alu_reg_we_delay);

    assign reg_waddr_r = (int_assert_delay == `INT_ASSERT) ? `ZeroReg :
                         muldiv_we_delay ? muldiv_waddr_delay :
                         agu_reg_we_i ? agu_reg_waddr_i :
                         alu_reg_we_delay ? alu_reg_waddr_delay :
                         idu_reg_waddr_delay;

    // 输出赋值
    assign reg_wdata_o = reg_wdata_r;
    assign reg_we_o = reg_we_r;
    assign reg_waddr_o = reg_waddr_r;

    // CSR输出赋值
    assign csr_we_o = (int_assert_delay == `INT_ASSERT) ? `WriteDisable : csr_we_delay;
    assign csr_wdata_o = csr_wdata_delay;
    assign csr_waddr_o = csr_waddr_delay;

endmodule