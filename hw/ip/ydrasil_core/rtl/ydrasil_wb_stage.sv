`include "define_mem_reg.svh"

// 写回单元 - 负责寄存器写回逻辑和延迟
module ydrasil_wb_stage (
    input wire clk,
    input wire rst_n,

    // 来自EXU的ALU数据
    input wire [`REGS_DATA_WIDTH-1:0]  alu_wdata_rd_i,
    input wire                         alu_rf_wen_rd_i,
    input wire [`REGS_ADDR_WIDTH-1:0]  alu_rf_waddr_rd_i,

    // 来自EXU的AGU/LSU数据
    input wire [`REGS_DATA_WIDTH-1:0]  lsu_wb_result_i,
    input wire                         lsu_rf_wen_rd_i,
    input wire [`REGS_ADDR_WIDTH-1:0]  lsu_rf_waddr_rd_i,

    output [`REGS_DATA_WIDTH-1:0]    wb_ex_pending_wdata_rd_ff_o,
    output [`REGS_ADDR_WIDTH-1:0]    wb_ex_pending_waddr_rd_ff_o,
    output                           wb_ex_pending_ff_o,  

    // 寄存器写回接口
    output wire [`REGS_DATA_WIDTH-1:0] rf_wdata_rd_o,
    output wire                        rf_wen_rd_o,
    output wire [`REGS_ADDR_WIDTH-1:0] rf_waddr_rd_o

    );

    // 延迟信号声明
    reg [`REGS_DATA_WIDTH-1:0]    alu_wdata_rd_ff;
    reg [`REGS_ADDR_WIDTH-1:0]    alu_rf_waddr_rd_ff;
    reg                           alu_pending_ff;  

    assign wb_ex_pending_wdata_rd_ff_o = alu_wdata_rd_ff;
    assign wb_ex_pending_waddr_rd_ff_o = alu_rf_waddr_rd_ff;
    assign wb_ex_pending_ff_o = alu_pending_ff;

    wire sel_lsu       ;
    wire sel_alu_i     ;
    wire sel_alu_ff    ;

    assign sel_lsu       = lsu_rf_wen_rd_i;
    assign sel_alu_i     = (~sel_lsu) & (~alu_pending_ff) & alu_rf_wen_rd_i;
    assign sel_alu_ff    = (~sel_lsu) & alu_pending_ff;



    // 统一打一拍寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_wdata_rd_ff     <= '0;
            alu_pending_ff    <= 1'b0;
            alu_rf_waddr_rd_ff  <= '0;
        end
        else begin
            alu_wdata_rd_ff     <= alu_wdata_rd_i;
            alu_pending_ff    <= (~sel_alu_i) & alu_rf_wen_rd_i;
            alu_rf_waddr_rd_ff  <= alu_rf_waddr_rd_i;
        end
    end


    wire [`REGS_DATA_WIDTH-1:0]    rf_wdata_rd;
    wire                           rf_wen_rd;
    wire [`REGS_ADDR_WIDTH-1:0]    rf_waddr_rd;




    assign rf_wen_rd    =   sel_lsu | sel_alu_i | sel_alu_ff;

    assign rf_waddr_rd =
        ({`REGS_ADDR_WIDTH{sel_lsu}}    & lsu_rf_waddr_rd_i) |
        ({`REGS_ADDR_WIDTH{sel_alu_i}}  & alu_rf_waddr_rd_i) |
        ({`REGS_ADDR_WIDTH{sel_alu_ff}} & alu_rf_waddr_rd_ff);

    assign rf_wdata_rd =
        ({`REGS_DATA_WIDTH{sel_lsu}}    & lsu_wb_result_i)  |
        ({`REGS_DATA_WIDTH{sel_alu_i}}  & alu_wdata_rd_i)   |
        ({`REGS_DATA_WIDTH{sel_alu_ff}} & alu_wdata_rd_ff);

    // 输出赋值
    assign rf_wdata_rd_o = rf_wdata_rd;
    assign rf_wen_rd_o = rf_wen_rd;
    assign rf_waddr_rd_o = rf_waddr_rd;

endmodule
