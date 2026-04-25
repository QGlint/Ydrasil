
`include "define_mem_reg.svh"
// 通用寄存器模块
module ydrasil_registers (

    input logic clk,
    input logic rst_n,

    // from ex
    input logic                         rf_wen_rd_i,     // 写寄存器标志
    input logic [`REGS_ADDR_WIDTH-1:0]  rf_waddr_rd_i,  // 写寄存器地址
    input logic [`REGS_DATA_WIDTH-1:0]  rf_wdata_rd_i,  // 写寄存器数据

    // from id
    input logic [`REGS_ADDR_WIDTH-1:0]  rf_raddr_rs1_i,  // 读寄存器1地址

    // to id
    output logic [`REGS_DATA_WIDTH-1:0] rf_rdata_rs1_o,  // 读寄存器1数据

    // from id
    input logic [`REGS_ADDR_WIDTH-1:0]  rf_raddr_rs2_i,  // 读寄存器2地址

    // to id
    output logic [`REGS_DATA_WIDTH-1:0] rf_rdata_rs2_o  // 读寄存器2数据

);

    logic [`REGS_DATA_WIDTH-1:0] registers[0:`REGS_NUM - 1];
    logic [`REGS_NUM-1:0] registers_wen;  // 每个寄存器的写使能信号

    assign registers_wen[0] = 1'b0;  

    genvar i;
    generate
        for (i = 1; i < `REGS_NUM; i = i + 1) begin : gen_regs_we
            assign registers_wen[i] = (rf_wen_rd_i ) && (rf_waddr_rd_i == i) && (!rst_n);
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int j = 0; j < `REGS_NUM; j = j + 1) begin
                registers[j] <= '0;
            end
        end else begin
            for (int j = 1; j < `REGS_NUM; j = j + 1) begin
                if (registers_wen[j]) begin
                    registers[j] <= rf_wdata_rd_i;
                end
            end
        end
    end

    // 读寄存器1
    // 如果读地址为零寄存器，则返回零
    // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
    // 否则返回寄存器值
    assign rf_rdata_rs1_o = (rf_raddr_rs1_i == '0) ? '0 :
                      ((rf_raddr_rs1_i == rf_waddr_rd_i) && (rf_wen_rd_i )) ? rf_wdata_rd_i :
                      registers[rf_raddr_rs1_i];

    // 读寄存器2
    // 如果读地址为零寄存器，则返回零
    // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
    // 否则返回寄存器值
    assign rf_rdata_rs2_o = (rf_raddr_rs2_i == '0) ? '0 :
                      ((rf_raddr_rs2_i == rf_waddr_rd_i) && (rf_wen_rd_i)) ? rf_wdata_rd_i :
                      registers[rf_raddr_rs2_i];

endmodule
