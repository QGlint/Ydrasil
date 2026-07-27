module ydrasil_branch_predictor
import ydrasil_pkg::*;
#(
    parameter int BP_ENTRIES  = 0,
    parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
    parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES,
    parameter bit USE_GSHARE  = 1'b0
) (
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc_i,
    output wire                            predict_hit_o,
    output wire                            predict_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_target_o,
    output wire [1:0]                      predict_counter_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_bht_index_o,
    input  wire                            predict0_spec_valid_i,
    input  wire                            predict0_spec_conditional_i,
    input  wire                            predict0_spec_taken_i,

    // The second lane shares this predictor's GHR and training state.  The
    // two read ports are kept inside one predictor instance so lane1 cannot
    // observe an independent history stream.
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc1_i,
    output wire                            predict1_hit_o,
    output wire                            predict1_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict1_target_o,
    output wire [1:0]                      predict1_counter_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict1_bht_index_o,

    input  ydrasil_bp_train_pkt_t          train_i,

    input  wire                            invalidate_i
);

    localparam int BTB_INDEX_WIDTH = (BTB_ENTRIES > 1) ? $clog2(BTB_ENTRIES) : 1;
    localparam int BHT_INDEX_WIDTH = (BHT_ENTRIES > 1) ? $clog2(BHT_ENTRIES) : 1;
    localparam int GHR_WIDTH = (BHT_INDEX_WIDTH > 4) ? 4 : BHT_INDEX_WIDTH;
    localparam int BTB_TAG_WIDTH = ydrasil_pkg::INST_ADDR_WIDTH - BTB_INDEX_WIDTH - 2;
    localparam int BTB_DATA_WIDTH = BTB_TAG_WIDTH + ydrasil_pkg::INST_ADDR_WIDTH;
    localparam int BTB_MEM_DATA_WIDTH = ((BTB_DATA_WIDTH + 7) / 8) * 8;
    localparam int BHT_MEM_DATA_WIDTH = 8;

    if ((BTB_ENTRIES < 2) || ((BTB_ENTRIES & (BTB_ENTRIES - 1)) != 0)) begin : g_bad_btb_entries
        initial begin
            $fatal(1, "BTB_ENTRIES must be a power of two and at least 2");
        end
    end

    if ((BHT_ENTRIES < 2) || ((BHT_ENTRIES & (BHT_ENTRIES - 1)) != 0)) begin : g_bad_bht_entries
        initial begin
            $fatal(1, "BHT_ENTRIES must be a power of two and at least 2");
        end
    end

    if (BTB_TAG_WIDTH < 1) begin : g_bad_btb_tag_width
        initial begin
            $fatal(1, "BTB_ENTRIES leaves no BTB tag bits");
        end
    end

    logic [BTB_ENTRIES-1:0] btb_valid_q;
    logic [BHT_ENTRIES-1:0] bht_valid_q;
    logic [GHR_WIDTH-1:0] ghr_q;

    wire [BTB_INDEX_WIDTH-1:0] predict_btb_index;
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index;
    wire [BHT_INDEX_WIDTH-1:0] predict_pc_bht_index;
    wire [BTB_TAG_WIDTH-1:0]   predict_btb_tag;
    wire [BTB_INDEX_WIDTH-1:0] train_btb_index;
    wire [BHT_INDEX_WIDTH-1:0] train_bht_index;
    wire [BHT_INDEX_WIDTH-1:0] ghr_index_mask;
    wire [BTB_TAG_WIDTH-1:0]   train_btb_tag;

    logic [BTB_TAG_WIDTH-1:0]   predict_btb_tag_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index_q;
    logic                       predict_btb_valid_q;
    logic                       predict_bht_valid_q;

    wire [BTB_DATA_WIDTH-1:0] btb_rdata;
    wire [BTB_DATA_WIDTH-1:0] btb_rdata1;
    wire [BTB_DATA_WIDTH-1:0] btb_wdata;
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_mem_rdata;
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_mem_rdata1;
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_mem_wdata;
    wire [BTB_TAG_WIDTH-1:0] btb_rtag;
    wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] btb_rtarget;
    wire [1:0] bht_rdata;
    wire [1:0] bht_rdata1;
    wire [1:0] bht_wdata;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_mem_rdata;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_mem_rdata1;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_mem_wdata;
    wire [1:0] bht_next_counter;
    wire [1:0] bht_counter;
    wire       train_fire;
    wire       conditional_train_fire;
    wire       btb_hit;
    wire       btb_hit1;
    wire [BTB_INDEX_WIDTH-1:0] predict_btb_index1;
    wire [BHT_INDEX_WIDTH-1:0] predict_pc_bht_index1;
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index1;
    wire [BTB_TAG_WIDTH-1:0] predict_btb_tag1;
    logic [BTB_TAG_WIDTH-1:0] predict_btb_tag1_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index1_q;
    logic predict_btb_valid1_q;
    logic predict_bht_valid1_q;
    wire [GHR_WIDTH-1:0] lane1_ghr =
        (predict0_spec_valid_i && predict0_spec_conditional_i) ?
        {ghr_q[GHR_WIDTH-2:0], predict0_spec_taken_i} : ghr_q;
    wire [BHT_INDEX_WIDTH-1:0] lane1_ghr_index_mask = USE_GSHARE ?
        {{(BHT_INDEX_WIDTH-GHR_WIDTH){1'b0}}, lane1_ghr} : '0;

    assign predict_btb_index = predict_pc_i[BTB_INDEX_WIDTH+1:2];
    assign predict_pc_bht_index = predict_pc_i[BHT_INDEX_WIDTH+1:2];
    assign ghr_index_mask = USE_GSHARE ? {{(BHT_INDEX_WIDTH-GHR_WIDTH){1'b0}}, ghr_q} : '0;
    assign predict_bht_index = predict_pc_bht_index ^ ghr_index_mask;
    assign predict_btb_tag   = predict_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign predict_btb_index1 = predict_pc1_i[BTB_INDEX_WIDTH+1:2];
    assign predict_pc_bht_index1 = predict_pc1_i[BHT_INDEX_WIDTH+1:2];
    assign predict_bht_index1 = predict_pc_bht_index1 ^ lane1_ghr_index_mask;
    assign predict_btb_tag1 = predict_pc1_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign train_btb_index   = train_i.pc[BTB_INDEX_WIDTH+1:2];
    assign train_bht_index   = train_i.bht_index[BHT_INDEX_WIDTH-1:0];
    assign train_btb_tag     = train_i.pc[ydrasil_pkg::INST_ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign predict_bht_index_o = {{(ydrasil_pkg::INST_ADDR_WIDTH-BHT_INDEX_WIDTH){1'b0}}, predict_bht_index_q};

    assign bht_next_counter = train_i.taken ?
        ((train_i.counter == 2'b11) ? train_i.counter : (train_i.counter + 2'b01)) :
        ((train_i.counter == 2'b00) ? train_i.counter : (train_i.counter - 2'b01));
    assign btb_wdata = {train_btb_tag, train_i.target};
    assign bht_wdata = bht_next_counter;
    assign btb_mem_wdata = {{(BTB_MEM_DATA_WIDTH-BTB_DATA_WIDTH){1'b0}}, btb_wdata};
    assign btb_rdata = btb_mem_rdata[BTB_DATA_WIDTH-1:0];
    assign btb_rdata1 = btb_mem_rdata1[BTB_DATA_WIDTH-1:0];
    // Physical zero represents logical weak-not-taken.  This preserves the
    // BHT power-on state in both generic simulation RAM and zero-initialized
    // FPGA BRAM without a side valid array or reset-time clear loop.
    assign bht_mem_wdata = {{(BHT_MEM_DATA_WIDTH-2){1'b0}},
        (bht_wdata ^ 2'b01)};
    assign bht_rdata = bht_mem_rdata[1:0] ^ 2'b01;
    assign bht_rdata1 = bht_mem_rdata1[1:0] ^ 2'b01;
    assign {btb_rtag, btb_rtarget} = btb_rdata;
    assign train_fire = train_i.valid && !invalidate_i;
    assign conditional_train_fire = train_fire;

    ydrmem_1r1w_ram #(
        .DEPTH(BTB_ENTRIES),
        .DATA_WIDTH(BTB_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BTB_INDEX_WIDTH),
        .INIT_VALUE('0)
    ) u_btb_ram (
        .clk     (clk),
        .ren_i   (1'b1),
        .raddr_i (predict_btb_index),
        .rdata_o (btb_mem_rdata),
        .wen_i   (train_fire),
        .waddr_i (train_btb_index),
        .wdata_i (btb_mem_wdata)
    );

    ydrmem_1r1w_ram #(
        .DEPTH(BTB_ENTRIES), .DATA_WIDTH(BTB_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BTB_INDEX_WIDTH), .INIT_VALUE('0)
    ) u_btb_ram_lane1 (
        .clk(clk), .ren_i(1'b1), .raddr_i(predict_btb_index1),
        .rdata_o(btb_mem_rdata1), .wen_i(train_fire),
        .waddr_i(train_btb_index), .wdata_i(btb_mem_wdata)
    );

    ydrmem_1r1w_ram #(
        .DEPTH(BHT_ENTRIES),
        .DATA_WIDTH(BHT_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BHT_INDEX_WIDTH),
        .INIT_VALUE('0)
    ) u_bht_ram (
        .clk     (clk),
        .ren_i   (1'b1),
        .raddr_i (predict_bht_index),
        .rdata_o (bht_mem_rdata),
        .wen_i   (conditional_train_fire),
        .waddr_i (train_bht_index),
        .wdata_i (bht_mem_wdata)
    );

    ydrmem_1r1w_ram #(
        .DEPTH(BHT_ENTRIES), .DATA_WIDTH(BHT_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BHT_INDEX_WIDTH), .INIT_VALUE('0)
    ) u_bht_ram_lane1 (
        .clk(clk), .ren_i(1'b1), .raddr_i(predict_bht_index1),
        .rdata_o(bht_mem_rdata1), .wen_i(conditional_train_fire),
        .waddr_i(train_bht_index), .wdata_i(bht_mem_wdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            predict_btb_tag_q   <= '0;
            predict_bht_index_q <= '0;
            predict_btb_valid_q <= 1'b0;
            predict_bht_valid_q <= 1'b0;
            predict_btb_tag1_q  <= '0;
            predict_bht_index1_q <= '0;
            predict_btb_valid1_q <= 1'b0;
            predict_bht_valid1_q <= 1'b0;
            btb_valid_q         <= '0;
            bht_valid_q         <= '0;
            ghr_q               <= '0;
        end else if (invalidate_i) begin
            predict_btb_tag_q   <= '0;
            predict_bht_index_q <= '0;
            predict_btb_valid_q <= 1'b0;
            predict_bht_valid_q <= 1'b0;
            predict_btb_tag1_q  <= '0;
            predict_bht_index1_q <= '0;
            predict_btb_valid1_q <= 1'b0;
            predict_bht_valid1_q <= 1'b0;
            btb_valid_q         <= '0;
            bht_valid_q         <= '0;
            ghr_q               <= '0;
        end else begin
            predict_btb_tag_q   <= predict_btb_tag;
            predict_bht_index_q <= predict_bht_index;
            predict_btb_valid_q <= btb_valid_q[predict_btb_index];
            predict_bht_valid_q <= bht_valid_q[predict_bht_index];
            predict_btb_tag1_q  <= predict_btb_tag1;
            predict_bht_index1_q <= predict_bht_index1;
            predict_btb_valid1_q <= btb_valid_q[predict_btb_index1];
            predict_bht_valid1_q <= bht_valid_q[predict_bht_index1];

            if (train_fire) begin
                btb_valid_q[train_btb_index] <= 1'b1;
                bht_valid_q[train_bht_index] <= 1'b1;
            end
            if (train_fire && train_i.conditional) begin
                ghr_q <= {ghr_q[GHR_WIDTH-2:0], train_i.taken};
            end
        end
    end

    assign btb_hit           = predict_btb_valid_q &&
        (btb_rtag == predict_btb_tag_q);
    wire [BTB_TAG_WIDTH-1:0] btb_rtag1;
    wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] btb_rtarget1;
    assign {btb_rtag1, btb_rtarget1} = btb_rdata1;
    assign btb_hit1          = predict_btb_valid1_q &&
        (btb_rtag1 == predict_btb_tag1_q);
    assign bht_counter       = predict_bht_valid_q ? bht_rdata : 2'b01;
    assign predict_hit_o     = !invalidate_i && btb_hit;
    assign predict_counter_o = !invalidate_i ? bht_counter : 2'b01;
    assign predict_taken_o   = predict_hit_o && predict_counter_o[1];
    assign predict_target_o  = btb_rtarget;
    assign predict1_hit_o = !invalidate_i && btb_hit1;
    assign predict1_counter_o = !invalidate_i && predict_bht_valid1_q ?
        bht_rdata1 : 2'b01;
    assign predict1_taken_o = predict1_hit_o && predict1_counter_o[1];
    assign predict1_target_o = btb_rtarget1;
    assign predict1_bht_index_o =
        {{(ydrasil_pkg::INST_ADDR_WIDTH-BHT_INDEX_WIDTH){1'b0}},
         predict_bht_index1_q};

endmodule
