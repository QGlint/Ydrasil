
`include "define_mem_reg.svh"
// 通用寄存器模块
module ydrasil_registers (

    input wire clk,
    input wire rst_n,

    // from ex
    input wire                         rf_wen_rd_i,     // 写寄存器标志
    input wire [`REGS_ADDR_WIDTH-1:0]  rf_waddr_rd_i,  // 写寄存器地址
    input wire [`REGS_DATA_WIDTH-1:0]  rf_wdata_rd_i,  // 写寄存器数据

    // from id
    input wire [`REGS_ADDR_WIDTH-1:0]  rf_raddr_rs1_i,  // 读寄存器1地址

    // to id
    output wire [`REGS_DATA_WIDTH-1:0] rf_rdata_rs1_o,  // 读寄存器1数据

    // from id
    input wire [`REGS_ADDR_WIDTH-1:0]  rf_raddr_rs2_i,  // 读寄存器2地址

    // to id
    output wire [`REGS_DATA_WIDTH-1:0] rf_rdata_rs2_o  // 读寄存器2数据

);

    reg [`REGS_DATA_WIDTH-1:0] registers[0:`REGS_NUM - 1];

    wire [`REGS_NUM-1:0] registers_wen;  // 每个寄存器的写使能信号

    assign registers_wen[0] = 1'b0;  

    genvar i;
    generate
        for (i = 1; i < `REGS_NUM; i = i + 1) begin : gen_regs_we
            assign registers_wen[i] = (rf_wen_rd_i ) && (rf_waddr_rd_i == i) && (rst_n);
        end
    endgenerate

    genvar j;
    generate
        for (j = 0; j < `REGS_NUM; j = j + 1) begin : gen_regs
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    registers[j] <= '0;
                end else begin
                    if (registers_wen[j]) begin
                        registers[j] <= rf_wdata_rd_i;
                    end
                end
            end
        end
    endgenerate


    assign rf_rdata_rs1_o = (rf_raddr_rs1_i == '0) ? '0 :
                      ((rf_raddr_rs1_i == rf_waddr_rd_i) && (rf_wen_rd_i)) ? rf_wdata_rd_i :
                       registers[rf_raddr_rs1_i];

    assign rf_rdata_rs2_o = (rf_raddr_rs2_i == '0) ? '0 :
                      ((rf_raddr_rs2_i == rf_waddr_rd_i) && (rf_wen_rd_i)) ? rf_wdata_rd_i :
                       registers[rf_raddr_rs2_i];

endmodule
