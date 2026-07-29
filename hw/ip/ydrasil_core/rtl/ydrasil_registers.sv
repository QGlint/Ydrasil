

module ydrasil_registers
import ydrasil_pkg::*;
 (

    input wire clk,
    input wire rst_n,

    // from ex
    input ydrasil_commit_pkt_t commit_pkt_i,
    input ydrasil_commit_pkt_t commit_pkt1_i,

    // from id
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_raddr_rs1_i,  // 读寄存器1地址

    // to id
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs1_o,  // 读寄存器1数据

    // from id
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_raddr_rs2_i,  // 读寄存器2地址

    // to id
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs2_o,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_raddr_rs3_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs3_o,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  rf_raddr_rs4_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] rf_rdata_rs4_o,

    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  dispatch_rf_raddr_rs1_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] dispatch_rf_rdata_rs1_o,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  dispatch_rf_raddr_rs2_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] dispatch_rf_rdata_rs2_o,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  dispatch_rf_raddr_rs3_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] dispatch_rf_rdata_rs3_o,
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  dispatch_rf_raddr_rs4_i,
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] dispatch_rf_rdata_rs4_o

);

    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0] registers[0:ydrasil_pkg::REGS_NUM - 1];

    genvar j;
    generate
        for (j = 0; j < ydrasil_pkg::REGS_NUM; j = j + 1) begin : gen_regs
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    registers[j] <= '0;
                end else begin
                    if (commit_pkt1_i.valid && commit_pkt1_i.writes_gpr &&
                        commit_pkt1_i.rd_addr == REGS_ADDR_WIDTH'(j)) begin
                        registers[j] <= commit_pkt1_i.value;
                    end else if (commit_pkt_i.valid && commit_pkt_i.writes_gpr &&
                        commit_pkt_i.rd_addr == REGS_ADDR_WIDTH'(j)) begin
                        registers[j] <= commit_pkt_i.value;
                    end
                end
            end
        end
    endgenerate


    assign rf_rdata_rs1_o = (rf_raddr_rs1_i == '0) ? '0 : registers[rf_raddr_rs1_i];
    assign rf_rdata_rs2_o = (rf_raddr_rs2_i == '0) ? '0 : registers[rf_raddr_rs2_i];
    assign rf_rdata_rs3_o = (rf_raddr_rs3_i == '0) ? '0 : registers[rf_raddr_rs3_i];
    assign rf_rdata_rs4_o = (rf_raddr_rs4_i == '0) ? '0 : registers[rf_raddr_rs4_i];
    assign dispatch_rf_rdata_rs1_o = (dispatch_rf_raddr_rs1_i == '0) ? '0 : registers[dispatch_rf_raddr_rs1_i];
    assign dispatch_rf_rdata_rs2_o = (dispatch_rf_raddr_rs2_i == '0) ? '0 : registers[dispatch_rf_raddr_rs2_i];
    assign dispatch_rf_rdata_rs3_o = (dispatch_rf_raddr_rs3_i == '0) ? '0 : registers[dispatch_rf_raddr_rs3_i];
    assign dispatch_rf_rdata_rs4_o = (dispatch_rf_raddr_rs4_i == '0) ? '0 : registers[dispatch_rf_raddr_rs4_i];

endmodule
