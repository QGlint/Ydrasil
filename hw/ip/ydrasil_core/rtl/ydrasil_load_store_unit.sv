
// 地址生成单元 - 处理内存访问和相关寄存器操作
module ydrasil_load_store_unit 
import ydrasil_pkg::*;
(
    input wire clk,  // 时钟输入
    input wire rst_n,

    input wire [ydrasil_pkg::BUS_ADDR_WIDTH-1:0]       ex_lsu_mem_addr_i,
    input wire [ 4:0]                      id_rd_waddr_i,
    input producer_id_t                    id_producer_id_i,
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
    output wire                            lsu_fast_load_o,


    // 寄存器写回接口
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]     lsu_wb_result_o,
    output wire                            lsu_rf_rd_wen_o,
    output wire [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     lsu_rf_rd_waddr_o
    ,output producer_id_t                   lsu_producer_id_o
    ,output wire                            lsu_producer_tracked_o
);
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
    producer_id_t                               mmio_producer_id_q;
    reg                                         mmio_producer_tracked_q;
    reg        mmio_wb_valid_q;
    reg [ydrasil_pkg::REGS_DATA_WIDTH-1:0]     mmio_wb_result_q;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     mmio_wb_rd_addr_q;
    producer_id_t                               mmio_wb_producer_id_q;
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
    producer_id_t                               load_s1_producer_id_q;
    reg                                         load_s1_producer_tracked_q;
    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]   load_s1_operator_lsu_q;
    reg [1:0]                                  load_s1_addr_index_q;
    reg [ydrasil_pkg::BUS_ADDR_WIDTH-1:2]      load_s1_word_addr_q;

    reg        load_s2_valid_q;
    reg [ydrasil_pkg::REGS_ADDR_WIDTH-1:0]     load_s2_rd_addr_q;
    producer_id_t                               load_s2_producer_id_q;
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
    assign dtcm_accept = request_valid & request_is_dtcm &
        !mmio_wb_valid_q & !pending_store_valid_q;
    always_comb begin
        hot_lookup_idx = id_lsu_i.addr[HOT_INDEX_WIDTH+1:2];
        hot_lookup_hit = hot_valid_q[hot_lookup_idx] &&
            (hot_addr_q[hot_lookup_idx] == id_lsu_i.addr[BUS_ADDR_WIDTH-1:2]);
        hot_lookup_data = hot_data_q[hot_lookup_idx];
    end

    localparam bit HOT_BYPASS_ENABLE = 1'b1;
    assign hot_load_req =
        dtcm_accept & is_load & hot_lookup_hit & HOT_BYPASS_ENABLE &
        !load_s1_valid_q;
    assign lsu_fast_load_o = hot_load_req;
    assign dtcm_array_load_req =
        dtcm_accept & is_load & !(hot_lookup_hit & HOT_BYPASS_ENABLE & !load_s1_valid_q);
    assign dtcm_load_req = hot_load_req | dtcm_array_load_req;

    assign mmio_accept = request_valid & !request_is_dtcm & !mmio_busy & !pending_store_valid_q;
    assign mmio_fire = mmio_accept & (is_load | id_lsu_i.store_data_valid);

    assign store_wmask = id_lsu_i.store_mask;
    assign store_wdata = align_store_data(operator_lsu_i,
                                          mem_addr_index,
                                          id_lsu_i.store_data);
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
            mmio_producer_id_q     <= '0;
            mmio_producer_tracked_q <= 1'b0;
            mmio_wb_valid_q        <= 1'b0;
            mmio_wb_result_q       <= '0;
            mmio_wb_rd_addr_q      <= '0;
            mmio_wb_producer_id_q  <= '0;
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
            load_s1_producer_id_q  <= '0;
            load_s1_producer_tracked_q <= 1'b0;
            load_s1_operator_lsu_q <= '0;
            load_s1_addr_index_q   <= '0;
            load_s1_word_addr_q    <= '0;
            load_s2_valid_q        <= 1'b0;
            load_s2_rd_addr_q      <= '0;
            load_s2_producer_id_q  <= '0;
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
                    (hot_addr_q[dtcm_addr_o[HOT_INDEX_WIDTH+1:2]] == dtcm_addr_o[BUS_ADDR_WIDTH-1:2]))
                    hot_valid_q[dtcm_addr_o[HOT_INDEX_WIDTH+1:2]] <= 1'b0;
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
                mmio_producer_id_q  <= '0;
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

endmodule
