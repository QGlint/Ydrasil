
// 地址生成单元 - 处理内存访问和相关寄存器操作
module ydrasil_load_store_unit 
import ydrasil_pkg::*;
(
    input wire clk,  // 时钟输入
    input wire rst_n,

    input wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_i,
    input wire [ 4:0]                      id_rd_waddr_i,
    input wire                             id_producer_id_i,
    input wire                             id_producer_tracked_i,
    input wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]    operator_lsu_i,
    input wire [1:0]                       operator_lsu_type_i,
    input ydrasil_id_lsu_pkt_t             id_lsu_i,
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]      ex_lsu_rd_data_i, // 存储操作的源寄存器数据
    input ydrasil_gpr_fwd_pkt_t            alu_fwd_i,
    input ydrasil_gpr_fwd_pkt_t            mul_fwd_i,
    input ydrasil_gpr_fwd_pkt_t            wb_fwd_i,
    
    // DTCM fast path
    input wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]       dtcm_rdata_i,
    output wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]      dtcm_wdata_o,
    output wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]      dtcm_addr_o,
    output wire                            dtcm_wen_o,
    output wire                            dtcm_req_o,
    output wire [                3:0]      dtcm_wmask_o,

    // MMIO slow path
    input wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]       mmio_rdata_i,
    output wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]      mmio_wdata_o,
    output wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]      mmio_addr_o,
    output wire                            mmio_wen_o,
    output wire                            mmio_req_o,
    output wire [                3:0]      mmio_wmask_o,

    output wire                            lsu_ctrl_busy_o,


    // 寄存器写回接口
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]     lsu_wb_result_o,
    output wire                            lsu_rf_rd_wen_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     lsu_rf_rd_waddr_o
    ,output wire                            lsu_producer_id_o
    ,output wire                            lsu_producer_tracked_o
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
        reg producer_id_q;
        reg producer_tracked_q;
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

        assign lsu_rs2_data = id_lsu_i.rs2_data;
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
        wire [63:0] single_load_data = {32'b0, dtcm_rdata_i};
        wire [63:0] cross_load_data = {dtcm_rdata_i, first_word_q};
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

        assign dtcm_req_o = first_access_req | second_access;
        assign dtcm_wen_o = ((state_q == S_IDLE) & is_store) | second_store_req;
        assign dtcm_addr_o = second_access ? latched_next_addr : mem_addr;
        assign dtcm_wmask_o = dtcm_wen_o ? store_mask_word : 4'b0000;
        assign dtcm_wdata_o = dtcm_wen_o ? store_data_word : 32'b0;

        assign mmio_req_o = 1'b0;
        assign mmio_wen_o = 1'b0;
        assign mmio_addr_o = '0;
        assign mmio_wmask_o = 4'b0000;
        assign mmio_wdata_o = '0;

        assign lsu_ctrl_busy_o = (state_q != S_IDLE) | request_valid | result_valid_q;

        assign lsu_wb_result_o = result_q;
        assign lsu_rf_rd_wen_o = result_valid_q;
        assign lsu_rf_rd_waddr_o = result_valid_q ? rd_addr_q : '0;
        assign lsu_producer_id_o = producer_id_q;
        assign lsu_producer_tracked_o = producer_tracked_q;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state_q         <= S_IDLE;
                addr_q          <= '0;
                store_data_q    <= '0;
                first_word_q    <= '0;
                operator_lsu_q  <= '0;
                rd_addr_q       <= '0;
                producer_id_q   <= 1'b0;
                producer_tracked_q <= 1'b0;
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
                            producer_id_q  <= id_producer_id_i;
                            producer_tracked_q <= id_producer_tracked_i;
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
                            first_word_q <= dtcm_rdata_i;
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
    wire is_load;
    wire is_store;
    wire request_valid;
    wire [1:0] mem_addr_index;

    wire request_is_dtcm;
    wire dtcm_accept;
    wire dtcm_load_req;
    wire dtcm_store_req;
    wire mmio_accept;
    wire mmio_busy;

    reg        mmio_req_valid_q;
    reg        mmio_wait_q;
    reg        mmio_is_load_q;
    reg        mmio_is_store_q;
    reg [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]      mmio_addr_q;
    reg [ydrasil_pkg::BUS_DATA_WIDTH-1:0]      mmio_wdata_q;
    reg [3:0]                                  mmio_wmask_q;
    reg [1:0]                                  mmio_addr_index_q;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   mmio_operator_lsu_q;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     mmio_rd_addr_q;
    reg                                         mmio_producer_id_q;
    reg                                         mmio_producer_tracked_q;
    reg        mmio_wb_valid_q;
    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0]     mmio_wb_result_q;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     mmio_wb_rd_addr_q;
    reg                                         mmio_wb_producer_id_q;
    reg                                         mmio_wb_producer_tracked_q;

    (* max_fanout = 8 *) reg pending_store_valid_q;
    reg        pending_store_is_dtcm_q;
    reg [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]      pending_store_addr_q;
    reg [3:0]                                  pending_store_mask_q;
    reg [1:0]                                  pending_store_addr_index_q;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   pending_store_operator_lsu_q;
    (* max_fanout = 8 *) reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] pending_store_rs2_raddr_q;

    reg        load_s1_valid_q;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     load_s1_rd_addr_q;
    reg                                         load_s1_producer_id_q;
    reg                                         load_s1_producer_tracked_q;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   load_s1_operator_lsu_q;
    reg [1:0]                                  load_s1_addr_index_q;
    reg [ydrasil_pkg::BUS_ADDR_WIDTH-1:2]      load_s1_word_addr_q;

    reg        load_s2_valid_q;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     load_s2_rd_addr_q;
    reg                                         load_s2_producer_id_q;
    reg                                         load_s2_producer_tracked_q;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   load_s2_operator_lsu_q;
    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0]     load_s2_shifted_q;

    wire [3:0] store_wmask;
    wire [31:0] store_wdata;
    wire pending_store_data_valid;
    wire [31:0] pending_store_raw_data;
    wire [31:0] pending_store_wdata;
    wire pending_store_dtcm_fire;
    wire pending_store_mmio_fire;
    wire store_pending_capture;
    wire mmio_fire;
    reg [31:0] dtcm_load_result;
    reg [31:0] mmio_load_result;
    reg [31:0] load_shifted_data;

    localparam int HOT_ENTRIES = 8;
    localparam int HOT_INDEX_WIDTH = $clog2(HOT_ENTRIES);
    reg [HOT_ENTRIES-1:0] hot_valid_q;
    reg [ydrasil_pkg::BUS_ADDR_WIDTH-1:2] hot_addr_q [0:HOT_ENTRIES-1];
    reg [31:0] hot_data_q [0:HOT_ENTRIES-1];
    reg hot_lookup_hit;
    reg [HOT_INDEX_WIDTH-1:0] hot_lookup_idx;
    reg [31:0] hot_lookup_data;
    wire hot_load_req;
    wire dtcm_array_load_req;
    wire [31:0] hot_load_shifted = hot_lookup_data >> ({3'b000, mem_addr_index} << 3);
    integer hot_idx;

`ifndef SYNTHESIS
    reg [31:0] perf_hot_lookup_q;
    reg [31:0] perf_hot_hit_q;
    reg [31:0] perf_hot_fill_q;
    reg [31:0] perf_hot_store_update_q;
`endif

    wire dtcm_wb_valid;
    wire mmio_wb_out_valid;
    wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] selected_wb_result;
    wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0] selected_wb_rd_addr;

    function automatic [31:0] align_store_data;
        input [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] op_lsu;
        input [1:0] addr_index;
        input [31:0] raw_data;
        begin
            if (op_lsu[ydrasil_pkg::OP_LSU_SB]) begin
                unique case (addr_index)
                    2'b00: align_store_data = {24'b0, raw_data[7:0]};
                    2'b01: align_store_data = {16'b0, raw_data[7:0], 8'b0};
                    2'b10: align_store_data = {8'b0, raw_data[7:0], 16'b0};
                    default: align_store_data = {raw_data[7:0], 24'b0};
                endcase
            end else if (op_lsu[ydrasil_pkg::OP_LSU_SH]) begin
                align_store_data = addr_index[1] ? {raw_data[15:0], 16'b0} :
                                                   {16'b0, raw_data[15:0]};
            end else begin
                align_store_data = raw_data;
            end
        end
    endfunction

    assign is_load = operator_lsu_type_i[ydrasil_pkg::OPERATOR_TYPE_LOAD - ydrasil_pkg::OPERATOR_TYPE_LSU_BASE];
    assign is_store = operator_lsu_type_i[ydrasil_pkg::OPERATOR_TYPE_STORE - ydrasil_pkg::OPERATOR_TYPE_LSU_BASE];
    assign request_valid = is_load | is_store;
    assign mem_addr_index = id_lsu_i.addr[1:0];
    assign request_is_dtcm = id_lsu_i.addr_is_dtcm;
    assign mmio_busy = mmio_req_valid_q | mmio_wait_q | mmio_wb_valid_q;
    assign dtcm_accept = request_valid & request_is_dtcm & !mmio_wb_valid_q & !pending_store_valid_q;
    always_comb begin
        hot_lookup_idx = id_lsu_i.addr[HOT_INDEX_WIDTH+1:2];
        hot_lookup_hit = hot_valid_q[hot_lookup_idx] &&
            (hot_addr_q[hot_lookup_idx] == id_lsu_i.addr[BUS_ADDR_WIDTH-1:2]);
        hot_lookup_data = hot_data_q[hot_lookup_idx];
    end

    localparam bit HOT_BYPASS_ENABLE = 1'b1;
    assign hot_load_req =
        dtcm_accept & is_load & hot_lookup_hit & HOT_BYPASS_ENABLE & !load_s1_valid_q;
    assign dtcm_array_load_req =
        dtcm_accept & is_load & !(hot_lookup_hit & HOT_BYPASS_ENABLE & !load_s1_valid_q);
    assign dtcm_load_req = hot_load_req | dtcm_array_load_req;

    assign mmio_accept = request_valid & !request_is_dtcm & !mmio_busy & !pending_store_valid_q;
    assign mmio_fire = mmio_accept & (is_load | id_lsu_i.store_data_valid);

    assign store_wmask = id_lsu_i.store_mask;
    assign store_wdata = id_lsu_i.store_data;
    assign store_pending_capture =
        (dtcm_accept | mmio_accept) & is_store & !id_lsu_i.store_data_valid;

    assign pending_store_data_valid =
        (pending_store_rs2_raddr_q == '0) |
        (dtcm_wb_valid & (selected_wb_rd_addr == pending_store_rs2_raddr_q)) |
        (mmio_wb_out_valid & (selected_wb_rd_addr == pending_store_rs2_raddr_q)) |
        (alu_fwd_i.valid & (alu_fwd_i.addr == pending_store_rs2_raddr_q)) |
        (mul_fwd_i.valid & (mul_fwd_i.addr == pending_store_rs2_raddr_q)) |
        (wb_fwd_i.valid & (wb_fwd_i.addr == pending_store_rs2_raddr_q));
    assign pending_store_raw_data =
        (pending_store_rs2_raddr_q == '0) ? 32'b0 :
        (dtcm_wb_valid & (selected_wb_rd_addr == pending_store_rs2_raddr_q)) ? selected_wb_result :
        (mmio_wb_out_valid & (selected_wb_rd_addr == pending_store_rs2_raddr_q)) ? selected_wb_result :
        (alu_fwd_i.valid & (alu_fwd_i.addr == pending_store_rs2_raddr_q)) ? alu_fwd_i.data :
        (mul_fwd_i.valid & (mul_fwd_i.addr == pending_store_rs2_raddr_q)) ? mul_fwd_i.data :
        (wb_fwd_i.valid & (wb_fwd_i.addr == pending_store_rs2_raddr_q)) ? wb_fwd_i.data :
        32'b0;
    assign pending_store_wdata =
        align_store_data(pending_store_operator_lsu_q,
                         pending_store_addr_index_q,
                         pending_store_raw_data);
    assign pending_store_dtcm_fire =
        pending_store_valid_q & pending_store_is_dtcm_q & pending_store_data_valid &
        !mmio_wb_valid_q;
    assign pending_store_mmio_fire =
        pending_store_valid_q & !pending_store_is_dtcm_q & pending_store_data_valid &
        !mmio_busy;
    assign dtcm_store_req =
        (dtcm_accept & is_store & id_lsu_i.store_data_valid) |
        pending_store_dtcm_fire;

    always_comb begin
        unique case (load_s1_addr_index_q)
            2'b00: load_shifted_data = dtcm_rdata_i;
            2'b01: load_shifted_data = {8'b0, dtcm_rdata_i[31:8]};
            2'b10: load_shifted_data = {16'b0, dtcm_rdata_i[31:16]};
            default: load_shifted_data = {24'b0, dtcm_rdata_i[31:24]};
        endcase
    end

    always_comb begin
        dtcm_load_result = load_s2_shifted_q;
        unique case (1'b1)
            load_s2_operator_lsu_q[ydrasil_pkg::OP_LSU_LB]: begin
                dtcm_load_result = {{24{load_s2_shifted_q[7]}}, load_s2_shifted_q[7:0]};
            end
            load_s2_operator_lsu_q[ydrasil_pkg::OP_LSU_LBU]: begin
                dtcm_load_result = {24'b0, load_s2_shifted_q[7:0]};
            end
            load_s2_operator_lsu_q[ydrasil_pkg::OP_LSU_LH]: begin
                dtcm_load_result = {{16{load_s2_shifted_q[15]}}, load_s2_shifted_q[15:0]};
            end
            load_s2_operator_lsu_q[ydrasil_pkg::OP_LSU_LHU]: begin
                dtcm_load_result = {16'b0, load_s2_shifted_q[15:0]};
            end
            default: begin
                dtcm_load_result = load_s2_shifted_q;
            end
        endcase
    end

    always_comb begin
        mmio_load_result = mmio_rdata_i;
        unique case (1'b1)
            mmio_operator_lsu_q[ydrasil_pkg::OP_LSU_LB]: begin
                unique case (mmio_addr_index_q)
                    2'b00: mmio_load_result = {{24{mmio_rdata_i[7]}}, mmio_rdata_i[7:0]};
                    2'b01: mmio_load_result = {{24{mmio_rdata_i[15]}}, mmio_rdata_i[15:8]};
                    2'b10: mmio_load_result = {{24{mmio_rdata_i[23]}}, mmio_rdata_i[23:16]};
                    default: mmio_load_result = {{24{mmio_rdata_i[31]}}, mmio_rdata_i[31:24]};
                endcase
            end
            mmio_operator_lsu_q[ydrasil_pkg::OP_LSU_LBU]: begin
                unique case (mmio_addr_index_q)
                    2'b00: mmio_load_result = {24'b0, mmio_rdata_i[7:0]};
                    2'b01: mmio_load_result = {24'b0, mmio_rdata_i[15:8]};
                    2'b10: mmio_load_result = {24'b0, mmio_rdata_i[23:16]};
                    default: mmio_load_result = {24'b0, mmio_rdata_i[31:24]};
                endcase
            end
            mmio_operator_lsu_q[ydrasil_pkg::OP_LSU_LH]: begin
                mmio_load_result = mmio_addr_index_q[1] ?
                    {{16{mmio_rdata_i[31]}}, mmio_rdata_i[31:16]} :
                    {{16{mmio_rdata_i[15]}}, mmio_rdata_i[15:0]};
            end
            mmio_operator_lsu_q[ydrasil_pkg::OP_LSU_LHU]: begin
                mmio_load_result = mmio_addr_index_q[1] ?
                    {16'b0, mmio_rdata_i[31:16]} :
                    {16'b0, mmio_rdata_i[15:0]};
            end
            default: begin
                mmio_load_result = mmio_rdata_i;
            end
        endcase
    end

    assign dtcm_req_o = dtcm_array_load_req | dtcm_store_req;
    assign dtcm_wen_o = dtcm_store_req;
    assign dtcm_addr_o = pending_store_dtcm_fire ? pending_store_addr_q : id_lsu_i.addr;
    assign dtcm_wmask_o =
        pending_store_dtcm_fire ? pending_store_mask_q :
        (dtcm_store_req ? store_wmask : 4'b0000);
    assign dtcm_wdata_o =
        pending_store_dtcm_fire ? pending_store_wdata :
        (dtcm_store_req ? store_wdata : 32'b0);

    assign mmio_req_o = mmio_req_valid_q;
    assign mmio_wen_o = mmio_req_valid_q & mmio_is_store_q;
    assign mmio_addr_o = mmio_addr_q;
    assign mmio_wmask_o = (mmio_req_valid_q & mmio_is_store_q) ? mmio_wmask_q : 4'b0000;
    assign mmio_wdata_o = (mmio_req_valid_q & mmio_is_store_q) ? mmio_wdata_q : 32'b0;

    assign dtcm_wb_valid = load_s2_valid_q;
    assign mmio_wb_out_valid = mmio_wb_valid_q & !dtcm_wb_valid;
    assign selected_wb_result = dtcm_wb_valid ? dtcm_load_result : mmio_wb_result_q;
    assign selected_wb_rd_addr = dtcm_wb_valid ? load_s2_rd_addr_q : mmio_wb_rd_addr_q;

    assign lsu_ctrl_busy_o =
        mmio_busy | mmio_accept | pending_store_valid_q | store_pending_capture;
    assign lsu_wb_result_o = selected_wb_result;
    assign lsu_rf_rd_wen_o = dtcm_wb_valid | mmio_wb_out_valid;
    assign lsu_rf_rd_waddr_o = (dtcm_wb_valid | mmio_wb_out_valid) ? selected_wb_rd_addr : '0;
    assign lsu_producer_id_o = dtcm_wb_valid ? load_s2_producer_id_q : mmio_wb_producer_id_q;
    assign lsu_producer_tracked_o = dtcm_wb_valid ? load_s2_producer_tracked_q :
        mmio_wb_producer_tracked_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_req_valid_q       <= 1'b0;
            mmio_wait_q            <= 1'b0;
            mmio_is_load_q         <= 1'b0;
            mmio_is_store_q        <= 1'b0;
            mmio_addr_q            <= '0;
            mmio_wdata_q           <= '0;
            mmio_wmask_q           <= '0;
            mmio_addr_index_q      <= '0;
            mmio_operator_lsu_q    <= '0;
            mmio_rd_addr_q         <= '0;
            mmio_producer_id_q     <= 1'b0;
            mmio_producer_tracked_q <= 1'b0;
            mmio_wb_valid_q        <= 1'b0;
            mmio_wb_result_q       <= '0;
            mmio_wb_rd_addr_q      <= '0;
            mmio_wb_producer_id_q  <= 1'b0;
            mmio_wb_producer_tracked_q <= 1'b0;
            pending_store_valid_q  <= 1'b0;
            pending_store_is_dtcm_q <= 1'b0;
            pending_store_addr_q   <= '0;
            pending_store_mask_q   <= '0;
            pending_store_addr_index_q <= '0;
            pending_store_operator_lsu_q <= '0;
            pending_store_rs2_raddr_q <= '0;
            load_s1_valid_q        <= 1'b0;
            load_s1_rd_addr_q      <= '0;
            load_s1_producer_id_q  <= 1'b0;
            load_s1_producer_tracked_q <= 1'b0;
            load_s1_operator_lsu_q <= '0;
            load_s1_addr_index_q   <= '0;
            load_s1_word_addr_q    <= '0;
            load_s2_valid_q        <= 1'b0;
            load_s2_rd_addr_q      <= '0;
            load_s2_producer_id_q  <= 1'b0;
            load_s2_producer_tracked_q <= 1'b0;
            load_s2_operator_lsu_q <= '0;
            load_s2_shifted_q      <= '0;
            hot_valid_q            <= '0;
            for (hot_idx = 0; hot_idx < HOT_ENTRIES; hot_idx = hot_idx + 1) begin
                hot_addr_q[hot_idx] <= '0;
                hot_data_q[hot_idx] <= '0;
            end
`ifndef SYNTHESIS
            perf_hot_lookup_q       <= '0;
            perf_hot_hit_q          <= '0;
            perf_hot_fill_q         <= '0;
            perf_hot_store_update_q <= '0;
`endif
        end else begin
            load_s1_valid_q <= dtcm_array_load_req;
            if (dtcm_array_load_req) begin
                load_s1_rd_addr_q      <= id_rd_waddr_i;
                load_s1_producer_id_q  <= id_producer_id_i;
                load_s1_producer_tracked_q <= id_producer_tracked_i;
                load_s1_operator_lsu_q <= operator_lsu_i;
                load_s1_addr_index_q   <= mem_addr_index;
                load_s1_word_addr_q    <= id_lsu_i.addr[BUS_ADDR_WIDTH-1:2];
            end

            load_s2_valid_q <= load_s1_valid_q | hot_load_req;
            if (hot_load_req) begin
                load_s2_rd_addr_q      <= id_rd_waddr_i;
                load_s2_producer_id_q  <= id_producer_id_i;
                load_s2_producer_tracked_q <= id_producer_tracked_i;
                load_s2_operator_lsu_q <= operator_lsu_i;
                load_s2_shifted_q      <= hot_load_shifted;
            end else if (load_s1_valid_q) begin
                load_s2_rd_addr_q      <= load_s1_rd_addr_q;
                load_s2_producer_id_q  <= load_s1_producer_id_q;
                load_s2_producer_tracked_q <= load_s1_producer_tracked_q;
                load_s2_operator_lsu_q <= load_s1_operator_lsu_q;
                load_s2_shifted_q      <= load_shifted_data;
            end

            if (load_s1_valid_q &&
                !(dtcm_store_req &&
                  (dtcm_addr_o[BUS_ADDR_WIDTH-1:2] == load_s1_word_addr_q))) begin
                hot_valid_q[load_s1_word_addr_q[HOT_INDEX_WIDTH+1:2]] <= 1'b1;
                hot_addr_q[load_s1_word_addr_q[HOT_INDEX_WIDTH+1:2]] <= load_s1_word_addr_q;
                hot_data_q[load_s1_word_addr_q[HOT_INDEX_WIDTH+1:2]] <= dtcm_rdata_i;
            end

            if (dtcm_store_req) begin
                if (hot_valid_q[dtcm_addr_o[HOT_INDEX_WIDTH+1:2]] &&
                    (hot_addr_q[dtcm_addr_o[HOT_INDEX_WIDTH+1:2]] == dtcm_addr_o[BUS_ADDR_WIDTH-1:2])) begin
                    hot_valid_q[dtcm_addr_o[HOT_INDEX_WIDTH+1:2]] <= 1'b0;
                end
            end
`ifndef SYNTHESIS
            if (dtcm_accept & is_load) perf_hot_lookup_q <= perf_hot_lookup_q + 1'b1;
            if (hot_load_req) perf_hot_hit_q <= perf_hot_hit_q + 1'b1;
            if (load_s1_valid_q) perf_hot_fill_q <= perf_hot_fill_q + 1'b1;
            if (dtcm_store_req && hot_valid_q[dtcm_addr_o[HOT_INDEX_WIDTH+1:2]] &&
                (hot_addr_q[dtcm_addr_o[HOT_INDEX_WIDTH+1:2]] == dtcm_addr_o[BUS_ADDR_WIDTH-1:2]))
                perf_hot_store_update_q <= perf_hot_store_update_q + 1'b1;
`endif

            if (mmio_wb_valid_q && !load_s2_valid_q) begin
                mmio_wb_valid_q <= 1'b0;
            end

            if (mmio_wait_q) begin
                mmio_wait_q       <= 1'b0;
                mmio_wb_valid_q   <= 1'b1;
                mmio_wb_result_q  <= mmio_load_result;
                mmio_wb_rd_addr_q <= mmio_rd_addr_q;
                mmio_wb_producer_id_q <= mmio_producer_id_q;
                mmio_wb_producer_tracked_q <= mmio_producer_tracked_q;
            end

            if (pending_store_dtcm_fire | pending_store_mmio_fire) begin
                pending_store_valid_q <= 1'b0;
            end

            if (store_pending_capture) begin
                pending_store_valid_q <= 1'b1;
                pending_store_is_dtcm_q <= request_is_dtcm;
                pending_store_addr_q <= id_lsu_i.addr;
                pending_store_mask_q <= id_lsu_i.store_mask;
                pending_store_addr_index_q <= mem_addr_index;
                pending_store_operator_lsu_q <= operator_lsu_i;
                pending_store_rs2_raddr_q <= id_lsu_i.rs2_raddr;
            end

            if (mmio_req_valid_q) begin
                mmio_req_valid_q <= 1'b0;
                if (mmio_is_load_q) begin
                    mmio_wait_q <= 1'b1;
                end
            end

            if (pending_store_mmio_fire) begin
                mmio_req_valid_q    <= 1'b1;
                mmio_is_load_q      <= 1'b0;
                mmio_is_store_q     <= 1'b1;
                mmio_addr_q         <= pending_store_addr_q;
                mmio_wdata_q        <= pending_store_wdata;
                mmio_wmask_q        <= pending_store_mask_q;
                mmio_addr_index_q   <= pending_store_addr_index_q;
                mmio_operator_lsu_q <= pending_store_operator_lsu_q;
                mmio_rd_addr_q      <= '0;
                mmio_producer_id_q  <= 1'b0;
                mmio_producer_tracked_q <= 1'b0;
            end

            if (mmio_fire) begin
                mmio_req_valid_q    <= 1'b1;
                mmio_is_load_q      <= is_load;
                mmio_is_store_q     <= is_store;
                mmio_addr_q         <= id_lsu_i.addr;
                mmio_wdata_q        <= store_wdata;
                mmio_wmask_q        <= store_wmask;
                mmio_addr_index_q   <= mem_addr_index;
                mmio_operator_lsu_q <= operator_lsu_i;
                mmio_rd_addr_q      <= id_rd_waddr_i;
                mmio_producer_id_q  <= id_producer_id_i;
                mmio_producer_tracked_q <= id_producer_tracked_i;
            end
        end
    end

    end

endmodule
