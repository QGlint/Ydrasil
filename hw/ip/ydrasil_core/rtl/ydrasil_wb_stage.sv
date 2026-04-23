`include "defines.svh"

// 写回单元 - 负责寄存器写回逻辑和延迟
module wbu (
    input wire clk,
    input wire rst_n,

    // 来自EXU的ALU数据
    input wire [`REG_DATA_WIDTH-1:0] alu_reg_wdata_i,
    input wire                       alu_reg_we_i,
    input wire [`REG_ADDR_WIDTH-1:0] alu_reg_waddr_i,

    // 来自EXU的MULDIV数据
    input wire [`REG_DATA_WIDTH-1:0] muldiv_reg_wdata_i,
    input wire                       muldiv_reg_we_i,
    input wire [`REG_ADDR_WIDTH-1:0] muldiv_reg_waddr_i,

    // 来自EXU的CSR数据
    input wire [`REG_DATA_WIDTH-1:0] csr_wdata_i,
    input wire                       csr_we_i,
    input wire [`BUS_ADDR_WIDTH-1:0] csr_waddr_i,

    // 添加CSR寄存器写数据输入
    input wire [`REG_DATA_WIDTH-1:0] csr_reg_wdata_i,

    // 来自EXU的AGU/LSU数据
    input wire [`REG_DATA_WIDTH-1:0] agu_reg_wdata_i,
    input wire                       agu_reg_we_i,
    input wire [`REG_ADDR_WIDTH-1:0] agu_reg_waddr_i,

    input wire [`REG_ADDR_WIDTH-1:0] idu_reg_waddr_i,
    // 中断信号
    input wire                       int_assert_i,

    // 寄存器写回接口
    output wire [`REG_DATA_WIDTH-1:0] reg_wdata_o,
    output wire                       reg_we_o,
    output wire [`REG_ADDR_WIDTH-1:0] reg_waddr_o,

    // CSR寄存器写回接口
    output wire [`REG_DATA_WIDTH-1:0] csr_wdata_o,
    output wire                       csr_we_o,
    output wire [`BUS_ADDR_WIDTH-1:0] csr_waddr_o
);

    // 延迟信号声明
    wire [`REG_DATA_WIDTH-1:0] alu_result_delay;
    wire                       alu_reg_we_delay;
    wire [`REG_ADDR_WIDTH-1:0] alu_reg_waddr_delay;

    wire [`REG_DATA_WIDTH-1:0] muldiv_wdata_delay;
    wire                       muldiv_we_delay;
    wire [`REG_ADDR_WIDTH-1:0] muldiv_waddr_delay;

    wire [`REG_DATA_WIDTH-1:0] csr_wdata_delay;
    wire                       csr_we_delay;
    wire [`BUS_ADDR_WIDTH-1:0] csr_waddr_delay;

    // 使用D触发器延迟CSR寄存器数据一个周期 
    wire [`REG_DATA_WIDTH-1:0] csr_reg_wdata_delay;

    wire [`REG_ADDR_WIDTH-1:0] idu_reg_waddr_delay;

    // 中断信号延迟
    wire int_assert_delay;

    // 使用D触发器延迟ALU结果一个周期
    gnrl_dff #(
        .DW(`REG_DATA_WIDTH)
    ) u_alu_result_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (alu_reg_wdata_i),
        .qout (alu_result_delay)
    );

    gnrl_dff #(
        .DW(1)
    ) u_alu_we_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (alu_reg_we_i),
        .qout (alu_reg_we_delay)
    );

    gnrl_dff #(
        .DW(`REG_ADDR_WIDTH)
    ) u_alu_waddr_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (alu_reg_waddr_i),
        .qout (alu_reg_waddr_delay)
    );

    // 使用D触发器延迟MULDIV结果一个周期
    gnrl_dff #(
        .DW(`REG_DATA_WIDTH)
    ) u_muldiv_data_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (muldiv_reg_wdata_i),
        .qout (muldiv_wdata_delay)
    );

    gnrl_dff #(
        .DW(1)
    ) u_muldiv_we_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (muldiv_reg_we_i),
        .qout (muldiv_we_delay)
    );

    gnrl_dff #(
        .DW(`REG_ADDR_WIDTH)
    ) u_muldiv_waddr_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (muldiv_reg_waddr_i),
        .qout (muldiv_waddr_delay)
    );

    // 使用D触发器延迟CSR结果一个周期
    gnrl_dff #(
        .DW(`REG_DATA_WIDTH)
    ) u_csr_data_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (csr_wdata_i),
        .qout (csr_wdata_delay)
    );

    gnrl_dff #(
        .DW(1)
    ) u_csr_we_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (csr_we_i),
        .qout (csr_we_delay)
    );

    gnrl_dff #(
        .DW(`BUS_ADDR_WIDTH)
    ) u_csr_waddr_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (csr_waddr_i),
        .qout (csr_waddr_delay)
    );

    gnrl_dff #(
        .DW(`REG_DATA_WIDTH)
    ) u_csr_rdata_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (csr_reg_wdata_i),
        .qout (csr_reg_wdata_delay)
    );

    gnrl_dff #(
        .DW(`REG_ADDR_WIDTH)
    ) u_idu_waddr_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (idu_reg_waddr_i),
        .qout (idu_reg_waddr_delay)
    );

    // 添加中断信号延迟触发器
    gnrl_dff #(
        .DW(1)
    ) u_int_assert_dff (
        .clk  (clk),
        .rst_n(rst_n),
        .dnxt (int_assert_i),
        .qout (int_assert_delay)
    );

    // 选择优先级：MULDIV > AGU(LSU) > CSR > ALU
    // 注意AGU/LSU数据已经在LSU内部延迟，所以直接使用
    wire [`REG_DATA_WIDTH-1:0] reg_wdata_r;
    wire                       reg_we_r;
    wire [`REG_ADDR_WIDTH-1:0] reg_waddr_r;

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