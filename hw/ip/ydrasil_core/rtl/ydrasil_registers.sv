

module ydrasil_registers
import ydrasil_pkg::*;
 (

    input wire clk,
    input wire rst_n,

    // from ex
    input wire                         rf_wen_rd_i,     // 写寄存器标志
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_waddr_rd_i,  // 写寄存器地址
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]  rf_wdata_rd_i,  // 写寄存器数据
    input wire                         rf_wen1_rd_i,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_waddr1_rd_i,
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]  rf_wdata1_rd_i,
    input wire                         rf_wen2_rd_i,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_waddr2_rd_i,
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]  rf_wdata2_rd_i,

    // from id
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_raddr_rs1_i,  // 读寄存器1地址

    // to id
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs1_o,  // 读寄存器1数据

    // from id
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_raddr_rs2_i,  // 读寄存器2地址

    // to id
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs2_o,  // 读寄存器2数据

    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  pipe1_rf_raddr_rs1_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_rf_rdata_rs1_o,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  pipe1_rf_raddr_rs2_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] pipe1_rf_rdata_rs2_o

);

    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] registers[0:ydrasil_pkg::REGS_NUM - 1];

    wire [ydrasil_pkg::REGS_NUM-1:0] registers_wen;  // 每个寄存器的写使能信号

    assign registers_wen[0] = 1'b0;  

    genvar i;
    generate
        for (i = 1; i < ydrasil_pkg::REGS_NUM; i = i + 1) begin : gen_regs_we
            assign registers_wen[i] =
                ((rf_wen_rd_i && (rf_waddr_rd_i == i)) ||
                 (rf_wen1_rd_i && (rf_waddr1_rd_i == i)) ||
                 (rf_wen2_rd_i && (rf_waddr2_rd_i == i))) && rst_n;
        end
    endgenerate

    genvar j;
    generate
        for (j = 0; j < ydrasil_pkg::REGS_NUM; j = j + 1) begin : gen_regs
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    registers[j] <= (j == 8) ? 32'h8000_0000 : '0;
                end else begin
                    if ((j != 0) && rf_wen2_rd_i && (rf_waddr2_rd_i == j)) begin
                        registers[j] <= rf_wdata2_rd_i;
                    end else if ((j != 0) && rf_wen1_rd_i && (rf_waddr1_rd_i == j)) begin
                        registers[j] <= rf_wdata1_rd_i;
                    end else if (registers_wen[j]) begin
                        registers[j] <= rf_wdata_rd_i;
                    end
                end
            end
        end
    endgenerate


    assign rf_rdata_rs1_o = (rf_raddr_rs1_i == '0) ? '0 : registers[rf_raddr_rs1_i];
    assign rf_rdata_rs2_o = (rf_raddr_rs2_i == '0) ? '0 : registers[rf_raddr_rs2_i];
    assign pipe1_rf_rdata_rs1_o =
        (pipe1_rf_raddr_rs1_i == '0) ? '0 : registers[pipe1_rf_raddr_rs1_i];
    assign pipe1_rf_rdata_rs2_o =
        (pipe1_rf_raddr_rs2_i == '0) ? '0 : registers[pipe1_rf_raddr_rs2_i];

endmodule
