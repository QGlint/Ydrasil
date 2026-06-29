
// 地址生成单元 - 处理内存访问和相关寄存器操作
module ydrasil_load_store_unit 
import ydrasil_pkg::*;
(
    input wire clk,  // 时钟输入
    input wire rst_n,

    input wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_i,
    input wire [ 4:0]                      id_rd_waddr_i,
    input wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]    operator_lsu_i,
    input wire [1:0]                       operator_lsu_type_i,
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      id_lsu_rs2_data_i, // 存储操作的源寄存器数据
    input wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]      id_lsu_rs2_raddr_i,
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      ex_lsu_rd_data_i, // 存储操作的源寄存器数据
    
    // 内存接口
    input wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]       lsu_mem_rdata_i,
    output wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]      lsu_mem_wdata_o,
    output wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]      lsu_mem_addr_o,
    output wire                            lsu_mem_wen_o,
    output wire                            lsu_mem_req_o,
    output wire [                3:0]      lsu_mem_wmask_o,  // 字节写入掩码，4位分别对应4个字节

    output wire                            lsu_ctrl_busy_o,


    // 寄存器写回接口
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]     lsu_wb_result_o,
    output wire                            lsu_rf_rd_wen_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     lsu_rf_rd_waddr_o
);
    if (LSU_MODE == LSU_MODE_NEW) begin : g_new
        localparam [1:0] S_IDLE         = 2'd0;
        localparam [1:0] S_LOAD_FIRST   = 2'd1;
        localparam [1:0] S_LOAD_SECOND  = 2'd2;
        localparam [1:0] S_STORE_SECOND = 2'd3;

        reg [1:0] state_q;
        reg [BUS_ADDR_WIDTH-1:0] addr_q;
        reg [REGS_DATA_WIDTH-1:0] store_data_q;
        reg [REGS_DATA_WIDTH-1:0] first_word_q;
        reg [OP_LSU_INFO_WIDTH-1:0] operator_lsu_q;
        reg [REGS_ADDR_WIDTH-1:0] rd_addr_q;
        reg [1:0] addr_index_q;
        reg load_cross_q;
        reg store_cross_q;
        reg [REGS_DATA_WIDTH-1:0] result_q;
        reg result_valid_q;

        wire [REGS_DATA_WIDTH-1:0] lsu_rs2_data;
        wire is_load;
        wire is_store;
        wire [1:0] mem_addr_index;
        wire [BUS_ADDR_WIDTH-1:0] mem_addr;
        wire [REGS_DATA_WIDTH-1:0] mem_rs2_data;
        wire request_valid;
        wire [2:0] request_access_size;
        wire [2:0] latched_access_size;
        wire request_crosses_word;
        wire latched_crosses_word;

        assign lsu_rs2_data = id_lsu_rs2_data_i;
        assign is_load = operator_lsu_type_i[OPERATOR_TYPE_LOAD - OPERATOR_TYPE_LSU_BASE];
        assign is_store = operator_lsu_type_i[OPERATOR_TYPE_STORE - OPERATOR_TYPE_LSU_BASE];
        assign mem_addr = ex_lsu_mem_addr_i;
        assign mem_addr_index = mem_addr[1:0];
        assign mem_rs2_data = lsu_rs2_data;
        assign request_valid = is_load | is_store;

        wire first_access_req = (state_q == S_IDLE) & request_valid;
        wire second_load_req = (state_q == S_LOAD_FIRST) & load_cross_q;
        wire second_store_req = (state_q == S_STORE_SECOND);
        wire second_access = second_load_req | second_store_req;
        wire [BUS_ADDR_WIDTH-1:0] latched_next_addr = {addr_q[BUS_ADDR_WIDTH-1:2] + 1'b1, 2'b00};
        wire [OP_LSU_INFO_WIDTH-1:0] active_store_op =
            second_store_req ? operator_lsu_q : operator_lsu_i;
        wire [1:0] active_store_index = second_store_req ? addr_index_q : mem_addr_index;
        wire [31:0] active_store_data = second_store_req ? store_data_q : mem_rs2_data;
        wire [2:0] active_store_size = second_store_req ? latched_access_size : request_access_size;
        wire [2:0] active_store_low_room = 3'd4 - {1'b0, active_store_index};
        wire [2:0] active_store_low_bytes =
            (active_store_size < active_store_low_room) ? active_store_size : active_store_low_room;
        wire [2:0] active_store_high_bytes = active_store_size - active_store_low_bytes;
        wire [63:0] single_load_data = {32'b0, lsu_mem_rdata_i};
        wire [63:0] cross_load_data = {lsu_mem_rdata_i, first_word_q};
        wire [63:0] single_load_shifted = single_load_data >> ({3'b000, addr_index_q} << 3);
        wire [63:0] cross_load_shifted = cross_load_data >> ({3'b000, addr_index_q} << 3);
        reg [3:0] store_mask_word;
        reg [31:0] store_data_word;
        reg [31:0] single_load_result;
        reg [31:0] cross_load_result;
        integer store_lane;
        integer store_src_byte;

        assign request_access_size =
            (operator_lsu_i[OP_LSU_LW] | operator_lsu_i[OP_LSU_SW]) ? 3'd4 :
            (operator_lsu_i[OP_LSU_LH] | operator_lsu_i[OP_LSU_LHU] | operator_lsu_i[OP_LSU_SH]) ? 3'd2 :
                                                                                                    3'd1;
        assign latched_access_size =
            (operator_lsu_q[OP_LSU_LW] | operator_lsu_q[OP_LSU_SW]) ? 3'd4 :
            (operator_lsu_q[OP_LSU_LH] | operator_lsu_q[OP_LSU_LHU] | operator_lsu_q[OP_LSU_SH]) ? 3'd2 :
                                                                                                    3'd1;
        assign request_crosses_word =
            ({1'b0, mem_addr_index} + request_access_size) > 3'd4;
        assign latched_crosses_word =
            ({1'b0, addr_index_q} + latched_access_size) > 3'd4;

        always_comb begin
            store_mask_word = 4'b0000;
            store_data_word = 32'b0;
            for (store_lane = 0; store_lane < 4; store_lane = store_lane + 1) begin
                if (second_store_req) begin
                    store_src_byte = active_store_low_bytes + store_lane;
                    if ({1'b0, store_lane[1:0]} < active_store_high_bytes) begin
                        store_mask_word[store_lane] = 1'b1;
                        store_data_word[(store_lane * 8) +: 8] =
                            active_store_data[(store_src_byte * 8) +: 8];
                    end
                end else begin
                    store_src_byte = store_lane - active_store_index;
                    if ((store_lane >= active_store_index) &&
                        ({1'b0, store_src_byte[1:0]} < active_store_low_bytes)) begin
                        store_mask_word[store_lane] = 1'b1;
                        store_data_word[(store_lane * 8) +: 8] =
                            active_store_data[(store_src_byte * 8) +: 8];
                    end
                end
            end
        end

        always_comb begin
            if (operator_lsu_q[OP_LSU_LB]) begin
                single_load_result = {{24{single_load_shifted[7]}}, single_load_shifted[7:0]};
                cross_load_result = {{24{cross_load_shifted[7]}}, cross_load_shifted[7:0]};
            end else if (operator_lsu_q[OP_LSU_LBU]) begin
                single_load_result = {24'b0, single_load_shifted[7:0]};
                cross_load_result = {24'b0, cross_load_shifted[7:0]};
            end else if (operator_lsu_q[OP_LSU_LH]) begin
                single_load_result = {{16{single_load_shifted[15]}}, single_load_shifted[15:0]};
                cross_load_result = {{16{cross_load_shifted[15]}}, cross_load_shifted[15:0]};
            end else if (operator_lsu_q[OP_LSU_LHU]) begin
                single_load_result = {16'b0, single_load_shifted[15:0]};
                cross_load_result = {16'b0, cross_load_shifted[15:0]};
            end else begin
                single_load_result = single_load_shifted[31:0];
                cross_load_result = cross_load_shifted[31:0];
            end
        end

        assign lsu_mem_req_o = first_access_req | second_access;
        assign lsu_mem_wen_o = ((state_q == S_IDLE) & is_store) | second_store_req;
        assign lsu_mem_addr_o = second_access ? latched_next_addr : mem_addr;
        assign lsu_mem_wmask_o = lsu_mem_wen_o ? store_mask_word : 4'b0000;
        assign lsu_mem_wdata_o = lsu_mem_wen_o ? store_data_word : 32'b0;

        assign lsu_ctrl_busy_o = (state_q != S_IDLE) | request_valid | result_valid_q;

        assign lsu_wb_result_o = result_q;
        assign lsu_rf_rd_wen_o = result_valid_q;
        assign lsu_rf_rd_waddr_o = result_valid_q ? rd_addr_q : '0;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state_q         <= S_IDLE;
                addr_q          <= '0;
                store_data_q    <= '0;
                first_word_q    <= '0;
                operator_lsu_q  <= '0;
                rd_addr_q       <= '0;
                addr_index_q    <= '0;
                load_cross_q    <= 1'b0;
                store_cross_q   <= 1'b0;
                result_q        <= '0;
                result_valid_q  <= 1'b0;
            end else begin
                result_valid_q <= 1'b0;

                case (state_q)
                    S_IDLE: begin
                        if (request_valid) begin
                            addr_q         <= mem_addr;
                            store_data_q   <= mem_rs2_data;
                            operator_lsu_q <= operator_lsu_i;
                            rd_addr_q      <= id_rd_waddr_i;
                            addr_index_q   <= mem_addr_index;
                            load_cross_q   <= request_crosses_word & is_load;
                            store_cross_q  <= request_crosses_word & is_store;

                            if (is_load) begin
                                state_q <= S_LOAD_FIRST;
                            end else if (request_crosses_word) begin
                                state_q <= S_STORE_SECOND;
                            end
                        end
                    end

                    S_LOAD_FIRST: begin
                        if (load_cross_q) begin
                            first_word_q <= lsu_mem_rdata_i;
                            state_q      <= S_LOAD_SECOND;
                        end else begin
                            result_q       <= single_load_result;
                            result_valid_q <= 1'b1;
                            state_q        <= S_IDLE;
                        end
                    end

                    S_LOAD_SECOND: begin
                        result_q       <= cross_load_result;
                        result_valid_q <= 1'b1;
                        state_q        <= S_IDLE;
                    end

                    S_STORE_SECOND: begin
                        state_q <= S_IDLE;
                    end

                    default: begin
                        state_q <= S_IDLE;
                    end
                endcase
            end
        end
    end else begin : g_legacy
    // 内部信号定义
    wire [ 1:0] mem_addr_index;
    wire [31:0] mem_addr        ;
    wire [31:0] mem_rs2_data    ;

    wire is_load   ;
    wire is_store  ;
    wire  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] lsu_rs2_data ;


    
    reg [ydrasil_pkg::OP_LOAD_INFO_WIDTH-1:0]  operator_load_ff;
    reg [4:0]  rd_addr_ff;
    reg        is_load_ff;
    reg [1:0]  mem_addr_index_ff;

    assign lsu_rs2_data = id_lsu_rs2_data_i;

    assign is_load   = operator_lsu_type_i[ydrasil_pkg::OPERATOR_TYPE_LOAD - ydrasil_pkg::OPERATOR_TYPE_LSU_BASE];
    assign is_store  = operator_lsu_type_i[ydrasil_pkg::OPERATOR_TYPE_STORE - ydrasil_pkg::OPERATOR_TYPE_LSU_BASE];

    
    assign mem_addr_index = mem_addr[1:0];
    assign mem_addr        = ex_lsu_mem_addr_i; // 内存访问的地址
    assign mem_rs2_data    = lsu_rs2_data; // 存储操作的源寄存器数据


    wire[ydrasil_pkg::REGS_DATA_WIDTH-1:0] lsu_wb_result;
    wire                         lsu_rf_rd_wen;
    wire[ydrasil_pkg::REGS_ADDR_WIDTH-1:0] lsu_rf_rd_waddr;
    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0]  lsu_wb_result_ff;
    reg                         lsu_rf_rd_wen_ff;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]  lsu_rf_rd_waddr_ff;

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

    assign lsu_ctrl_busy_o = 1'b0;

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
            operator_load_ff        <= operator_lsu_i[ydrasil_pkg::OP_LOAD_INFO_WIDTH-1:0];
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

    assign is_lb  = operator_load_ff[ydrasil_pkg::OP_LSU_LB];
    assign is_lh  = operator_load_ff[ydrasil_pkg::OP_LSU_LH];
    assign is_lw  = operator_load_ff[ydrasil_pkg::OP_LSU_LW];
    assign is_lbu = operator_load_ff[ydrasil_pkg::OP_LSU_LBU];
    assign is_lhu = operator_load_ff[ydrasil_pkg::OP_LSU_LHU];

    wire is_sb     ;
    wire is_sh     ;
    wire is_sw     ;

    assign is_sb = operator_lsu_i[ydrasil_pkg::OP_LSU_SB];
    assign is_sh = operator_lsu_i[ydrasil_pkg::OP_LSU_SH];
    assign is_sw = operator_lsu_i[ydrasil_pkg::OP_LSU_SW];
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

    end

endmodule
