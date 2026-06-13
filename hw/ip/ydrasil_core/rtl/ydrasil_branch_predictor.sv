module ydrasil_branch_predictor
import ydrasil_pkg::*;
#(
    parameter int BP_ENTRIES  = 0,
    parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
    parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES
) (
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc_i,
    output wire                            predict_hit_o,
    output wire                            predict_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_target_o,
    output wire [1:0]                      predict_counter_o,

    input  wire                            train_valid_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] train_pc_i,
    input  wire                            train_taken_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] train_target_i,
    input  wire [1:0]                      train_counter_i,

    input  wire                            invalidate_i
);

    localparam int BTB_INDEX_WIDTH = ydrasil_pkg::log_addr_width(BTB_ENTRIES);
    localparam int BHT_INDEX_WIDTH = ydrasil_pkg::log_addr_width(BHT_ENTRIES);
    localparam int BTB_TAG_WIDTH = ydrasil_pkg::INST_ADDR_WIDTH - BTB_INDEX_WIDTH - 2;
    localparam int BTB_DATA_WIDTH = BTB_TAG_WIDTH + ydrasil_pkg::INST_ADDR_WIDTH;

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

    logic btb_valid_q [0:BTB_ENTRIES-1];
    logic bht_valid_q [0:BHT_ENTRIES-1];

    wire [BTB_INDEX_WIDTH-1:0] predict_btb_index;
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index;
    wire [BTB_TAG_WIDTH-1:0]   predict_btb_tag;
    wire [BTB_INDEX_WIDTH-1:0] train_btb_index;
    wire [BHT_INDEX_WIDTH-1:0] train_bht_index;
    wire [BTB_TAG_WIDTH-1:0]   train_btb_tag;

    logic [BTB_TAG_WIDTH-1:0]   predict_btb_tag_q;
    logic                       predict_btb_valid_q;
    logic                       predict_bht_valid_q;

    wire [BTB_DATA_WIDTH-1:0] btb_rdata;
    wire [BTB_DATA_WIDTH-1:0] btb_wdata;
    wire [BTB_TAG_WIDTH-1:0] btb_rtag;
    wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] btb_rtarget;
    wire [1:0] bht_rdata;
    wire [1:0] bht_wdata;
    wire [1:0] bht_counter;
    wire       train_fire;
    wire       btb_hit;

    function automatic logic [1:0] next_counter(
        input logic [1:0] counter_i,
        input logic       taken_i
    );
        if (taken_i) begin
            next_counter = (counter_i == 2'b11) ? counter_i : (counter_i + 2'b01);
        end else begin
            next_counter = (counter_i == 2'b00) ? counter_i : (counter_i - 2'b01);
        end
    endfunction

    assign predict_btb_index = predict_pc_i[BTB_INDEX_WIDTH+1:2];
    assign predict_bht_index = predict_pc_i[BHT_INDEX_WIDTH+1:2];
    assign predict_btb_tag   = predict_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign train_btb_index   = train_pc_i[BTB_INDEX_WIDTH+1:2];
    assign train_bht_index   = train_pc_i[BHT_INDEX_WIDTH+1:2];
    assign train_btb_tag     = train_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];

    assign btb_wdata = {train_btb_tag, train_target_i};
    assign bht_wdata = next_counter(train_counter_i, train_taken_i);
    assign {btb_rtag, btb_rtarget} = btb_rdata;
    assign train_fire = train_valid_i && !invalidate_i;

    ydrmem_1r1w_ram #(
        .DEPTH(BTB_ENTRIES),
        .DATA_WIDTH(BTB_DATA_WIDTH),
        .ADDR_WIDTH(BTB_INDEX_WIDTH)
    ) u_btb_ram (
        .clk     (clk),
        .ren_i   (1'b1),
        .raddr_i (predict_btb_index),
        .rdata_o (btb_rdata),
        .wen_i   (train_fire),
        .waddr_i (train_btb_index),
        .wdata_i (btb_wdata)
    );

    ydrmem_1r1w_ram #(
        .DEPTH(BHT_ENTRIES),
        .DATA_WIDTH(2),
        .ADDR_WIDTH(BHT_INDEX_WIDTH)
    ) u_bht_ram (
        .clk     (clk),
        .ren_i   (1'b1),
        .raddr_i (predict_bht_index),
        .rdata_o (bht_rdata),
        .wen_i   (train_fire),
        .waddr_i (train_bht_index),
        .wdata_i (bht_wdata)
    );

    integer i;
    integer j;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            predict_btb_tag_q   <= '0;
            predict_btb_valid_q <= 1'b0;
            predict_bht_valid_q <= 1'b0;
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb_valid_q[i] <= 1'b0;
            end
            for (j = 0; j < BHT_ENTRIES; j = j + 1) begin
                bht_valid_q[j] <= 1'b0;
            end
        end else if (invalidate_i) begin
            predict_btb_tag_q   <= '0;
            predict_btb_valid_q <= 1'b0;
            predict_bht_valid_q <= 1'b0;
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb_valid_q[i] <= 1'b0;
            end
            for (j = 0; j < BHT_ENTRIES; j = j + 1) begin
                bht_valid_q[j] <= 1'b0;
            end
        end else begin
            predict_btb_tag_q   <= predict_btb_tag;
            predict_btb_valid_q <= btb_valid_q[predict_btb_index];
            predict_bht_valid_q <= bht_valid_q[predict_bht_index];

            if (train_fire) begin
                btb_valid_q[train_btb_index] <= 1'b1;
                bht_valid_q[train_bht_index] <= 1'b1;
            end
        end
    end

    assign btb_hit           = predict_btb_valid_q && (btb_rtag == predict_btb_tag_q);
    assign bht_counter       = predict_bht_valid_q ? bht_rdata : 2'b01;
    assign predict_hit_o     = !invalidate_i && btb_hit;
    assign predict_counter_o = !invalidate_i ? bht_counter : 2'b01;
    assign predict_taken_o   = predict_hit_o && predict_counter_o[1];
    assign predict_target_o  = predict_hit_o ? btb_rtarget : '0;

endmodule
