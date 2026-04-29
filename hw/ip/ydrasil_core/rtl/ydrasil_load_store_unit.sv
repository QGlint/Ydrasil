`include "define_decode.svh"
`include "define_mem_reg.svh"

// 地址生成单元 - 处理内存访问和相关寄存器操作
module ydrasil_load_store_unit (
    input wire clk,  // 时钟输入
    input wire rst_n,

    input wire [`BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_i,
    input wire [ 4:0]                      id_rd_waddr_i,
    input wire [`OP_LSU_INFO_WIDTH-1:0]    operator_lsu_i,
    input wire [1:0]                       operator_lsu_type_i,
    input wire [`REGS_DATA_WIDTH-1:0]      id_lsu_rs2_data_i, // 存储操作的源寄存器数据
    input wire [`REGS_DATA_WIDTH-1:0]      ex_lsu_rd_data_i, // 存储操作的源寄存器数据
    input wire                             id_lsu_rs2_rd_forward_i,
    
    // 内存接口
    input wire [`BUS_DATA_WIDTH-1:0]       lsu_mem_rdata_i,
    output wire [`BUS_DATA_WIDTH-1:0]      lsu_mem_wdata_o,
    output wire [`BUS_ADDR_WIDTH-1:0]      lsu_mem_addr_o,
    output wire                            lsu_mem_wen_o,
    output wire                            lsu_mem_req_o,
    output wire [                3:0]      lsu_mem_wmask_o,  // 字节写入掩码，4位分别对应4个字节

	output wire                           	lsu_ctrl_stall_o,       // LSU 可能会因为等待内存响应而请求stall
    output wire                           	lsu_ctrl_stall_wb_o,    // LSU 可能会因为异常等原因
    output wire [`REGS_ADDR_WIDTH-1:0]    	lsu_ctrl_waddr_rd_o,
    output wire [`REGS_ADDR_WIDTH-1:0]    	lsu_ctrl_waddr_rd_wb_o,


    // 寄存器写回接口
    output wire [`REGS_DATA_WIDTH-1:0]     lsu_wb_result_o,
    output wire                            lsu_rf_rd_wen_o,
    output wire [`REGS_ADDR_WIDTH-1:0]     lsu_rf_rd_waddr_o
);
    // 内部信号定义
    wire [ 1:0] mem_addr_index;
    wire [31:0] mem_addr        ;
    wire [31:0] mem_rs2_data    ;

    wire is_load   ;
    wire is_store  ;
    wire  [`REGS_DATA_WIDTH-1:0] lsu_rs2_data ;


    
    reg [`OP_LOAD_INFO_WIDTH-1:0]  operator_load_ff;
    reg [4:0]  rd_addr_ff;
    reg        is_load_ff;
    reg [1:0]  mem_addr_index_ff;

    assign lsu_rs2_data = id_lsu_rs2_rd_forward_i ? ex_lsu_rd_data_i : id_lsu_rs2_data_i; // 前递后的源寄存器数据

    assign is_load   = operator_lsu_type_i [`OPERATOR_TYPE_LOAD - `OPERATOR_TYPE_LSU_BASE] ;
    assign is_store  = operator_lsu_type_i [`OPERATOR_TYPE_STORE - `OPERATOR_TYPE_LSU_BASE] ;

    
    assign mem_addr_index = mem_addr[1:0];
    assign mem_addr        = ex_lsu_mem_addr_i; // 内存访问的地址
    assign mem_rs2_data    = lsu_rs2_data; // 存储操作的源寄存器数据


    wire[`REGS_DATA_WIDTH-1:0] lsu_wb_result;
    wire                         lsu_rf_rd_wen;
    wire[`REGS_ADDR_WIDTH-1:0] lsu_rf_rd_waddr;
    reg [`REGS_DATA_WIDTH-1:0]  lsu_wb_result_ff;
    reg                         lsu_rf_rd_wen_ff;
    reg [`REGS_ADDR_WIDTH-1:0]  lsu_rf_rd_waddr_ff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsu_wb_result_ff <= 0;
            lsu_rf_rd_wen_ff <= 0;
            lsu_rf_rd_waddr_ff <= 0;
        end
        else begin
            lsu_wb_result_ff <= lsu_wb_result; // 直接使用组合逻辑输出的结果
            lsu_rf_rd_wen_ff <= lsu_rf_rd_wen; // 直接使用组合逻辑输出的结果
            lsu_rf_rd_waddr_ff <= lsu_rf_rd_waddr; // 直接使用组合逻辑输出的结果
        end
    end

    assign lsu_ctrl_stall_o = is_load; 
    assign lsu_ctrl_stall_wb_o = is_load_ff; // 假设与lsu_ctrl_stall_o相同
    assign lsu_ctrl_waddr_rd_o = id_rd_waddr_i;
    assign lsu_ctrl_waddr_rd_wb_o = rd_addr_ff;

    assign lsu_wb_result_o = lsu_wb_result_ff;
    assign lsu_rf_rd_wen_o = lsu_rf_rd_wen_ff;
    assign lsu_rf_rd_waddr_o = lsu_rf_rd_waddr_ff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_addr_ff              <= 0;
            operator_load_ff        <= 0;
            is_load_ff              <= 0;
            mem_addr_index_ff       <= 0;
        end
        else begin
            operator_load_ff        <= operator_lsu_i[`OP_LOAD_INFO_WIDTH-1:0];
            rd_addr_ff              <= id_rd_waddr_i;
            is_load_ff              <= is_load;
            mem_addr_index_ff       <= mem_addr_index;
        end
    end

    wire is_lb     ;
    wire is_lh     ;
    wire is_lw     ;
    wire is_lbu    ;
    wire is_lhu    ;

    assign is_lb  = operator_load_ff[`OP_LSU_LB];
    assign is_lh  = operator_load_ff[`OP_LSU_LH];
    assign is_lw  = operator_load_ff[`OP_LSU_LW];
    assign is_lbu = operator_load_ff[`OP_LSU_LBU];
    assign is_lhu = operator_load_ff[`OP_LSU_LHU];

    wire is_sb     ;
    wire is_sh     ;
    wire is_sw     ;

    assign is_sb = operator_lsu_i[`OP_LSU_SB];
    assign is_sh = operator_lsu_i[`OP_LSU_SH];
    assign is_sw = operator_lsu_i[`OP_LSU_SW];
    // 使用并行选择逻辑生成内存请求信号
    assign lsu_mem_req_o      = is_load | is_store;

    // 并行选择逻辑生成地址
    assign lsu_mem_addr_o    = mem_addr;
    // assign lsu_mem_waddr_o    = (valid_op & is_store_op) ? mem_addr ;

    // 并行选择逻辑生成写使能信号
    assign lsu_mem_wen_o       = is_store ;

    // 并行选择逻辑生成寄存器写回控制 - 使用打一拍后的信号
    assign lsu_rf_rd_wen      = is_load_ff;
    assign lsu_rf_rd_waddr    = is_load_ff? rd_addr_ff : '0;

    // 字节加载数据 - 使用并行选择逻辑
    wire [31:0] lb_data, lh_data, lw_data, lbu_data, lhu_data;
    wire [31:0] lb_byte0, lb_byte1, lb_byte2, lb_byte3;
    wire [31:0] lbu_byte0, lbu_byte1, lbu_byte2, lbu_byte3;
    wire [31:0] lh_low, lh_high, lhu_low, lhu_high;

    // 有符号字节加载 - 并行准备所有可能的字节值
    assign lb_byte0 = {{24{lsu_mem_rdata_i[7]}}, lsu_mem_rdata_i[7:0]};
    assign lb_byte1 = {{24{lsu_mem_rdata_i[15]}}, lsu_mem_rdata_i[15:8]};
    assign lb_byte2 = {{24{lsu_mem_rdata_i[23]}}, lsu_mem_rdata_i[23:16]};
    assign lb_byte3 = {{24{lsu_mem_rdata_i[31]}}, lsu_mem_rdata_i[31:24]};

    // 无符号字节加载 - 并行准备所有可能的字节值
    assign lbu_byte0 = {24'h0, lsu_mem_rdata_i[7:0]};
    assign lbu_byte1 = {24'h0, lsu_mem_rdata_i[15:8]};
    assign lbu_byte2 = {24'h0, lsu_mem_rdata_i[23:16]};
    assign lbu_byte3 = {24'h0, lsu_mem_rdata_i[31:24]};

    // 有符号半字加载 - 并行准备所有可能的半字值
    assign lh_low = {{16{lsu_mem_rdata_i[15]}}, lsu_mem_rdata_i[15:0]};
    assign lh_high = {{16{lsu_mem_rdata_i[31]}}, lsu_mem_rdata_i[31:16]};

    // 无符号半字加载 - 并行准备所有可能的半字值
    assign lhu_low = {16'h0, lsu_mem_rdata_i[15:0]};
    assign lhu_high = {16'h0, lsu_mem_rdata_i[31:16]};

    // 使用并行选择逻辑选择正确的字节/半字/字 - 使用打一拍后的地址索引
    assign lb_data = ({32{mem_addr_index_ff == 2'b00}} & lb_byte0) |
                     ({32{mem_addr_index_ff == 2'b01}} & lb_byte1) |
                     ({32{mem_addr_index_ff == 2'b10}} & lb_byte2) |
                     ({32{mem_addr_index_ff == 2'b11}} & lb_byte3);

    assign lbu_data = ({32{mem_addr_index_ff == 2'b00}} & lbu_byte0) |
                      ({32{mem_addr_index_ff == 2'b01}} & lbu_byte1) |
                      ({32{mem_addr_index_ff == 2'b10}} & lbu_byte2) |
                      ({32{mem_addr_index_ff == 2'b11}} & lbu_byte3);

    assign lh_data = ({32{mem_addr_index_ff[1] == 1'b0}} & lh_low) | ({32{mem_addr_index_ff[1] == 1'b1}} & lh_high);

    assign lhu_data = ({32{mem_addr_index_ff[1] == 1'b0}} & lhu_low) | ({32{mem_addr_index_ff[1] == 1'b1}} & lhu_high);

    assign lw_data = lsu_mem_rdata_i;

    // 并行选择最终的寄存器写回数据 - 使用打一拍后的信号
    assign lsu_wb_result =    ({32{is_lb}} & lb_data) |
                                ({32{is_lbu}} & lbu_data) |
                                ({32{is_lh}} & lh_data) |
                                ({32{is_lhu}} & lhu_data) |
                                ({32{is_lw}} & lw_data);

    // 存储操作的掩码和数据 - 使用并行选择逻辑
    // 字节存储掩码和数据
    wire [ 3:0] sb_mask;
    wire [31:0] sb_data;

    assign sb_mask = ({4{mem_addr_index == 2'b00}} & 4'b0001) |
                     ({4{mem_addr_index == 2'b01}} & 4'b0010) |
                     ({4{mem_addr_index == 2'b10}} & 4'b0100) |
                     ({4{mem_addr_index == 2'b11}} & 4'b1000);

    assign sb_data = ({32{mem_addr_index == 2'b00}} & {24'b0, mem_rs2_data[7:0]}) |
                     ({32{mem_addr_index == 2'b01}} & {16'b0, mem_rs2_data[7:0], 8'b0}) |
                     ({32{mem_addr_index == 2'b10}} & {8'b0, mem_rs2_data[7:0], 16'b0}) |
                     ({32{mem_addr_index == 2'b11}} & {mem_rs2_data[7:0], 24'b0});

    // 半字存储掩码和数据
    wire [ 3:0] sh_mask= ({4{mem_addr_index[1] == 1'b0}} & 4'b0011) | ({4{mem_addr_index[1] == 1'b1}} & 4'b1100);
    wire [31:0] sh_data;

    assign sh_data = ({32{mem_addr_index[1] == 1'b0}} & {16'b0, mem_rs2_data[15:0]}) |
                     ({32{mem_addr_index[1] == 1'b1}} & {mem_rs2_data[15:0], 16'b0});

    // 字存储掩码和数据
    wire [ 3:0] sw_mask = 4'b1111;
    wire [31:0] sw_data = mem_rs2_data;


    // 并行选择最终的存储掩码和数据
    assign lsu_mem_wmask_o = ({ 4{is_sb}} & sb_mask) |
                         ({ 4{is_sh}} & sh_mask) |
                         ({ 4{is_sw}} & sw_mask);

    assign lsu_mem_wdata_o = ({32{is_sb}} & sb_data) |
                         ({32{is_sh}} & sh_data) |
                         ({32{is_sw}} & sw_data);

endmodule
